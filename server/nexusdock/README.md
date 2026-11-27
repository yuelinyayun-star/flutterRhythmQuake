# NexusDock on the API server

This deployment puts the shared AgentDock control plane on the existing API
server and exposes it through the existing `mcp.yuelinrhythm.top` hostname.
The current API and KMA relay ports remain separate.

## Runtime layout

- Public MCP and web console: `https://mcp.yuelinrhythm.top`
- Nginx upstream: `127.0.0.1:18777`
- Nexus control data: `/opt/rhythmquake/nexusdock/nexus-data`
- Shared Recall data: `/opt/rhythmquake/nexusdock/recall`
- Container image: `ghcr.io/uvwt/nexusdock:latest` until a verified digest is pinned

The container is bound to loopback. Nginx is the only public entry point. The
AgentDock nodes connect outbound to NexusDock after pairing, so their local
MCP ports do not need public firewall rules.

## First-time setup

The deployment workflow starts the service and installs the HTTPS proxy. The
administrator account must be initialized separately by an operator with server
access. Credentials are never stored in this repository.

From `/opt/rhythmquake/nexusdock` on the server:

```bash
docker compose run --rm nexusdock admin init admin
docker compose up -d
curl --fail http://127.0.0.1:18777/health
```

After signing in at `https://mcp.yuelinrhythm.top`, pair the local AgentDock,
the existing cloud Windows AgentDock, the VGPU Windows AgentDock, and the API
server AgentDock. Each pairing code is single-use. Gemini should use the single
MCP endpoint `https://mcp.yuelinrhythm.top/mcp`.

## Upgrade and backup

Back up both persistent directories before upgrading:

```bash
tar -C /opt/rhythmquake/nexusdock -czf /opt/rhythmquake/nexusdock-backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz nexus-data recall
docker compose pull
docker compose up -d
curl --fail http://127.0.0.1:18777/health
```

Do not run a second NexusDock instance against these directories.
