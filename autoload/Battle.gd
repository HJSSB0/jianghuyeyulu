extends Node
## Battle —— 大侠立志传式战棋引擎（纯逻辑，零渲染依赖）：
## ATB 集气决定行动顺序；就绪单位获「移动步数 + 一次行动」；
## 9×7 网格战场自由走位，侧击 +15% / 背击 +25%；战意 0-200（100 绝招 / 200 必爆）；
## 阵法=战前布阵全队光环；经脉/内力/状态系统不变。

const ATB_MAX := 1000
const YIDE_ULT := 100
const YIDE_CRIT := 200
const GRID_W := 9
const GRID_H := 7
const SIDE_BONUS := 0.15
const BACK_BONUS := 0.25

var units: Array = []
var formation := "meihua"
var log: Array = []
var finished := false
var result := {}
var spar := false
var spar_npc := ""
var round_no := 0
var obstacles: Array = []   # Vector2i 列表
var fx_events: Array = []   # 演出事件流：{kind:hit/slash, 坐标, 数值}（视图层消费后 clear_fx）
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()  # 运行时随机；测试中可用 _rng.seed 固定

# ---------- 建队 ----------
func setup(cfg: Dictionary) -> void:
	units.clear(); log.clear(); obstacles.clear(); fx_events.clear()
	finished = false; result = {}; round_no = 0
	spar = cfg.get("spar", false)
	spar_npc = cfg.get("spar_npc", "")
	formation = cfg.get("formation", GameState.formation)
	_gen_obstacles(str(cfg.get("map", "")))
	# 主角
	units.append(make_player_unit())
	# 随从（非切磋才上阵）
	if not spar:
		for i in GameState.party.size():
			var u := make_follower_unit(GameState.party[i])
			if u != {}:
				u["x"] = 0
				u["y"] = 1 + (i % 2) * 4
				units.append(u)
	# 敌人（旧数据 pos=[col,lane] → 网格右侧）
	for e in cfg.get("enemies", []):
		var col: int = int(e.get("pos", [0, 0])[0])
		var lane: int = int(e.get("pos", [0, 0])[1])
		var u := make_enemy_unit(e.get("enemy", ""), col, lane)
		if u != {}:
			u["x"] = GRID_W - 1 - clampi(col, 0, 3)
			u["y"] = clampi(1 + lane * 2, 0, GRID_H - 1)
			units.append(u)
	for u in units:
		u["gauge"] += int(u.get("gauge_start", 0))
		u["facing"] = Vector2i(1, 0) if u["side"] == "ally" else Vector2i(-1, 0)
		u["steps_left"] = 0
	_add_log("—— 战斗开始：%s ——" % cfg.get("name", "遭遇战"))

## 战场障碍：按地图名确定性布几个岩块（中轴带，避开出生列）
func _gen_obstacles(map_id: String) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(map_id) & 0xffff if map_id != "" else 424242
	var n := 5
	var tries := 0
	while obstacles.size() < n and tries < 60:
		tries += 1
		var c := Vector2i(r.randi_range(3, GRID_W - 4), r.randi_range(0, GRID_H - 1))
		if c in obstacles:
			continue
		if c.y in [1, 3, 5] and c.x >= GRID_W - 3:
			continue
		obstacles.append(c)

func make_player_unit() -> Dictionary:
	var p: Dictionary = GameState.get_panel()
	var wid: String = GameState.equipped["套路"]
	var u := _base_unit("hero", GameState.player_name, "ally", int(p["hp_max"]), p, wid)
	u["hp"] = GameState.hp
	u["mp"] = GameState.mp
	u["is_hero"] = true
	u["lv"] = GameState.lv
	u["weapon"] = GameState.weapon
	u["x"] = 0
	u["y"] = 3
	return u

func make_follower_unit(fid: String) -> Dictionary:
	var tpl: Dictionary = GameDB.get_enemy("n_" + fid)
	if tpl == {}: return {}
	var scale := 1.0 + 0.08 * (GameState.lv - 1)
	var u := _base_unit(fid, tpl.get("name", fid), "ally", int(tpl["hp"] * scale), tpl, tpl.get("wuxue", "quan_jichu"))
	u["mp"] = 40
	u["mp_max"] = 40
	u["moves"] = tpl.get("moves", [0, 1])
	u["is_follower"] = true
	u["lv"] = tpl.get("lv", 1)
	u["weapon"] = tpl.get("weapon", "拳")
	return u

