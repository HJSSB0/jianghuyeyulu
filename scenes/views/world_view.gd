extends Control
## 大地图：节点行进（烟雨章节解锁式）+ 移动耗时 + 野外遭遇

var main: Node
var cur_node := "village"
var hud: Label
var status_hint: Label
const NODE_R := 16.0

func on_enter(p: Dictionary = {}) -> void:
	if p.has("node"):
		cur_node = p["node"]
	rebuild()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("10141f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "江湖行 · 大地图"
	title.add_theme_font_size_override("font_size", 20)
	title.position = Vector2(24, 12)
	add_child(title)

	hud = Label.new()
	hud.position = Vector2(24, 44)
	hud.add_theme_color_override("font_color", Color("9aa8bc"))
	add_child(hud)

	# 连线（节点坐标统一缩放：y 压至 0.62 防溢出）
	var lines := Control.new()
	lines.position = Vector2.ZERO
	lines.size = Vector2(960, 540)
	add_child(lines)
	lines.draw.connect(func():
		for e in GameDB.world["edges"]:
			var a: Dictionary = GameDB.world["nodes"][e["a"]]
			var b: Dictionary = GameDB.world["nodes"][e["b"]]
			var unlocked: bool = _node_unlocked(e["a"]) and _node_unlocked(e["b"])
			lines.draw_line(_np(a), _np(b), Color("3a4a5f") if unlocked else Color("232833"), 2.0))

	# 节点
	for nid in GameDB.world["nodes"]:
		var nd: Dictionary = GameDB.world["nodes"][nid]
		var unlocked := _node_unlocked(nid)
		var btn := Button.new()
		btn.text = nd["name"] if unlocked else "？？"
		var center := _np(nd)
		btn.position = center - Vector2(50, 14)
		btn.size = Vector2(100, 28)
		btn.disabled = not unlocked
		var is_cur: bool = nid == cur_node
		var is_adj: bool = _adjacent(nid)
		btn.add_theme_font_size_override("font_size", 13)
		btn.modulate = Color(1, 1, 1) if not is_cur else Color("c9a067")
		if is_adj and unlocked and nid != cur_node:
			btn.text = "→ " + btn.text
		btn.pressed.connect(func(): _travel(nid))
		add_child(btn)

	var desc := Label.new()
	var cd: Dictionary = GameDB.world["nodes"][cur_node]
	desc.text = "【%s】%s" % [cd["name"], cd.get("desc", "")]
	desc.position = Vector2(24, 470)
	desc.add_theme_font_size_override("font_size", 14)
	add_child(desc)

	status_hint = Label.new()
	status_hint.text = "点击相邻地名行进（消耗时辰）。"
	status_hint.position = Vector2(24, 500)
	status_hint.add_theme_color_override("font_color", Color("6a7a8a"))
	status_hint.add_theme_font_size_override("font_size", 12)
	add_child(status_hint)

	var enter_b := Button.new()
	enter_b.text = "进 入 此 地"
	enter_b.position = Vector2(820, 490)
	enter_b.size = Vector2(120, 36)
	enter_b.pressed.connect(_enter_node)
	add_child(enter_b)
	_refresh_hud()

func _np(nd: Dictionary) -> Vector2:
	return Vector2(120 + float(nd["pos"][0]), 70 + float(nd["pos"][1]) * 0.62)

func _refresh_hud() -> void:
	hud.text = "%s · 第%d日 %s · %s · 等级%d · 铜钱%d" % [
		GameState.player_name, GameState.day, GameState.shichen_str(),
		GameState.fame_name(), GameState.lv, GameState.money_total()]

func _node_unlocked(nid: String) -> bool:
	var nd: Dictionary = GameDB.world["nodes"][nid]
	var u: Dictionary = nd.get("unlock", {})
	if u.has("quest"):
		return GameState.quest_state(u["quest"]) in ["active", "done"]
	return true

func _adjacent(nid: String) -> bool:
	for e in GameDB.world["edges"]:
		if (e["a"] == cur_node and e["b"] == nid) or (e["b"] == cur_node and e["a"] == nid):
			return true
	return false

func _travel(nid: String) -> void:
	if not _adjacent(nid) or not _node_unlocked(nid):
		return
	var cost := 2
	for e in GameDB.world["edges"]:
		if (e["a"] == cur_node and e["b"] == nid) or (e["b"] == cur_node and e["a"] == nid):
			cost = int(e.get("cost", 2))
			break
	# 烟波步等旅行加速
	var travel_bonus: int = int(GameState.get_all_mods().get("travel", 0))
	cost = maxi(1, cost - travel_bonus)
	GameState.advance_time(cost * 4)
	cur_node = nid
	main.toast_panel("行至【%s】，途中耗时 %d 个时辰。" % [GameDB.world["nodes"][nid]["name"], cost])
	# 野外节点随机遭遇
	var nd: Dictionary = GameDB.world["nodes"][nid]
	if nid in ["wild_north", "wild_west"] and GameState.fame >= 1 and randf() < 0.25:
		_ambush(nid)
		return
	rebuild()

func _ambush(nid: String) -> void:
	var m: Dictionary = GameDB.get_map(nid)
	var squads: Array = m.get("squads", [])
	if squads.is_empty():
		rebuild()
		return
	var sq: Dictionary = squads[randi() % squads.size()]
	var payload := {"name": sq.get("name", "遭遇"), "enemies": sq["units"], "formation": GameState.formation, "back": "world", "node": nid}
	main.switch_to("battle", payload)

func _enter_node() -> void:
	var nd: Dictionary = GameDB.world["nodes"][cur_node]
	GameState.quest_hook({"type": "visit", "map": nd.get("map", cur_node)})
	main.switch_to("town", {"map": nd.get("map", cur_node)})
