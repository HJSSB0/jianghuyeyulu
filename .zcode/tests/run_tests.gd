extends SceneTree
## 《江湖夜雨录》headless 冒烟测试
## 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path . --script .zcode/tests/run_tests.gd

var _pass := 0
var _fail := 0
var _fail_names: Array = []
var GDB: Node
var GS: Node
var BT: Node
var SV: Node

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
	BT = root.get_node("Battle")
	SV = root.get_node("SaveSystem")
	# --script 模式下 autoload 的 _ready 要到主循环首轮才触发，这里手动初始化
	GDB.load_all()
	GS.reset()
	seed(20261105)
	print("《江湖夜雨录》逻辑层冒烟测试开始")
	test_gamedb()
	test_gamestate_newgame()
	test_growth()
	test_economy()
	test_quests()
	test_battle()
	test_social()
	test_save()
	test_save_v2()
	print("")
	print("结果：PASS=%d FAIL=%d" % [_pass, _fail])
	if _fail > 0:
		print("失败项：", _fail_names)
	quit(0 if _fail == 0 else 1)

# ---------- 1. 数据层 ----------
func test_gamedb() -> void:
	section("GameDB 数据加载与校验")
	check(GDB.wuxue.size() == 38, "武学 38 门（实际 %d）" % GDB.wuxue.size())
	check(GDB.items.size() >= 60, "物品 ≥60（实际 %d）" % GDB.items.size())
	check(GDB.npcs.size() >= 30, "NPC ≥30（实际 %d）" % GDB.npcs.size())
	check(GDB.quests.size() >= 20, "任务 ≥20（实际 %d）" % GDB.quests.size())
	check(GDB.enemies.size() >= 15, "敌人 ≥15（实际 %d）" % GDB.enemies.size())
	check(GDB.encounters.size() >= 10, "奇遇 ≥10（实际 %d）" % GDB.encounters.size())
	check(GDB.traits.size() >= 15, "特性 ≥15（实际 %d）" % GDB.traits.size())
	check(GDB.meridians.size() == 8, "经脉 8 条")
	check(GDB.formations.size() == 4, "阵法 4 种")
	check(GDB.world.has("nodes"), "世界图节点存在")
	check(GDB.world["nodes"].size() == 10, "世界节点 10 个")
	check(GDB.maps.size() == 10, "地图 10 张")
	check(GDB.last_errors.is_empty(), "引用完整性校验零错误 %s" % str(GDB.last_errors.slice(0, 3)))
	check(GDB.get_wuxue("jian_tianhe").get("grade", "") == "甲", "天河剑法为甲级")
	check(GDB.move_of("jian_tiejian", 4).get("ult", false), "铁剑十三式第5式为绝招")
	check(GDB.grade_rank("丁") < GDB.grade_rank("甲"), "品级排序正确")

# ---------- 2. 开局 ----------
func test_gamestate_newgame() -> void:
	section("GameState 开局与面板")
	GS.new_game({"name": "测试侠", "weapon": "剑", "attrs": {"臂力": 5, "体质": 4, "敏捷": 3, "悟性": 2, "福缘": 1}, "trait": "t_lixia"})
	check(GS.inited, "开局初始化")
	check(GS.player_name == "测试侠", "姓名生效")
	check(GS.traits.has("t_lixia"), "开局特性生效")
	var p: Dictionary = GS.get_panel()
	check(p["atk"] > 15, "面板攻击>15（%d）" % p["atk"])
	check(p["hp_max"] > 100, "面板气血>100（%d）" % p["hp_max"])
	check(GS.hp == p["hp_max"], "开局满血")
	check(GS.equipped["套路"] == "jian_jichu", "剑系默认装套路")
	check(GS.count_item("c_mantou") == 3, "初始物品")

