extends Control
## TownView —— 城镇/野外行走：双轨移动（大侠式键盘 WASD 平滑移动 + 烟雨式点击/触屏 A* 寻路）、
## NPC、采集、隐藏点、出口、随机遭遇、事件；摄像机跟随（小图整图居中、大图跟人滚动）。

const PixelArt := preload("res://scripts/art/pixel_art.gd")
const ArtLib := preload("res://scripts/art/art_lib.gd")
const TouchControls := preload("res://scenes/views/touch_controls.gd")
const Pathfinding := preload("res://scripts/pathfinding.gd")

const S_TILE := 32                    # tile 渲染边长（px）
const MAP_ORIGIN := Vector2(96, 40)   # 地图在视口内的基准偏移
const MAP_VIEW := Vector2(864, 500)   # 地图可视区域（960×540 减去边距）
const WALK_SPEED := 6.0               # 平滑移动速度（格/秒）

var main: Node
var panels: Control
var touch: Control
var map_id := "village"
var map: Dictionary = {}
var px := 1
var py := 1
var facing := Vector2i(0, 1)
var pos_f := Vector2(1, 1)    # 连续渲染位置（格坐标浮点，双轨移动引擎）
var move_t := 1.0             # 当前步进度 0..1（>=1 站定）
var move_from := Vector2i.ZERO
var move_to := Vector2i.ZERO
var walk_queue: Array = []    # 点击寻路剩余路径（Vector2i 队列，不含已走格）
var cam := Vector2.ZERO       # 摄像机视图偏移（画布内滚动/居中量）
var cam_ready := false
var npc_positions := {}     # npc_id -> Vector2i
var anim_time := 0.0        # 角色动画时钟（秒，walk/idle 帧选取）
var busy := false           # 面板打开时禁移动
var canvas: Control         # 地图画布（成员：_process 需每帧 queue_redraw；局部变量会导致画面冻结在出生点）

func on_enter(p: Dictionary = {}) -> void:
	map_id = p.get("map", "village")
	map = GameDB.get_map(map_id)
	# 玩家落点：战斗/切磋归来恢复原位（payload.pos），否则出口附近或中心
	var spawn := _find_spawn()
	px = spawn.x
	py = spawn.y
	var pos: Array = p.get("pos", [])
	if pos.size() == 2 and _walkable(int(pos[0]), int(pos[1])):
		px = int(pos[0])
		py = int(pos[1])
	facing = Vector2i(0, 1)
	pos_f = Vector2(px, py)
	move_t = 1.0
	walk_queue.clear()
	cam_ready = false
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
	canvas = Control.new()
	canvas.name = "MapCanvas"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP   # 接收点击寻路（按钮/面板在其上层，不受影响）
	add_child(canvas)
	canvas.draw.connect(_draw_map.bind(canvas))
	canvas.gui_input.connect(_on_canvas_input)
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
	if not visible:
		return   # 隐藏时不吃输入不重绘（防大地图/战斗界面下 WASD 后台移动）
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_redraw()   # 核心修复：地图画布每帧重绘，否则玩家/地图冻结在出生点
	anim_time += delta
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
	_advance_step(delta)
	_update_camera(delta)
	# 双轨输入：键盘/虚拟方向键优先（接管即清除点击路径），否则继续走寻路队列
	if move_t >= 1.0:
		var dir := _input_dir()
		if dir != Vector2i.ZERO:
			walk_queue.clear()
			facing = dir
			_begin_step(Vector2i(px, py) + dir, dir)
		elif walk_queue.size() > 0:
			var nxt: Vector2i = walk_queue[0]
			var sd: Vector2i = nxt - Vector2i(px, py)
			if _begin_step(nxt, sd):
				facing = sd
				walk_queue.pop_front()
			else:
				walk_queue.clear()   # 路径被堵（NPC 占位变化等），就地放弃
		# 动作键：站定响应，just_pressed 防长按连发
		if Input.is_action_just_pressed("interact"):
			_interact()
		elif Input.is_action_just_pressed("menu"):
			panels.status_panel()
		elif Input.is_action_just_pressed("craft"):
			panels.craft_panel()
		elif Input.is_action_just_pressed("save"):
			_save_and_sync()
	_refresh_hud()

## 保存并触发云端自动同步（F5 与触屏「保存」共用）
func _save_and_sync() -> void:
	if SaveSystem.save_game():
		main.toast_panel("已保存。")
		CloudSync.auto_push()

