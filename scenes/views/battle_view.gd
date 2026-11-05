extends Control
## BattleView —— 融合战斗演出：九宫格站位 + ATB 时序条 + 战意 + 招式面板 + 日志

const PixelArt := preload("res://scripts/art/pixel_art.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

var main: Node
var canvas: Control
var atb_bar: Control
var log_rt: RichTextLabel
var move_box: VBoxContainer
var auto_toggle: Button
var unit_faces := {}
var turn_label: Label
var battle_name := "遭遇战"
var back_to := "world"
var back_payload := {}
var waiting_input := false
var auto := false
var _face_cache := {}

func on_enter(p: Dictionary = {}) -> void:
	battle_name = p.get("name", "遭遇战")
	back_to = p.get("back", "world")
	back_payload = p
	Battle.setup(p)
	auto = false
	rebuild()
	_step()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("0d1017")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "⚔ " + battle_name + (String("（阵法：%s）" % GameDB.get_formation(Battle.formation).get("name", "")))
	title.add_theme_font_size_override("font_size", 18)
	title.position = Vector2(16, 8)
	add_child(title)
	# 战场
	canvas = Control.new()
	canvas.position = Vector2(40, 60)
	canvas.size = Vector2(560, 320)
	add_child(canvas)
	canvas.draw.connect(_draw_field)
	# ATB 条
	atb_bar = Control.new()
	atb_bar.position = Vector2(40, 396)
	atb_bar.size = Vector2(560, 44)
	add_child(atb_bar)
	atb_bar.draw.connect(_draw_atb)
	# 日志
	log_rt = RichTextLabel.new()
	log_rt.position = Vector2(620, 60)
	log_rt.size = Vector2(320, 300)
	log_rt.scroll_following = true
	log_rt.add_theme_font_size_override("normal_font_size", 13)
	add_child(log_rt)
	# 招式面板
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 434)
	panel.size = Vector2(560, 102)
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
	turn_label = Label.new()
	turn_label.position = Vector2(620, 420)
	turn_label.add_theme_color_override("font_color", Color("9aa8bc"))
	add_child(turn_label)
	var hint := Label.new()
	hint.text = "九宫格：前中后三列×上中下三路 · 近战打对位 · 突进直取后排+25% · 战意100放大招/200必爆"
	hint.position = Vector2(620, 508)
	hint.add_theme_color_override("font_color", Color("5a6470"))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)
	_log_flush()

func _process(_d: float) -> void:
	if not visible or canvas == null:
		return
	if Battle.finished:
		_finish()
		set_process(false)
		return
	canvas.queue_redraw()
	atb_bar.queue_redraw()
	turn_label.text = _status_line()

func _status_line() -> String:
	var al: int = Battle.alive_of("ally").size()
	var en: int = Battle.alive_of("enemy").size()
	var who := ""
	if waiting_input:
		who = " ← 轮到你了"
	elif auto:
		who = "（自动战斗中…）"
	return "回合%d  我方%d  敌方%d%s" % [Battle.round_no, al, en, who]

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
		var ch: Dictionary = Battle.ai_choose(actor)
		Battle.use_move(actor, int(ch["move"]), ch.get("pick", {}))
		_log_flush()
		await get_tree().create_timer(0.3).timeout
		_step()
	else:
		_show_moves(actor)

func _show_moves(actor: Dictionary) -> void:
	waiting_input = true
	for c in move_box.get_children():
		c.queue_free()
	var info := Label.new()
	info.text = "%s 的回合——选择招式（%d/%d 内力，战意%d/200）" % [actor["name"], actor["mp"], actor["mp_max"], actor["yide"]]
	info.add_theme_font_size_override("font_size", 13)
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
		b.custom_minimum_size = Vector2(104, 60)
		b.disabled = (not usable) or (not yide_ok)
		var idx := i
		b.pressed.connect(func():
			waiting_input = false
			_clear_moves()
			Battle.use_move(actor, idx, {})
			_log_flush()
			_step())
		row.add_child(b)

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
	# 结算
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
		# 主角战后回内力
		GameState.mp = GameState.get_panel()["mp_max"] / 2
	else:
		# 战败：不死，回村半血（规避大侠式 SL 惩罚）
		GameState.hp = maxi(1, GameState.get_panel()["hp_max"] / 4)
		GameState.money_tong = maxi(0, GameState.money_tong - int(GameState.money_tong * 0.1))
		main.toast_panel("战败……你被好心的路人救起，损失了一成盘缠。（回满需休整）")
	await get_tree().create_timer(1.2).timeout
	GameState.refresh_vitals()
	if main.current == "ending":
		return  # 结局界面已接管（m7 胜利 → m8 触发）
	if back_to == "town":
		main.switch_to("town", {"map": back_payload.get("map", "village")})
	else:
		main.switch_to("world", {"node": back_payload.get("node", "village")})