# ---------- 3. 养成 ----------
func test_growth() -> void:
	section("养成：经验/武学/经脉/品格/名声")
	var need0: int = GS.exp_need(1)
	GS.add_exp(need0)
	check(GS.lv == 2, "升级正常（lv=%d）" % GS.lv)
	GS.add_xiuwei("jian_jichu", 999)
	check(GS.wuxue_lv("jian_jichu") == 2, "修为突破第2重")
	GS.equip_wuxue("套路", "quan_jichu")
	check(GS.equipped["套路"] == "quan_jichu", "切换套路")
	GS.zhenqi = 1000
	var r: String = GS.open_meridian("shou_jueyin", "shun")
	check(r == "ok", "顺通手厥阴（%s）" % r)
	check(GS.meridians["shou_jueyin"] == "shun", "经脉方向记录")
	r = GS.open_meridian("shou_jueyin", "ni")
	check(r == "已通", "已通经脉不可重复")
	GS.zhenqi = 100
	r = GS.open_meridian("ren_mai", "shun")
	check(r == "真气不足", "真气不足拦截")
	GS.add_morality("仁", 150)
	check(GS.morality["仁"] == 100, "品格钳制±100")
	GS.add_fame(500)
	check(GS.fame_name() == "威震江湖", "名声等级")
	GS.add_affinity("liumianmian", 40)
	check(GS.get_affinity("liumianmian") == 40, "好感累计")
	# 时辰推进
	var q0: int = GS.abs_quarter
	GS.advance_time(10)
	check(GS.abs_quarter == q0 + 10, "绝对刻推进")
	check(GS.zhenqi >= 10, "时辰推进回真气")

# ---------- 4. 经济 ----------
func test_economy() -> void:
	section("经济：货币/背包/商店/采集")
	GS.add_money(1000)
	check(GS.can_afford(500), "可支付")
	var t0: int = GS.money_total()
	GS.add_item("m_caoy", 5)
	GS.remove_item("m_caoy", 2)
	check(GS.count_item("m_caoy") == 3, "背包增删")
	check(not GS.remove_item("m_caoy", 99), "超量删除被拒")
	var bought: String = GS.buy("c_jinchuang", 60)
	check(bought == "ok" and GS.count_item("c_jinchuang") >= 1, "购买成功")
	check(GS.money_total() == t0 - 60, "货币扣减")
	var sold: bool = GS.sell("m_caoy")
	check(sold, "售卖成功")
	check(not GS.sell("q_suiyu") if GS.count_item("q_suiyu") <= 0 else true, "任务物/无货不可卖")
	# 采集：找一个采药点
	var out: Dictionary = GS.do_gather("vg_herb")
	check(out["ok"], "采集成功（%s）" % str(out.get("msg")))
	var out2: Dictionary = GS.do_gather("vg_herb")
	check(not out2["ok"], "采集冷却生效")
	# 押注
	var m_before: int = GS.money_total()
	GS.add_money(1000)
	GS.apply_effect({"gamble": {"stake": 100, "win_mult": 2, "chance": 45}})
	check(GS.money_total() != m_before + 1000, "赌坊有输赢变化")

