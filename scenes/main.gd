extends Node
## Main —— 根状态机：Title → CharCreate → World ⇄ Town ⇄ Battle → Ending

const UITheme := preload("res://scripts/ui_theme.gd")
const TitleView := preload("res://scenes/views/title_view.gd")
const CharCreateView := preload("res://scenes/views/char_create_view.gd")
const WorldView := preload("res://scenes/views/world_view.gd")
const TownView := preload("res://scenes/views/town_view.gd")
const BattleView := preload("res://scenes/views/battle_view.gd")
const EndingView := preload("res://scenes/views/ending_view.gd")

var views: Dictionary = {}
var current := ""

func _ready() -> void:
	get_tree().root.theme = UITheme.make_theme()
	var defs := {
		"title": TitleView, "create": CharCreateView, "world": WorldView,
		"town": TownView, "battle": BattleView, "ending": EndingView,
	}
	for k in defs:
		var v: Control = defs[k].new()
		v.name = k
		v.set("main", self)
		v.visible = false
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(v)
		views[k] = v
	switch_to("title")

func switch_to(name: String, payload: Dictionary = {}) -> void:
	for k in views:
		views[k].visible = false
	current = name
	views[name].visible = true
	if views[name].has_method("on_enter"):
		views[name].on_enter(payload)

func toast_panel(msg: String) -> void:
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", UITheme.C_GOLD)
	t.add_theme_stylebox_override("panel", _toast_style())
	t.position = Vector2(280, 8)
	t.size = Vector2(400, 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.z_index = 100
	add_child(t)
	var tw := t.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(t, "modulate:a", 0.0, 0.6)
	tw.tween_callback(t.queue_free)

func _toast_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0e131bee")
	sb.border_color = UITheme.C_GOLD
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb

func _ready_toast() -> void:
	EventBus.toast.connect(func(msg: String): toast_panel(msg))

func _enter_tree() -> void:
	call_deferred("_wire")

func _wire() -> void:
	_ready_toast()
	EventBus.ending_reached.connect(func(_id: String): switch_to("ending"))
