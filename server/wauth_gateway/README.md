# RhythmQuake WAuth Gateway

WAuth OAuth 2.0 Authorization Code + PKCE 的服务端网关。它只负责保存 AppSecret、交换授权码，并把 WAuth 官方 token 与 userinfo 通过一次性结果交给 RhythmQuake 客户端。

固定回调地址：

```text
https://quake.yuelinrhythm.top/wauth/callback
```

必须先在 WAuth 应用后台把这个地址加入回调白名单，字符必须完全一致。

## 安全边界

- AppSecret 只通过服务器环境变量 `WAUTH_CLIENT_SECRET` 提供，绝不放入 Flutter 客户端。
- AppSecret、访问令牌和授权码不写入仓库或日志。
- 回调和结果响应都使用 `Cache-Control: no-store`。
- Nginx 必须关闭 `/wauth/callback` 和 `/wauth/result` 的访问日志，避免查询参数进入日志。
- 每个授权结果只允许读取一次，默认 10 分钟过期。
- 客户端使用官方 access token 请求 WAuth `/oauth2/userinfo` 确认账号登录状态；业务 API 另需通过 `POST /api/token/verify` 校验 api_token。
- 本地缓存的 `userinfo` 只用于显示，不能单独作为业务 API 的启用条件。

## 客户端流程

1. 客户端生成 PKCE `code_verifier`、`code_challenge` 和随机 `state`。
2. 客户端通过 HTTPS 创建一次授权会话：

```text
POST https://quake.yuelinrhythm.top/wauth/session
Content-Type: application/json

{
  "state": "...",
  "code_challenge": "...",
  "code_verifier": "..."
}
```

3. 客户端打开响应里的 `authorizationUrl`。
4. 浏览器授权后回到固定回调地址，服务器使用 AppSecret 交换官方 token，并请求官方 `userinfo`。
5. 客户端轮询一次性授权结果：

```text
GET /wauth/result?state=...
```

`202` 表示等待授权，`200` 表示完成且结果已被消费，`400/410` 表示失败或过期。成功响应包含 WAuth 官方 `token` 和 `userinfo`：

```json
{
  "status": "complete",
  "token": {
    "access_token": "...",
    "token_type": "Bearer",
    "expires_in": 3600,
    "scope": "openid profile"
  },
  "userinfo": {
    "sub": "..."
  }
}
```

6. 客户端保存官方 access token。启动、恢复应用或开启受保护 API 前，必须使用该 token 请求 WAuth 官方 `/oauth2/userinfo`。验证失败、超时或没有 token 时，API 保持关闭。
7. 退出登录只清理客户端保存的官方 token 和用户资料。本地网关不签发自己的会话，也没有 `/wauth/status` 或 `/wauth/logout` 路由。

## API token 校验

真实授权结果中可能同时包含 `access_token` 与 `api_token`，两者用途不同：

- `access_token` 只用于请求 WAuth 官方 `/oauth2/userinfo`。
- `api_token` 用于业务 API 的官方校验端点 `POST /api/token/verify`。
- 只有校验响应中的 `valid` 严格等于 `true`，业务 API 才允许开启。
- 未登录、缺少 api_token、校验返回 `valid: false`、令牌过期或校验超时时，都必须保持关闭。

本地网关只原样转发官方 token 字段，不自行生成或替换令牌。
## 本地测试

```powershell
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
python -m unittest -v test_wauth_gateway.py
```

测试不连接 WAuth，也不使用真实 AppSecret。
