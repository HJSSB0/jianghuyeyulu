extends Control
## 标题画面

const ArtLib := preload("res://scripts/art/art_lib.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

var main: Node

func on_enter(_p: Dictionary = {}) -> void:
	for c in get_children():
		c.queue_free()
	var PixelArt := preload("res://scripts/art/pixel_art.gd")
	# 2.5D 重绘：CC0 山门插画（缺失时回退程序化标题画）
	var art: Texture2D = ArtLib.mood_art("07_immortal_gate")
	if art == null:
		art = PixelArt.gen_title_art()
	var bg := TextureRect.new()
	bg.texture = art
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 压暗层：保证标题文字与按钮可读
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.position = Vector2(640, 36)
	box.size = Vector2(260, 470)
	box.add_theme_constant_override("separation", 7)
	add_child(box)

	var t := Label.new()
	t.text = "江\n湖\n夜\n雨\n录"
	var tf: FontFile = UITheme.title_font()
	if tf != null:
		t.add_theme_font_override("font", tf)
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color("e9dfc6"))
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_x", 2)
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)

	var sub := Label.new()
	sub.text = "—— 大侠立志传 × 烟雨江湖 融合复刻 ——\n雨夜孤村，一剑出门。"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color("9aa8bc"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_spacer(16))
	box.add_child(_btn("新的旅程", func(): main.switch_to("create")))
	var cont := _btn("继续旅程", func():
		if SaveSystem.load_game():
			main.switch_to("world")
		else:
			main.toast_panel("没有找到存档"))
	cont.disabled = not SaveSystem.has_save()
	box.add_child(cont)
	box.add_child(_btn("云同步", func(): _cloud_dialog()))
	box.add_child(_btn("退出游戏", func(): get_tree().quit()))

	var foot := Label.new()
	foot.text = "v0.3 2.5D 重绘 · Godot 4.7 · 素材来源见 assets/CREDITS.md"
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color("5a6470"))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(12, 516)
	add_child(foot)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b

# ---------- 云同步（新设备拉取存档） ----------
func _cloud_dialog() -> void:
	for c in get_children():
		c.queue_free()
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(440, 0)
	pc.position = Vector2((960 - 440) / 2.0, 110)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var t := Label.new()
	t.text = "云同步 · 拉取云端存档"
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color("e8e0d0"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var hint := Label.new()
	hint.text = "新设备第一次玩：填服务器与账号，把另一台设备上传的进度拉下来。"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("9aa8bc"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	var url := LineEdit.new()
	url.placeholder_text = "服务器地址 如 http://192.168.1.5:8787"
	url.text = CloudSync.base_url
	var un := LineEdit.new()
	un.placeholder_text = "用户名"
	un.text = CloudSync.user
	var pw := LineEdit.new()
	pw.placeholder_text = "PIN 码"
	pw.secret = true
	pw.text = CloudSync.pin
	vb.add_child(url)
	vb.add_child(un)
	vb.add_child(pw)
	var st := Label.new()
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_theme_font_size_override("font_size", 13)
	vb.add_child(st)
	vb.add_child(_btn("拉取云端存档", func(): _cloud_pull(url, un, pw, st)))
	vb.add_child(_btn("返回", func(): on_enter()))

func _cloud_pull(url: LineEdit, un: LineEdit, pw: LineEdit, st: Label) -> void:
	CloudSync.save_config(url.text, un.text, pw.text)
	st.text = "正在连接…"
	CloudSync.peek(_title_peek_cb.bind(st))

func _title_peek_cb(ok: bool, data: Dictionary, st: Label) -> void:
	if not ok:
		st.text = "连接失败：" + str(data.get("error", ""))
		return
	if not bool(data.get("exists", false)):
		st.text = "云端暂无存档（先在另一台设备：行囊→云同步→上传）。"
		return
	CloudSync.pull(_title_pull_cb.bind(st))

func _title_pull_cb(ok: bool, data: Dictionary, st: Label) -> void:
	if not ok:
		st.text = "拉取失败：" + str(data.get("error", ""))
		return
	var sd: Dictionary = data.get("save", {})
	if SaveSystem.apply_save_dict(sd) and SaveSystem.write_save_dict(sd):
		st.text = "已拉取「%s」的进度（第%d日）。返回后点「继续旅程」。" % [GameState.player_name, GameState.day]
	else:
		st.text = "云端存档格式异常。"
