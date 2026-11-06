extends SceneTree
## 截图巡检：GUI 模式下逐视图渲染并截图（需非 headless 运行）
## 运行：Godot_console.exe --path . --script .zcode/tests/screenshot_tour.gd

var GS: Node
func GS_BATTLE() -> Node: return root.get_node("Battle")
var frame := 0
var stage := 0
var main: Node
var move_start := -1   # 移动回归检查：按住 D 前的玩家格 x
var move_ms := 0       # 移动回归检查：按下时刻（真实时间）
const OUT := "res://.zcode/shots/"

func _initialize() -> void:
	OS.set_environment("JH_TOUCH", "1")   # 强制显示触屏 HUD，巡检虚拟按键布局
	var GDB: Node = root.get_node("GameDB")
	GS = root.get_node("GameState")
	GDB.load_all()
	GS.reset()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)

func _snap(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("SNAP ", name)

func _process(_d: float) -> bool:
	frame += 1
	if frame % 12 != 0:
		return false
	match stage:
		0:
			_snap("01_title")
			main.switch_to("create")
		1:
			_snap("02_create")
			GS.new_game({"name": "沈青崖", "weapon": "剑", "attrs": {"臂力": 5, "体质": 4, "敏捷": 3, "悟性": 2, "福缘": 1}, "trait": "t_xianfa"})
			main.switch_to("town", {"map": "village"})
		2:
			_snap("03_village")
			# 虚拟方向键接线检查：▲ 按下应使 held_dir = 上
			var tctrl: Node = main.views["town"].get_node_or_null("TouchControls")
			if tctrl != null:
				var up_btn: Button = tctrl.get_child(0)
				up_btn.button_down.emit()
				print("TOUCHCHECK held_dir_up=", tctrl.held_dir == Vector2i(0, -1))
				up_btn.button_up.emit()
				print("TOUCHCHECK released=", tctrl.held_dir == Vector2i.ZERO)
			else:
				print("TOUCHCHECK MISSING TouchControls")
			# 移动回归检查：合成按住 D（与 PC 键盘同一条 is_action_pressed 轮询路径）
			var town: Node = main.views["town"]
			move_start = town.px
			move_ms = Time.get_ticks_msec()
			var ev := InputEventKey.new()
			ev.keycode = KEY_D
			ev.physical_keycode = KEY_D
			ev.pressed = true
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
			print("KEYCHECK has_action=", InputMap.has_action("move_right"),
				" is_key_pressed=", Input.is_key_pressed(KEY_D),
				" is_action_pressed=", Input.is_action_pressed("move_right"))
		3:
			# 等满 0.5s（平滑移动按真实时间累计，与帧率无关）再检查
			if Time.get_ticks_msec() - move_ms < 500:
				return false
			var town: Node = main.views["town"]
			_snap("03b_village_moved")
			print("MOVECHECK start_px=", move_start, " now_px=", town.px, " moved=", town.px != move_start)
			var ev2 := InputEventKey.new()
			ev2.keycode = KEY_D
			ev2.physical_keycode = KEY_D
			ev2.pressed = false
			Input.parse_input_event(ev2)
			main.switch_to("world", {"node": "village"})
		4:
			_snap("04_worldmap")
			main.switch_to("town", {"map": "jiangzhou"})
		5:
			_snap("05_jiangzhou")
			var town: Node = main.views["town"]
			town.panels.status_panel()
		6:
			_snap("06_status")
			# 切到云同步页签（第 6 个）
			var tabs: TabContainer = null
			for pc in main.views["town"].panels.get_children():
				for vb in pc.get_children():
					for c in vb.get_children():
						if c is TabContainer:
							tabs = c
			if tabs != null:
				tabs.current_tab = 5
			else:
				print("CLOUDTAB MISSING")
		7:
			_snap("07_cloud")
			var town: Node = main.views["town"]
			town.panels._clear()
			town.panels.npc_dialog("xuanchen")
		8:
			_snap("08_dialog")
			var town: Node = main.views["town"]
			town.panels._clear()
			town.panels.shop_panel("shop_wuqi")
		9:
			_snap("09_shop")
			var town: Node = main.views["town"]
			town.panels._clear()
			main.switch_to("battle", {"name": "巡检·狼群", "enemies": [{"enemy": "wolf", "pos": [0, 0]}, {"enemy": "wolf_alpha", "pos": [2, 1]}], "formation": "tiangang", "back": "town", "map": "village"})
		10:
			_snap("10_battle")
			var bv: Node = main.views["battle"]
			var hero: Dictionary = GS_BATTLE().units[0] if GS_BATTLE().units.size() > 0 else {}
			if not hero.is_empty() and not GS_BATTLE().finished:
				GS_BATTLE().use_move(hero, 0, {})
		11:
			_snap("11_battle2")
			var bv: Node = main.views["battle"]
			bv._finish()
		12:
			_snap("12_after_battle")
			GS.quest_states["m8"] = {"state": "active", "step": 0}
			main.switch_to("ending")
		13:
			_snap("13_ending")
			print("TOUR DONE")
			quit(0)
			return true
	stage += 1
	return false
