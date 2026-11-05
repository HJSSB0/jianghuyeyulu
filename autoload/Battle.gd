extends Node
## Battle —— 融合战斗引擎（纯逻辑，零渲染依赖）：
## 烟雨：九宫格 3×3 站位（上中下路×前中后排）、阵法加成、分路目标规则
## 大侠：ATB 时序条（身法决定集气速率）、战意 0-200（100 绝招 / 200 必爆）、突进类绕后+25%

const ATB_MAX := 1000
const YIDE_ULT := 100
const YIDE_CRIT := 200

var units: Array = []
var formation := "meihua"
var log: Array = []
var finished := false
var result := {}
var spar := false
var spar_npc := ""
var round_no := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()  # 运行时随机；测试中可用 _rng.seed 固定

# ---------- 建队 ----------
func setup(cfg: Dictionary) -> void:
	units.clear(); log.clear()
	finished = false; result = {}; round_no = 0
	spar = cfg.get("spar", false)
	spar_npc = cfg.get("spar_npc", "")
	formation = cfg.get("formation", GameState.formation)
	# 主角
	units.append(make_player_unit())
	# 随从（非切磋才上阵）
	if not spar:
		for fid in GameState.party:
			units.append(make_follower_unit(fid))
	# 敌人
	for u in cfg.get("enemies", []):
		units.append(make_enemy_unit(u.get("enemy", ""), int(u.get("pos", [0, 0])[0]), int(u.get("pos", [0, 0])[1])))
	# 先发制人等开局集气
	for u in units:
		u["gauge"] += int(u.get("gauge_start", 0))
	_add_log("—— 战斗开始：%s ——" % cfg.get("name", "遭遇战"))

func make_player_unit() -> Dictionary:
	var p: Dictionary = GameState.get_panel()
	var wid: String = GameState.equipped["套路"]
	return {
		"id": "hero", "name": GameState.player_name, "side": "ally",
		"lane": 1, "col": 0,
		"hp": GameState.hp, "hp_max": p["hp_max"], "mp": GameState.mp, "mp_max": p["mp_max"],
		"atk": p["atk"], "def": p["def"], "spd": p["spd"], "hit": p["hit"], "dodge": p["dodge"], "crit": p["crit"],
		"armor_pen": p["armor_pen_pct"], "tenacity": p["tenacity"], "dr_flat": p["dr_flat"],
		"atk_pct": p["atk_pct"], "gauge": 0, "gauge_flat": p["gauge_flat"], "gauge_pct": p["gauge_pct"],
		"gauge_start": p["gauge_start"], "yide": 0, "yide_rate": p["yide_rate"],
		"ult_amp": p["ult_amp"], "team_amp": p["team_amp"], "weapon_amp": p["weapon_amp"],
		"statuses": {}, "cds": {}, "wuxue": wid, "alive": true, "is_hero": true,
		"lv": GameState.lv, "weapon": GameState.weapon,
	}

func make_follower_unit(fid: String) -> Dictionary:
	var tpl: Dictionary = GameDB.get_enemy("n_" + fid)
	if tpl == {}: return {}
	var scale := 1.0 + 0.08 * (GameState.lv - 1)
	return {
		"id": fid, "name": tpl.get("name", fid), "side": "ally",
		"lane": int(tpl.get("lane", 0)), "col": 1,
		"hp": int(tpl["hp"] * scale), "hp_max": int(tpl["hp"] * scale), "mp": 40, "mp_max": 40,
		"atk": int(tpl["atk"] * scale), "def": tpl["def"], "spd": tpl["spd"],
		"hit": tpl["hit"], "dodge": tpl["dodge"], "crit": tpl["crit"],
		"armor_pen": 0.0, "tenacity": 0, "dr_flat": 0,
		"atk_pct": 0.0, "gauge": 0, "gauge_flat": 0, "gauge_pct": 0.0, "gauge_start": 0,
		"yide": 0, "yide_rate": 0.0, "ult_amp": 0.0, "team_amp": 0.0, "weapon_amp": 0.0,
		"statuses": {}, "cds": {}, "wuxue": tpl.get("wuxue", "quan_jichu"),
		"moves": tpl.get("moves", [0, 1]), "alive": true, "is_follower": true, "lv": tpl.get("lv", 1),
		"weapon": tpl.get("weapon", "拳"),
	}

