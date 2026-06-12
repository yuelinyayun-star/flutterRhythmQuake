# NIED 中继部署（Windows 服务器版）

## 1. 适用场景

- Cloudflare Worker 部署超时或不稳定
- 你已有香港 Windows 服务器，希望直接自建中继

## 2. 前置条件

- Windows Server
- Node.js 18+（建议 20 LTS）
- 放行一个端口（例如 `8787`）

## 3. 启动中继服务

在项目根目录执行：

```powershell
$env:PORT=8787
$env:HOST="0.0.0.0"
node .\tools\nied_relay_server_win.js
```

服务启动后，测试：

- `http://你的服务器IP:8787/nied/sitelist`
- `http://你的服务器IP:8787/nied/realtime?date=20260504&time=170001`

## 4. 作为 Windows 服务长期运行（建议）

### 方案 A：NSSM（推荐）

1. 下载 NSSM（Non-Sucking Service Manager）
2. 安装服务（示例）：

```powershell
nssm install nied-relay "C:\Program Files\nodejs\node.exe" "D:\flutterApp\flutterrhythmquake\tools\nied_relay_server_win.js"
nssm set nied-relay AppDirectory "D:\flutterApp\flutterrhythmquake"
nssm set nied-relay AppEnvironmentExtra PORT=8787 HOST=0.0.0.0
nssm start nied-relay
```

### 方案 B：PM2（也可）

```powershell
npm i -g pm2
pm2 start .\tools\nied_relay_server_win.js --name nied-relay --time
pm2 save
pm2 startup
```

## 5. Flutter 对接（主备中继）

客户端已支持主备中继和自动切换，运行时传入：

```powershell
flutter run -d windows `
  --dart-define=NIED_RELAY_PRIMARY=http://你的主中继IP:8787 `
  --dart-define=NIED_RELAY_BACKUP=http://你的备中继IP:8787 `
  --dart-define=NIED_DIRECT_FALLBACK=false
```

如果你只有一台服务器，可以先只配主中继：

```powershell
flutter run -d windows `
  --dart-define=NIED_RELAY_PRIMARY=http://你的中继IP:8787 `
  --dart-define=NIED_DIRECT_FALLBACK=false
```

## 6. 安全与稳定建议

- 在服务器防火墙只开放给你的客户端来源（或加 Nginx + 认证）
- 反向代理加 HTTPS（Nginx/Caddy）
- 观察日志里 `upstreamStatus`，若频繁 `403`，可增加第二台中继作为备源

## 7. 接口返回结构

中继返回固定结构：

```json
{
  "ok": true,
  "source": "nied-relay-win",
  "upstreamStatus": 200,
  "upstreamUrl": "https://weather-kyoshin.../RealTimeData/20260504/170001.json",
  "fetchedAt": "2026-05-04T17:00:01.123Z",
  "body": {}
}
```
