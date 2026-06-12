const UPSTREAM_BASE = "https://weather-kyoshin.east.edge.storage-yahoo.jp";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

const UPSTREAM_HEADERS = {
  Accept: "application/json,text/plain,*/*",
  "Cache-Control": "no-cache",
  Pragma: "no-cache",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
};

function json(data, status = 200, cacheControl = "no-store") {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": cacheControl,
      ...CORS_HEADERS,
    },
  });
}

function buildUpstreamUrl(url) {
  if (url.pathname === "/nied/sitelist") {
    const stamp = Date.now();
    return `${UPSTREAM_BASE}/SiteList/sitelist.json?time=${stamp}`;
  }

  if (url.pathname === "/nied/realtime") {
    const date = url.searchParams.get("date");
    const time = url.searchParams.get("time");
    if (!/^\d{8}$/.test(date || "") || !/^\d{6}$/.test(time || "")) {
      return null;
    }
    return `${UPSTREAM_BASE}/RealTimeData/${date}/${time}.json`;
  }

  return null;
}

function getCacheTtlByStatus(statusCode) {
  if (statusCode === 200) return 1;
  if (statusCode === 404) return 1;
  return 0;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method !== "GET") {
      return json({ ok: false, error: "method_not_allowed" }, 405);
    }

    const url = new URL(request.url);
    const upstreamUrl = buildUpstreamUrl(url);
    if (!upstreamUrl) {
      return json(
        {
          ok: false,
          error: "invalid_path_or_params",
          usage: ["/nied/sitelist", "/nied/realtime?date=YYYYMMDD&time=HHmmss"],
        },
        400,
      );
    }

    const cache = caches.default;
    const cacheKey = new Request(url.toString(), { method: "GET" });
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    let upstreamResp;
    try {
      upstreamResp = await fetch(upstreamUrl, {
        method: "GET",
        headers: UPSTREAM_HEADERS,
        redirect: "follow",
        cf: { cacheTtl: 0, cacheEverything: false },
      });
    } catch (e) {
      return json(
        {
          ok: false,
          error: "upstream_fetch_failed",
          detail: String(e),
          upstreamUrl,
        },
        502,
      );
    }

    const text = await upstreamResp.text();
    const statusCode = upstreamResp.status;
    const contentType = upstreamResp.headers.get("content-type") || "";
    const isJson = contentType.includes("application/json");

    let body = text;
    if (isJson) {
      try {
        body = JSON.parse(text);
      } catch (_) {
        body = text;
      }
    }

    const responsePayload = {
      ok: statusCode === 200,
      source: "nied-relay-worker",
      upstreamStatus: statusCode,
      upstreamUrl,
      fetchedAt: new Date().toISOString(),
      body,
    };

    const ttl = getCacheTtlByStatus(statusCode);
    const response = json(
      responsePayload,
      200,
      ttl > 0 ? `public, max-age=${ttl}` : "no-store",
    );
    if (ttl > 0) {
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
    }

    return response;
  },
};
