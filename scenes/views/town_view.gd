extends Control
## TownView —— 城镇/野外 tile 行走：移动、NPC、采集、隐藏点、出口、随机遭遇、事件

const PixelArt := preload("res://scripts/art/pixel_art.gd")
const TouchControls := preload("res://scenes/views/touch_controls.gd")

var main: Node
var panels: Control
var touch: Control
var map_id := "village"
var map: Dictionary = {}
var px := 1
var py := 1
var facing := Vector2i(0, 1)
var move_cd := 0.0
var npc_positions := {}     # npc_id -> Vector2i
var tiles: Dictionary = {}
var char_tex: Dictionary = {}
var npc_tex: Dictionary = {}
var busy := false           # 面板打开时禁移动

func on_enter(p: Dictionary = {}) -> void:
	map_id = p.get("map", "village")
	map = GameDB.get_map(map_id)
	tiles = PixelArt.gen_tiles()
	char_tex = PixelArt.gen_char(11, Color("3a6a8a"))
	npc_tex.clear()
	# 玩家落点：出口附近或中心
	var spawn := _find_spawn()
	px = spawn.x
	py = spawn.y
	facing = Vector2i(0, 1)
	busy = false
	rebuild()

func _find_spawn() -> Vector2i:
	var g: Array = map.get("grid", [])
	for y in g.size():
		for x in str(g[y]).length():
			if str(g[y])[x] in ["=", "."]:
				return Vector2i(x, y)
	return Vector2i(1, 1)

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	busy = false
	var bg := ColorRect.new()
	bg.color = Color("0a0d14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var canvas := Control.new()
	canvas.position = Vector2(96, 40)
	add_child(canvas)
	canvas.draw.connect(_draw_map.bind(canvas))
	# NPC 位置表（NPC 定义于 npcs.json：map/pos）
	npc_positions.clear()
	for nid in GameDB.npcs:
		var nd: Dictionary = GameDB.npcs[nid]
		if nd.get("map", "") == map_id:
			var pos: Array = nd.get("pos", [1, 1])
			npc_positions[nid] = Vector2i(int(pos[0]), int(pos[1]))
	# 面板层
	panels = preload("res://scenes/views/panels.gd").new()
	panels.set("main", main)
	panels.set("town", self)
	add_child(panels)
	# HUD
	var hud := Label.new()
	hud.name = "HUD"
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 14)
	add_child(hud)
	var hint := Label.new()
	hint.name = "HINT"
	hint.position = Vector2(12, 514)
	hint.add_theme_color_override("font_color", Color("6a7a8a"))
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	# 触屏虚拟操控层（仅触屏/移动端显示）
	touch = TouchControls.new()
	touch.name = "TouchControls"
	touch.town = self
	add_child(touch)
	_refresh_hud()

func _process(delta: float) -> void:
	move_cd -= delta
	if panels != null and panels.get_child_count() > 0:
		busy = true
	else:
		busy = false
	if busy or map == {}:
		if touch != null and is_instance_valid(touch):
			touch.held_dir = Vector2i.ZERO   # 面板打开时清掉按住的方向，防粘键
		return
	if Input.is_key_pressed(KEY_ESCAPE):
		return
	var dir := Vector2i.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir = Vector2i(0, -1)
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir = Vector2i(0, 1)
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir = Vector2i(-1, 0)
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir = Vector2i(1, 0)
	if dir == Vector2i.ZERO and touch != null and is_instance_valid(touch):
		dir = touch.get_dir()
	if dir != Vector2i.ZERO and move_cd <= 0.0:
		facing = dir
		_try_move(dir)
		move_cd = 0.14
		_refresh_hud()
	if move_cd <= 0.0:
		if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE):
			move_cd = 0.25
			_interact()
		elif Input.is_key_pressed(KEY_M):
			move_cd = 0.3
			panels.status_panel()
		elif Input.is_key_pressed(KEY_C):
			move_cd = 0.3
			panels.craft_panel()
		elif Input.is_key_pressed(KEY_F5):
			move_cd = 0.5
			_save_and_sync()
		_refresh_hud()

## 保存并触发云端自动同步（F5 与触屏「保存」共用）
func _save_and_sync() -> void:
	if SaveSystem.save_game():
		main.toast_panel("已保存。")
		CloudSync.auto_push()

## 触屏按钮入口（与键位等价：interact=E，menu=M，craft=C，save=F5）
func touch_action(a: String) -> void:
	if busy or map == {} or move_cd > 0.0:
		return
	match a:
		"interact":
			move_cd = 0.25
			_interact()
		"menu":
			move_cd = 0.3
			panels.status_panel()
		"craft":
			move_cd = 0.3
			panels.craft_panel()
		"save":
			move_cd = 0.5
			_save_and_sync()
	_refresh_hud()