# ---------- 5. 任务 ----------
func test_quests() -> void:
	section("任务系统（数据驱动 do 钩子）")
	GS.new_game({"name": "任务侠", "weapon": "剑", "attrs": {}, "trait": ""})
	GS._auto_start()
	check(GS.quest_state("m1") == "active", "主线 m1 自动激活")
	check(GS.quest_state("m2") == "none", "m2 尚未解锁")
	GS.quest_hook({"type": "talk", "npc": "gu_laozhang"})
	check(GS.quest_step("m1") == 1, "m1 第一步推进")
	GS.quest_hook({"type": "talk", "npc": "xuanchen"})
	check(GS.quest_state("m1") == "done", "m1 完成发奖")
	check(GS.quest_state("m2") == "active", "m2 自动衔接")
	# m2: 小满→刘二→玄尘
	GS.quest_hook({"type": "talk", "npc": "gu_xiaoman"})
	GS.quest_hook({"type": "talk", "npc": "liu_er"})
	GS.quest_hook({"type": "talk", "npc": "xuanchen"})
	check(GS.quest_state("m3") == "active", "m3 衔接")
	# m3: visit + talk_any + join_faction
	GS.quest_hook({"type": "visit", "map": "jiangzhou"})
	GS.quest_hook({"type": "talk", "npc": "lin_jianxin"})
	check(GS.quest_step("m3") == 2, "m3 talk_any 匹配")
	GS.join_faction("tiejianmen")
	GS.quest_hook({"type": "join_faction"})
	check(GS.quest_state("m3") == "done", "m3 拜师完成")
	check(GS.traits.has("t_jianshin"), "门派特性获得")
	# m4 招募
	GS.recruit("liumianmian")
	check(GS.party.has("liumianmian"), "随从入队")
	check(GS.quest_state("m4") == "done", "m4 招募完成")
	# m5 杀头狼
	GS.quest_hook({"type": "visit", "map": "wild_north"})
	GS.quest_hook({"type": "kill", "enemy": "wolf_alpha"})
	check(GS.quest_state("m5") == "done", "m5 头狼击杀")
	# m6 黑市+教众
	GS.quest_hook({"type": "talk", "npc": "guishou"})
	GS.quest_hook({"type": "kill", "enemy": "baiyue_adept"})
	check(GS.quest_state("m6") == "done", "m6 完成")
	check(GS.count_item("q_baiyueling") == 1, "拜月令入包")
	# m7 酉时后(>=9)访问
	GS.shichen = 3
	GS.quest_hook({"type": "visit", "map": "wild_west"})
	check(GS.quest_step("m7") == 0, "酉时前不推进 m7")
	GS.shichen = 10
	GS.quest_hook({"type": "visit", "map": "wild_west"})
	check(GS.quest_step("m7") == 1, "戌时后推进 m7")
	check(GS.quest_state("m7") == "active", "m7 等待击杀护法")
	GS.quest_hook({"type": "kill", "enemy": "baiyue_guard"})
	check(GS.quest_state("m7") == "done", "m7 护法战完成")
	check(GS.quest_state("m8") == "active", "m8 结局选择激活")
	check(GS.flags.get("m7_boss_down", false), "护法旗标")
	# 悬赏
	var ok: bool = GS.accept_bounty("bounty_c1")
	check(ok and GS.quest_state("bounty_c1") == "active", "接悬赏")
	GS.add_item("m_tiekuang", 3)
	GS.quest_hook({"type": "collect", "item": "m_tiekuang"})
	check(GS.quest_state("bounty_c1") == "done", "悬赏收集完成")
	# 随从任务 hidden 推进
	GS.start_quest("f_liu1", true)
	GS.quest_hook({"type": "hidden", "id": "nh_relic"})
	check(GS.quest_step("f_liu1") == 1, "遗物隐藏点推进")
	GS.quest_hook({"type": "talk", "npc": "liumianmian"})
	check(GS.quest_state("f_liu1") == "done", "遗物任务完成")
	check(GS.traits.has("t_zhongqing"), "重情特性获得")