func make_enemy_unit(eid: String, col: int, lane: int) -> Dictionary:
	var tpl: Dictionary = GameDB.get_enemy(eid)
	if tpl == {}: return {}
	var scale := 1.0
	if not tpl.get("spar", false) and not tpl.get("boss", false):
		scale = clampf(1.0 + 0.05 * (GameState.lv - tpl.get("lv", 1)), 0.85, 1.3)
	return {
		"id": eid + "#" + str(units.size()), "eid": eid, "name": tpl.get("name", eid), "side": "enemy",
		"lane": lane, "col": col,
		"hp": int(tpl["hp"] * scale), "hp_max": int(tpl["hp"] * scale), "mp": 60, "mp_max": 60,
		"atk": int(tpl["atk"] * scale), "def": tpl["def"], "spd": tpl["spd"],
		"hit": tpl["hit"], "dodge": tpl["dodge"], "crit": tpl["crit"],
		"armor_pen": 0.0, "tenacity": 0, "dr_flat": 0,
		"atk_pct": 0.0, "gauge": 0, "gauge_flat": 0, "gauge_pct": 0.0, "gauge_start": 0,
		"yide": 0, "yide_rate": 0.0, "ult_amp": 0.0, "team_amp": 0.0, "weapon_amp": 0.0,
		"statuses": {}, "cds": {}, "wuxue": tpl.get("wuxue", "quan_jichu"),
		"moves": tpl.get("moves", [0]), "alive": true,
		"is_boss": tpl.get("boss", false), "spar": tpl.get("spar", false), "lv": tpl.get("lv", 1),
		"weapon": tpl.get("weapon", "拳"),
	}

# ---------- 查询 ----------
func alive_of(side: String) -> Array:
	return units.filter(func(u): return u["side"] == side and u["alive"])

func get_formation_mods() -> Dictionary:
	return GameDB.get_formation(formation).get("bonus", {}).get("mods", {})

func _add_log(s: String) -> void:
	log.append(s)

# ---------- ATB ----------
## 推进时序条直到有单位可行动；返回该单位（或 null=战斗结束）
func tick_until_ready() -> Dictionary:
	if finished: return {}
	var guard := 0
	while guard < 100000:
		guard += 1
		var ready := _find_ready()
		if ready != {}:
			# 封穴：概率跳过行动
			if ready["statuses"].has("封穴") and _rng.randf() < float(ready["statuses"]["封穴"].get("val", 0.5)):
				_add_log("%s 被封住穴道，无法动弹！" % ready["name"])
				ready["gauge"] = 0
				_end_of_action(ready)
				continue
			return ready
		for u in units:
			if not u["alive"]: continue
			var rate: float = (8.0 + u["spd"] * 0.6) * (1.0 + u["gauge_pct"] + get_formation_mods().get("gauge", 0.0))
			if u["statuses"].has("迟缓"): rate *= 0.6
			u["gauge"] += rate * 1.0
		round_no += 1
		if round_no % 8 == 0:
			_round_effects()
	return {}

func _find_ready() -> Dictionary:
	var best: Dictionary = {}
	for u in units:
		if not u["alive"] or u["gauge"] < ATB_MAX: continue
		if best == {} or u["gauge"] > best["gauge"]:
			best = u
	return best

