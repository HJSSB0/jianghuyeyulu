extends RefCounted
## UITheme —— 暗色水墨风主题（代码生成，中文用系统字体）

static func make_theme() -> Theme:
	var t := Theme.new()
	# 中文字体：内嵌 Noto Sans SC（跨平台一致，iOS 无雅黑/SimHei），系统字体作回退
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

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("141a24")
	bg.border_color = Color("3a4a5f")
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 10.0
	bg.content_margin_right = 10.0
	bg.content_margin_top = 6.0
	bg.content_margin_bottom = 6.0

	var bg_dark := bg.duplicate()
	bg_dark.bg_color = Color("0e131b")

	var bg_accent := bg.duplicate()
	bg_accent.bg_color = Color("2a3040")
	bg_accent.border_color = Color("c9a067")

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("232c3b")
	btn.border_color = Color("4a5a70")
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.content_margin_left = 12.0
	btn.content_margin_right = 12.0
	btn.content_margin_top = 4.0
	btn.content_margin_bottom = 4.0

	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color("33415a")
	btn_hover.border_color = Color("c9a067")

	var btn_pressed := btn.duplicate()
	btn_pressed.bg_color = Color("1a2230")

	var btn_disabled := btn.duplicate()
	btn_disabled.bg_color = Color("1a1f28")
	btn_disabled.border_color = Color("2a3240")

	t.set_stylebox("panel", "PanelContainer", bg)
	t.set_stylebox("panel", "Panel", bg)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("normal", "LineEdit", bg_dark)
	t.set_stylebox("focus", "LineEdit", bg_accent)
	t.set_stylebox("panel", "ScrollContainer", bg_dark)

	t.set_color("font_color", "Label", Color("c9d4e0"))
	t.set_color("font_color", "Button", Color("c9d4e0"))
	t.set_color("font_hover_color", "Button", Color("f0e6c8"))
	t.set_color("font_disabled_color", "Button", Color("5a6470"))
	t.set_color("default_color", "RichTextLabel", Color("c9d4e0"))

	var sep := StyleBoxFlat.new()
	sep.bg_color = Color("3a4a5f")
	sep.content_margin_top = 2.0
	sep.content_margin_bottom = 2.0
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)
	return t

const C_BG := Color("141a24")
const C_PANEL := Color("1a2230cc")
const C_TEXT := Color("c9d4e0")
const C_DIM := Color("7a8aa0")
const C_GOLD := Color("c9a067")
const C_HP := Color("b84a4a")
const C_MP := Color("4a7ab8")
const C_YIDE := Color("c98a3a")
const C_GOOD := Color("7ab86a")
const C_BAD := Color("c96a5a")