## 触屏按钮入口（与键位等价：interact=E，menu=M，craft=C，save=F5）
func touch_action(a: String) -> void:
	if busy or map == {} or move_t < 1.0:
		return
	match a:
		"interact":
			_interact()
		"menu":
			panels.status_panel()
		"craft":
			panels.craft_panel()
		"save":
			_save_and_sync()
	_refresh_hud()

# ---------- 双轨移动引擎 ----------

## 当前键盘/虚拟方向键输入（8 向：两键同按取对角）
func _input_dir() -> Vector2i:
	var v := Vector2i.ZERO
	if Input.is_action_pressed("move_up"):
		v.y -= 1
	if Input.is_action_pressed("move_down"):
		v.y += 1
	if Input.is_action_pressed("move_left"):
		v.x -= 1
	if Input.is_action_pressed("move_right"):
		v.x += 1
	if v == Vector2i.ZERO and touch != null and is_instance_valid(touch):
		v = touch.get_dir()
	return v

## 开始一步：to 为目标格。对角步需两侧正交格均可走（防穿墙角，与 A* 规则一致）
func _begin_step(to: Vector2i, dir: Vector2i) -> bool:
	if absi(dir.x) == 1 and absi(dir.y) == 1:
		if not (_walkable(px + dir.x, py) and _walkable(px, py + dir.y)):
			return false
	if not _walkable(to.x, to.y):
		return false
	move_from = Vector2i(px, py)
	move_to = to
	move_t = 0.0
	return true

## 推进当前步；到格时触发踏点副作用（野外耗时/遭遇/事件踏点）
func _advance_step(delta: float) -> void:
	if move_t >= 1.0:
		return
	move_t = minf(1.0, move_t + delta * WALK_SPEED)
	pos_f = Vector2(move_from).lerp(Vector2(move_to), move_t)
	if move_t >= 1.0:
		px = move_to.x
		py = move_to.y
		pos_f = Vector2(px, py)
		_enter_cell()

## 踏入新格的副作用（原 _try_move 的游戏逻辑部分）
func _enter_cell() -> void:
	if map.get("id", "") in ["wild_north", "wild_west"]:
		GameState.advance_time(1)
		_random_encounter_check()
	for ev in map.get("events", []):
		if Vector2i(ev["pos"][0], ev["pos"][1]) == Vector2i(px, py) and _event_require_ok(ev):
			panels.event_prompt(ev)
			break

# ---------- 摄像机 ----------

func _map_px_size() -> Vector2:
	var g: Array = map.get("grid", [])
	if g.is_empty():
		return Vector2.ZERO
	return Vector2(str(g[0]).length(), g.size()) * float(S_TILE)

## 小图整图居中，大图跟随玩家并夹在地图边界内
func _update_camera(delta: float) -> void:
	var ms := _map_px_size()
	if ms == Vector2.ZERO:
		return
	var target: Vector2
	if ms.x <= MAP_VIEW.x:
		target.x = (ms.x - MAP_VIEW.x) / 2.0
	else:
		target.x = clampf((pos_f.x + 0.5) * S_TILE - MAP_VIEW.x / 2.0, 0.0, ms.x - MAP_VIEW.x)
	if ms.y <= MAP_VIEW.y:
		target.y = (ms.y - MAP_VIEW.y) / 2.0
	else:
		target.y = clampf((pos_f.y + 0.5) * S_TILE - MAP_VIEW.y / 2.0, 0.0, ms.y - MAP_VIEW.y)
	if not cam_ready:
		cam = target
		cam_ready = true
		return
	cam = cam.lerp(target, 1.0 - exp(-8.0 * delta))

# ---------- 点击寻路（烟雨式） ----------

func _on_canvas_input(ev: InputEvent) -> void:
	if busy or map == {}:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_request_path(_local_to_cell(ev.position))
	elif ev is InputEventScreenTouch and ev.pressed:
		_request_path(_local_to_cell(ev.position))

func _local_to_cell(local: Vector2) -> Vector2i:
	var p := local - MAP_ORIGIN + cam
	return Vector2i(int(floor(p.x / float(S_TILE))), int(floor(p.y / float(S_TILE))))

