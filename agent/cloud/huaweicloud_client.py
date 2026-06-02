"""
Huawei Cloud API client.
Acquires/refreshes OIDC tokens and wraps key API calls needed by pre-flight checks.
Uses httpx for async HTTP.
"""
from __future__ import annotations

import asyncio
import os
import time
from typing import Any

import httpx
import structlog

log = structlog.get_logger()

_TOKEN_REFRESH_MARGIN = 300  # refresh if token expires in < 5 min


class HuaweiCloudClient:
    def __init__(self) -> None:
        self.region = os.environ.get("TF_STATE_REGION", "cn-east-3")
        self.access_key = os.environ["HWC_ACCESS_KEY"]
        self.secret_key = os.environ["HWC_SECRET_KEY"]
        self._token: str | None = None
        self._token_expires: float = 0.0
        self._http = httpx.AsyncClient(timeout=30.0)

    async def close(self) -> None:
        await self._http.aclose()

    async def _get_token(self) -> str:
        """Acquire or return a cached IAM token (AK/SK → project-scoped token)."""
        if self._token and time.time() < self._token_expires - _TOKEN_REFRESH_MARGIN:
            return self._token

        endpoint = f"https://iam.{self.region}.myhuaweicloud.com"
        payload = {
            "auth": {
                "identity": {
                    "methods": ["hw_ak_sk"],
                    "hw_ak_sk": {
                        "ak": {"value": self.access_key},
                        "sk": {"value": self.secret_key},
                    },
                },
                "scope": {"project": {"name": self.region}},
            }
        }
        resp = await self._http.post(f"{endpoint}/v3/auth/tokens", json=payload)
        resp.raise_for_status()
        self._token = resp.headers["X-Subject-Token"]
        # Token is valid for 24h; cache for 23h
        self._token_expires = time.time() + 23 * 3600
        return self._token

    async def _get(self, url: str, **kwargs) -> Any:
        token = await self._get_token()
        resp = await self._http.get(url, headers={"X-Auth-Token": token}, **kwargs)
        resp.raise_for_status()
        return resp.json()

    # ── IAM ──────────────────────────────────────────────────────────────────

    async def get_oidc_providers(self) -> list[dict]:
        """List IAM OIDC identity providers in the master account."""
        data = await self._get(
            f"https://iam.{self.region}.myhuaweicloud.com/v3/OS-FEDERATION/identity_providers"
        )
        return data.get("identity_providers", [])

    async def list_agencies(self) -> list[dict]:
        """List IAM agencies in the master account."""
        domain_id = await self._get_domain_id()
        data = await self._get(
            f"https://iam.{self.region}.myhuaweicloud.com/v3.0/OS-AGENCY/agencies",
            params={"domain_id": domain_id},
        )
        return data.get("agencies", [])

    async def _get_domain_id(self) -> str:
        """Return the master account's domain ID."""
        data = await self._get(
            f"https://iam.{self.region}.myhuaweicloud.com/v3/auth/domains"
        )
        return data["domains"][0]["id"]

    # ── Organizations ────────────────────────────────────────────────────────

    async def get_organization(self) -> dict | None:
        """Return the Organizations root, or None if org not yet enabled."""
        try:
            data = await self._get(
                "https://organizations.myhuaweicloud.com/v1/organizations"
            )
            return data.get("organization")
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (404, 403):
                return None
            raise

    async def list_accounts(self) -> list[dict]:
        data = await self._get(
            "https://organizations.myhuaweicloud.com/v1/organizations/accounts"
        )
        return data.get("accounts", [])

    # ── Quota ────────────────────────────────────────────────────────────────

    async def get_vpc_quota(self) -> dict:
        """Return VPC quota info for the current region."""
        data = await self._get(
            f"https://vpc.{self.region}.myhuaweicloud.com/v3/{await self._get_project_id()}/quotas",
            params={"type": "vpc"},
        )
        return data.get("quotas", {})

    async def _get_project_id(self) -> str:
        data = await self._get(
            f"https://iam.{self.region}.myhuaweicloud.com/v3/auth/projects"
        )
        for p in data.get("projects", []):
            if p.get("name") == self.region:
                return p["id"]
        return data["projects"][0]["id"]

    # ── RGC / Landing Zone ───────────────────────────────────────────────────

    async def get_rgc_landing_zone(self) -> dict | None:
        """Return the RGC landing zone status, or None if not deployed."""
        try:
            data = await self._get(
                f"https://rgc.{self.region}.myhuaweicloud.com/v1/landing-zone"
            )
            return data.get("landing_zone")
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code in (404, 403):
                return None
            raise