func _draw_map(cv: Control) -> void:
	var g: Array = map.get("grid", [])
	var S := 32  # 渲染尺寸（16px 素材放大2倍）
	for y in g.size():
		var row := str(g[y])
		for x in row.length():
			var ch := row[x]
			var tex: ImageTexture = tiles.get(ch, tiles["."])
			cv.draw_texture_rect(tex, Rect2(x * S, y * S, S, S), false)
	# 采集点标记
	for ga in map.get("gathers", []):
		var pos: Array = ga["pos"]
		var ready: bool = GameState.can_gather(ga["id"])
		cv.draw_circle(Vector2(pos[0] * S + 16, pos[1] * S + 8), 5.0, Color("7ab86a") if ready else Color("4a5a50"))
	# 隐藏点（若条件可见则闪金光）
	for h in map.get("hiddens", []):
		if _hidden_visible(h):
			var hp2: Array = h["pos"]
			cv.draw_circle(Vector2(hp2[0] * S + 16, hp2[1] * S + 24), 4.0, Color("c9a067"))
	# 事件标记
	for ev in map.get("events", []):
		if _event_require_ok(ev):
			var ep: Array = ev["pos"]
			cv.draw_circle(Vector2(ep[0] * S + 16, ep[1] * S + 16), 7.0, Color("c95a5a"))
	# NPC
	for nid in npc_positions:
		var p2: Vector2i = npc_positions[nid]
		if not npc_tex.has(nid):
			var col := Color("8a6a4a")
			var role: String = GameDB.get_npc(nid).get("role", "闲人")
			col = {"任务": Color("6a8ab8"), "随从": Color("8a6ab8"), "杂货": Color("b8a04a"), "药铺": Color("7ab86a"),
				"武器": Color("b86a4a"), "酒馆": Color("b88a4a"), "门派": Color("4a9ad8"), "黑市": Color("6a5a8a"), "奇遇": Color("c98a3a")}.get(role, col)
			npc_tex[nid] = PixelArt.gen_char(nid.hash() & 0xffff, col)
		var frame := (1 if int(Time.get_ticks_msec() / 500.0) % 2 == 0 else 0)
		cv.draw_texture_rect(npc_tex[nid]["d" + str(frame)], Rect2(p2.x * S + 4, p2.y * S - 6, 24, 32), false)
		var nname: String = GameDB.get_npc(nid).get("name", "?")
		var fnt := get_tree().root.theme.default_font
		cv.draw_string(fnt, Vector2(p2.x * S - 4, p2.y * S + 26), nname, HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color("c9d4e0"))
	# 玩家
	var pd := "d"
	if facing == Vector2i(0, -1): pd = "u"
	elif facing == Vector2i(-1, 0): pd = "l"
	elif facing == Vector2i(1, 0): pd = "r"
	var pframe := (1 if int(Time.get_ticks_msec() / 250.0) % 2 == 0 else 0) if move_cd > 0.02 else 0
	cv.draw_texture_rect(char_tex[pd + str(pframe)], Rect2(px * S + 4, py * S - 6, 24, 32), false)

func _walkable(x: int, y: int) -> bool:
	var g: Array = map.get("grid", [])
	if y < 0 or y >= g.size() or x < 0 or x >= str(g[y]).length():
		return false
	var ch := str(g[y])[x]
	if not PixelArt.is_walkable(ch):
		return false
	for nid in npc_positions:
		if npc_positions[nid] == Vector2i(x, y):
			return false
	return true

func _try_move(dir: Vector2i) -> void:
	var nx := px + dir.x
	var ny := py + dir.y
	if _walkable(nx, ny):
		px = nx
		py = ny
		if map.get("id", "") in ["wild_north", "wild_west"]:
			GameState.advance_time(1)
			_random_encounter_check()
		# 事件踏点检查
		for ev in map.get("events", []):
			if Vector2i(ev["pos"][0], ev["pos"][1]) == Vector2i(px, py) and _event_require_ok(ev):
				panels.event_prompt(ev)
				break

func _interact() -> void:
	# 先看面前，再看脚下
	var tx := px + facing.x
	var ty := py + facing.y
	# NPC
	for nid in npc_positions:
		var np: Vector2i = npc_positions[nid]
		if np == Vector2i(tx, ty) or np == Vector2i(px, py):
			var n: Dictionary = GameDB.get_npc(nid)
			if n.has("hours") and not (n["hours"] as Array).has(GameDB.shichen_name(GameState.shichen)):
				main.toast_panel("%s此刻不在（%s才在）。" % [n.get("name", nid), "、".join(n["hours"])])
				return
			if n.get("night_only", false) and not GameState.shichen in [0, 1]:
				main.toast_panel("%s只在子时与丑时出没。" % n.get("name", nid))
				return
			panels.npc_dialog(nid)
			return
	# 采集
	for ga in map.get("gathers", []):
		if Vector2i(ga["pos"][0], ga["pos"][1]) == Vector2i(px, py):
			var out: Dictionary = GameState.do_gather(ga["id"])
			main.toast_panel(out.get("msg", "一无所获。"))
			return
	# 隐藏点
	for h in map.get("hiddens", []):
		var hp2 := Vector2i(h["pos"][0], h["pos"][1])
		if hp2 == Vector2i(tx, ty) or hp2 == Vector2i(px, py):
			_open_hidden(h)
			return
	# 出口
	var g: Array = map.get("grid", [])
	if ty < g.size() and tx < str(g[ty]).length() and str(g[ty])[tx] == "d":
		main.switch_to("world")
		return

