extends Control
## EndingView —— 第一章结局：三选一（大侠式多结局钩子），按品格与门派微调文案

var main: Node

func on_enter(_p: Dictionary = {}) -> void:
	rebuild()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var ArtLib := preload("res://scripts/art/art_lib.gd")
	var bg := ColorRect.new()
	bg.color = Color("0d1017")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 水墨结局画按品格取向选择（圣经三结局）
	var kind := "world"
	if GameState.morality["仁"] >= 50:
		kind = "hidden"
	elif GameState.morality["义"] < 50 and GameState.morality["勇"] < 50 and GameState.learned.has("nei_baiyue"):
		kind = "dark"
	var art: Texture2D = ArtLib.mood_art("ending_" + kind)
	if art != null:
		var pic := TextureRect.new()
		pic.texture = art
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.modulate = Color(1, 1, 1, 0.55)
		add_child(pic)
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.03, 0.05, 0.35)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(shade)

	var t := Label.new()
	t.text = "—— 第一章 · 夜雨初歇 ——"
	t.add_theme_font_size_override("font_size", 26)
	t.position = Vector2(300, 30)
	add_child(t)

	var txt := Label.new()
	txt.text = "拜月护法·玄 败退时冷笑：'月圆之夜，武神殿见。'\n\n雨停了。晨光落在湿漉漉的青石板上。\n路有三条，你握紧了手中兵刃——"
	txt.add_theme_font_size_override("font_size", 15)
	txt.position = Vector2(280, 80)
	add_child(txt)

	var opts := VBoxContainer.new()
	opts.position = Vector2(300, 200)
	opts.size = Vector2(360, 260)
	opts.add_theme_constant_override("separation", 12)
	add_child(opts)

	opts.add_child(_ending_btn("入世 · 剑指拜月",
		"追随护法的踪迹北上，直捣武神殿。\n（义≥50 或 勇≥60 时口碑最佳）", "ending_world",
		GameState.morality["义"] >= 50 or GameState.morality["勇"] >= 60))
	opts.add_child(_ending_btn("出世 · 归隐小村",
		"回无名小村重建家园，守护想守护的人。\n（仁≥50 时口碑最佳）", "ending_hidden",
		GameState.morality["仁"] >= 50))
	opts.add_child(_ending_btn("沉沦 · 接任教主",
		"夺其令，承其力，以拜月之名号令江湖。\n（需习得拜月冥功）", "ending_dark",
		GameState.learned.has("nei_baiyue")))

	var note := Label.new()
	note.text = "本结局按你的品格、门派与选择分出三条去向——第二章的伏笔。\n当前评价：仁%d 义%d 勇%d · 门派：%s · 名声%s" % [
		GameState.morality["仁"], GameState.morality["义"], GameState.morality["勇"],
		GameDB.get_faction(GameState.faction).get("name", "无门无派") if GameState.faction != "" else "无门无派",
		GameState.fame_name()]
	note.position = Vector2(240, 480)
	note.add_theme_color_override("font_color", Color("7a8aa0"))
	note.add_theme_font_size_override("font_size", 13)
	add_child(note)

func _ending_btn(title: String, desc: String, ending_id: String, ideal: bool) -> Button:
	var b := Button.new()
	b.text = "%s %s\n%s" % ["★" if ideal else "○", title, desc]
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(360, 70)
	b.pressed.connect(func(): _pick(ending_id, title))
	return b

func _pick(ending_id: String, title: String) -> void:
	GameState.quest_hook({"type": "ending_choice"})
	for c in get_children():
		c.queue_free()
	var t := Label.new()
	var flavor := {
		"ending_world": "你背上行囊，踏上了北去的官道。\n雨后的天边，一线金光破云而出。\n\n—— 入世线 · 待续 ——\n（名声+50，品格·勇+10）",
		"ending_hidden": "你回到无名小村，斧凿声再次响起。\n孩子们在修好的祠堂前追逐打闹。\n\n—— 出世线 · 待续 ——\n（品格·仁+10，村民的好感即你的武功）",
		"ending_dark": "月圆之夜，你坐上了那把冰冷的椅子。\n教众山呼海啸，你的眼中再无暖意。\n\n—— 暗渊线 · 待续 ——\n（拜月冥功大成，品格·仁-20）",
	}
	t.text = "结局已定：%s\n\n%s" % [title, flavor.get(ending_id, "")]
	t.add_theme_font_size_override("font_size", 18)
	t.set_anchors_preset(Control.PRESET_CENTER)
	t.position = Vector2(180, 150)
	t.size = Vector2(600, 200)
	add_child(t)
	# 结局奖励
	match ending_id:
		"ending_world":
			GameState.add_fame(50); GameState.add_morality("勇", 10)
		"ending_hidden":
			GameState.add_morality("仁", 10)
		"ending_dark":
			GameState.add_morality("仁", -20)
	SaveSystem.save_game()
	var box := VBoxContainer.new()
	box.position = Vector2(390, 400)
	add_child(box)
	var again := Button.new()
	again.text = "继续游历（自由活动）"
	again.pressed.connect(func(): main.switch_to("world"))
	box.add_child(again)
	var ng := Button.new()
	ng.text = "重开一局（新周目）"
	ng.pressed.connect(func():
		GameState.reset()
		main.switch_to("title"))
	box.add_child(ng)