func make_enemy_unit(eid: String, col: int, lane: int) -> Dictionary:
	var tpl: Dictionary = GameDB.get_enemy(eid)
	if tpl == {}: return {}
	var scale := 1.0
	if not tpl.get("spar", false) and not tpl.get("boss", false):
		scale = clampf(1.0 + 0.05 * (GameState.lv - tpl.get("lv", 1)), 0.85, 1.3)
	var u := _base_unit(eid + "#" + str(units.size()), tpl.get("name", eid), "enemy", int(tpl["hp"] * scale), tpl, tpl.get("wuxue", "quan_jichu"))
	u["eid"] = eid
	u["hp"] = int(tpl["hp"] * scale)
	u["mp"] = 60
	u["mp_max"] = 60
	u["moves"] = tpl.get("moves", [0])
	u["is_boss"] = tpl.get("boss", false)
	u["spar"] = tpl.get("spar", false)
	u["lv"] = tpl.get("lv", 1)
	u["weapon"] = tpl.get("weapon", "拳")
	return u

func _base_unit(id: String, uname: String, side: String, hp: int, st: Dictionary, wuxue: String) -> Dictionary:
	return {
		"id": id, "name": uname, "side": side,
		"x": 0, "y": 3, "facing": Vector2i(1, 0), "steps_left": 0,
		"hp": hp, "hp_max": hp, "mp": 40, "mp_max": 40,
		"atk": int(st.get("atk", 10)), "def": st.get("def", 5), "spd": st.get("spd", 10),
		"hit": st.get("hit", 85), "dodge": st.get("dodge", 5), "crit": st.get("crit", 8),
		"armor_pen": st.get("armor_pen_pct", 0.0), "tenacity": st.get("tenacity", 0), "dr_flat": st.get("dr_flat", 0),
		"atk_pct": st.get("atk_pct", 0.0), "gauge": 0, "gauge_flat": st.get("gauge_flat", 0), "gauge_pct": st.get("gauge_pct", 0.0),
		"gauge_start": st.get("gauge_start", 0), "yide": 0, "yide_rate": st.get("yide_rate", 0.0),
		"ult_amp": st.get("ult_amp", 0.0), "team_amp": st.get("team_amp", 0.0), "weapon_amp": st.get("weapon_amp", 0.0),
		"statuses": {}, "cds": {}, "wuxue": wuxue, "moves": [], "alive": true,
	}

# ---------- 查询 ----------
func alive_of(side: String) -> Array:
	return units.filter(func(u): return u["side"] == side and u["alive"])

func get_formation_mods() -> Dictionary:
	return GameDB.get_formation(formation).get("bonus", {}).get("mods", {})

func _add_log(s: String) -> void:
	log.append(s)

func unit_at(x: int, y: int) -> Dictionary:
	for u in units:
		if u["alive"] and u["x"] == x and u["y"] == y:
			return u
	return {}

func cell_blocked(x: int, y: int) -> bool:
	return Vector2i(x, y) in obstacles

func in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GRID_W and y < GRID_H

# ---------- 战棋走位 ----------

## 本单位本回合的移动步数（轻功/身法加成）
func steps_of(u: Dictionary) -> int:
	return clampi(2 + int(float(u["spd"]) / 25.0), 2, 6)

## 可达格（BFS，含自身格；单位与障碍阻挡）
func move_range(u: Dictionary) -> Array:
	var start := Vector2i(u["x"], u["y"])
	var steps := steps_of(u)
	var dist := {start: 0}
	var queue: Array = [start]
	var out: Array = []
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		var d: int = dist[cur]
		if d >= steps:
			continue
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + dd
			if not in_grid(nx.x, nx.y) or cell_blocked(nx.x, nx.y) or dist.has(nx):
				continue
			var occ := unit_at(nx.x, nx.y)
			if occ != {} and occ != u:
				continue
			dist[nx] = d + 1
			out.append(nx)
			queue.append(nx)
	return out

## 走格：返回是否成功（面向移动方向）
func move_to(u: Dictionary, cell: Vector2i) -> bool:
	if finished or not u["alive"]:
		return false
	if cell == Vector2i(u["x"], u["y"]):
		return true
	if not (cell in move_range(u)):
		return false
	var dd := cell - Vector2i(u["x"], u["y"])
	u["facing"] = Vector2i(signi(dd.x), signi(dd.y)) if dd.x != 0 else Vector2i(0, signi(dd.y))
	if absi(dd.x) >= absi(dd.y) and dd.x != 0:
		u["facing"] = Vector2i(signi(dd.x), 0)
	u["x"] = cell.x
	u["y"] = cell.y
	return true

