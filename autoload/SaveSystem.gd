extends Node
## SaveSystem —— JSON 存档（user://save_1.json），含版本迁移与类型归一化。
## v2 新增云同步元数据（saved_at_ms / device_name）；存档为纯 JSON，可经 CloudSync 直传。

const SAVE_PATH := "user://save_1.json"
const SAVE_VERSION := 2

var last_saved_at_ms := 0   # 最近一次导出/应用存档的真实时间戳（冲突裁决用）

func save_game() -> bool:
	var d := export_save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true

## 导出当前存档字典（本地保存与云端上传共用）：游戏态 + 版本 + 云同步元数据
func export_save() -> Dictionary:
	var d: Dictionary = GameState.to_save()
	d["version"] = SAVE_VERSION
	d["saved_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	d["device_name"] = OS.get_name()
	last_saved_at_ms = int(d["saved_at_ms"])
	return d

## 从任意来源（本地文件 / 云端 JSON）应用存档：归一化 → 迁移 → 落到 GameState
func apply_save_dict(d: Dictionary) -> bool:
	if d.is_empty(): return false
	GameState.from_save(_migrate(_denormalize(d)))
	last_saved_at_ms = int(d.get("saved_at_ms", 0))
	return true

## 把外部存档字典写入本地槽（云端拉取落地用，原样保存，读取时再迁移）
func write_save_dict(d: Dictionary) -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> bool:
	if not has_save(): return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary): return false
	return apply_save_dict(parsed)

## JSON round-trip 归一化：解析后数值全变 float、嵌套容器键变 Variant——递归还原。
## 本作存档无浮点字段：整数值 float 一律转 int，非整值原样保留。
func _denormalize(v: Variant) -> Variant:
	if v is float:
		return int(v) if is_equal_approx(v, float(int(v))) else v
	if v is Array:
		var a := []
		for e in v:
			a.append(_denormalize(e))
		return a
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = _denormalize(v[k])
		return o
	return v

## 版本迁移链：旧档逐版升级到当前
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	# v0 -> v1: 补齐新字段
	if v < 1:
		if not d.has("formation"): d["formation"] = "meihua"
		if not d.has("bounty_pool"): d["bounty_pool"] = []
		if not d.has("counters"): d["counters"] = {}
		if not d.has("gather_cooldown"): d["gather_cooldown"] = {}
		if not d.has("flags"): d["flags"] = {}
		if not d.has("faction_quest_done"): d["faction_quest_done"] = {}
		if not d.has("main_done"): d["main_done"] = false
		d["version"] = 1
	# v1 -> v2: 云同步元数据
	if v < 2:
		if not d.has("saved_at_ms"): d["saved_at_ms"] = 0
		if not d.has("device_name"): d["device_name"] = ""
		d["version"] = 2
	return d

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
