#!/usr/bin/env node
// 江湖夜雨录 · 云存档服务器（零依赖单文件，需 Node ≥ 18）
// 用法：node save_server.mjs [端口]   （默认 8787）
// 接口（除 /health 均为 POST JSON）：
//   /register {user, pin}                   注册（PIN 经 scrypt 盐哈希存储）
//   /push     {user, pin, device_id, save}  上传存档（旧档自动备份到 history/，保留最近 5 份）
//   /peek     {user, pin}                   查询云端状态（不返回存档内容）
//   /pull     {user, pin}                   拉取云端存档
//   /health   GET                           健康检查

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.argv[2] || process.env.PORT || 8787);
const ROOT = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(ROOT, 'data');
const HIST_DIR = path.join(ROOT, 'history');
const MAX_BODY = 4 * 1024 * 1024;   // 存档几十 KB 量级，4MB 上限防滥用
const KEEP_HIST = 5;
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(HIST_DIR, { recursive: true });

const USER_RE = /^[A-Za-z0-9_-]{2,24}$/;
const authFile = (u) => path.join(DATA_DIR, `${u}.auth.json`);
const saveFile = (u) => path.join(DATA_DIR, `${u}.save.json`);
const okRes = (extra = {}) => JSON.stringify({ ok: true, ...extra });
const errRes = (code, error) => ({ code, body: JSON.stringify({ ok: false, error }) });

// PIN 校验：返回 null 表示通过，否则返回错误响应
function verify(user, pin) {
  if (!USER_RE.test(user || '')) return errRes(400, '用户名不合法（2-24 位字母数字_-）');
  if (typeof pin !== 'string' || pin.length < 4) return errRes(400, 'PIN 至少 4 位');
  const af = authFile(user);
  if (!fs.existsSync(af)) return errRes(404, '账号不存在，请先注册');
  const auth = JSON.parse(fs.readFileSync(af, 'utf8'));
  const hash = crypto.scryptSync(pin, auth.salt, 32).toString('hex');
  const a = Buffer.from(hash);
  const b = Buffer.from(auth.hash);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return errRes(401, '用户名或 PIN 错误');
  return null;
}

// 上传前备份旧档，并按用户保留最近 KEEP_HIST 份
function backupOld(user) {
  const sf = saveFile(user);
  if (!fs.existsSync(sf)) return;
  fs.copyFileSync(sf, path.join(HIST_DIR, `${user}-${Date.now()}.json`));
  const olds = fs.readdirSync(HIST_DIR).filter(f => f.startsWith(`${user}-`)).sort();
  while (olds.length > KEEP_HIST) fs.unlinkSync(path.join(HIST_DIR, olds.shift()));
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  const done = (code, body) => { res.statusCode = code; res.end(body); };
  const url = (req.url || '/').split('?')[0];
  if (req.method === 'GET' && url === '/health') return done(200, okRes({ uptime: process.uptime() }));
  if (req.method !== 'POST') return done(405, JSON.stringify({ ok: false, error: '仅支持 POST' }));
  const chunks = [];
  let size = 0;
  req.on('data', (c) => {
    size += c.length;
    if (size > MAX_BODY) { req.destroy(); return; }
    chunks.push(c);
  });
  req.on('end', () => {
    let body = {};
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); }
    catch { return done(400, JSON.stringify({ ok: false, error: 'JSON 解析失败' })); }
    const user = String(body.user || '');

    if (url === '/register') {
      if (!USER_RE.test(user)) return done(400, JSON.stringify({ ok: false, error: '用户名不合法（2-24 位字母数字_-）' }));
      if (typeof body.pin !== 'string' || body.pin.length < 4) return done(400, JSON.stringify({ ok: false, error: 'PIN 至少 4 位' }));
      if (fs.existsSync(authFile(user))) return done(409, JSON.stringify({ ok: false, error: '账号已存在' }));
      const salt = crypto.randomBytes(16).toString('hex');
      fs.writeFileSync(authFile(user), JSON.stringify({
        salt,
        hash: crypto.scryptSync(body.pin, salt, 32).toString('hex'),
        created_at: Date.now(),
      }));
      console.log(`[reg]   ${user}`);
      return done(200, okRes());
    }

    const bad = verify(user, body.pin);
    if (bad) return done(bad.code, bad.body);

    if (url === '/peek') {
      const sf = saveFile(user);
      if (!fs.existsSync(sf)) return done(200, okRes({ exists: false }));
      const rec = JSON.parse(fs.readFileSync(sf, 'utf8'));
      return done(200, okRes({ exists: true, pushed_at_ms: rec.pushed_at_ms || 0, device_id: rec.device_id || '' }));
    }
    if (url === '/pull') {
      const sf = saveFile(user);
      if (!fs.existsSync(sf)) return done(200, okRes({ exists: false }));
      const rec = JSON.parse(fs.readFileSync(sf, 'utf8'));
      return done(200, okRes({ exists: true, save: rec.save || {}, device_id: rec.device_id || '', pushed_at_ms: rec.pushed_at_ms || 0 }));
    }
    if (url === '/push') {
      if (!body.save || typeof body.save !== 'object' || Array.isArray(body.save)) {
        return done(400, JSON.stringify({ ok: false, error: '缺少 save 字段' }));
      }
      backupOld(user);
      const rec = { save: body.save, device_id: String(body.device_id || ''), pushed_at_ms: Date.now() };
      fs.writeFileSync(saveFile(user), JSON.stringify(rec));
      console.log(`[push]  ${user}  pushed_at=${rec.pushed_at_ms}`);
      return done(200, okRes({ pushed_at_ms: rec.pushed_at_ms }));
    }
    done(404, JSON.stringify({ ok: false, error: '未知接口' }));
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`《江湖夜雨录》云存档服务器已启动：http://0.0.0.0:${PORT}  （数据目录 ${DATA_DIR}）`);
});
