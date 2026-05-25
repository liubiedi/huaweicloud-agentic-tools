from __future__ import annotations

import json
import os
from typing import Any

import boto3
import structlog
from botocore.exceptions import ClientError

from agent.models.run_state import RunState

log = structlog.get_logger()

_STATE_PREFIX = "agent-runs"
_EVENTS_PREFIX = "agent-run-events"


def _client() -> Any:
    region = os.environ["TF_STATE_REGION"]
    return boto3.client(
        "s3",
        endpoint_url=f"https://obs.{region}.myhuaweicloud.com",
        aws_access_key_id=os.environ["HWC_ACCESS_KEY"],
        aws_secret_access_key=os.environ["HWC_SECRET_KEY"],
        region_name=region,
    )


def _bucket() -> str:
    return os.environ["TF_STATE_BUCKET"]


def save_state(state: RunState) -> None:
    key = f"{_STATE_PREFIX}/{state.run_id}/state.json"
    body = state.model_dump_json(indent=2).encode()
    _client().put_object(Bucket=_bucket(), Key=key, Body=body, ContentType="application/json")
    log.info("state_saved", run_id=state.run_id, step=state.step, key=key)


def load_state(run_id: str) -> RunState | None:
    key = f"{_STATE_PREFIX}/{run_id}/state.json"
    try:
        resp = _client().get_object(Bucket=_bucket(), Key=key)
        data = json.loads(resp["Body"].read())
        return RunState.model_validate(data)
    except ClientError as exc:
        if exc.response["Error"]["Code"] in ("NoSuchKey", "404"):
            return None
        raise


def list_runs() -> list[str]:
    paginator = _client().get_paginator("list_objects_v2")
    run_ids: list[str] = []
    for page in paginator.paginate(Bucket=_bucket(), Prefix=f"{_STATE_PREFIX}/", Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            prefix = cp["Prefix"]
            run_id = prefix.rstrip("/").split("/")[-1]
            run_ids.append(run_id)
    return run_ids


def save_artifact(run_id: str, filename: str, content: str) -> str:
    key = f"{_STATE_PREFIX}/{run_id}/artifacts/{filename}"
    _client().put_object(Bucket=_bucket(), Key=key, Body=content.encode(), ContentType="text/plain")
    return key


def poll_cicd_events(run_id: str, after_seq: int = 0) -> list[dict]:
    """Read CI/CD event files dropped by runner when webhook is unreachable."""
    prefix = f"{_EVENTS_PREFIX}/{run_id}/"
    try:
        resp = _client().list_objects_v2(Bucket=_bucket(), Prefix=prefix)
    except ClientError:
        return []

    events: list[dict] = []
    for obj in resp.get("Contents", []):
        key = obj["Key"]
        seq_str = key.rstrip(".json").split("/")[-1]
        try:
            seq = int(seq_str)
        except ValueError:
            continue
        if seq > after_seq:
            body = _client().get_object(Bucket=_bucket(), Key=key)["Body"].read()
            events.append({"seq": seq, "event": json.loads(body)})

    return sorted(events, key=lambda e: e["seq"])