## 点哪走哪；点到不可走格（如 NPC/建筑）时自动改走其相邻可走格
func _request_path(target: Vector2i) -> void:
	var g: Array = map.get("grid", [])
	if g.is_empty():
		return
	var h: int = g.size()
	var w: int = str(g[0]).length()
	if target.x < 0 or target.y < 0 or target.x >= w or target.y >= h:
		return
	var start := Vector2i(roundi(pos_f.x), roundi(pos_f.y))
	if target == start:
		return
	if not _walkable(target.x, target.y):
		var alt := Vector2i(-1, -1)
		var best := 1 << 30
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var c: Vector2i = target + d
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or not _walkable(c.x, c.y):
				continue
			var dist: int = absi(c.x - start.x) + absi(c.y - start.y)
			if dist < best:
				best = dist
				alt = c
		if alt.x < 0:
			return
		target = alt
	var path: Array = Pathfinding.find_path(w, h, _walkable, start, target, true)
	if not path.is_empty():
		walk_queue = path

func _draw_map(cv: Control) -> void:
	var g: Array = map.get("grid", [])
	var off := MAP_ORIGIN - cam
	# —— 地面层（Jianghu 草地/石板/水渠 + Guishan 石面墙带/土面） ——
	for y in g.size():
		var row := str(g[y])
		for x in row.length():
			var kind := ArtLib.ground_kind(row[x])
			var gtex: Texture2D = ArtLib.ground_tex(kind, x, y)
			var r := Rect2(off.x + x * S_TILE, off.y + y * S_TILE, S_TILE, S_TILE)
			if gtex != null:
				cv.draw_texture_rect(gtex, r, false)
			else:
				cv.draw_rect(r, _fallback_ground_color(kind))
	# —— 地面标记（采集/隐藏/事件/寻路目标） ——
	for ga in map.get("gathers", []):
		var pos: Array = ga["pos"]
		var ready: bool = GameState.can_gather(ga["id"])
		cv.draw_circle(off + Vector2(pos[0] * S_TILE + 16, pos[1] * S_TILE + 8), 5.0, Color("7ab86a") if ready else Color("4a5a50"))
	for h in map.get("hiddens", []):
		if _hidden_visible(h):
			var hp2: Array = h["pos"]
			cv.draw_circle(off + Vector2(hp2[0] * S_TILE + 16, hp2[1] * S_TILE + 24), 4.0, Color("c9a067"))
	for ev in map.get("events", []):
		if _event_require_ok(ev):
			var ep: Array = ev["pos"]
			cv.draw_circle(off + Vector2(ep[0] * S_TILE + 16, ep[1] * S_TILE + 16), 7.0, Color("c95a5a"))
	if walk_queue.size() > 0:
		var tail: Vector2i = walk_queue[walk_queue.size() - 1]
		cv.draw_arc(off + (Vector2(tail) + Vector2(0.5, 0.5)) * S_TILE, 9.0, 0.0, TAU, 20, Color("c9a067"), 2.0)
	# —— 实体层：组件/装饰/NPC/玩家 按 y 深度画家算法（走 到房后被屋顶遮挡） ——
	var ents: Array = []   # {depth: float, tex, pos: Vector2, shadow_foot: Vector2(空=无影)}
	for y in g.size():
		var row := str(g[y])
		for x in row.length():
			var pname := ArtLib.prop_for(row[x], x, y)
			if pname == "":
				continue
			var ptex: Texture2D = ArtLib.prop_tex(pname)
			if ptex == null:
				continue
			var pos := Vector2(off.x + x * S_TILE + S_TILE / 2.0 - ptex.get_width() / 2.0, off.y + (y + 1) * S_TILE - ptex.get_height())
			ents.append({"depth": y + 0.5, "tex": ptex, "pos": pos, "shadow_foot": Vector2.ZERO})
	for d in ArtLib.map_decor(map_id):
		var dtex: Texture2D = ArtLib.prop_tex(str(d.get("prop", "")))
		if dtex == null:
			continue
		var c: Vector2 = d.get("cell", Vector2.ZERO)
		var dpos := Vector2(off.x + c.x * S_TILE + S_TILE / 2.0 - dtex.get_width() / 2.0, off.y + (c.y + 1) * S_TILE - dtex.get_height())
		ents.append({"depth": float(d.get("depth", c.y + 0.4)), "tex": dtex, "pos": dpos, "shadow_foot": Vector2.ZERO})
	# NPC（程序化村民 4 向；朝向按格位确定性散布，静立首帧）
	var fnt := get_tree().root.theme.default_font
	var npc_labels: Array = []
	for nid in npc_positions:
		var p2: Vector2i = npc_positions[nid]
		var dir4: String = ["down", "left", "right", "up"][ArtLib.cell_rand(p2.x, p2.y, 5) % 4]
		var ntex: Texture2D = ArtLib.traveler_frame(dir4, 0)
		var foot := Vector2(off.x + p2.x * S_TILE + S_TILE / 2.0, off.y + (p2.y + 1) * S_TILE - 2.0)
		if ntex != null:
			ents.append({"depth": p2.y + 0.9, "tex": ntex,
				"pos": foot - Vector2(8.0, 23.0), "shadow_foot": foot})
		else:
			ents.append({"depth": p2.y + 0.9, "tex": null,
				"pos": foot - Vector2(8.0, 22.0), "shadow_foot": foot,
				"fallback": ArtLib.cell_rand(p2.x, p2.y, 9) % 4})
		npc_labels.append({"name": GameDB.get_npc(nid).get("name", "?"), "foot": foot})
	# 玩家（Jianghu 剑客 8 向 walk/idle）
	var dir8: String = ArtLib.dir8_of(facing)
	var anim := "walk" if move_t < 1.0 else "idle"
	var info := ArtLib.anim_info("swordsman", anim)
	var fps := float(info.get("fps", 5)) if info.size() > 0 else 5.0
	var pframe := int(anim_time * fps)
	var ptex2: Texture2D = ArtLib.char_frame("swordsman", anim, dir8, pframe)
	var pfoot := Vector2(off.x + pos_f.x * S_TILE + S_TILE / 2.0, off.y + (pos_f.y + 1.0) * S_TILE - 2.0)
	if ptex2 != null:
		var p_foot_off := ArtLib.char_foot("swordsman", anim)
		ents.append({"depth": pos_f.y + 0.9, "tex": ptex2,
			"pos": pfoot - p_foot_off, "shadow_foot": pfoot})
	else:
		ents.append({"depth": pos_f.y + 0.9, "tex": null,
			"pos": pfoot - Vector2(12.0, 30.0), "shadow_foot": pfoot, "fallback": 4})
	ents.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))
	for e in ents:
		var foot2: Vector2 = e["shadow_foot"]
		if foot2 != Vector2.ZERO:
			cv.draw_set_transform(foot2, 0.0, Vector2(1.0, 0.4))
			cv.draw_circle(Vector2.ZERO, 5.0, Color(0, 0, 0, 0.22))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tex2: Texture2D = e["tex"]
		if tex2 != null:
			cv.draw_texture_rect(tex2, Rect2(e["pos"], tex2.get_size()), false)
		elif e.has("fallback"):
			cv.draw_rect(Rect2(e["pos"], Vector2(16, 24)), _fallback_body_color(int(e["fallback"])))
	# —— 名牌（最上层，保证可读） ——
	for lb in npc_labels:
		cv.draw_string(fnt, lb["foot"] + Vector2(-20, 12), str(lb["name"]), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color("e8e0d0"))

