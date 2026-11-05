extends Node
## GameDB —— 静态数据库。启动时从 data/*.json 载入全部配置，并做引用完整性校验。
## 数据与逻辑分离：本节点只读不写；GameState/Battle 消费这里的数据。

const GRADE_ORDER: Array = ["丁", "丙", "乙", "甲"]
const SHICHEN: Array = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const SHICHEN_NAME: Dictionary = {
	"子": "夜半", "丑": "鸡鸣", "寅": "平旦", "卯": "日出", "辰": "食时", "巳": "隅中",
	"午": "日中", "未": "日昳", "申": "晡时", "酉": "日入", "戌": "黄昏", "亥": "人定",
}
const ATTRS: Array = ["臂力", "体质", "敏捷", "悟性", "福缘"]
const MORALS: Array = ["仁", "义", "勇"]
const MOVE_TARGETS: Array = ["对位", "突进", "横扫", "全体", "自身", "己方"]
const STATUS_IDS: Array = ["中毒", "流血", "内伤", "封穴", "目盲", "迟缓", "攻增", "防增", "免伤", "回气"]

var wuxue: Dictionary = {}
var items: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var encounters: Dictionary = {}
var factions: Dictionary = {}
var formations: Dictionary = {}
var meridians: Dictionary = {}
var traits: Dictionary = {}
var shops: Dictionary = {}
var maps: Dictionary = {}
var world: Dictionary = {}
var recipes: Dictionary = {}
var enemies: Dictionary = {}

var last_errors: Array = []   # 校验错误（测试断言用）

func _ready() -> void:
	load_all()

func load_all() -> void:
	wuxue = _load_kv("wuxue.json")
	items = _load_kv("items.json")
	npcs = _load_kv("npcs.json")
	quests = _load_kv("quests.json")
	encounters = _load_kv("encounters.json")
	factions = _load_kv("factions.json")
	formations = _load_kv("formations.json")
	meridians = _load_kv("meridians.json")
	traits = _load_kv("traits.json")
	shops = _load_kv("shops.json")
	recipes = _load_kv("recipes.json")
	enemies = _load_kv("enemies.json")
	var maps_all: Dictionary = _load_kv("maps.json")
	world = maps_all.get("world", {})
	maps = maps_all.get("maps", {})
	last_errors = validate()
	for e in last_errors:
		push_error("[GameDB] " + e)

func _load_kv(fname: String) -> Dictionary:
	var path := "res://data/" + fname
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_error("[GameDB] 缺少数据文件: " + path)
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		push_error("[GameDB] JSON 解析失败: " + path)
		return out
	for k in parsed:
		var v = parsed[k]
		if v is Dictionary and v.has("id"):
			out[str(v["id"])] = v
		else:
			out[str(k)] = v
	return out