# ---------- 绘制 ----------
func _face(tex_key: String, main_col: Color) -> ImageTexture:
	if not _face_cache.has(tex_key):
		_face_cache[tex_key] = PixelArt.gen_face(tex_key.hash() & 0xffff, main_col)
	return _face_cache[tex_key]

func _draw_field() -> void:
	var S := 84.0
	var gap := 6.0
	# 三路分隔线
	for lane in 3:
		var y := 20 + lane * (S + gap + 24)
		canvas.draw_line(Vector2(0, y - 10), Vector2(560, y - 10), Color("232833"), 1.0)
	var lane_names := ["上", "中", "下"]
	var fnt := get_tree().root.theme.default_font
	# 我方（左，列0-2）
	for u in Battle.units:
		if u["side"] != "ally": continue
		_draw_unit(u, 20.0 + u["col"] * (S * 0.82), 24 + u["lane"] * (S + gap + 24), S * 0.8, fnt, true)
	# 敌方（右，列反序）
	for u in Battle.units:
		if u["side"] != "enemy": continue
		_draw_unit(u, 560 - S * 0.8 - u["col"] * (S * 0.82), 24 + u["lane"] * (S + gap + 24), S * 0.8, fnt, false)

func _draw_unit(u: Dictionary, x: float, y: float, sz: float, fnt: Font, ally: bool) -> void:
	var col: Color = Color("3a6a8a") if ally else Color("8a3a3a")
	if u.get("is_boss", false):
		col = Color("5a2a6a") if not ally else col
	# 底座
	canvas.draw_rect(Rect2(x, y, sz, sz), Color("161d2b"))
	canvas.draw_rect(Rect2(x, y, sz, sz), col, false, 2.0)
	# 头像
	var key: String = str(u["id"])
	var face: ImageTexture = _face(key, col)
	canvas.draw_texture_rect(face, Rect2(x + sz * 0.15, y + sz * 0.1, sz * 0.7, sz * 0.7), false)
	# 血条
	var hp_r: float = float(u["hp"]) / float(u["hp_max"])
	canvas.draw_rect(Rect2(x, y + sz + 2, sz, 7), Color("301414"))
	canvas.draw_rect(Rect2(x, y + sz + 2, sz * hp_r, 7), UITheme.C_HP if hp_r > 0.3 else Color("e05a4a"))
	# 战意条
	var yd_r: float = float(u["yide"]) / 200.0
	canvas.draw_rect(Rect2(x, y + sz + 11, sz * yd_r, 4), UITheme.C_YIDE)
	# 名字
	canvas.draw_string(fnt, Vector2(x, y + sz + 26), u["name"], HORIZONTAL_ALIGNMENT_CENTER, sz, 11, UITheme.C_TEXT)
	# 状态
	var sts := []
	for sk in u["statuses"]:
		sts.append(sk)
	if sts.size() > 0:
		canvas.draw_string(fnt, Vector2(x, y - 4), "、".join(sts), HORIZONTAL_ALIGNMENT_CENTER, sz, 10, Color("c98a8a"))
	if u.get("is_boss", false):
		canvas.draw_string(fnt, Vector2(x, y - 16), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, sz, 10, Color("c9a067"))

func _draw_atb() -> void:
	var fnt := get_tree().root.theme.default_font
	atb_bar.draw_rect(Rect2(0, 0, 560, 40), Color("12161f"))
	var rows := 0
	for u in Battle.units:
		if not u["alive"]: continue
		var y := 4 + rows * 12
		var g: float = clampf(float(u["gauge"]) / float(Battle.ATB_MAX), 0.0, 1.0)
		var col: Color = Color("4a7ab8") if u["side"] == "ally" else Color("b84a4a")
		atb_bar.draw_rect(Rect2(70, y + 2, 400 * g, 6), col)
		atb_bar.draw_string(fnt, Vector2(0, y + 8), u["name"].substr(0, 6), HORIZONTAL_ALIGNMENT_LEFT, 70, 10, UITheme.C_DIM)
		rows += 1
	atb_bar.draw_string(fnt, Vector2(480, 18), "ATB", HORIZONTAL_ALIGNMENT_LEFT, 60, 11, UITheme.C_DIM)
	atb_bar.draw_string(fnt, Vector2(480, 34), "时序条", HORIZONTAL_ALIGNMENT_LEFT, 60, 10, UITheme.C_DIM)

func _log_flush() -> void:
	if log_rt == null: return
	log_rt.clear()
	var logs: Array = Battle.log
	var start: int = maxi(0, logs.size() - 40)
	for i in range(start, logs.size()):
		log_rt.append_text(str(logs[i]) + "\n")