func _hidden_visible(h: Dictionary) -> bool:
	var cond: Dictionary = h.get("condition", {})
	if cond.has("faction"):
		return GameState.faction == cond["faction"]
	if cond.has("quest"):
		return GameState.quest_state(cond["quest"]) in ["active", "done"]
	if cond.has("affinity"):
		var a: Dictionary = cond["affinity"]
		return GameState.get_affinity(a["npc"]) >= int(a["gte"])
	if cond.has("counter"):
		var c: Dictionary = cond["counter"]
		return int(GameState.counters.get(c["key"], 0)) >= int(c["gte"])
	return true

func _open_hidden(h: Dictionary) -> void:
	if not _hidden_visible(h):
		main.toast_panel("这里似乎有些什么，但暂时无法探究。")
		return
	if GameState.flags.get("hidden_" + h["id"], false):
		main.toast_panel("此处已被你翻找过了。")
		return
	GameState.flags["hidden_" + h["id"]] = true
	var got := []
	for iid in h.get("items", {}):
		GameState.add_item(iid, int(h["items"][iid]))
		GameState.learn_book(iid)
		got.append("【%s】×%d" % [GameDB.get_item(iid).get("name", iid), int(h["items"][iid])])
	if h.has("money"):
		GameState.add_money(int(h["money"]))
		got.append("%d 文铜钱" % int(h["money"]))
	GameState.quest_hook({"type": "hidden", "id": h["id"]})
	main.toast_panel("发现「%s」：%s！" % [h.get("name", ""), "、".join(got) if got.size() > 0 else "空无一物"])

func _event_require_ok(ev: Dictionary) -> bool:
	var req: Dictionary = ev.get("require", {})
	if req.has("quest") and GameState.quest_state(req["quest"]) != "active":
		return false
	if req.has("step_gte") and GameState.quest_step(req["quest"]) < int(req["step_gte"]):
		return false
	if req.has("item") and GameState.count_item(req["item"]) <= 0:
		return false
	if GameState.flags.get("event_done_" + ev.get("id", ""), false):
		return false
	return true

func _random_encounter_check() -> void:
	if randf() > 0.16:
		return
	var squads: Array = map.get("squads", [])
	if squads.is_empty():
		return
	var sq: Dictionary = squads[randi() % squads.size()]
	main.toast_panel("「%s」拦住了去路！" % sq.get("name", "敌人"))
	var payload := {"name": sq.get("name", "遭遇"), "enemies": sq["units"], "formation": GameState.formation, "back": "town", "map": map_id}
	call_deferred("_goto_battle", payload)

func _goto_battle(payload: Dictionary) -> void:
	main.switch_to("battle", payload)

func start_spar(npc_id: String) -> void:
	var payload := {"name": "切磋·" + GameDB.get_npc(npc_id).get("name", npc_id), "enemies": [{"enemy": "n_" + npc_id, "pos": [1, 0]}], "spar": true, "spar_npc": npc_id, "formation": GameState.formation, "back": "town", "map": map_id}
	main.switch_to("battle", payload)

func start_custom_battle(units_cfg: Dictionary, eid: String) -> void:
	GameState.flags["event_done_" + eid] = true
	var payload := {"name": "宿命之战", "enemies": units_cfg.get("units", []), "formation": GameState.formation, "back": "town", "map": map_id, "event": eid}
	main.switch_to("battle", payload)

func resume() -> void:
	_refresh_hud()

func _refresh_hud() -> void:
	var hud: Label = get_node_or_null("HUD")
	if hud == null: return
	var p: Dictionary = GameState.get_panel()
	hud.text = "%s Lv%d  气血%d/%d  内力%d/%d  真气%d  %s·%s  铜钱%d·银两%d  阵法:%s" % [
		GameState.player_name, GameState.lv, GameState.hp, p["hp_max"], GameState.mp, p["mp_max"], GameState.zhenqi,
		"第%d日" % GameState.day, GameState.shichen_str(), GameState.money_tong, GameState.money_yin,
		GameDB.get_formation(GameState.formation).get("name", "")]
	var hint: Label = get_node_or_null("HINT")
	if hint:
		var extra := ""
		if not map.get("gathers", []).is_empty():
			extra += "  绿点=采集"
		if map.get("events", []).size() > 0:
			extra += "  红点=事件"
		hint.text = "WASD/方向键移动 · E/空格 交互 · M 行囊 · C 炼制 · F5 保存 · 出口=金色门" + extra
		if touch != null and is_instance_valid(touch) and touch.visible:
			hint.text = "触屏：左下方向键移动 · 右下按钮操作" + extra
	queue_redraw()