## 招式可达格（从当前位置；空数组=无需选格：自身/己方/全体）
func attack_cells(u: Dictionary, idx: int) -> Array:
	var mv_arr := moves_of(u)
	if idx < 0 or idx >= mv_arr.size():
		return []
	var tt: String = mv_arr[idx].get("target", "对位")
	match tt:
		"自身", "己方", "全体":
			return []
		"横扫":
			var out: Array = []
			for dx in range(-2, 3):
				if dx == 0:
					continue
				if in_grid(u["x"] + dx, u["y"]):
					out.append(Vector2i(u["x"] + dx, u["y"]))
			return out
		"突进":
			var out2: Array = []
			for yy in GRID_H:
				for xx in GRID_W:
					var c := Vector2i(xx, yy)
					if c != Vector2i(u["x"], u["y"]) and absi(xx - u["x"]) + absi(yy - u["y"]) <= 3:
						out2.append(c)
			return out2
		_:
			var rng := int(mv_arr[idx].get("range", 1))
			var out3: Array = []
			for yy in GRID_H:
				for xx in GRID_W:
					var c2 := Vector2i(xx, yy)
					if c2 != Vector2i(u["x"], u["y"]) and absi(xx - u["x"]) + absi(yy - u["y"]) <= rng:
						out3.append(c2)
			return out3

# ---------- ATB ----------
## 推进时序条直到有单位可行动；返回该单位（或 null=战斗结束）
func tick_until_ready() -> Dictionary:
	if finished: return {}
	var guard := 0
	while guard < 100000:
		guard += 1
		var ready := _find_ready()
		if ready != {}:
			ready["steps_left"] = steps_of(ready)
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
		if u["statuses"].has("中毒"):
			var d := int(u["hp_max"] * 0.04)
			u["hp"] = maxi(0, u["hp"] - d)
			_add_log("%s 中毒发作，损失 %d 气血。" % [u["name"], d])
		if u["statuses"].has("流血"):
			var d2: int = maxi(2, int(u["statuses"]["流血"].get("val", 6)) - u["tenacity"] / 4)
			u["hp"] = maxi(0, u["hp"] - d2)
			_add_log("%s 流血不止，损失 %d 气血。" % [u["name"], d2])
		if u["side"] == "ally" and fmods.has("regen"):
			u["hp"] = mini(u["hp_max"], u["hp"] + int(u["hp_max"] * fmods["regen"]))
		for sk in u["statuses"].keys():
			u["statuses"][sk]["turns"] -= 1
		for sk in u["statuses"].keys():
			if int(u["statuses"][sk]["turns"]) <= 0:
				u["statuses"].erase(sk)
		for mk in u["cds"].keys():
			u["cds"][mk] = maxi(0, int(u["cds"][mk]) - 1)
		if u["hp"] <= 0:
			_die(u)

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

## 选目标：优先 pick.cell 指定格上的敌人，否则最近者
func _pick_foe(actor: Dictionary, pick: Dictionary) -> Dictionary:
	var foe_side := "enemy" if actor["side"] == "ally" else "ally"
	var foes := alive_of(foe_side)
	if foes.is_empty():
		return {}
	var cellv = pick.get("cell", null)
	if cellv != null:
		var c: Vector2i = cellv if cellv is Vector2i else Vector2i(int((cellv as Dictionary).get("x", -99)), int((cellv as Dictionary).get("y", -99)))
		for f in foes:
			if f["x"] == c.x and f["y"] == c.y:
				return f
	var best: Dictionary = foes[0]
	var bd := absi(best["x"] - actor["x"]) + absi(best["y"] - actor["y"])
	for f in foes:
		var d := absi(f["x"] - actor["x"]) + absi(f["y"] - actor["y"])
		if d < bd:
			bd = d
			best = f
	return best