func _round_effects() -> void:
	var fmods := get_formation_mods()
	for u in units:
		if not u["alive"]: continue
		# DOT
		if u["statuses"].has("中毒"):
			var d := int(u["hp_max"] * 0.04)
			u["hp"] = maxi(0, u["hp"] - d)
			_add_log("%s 中毒发作，损失 %d 气血。" % [u["name"], d])
		if u["statuses"].has("流血"):
			var d2: int = maxi(2, int(u["statuses"]["流血"].get("val", 6)) - u["tenacity"] / 4)
			u["hp"] = maxi(0, u["hp"] - d2)
			_add_log("%s 流血不止，损失 %d 气血。" % [u["name"], d2])
		# 阵法回血（仅我方）
		if u["side"] == "ally" and fmods.has("regen"):
			u["hp"] = mini(u["hp_max"], u["hp"] + int(u["hp_max"] * fmods["regen"]))
		# 状态倒计时
		for sk in u["statuses"].keys():
			u["statuses"][sk]["turns"] -= 1
		for sk in u["statuses"].keys():
			if int(u["statuses"][sk]["turns"]) <= 0:
				u["statuses"].erase(sk)
		for mk in u["cds"].keys():
			u["cds"][mk] = maxi(0, int(u["cds"][mk]) - 1)
		if u["hp"] <= 0:
			_die(u)
	# 四象阵回血提示略

func _die(u: Dictionary) -> void:
	u["alive"] = false
	_add_log("【%s】倒下了！" % u["name"])
	_check_end()

func _check_end() -> void:
	if finished: return
	var allies := alive_of("ally").size()
	var enemies := alive_of("enemy").size()
	if enemies == 0:
		finished = true
		result = _build_win_result()
		_add_log("—— 战斗胜利！——")
	elif allies == 0:
		finished = true
		result = {"win": false, "retreat": false, "spar": spar}
		_add_log("—— 战败……——")

func _build_win_result() -> Dictionary:
	if spar:
		return {"win": true, "spar": true, "spar_npc": spar_npc, "exp": 0, "money": 0, "drops": [], "killed": []}
	var exp_v := 0
	var money := 0
	var drops: Array = []
	var killed: Array = []
	for u in units:
		if u["side"] != "enemy": continue
		var tpl: Dictionary = GameDB.get_enemy(u.get("eid", ""))
		if tpl == {}: continue
		exp_v += int(tpl.get("exp", 0))
		money += int(tpl.get("money", 0))
		killed.append(u.get("eid", ""))
		for d in tpl.get("drops", []):
			if _rng.randf() < float(d.get("rate", 0)):
				drops.append({"item": d["item"], "n": 1})
		for d in tpl.get("drops_force", []):
			if _rng.randf() < float(d.get("rate", 1.0)):
				drops.append({"item": d["item"], "n": 1})
	var xw := {GameState.equipped["套路"]: exp_v / 2 + 8}
	return {"win": true, "exp": exp_v, "money": money, "drops": drops, "killed": killed, "xiuwei": xw}

# ---------- 出招 ----------
func moves_of(u: Dictionary) -> Array:
	return GameDB.get_wuxue(u.get("wuxue", "")).get("moves", [])

func can_use(u: Dictionary, idx: int) -> bool:
	var mv_arr := moves_of(u)
	if idx < 0 or idx >= mv_arr.size(): return false
	var mv: Dictionary = mv_arr[idx]
	if int(u["cds"].get(str(idx), 0)) > 0: return false
	if u["mp"] < int(mv.get("mp", 0)): return false
	return true

func resolve_targets(actor: Dictionary, target_type: String, pick: Dictionary = {}) -> Array:
	var foe_side := "enemy" if actor["side"] == "ally" else "ally"
	var foes := alive_of(foe_side)
	match target_type:
		"自身": return [actor]
		"己方":
			var allies := alive_of(actor["side"])
			allies.sort_custom(func(a, b): return a["hp"] < b["hp"])
			return allies.slice(0, 1) if allies.size() > 0 else []
		"全体": return foes
		"横扫":
			# 选敌方存活最多的路
			var lanes := {0: 0, 1: 0, 2: 0}
			for f in foes: lanes[f["lane"]] = int(lanes[f["lane"]]) + 1
			var best_lane: int = int(actor["lane"])
			for l in lanes:
				if lanes[l] > lanes[best_lane]: best_lane = l
			return foes.filter(func(f): return f["lane"] == best_lane)
		"突进":
			# 直取最后排
			foes.sort_custom(func(a, b):
				if a["col"] != b["col"]: return a["col"] > b["col"]
				return absi(a["lane"] - actor["lane"]) < absi(b["lane"] - actor["lane"]))
			return foes.slice(0, 1)
		_:
			# 对位：同路最近列，否则全场最近
			var lane: int = int(pick.get("lane", actor["lane"]))
			var same := foes.filter(func(f): return f["lane"] == lane)
			same.sort_custom(func(a, b): return a["col"] < b["col"])
			if same.size() > 0: return [same[0]]
			foes.sort_custom(func(a, b):
				if a["col"] != b["col"]: return a["col"] < b["col"]
				return absi(a["lane"] - actor["lane"]) < absi(b["lane"] - actor["lane"]))
			return foes.slice(0, 1)