func _fallback_ground_color(kind: String) -> Color:
	match kind:
		"slab":
			return Color("b8a88a")
		"water":
			return Color("3a6a8a")
		"stone":
			return Color("5a5a62")
		"earth":
			return Color("9a7a58")
		_:
			return Color("6a8a4a")

func _fallback_body_color(i: int) -> Color:
	return [Color("3a6a8a"), Color("8a6a4a"), Color("b8a04a"), Color("6a8ab8"), Color("c9a067")][i % 5]

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
	var payload := {"name": sq.get("name", "遭遇"), "enemies": sq["units"], "formation": GameState.formation, "back": "town", "map": map_id, "pos": [px, py]}
	call_deferred("_goto_battle", payload)

func _goto_battle(payload: Dictionary) -> void:
	main.switch_to("battle", payload)

func start_spar(npc_id: String) -> void:
	var payload := {"name": "切磋·" + GameDB.get_npc(npc_id).get("name", npc_id), "enemies": [{"enemy": "n_" + npc_id, "pos": [1, 0]}], "spar": true, "spar_npc": npc_id, "formation": GameState.formation, "back": "town", "map": map_id, "pos": [px, py]}
	main.switch_to("battle", payload)

func start_custom_battle(units_cfg: Dictionary, eid: String) -> void:
	GameState.flags["event_done_" + eid] = true
	var payload := {"name": "宿命之战", "enemies": units_cfg.get("units", []), "formation": GameState.formation, "back": "town", "map": map_id, "event": eid, "pos": [px, py]}
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
		hint.text = "WASD/方向键/点击移动 · E/空格 交互 · M 行囊 · C 炼制 · F5 保存 · 山门=出口" + extra
		if touch != null and is_instance_valid(touch) and touch.visible:
			hint.text = "触屏：方向键/点按地面移动 · 右下按钮操作" + extra