## 执行一次出招。pick 可带 {"cell": Vector2i}。返回是否成功
func use_move(actor: Dictionary, idx: int, pick: Dictionary = {}) -> bool:
	if finished or not actor["alive"]: return false
	var mv_arr := moves_of(actor)
	if idx < 0 or idx >= mv_arr.size(): return false
	var mv: Dictionary = mv_arr[idx]
	if not can_use(actor, idx): return false
	actor["mp"] -= int(mv.get("mp", 0))
	actor["cds"][str(idx)] = int(mv.get("cd", 0)) + 1
	# 出手演出事件（突进以跃前起点画弧）
	fx_events.append({"kind": "slash", "ax": actor["x"], "ay": actor["y"], "tx": actor["x"] + actor["facing"].x, "ty": actor["y"] + actor["facing"].y})
	var tt: String = mv.get("target", "对位")
	var targets: Array = []
	match tt:
		"自身":
			targets = [actor]
		"己方":
			var allies := alive_of(actor["side"])
			allies.sort_custom(func(a, b): return a["hp"] < b["hp"])
			targets = allies.slice(0, 1)
		"全体":
			targets = alive_of("enemy" if actor["side"] == "ally" else "ally")
		"横扫":
			var row: int = actor["y"]
			targets = alive_of("enemy" if actor["side"] == "ally" else "ally").filter(
				func(f): return f["y"] == row)
			if targets.is_empty():
				targets = [_pick_foe(actor, pick)]
		"突进":
			var foe := _pick_foe(actor, pick)
			if foe != {}:
				# 跃至目标邻格（朝原位一侧），刀随人走
				var land := Vector2i(foe["x"] - signi(foe["x"] - actor["x"]), foe["y"])
				if in_grid(land.x, land.y) and not cell_blocked(land.x, land.y) and (unit_at(land.x, land.y) == {} or unit_at(land.x, land.y) == actor):
					actor["facing"] = Vector2i(signi(foe["x"] - actor["x"]), 0)
					actor["x"] = land.x
					actor["y"] = land.y
			targets = [foe] if foe != {} else []
		_:
			var foe2 := _pick_foe(actor, pick)
			targets = [foe2] if foe2 != {} else []
	if targets.is_empty() or (targets.size() == 1 and targets[0] == {}):
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
	var forced_crit: bool = actor["yide"] >= YIDE_CRIT
	for tgt in targets:
		_resolve_hit(actor, tgt, mv, is_ult, forced_crit, tt)
	if forced_crit:
		actor["yide"] = 0
		_add_log("战意如虹！%s 的攻击势在必得！" % actor["name"])
	if mv.has("buff_self"):
		actor["statuses"][mv["buff_self"]["id"]] = {"turns": int(mv["buff_self"].get("turns", 2)), "val": float(mv["buff_self"].get("val", 0.1))}
	_end_of_action(actor)
	return true

## 朝向加成：背面 +25%、侧面 +15%、正面 0；受击后转向攻击者
func _facing_mult(tgt: Dictionary, attack_dir: Vector2i) -> float:
	if tgt["facing"] == attack_dir:
		return 1.0 + BACK_BONUS       # 目标背对来敌
	if tgt["facing"] == -attack_dir:
		return 1.0                    # 正面对峙
	return 1.0 + SIDE_BONUS           # 侧翼

