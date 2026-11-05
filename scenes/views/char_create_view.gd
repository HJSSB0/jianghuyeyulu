extends Control
## 开局构建：姓名 + 五维 15 点分配 + 武器三选一 + 特性 Roll（可 1 次重掷）——大侠立志传式

var main: Node
var pts := 15
var alloc := {"臂力": 1, "体质": 1, "敏捷": 1, "悟性": 1, "福缘": 1}
var weapon := "剑"
var cur_trait := ""
var rerolled := false
var name_edit: LineEdit
var pts_label: Label
var attr_rows := {}

func on_enter(_p: Dictionary = {}) -> void:
	roll_trait()
	rebuild()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var bgc := ColorRect.new()
	bgc.color = Color("0e131b")
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgc)

	var title := Label.new()
	title.text = "—— 楔子 · 雨夜之后 ——"
	title.add_theme_font_size_override("font_size", 22)
	title.position = Vector2(330, 16)
	add_child(title)

	var story := Label.new()
	story.text = "昨夜大雨，黑衣人过村，火光冲天。\n你从塌了半边的屋檐下爬出来，手里只握着半截断剑。\n村口的老槐树下，幸存的人们等着你开口。"
	story.add_theme_font_size_override("font_size", 14)
	story.add_theme_color_override("font_color", Color("9aa8bc"))
	story.position = Vector2(310, 52)
	add_child(story)

	# 姓名
	var name_l := Label.new()
	name_l.text = "姓名："
	name_l.position = Vector2(300, 120)
	add_child(name_l)
	name_edit = LineEdit.new()
	name_edit.text = "沈青崖"
	name_edit.position = Vector2(360, 116)
	name_edit.size = Vector2(160, 28)
	add_child(name_edit)

	# 武器
	var wl := Label.new()
	wl.text = "趁手兵刃（决定初始套路与武器）："
	wl.position = Vector2(300, 156)
	add_child(wl)
	for i in 4:
		var wname: String = ["拳", "剑", "刀", "棍"][i]
		var b := Button.new()
		b.text = ["拳掌（刚猛）", "长剑（均衡）", "单刀（高伤）", "棍棒（横扫）"][i]
		b.toggle_mode = true
		b.button_pressed = weapon == wname
		b.position = Vector2(300 + (i % 2) * 158, 180 + (i / 2) * 34)
		b.size = Vector2(152, 30)
		b.pressed.connect(func():
			weapon = wname
			rebuild())
		add_child(b)

	# 五维
	var al := Label.new()
	al.text = "五维根骨（余 %d 点）：" % pts
	al.position = Vector2(300, 260)
	al.name = "PtsLabel"
	add_child(al)
	pts_label = al
	var attr_desc := {"臂力": "攻击", "体质": "气血/防御", "敏捷": "速度·集气/闪避", "悟性": "修为效率", "福缘": "暴击·奇遇"}
	for i in 5:
		var k: String = ["臂力", "体质", "敏捷", "悟性", "福缘"][i]
		var row_l := Label.new()
		row_l.text = "%s（+%s）" % [k, attr_desc[k]]
		row_l.position = Vector2(300, 292 + i * 33)
		add_child(row_l)
		var val := Label.new()
		val.text = str(alloc[k])
		val.position = Vector2(470, 292 + i * 33)
		add_child(val)
		attr_rows[k] = val
		var plus := Button.new()
		plus.text = "+"
		plus.position = Vector2(500, 288 + i * 33)
		plus.size = Vector2(30, 26)
		plus.disabled = pts <= 0 or alloc[k] >= 8
		plus.pressed.connect(func():
			if pts > 0 and alloc[k] < 8:
				alloc[k] += 1
				pts -= 1
				rebuild())
		add_child(plus)
		var minus := Button.new()
		minus.text = "−"
		minus.position = Vector2(535, 288 + i * 33)
		minus.size = Vector2(30, 26)
		minus.disabled = alloc[k] <= 1
		minus.pressed.connect(func():
			if alloc[k] > 1:
				alloc[k] -= 1
				pts += 1
				rebuild())
		add_child(minus)

	# 特性
	var tl := Label.new()
	tl.text = "出身特性（天授，可重掷一次）："
	tl.position = Vector2(620, 120)
	add_child(tl)
	var tr: Dictionary = GameDB.get_trait(cur_trait)
	var tr_name: Label = null
	var tr_box := PanelContainer.new()
	tr_box.position = Vector2(620, 146)
	tr_box.size = Vector2(300, 90)
	add_child(tr_box)
	var tvb := VBoxContainer.new()
	tr_box.add_child(tvb)
	tr_name = Label.new()
	tr_name.text = "【%s】%s" % [tr.get("name", "?"), tr.get("grade", "")]
	tr_name.add_theme_color_override("font_color", Color("c9a067") if tr.get("grade", "") == "稀有" else Color("8ab8c9"))
	tvb.add_child(tr_name)
	var tr_desc := Label.new()
	tr_desc.text = tr.get("desc", "")
	tr_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tr_desc.add_theme_font_size_override("font_size", 13)
	tvb.add_child(tr_desc)
	var roll_b := Button.new()
	roll_b.text = "重掷" + ("（最后一次）" if not rerolled else "（已用尽）")
	roll_b.position = Vector2(620, 244)
	roll_b.disabled = rerolled
	roll_b.pressed.connect(func():
		rerolled = true
		roll_trait()
		rebuild())
	add_child(roll_b)

	# 品格倾向提示
	var hint := Label.new()
	hint.text = "提示：分配影响开局面板；武器决定初始武学。后续可在门派与江湖中习得更多。"
	hint.position = Vector2(300, 452)
	hint.add_theme_color_override("font_color", Color("6a7a8a"))
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)

	# 开始
	var go := Button.new()
	go.text = "踏 入 江 湖"
	go.position = Vector2(390, 480)
	go.size = Vector2(180, 42)
	go.add_theme_font_size_override("font_size", 18)
	go.disabled = pts > 0
	go.pressed.connect(_start)
	add_child(go)

func roll_trait() -> void:
	var pool: Array = GameDB.traits.keys().filter(func(t): return GameDB.get_trait(t).get("kind", "") in ["战斗", "养成", "探索", "社交", "负面"])
	cur_trait = pool[randi() % pool.size()]

func _start() -> void:
	GameState.new_game({
		"name": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "无名小卒",
		"weapon": weapon,
		"attrs": alloc,
		"trait": cur_trait,
	})
	main.switch_to("world")
