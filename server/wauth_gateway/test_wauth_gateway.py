import base64
import hashlib
import os
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

from aiohttp.test_utils import AioHTTPTestCase

from wauth_gateway import AuthorizationStore, _callback_page, _is_base64url, create_app


class AuthorizationStoreTest(unittest.TestCase):
    def test_expired_attempt_is_removed(self) -> None:
        store = AuthorizationStore(ttl_seconds=10)
        store.create(
            state="s" * 32,
            code_challenge="c" * 43,
            nonce=None,
            now=100,
        )

        self.assertIsNone(store.get("s" * 32, now=111))
        self.assertEqual(store.count, 0)

    def test_completed_attempt_is_consumed_once(self) -> None:
        store = AuthorizationStore()
        attempt = store.create(
            state="s" * 32,
            code_challenge="c" * 43,
            nonce=None,
            now=100,
        )
        attempt.result = {"token": {"access_token": "test"}}

        self.assertIs(store.consume("s" * 32), attempt)
        self.assertIsNone(store.consume("s" * 32))

    def test_verifier_is_kept_separately_from_challenge(self) -> None:
        store = AuthorizationStore()
        attempt = store.create(
            state="s" * 32,
            code_challenge="c" * 43,
            nonce=None,
            now=100,
        )
        attempt.code_verifier = "v" * 43

        self.assertEqual(attempt.code_challenge, "c" * 43)
        self.assertEqual(attempt.code_verifier, "v" * 43)


class ValidationTest(unittest.TestCase):
    def test_pkce_verifier_and_challenge_are_base64url(self) -> None:
        verifier = "a" * 43
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode("ascii")).digest()
        ).decode("ascii").rstrip("=")

        self.assertTrue(_is_base64url(verifier, minimum=43, maximum=128))
        self.assertTrue(_is_base64url(challenge, minimum=43, maximum=128))

    def test_invalid_characters_are_rejected(self) -> None:
        self.assertFalse(_is_base64url("a" * 31 + "+", minimum=32, maximum=256))


class AuthorizeUrlContractTest(unittest.TestCase):
    def test_standard_authorize_url_shape(self) -> None:
        uri = urlparse(
            "https://auth.beecld.com/oauth2/authorize?"
            "response_type=code&client_id=client&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback"
            "&scope=openid+profile+email&state=state&code_challenge=challenge"
            "&code_challenge_method=S256"
        )
        query = parse_qs(uri.query)

        self.assertEqual(uri.path, "/oauth2/authorize")
        self.assertEqual(query["response_type"], ["code"])
        self.assertEqual(query["code_challenge_method"], ["S256"])


class CallbackPageTest(unittest.TestCase):
    def test_dynamic_detail_is_escaped_inside_the_panel(self) -> None:
        response = _callback_page(
            success=False,
            detail='<script>alert("unsafe")</script>',
        )
        body = response.text

        self.assertEqual(response.status, 400)
        self.assertIn('class="auth-panel auth-panel--failure"', body)
        self.assertIn("授权失败", body)
        self.assertIn(
            "&lt;script&gt;alert(&quot;unsafe&quot;)&lt;/script&gt;",
            body,
        )
        self.assertNotIn('<script>alert("unsafe")</script>', body)
        self.assertIn("现在可以返回 RhythmQuake。", body)
        self.assertIn('href="rhythmquake://wauth-complete"', body)
        self.assertIn('url("/wauth/assets/background.jpg")', body)
        self.assertIn("img-src 'self'", response.headers["Content-Security-Policy"])