func _resolve_hit(actor: Dictionary, tgt: Dictionary, mv: Dictionary, is_ult: bool, forced_crit: bool, target_type: String) -> void:
	if tgt == {} or not tgt.get("alive", false):
		return
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
	# 朝向加成
	var dv := Vector2i(tgt["x"] - actor["x"], tgt["y"] - actor["y"])
	var adir := Vector2i(signi(dv.x), 0) if absi(dv.x) >= absi(dv.y) else Vector2i(0, signi(dv.y))
	var face_mult := _facing_mult(tgt, adir)
	# 伤害
	var crit: bool = forced_crit or _rng.randi() % 100 < actor["crit"]
	var dmg := float(actor["atk"]) * float(mv.get("mult", 1.0))
	dmg *= 1.0 + float(actor["atk_pct"]) * 0.01
	dmg *= 1.0 + float(actor["weapon_amp"]) + float(actor["team_amp"])
	# 阵法攻击光环（仅我方）
	if actor["side"] == "ally":
		dmg *= 1.0 + float(get_formation_mods().get("atk", 0.0))
	if is_ult: dmg *= 1.0 + float(actor["ult_amp"])
	var eff_def := float(tgt["def"]) * (1.0 - float(actor["armor_pen"]))
	dmg *= 1.0 - eff_def / (eff_def + 120.0)
	if target_type == "突进": dmg *= 1.25
	dmg *= face_mult
	# 阵法减伤光环（我方全队）
	var fmods := get_formation_mods()
	if tgt["side"] == "ally" and fmods.has("dr"):
		dmg *= 1.0 - float(fmods["dr"])
	if tgt["statuses"].has("免伤"): dmg *= 1.0 - float(tgt["statuses"]["免伤"].get("val", 0.1))
	dmg *= 1.0 - float(tgt["dr_flat"]) * 0.01
	if crit: dmg *= 1.6
	var dmg_i := maxi(1, int(round(dmg)))
	tgt["hp"] = maxi(0, tgt["hp"] - dmg_i)
	fx_events.append({"kind": "hit", "x": tgt["x"], "y": tgt["y"], "dmg": dmg_i, "crit": crit,
		"face": ("背击" if face_mult > 1.2 else ("侧击" if face_mult > 1.0 else ""))})
	var tag := ("绝招" if is_ult else "招式")
	var crit_tag := "（会心！）" if crit else ""
	var face_tag := ""
	if face_mult > 1.2:
		face_tag = "【背击】"
	elif face_mult > 1.0:
		face_tag = "【侧击】"
	_add_log("%s 使出【%s】%s，%s 受到 %d 点伤害%s%s。" % [actor["name"], mv["name"], tag, tgt["name"], dmg_i, crit_tag, face_tag])
	# 受击者转向攻击者
	tgt["facing"] = -adir
	_gain_yide(actor, 12)
	_gain_yide(tgt, 10)
	if mv.has("drain"):
		var back := int(dmg_i * float(mv["drain"]))
		actor["hp"] = mini(actor["hp_max"], actor["hp"] + back)
		_add_log("%s 以血还血，回复 %d 气血。" % [actor["name"], back])
	if mv.has("mp_burn"):
		tgt["mp"] = maxi(0, tgt["mp"] - int(mv["mp_burn"]))
	if mv.has("status"):
		var st: Dictionary = mv["status"]
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
	actor["steps_left"] = 0
	actor["mp"] = mini(actor["mp_max"], actor["mp"] + 1)
	_check_end()

# ---------- AI ----------
## 战棋化 AI：寻路接近最优目标格 → 占侧/背位 → 放招
func ai_act(actor: Dictionary) -> void:
	if finished or not actor["alive"]:
		return
	var foe_side := "enemy" if actor["side"] == "ally" else "ally"
	var foes := alive_of(foe_side)
	if foes.is_empty():
		return
	# 选目标：最近
	var tgt: Dictionary = foes[0]
	var bd := 9999
	for f in foes:
		var d := absi(f["x"] - actor["x"]) + absi(f["y"] - actor["y"])
		if d < bd:
			bd = d
			tgt = f
	# 可用招式
	var mv_arr := moves_of(actor)
	var best_i := -1
	var best_score := -1.0
	for i in mv_arr.size():
		if not can_use(actor, i): continue
		var mv: Dictionary = mv_arr[i]
		if mv.get("ult", false) and actor["yide"] < YIDE_ULT: continue
		var score: float = float(mv.get("mult", 1.0))
		if mv.get("ult", false): score += 1.0
		if score > best_score:
			best_score = score
			best_i = i
	if best_i < 0:
		_add_log("%s 气力未复，只能运氣。" % actor["name"])
		_end_of_action(actor)
		return
	var tt: String = mv_arr[best_i].get("target", "对位")
	# 走位：在移动范围内找离目标最近的格（近战贴脸，正面让给背击机会）
	var rng_cells: Array = move_range(actor)
	var cur := Vector2i(actor["x"], actor["y"])
	var best_cell := cur
	var best_d := absi(tgt["x"] - cur.x) + absi(tgt["y"] - cur.y)
	for c in rng_cells:
		var d := absi(tgt["x"] - c.x) + absi(tgt["y"] - c.y)
		if d < best_d:
			best_d = d
			best_cell = c
	if best_cell != cur:
		move_to(actor, best_cell)
	use_move(actor, best_i, {"cell": Vector2i(tgt["x"], tgt["y"])})

## 自动战斗一整场（测试/挂机用）
func run_auto(max_ticks := 100000) -> Dictionary:
	var n := 0
	while not finished and n < max_ticks:
		n += 1
		var actor := tick_until_ready()
		if actor == {}:
			break
		ai_act(actor)
	return result

# ---------- 撤退 ----------
func clear_fx() -> void:
	fx_events.clear()

func try_retreat() -> bool:
	if finished: return false
	if _rng.randf() < 0.75:
		finished = true
		result = {"win": false, "retreat": true, "spar": spar}
		_add_log("你且战且退，脱出了战团。")
		return true
	_add_log("退路被阻，撤退失败！")
	return false
