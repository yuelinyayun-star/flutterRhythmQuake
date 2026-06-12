/*
  NIED relay server for Windows (Node.js 18+)
  Start:
    node tools/nied_relay_server_win.js
  Env:
    PORT=8787
    HOST=0.0.0.0
*/

const http = require("node:http");
const { URL } = require("node:url");

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "0.0.0.0";
const REQUEST_TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT_MS || 15000);
const MAX_RETRIES = Number(process.env.UPSTREAM_RETRIES || 2);

const UPSTREAM_BASE = "https://weather-kyoshin.east.edge.storage-yahoo.jp";

const cache = new Map();

const UPSTREAM_HEADERS = {
  Accept: "application/json,text/plain,*/*",
  "Cache-Control": "no-cache",
  Pragma: "no-cache",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
};

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
}

function sendJson(res, statusCode, payload) {
  setCors(res);
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

function getCacheTtlMs(upstreamStatus) {
  if (upstreamStatus === 200) return 1000;
  if (upstreamStatus === 404) return 1000;
  return 0;
}

function readCache(key) {
  const v = cache.get(key);
  if (!v) return null;
  if (Date.now() > v.expireAt) {
    cache.delete(key);
    return null;
  }
  return v.payload;
}

function writeCache(key, payload, ttlMs) {
  if (ttlMs <= 0) return;
  cache.set(key, { payload, expireAt: Date.now() + ttlMs });
}

async function fetchWithTimeout(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(url, {
      method: "GET",
      headers: UPSTREAM_HEADERS,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

function shouldRetry(error) {
  const msg = String(error || "");
  return (
    msg.includes("AbortError") ||
    msg.includes("ETIMEDOUT") ||
    msg.includes("ECONNRESET") ||
    msg.includes("ENOTFOUND") ||
    msg.includes("EAI_AGAIN") ||
    msg.includes("fetch failed")
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchUpstreamWithRetry(url) {
  let lastError = null;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fetchWithTimeout(url);
    } catch (e) {
      lastError = e;
      if (attempt >= MAX_RETRIES || !shouldRetry(e)) break;
      await sleep(400 * (attempt + 1));
    }
  }
  throw lastError;
}

function buildUpstreamUrl(reqUrl) {
  if (reqUrl.pathname === "/nied/sitelist") {
    return `${UPSTREAM_BASE}/SiteList/sitelist.json?time=${Date.now()}`;
  }
  if (reqUrl.pathname === "/nied/realtime") {
    const date = reqUrl.searchParams.get("date");
    const time = reqUrl.searchParams.get("time");
    if (!/^\d{8}$/.test(date || "") || !/^\d{6}$/.test(time || "")) {
      return null;
    }
    return `${UPSTREAM_BASE}/RealTimeData/${date}/${time}.json`;
  }
  return null;
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      setCors(res);
      res.statusCode = 204;
      return res.end();
    }

    if (req.method !== "GET") {
      return sendJson(res, 405, { ok: false, error: "method_not_allowed" });
    }

    const reqUrl = new URL(req.url, `http://${req.headers.host}`);
    const upstreamUrl = buildUpstreamUrl(reqUrl);
    if (!upstreamUrl) {
      return sendJson(res, 400, {
        ok: false,
        error: "invalid_path_or_params",
        usage: ["/nied/sitelist", "/nied/realtime?date=YYYYMMDD&time=HHmmss"],
      });
    }

    const cacheKey = reqUrl.pathname + reqUrl.search;
    const hit = readCache(cacheKey);
    if (hit) {
      return sendJson(res, 200, hit);
    }

    let upstreamResp;
    try {
      upstreamResp = await fetchUpstreamWithRetry(upstreamUrl);
    } catch (e) {
      return sendJson(res, 502, {
        ok: false,
        error: "upstream_fetch_failed",
        detail: String(e),
        upstreamUrl,
        timeoutMs: REQUEST_TIMEOUT_MS,
        retries: MAX_RETRIES,
      });
    }

    const upstreamStatus = upstreamResp.status;
    const contentType = upstreamResp.headers.get("content-type") || "";
    const raw = await upstreamResp.text();
    let body = raw;
    if (contentType.includes("application/json")) {
      try {
        body = JSON.parse(raw);
      } catch (_) {
        body = raw;
      }
    }

    const payload = {
      ok: upstreamStatus === 200,
      source: "nied-relay-win",
      upstreamStatus,
      upstreamUrl,
      fetchedAt: new Date().toISOString(),
      body,
    };

    writeCache(cacheKey, payload, getCacheTtlMs(upstreamStatus));
    return sendJson(res, 200, payload);
  } catch (e) {
    return sendJson(res, 500, {
      ok: false,
      error: "relay_internal_error",
      detail: String(e),
    });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`NIED relay listening on http://${HOST}:${PORT}`);
});
