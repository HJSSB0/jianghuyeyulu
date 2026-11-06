extends SceneTree
## 移动/寻路 headless 测试：A*（直线/绕障/不可达/防穿角）+ 双轨移动引擎（平滑步进/阻挡/
## 点击寻路走完/NPC 相邻落点/摄像机拾取逆变换/战斗归位）+ 回归 village 集成。
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/test_movement.gd

var _pass := 0
var _fail := 0
var _fail_names: Array = []
var GDB: Node
var GS: Node

func check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fail_names.append(name)
		print("  ✗ FAIL: ", name)

func section(s: String) -> void:
	print("== ", s, " ==")

func _initialize() -> void:
	GDB = root.get_node("GameDB")
	GS = root.get_node("GameState")
	GDB.load_all()
	GS.reset()
	seed(20261106)
	print("《江湖夜雨录》移动/寻路测试开始")
	test_pathfinding()
	test_step_engine()
	test_town_integration()
	print("")
	print("结果：PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		print("失败项：", _fail_names)
	quit(0 if _fail == 0 else 1)

# ---------- A* 纯逻辑 ----------

func _mk_walkable(rows: Array) -> Callable:
	return func(x: int, y: int) -> bool:
		if y < 0 or y >= rows.size() or x < 0 or x >= str(rows[y]).length():
			return false
		return str(rows[y])[x] == "."

func test_pathfinding() -> void:
	section("A* 寻路（直线/绕障/不可达/防穿角）")
	var PF := load("res://scripts/pathfinding.gd")
	# 直线
	var w1 := _mk_walkable(["...", "...", "..."])
	var p1: Array = PF.find_path(3, 3, w1, Vector2i(0, 0), Vector2i(2, 0), false)
	check(p1.size() == 2 and p1[0] == Vector2i(1, 0) and p1[1] == Vector2i(2, 0), "直线4向路径正确")
	# 绕墙列（墙只在 0-1 行，第 2 行可横向穿过）
	var w2 := _mk_walkable([".#.", ".#.", "..."])
	var p2: Array = PF.find_path(3, 3, w2, Vector2i(0, 0), Vector2i(2, 0), false)
	check(p2.size() == 6 and p2[0] == Vector2i(0, 1) and p2[p2.size() - 1] == Vector2i(2, 0), "绕障碍列路径正确（6 步）")
	# 封死不可达
	var w3 := _mk_walkable(["...", "###", "..."])
	var p3: Array = PF.find_path(3, 3, w3, Vector2i(1, 0), Vector2i(1, 2), false)
	check(p3.is_empty(), "封死目标返回空路径")
	# 目标格不可走
	var wb := _mk_walkable([".#.", "...", "..."])
	var p4: Array = PF.find_path(3, 3, wb, Vector2i(0, 0), Vector2i(1, 0), false)
	check(p4.is_empty(), "目标不可走直接返回空")
	# 起点即终点
	var p5: Array = PF.find_path(3, 3, w1, Vector2i(1, 1), Vector2i(1, 1), false)
	check(p5.is_empty(), "起点=终点返回空")
	# 防穿角：对角捷径被两侧墙规则禁止（AND 规则 → 2 步绕行而非 1 步穿角）
	var w6 := _mk_walkable(["...", ".#.", "..."])
	var p6: Array = PF.find_path(3, 3, w6, Vector2i(1, 0), Vector2i(2, 1), true)
	check(p6.size() == 2 and p6[0] == Vector2i(2, 0), "对角穿角被 AND 规则禁止，绕行走 2 步")

# ---------- 双轨移动引擎（合成地图，确定性） ----------

func _mk_town() -> Node:
	var tv: Node = load("res://scenes/views/town_view.gd").new()
	tv.on_enter({"map": "village"})
	return tv

func _synth_map(tv: Node, rows: Array) -> void:
	tv.map = {"id": "testmap", "grid": rows, "gathers": [], "hiddens": [], "events": []}
	tv.npc_positions = {}
	tv.px = 0
	tv.py = 0
	tv.pos_f = Vector2.ZERO
	tv.move_t = 1.0
	tv.walk_queue = []

func test_step_engine() -> void:
	section("双轨移动引擎（平滑步进/阻挡/寻路/拾取）")
	var tv := _mk_town()
	check(tv.px == 3 and tv.py == 1, "village 出生点 (3,1)")
	# —— 合成地图：0行全通，1行中段墙，2行全通
	_synth_map(tv, ["....", ".##.", "...."])
	# 无输入方向为零（headless 无键盘事件）
	check(tv._input_dir() == Vector2i.ZERO, "无输入时方向为零")
	# 键盘一步：起步→推进→落格
	var ok: bool = tv._begin_step(Vector2i(1, 0), Vector2i(1, 0))
	check(ok, "向可走格起步成功")
	for i in 120:
		tv._advance_step(1.0 / 60.0)
		if tv.move_t >= 1.0:
			break
	check(tv.px == 1 and tv.py == 0, "一步走完落格 (1,0)")
	check(tv.pos_f.distance_to(Vector2(1, 0)) < 0.001, "pos_f 吸附到格中心")
	# 墙格拒绝
	check(not tv._begin_step(Vector2i(2, 1), Vector2i(1, 1)), "墙格拒绝起步")
	check(tv.px == 1 and tv.py == 0 and tv.move_t >= 1.0, "撞墙不位移不锁步")
	# 防穿角：两侧正交格有墙时对角步被拒
	tv.px = 0
	tv.py = 1
	tv.pos_f = Vector2(0, 1)
	check(not tv._begin_step(Vector2i(1, 0), Vector2i(1, -1)), "对角穿角被拒（侧格为墙·上）")
	check(not tv._begin_step(Vector2i(1, 2), Vector2i(1, 1)), "对角穿角被拒（侧格为墙·下）")
	check(tv._begin_step(Vector2i(0, 0), Vector2i(0, -1)), "普通直行不受影响")
	for i in 120:
		tv._advance_step(1.0 / 60.0)
		if tv.move_t >= 1.0:
			break
	# 点击寻路：绕墙到 (3,2)
	tv._request_path(Vector2i(3, 2))
	check(tv.walk_queue.size() > 0, "点击寻路生成队列")
	var guard := 0
	while (tv.walk_queue.size() > 0 or tv.move_t < 1.0) and guard < 2000:
		tv._advance_step(1.0 / 30.0)
		if tv.move_t >= 1.0 and tv.walk_queue.size() > 0:
			var nxt: Vector2i = tv.walk_queue[0]
			var sd: Vector2i = nxt - Vector2i(tv.px, tv.py)
			if tv._begin_step(nxt, sd):
				tv.walk_queue.pop_front()
			else:
				break
		guard += 1
	check(tv.px == 3 and tv.py == 2, "寻路走完到达目标格 (3,2)")
	check(tv.walk_queue.is_empty(), "寻路队列消费完毕")
	# 不可达目标：2×2 封死格（目标与相邻全为墙 → 无 alt → 队列不变）
	_synth_map(tv, [".#", "##"])
	tv.px = 0
	tv.py = 0
	tv.pos_f = Vector2.ZERO
	tv._request_path(Vector2i(1, 1))
	check(tv.walk_queue.is_empty(), "点封闭墙块不改队列（无相邻可走改点）")
	# 拾取逆变换（摄像机偏移 0 与非 0）
	_synth_map(tv, ["....", "....", "...."])
	tv.cam = Vector2.ZERO
	check(tv._local_to_cell(Vector2(96 + 176, 40 + 48)) == Vector2i(5, 1), "拾取：cam=0 时屏幕点→格")
	tv.cam = Vector2(64, 32)
	check(tv._local_to_cell(Vector2(96 + 176, 40 + 48)) == Vector2i(7, 2), "拾取：cam 偏移补偿正确")
	tv.cam = Vector2.ZERO
	tv.free()

func test_town_integration() -> void:
	section("village 集成（真实地图寻路/NPC 相邻/归位/_process 冒烟）")
	var tv := _mk_town()
	# 找一个无 NPC 占位的可走格作为寻路目标
	var target := Vector2i(-1, -1)
	var g: Array = tv.map.get("grid", [])
	for y in range(1, g.size()):
		for x in str(g[y]).length():
			var c := Vector2i(x, y)
			if str(g[y])[x] == "." and c != Vector2i(tv.px, tv.py) and not tv.npc_positions.values().has(c):
				target = c
				break
		if target.x >= 0:
			break
	check(target.x >= 0, "找到无 NPC 可走目标格 %s" % [target])
	tv._request_path(target)
	check(tv.walk_queue.size() > 0, "真实地图寻路生成队列")
	var guard := 0
	while (tv.walk_queue.size() > 0 or tv.move_t < 1.0) and guard < 4000:
		tv._advance_step(1.0 / 30.0)
		if tv.move_t >= 1.0 and tv.walk_queue.size() > 0:
			var nxt: Vector2i = tv.walk_queue[0]
			var sd: Vector2i = nxt - Vector2i(tv.px, tv.py)
			if tv._begin_step(nxt, sd):
				tv.walk_queue.pop_front()
			else:
				break
		guard += 1
	check(Vector2i(tv.px, tv.py) == target, "真实地图寻路抵达目标")
	# 点 NPC 格 → 自动走到相邻可走格
	var npc_cell := Vector2i(-1, -1)
	for nid in tv.npc_positions:
		npc_cell = tv.npc_positions[nid]
		break
	if npc_cell.x >= 0:
		tv._request_path(npc_cell)
		check(tv.walk_queue.size() > 0, "点 NPC 生成相邻落点队列")
		var guard2 := 0
		while (tv.walk_queue.size() > 0 or tv.move_t < 1.0) and guard2 < 4000:
			tv._advance_step(1.0 / 30.0)
			if tv.move_t >= 1.0 and tv.walk_queue.size() > 0:
				var nxt2: Vector2i = tv.walk_queue[0]
				var sd2: Vector2i = nxt2 - Vector2i(tv.px, tv.py)
				if tv._begin_step(nxt2, sd2):
					tv.walk_queue.pop_front()
				else:
					break
			guard2 += 1
		var md := absi(tv.px - npc_cell.x) + absi(tv.py - npc_cell.y)
		check(md == 1, "NPC 相邻落点（曼哈顿距离=1，实际=%d）" % md)
	else:
		check(false, "village 无 NPC 可测")
	# 战斗归来按 payload.pos 归位（先验证 pos 本身可走且无 NPC）
	var home := Vector2i(-1, -1)
	for y in range(1, g.size()):
		for x in str(g[y]).length():
			var c2 := Vector2i(x, y)
			if str(g[y])[x] == "." and not tv.npc_positions.values().has(c2):
				home = c2
				break
		if home.x >= 0:
			break
	var tv2 := _mk_town()
	tv2.free()
	tv2 = load("res://scenes/views/town_view.gd").new()
	tv2.on_enter({"map": "village", "pos": [home.x, home.y]})
	check(tv2.px == home.x and tv2.py == home.y, "payload.pos 战斗归位")
	# 非法 pos（墙）回退出生点
	var tv3: Node = load("res://scenes/views/town_view.gd").new()
	tv3.on_enter({"map": "village", "pos": [0, 0]})
	check(tv3.px == 3 and tv3.py == 1, "非法 pos 回退出生点")
	# _process 冒烟（headless 跑一帧，含 action 轮询/摄像机/HUD）
	tv._process(1.0 / 60.0)
	check(true, "_process headless 冒烟无崩溃")
	tv.free()
	tv2.free()
	tv3.free()