# ---------- 6. 战斗 ----------
func test_battle() -> void:
	section("战斗：ATB/战意/阵法/战棋走位/朝向/状态/AI")
	BT._rng.seed = 20261105  # 固定战斗内部 RNG，保证可回归
	# 6.1 自动战斗能分出胜负
	GS.new_game({"name": "战侠", "weapon": "刀", "attrs": {"臂力": 6, "体质": 5, "敏捷": 4, "悟性": 2, "福缘": 1}, "trait": "t_lixia"})
	GS.learn_wuxue("dao_poshan"); GS.equip_wuxue("套路", "dao_poshan")
	BT.setup({"name": "测试·狼群", "enemies": [{"enemy": "wolf", "pos": [0, 0]}, {"enemy": "wolf", "pos": [2, 0]}], "formation": "meihua", "spar": false})
	check(BT.GRID_W == 9 and BT.GRID_H == 7, "战棋战场 9×7")
	check(BT.obstacles.size() > 0, "战场障碍确定性生成")
	var res: Dictionary = BT.run_auto()
	check(BT.finished, "自动战斗收敛")
	check(res.get("win", false), "高配主角胜灰狼")
	check(res.get("exp", 0) > 0, "胜利有经验")
	# 6.2 ATB 顺序：高身法先动
	BT.setup({"name": "测试·顺序", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "spar": true})
	var hero: Dictionary = BT.units[0]
	hero["spd"] = 20
	var wolf: Dictionary = BT.units[1]
	wolf["spd"] = 8
	hero["gauge"] = 0; wolf["gauge"] = 0
	var actor: Dictionary = BT.tick_until_ready()
	check(actor.get("id", "") == "hero", "高身法先手")
	check(int(actor.get("steps_left", 0)) > 0, "就绪单位获移动力")
	# 6.3 战意绝招
	hero["yide"] = 100
	hero["mp"] = 100
	hero["hit"] = 200  # 保证命中，行为确定
	var mv_arr: Array = BT.moves_of(hero)
	var ult_idx := -1
	for i in mv_arr.size():
		if mv_arr[i].get("ult", false): ult_idx = i
	check(ult_idx >= 0, "套路含绝招")
	var foe0: Dictionary = BT.alive_of("enemy")[0]
	BT.use_move(hero, ult_idx, {"cell": Vector2i(foe0["x"], foe0["y"])})
	check(hero["yide"] < 100, "绝招消耗 100 战意（剩余%d）" % hero["yide"])
	# 6.4 必爆清空
	hero["yide"] = 200
	var foes2: Array = BT.alive_of("enemy")
	if foes2.size() > 0:
		hero["hit"] = 200
		BT.use_move(hero, 0, {"cell": Vector2i(foes2[0]["x"], foes2[0]["y"])})
		check(hero["yide"] == 12, "满战意攻击后清零并回攒12（实际%d）" % hero["yide"])
	# 6.5 战棋走位与阻挡
	BT.setup({"name": "测试·走位", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "spar": true})
	hero = BT.units[0]
	var mr: Array = BT.move_range(hero)
	check(mr.size() > 0, "移动范围非空")
	check(not (Vector2i(hero["x"], hero["y"]) in mr), "移动范围不含自身")
	check(not (Vector2i(BT.GRID_W, 3) in mr), "移动范围不出格")
	var occ: Dictionary = BT.alive_of("enemy")[0]
	check(not (Vector2i(occ["x"], occ["y"]) in mr), "敌占格不可入")
	check(BT.move_to(hero, Vector2i(2, 3)), "走格成功")
	check(Vector2i(hero["x"], hero["y"]) == Vector2i(2, 3), "坐标更新")
	check(hero["facing"] == Vector2i(1, 0), "面向移动方向")
	check(not BT.move_to(hero, Vector2i(7, 3)), "超出移动力拒绝")
	# 6.6 突进贴脸
	BT.setup({"name": "测试·突进", "enemies": [{"enemy": "wolf", "pos": [0, 0]}, {"enemy": "wolf_alpha", "pos": [2, 1]}], "spar": true})
	BT.obstacles.clear()  # 突进落点确定性
	hero = BT.units[0]
	hero["wuxue"] = "jian_tiejian"  # 铁剑十三式第4式"剑贯长虹"=突进
	hero["mp"] = 100
	hero["hit"] = 200
	hero["crit"] = 0
	var jian_moves: Array = BT.moves_of(hero)
	var rush_idx := -1
	for i in jian_moves.size():
		if jian_moves[i].get("target", "") == "突进": rush_idx = i
	check(rush_idx >= 0, "存在突进招式")
	var alpha_arr: Array = BT.alive_of("enemy").filter(func(u): return u.get("eid", "") == "wolf_alpha")
	check(alpha_arr.size() == 1, "远目标在场")
	var alpha: Dictionary = alpha_arr[0]
	var hp_a: int = alpha["hp"]
	BT.use_move(hero, rush_idx, {"cell": Vector2i(alpha["x"], alpha["y"])})
	check(alpha["hp"] < hp_a, "突进命中远目标")
	check(absi(hero["x"] - alpha["x"]) + absi(hero["y"] - alpha["y"]) == 1, "突进后贴脸")
	# 6.7 背击加成（关暴击保证确定性）
	BT.setup({"name": "测试·背击", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "spar": true})
	BT.obstacles.clear()
	hero = BT.units[0]
	hero["hit"] = 200
	hero["crit"] = 0
	var w: Dictionary = BT.alive_of("enemy")[0]
	w["hp_max"] = 999
	w["hp"] = 999   # 防止第一刀打死，保证两刀可比
	w["facing"] = Vector2i(-1, 0)   # 正面迎敌
	var hp_front0: int = w["hp"]
	BT.use_move(hero, 0, {"cell": Vector2i(w["x"], w["y"])})
	var dmg_front: int = hp_front0 - w["hp"]
	w["facing"] = Vector2i(1, 0)    # 背对主角
	hero["gauge"] = BT.ATB_MAX
	hero["cds"].clear()             # 清冷却/补内力，保证第二刀可出
	hero["mp"] = 100
	w["hp"] = 999
	var hp_back0: int = w["hp"]
	BT.use_move(hero, 0, {"cell": Vector2i(w["x"], w["y"])})
	var dmg_back: int = hp_back0 - w["hp"]
	check(dmg_back > dmg_front, "背击伤害高于正面（%d > %d）" % [dmg_back, dmg_front])
	check(w["facing"] == Vector2i(-1, 0), "受击后转向攻击者")
	# 6.8 状态施加
	BT.setup({"name": "测试·状态", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "spar": true})
	hero = BT.units[0]
	hero["wuxue"] = "quan_liehu"; hero["mp"] = 100; hero["hit"] = 200
	var tgt: Dictionary = BT.alive_of("enemy")[0]
	var hp0: int = tgt["hp"]
	BT.use_move(hero, 1, {"cell": Vector2i(tgt["x"], tgt["y"])})
	check(tgt["statuses"].has("流血") or tgt["hp"] < hp0, "流血状态命中")
	# 6.9 阵法光环
	GS.formation = "tiangang"
	BT.setup({"name": "测试·阵法", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "formation": "tiangang", "spar": true})
	check(BT.get_formation_mods().has("atk") and BT.get_formation_mods().has("dr"), "天罡阵战前光环载入")
	GS.formation = "liuyun"
	BT.setup({"name": "测试·阵法2", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "formation": "liuyun", "spar": true})
	check(BT.get_formation_mods().has("gauge"), "流云阵集气光环载入")
	# 6.9b 演出事件流（伤害飘字/刀光）
	BT.setup({"name": "测试·演出", "enemies": [{"enemy": "wolf", "pos": [0, 0]}], "spar": true})
	hero = BT.units[0]
	hero["hit"] = 200
	hero["crit"] = 0
	BT.use_move(hero, 0, {"cell": Vector2i(BT.alive_of("enemy")[0]["x"], BT.alive_of("enemy")[0]["y"])})
	var fx_hit: Array = BT.fx_events.filter(func(x): return x["kind"] == "hit" and int(x["dmg"]) > 0)
	check(fx_hit.size() >= 1, "演出事件流：命中带伤害飘字")
	check(BT.fx_events.any(func(x): return x["kind"] == "slash"), "演出事件流：出手刀光")
	BT.clear_fx()
	check(BT.fx_events.is_empty(), "clear_fx 清空事件流")
	# 6.10 战败收敛
	BT.setup({"name": "测试·战败", "enemies": [{"enemy": "n_yeguhong", "pos": [0, 0]}, {"enemy": "n_yeguhong", "pos": [2, 2]}], "spar": false, "formation": "meihua"})
	GS.party.clear()
	var res2: Dictionary = BT.run_auto()
	check(BT.finished, "Boss 战收敛")
	# 6.11 切磋不死人
	BT.setup({"name": "测试·切磋", "enemies": [{"enemy": "n_liumianmian", "pos": [0, 0]}], "spar": true, "spar_npc": "liumianmian"})
	var res3: Dictionary = BT.run_auto()
	if res3.get("win", false):
		check(res3.get("spar", false), "切磋结算带标记")
	check(BT.log.size() > 3, "战斗日志生成")

