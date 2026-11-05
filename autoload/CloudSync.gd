extends Node
## CloudSync —— 双端云存档互通（Windows ↔ iOS）REST 客户端。
## 服务器：server/save_server.mjs（Node 单文件，零依赖）。
## 配置与设备标识保存在 user://；冲突裁决：时间戳新者胜，接近时由玩家在面板中二选一。

const CONFIG_PATH := "user://cloud_config.json"
const DEVICE_PATH := "user://device_id.txt"
const CONFLICT_TOLERANCE_MS := 120000   # 双端时间戳差 ≤2 分钟视为"接近"，转人工裁决

var base_url := ""
var user := ""
var pin := ""
var device_id := ""
var busy := false

func _ready() -> void:
	_load_config()
	_load_or_make_device()

# ---------- 配置与设备 ----------
func configured() -> bool:
	return base_url != "" and user != "" and pin != ""

func save_config(url: String, u: String, p: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	user = u.strip_edges()
	pin = p.strip_edges()
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"base_url": base_url, "user": user, "pin": pin}))
		f.close()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH): return
	var parsed = JSON.parse_string(FileAccess.open(CONFIG_PATH, FileAccess.READ).get_as_text())
	if parsed is Dictionary:
		base_url = str(parsed.get("base_url", ""))
		user = str(parsed.get("user", ""))
		pin = str(parsed.get("pin", ""))

func _load_or_make_device() -> void:
	if FileAccess.file_exists(DEVICE_PATH):
		device_id = FileAccess.open(DEVICE_PATH, FileAccess.READ).get_line().strip_edges()
	if device_id == "":
		device_id = "%d-%08x-%08x" % [int(Time.get_unix_time_from_system() * 1000.0), randi(), randi()]
		var f := FileAccess.open(DEVICE_PATH, FileAccess.WRITE)
		if f:
			f.store_line(device_id)
			f.close()

# ---------- 冲突裁决 ----------
## 1=本地较新  -1=云端较新  0=接近（需人工选择保留哪份）
func verdict(local_ms: int, cloud_ms: int) -> int:
	if cloud_ms <= 0: return 1
	if local_ms <= 0: return -1
	if absi(local_ms - cloud_ms) <= CONFLICT_TOLERANCE_MS: return 0
	return 1 if local_ms > cloud_ms else -1

## 本地存档文件的时间戳（无本地档返回 0）
func local_saved_at_ms() -> int:
	if not SaveSystem.has_save(): return 0
	var parsed = JSON.parse_string(FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.READ).get_as_text())
	if parsed is Dictionary:
		return int(parsed.get("saved_at_ms", 0))
	return 0

# ---------- REST ----------
## 所有回调签名统一 cb(ok: bool, data: Dictionary)
func _post(path: String, body: Dictionary, cb: Callable) -> void:
	if busy:
		cb.call(false, {"error": "同步进行中，请稍候"})
		return
	busy = true
	var h := HTTPRequest.new()
	h.timeout = 10.0
	add_child(h)
	h.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray):
		h.queue_free()
		busy = false
		var data := {}
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			data = parsed
		else:
			data = {"error": "服务器响应解析失败"}
		cb.call(code == 200 and bool(data.get("ok", false)), data)
	)
	var err := h.request(base_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		h.queue_free()
		busy = false
		cb.call(false, {"error": "无法连接服务器（错误码 %d）" % err})

func register(u: String, p: String, cb: Callable) -> void:
	_post("/register", {"user": u, "pin": p}, cb)

## 上传本地存档
func push(cb: Callable) -> void:
	_post("/push", {"user": user, "pin": pin, "device_id": device_id, "save": SaveSystem.export_save()}, cb)

## 查询云端状态（不拉取内容）
func peek(cb: Callable) -> void:
	_post("/peek", {"user": user, "pin": pin}, cb)

## 拉取云端存档（不自动应用）
func pull(cb: Callable) -> void:
	_post("/pull", {"user": user, "pin": pin}, cb)

# ---------- 自动同步 ----------
## 保存后的自动同步：云端为空或本地不旧于云端 → 静默上传；云端较新 → 提示且不覆盖
func auto_push() -> void:
	if not configured() or busy:
		return
	peek(_on_autopeek)

func _on_autopeek(ok: bool, data: Dictionary) -> void:
	if not ok:
		return
	if bool(data.get("exists", false)) and verdict(SaveSystem.last_saved_at_ms, int(data.get("pushed_at_ms", 0))) < 0:
		EventBus.toast.emit("云端存档较新，已保留云端（行囊→云同步 可处理）")
		return
	push(_push_toast)

func _push_toast(ok: bool, data: Dictionary) -> void:
	EventBus.toast.emit("已同步到云端。" if ok else "云端同步失败：" + str(data.get("error", "")))