class GatewayHttpTest(AioHTTPTestCase):
    async def get_application(self):
        os.environ["WAUTH_CLIENT_SECRET"] = "local-test-only"
        return create_app()

    async def asyncTearDown(self) -> None:
        try:
            await super().asyncTearDown()
        finally:
            os.environ.pop("WAUTH_CLIENT_SECRET", None)

    async def _create_authorization(self, state: str = "s" * 32) -> None:
        verifier = "v" * 43
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode("ascii")).digest()
        ).decode("ascii").rstrip("=")
        response = await self.client.post(
            "/wauth/session",
            json={
                "state": state,
                "code_challenge": challenge,
                "code_verifier": verifier,
            },
        )
        self.assertEqual(response.status, 200)

    async def test_health_does_not_expose_secret(self) -> None:
        response = await self.client.get("/health")
        payload = await response.json()

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(payload["clientSecretConfigured"])
        self.assertNotIn("local-test-only", str(payload))
        self.assertNotIn("authenticatedSessions", payload)

    async def test_callback_background_is_served_as_the_original_jpeg(self) -> None:
        response = await self.client.get("/wauth/assets/background.jpg")
        body = await response.read()

        self.assertEqual(response.status, 200)
        self.assertEqual(response.content_type, "image/jpeg")
        self.assertEqual(response.headers["Cache-Control"], "public, max-age=86400")
        self.assertEqual(
            hashlib.sha256(body).hexdigest(),
            "0745312d39c45c595d0aeab5045af7f72547a09df28bcf9d05eae22243d06146",
        )

    async def test_root_only_advertises_the_live_gateway_contract(self) -> None:
        response = await self.client.get("/")
        payload = await response.json()

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["session"], "/wauth/session")
        self.assertEqual(payload["callback"], "/wauth/callback")
        self.assertEqual(payload["result"], "/wauth/result")
        self.assertNotIn("status", payload)
        self.assertNotIn("logout", payload)

    async def test_session_uses_fixed_callback(self) -> None:
        verifier = "v" * 43
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode("ascii")).digest()
        ).decode("ascii").rstrip("=")
        response = await self.client.post(
            "/wauth/session",
            json={
                "state": "s" * 32,
                "code_challenge": challenge,
                "code_verifier": verifier,
            },
        )
        payload = await response.json()
        redirect = urlparse(payload["authorizationUrl"])
        query = parse_qs(redirect.query)

        self.assertEqual(response.status, 200)
        self.assertEqual(redirect.netloc, "auth.beecld.com")
        self.assertEqual(
            query["redirect_uri"],
            ["https://quake.yuelinrhythm.top/wauth/callback"],
        )

    async def test_session_rejects_mismatched_pkce(self) -> None:
        response = await self.client.post(
            "/wauth/session",
            json={
                "state": "s" * 32,
                "code_challenge": "c" * 43,
                "code_verifier": "v" * 43,
            },
        )

        self.assertEqual(response.status, 400)
        self.assertEqual((await response.json())["error"], "pkce_mismatch")

    async def test_callback_publishes_official_token_and_userinfo_once(self) -> None:
        state = "s" * 32
        await self._create_authorization(state)

        async def exchange_code(_request, *, code, code_verifier):
            self.assertEqual(code, "authorization-code")
            self.assertEqual(code_verifier, "v" * 43)
            return {
                "access_token": "official-access-token",
                "api_token": "official-api-token",
                "token_type": "Bearer",
                "expires_in": 3600,
                "scope": "openid profile",
                "id_token": "id-token",
            }

        async def fetch_userinfo(_request, access_token):
            self.assertEqual(access_token, "official-access-token")
            return {"sub": "72", "name": "Rhythm"}

        self.app["userinfo_fetcher"] = fetch_userinfo
        with patch("wauth_gateway._exchange_code", new=exchange_code):
            callback = await self.client.get(
                "/wauth/callback",
                params={"state": state, "code": "authorization-code"},
            )

        self.assertEqual(callback.status, 200)
        callback_body = await callback.text()
        self.assertIn('class="auth-panel auth-panel--success"', callback_body)
        self.assertIn("授权完成", callback_body)
        self.assertIn("WAuth 登录信息已经交给应用。", callback_body)
        self.assertIn("现在可以返回 RhythmQuake。", callback_body)
        self.assertIn('href="rhythmquake://wauth-complete"', callback_body)
        result = await self.client.get("/wauth/result", params={"state": state})
        payload = await result.json()

        self.assertEqual(result.status, 200)
        self.assertEqual(payload["status"], "complete")
        self.assertEqual(payload["token"]["access_token"], "official-access-token")
        self.assertEqual(payload["token"]["api_token"], "official-api-token")
        self.assertEqual(payload["userinfo"]["sub"], "72")
        self.assertNotIn("sessionToken", payload)

        consumed = await self.client.get("/wauth/result", params={"state": state})
        self.assertEqual(consumed.status, 410)

    async def test_invalid_callback_uses_the_failure_panel(self) -> None:
        callback = await self.client.get(
            "/wauth/callback",
            params={"state": "x" * 32, "code": "unused"},
        )
        callback_body = await callback.text()

        self.assertEqual(callback.status, 400)
        self.assertIn('class="auth-panel auth-panel--failure"', callback_body)
        self.assertIn("授权失败", callback_body)
        self.assertIn("授权状态无效或已经过期。", callback_body)
        self.assertIn("现在可以返回 RhythmQuake。", callback_body)
        self.assertIn('href="rhythmquake://wauth-complete"', callback_body)

    async def test_removed_private_session_routes_are_not_registered(self) -> None:
        status = await self.client.get("/wauth/status")
        logout = await self.client.post("/wauth/logout")

        self.assertEqual(status.status, 404)
        self.assertEqual(logout.status, 404)


if __name__ == "__main__":
    unittest.main()