# ---------- 7. 存档 ----------
func test_save() -> void:
	section("存档 roundtrip")
	GS.new_game({"name": "存档侠", "weapon": "拳", "attrs": {"臂力": 7}, "trait": "t_tiegu"})
	GS.add_money(1234)
	GS.add_item("m_lingzhi", 2)
	GS.add_morality("义", 30)
	GS.add_fame(88)
	GS.start_quest("m1", true)
	var ok: bool = SV.save_game()
	check(ok, "保存成功")
	GS.new_game({"name": "被覆盖者", "weapon": "剑", "attrs": {}, "trait": ""})
	ok = SV.load_game()
	check(ok, "读档成功")
	check(GS.player_name == "存档侠", "姓名还原")
	check(GS.money_total() >= 1234, "货币还原")
	check(GS.count_item("m_lingzhi") == 2, "背包还原")
	check(GS.morality["义"] == 30, "品格还原")
	check(GS.fame == 88, "名声还原")
	check(GS.quest_state("m1") == "active", "任务态还原")
	check(GS.weapon == "拳", "武器还原")
	SV.delete_save()
	check(not SV.has_save(), "删档生效")

# ---------- 8. 存档 v2：元数据 / 迁移 / 归一化 ----------
func test_save_v2() -> void:
	section("存档 v2：云同步元数据 / 版本迁移 / JSON 归一化")
	GS.new_game({"name": "云同步侠", "weapon": "剑", "attrs": {}, "trait": ""})
	var d: Dictionary = SV.export_save()
	check(int(d.get("version", 0)) == 2, "导出版本为 v2")
	check(int(d.get("saved_at_ms", 0)) > 0, "导出含真实时间戳")
	check(str(d.get("device_name", "")) != "", "导出含设备名")
	# JSON round-trip：数值 float 漂移 → 归一化还原为 int
	var j = JSON.parse_string(JSON.stringify(d))
	check(j is Dictionary, "JSON 序列化可解析")
	check(typeof(j["lv"]) == TYPE_FLOAT, "JSON 解析后数值变 float（前置条件）")
	check(SV.apply_save_dict(j), "apply_save_dict 应用成功")
	check(GS.player_name == "云同步侠", "云端字典应用：姓名还原")
	check(typeof(GS.lv) == TYPE_INT and GS.lv == 1, "归一化：lv 还原为 int")
	check(typeof(GS.money_tong) == TYPE_INT, "归一化：货币还原为 int")
	# v1 旧档迁移（无 saved_at_ms / device_name）
	var old = JSON.parse_string(JSON.stringify(GS.to_save()))
	old["version"] = 1
	old.erase("saved_at_ms")
	old.erase("device_name")
	var m: Dictionary = SV._migrate(old)
	check(int(m["version"]) == 2 and m.has("saved_at_ms") and m.has("device_name"), "v1 旧档迁移补元数据")
	# v0 局部档迁移
	var m0: Dictionary = SV._migrate({"version": 0, "player_name": "古董"})
	check(int(m0["version"]) == 2 and m0["formation"] == "meihua", "v0 档迁移补默认字段")
	# write_save_dict → load_game 落地闭环
	check(SV.write_save_dict(d), "云端字典落地本地槽")
	check(SV.load_game() and GS.player_name == "云同步侠", "落地后 load_game 还原")
	SV.delete_save()

