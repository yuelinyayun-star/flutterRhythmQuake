"""WAuth OAuth/OIDC gateway for RhythmQuake native clients."""

from __future__ import annotations

import asyncio
import base64
import html
import json
import logging
import os
import secrets
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from aiohttp import ClientSession, ClientTimeout, web


ISSUER = "https://auth.beecld.com"
AUTHORIZE_URL = f"{ISSUER}/oauth2/authorize"
TOKEN_URL = f"{ISSUER}/oauth2/token"
USERINFO_URL = f"{ISSUER}/oauth2/userinfo"
DEFAULT_CLIENT_ID = "wauth_49ad8dff5251645797672e5d"
DEFAULT_REDIRECT_URI = "https://quake.yuelinrhythm.top/wauth/callback"
DEFAULT_SCOPE = "openid profile email"
BACKGROUND_IMAGE_PATH = Path(__file__).with_name("wauth_background.jpg")


@dataclass
class AuthorizationAttempt:
    state: str
    code_challenge: str
    nonce: str | None
    created_at: float
    code_verifier: str | None = None
    result: dict[str, Any] | None = None
    error: dict[str, Any] | None = None
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)



class WAuthUpstreamError(Exception):
    def __init__(self, *, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


class AuthorizationStore:
    def __init__(self, ttl_seconds: int = 600, max_entries: int = 1000) -> None:
        self.ttl_seconds = ttl_seconds
        self.max_entries = max_entries
        self._items: dict[str, AuthorizationAttempt] = {}

    def create(
        self,
        *,
        state: str,
        code_challenge: str,
        code_verifier: str | None = None,
        nonce: str | None = None,
        now: float | None = None,
    ) -> AuthorizationAttempt:
        current = time.time() if now is None else now
        self.prune(current)
        if len(self._items) >= self.max_entries:
            oldest_state = min(
                self._items,
                key=lambda item_state: self._items[item_state].created_at,
            )
            self._items.pop(oldest_state, None)
        attempt = AuthorizationAttempt(
            state=state,
            code_challenge=code_challenge,
            nonce=nonce,
            created_at=current,
            code_verifier=code_verifier,
        )
        self._items[state] = attempt
        return attempt

    def get(
        self,
        state: str,
        *,
        now: float | None = None,
    ) -> AuthorizationAttempt | None:
        current = time.time() if now is None else now
        attempt = self._items.get(state)
        if attempt is None:
            return None
        if current - attempt.created_at > self.ttl_seconds:
            self._items.pop(state, None)
            return None
        return attempt

    def consume(self, state: str) -> AuthorizationAttempt | None:
        return self._items.pop(state, None)

    def prune(self, now: float | None = None) -> None:
        current = time.time() if now is None else now
        expired = [
            state
            for state, attempt in self._items.items()
            if current - attempt.created_at > self.ttl_seconds
        ]
        for state in expired:
            self._items.pop(state, None)

    @property
    def count(self) -> int:
        self.prune()
        return len(self._items)



def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


def _is_base64url(value: str, *, minimum: int, maximum: int) -> bool:
    if not minimum <= len(value) <= maximum:
        return False
    return all(
        character.isascii()
        and (character.isalnum() or character in {"-", "_", ".", "~"})
        for character in value
    )


def _json_response(payload: dict[str, Any], status: int = 200) -> web.Response:
    return web.json_response(
        payload,
        status=status,
        headers={
            "Cache-Control": "no-store",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
        },
    )


def _callback_page(*, success: bool, detail: str) -> web.Response:
    title = "授权完成" if success else "授权失败"
    status_class = "success" if success else "failure"
    safe_detail = html.escape(detail)
    body = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    * {{
      box-sizing: border-box;
    }}

    body {{
      display: grid;
      place-items: center;
      min-height: 100vh;
      min-height: 100dvh;
      margin: 0;
      padding: 24px;
      background-color: #171717;
      background-image: url("/wauth/assets/background.jpg");
      background-position: center;
      background-repeat: no-repeat;
      background-size: cover;
      color: #f5f5f4;
      font-family: "Segoe UI", "Microsoft YaHei", sans-serif;
    }}

    body::before {{
      content: "";
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.22);
      pointer-events: none;
    }}

    .auth-panel {{
      position: relative;
      width: min(100%, 460px);
      padding: 28px 30px 24px;
      overflow: hidden;
      background: rgba(28, 28, 27, 0.72);
      border: 1px solid rgba(255, 255, 255, 0.16);
      border-radius: 8px;
      box-shadow: 0 18px 48px rgba(0, 0, 0, 0.28);
      backdrop-filter: blur(18px) saturate(120%);
      -webkit-backdrop-filter: blur(18px) saturate(120%);
    }}

    .auth-panel__title {{
      margin: 0;
      font-size: 28px;
      font-weight: 650;
      line-height: 1.25;
      letter-spacing: 0;
    }}

    .auth-panel--success .auth-panel__title {{
      color: #8ee6ad;
    }}

    .auth-panel--failure .auth-panel__title {{
      color: #ff9c96;
    }}

    .auth-panel__detail {{
      margin: 16px 0 0;
      color: #f5f5f4;
      font-size: 16px;
      line-height: 1.7;
      overflow-wrap: anywhere;
    }}

    .auth-panel__return {{
      margin: 22px 0 0;
      padding-top: 18px;
      border-top: 1px solid rgba(255, 255, 255, 0.12);
      color: rgba(245, 245, 244, 0.7);
      font-size: 14px;
      line-height: 1.6;
    }}

    .auth-panel__action {{
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      margin-top: 16px;
      padding: 10px 18px;
      border: 1px solid rgba(255, 255, 255, 0.2);
      border-radius: 6px;
      background: #f5f5f4;
      color: #171717;
      font-size: 15px;
      font-weight: 600;
      line-height: 1.4;
      text-align: center;
      text-decoration: none;
      transition: background-color 120ms ease, transform 120ms ease;
    }}

    .auth-panel__action:hover {{
      background: #ffffff;
    }}

    .auth-panel__action:active {{
      transform: translateY(1px);
    }}

    .auth-panel__action:focus-visible {{
      outline: 2px solid #ffffff;
      outline-offset: 3px;
    }}

    @media (max-width: 520px) {{
      body {{
        padding: 16px;
      }}

      .auth-panel {{
        padding: 24px 22px 20px;
      }}

      .auth-panel__title {{
        font-size: 24px;
      }}
    }}
  </style>