## 执行一次出招。返回是否成功
func use_move(actor: Dictionary, idx: int, pick: Dictionary = {}) -> bool:
	if finished or not actor["alive"]: return false
	var mv_arr := moves_of(actor)
	if idx < 0 or idx >= mv_arr.size(): return false
	var mv: Dictionary = mv_arr[idx]
	if not can_use(actor, idx): return false
	actor["mp"] -= int(mv.get("mp", 0))
	actor["cds"][str(idx)] = int(mv.get("cd", 0)) + 1
	var targets := resolve_targets(actor, mv.get("target", "对位"), pick)
	if targets.is_empty():
		_add_log("%s 的【%s】落了空。" % [actor["name"], mv.get("name", "?")])
		_end_of_action(actor)
		return true
	var is_ult: bool = mv.get("ult", false)
	if is_ult:
		if actor["yide"] < YIDE_ULT:
			_add_log("%s 战意不足，绝招【%s】未成。" % [actor["name"], mv["name"]])
			_end_of_action(actor)
			return true
		actor["yide"] -= YIDE_ULT
	# 必爆判定
	var forced_crit: bool = actor["yide"] >= YIDE_CRIT
	for t in targets:
		_resolve_hit(actor, t, mv, is_ult, forced_crit)
	if forced_crit:
		actor["yide"] = 0
		_add_log("战意如虹！%s 的攻击势在必得！" % actor["name"])
	# 自带 buff
	if mv.has("buff_self"):
		actor["statuses"][mv["buff_self"]["id"]] = {"turns": int(mv["buff_self"].get("turns", 2)), "val": float(mv["buff_self"].get("val", 0.1))}
	_end_of_action(actor)
	return true

