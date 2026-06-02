"""
Gmail client: send emails via Gmail API, poll GCP Pub/Sub for push notifications,
route replies to per-run asyncio queues.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import re
from email.mime.text import MIMEText
from typing import Any

import structlog
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google.oauth2.service_account import Credentials as SACredentials
from googleapiclient.discovery import build
from google.cloud import pubsub_v1

from agent.email import templates as _templates

log = structlog.get_logger()

RUN_ID_PATTERN = re.compile(r"\[LZ-([A-Za-z0-9_-]+)\]")
# Tokens that advance the state machine when found in a reply body
CONTROL_TOKENS = {"APPROVE", "REJECT", "RECHECK", "SKIP", "ABORT", "RESUME"}
# Delimiter between metadata-prefix header and email body when parsing replies
HEADER_DELIMITER = "──"


def _build_gmail_service():
    creds_json = os.environ.get("GMAIL_SERVICE_ACCOUNT_JSON")
    delegated = os.environ["GMAIL_SENDER_EMAIL"]
    if creds_json:
        sa_creds = SACredentials.from_service_account_info(
            json.loads(creds_json),
            scopes=["https://www.googleapis.com/auth/gmail.send",
                    "https://www.googleapis.com/auth/gmail.readonly",
                    "https://www.googleapis.com/auth/gmail.modify"],
        )
        creds = sa_creds.with_subject(delegated)
    else:
        # OAuth2 token file path (dev/local)
        token_file = os.environ.get("GMAIL_TOKEN_FILE", "/secrets/gmail_token.json")
        creds = Credentials.from_authorized_user_file(
            token_file,
            scopes=["https://www.googleapis.com/auth/gmail.send",
                    "https://www.googleapis.com/auth/gmail.readonly"],
        )
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())

    return build("gmail", "v1", credentials=creds, cache_discovery=False)


class GmailClient:
    def __init__(self) -> None:
        self._service = _build_gmail_service()
        self.sender = os.environ["GMAIL_SENDER_EMAIL"]
        self._pubsub_subscription = os.environ.get("GMAIL_PUBSUB_SUBSCRIPTION", "")
        # run_id → asyncio Queue for email replies
        self._run_queues: dict[str, asyncio.Queue[str]] = {}
        # run_id → asyncio Queue for LLD attachment emails (new runs)
        self._incoming_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self.templates = _templates

    def get_reply_queue(self, run_id: str) -> asyncio.Queue[str]:
        if run_id not in self._run_queues:
            self._run_queues[run_id] = asyncio.Queue()
        return self._run_queues[run_id]

    @property
    def incoming(self) -> asyncio.Queue[dict[str, Any]]:
        return self._incoming_queue

    async def send(self, to: str, subject: str, body: str) -> str:
        msg = MIMEText(body, "plain", "utf-8")
        msg["to"] = to
        msg["from"] = self.sender
        msg["subject"] = subject
        raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: self._service.users()
            .messages()
            .send(userId="me", body={"raw": raw})
            .execute(),
        )
        log.info("email_sent", to=to, subject=subject, message_id=result.get("id"))
        return result["id"]

    def _parse_message(self, message_id: str) -> dict[str, Any] | None:
        """Fetch a Gmail message and return {run_id, subject, body, attachments}."""
        msg = (
            self._service.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute()
        )
        headers = {h["name"]: h["value"] for h in msg["payload"]["headers"]}
        subject = headers.get("Subject", "")
        sender = headers.get("From", "")

        # Extract run_id from subject
        m = RUN_ID_PATTERN.search(subject)
        run_id = m.group(1) if m else None

        # Extract plain text body
        body = _extract_body(msg["payload"])

        # Extract attachments (Excel files)
        attachments = _extract_attachments(msg["payload"], message_id, self._service)

        return {
            "message_id": message_id,
            "run_id": run_id,
            "subject": subject,
            "sender": sender,
            "body": body,
            "attachments": attachments,
        }

    def _route_message(self, parsed: dict[str, Any]) -> None:
        run_id = parsed["run_id"]
        body = parsed["body"] or ""
        attachments = parsed.get("attachments", [])

        if run_id and run_id in self._run_queues:
            # Route reply to the existing run's queue
            self._run_queues[run_id].put_nowait(body)
            log.info("reply_routed", run_id=run_id)
        elif attachments or not run_id:
            # New LLD submission (no run_id or has Excel attachment)
            self._incoming_queue.put_nowait(parsed)
            log.info("new_lld_queued", sender=parsed["sender"])

    async def poll_pubsub_forever(self) -> None:
        """Background task: pull GCP Pub/Sub notifications and route to queues."""
        if not self._pubsub_subscription:
            log.warning("pubsub_not_configured_skipping_poll")
            return

        subscriber = pubsub_v1.SubscriberClient()
        log.info("pubsub_polling_started", subscription=self._pubsub_subscription)

        loop = asyncio.get_event_loop()
        while True:
            try:
                response = await loop.run_in_executor(
                    None,
                    lambda: subscriber.pull(
                        subscription=self._pubsub_subscription,
                        max_messages=10,
                    ),
                )
                ack_ids = []
                for received in response.received_messages:
                    ack_ids.append(received.ack_id)
                    data = json.loads(received.message.data.decode())
                    # Gmail push notification carries emailAddress + historyId
                    history_id = data.get("historyId")
                    if history_id:
                        await self._process_history(int(history_id))

                if ack_ids:
                    await loop.run_in_executor(
                        None,
                        lambda: subscriber.acknowledge(
                            subscription=self._pubsub_subscription,
                            ack_ids=ack_ids,
                        ),
                    )
            except Exception as exc:
                log.error("pubsub_poll_error", error=str(exc))

            await asyncio.sleep(5)

    async def _process_history(self, history_id: int) -> None:
        loop = asyncio.get_event_loop()
        history = await loop.run_in_executor(
            None,
            lambda: self._service.users()
            .history()
            .list(userId="me", startHistoryId=history_id - 1, historyTypes=["messageAdded"])
            .execute(),
        )
        for record in history.get("history", []):
            for added in record.get("messagesAdded", []):
                msg_id = added["message"]["id"]
                try:
                    parsed = await loop.run_in_executor(
                        None, lambda: self._parse_message(msg_id)
                    )
                    if parsed:
                        self._route_message(parsed)
                except Exception as exc:
                    log.error("message_parse_error", message_id=msg_id, error=str(exc))

    async def setup_gmail_watch(self) -> None:
        """Configure Gmail API push notifications to Pub/Sub topic (run once)."""
        topic = os.environ.get("GMAIL_PUBSUB_TOPIC", "")
        if not topic:
            log.warning("gmail_watch_not_configured")
            return
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: self._service.users()
            .watch(userId="me", body={"topicName": topic, "labelIds": ["INBOX"]})
            .execute(),
        )
        log.info("gmail_watch_set_up", expiration=result.get("expiration"))


# ── helpers ──────────────────────────────────────────────────────────────────

def _extract_body(payload: dict) -> str:
    """Recursively extract plain-text body from a Gmail message payload."""
    mime_type = payload.get("mimeType", "")
    if mime_type == "text/plain":
        data = payload.get("body", {}).get("data", "")
        return base64.urlsafe_b64decode(data + "==").decode("utf-8", errors="replace")
    if mime_type.startswith("multipart/"):
        for part in payload.get("parts", []):
            text = _extract_body(part)
            if text:
                return text
    return ""


def _extract_attachments(payload: dict, message_id: str, service) -> list[dict]:
    """Return list of {filename, data} for Excel attachments."""
    attachments = []
    for part in payload.get("parts", []):
        filename = part.get("filename", "")
        if filename.endswith(".xlsx") or filename.endswith(".json"):
            attachment_id = part.get("body", {}).get("attachmentId")
            if attachment_id:
                att = (
                    service.users()
                    .messages()
                    .attachments()
                    .get(userId="me", messageId=message_id, id=attachment_id)
                    .execute()
                )
                data = base64.urlsafe_b64decode(att["data"] + "==")
                attachments.append({"filename": filename, "data": data})
    return attachments