</head>
<body class="callback-page callback-page--{status_class}">
  <main class="auth-panel auth-panel--{status_class}">
    <h1 class="auth-panel__title">{title}</h1>
    <p class="auth-panel__detail">{safe_detail}</p>
    <p class="auth-panel__return">现在可以返回 RhythmQuake。</p>
    <a class="auth-panel__action" href="rhythmquake://wauth-complete" role="button">返回 RhythmQuake</a>
  </main>
</body>
</html>"""
    return web.Response(
        text=body,
        content_type="text/html",
        charset="utf-8",
        status=200 if success else 400,
        headers={
            "Cache-Control": "no-store",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": (
                "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'"
            ),
            "Referrer-Policy": "no-referrer",
        },
    )


async def _exchange_code(
    request: web.Request,
    *,
    code: str,
    code_verifier: str,
) -> dict[str, Any]:
    client_id = request.app["client_id"]
    client_secret = request.app["client_secret"]
    redirect_uri = request.app["redirect_uri"]
    basic = base64.b64encode(
        f"{client_id}:{client_secret}".encode("utf-8")
    ).decode("ascii")
    session: ClientSession = request.app["http_session"]
    async with session.post(
        TOKEN_URL,
        headers={
            "Accept": "application/json",
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "code_verifier": code_verifier,
        },
    ) as response:
        text = await response.text()
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as error:
            raise web.HTTPBadGateway(
                text=f"WAuth token endpoint returned invalid JSON: {error}"
            ) from error
        if response.status < 200 or response.status >= 300:
            message = payload.get("error_description") or payload.get("error")
            raise web.HTTPBadGateway(text=str(message or "WAuth token exchange failed"))
        if not payload.get("access_token"):
            raise web.HTTPBadGateway(text="WAuth response did not contain access_token")
        return payload


async def _fetch_userinfo(request: web.Request, access_token: str) -> dict[str, Any]:
    session: ClientSession = request.app["http_session"]
    async with session.get(
        USERINFO_URL,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {access_token}",
        },
    ) as response:
        text = await response.text()
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            payload = {"raw": text}
        if response.status < 200 or response.status >= 300:
            raise WAuthUpstreamError(
                status=response.status,
                message="WAuth userinfo request failed",
            )
        if not isinstance(payload, dict):
            raise WAuthUpstreamError(
                status=response.status,
                message="WAuth userinfo response was not an object",
            )
        return payload



async def handle_root(request: web.Request) -> web.Response:
    return _json_response(
        {
            "service": "RhythmQuake WAuth gateway",
            "session": "/wauth/session",
            "callback": "/wauth/callback",
            "result": "/wauth/result",
            "health": "/health",
        }
    )


async def handle_health(request: web.Request) -> web.Response:
    store: AuthorizationStore = request.app["store"]
    return _json_response(
        {
            "status": "ok",
            "issuer": ISSUER,
            "redirectUri": request.app["redirect_uri"],
            "pendingAuthorizations": store.count,
            "clientSecretConfigured": bool(request.app["client_secret"]),
        }
    )


async def handle_background_image(request: web.Request) -> web.Response:
    if not BACKGROUND_IMAGE_PATH.is_file():
        raise web.HTTPNotFound()
    return web.FileResponse(
        BACKGROUND_IMAGE_PATH,
        headers={
            "Cache-Control": "public, max-age=86400",
            "X-Content-Type-Options": "nosniff",
        },
    )


async def handle_session(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except (json.JSONDecodeError, TypeError):
        return _json_response({"error": "invalid_json"}, status=400)

    state = str(payload.get("state", ""))
    code_challenge = str(payload.get("code_challenge", ""))
    code_verifier = str(payload.get("code_verifier", ""))
    raw_nonce = payload.get("nonce")
    nonce = str(raw_nonce) if raw_nonce is not None else None

    if not _is_base64url(state, minimum=32, maximum=256):
        return _json_response(
            {"error": "invalid_state", "message": "state must be 32-256 base64url characters"},
            status=400,
        )
    if not _is_base64url(code_challenge, minimum=43, maximum=128):
        return _json_response(
            {
                "error": "invalid_code_challenge",
                "message": "code_challenge must be 43-128 base64url characters",
            },
            status=400,
        )
    if not _is_base64url(code_verifier, minimum=43, maximum=128):
        return _json_response(
            {
                "error": "invalid_code_verifier",
                "message": "code_verifier must be 43-128 base64url characters",
            },
            status=400,
        )
    if nonce is not None and not _is_base64url(nonce, minimum=16, maximum=256):
        return _json_response(
            {"error": "invalid_nonce", "message": "nonce must be 16-256 base64url characters"},
            status=400,
        )

    calculated_challenge = base64.urlsafe_b64encode(
        __import__("hashlib").sha256(code_verifier.encode("ascii")).digest()
    ).decode("ascii").rstrip("=")
    if not secrets.compare_digest(calculated_challenge, code_challenge):
        return _json_response({"error": "pkce_mismatch"}, status=400)

    store: AuthorizationStore = request.app["store"]
    store.create(
        state=state,
        code_challenge=code_challenge,
        code_verifier=code_verifier,
        nonce=nonce,
    )
    parameters = {
        "response_type": "code",
        "client_id": request.app["client_id"],
        "redirect_uri": request.app["redirect_uri"],
        "scope": DEFAULT_SCOPE,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    if nonce:
        parameters["nonce"] = nonce
    return _json_response(
        {
            "status": "ready",
            "authorizationUrl": f"{AUTHORIZE_URL}?{urlencode(parameters)}",
            "expiresIn": store.ttl_seconds,
        }
    )


async def handle_callback(request: web.Request) -> web.Response:
    state = request.query.get("state", "")
    store: AuthorizationStore = request.app["store"]
    attempt = store.get(state)
    if attempt is None:
        return _callback_page(success=False, detail="授权状态无效或已经过期。")

    error = request.query.get("error")
    if error:
        attempt.error = {
            "error": error,
            "error_description": request.query.get("error_description"),
        }
        return _callback_page(success=False, detail="WAuth 未完成授权。")

    code = request.query.get("code", "")
    if not code:
        return _callback_page(success=False, detail="回调中没有授权码。")
    if not attempt.code_verifier:
        attempt.error = {
            "error": "missing_code_verifier",
            "error_description": "Native client must submit code_verifier before callback.",
        }
        return _callback_page(success=False, detail="应用尚未提交 PKCE 校验信息。")

    async with attempt.lock:
        if attempt.result is not None:
            return _callback_page(success=True, detail="授权结果已经生成。")
        try:
            token = await _exchange_code(
                request,
                code=code,
                code_verifier=attempt.code_verifier,
            )
            access_token = str(token["access_token"])
            userinfo_fetcher = request.app.get("userinfo_fetcher", _fetch_userinfo)
            userinfo = await userinfo_fetcher(request, access_token)
        except (ValueError, web.HTTPException, WAuthUpstreamError) as exception:
            detail = getattr(exception, "text", str(exception))
            status = getattr(exception, "status", 502)
            attempt.error = {
                "error": "token_exchange_failed",
                "error_description": detail,
            }
            request.app["logger"].warning(
                "WAuth token exchange failed with status %s",
                status,
            )
            return _callback_page(success=False, detail="服务器无法完成令牌交换。")
        attempt.result = {
            "token": token,
            "userinfo": userinfo,
        }
    return _callback_page(success=True, detail="WAuth 登录信息已经交给应用。")


async def handle_result(request: web.Request) -> web.Response:
    state = request.query.get("state", "")
    store: AuthorizationStore = request.app["store"]
    attempt = store.get(state)
    if attempt is None:
        return _json_response({"status": "expired"}, status=410)
    if attempt.error is not None:
        store.consume(state)
        return _json_response({"status": "error", **attempt.error}, status=400)
    if attempt.result is None:
        return _json_response({"status": "pending"}, status=202)
    completed = store.consume(state)
    return _json_response({"status": "complete", **(completed.result or {})})



async def _close_http_session(app: web.Application) -> None:
    session: ClientSession | None = app.get("http_session")
    if session is not None:
        await session.close()


async def _open_http_session(app: web.Application) -> None:
    app["http_session"] = ClientSession(timeout=ClientTimeout(total=15))


def create_app() -> web.Application:
    client_secret = _required_environment("WAUTH_CLIENT_SECRET")
    app = web.Application(client_max_size=16 * 1024)
    app["client_id"] = os.environ.get("WAUTH_CLIENT_ID", DEFAULT_CLIENT_ID).strip()
    app["client_secret"] = client_secret
    app["redirect_uri"] = os.environ.get(
        "WAUTH_REDIRECT_URI", DEFAULT_REDIRECT_URI
    ).strip()
    app["store"] = AuthorizationStore(
        ttl_seconds=int(os.environ.get("WAUTH_STATE_TTL_SECONDS", "600")),
        max_entries=int(os.environ.get("WAUTH_MAX_PENDING", "1000")),
    )
    app["logger"] = logging.getLogger("wauth_gateway")
    app["http_session"] = None
    app.on_startup.append(_open_http_session)
    app.on_cleanup.append(_close_http_session)
    app.router.add_get("/", handle_root)
    app.router.add_get("/health", handle_health)
    app.router.add_get("/wauth/assets/background.jpg", handle_background_image)
    app.router.add_post("/wauth/session", handle_session)
    app.router.add_get("/wauth/callback", handle_callback)
    app.router.add_get("/wauth/result", handle_result)
    return app


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("WAUTH_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    web.run_app(
        create_app(),
        host=os.environ.get("WAUTH_HOST", "127.0.0.1"),
        port=int(os.environ.get("WAUTH_PORT", "8787")),
        access_log=None,
    )


if __name__ == "__main__":
    main()
