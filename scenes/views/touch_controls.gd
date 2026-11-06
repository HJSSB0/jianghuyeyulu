extends Control
## TouchControls —— 触屏虚拟操控层：左下方向键（按住持续移动）+ 右下动作按钮。
## 仅触屏/移动端显示；桌面端设环境变量 JH_TOUCH=1 可强制开启（调试/截图巡检）。
## 键位与桌面一一对应：方向=移动，交互=E，行囊=M，炼制=C，保存=F5。

const SIZE := 56.0   # 单键尺寸（960×540 逻辑坐标下 ≥44pt 触控目标，iPhone 横屏约再放大 1.57 倍）
const PAD := 10.0

var town: Node
var held_dir := Vector2i.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 仅真实触屏设备显示；桌面端 emulate_touch_from_mouse 会令 is_touchscreen_available()
	# 误报 true，需排除（PC 玩家用 WASD/点击双轨，无需虚拟键）。JH_TOUCH=1 仍可强制开启。
	var emu_mouse: bool = bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse"))
	visible = OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android") \
		or (DisplayServer.is_touchscreen_available() and not emu_mouse) \
		or OS.get_environment("JH_TOUCH") == "1"
	if not visible:
		return
	_build_dpad()
	_build_actions()

## 供 town_view 轮询的当前按住方向
func get_dir() -> Vector2i:
	return held_dir

func _btn_style(accent := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.24, 0.12, 0.80) if accent else Color(0.10, 0.13, 0.19, 0.72)
	sb.border_color = Color("c9a067") if accent else Color("4a5a70")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	return sb

func _mk_btn(text: String, pos: Vector2, sz: Vector2, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.add_theme_font_size_override("font_size", 15)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _btn_style(accent))
	b.add_theme_color_override("font_color", Color("f0e6c8") if accent else Color("c9d4e0"))
	b.z_index = 50
	add_child(b)
	return b

func _build_dpad() -> void:
	var o := Vector2(PAD, 540.0 - PAD - SIZE * 3.0)
	var up := _mk_btn("▲", o + Vector2(SIZE, 0), Vector2(SIZE, SIZE))
	var down := _mk_btn("▼", o + Vector2(SIZE, SIZE * 2.0), Vector2(SIZE, SIZE))
	var left := _mk_btn("◀", o + Vector2(0, SIZE), Vector2(SIZE, SIZE))
	var right := _mk_btn("▶", o + Vector2(SIZE * 2.0, SIZE), Vector2(SIZE, SIZE))
	_wire_dir(up, Vector2i(0, -1))
	_wire_dir(down, Vector2i(0, 1))
	_wire_dir(left, Vector2i(-1, 0))
	_wire_dir(right, Vector2i(1, 0))

func _wire_dir(b: Button, dir: Vector2i) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): held_dir = dir)
	b.button_up.connect(func():
		if held_dir == dir:
			held_dir = Vector2i.ZERO)

func _build_actions() -> void:
	var s := SIZE + 6.0
	var o := Vector2(960.0 - PAD - s * 2.0, 540.0 - PAD - s * 2.0)
	_wire_act(_mk_btn("行囊", o, Vector2(SIZE, SIZE)), "menu")
	_wire_act(_mk_btn("炼制", o + Vector2(s, 0), Vector2(SIZE, SIZE)), "craft")
	_wire_act(_mk_btn("保存", o + Vector2(0, s), Vector2(SIZE, SIZE)), "save")
	_wire_act(_mk_btn("交互", o + Vector2(s, s), Vector2(SIZE, SIZE), true), "interact")

func _wire_act(b: Button, action: String) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		if town != null and town.has_method("touch_action"):
			town.touch_action(action))