# ---------- 8. 人际四层网与内容扩张 ----------
func test_social() -> void:
	section("人际：送礼/阈值奖励/贡献晋升/名声门槛 + 新内容")
	GS.new_game({"name": "礼侠", "weapon": "剑", "attrs": {"臂力": 4, "体质": 4, "敏捷": 4, "悟性": 3, "福缘": 1}, "trait": "t_lixia"})
	GS.add_item("g_dianxin", 3)
	GS.add_item("g_jiangnanchun", 2)
	# 8.1 送礼：至爱/厌恶/消耗
	var pv: Dictionary = GS.gift_preview("liumianmian", "g_dianxin")
	check(int(pv["delta"]) >= 3 and pv["mood"] == "至爱", "柳绵绵至爱点心（%s %+d）" % [pv["mood"], int(pv["delta"])])
	var aff0: int = GS.get_affinity("liumianmian")
	var out: Dictionary = GS.gift("liumianmian", "g_dianxin")
	check(out.get("ok", false) and GS.get_affinity("liumianmian") > aff0, "送礼落账好感上升")
	check(GS.count_item("g_dianxin") == 2, "礼物消耗 1 份")
	var pv2: Dictionary = GS.gift_preview("xuanchen", "g_jiangnanchun")
	check(pv2["mood"] == "厌恶" and int(pv2["delta"]) <= -1, "玄尘厌恶酒（礼签映射）")
	# 8.2 好感阈值奖励一次性
	var money0: int = GS.money_total()
	GS.affinity["liumianmian"] = 35
	GS.add_affinity("liumianmian", 0)
	check(GS.money_total() >= money0 + 300, "好感30阈值奖励到账")
	GS.add_affinity("liumianmian", 0)
	check(GS.money_total() == GS.money_total(), "阈值奖励不重复发放")
	# 8.3 门派贡献晋升（贡献 120 学镇岳剑诀）
	GS.faction = "tiejianmen"
	GS.faction_contrib = 0
	GS.add_contrib(120)
	check(GS.learned.has("jian_zhenyue"), "贡献120晋升镇岳剑诀")
	GS.add_contrib(50)
	check(GS.faction_contrib == 170, "贡献累计正确")
	# 8.4 悬赏名声门槛
	GS.fame = 0
	check(GS.bounty_locked("bounty_a2").get("locked", false), "甲级悬赏锁（名声<25）")
	check(not GS.bounty_locked("bounty_c5").get("locked", false), "丙级悬赏不锁")
	GS.fame = 30
	check(not GS.bounty_locked("bounty_a2").get("locked", false), "名声30解甲级")
	# 8.5 新内容载入
	check(GDB.get_map("wild_south") != {} and GDB.get_map("wild_east") != {}, "两张新野外图载入")
	check(GDB.get_wuxue("jian_zhenyue") != {} and GDB.get_wuxue("nei_guixi") != {}, "新武学载入")
	check(GDB.world["nodes"].has("wild_south") and GDB.world["nodes"].has("wild_east"), "世界节点接入")
	# 8.6 烟波支线链（m6 完成后自动接取，visit 推进）
	GS.quest_states["m6"] = {"state": "done", "step": 0}
	GS.quest_hook({"type": "visit", "map": "wild_west"})
	check(GS.quest_state("s_yan2") == "active", "烟波支线自动接取")
	GS.quest_hook({"type": "kill", "enemy": "baiyue_adept"})
	GS.quest_hook({"type": "kill", "enemy": "baiyue_adept"})
	check(GS.quest_step("s_yan2") == 2, "杀敌两步推进至回禀")