# ---------- 校验：引用完整性 ----------
func validate() -> Array:
	var errs: Array = []
	# 武学
	for id in wuxue:
		var w: Dictionary = wuxue[id]
		if not GRADE_ORDER.has(w.get("grade", "")):
			errs.append("武学 %s 品级非法: %s" % [id, w.get("grade")])
		var kind: String = w.get("kind", "")
		if kind == "套路":
			if not w.has("moves") or (w["moves"] as Array).size() < 1:
				errs.append("武学 %s 缺少招式" % id)
			else:
				for m in w["moves"]:
					var mv: Dictionary = m
					if not MOVE_TARGETS.has(mv.get("target", "")):
						errs.append("武学 %s 招式[%s] 目标非法: %s" % [id, mv.get("name"), mv.get("target")])
					if mv.has("status") and not STATUS_IDS.has(mv["status"].get("id", "")):
						errs.append("武学 %s 招式[%s] 状态非法: %s" % [id, mv.get("name"), mv["status"].get("id")])
	# 物品
	for id in items:
		var it: Dictionary = items[id]
		if it.has("learn") and not wuxue.has(it["learn"]):
			errs.append("物品 %s 引用不存在武学 %s" % [id, it["learn"]])
		if it.has("equip") and not ["武器", "防具", "饰品"].has(it["equip"]):
			errs.append("物品 %s 装备类型非法" % id)
	# NPC
	for id in npcs:
		var n: Dictionary = npcs[id]
		if n.has("shop") and not shops.has(n["shop"]):
			errs.append("NPC %s 引用不存在商店 %s" % [id, n["shop"]])
		if n.has("faction") and not factions.has(n["faction"]):
			errs.append("NPC %s 引用不存在门派 %s" % [id, n["faction"]])
	# 任务
	for id in quests:
		var q: Dictionary = quests[id]
		var rw: Dictionary = q.get("rewards", {})
		for iid in rw.get("items", {}):
			if not items.has(iid):
				errs.append("任务 %s 奖励物品不存在: %s" % [id, iid])
		var pre: Dictionary = q.get("prereq", {})
		for need in pre.get("quests", []):
			if not quests.has(need):
				errs.append("任务 %s 前置任务不存在: %s" % [id, need])
	# 商店
	for id in shops:
		var s: Dictionary = shops[id]
		for entry in s.get("items", []):
			var iid2: String = entry.get("item", "")
			if not items.has(iid2):
				errs.append("商店 %s 物品不存在: %s" % [id, iid2])
	# 配方
	for id in recipes:
		var r: Dictionary = recipes[id]
		for m2 in r.get("mats", {}):
			if not items.has(m2):
				errs.append("配方 %s 材料不存在: %s" % [id, m2])
		if not items.has(r.get("out", "")):
			errs.append("配方 %s 产物不存在: %s" % [id, r.get("out")])
	# 敌人
	for id in enemies:
		var e: Dictionary = enemies[id]
		for d in e.get("drops", []):
			if not items.has(d.get("item", "")):
				errs.append("敌人 %s 掉落物品不存在: %s" % [id, d.get("item")])
	# 地图
	for id in maps:
		var m3: Dictionary = maps[id]
		var grid: Array = m3.get("grid", [])
		if grid.is_empty():
			errs.append("地图 %s 网格为空" % id)
		var w3: int = str(grid[0]).length() if not grid.is_empty() else 0
		for row in grid:
			if str(row).length() != w3:
				errs.append("地图 %s 网格行宽不一致" % id)
		for nid in m3.get("npcs", {}):
			if not npcs.has(nid):
				errs.append("地图 %s 放置了不存在 NPC %s" % [id, nid])
		for g in m3.get("gathers", []):
			if not items.has(g.get("pool", [""])[0] if not g.get("pool", []).is_empty() else ""):
				pass  # pool 可能为空，允许
		for h in m3.get("hiddens", []):
			for iid3 in h.get("items", {}):
				if not items.has(iid3):
					errs.append("地图 %s 隐藏点物品不存在: %s" % [id, iid3])
		for sq in m3.get("squads", []):
			for u in sq.get("units", []):
				if not enemies.has(u.get("enemy", "")):
					errs.append("地图 %s 敌组引用不存在敌人 %s" % [id, u.get("enemy")])
	# 世界图
	for nid2 in world.get("nodes", {}):
		var nd: Dictionary = world["nodes"][nid2]
		if not maps.has(nd.get("map", "")) and nd.get("type", "") != "据点":
			errs.append("世界节点 %s 引用不存在地图 %s" % [nid2, nd.get("map")])
	for eid in world.get("edges", []):
		var ed: Dictionary = eid
		if not world["nodes"].has(ed.get("a", "")) or not world["nodes"].has(ed.get("b", "")):
			errs.append("世界边引用不存在节点: %s-%s" % [ed.get("a"), ed.get("b")])
	# 奇遇
	for id in encounters:
		var enc: Dictionary = encounters[id]
		for rw2 in enc.get("options", []):
			for iid4 in rw2.get("items", {}):
				if not items.has(iid4):
					errs.append("奇遇 %s 选项物品不存在: %s" % [id, iid4])
			if rw2.has("learn") and not wuxue.has(rw2["learn"]):
				errs.append("奇遇 %s 选项武学不存在: %s" % [id, rw2["learn"]])
			if rw2.has("trait") and not traits.has(rw2["trait"]):
				errs.append("奇遇 %s 选项特性不存在: %s" % [id, rw2["trait"]])
	return errs

# ---------- 查询助手 ----------
func get_wuxue(id: String) -> Dictionary: return wuxue.get(id, {})
func get_item(id: String) -> Dictionary: return items.get(id, {})
func get_npc(id: String) -> Dictionary: return npcs.get(id, {})
func get_quest(id: String) -> Dictionary: return quests.get(id, {})
func get_enemy(id: String) -> Dictionary: return enemies.get(id, {})
func get_formation(id: String) -> Dictionary: return formations.get(id, {})
func get_meridian(id: String) -> Dictionary: return meridians.get(id, {})
func get_trait(id: String) -> Dictionary: return traits.get(id, {})
func get_shop(id: String) -> Dictionary: return shops.get(id, {})
func get_map(id: String) -> Dictionary: return maps.get(id, {})
func get_faction(id: String) -> Dictionary: return factions.get(id, {})

func move_of(wuxue_id: String, idx: int) -> Dictionary:
	var w: Dictionary = get_wuxue(wuxue_id)
	var mv_arr: Array = w.get("moves", [])
	if idx >= 0 and idx < mv_arr.size():
		return mv_arr[idx]
	return {}

func grade_rank(g: String) -> int:
	return GRADE_ORDER.find(g)

func item_price(id: String) -> int:
	var it: Dictionary = get_item(id)
	return int(it.get("price", 0))

func shichen_name(idx: int) -> String:
	return SHICHEN[idx % 12]

func shichen_desc(idx: int) -> String:
	return SHICHEN_NAME.get(SHICHEN[idx % 12], "")
