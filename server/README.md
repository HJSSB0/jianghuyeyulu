# 云存档服务器部署指引

单文件零依赖 Node 服务（`save_server.mjs`），为 Windows ↔ iOS 双端提供存档互通。

## 本机/局域网联调（最快）

1. 启动：双击 `start_server.bat`，或命令行 `node save_server.mjs 8787`
2. 游戏内（电脑）：行囊 → 云同步 → 填 `http://127.0.0.1:8787` 与用户名/PIN → 注册 → 上传本地存档
3. 另一台设备（同一路由器）：填电脑的**局域网 IP**（`ipconfig` 查看 IPv4 地址），如 `http://192.168.1.5:8787` → 拉取云端存档
   - Windows 防火墙首次会弹窗，允许"专用网络"访问 Node

## 公网部署（真机 iOS 用）

iOS 真机不在局域网时需要公网可达。任选其一：

| 方式 | 说明 |
|---|---|
| 云主机 | 任意 1C1G 主机：`node save_server.mjs 8787`，用 systemd/pm2 守护，安全组放行端口 |
| 内网穿透 | frp / Cloudflare Tunnel / 花生壳等，把本机 8787 映射到公网域名 |

**务必上 HTTPS**：游戏客户端目前是明文 HTTP，公网裸奔会被嗅探 PIN。用 nginx/Caddy 反向代理加证书即可，客户端服务器地址填 `https://你的域名`。

## 数据与安全

- 账号与存档落盘在 `server/data/`（`<user>.auth.json` / `<user>.save.json`），备份历史在 `server/history/`（每用户保留最近 5 份）
- PIN 只存 scrypt 盐哈希，服务器代码不记录请求体
- 接口均为 `POST + JSON`；`/health` 可用于探活
- 这是单进程内存外模型，重启不丢数据；适合个人/小团队使用，不建议公开运营（无频控、无防刷）

## 接口一览

| 方法 | 路径 | 请求体 | 响应 |
|---|---|---|---|
| POST | /register | `{user, pin}` | `{ok:true}` / 409 已存在 |
| POST | /push | `{user, pin, device_id, save}` | `{ok:true, pushed_at_ms}` |
| POST | /peek | `{user, pin}` | `{ok:true, exists, pushed_at_ms?, device_id?}` |
| POST | /pull | `{user, pin}` | `{ok:true, exists, save?, device_id?, pushed_at_ms?}` |
| GET  | /health | - | `{ok:true, uptime}` |