func _resolve_hit(actor: Dictionary, tgt: Dictionary, mv: Dictionary, is_ult: bool, forced_crit: bool) -> void:
	var target_type: String = mv.get("target", "对位")
	# 己方类：治疗/净化
	if target_type == "己方":
		var heal_v := int(actor["atk"] * 1.2)
		tgt["hp"] = mini(tgt["hp_max"], tgt["hp"] + heal_v)
		_add_log("%s 为 %s 疗伤，回复 %d 气血。" % [actor["name"], tgt["name"], heal_v])
		return
	if target_type == "自身":
		_add_log("%s 运起【%s】，气息一沉。" % [actor["name"], mv.get("name", "?")])
		return
	# 命中
	var hit_chance: float = float(actor["hit"] - tgt["dodge"]) / 100.0
	if actor["statuses"].has("目盲"): hit_chance -= 0.30
	hit_chance = clampf(hit_chance, 0.30, 1.0)
	if _rng.randf() > hit_chance:
		_add_log("%s 出手一击，被 %s 侧身避过！" % [actor["name"], tgt["name"]])
		_gain_yide(tgt, 10)
		return
	# 伤害
	var crit: bool = forced_crit or _rng.randi() % 100 < actor["crit"]
	var dmg := float(actor["atk"]) * float(mv.get("mult", 1.0))
	# 攻增
	dmg *= 1.0 + float(actor["atk_pct"]) * 0.01
	# 武器/团队/武器加成
	dmg *= 1.0 + float(actor["weapon_amp"]) + float(actor["team_amp"])
	# 绝招增幅
	if is_ult: dmg *= 1.0 + float(actor["ult_amp"])
	# 防御减免（破甲）
	var eff_def := float(tgt["def"]) * (1.0 - float(actor["armor_pen"]))
	dmg *= 1.0 - eff_def / (eff_def + 120.0)
	# 突进加成
	if target_type == "突进": dmg *= 1.25
	# 阵法/位置减伤
	var fmods := get_formation_mods()
	if tgt["side"] == "ally":
		if tgt["col"] == 0 and fmods.has("front_dr"): dmg *= 1.0 - float(fmods["front_dr"])
		if tgt["col"] == 1 and fmods.has("mid_dr"): dmg *= 1.0 - float(fmods["mid_dr"])
	# 免伤
	if tgt["statuses"].has("免伤"): dmg *= 1.0 - float(tgt["statuses"]["免伤"].get("val", 0.1))
	dmg *= 1.0 - float(tgt["dr_flat"]) * 0.01
	# 暴击
	if crit: dmg *= 1.6
	var dmg_i := maxi(1, int(round(dmg)))
	tgt["hp"] = maxi(0, tgt["hp"] - dmg_i)
	var tag := ("绝招" if is_ult else "招式")
	var crit_tag := "（会心！）" if crit else ""
	_add_log("%s 使出【%s】%s，%s 受到 %d 点伤害%s。" % [actor["name"], mv["name"], tag, tgt["name"], dmg_i, crit_tag])
	# 战意
	_gain_yide(actor, 12)
	_gain_yide(tgt, 10)
	# 吸血
	if mv.has("drain"):
		var back := int(dmg_i * float(mv["drain"]))
		actor["hp"] = mini(actor["hp_max"], actor["hp"] + back)
		_add_log("%s 以血还血，回复 %d 气血。" % [actor["name"], back])
	# 内力灼烧
	if mv.has("mp_burn"):
		tgt["mp"] = maxi(0, tgt["mp"] - int(mv["mp_burn"]))
	# 附加状态
	if mv.has("status"):
		var st: Dictionary = mv["status"]
		# 韧性抗DOT
		if st["id"] in ["中毒", "流血"] and _rng.randi() % 100 < tgt["tenacity"]:
			_add_log("%s 内息沉稳，抗住了%s。" % [tgt["name"], st["id"]])
		else:
			tgt["statuses"][st["id"]] = {"turns": int(st.get("turns", 2)), "val": st.get("val", 0)}
			_add_log("%s 陷入【%s】！" % [tgt["name"], st["id"]])
	if tgt["hp"] <= 0:
		_die(tgt)

func _gain_yide(u: Dictionary, base: int) -> void:
	u["yide"] = mini(YIDE_CRIT, u["yide"] + int(round(base * (1.0 + float(u["yide_rate"])))))

func _end_of_action(actor: Dictionary) -> void:
	actor["gauge"] = 0.0
	# 行动后内力微回
	actor["mp"] = mini(actor["mp_max"], actor["mp"] + 1)
	_check_end()

# ---------- AI ----------
func ai_choose(actor: Dictionary) -> Dictionary:
	var mv_arr := moves_of(actor)
	var best_i := 0
	var best_score := -1.0
	for i in mv_arr.size():
		if not can_use(actor, i): continue
		var mv: Dictionary = mv_arr[i]
		var is_ult: bool = mv.get("ult", false)
		if is_ult and actor["yide"] < YIDE_ULT: continue
		var score: float = float(mv.get("mult", 1.0))
		if is_ult: score += 1.0
		if score > best_score:
			best_score = score
			best_i = i
	return {"move": best_i, "pick": {}}

## 自动战斗一整场（测试/挂机用）
func run_auto(max_ticks := 100000) -> Dictionary:
	var n := 0
	while not finished and n < max_ticks:
		n += 1
		var actor := tick_until_ready()
		if actor == {}: break
		var ch := ai_choose(actor)
		use_move(actor, int(ch["move"]), ch.get("pick", {}))
	return result

# ---------- 撤退 ----------
func try_retreat() -> bool:
	if finished: return false
	if _rng.randf() < 0.75:
		finished = true
		result = {"win": false, "retreat": true, "spar": spar}
		_add_log("你且战且退，脱出了战团。")
		return true
	_add_log("退路被阻，撤退失败！")
	return false
