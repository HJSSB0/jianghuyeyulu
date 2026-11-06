extends RefCounted
## UITheme —— 古典水墨 · 宣纸卷轴主题（程序化 NinePatch，docs/06 规范）。
## 中文字体：正文 Noto Sans SC（内嵌）；标题/书法 Ma Shan Zheng（OFL，内嵌）。

const INK := Color("221d17")
const INK_SOFT := Color("4a4238")
const PAPER := Color("e9dfc6")
const PAPER_DARK := Color("d8cbaa")
const GOLD := Color("c9a067")
const CINNABAR := Color("b03a2e")
const WOOD := Color("8a6a48")
const WOOD_DARK := Color("5e4732")
const NIGHT := Color("12100c")

static var _sb_cache: Dictionary = {}

static func title_font() -> FontFile:
	if ResourceLoader.exists("res://assets/fonts/MaShanZheng-Regular.ttf"):
		return load("res://assets/fonts/MaShanZheng-Regular.ttf")
	return null

static func _paper_tex(margin_ink: Color, pressed: bool) -> ImageTexture:
	var key := "paper_%s_%s" % [margin_ink.to_html(), pressed]
	if _sb_cache.has(key):
		return _sb_cache.get(key)
	var S := 48
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for yy in S:
		for xx in S:
			var g := 0.88 + 0.06 * r.randf()
			var c := Color(g * 0.93, g * 0.88, g * 0.76)
			if pressed:
				c = c.darkened(0.10)
			img.set_pixel(xx, yy, c)
	# 纸纤维（横向细纹）
	for i in 40:
		var fy := r.randi_range(2, S - 3)
		var fx := r.randi_range(2, S - 8)
		for l in r.randi_range(3, 7):
			img.set_pixel(fx + l, fy, Color(0.72, 0.66, 0.53, 0.6))
	# 墨线双边框（外 2px 墨，内 1px 墨/金）
	for b in 2:
		for xx in S:
			img.set_pixel(xx, b, INK)
			img.set_pixel(xx, S - 1 - b, INK)
	for yy in S:
		img.set_pixel(0, yy, INK)
		img.set_pixel(1, yy, INK)
		img.set_pixel(S - 1, yy, INK)
		img.set_pixel(S - 2, yy, INK)
		img.set_pixel(4, yy, INK_SOFT)
		img.set_pixel(S - 5, yy, INK_SOFT)
	for xx in range(4, S - 4):
		img.set_pixel(xx, 4, INK_SOFT)
		img.set_pixel(xx, S - 5, INK_SOFT)
	# 四角朱砂印点
	for c in [Vector2(3, 3), Vector2(S - 5, 3), Vector2(3, S - 5), Vector2(S - 5, S - 5)]:
		img.set_pixel(int(c.x), int(c.y), CINNABAR)
	var t := ImageTexture.create_from_image(img)
	_sb_cache[key] = t
	return t

static func _wood_tex(pressed: bool, gold_border: bool) -> ImageTexture:
	var key := "wood_%s_%s" % [pressed, gold_border]
	if _sb_cache.has(key):
		return _sb_cache.get(key)
	var w := 36
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for yy in h:
		for xx in w:
			var g := (0.86 if not pressed else 0.72) + 0.05 * r.randf()
			var c := Color(g * 0.55, g * 0.42, g * 0.28)
			if yy % 5 == 0:
				c = c.darkened(0.12)
			img.set_pixel(xx, yy, c)
	for b in 1:
		for xx in w:
			img.set_pixel(xx, b, INK)
			img.set_pixel(xx, h - 1 - b, INK)
		for yy in h:
			img.set_pixel(b, yy, INK)
			img.set_pixel(w - 1 - b, yy, INK)
	if gold_border:
		for xx in range(3, w - 3):
			img.set_pixel(xx, 3, GOLD)
			img.set_pixel(xx, h - 4, GOLD)
		for yy in range(3, h - 3):
			img.set_pixel(3, yy, GOLD)
			img.set_pixel(w - 4, yy, GOLD)
	var t := ImageTexture.create_from_image(img)
	_sb_cache[key] = t
	return t

static func _sb(tex: Texture2D, m: int, cm: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = cm
	sb.content_margin_right = cm
	sb.content_margin_top = cm * 0.6
	sb.content_margin_bottom = cm * 0.6
	return sb

static func make_theme() -> Theme:
	var t := Theme.new()
	# 正文：内嵌 Noto Sans SC（回退系统字体）
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "PingFang SC", "sans-serif"])
	var default_font: Font = sf
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC-Regular.otf"):
		var nf := load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile
		if nf != null:
			nf.fallbacks = [sf]
			default_font = nf
	t.default_font = default_font
	t.default_font_size = 14

	var panel := _sb(_paper_tex(INK, false), 8, 10.0)
	var panel_dark := _sb(_paper_tex(INK, true), 8, 10.0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var btn := _sb(_wood_tex(false, false), 6, 8.0)
	var btn_hover := _sb(_wood_tex(false, true), 6, 8.0)
	var btn_pressed := _sb(_wood_tex(true, true), 6, 8.0)
	var btn_disabled := _sb(_wood_tex(true, false), 6, 8.0)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)

	var line := _sb(_paper_tex(INK, true), 6, 6.0)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", _sb(_paper_tex(GOLD, false), 6, 6.0))
	t.set_stylebox("panel", "ScrollContainer", panel_dark)

	# 宣纸底上的字色：墨字
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", Color("f0e6c8"))
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("8a7f6a"))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "CheckBox", INK)

	var sep := StyleBoxFlat.new()
	sep.bg_color = Color(0.13, 0.11, 0.09, 0.55)
	sep.content_margin_top = 2.0
	sep.content_margin_bottom = 2.0
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)
	return t

# 兼容旧引用的色常量（战斗/视图仍在用）
const C_BG := Color("12100c")
const C_PANEL := Color("e9dfc6e6")
const C_TEXT := Color("221d17")
const C_DIM := Color("4a4238")
const C_GOLD := Color("c9a067")
const C_HP := Color("b03a2e")
const C_MP := Color("3f545c")
const C_YIDE := Color("c9803a")
const C_GOOD := Color("5a7a3a")
const C_BAD := Color("b03a2e")
