extends Control
## BattleView —— 大侠立志传式战棋演出：9×7 网格战场 + ATB 时序条 + 战意 + 招式面板 + 日志。
## 操作：我方就绪后选招式 → 点蓝格走位 → 点红格出手；右键/取消按钮返回招式列表。

const ArtLib := preload("res://scripts/art/art_lib.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

const CELL := 50.0
const BOARD_X := 44.0
const BOARD_Y := 58.0

var main: Node
var canvas: Control
var atb_bar: Control
var log_rt: RichTextLabel
var move_box: VBoxContainer
var auto_toggle: Button
var turn_label: Label
var battle_name := "遭遇战"
var back_to := "world"
var back_payload := {}
var waiting_input := false
var auto := false
var anim_time := 0.0
var sel_move := -1          # 已选招式（目标选择中）
var target_mode := false
var cursor := Vector2i(-1, -1)
var moved_this_turn := false
var render_pos := {}        # 单位 id → 渲染像素位（滑行补间）
var floaters: Array = []    # 伤害飘字 {pos, txt, col, age}
var slashes: Array = []     # 刀光弧 {a, b, age}
var flash: Dictionary = {}  # 单位 id → 受击闪白年龄

func on_enter(p: Dictionary = {}) -> void:
	battle_name = p.get("name", "遭遇战")
	back_to = p.get("back", "world")
	back_payload = p
	Battle.setup(p)
	auto = false
	sel_move = -1
	target_mode = false
	cursor = Vector2i(-1, -1)
	rebuild()
	_step()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("12100c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "⚔ " + battle_name + (String("（阵法：%s）" % GameDB.get_formation(Battle.formation).get("name", "")))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.C_GOLD)
	title.position = Vector2(16, 8)
	add_child(title)
	# 战场画布
	canvas = Control.new()
	canvas.position = Vector2(BOARD_X, BOARD_Y)
	canvas.size = Vector2(Battle.GRID_W * CELL, Battle.GRID_H * CELL)
	add_child(canvas)
	canvas.draw.connect(_draw_field)
	canvas.gui_input.connect(_on_canvas_input)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	# ATB 条
	atb_bar = Control.new()
	atb_bar.position = Vector2(BOARD_X, 414)
	atb_bar.size = Vector2(Battle.GRID_W * CELL, 40)
	add_child(atb_bar)
	atb_bar.draw.connect(_draw_atb)
	# 日志
	log_rt = RichTextLabel.new()
	log_rt.position = Vector2(620, 60)
	log_rt.size = Vector2(320, 300)
	log_rt.scroll_following = true
	log_rt.add_theme_font_size_override("normal_font_size", 13)
	log_rt.add_theme_color_override("default_color", UITheme.C_TEXT)
	add_child(log_rt)
	# 招式面板
	var panel := PanelContainer.new()
	panel.position = Vector2(BOARD_X, 458)
	panel.size = Vector2(Battle.GRID_W * CELL, 78)
	add_child(panel)
	move_box = VBoxContainer.new()
	panel.add_child(move_box)
	# 右下控制
	auto_toggle = Button.new()
	auto_toggle.text = "自动战斗：关"
	auto_toggle.position = Vector2(620, 380)
	auto_toggle.size = Vector2(150, 30)
	auto_toggle.pressed.connect(func():
		auto = not auto
		auto_toggle.text = "自动战斗：%s" % ("开" if auto else "关"))
	add_child(auto_toggle)
	var flee := Button.new()
	flee.text = "撤退"
	flee.position = Vector2(790, 380)
	flee.size = Vector2(80, 30)
	flee.pressed.connect(_try_flee)
	add_child(flee)
	var cancel := Button.new()
	cancel.text = "取消选择"
	cancel.position = Vector2(620, 416)
	cancel.size = Vector2(150, 28)
	cancel.pressed.connect(_cancel_targeting)
	add_child(cancel)
	turn_label = Label.new()
	turn_label.position = Vector2(620, 452)
	turn_label.add_theme_color_override("font_color", UITheme.C_GOLD)
	add_child(turn_label)
	var hint := Label.new()
	hint.text = "战棋：选招式 → 蓝格走位 → 红格出手 · 侧击+15% 背击+25% · 战意100绝招/200必爆"
	hint.position = Vector2(620, 508)
	hint.add_theme_color_override("font_color", Color("6a5a44"))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)
	_log_flush()

func _process(_d: float) -> void:
	if not visible or canvas == null:
		return
	anim_time += _d
	_drain_fx()
	_step_fx(_d)
	if Battle.finished:
		_finish()
		set_process(false)
		return
	canvas.queue_redraw()
	atb_bar.queue_redraw()
	turn_label.text = _status_line()
	# 键盘光标（我方目标选择中）
	if waiting_input and target_mode:
		var dir := Vector2i.ZERO
		if Input.is_action_just_pressed("move_up"): dir = Vector2i(0, -1)
		elif Input.is_action_just_pressed("move_down"): dir = Vector2i(0, 1)
		elif Input.is_action_just_pressed("move_left"): dir = Vector2i(-1, 0)
		elif Input.is_action_just_pressed("move_right"): dir = Vector2i(1, 0)
		if dir != Vector2i.ZERO:
			var nc := cursor + dir
			if Battle.in_grid(nc.x, nc.y):
				cursor = nc
		if cursor.x >= 0 and Input.is_action_just_pressed("interact"):
			_click_cell(cursor)

func _status_line() -> String:
	var al: int = Battle.alive_of("ally").size()
	var en: int = Battle.alive_of("enemy").size()
	var who := ""
	if waiting_input:
		var steps := 0
		if Battle.units.size() > 0:
			steps = Battle.steps_of(Battle.units[0])
		who = " ← 轮到你了（移动力 %d）" % steps
	elif auto:
		who = "（自动战斗中…）"
	return "回合%d  我方%d  敌方%d%s" % [Battle.round_no, al, en, who]

# ---------- 演出层 ----------
func _cell_px(x: int, y: int) -> Vector2:
	return Vector2(x * CELL + CELL / 2.0, y * CELL + CELL / 2.0)

## 引擎特效事件 → 视图动画对象（飘字/刀光/受击闪白）
func _drain_fx() -> void:
	for ev in Battle.fx_events:
		if ev["kind"] == "hit":
			var col := UITheme.C_GOLD if bool(ev["crit"]) else UITheme.C_HP
			var txt := str(int(ev["dmg"])) + ("！" if bool(ev["crit"]) else "")
			if str(ev.get("face", "")) != "":
				txt += "·" + str(ev["face"])
			floaters.append({"pos": _cell_px(int(ev["x"]), int(ev["y"])) + Vector2(0, -14), "txt": txt, "col": col, "age": 0.0})
			var u: Dictionary = Battle.unit_at(int(ev["x"]), int(ev["y"]))
			if u != {}:
				flash[str(u["id"])] = 0.0
		elif ev["kind"] == "slash":
			slashes.append({"a": _cell_px(int(ev["ax"]), int(ev["ay"])), "b": _cell_px(int(ev["tx"]), int(ev["ty"])), "age": 0.0})
	Battle.clear_fx()

func _step_fx(d: float) -> void:
	# 渲染位滑行补间（战棋走位）
	for u in Battle.units:
		var key := str(u["id"])
		var target := _cell_px(u["x"], u["y"])
		if not render_pos.has(key):
			render_pos[key] = target
		else:
			render_pos[key] = render_pos[key].lerp(target, 1.0 - exp(-14.0 * d))
	# 飘字/刀光/闪白寿命
	for f in floaters:
		f["age"] += d
	floaters = floaters.filter(func(x): return float(x["age"]) < 0.9)
	for s in slashes:
		s["age"] += d
	slashes = slashes.filter(func(x): return float(x["age"]) < 0.22)
	for k in flash.keys():
		flash[k] = float(flash[k]) + d
	for k in flash.keys():
		if float(flash[k]) > 0.18:
			flash.erase(k)

# ---------- 主循环 ----------
func _step() -> void:
	if Battle.finished:
		_finish()
		return
	var actor: Dictionary = Battle.tick_until_ready()
	if actor == {}:
		_finish()
		return
	if actor["side"] == "enemy" or auto:
		Battle.ai_act(actor)
		_log_flush()
		await get_tree().create_timer(0.3).timeout
		_step()
	else:
		waiting_input = true
		sel_move = -1
		target_mode = false
		_show_moves(actor)

func _show_moves(actor: Dictionary) -> void:
	waiting_input = true
	for c in move_box.get_children():
		c.queue_free()
	var info := Label.new()
	info.text = "%s 的回合——选招式（%d/%d 内力，战意%d/200）" % [actor["name"], actor["mp"], actor["mp_max"], actor["yide"]]
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", UITheme.C_TEXT)
	move_box.add_child(info)
	var row := HBoxContainer.new()
	move_box.add_child(row)
	var mv_arr: Array = Battle.moves_of(actor)
	for i in mv_arr.size():
		var mv: Dictionary = mv_arr[i]
		var usable: bool = Battle.can_use(actor, i)
		var ult_tag: String = "★" if mv.get("ult", false) else ""
		var yide_ok: bool = (not mv.get("ult", false)) or actor["yide"] >= Battle.YIDE_ULT
		var b := Button.new()
		b.text = "%s%s\n倍率%.1f 内力%d CD%d %s" % [ult_tag, mv.get("name", "?"), float(mv.get("mult", 1)), int(mv.get("mp", 0)), int(mv.get("cd", 0)), mv.get("target", "对位")]
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(86, 56)
		b.disabled = (not usable) or (not yide_ok)
		var idx := i
		b.pressed.connect(func(): _on_move_selected(actor, idx))
		row.add_child(b)

func _on_move_selected(actor: Dictionary, idx: int) -> void:
	if not waiting_input:
		return
	sel_move = idx
	var cells: Array = Battle.attack_cells(actor, idx)
	if cells.is_empty():
		# 无需选格：直接施放（移动权保留给走位前的自主调整——本版从简）
		waiting_input = false
		_clear_moves()
		Battle.use_move(actor, idx, {})
		_log_flush()
		_step()
		return
	# 进入目标选择
	target_mode = true
	moved_this_turn = false
	cursor = Vector2(actor["x"], actor["y"])
	_clear_moves()
	var tip := Label.new()
	tip.text = "点蓝格走位（可再点红格出手）· 右键取消"
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", UITheme.C_TEXT)
	move_box.add_child(tip)

func _click_cell(cell: Vector2i) -> void:
	if not waiting_input or not target_mode or sel_move < 0:
		return
	var hero: Dictionary = Battle.units[0] if Battle.units.size() > 0 else {}
	if hero == {}:
		return
	var atk_cells: Array = Battle.attack_cells(hero, sel_move)
	# 先看出手：格上有敌人且在攻击范围
	var tgt: Dictionary = Battle.unit_at(cell.x, cell.y)
	if tgt != {} and tgt["side"] == "enemy" and cell in atk_cells:
		var idx := sel_move
		waiting_input = false
		target_mode = false
		sel_move = -1
		_clear_moves()
		Battle.use_move(hero, idx, {"cell": cell})
		_log_flush()
		_step()
		return
	# 再看走位：蓝格移动（每回合一次移动权）
	if not moved_this_turn and cell in Battle.move_range(hero):
		Battle.move_to(hero, cell)
		moved_this_turn = true
		return
	# 点自己 = 收招（走位后原地不出手则结束回合走位无效，直接收）
	if cell == Vector2i(hero["x"], hero["y"]):
		_cancel_targeting()

func _cancel_targeting() -> void:
	if waiting_input and target_mode:
		target_mode = false
		sel_move = -1
		_show_moves(Battle.units[0])

func _on_canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		var cell := Vector2i(int(ev.position.x / CELL), int(ev.position.y / CELL))
		if Battle.in_grid(cell.x, cell.y):
			_click_cell(cell)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_cancel_targeting()

func _clear_moves() -> void:
	for c in move_box.get_children():
		c.queue_free()

func _try_flee() -> void:
	if waiting_input:
		waiting_input = false
		_clear_moves()
		Battle.try_retreat()
		_log_flush()

func _finish() -> void:
	var res: Dictionary = Battle.result
	_log_flush()
	if res.get("spar", false):
		if res.get("win", false):
			main.toast_panel("切磋获胜！江湖经验+10")
			GameState.add_affinity(Battle.spar_npc, 5)
			GameState.add_exp(10)
		else:
			main.toast_panel("点到为止，虽败犹荣。")
			GameState.add_affinity(Battle.spar_npc, 2)
	elif res.get("retreat", false):
		main.toast_panel("你退出了战斗。")
	elif res.get("win", false):
		GameState.settle_battle(res)
		var drops := []
		for d in res.get("drops", []):
			drops.append(GameDB.get_item(d["item"]).get("name", d["item"]))
		main.toast_panel("胜！修为+%d 铜钱+%d %s" % [int(res.get("exp", 0)), int(res.get("money", 0)), "、".join(drops)])
		GameState.mp = GameState.get_panel()["mp_max"] / 2
	else:
		GameState.hp = maxi(1, GameState.get_panel()["hp_max"] / 4)
		GameState.money_tong = maxi(0, GameState.money_tong - int(GameState.money_tong * 0.1))
		main.toast_panel("战败……你被好心的路人救起，损失了一成盘缠。（回满需休整）")
	await get_tree().create_timer(1.2).timeout
	GameState.refresh_vitals()
	if main.current == "ending":
		return
	if back_to == "town":
		main.switch_to("town", {"map": back_payload.get("map", "village"), "pos": back_payload.get("pos", [])})
	else:
		main.switch_to("world", {"node": back_payload.get("node", "village")})

# ---------- 绘制 ----------
func _draw_field() -> void:
	var fnt := get_tree().root.theme.default_font
	# 地面格（宣纸色系瓦面）+ 墨线网格
	for yy in Battle.GRID_H:
		for xx in Battle.GRID_W:
			var r := Rect2(xx * CELL, yy * CELL, CELL, CELL)
			var kind := "grass"
			if Battle.cell_blocked(xx, yy):
				kind = "stone"
			var tex: ImageTexture = ArtLib.ground_tex(kind, xx + 40, yy + 40)
			if tex != null:
				canvas.draw_texture_rect(tex, r, false)
			else:
				canvas.draw_rect(r, Color("e9dfc6"))
			canvas.draw_rect(r, Color(0.13, 0.11, 0.09, 0.35), false, 1.0)
	# 障碍（岩块剪影）
	for ob in Battle.obstacles:
		canvas.draw_circle(Vector2(ob.x * CELL + CELL / 2, ob.y * CELL + CELL / 2), CELL * 0.32, Color("221d17"))
		canvas.draw_circle(Vector2(ob.x * CELL + CELL / 2 - 3, ob.y * CELL + CELL / 2 - 3), CELL * 0.18, Color("4a4238"))
	# 范围高亮（目标选择中）
	var hero: Dictionary = Battle.units[0] if Battle.units.size() > 0 else {}
	if waiting_input and target_mode and sel_move >= 0 and hero != {}:
		for c in Battle.move_range(hero):
			_cell_glow(c, Color(0.35, 0.5, 0.62, 0.30))
		for c in Battle.attack_cells(hero, sel_move):
			var occupied: Dictionary = Battle.unit_at(c.x, c.y)
			var col := Color(0.69, 0.23, 0.18, 0.38) if occupied != {} else Color(0.69, 0.23, 0.18, 0.16)
			_cell_glow(c, col)
		if cursor.x >= 0:
			canvas.draw_rect(Rect2(cursor.x * CELL + 2, cursor.y * CELL + 2, CELL - 4, CELL - 4), UITheme.C_GOLD, false, 2.0)
	# 刀光（弧线，快闪）
	for s in slashes:
		var a: float = 1.0 - float(s["age"]) / 0.22
		canvas.draw_line(s["a"], s["a"].lerp(s["b"], 0.6), Color(0.85, 0.78, 0.55, a), 3.0)
	# 单位（按 y 排序，站格子；滑行补间 + 受击闪白；2× 整数缩放 32×48）
	var sorted: Array = Battle.units.filter(func(u): return u["alive"])
	sorted.sort_custom(func(a, b): return a["y"] < b["y"])
	for u in sorted:
		_draw_unit(u, fnt)
	# 伤害飘字（上浮渐隐）
	for fl in floaters:
		var fa: float = 1.0 - float(fl["age"]) / 0.9
		var fp: Vector2 = fl["pos"] + Vector2(0, -26.0 * float(fl["age"]))
		canvas.draw_string(fnt, fp + Vector2(1, 1), str(fl["txt"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color(0, 0, 0, 0.6 * fa))
		canvas.draw_string(fnt, fp, str(fl["txt"]), HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color(fl["col"], fa))

func _cell_glow(c: Vector2i, col: Color) -> void:
	canvas.draw_rect(Rect2(c.x * CELL + 3, c.y * CELL + 3, CELL - 6, CELL - 6), col)

func _draw_unit(u: Dictionary, fnt: Font) -> void:
	var key := str(u["id"])
	if not render_pos.has(key):
		render_pos[key] = _cell_px(u["x"], u["y"])
	var px: float = render_pos[key].x - CELL / 2.0
	var py: float = render_pos[key].y - CELL / 2.0
	var col: Color = UITheme.C_GOLD if u["side"] == "ally" else Color("b03a2e")
	if u.get("is_boss", false):
		col = Color("7a2a6a")
	# 站格框 + 受击闪白
	canvas.draw_rect(Rect2(px + 3, py + 3, CELL - 6, CELL - 6), col, false, 2.0)
	if flash.has(key):
		var fk: float = maxf(0.0, 0.6 - float(flash[key]) * 3.3)
		if fk > 0.01:
			canvas.draw_rect(Rect2(px + 3, py + 3, CELL - 6, CELL - 6), Color(1, 1, 1, fk))
	# 影
	canvas.draw_set_transform(Vector2(px + CELL / 2, py + CELL - 8), 0.0, Vector2(1.0, 0.35))
	canvas.draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.25))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 角色（2×：32×48）
	var actor := "swordsman" if u["side"] == "ally" else "bandit"
	var dir8 := ArtLib.dir8_of(u["facing"])
	var body: Texture2D = ArtLib.char_frame(actor, "idle", dir8, int(anim_time * 3.0))
	if body != null:
		canvas.draw_texture_rect(body, Rect2(px + (CELL - body.get_width() * 2) / 2.0, py + CELL - 12 - body.get_height() * 2, body.get_width() * 2.0, body.get_height() * 2.0), false)
	# 朝向指示（墨色小三角）
	var fx: float = px + CELL / 2 + u["facing"].x * (CELL / 2.0 - 6.0)
	var fy: float = py + CELL / 2 + u["facing"].y * (CELL / 2.0 - 6.0)
	canvas.draw_circle(Vector2(fx, fy), 3.0, INK_COLOR)
	# 血条（宣纸底+朱砂条）
	var hp_r: float = clampf(float(u["hp"]) / float(u["hp_max"]), 0.0, 1.0)
	canvas.draw_rect(Rect2(px + 6, py + CELL - 6, CELL - 12, 4), Color(0.1, 0.08, 0.07, 0.7))
	canvas.draw_rect(Rect2(px + 6, py + CELL - 6, (CELL - 12) * hp_r, 4), UITheme.C_HP)
	# 名字
	canvas.draw_string(fnt, Vector2(px, py - 2), u["name"], HORIZONTAL_ALIGNMENT_CENTER, CELL, 10, UITheme.C_TEXT)
	if u.get("is_boss", false):
		canvas.draw_string(fnt, Vector2(px, py - 12), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, CELL, 9, UITheme.C_GOLD)

const INK_COLOR := Color("221d17")

func _draw_atb() -> void:
	var fnt := get_tree().root.theme.default_font
	atb_bar.draw_rect(Rect2(0, 0, Battle.GRID_W * CELL, 40), Color(0.09, 0.08, 0.06, 0.9))
	var rows := 0
	var ally_fill: ImageTexture = ArtLib.ui_bar("mp")
	var enemy_fill: ImageTexture = ArtLib.ui_bar("hp")
	for u in Battle.units:
		if not u["alive"]: continue
		var y := 4 + rows * 12
		var g: float = clampf(float(u["gauge"]) / float(Battle.ATB_MAX), 0.0, 1.0)
		var fill: ImageTexture = ally_fill if u["side"] == "ally" else enemy_fill
		if fill != null:
			atb_bar.draw_texture_rect(fill, Rect2(70, y + 2, 350 * g, 6), false)
		else:
			atb_bar.draw_rect(Rect2(70, y + 2, 350 * g, 6), Color("3f545c") if u["side"] == "ally" else Color("b03a2e"))
		var name_col: Color = UITheme.C_TEXT if u["side"] == "ally" else Color("8a5a4a")
		atb_bar.draw_string(fnt, Vector2(0, y + 8), u["name"].substr(0, 6), HORIZONTAL_ALIGNMENT_LEFT, 70, 10, name_col)
		rows += 1
	atb_bar.draw_string(fnt, Vector2(424, 18), "ATB", HORIZONTAL_ALIGNMENT_LEFT, 50, 11, UITheme.C_DIM)
	atb_bar.draw_string(fnt, Vector2(424, 34), "时序条", HORIZONTAL_ALIGNMENT_LEFT, 50, 10, UITheme.C_DIM)

func _log_flush() -> void:
	if log_rt == null: return
	log_rt.clear()
	var logs: Array = Battle.log
	var start: int = maxi(0, logs.size() - 40)
	for i in range(start, logs.size()):
		log_rt.append_text(str(logs[i]) + "\n")
