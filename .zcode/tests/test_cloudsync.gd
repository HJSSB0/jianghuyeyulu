extends SceneTree
## 云同步端到端测试（需先启动服务器：node server/save_server.mjs 8787）
## 运行：Godot --headless --path . --script .zcode/tests/test_cloudsync.gd
## 退出码：0=全部通过  1=有失败项  2=服务器不可达（跳过）

const BASE := "http://127.0.0.1:8787"

var _pass := 0
var _fail := 0
var GDB: Node
var GS: Node
var SV: Node
var CS: Node

func check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  ✗ FAIL: ", name)

func section(s: String) -> void:
	print("== ", s, " ==")

func _initialize() -> void:
	GDB = root.get_node("GameDB")
	GS = root.get_node("GameState")
	SV = root.get_node("SaveSystem")
	CS = root.get_node("CloudSync")
	GDB.load_all()
	GS.reset()
	seed(20261105)
	print("《江湖夜雨录》云同步端到端测试开始")
	_run()

## 调 CloudSync 方法并等待回调：meth ∈ register/peek/pull/push；args 不含 cb；→ [ok, data]
func _req(meth: String, args: Array) -> Array:
	var out: Array = [false, {}]
	var flag: Array = [false]
	var cb := func(ok: bool, data: Dictionary):
		out[0] = ok
		out[1] = data
		flag[0] = true
	var a := args.duplicate()
	a.append(cb)
	CS.callv(meth, a)
	var ticks := 0
	while not flag[0] and ticks < 900:   # 看门狗：~15 秒
		await process_frame
		ticks += 1
	if not flag[0]:
		out[1] = {"error": "请求超时"}
	return out

func _probe() -> bool:
	var h := HTTPRequest.new()
	root.add_child(h)
	h.timeout = 3.0
	var err := h.request(BASE + "/health")
	if err != OK:
		h.queue_free()
		return false
	var res: Array = await h.request_completed
	h.queue_free()
	return int(res[0]) == HTTPRequest.RESULT_SUCCESS and String(res[3].get_string_from_utf8()).contains("\"ok\":true")

func _run() -> void:
	await process_frame   # 等 root 入树（_initialize 阶段 HTTPRequest 尚不可用）
	if not await _probe():
		print("服务器 %s 不可达 → 跳过端到端（先运行：node server/save_server.mjs）" % BASE)
		quit(2)
		return
	var user := "t%d" % int(Time.get_unix_time_from_system())
	CS.save_config(BASE, user, "1234")

	section("注册与鉴权")
	var r := await _req("register", [user, "1234"])
	check(r[0], "注册成功")
	r = await _req("register", [user, "1234"])
	check(not r[0], "重复注册被拒")
	# 错误 PIN：peek 只认配置内账号，直接走 _post 携带错误凭证
	var wrong: Array = [false, {}]
	var wflag: Array = [false]
	CS._post("/peek", {"user": user, "pin": "9999"}, func(ok: bool, data: Dictionary):
		wrong[0] = ok
		wrong[1] = data
		wflag[0] = true)
	var wt := 0
	while not wflag[0] and wt < 900:
		await process_frame
		wt += 1
	check(not wrong[0], "错误 PIN 被拒")

	section("上传与拉取")
	GS.new_game({"name": "云端侠", "weapon": "剑", "attrs": {}, "trait": ""})
	GS.add_money(1000)
	var d0: Dictionary = GS.to_save()
	r = await _req("push", [])
	check(r[0], "上传成功")
	r = await _req("peek", [])
	check(r[0] and bool(r[1].get("exists", false)) and int(r[1].get("pushed_at_ms", 0)) > 0, "peek：云端存在且有时间戳")
	var cloud_ms := int(r[1].get("pushed_at_ms", 0))
	GS.reset()   # 模拟新设备：本地空白
	r = await _req("pull", [])
	var sd: Dictionary = r[1].get("save", {})
	check(r[0] and str(sd.get("player_name", "")) == "云端侠", "拉取到上传者进度")
	check(int(sd.get("money_tong", 0)) == int(d0["money_tong"]), "拉取数据与上传一致")
	check(SV.apply_save_dict(sd), "云端字典应用到 GameState")
	check(GS.player_name == "云端侠", "应用后姓名还原")
	check(int(GS.money_tong) == int(d0["money_tong"]), "应用后货币还原")
	check(SV.write_save_dict(sd) and SV.load_game() and GS.player_name == "云端侠", "落地本地槽并可 load_game")

	section("冲突裁决 verdict")
	check(CS.verdict(2000000, 1000000) == 1, "本地较新 → 1")
	check(CS.verdict(1000000, 2000000) == -1, "云端较新 → -1")
	check(CS.verdict(1000000, 1000000) == 0, "两端接近 → 0（人工裁决）")
	check(CS.verdict(0, 5000000) == -1, "无本地档 → 云端优先")
	check(CS.verdict(5000000, 0) == 1, "云端为空 → 本地优先")

	section("自动同步守门 auto_push")
	# 云端较新时不得覆盖
	GS.add_money(777)
	SV.last_saved_at_ms = cloud_ms - 600000   # 本地"10 分钟前"
	CS.auto_push()
	await create_timer(1.0).timeout
	r = await _req("peek", [])
	check(int(r[1].get("pushed_at_ms", 0)) == cloud_ms, "云端较新 → auto_push 不覆盖")
	# 本地较新时静默上传
	SV.last_saved_at_ms = int(Time.get_unix_time_from_system() * 1000.0) + 5000
	CS.auto_push()
	await create_timer(1.0).timeout
	r = await _req("peek", [])
	check(int(r[1].get("pushed_at_ms", 0)) > cloud_ms, "本地较新 → auto_push 已上传")

	print("")
	print("结果：PASS=%d FAIL=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
