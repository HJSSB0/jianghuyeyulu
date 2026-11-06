extends Node
## GameState —— 运行态总管：玩家、队伍、背包、时辰、旗标、好感、门派、任务进度。
## 纯逻辑、零 UI 依赖；UI 经 EventBus 订阅信号。

const SAVE_VERSION := 2
const MAX_PARTY := 3
const ATTR_KEYS: Array = ["臂力", "体质", "敏捷", "悟性", "福缘"]
const MORAL_KEYS: Array = ["仁", "义", "勇"]
const GATHER_COOLDOWN_Q := {"丁": 6, "丙": 12, "乙": 24, "甲": 48}  # 游戏内刻（1时辰=4刻）
const FAME_LEVELS: Array = [0, 30, 80, 160, 300, 500]
const FAME_NAMES: Array = ["无名小卒", "初入江湖", "小有名气", "声名鹊起", "名动一方", "威震江湖"]

# ---------- 运行态 ----------
var inited := false
var player_name := "无名小卒"
var weapon := "剑"                     # 拳/剑/刀/棍
var lv := 1
var exp := 0
var hp := 100
var mp := 30
var zhenqi := 0
var attrs := {"臂力": 3, "体质": 3, "敏捷": 3, "悟性": 3, "福缘": 3}
var morality := {"仁": 0, "义": 0, "勇": 0}
var fame := 0
var money_tong := 300                  # 铜钱
var money_yin := 0                     # 银两（1银两=1000铜）
var inventory := {}                    # item_id -> count
var traits: Array = []                 # trait_id[]
var learned := {}                      # wuxue_id -> {lv, xiuwei}
var equipped := {"套路": "", "内功": "", "轻功": ""}
var equips := {"武器": "", "防具": "", "饰品": ""}
var meridians := {}                    # mer_id -> "shun"/"ni"
var formation := "meihua"
var affinity := {}                     # npc_id -> int 0-100
var faction := ""                      # faction_id
var faction_contrib := 0
var followers: Array = []              # 已招募随从 npc_id
var party: Array = []                  # 出战随从 npc_id (<=3)
var quest_states := {}                 # qid -> {state:"active"/"done"/"locked", step:int}
var bounty_pool: Array = []
var counters := {}                     # 通用计数器
var gather_cooldown := {}              # gather_id -> 绝对刻
var day := 1
var shichen := 6                       # 0子..11亥，开局卯时后（辰=4? 用辰时=4）
var quarter := 0                       # 每时辰4刻
var abs_quarter := 0                   # 绝对刻（= (day-1)*48 + shichen*4 + quarter）
var faction_quest_done := {}           # 门派任务完成标记
var main_done := false
var flags := {}                        # 杂项旗标（结局选择等）

func _ready() -> void:
	reset()

func reset() -> void:
	inited = false
	player_name = "无名小卒"; weapon = "剑"; lv = 1; exp = 0
	hp = 100; mp = 30; zhenqi = 0
	attrs = {"臂力": 3, "体质": 3, "敏捷": 3, "悟性": 3, "福缘": 3}
	morality = {"仁": 0, "义": 0, "勇": 0}
	fame = 0; money_tong = 300; money_yin = 0
	inventory = {}; traits = []; learned = {}
	equipped = {"套路": "", "内功": "", "轻功": ""}
	equips = {"武器": "", "防具": "", "饰品": ""}
	meridians = {}; formation = "meihua"
	affinity = {}; faction = ""; faction_contrib = 0
	followers = []; party = []
	quest_states = {}; bounty_pool = []; counters = {}; gather_cooldown = {}
	day = 1; shichen = 4; quarter = 0; abs_quarter = 0
	faction_quest_done = {}; main_done = false; flags = {}
	# 初始武学与物品
	learn_wuxue("quan_jichu", true)
	learn_wuxue("jian_jichu", true)
	learn_wuxue("dao_jichu", true)
	learn_wuxue("gun_jichu", true)
	learn_wuxue("nei_jichu", true)
	learn_wuxue("qing_jichu", true)
	equipped["套路"] = "jian_jichu"; equipped["内功"] = "nei_jichu"; equipped["轻功"] = "qing_jichu"
	add_item("c_mantou", 3); add_item("c_jinchuang", 2)
	refresh_bounty_pool()

# ---------- 开局 ----------
func new_game(cfg: Dictionary) -> void:
	reset()
	inited = true
	player_name = cfg.get("name", "无名小卒")
	weapon = cfg.get("weapon", "剑")
	for k in cfg.get("attrs", {}):
		attrs[k] = int(cfg["attrs"][k])
	var t: String = cfg.get("trait", "")
	if t != "" and GameDB.get_trait(t) != {}:
		traits.append(t)
	var money_mult := get_all_mods().get("start_money_mult", 1.0)
	money_tong = int(300 * money_mult)
	hp = get_panel()["hp_max"]; mp = get_panel()["mp_max"]

# ---------- 属性汇总（特性+装备+武学+经脉+品格 → mods） ----------
func get_all_mods() -> Dictionary:
	var m: Dictionary = {}
	for tid in traits:
		for k in GameDB.get_trait(tid).get("mods", {}):
			m[k] = m.get(k, 0) + GameDB.get_trait(tid)["mods"][k]
	# 装备
	for slot in equips:
		var iid: String = equips[slot]
		if iid == "": continue
		var it: Dictionary = GameDB.get_item(iid)
		for k in ["atk", "def", "hp", "crit", "dodge", "hit", "spd"]:
			if it.has(k): m[k] = m.get(k, 0) + int(it[k])
		for k in it.get("stats", {}):
			m[k] = m.get(k, 0) + int(it["stats"][k])
	# 坐骑（健马·踏雪）：官道行进更快
	if count_item("m_ma") > 0:
		m["travel"] = m.get("travel", 0) + 1
	# 已装备武学（按当前境界）
	for slot in equipped:
		var wid: String = equipped[slot]
		if wid == "": continue
		var w: Dictionary = GameDB.get_wuxue(wid)
		for k in w.get("stats", {}):
			m[k] = m.get(k, 0) + int(round(int(w["stats"][k]) * (1.0 + 0.12 * (wuxue_lv(wid) - 1))))
	var pas: Dictionary = wuxue_passive_mods()
	for k in pas:
		m[k] = m.get(k, 0) + pas[k]
	# 经脉
	for mid in meridians:
		var mer: Dictionary = GameDB.get_meridian(mid)
		var dir: String = meridians[mid]
		if mer == {} or not mer.has(dir): continue
		for k in mer[dir].get("mods", {}):
			m[k] = m.get(k, 0) + mer[dir]["mods"][k]
	# 品格满值特征
	for k in MORAL_KEYS:
		if morality[k] >= 100:
			match k:
				"仁": m["encounter_safe"] = 1
				"义": m["affinity_rate"] = m.get("affinity_rate", 0) + 0.25
				"勇": m["team_amp"] = m.get("team_amp", 0) + 0.10
	return m

func wuxue_passive_mods() -> Dictionary:
	var m: Dictionary = {}
	var wid: String = equipped.get("内功", "")
	if wid != "":
		var p: Dictionary = GameDB.get_wuxue(wid).get("passive", {})
		var pid: String = p.get("id", "无")
		if pid != "无":
			var key: String = {"回气": "mp_regen", "回血": "hp_regen", "免伤": "dr_flat", "集气": "gauge_flat", "攻增": "atk_pct"}.get(pid, "")
			if key != "":
				m[key] = m.get(key, 0) + int(p.get("val", 0))
	return m

func wuxue_lv(wid: String) -> int:
	return int(learned.get(wid, {}).get("lv", 0))

# ---------- 面板 ----------
func exp_need(l: int) -> int:
	return int(round(30.0 * pow(float(l), 1.6)))

func get_panel() -> Dictionary:
	var mods := get_all_mods()
	var hp_max: int = 60 + int(attrs["体质"]) * 12 + (lv - 1) * 15 + int(mods.get("hp_max", 0))
	var mp_max: int = 20 + int(attrs["悟性"]) * 3 + int(mods.get("mp_max", 0))
	var atk: int = 8 + int(attrs["臂力"]) * 2 + (lv - 1) * 2 + int(mods.get("atk", 0))
	var wux: Dictionary = GameDB.get_wuxue(equipped.get("套路", ""))
	if wux.get("kind", "") == "套路" and wux.get("weapon", "") == weapon:
		atk += 2  # 武器类型匹配
	var def: int = 4 + int(attrs["体质"]) + (lv - 1) + int(mods.get("def", 0))
	var spd: int = 8 + int(attrs["敏捷"]) * 2 + int(mods.get("spd", 0))
	var hit := 85 + int(mods.get("hit", 0))
	var dodge: int = int(attrs["敏捷"]) + int(mods.get("dodge", 0))
	var crit: int = 5 + int(round(float(attrs["福缘"]) / 2.0)) + int(mods.get("crit", 0))
	return {"hp_max": hp_max, "mp_max": mp_max, "atk": atk, "def": def, "spd": spd,
			"hit": hit, "dodge": dodge, "crit": crit,
			"armor_pen": mods.get("armor_pen", 0.0), "tenacity": mods.get("tenacity", 0),
			"dr_flat": mods.get("dr_flat", 0), "gauge_flat": mods.get("gauge_flat", 0),
			"atk_pct": mods.get("atk_pct", 0), "hp_regen": mods.get("hp_regen", 0),
			"mp_regen": mods.get("mp_regen", 0), "gauge_start": mods.get("gauge_start", 0),
			"gauge_pct": mods.get("gauge", 0.0), "ult_amp": mods.get("ult_amp", 0.0),
			"yide_rate": mods.get("yide_rate", 0.0), "team_amp": mods.get("team_amp", 0.0),
			"weapon_amp": mods.get("weapon_amp_" + weapon, 0.0),
			"armor_pen_pct": mods.get("armor_pen", 0.0)}

func refresh_vitals() -> void:
	var p := get_panel()
	hp = clampi(hp, 0, p["hp_max"]); mp = clampi(mp, 0, p["mp_max"])

func heal(h: int, m: int = 0) -> void:
	var p := get_panel()
	var amp: float = 1.0 + float(get_all_mods().get("heal_amp", 0.0))
	hp = clampi(hp + int(h * amp), 0, p["hp_max"])
	mp = clampi(mp + m, 0, p["mp_max"])
	EventBus.hp_mp_changed.emit(hp, p["hp_max"], mp, p["mp_max"])

# ---------- 经验/升级 ----------
func add_exp(v: int) -> void:
	exp += v
	while lv < 10 and exp >= exp_need(lv):
		exp -= exp_need(lv)
		lv += 1
		refresh_vitals()
		hp = get_panel()["hp_max"]  # 升级回满
		EventBus.toast.emit("武学修为精进！等级提升至 %d 层。" % lv)

# ---------- 武学 ----------
func learn_wuxue(wid: String, silent := false) -> void:
	if learned.has(wid): return
	learned[wid] = {"lv": 1, "xiuwei": 0}
	if not silent:
		EventBus.toast.emit("习得【%s】！" % GameDB.get_wuxue(wid).get("name", wid))
		EventBus.wuxue_learned.emit(wid)

func add_xiuwei(wid: String, v: int) -> void:
	if not learned.has(wid): return
	var rate: float = 1.0 + float(attrs["悟性"]) * 0.05 + float(get_all_mods().get("xiuwei_rate", 0.0))
	learned[wid]["xiuwei"] += int(round(v * rate))
	var lv_now: int = learned[wid]["lv"]
	if lv_now >= 5: return
	var need: int = lv_now * 100
	if learned[wid]["xiuwei"] >= need:
		learned[wid]["lv"] = lv_now + 1
		learned[wid]["xiuwei"] = 0
		refresh_vitals()
		EventBus.toast.emit("【%s】突破第%s重！" % [GameDB.get_wuxue(wid).get("name", wid), "一二三四五"[learned[wid]["lv"] - 1]])
		EventBus.wuxue_breakthrough.emit(wid, learned[wid]["lv"])

func equip_wuxue(slot: String, wid: String) -> void:
	if not learned.has(wid): return
	if GameDB.get_wuxue(wid).get("kind", "") != slot: return
	equipped[slot] = wid
	refresh_vitals()

# ---------- 经脉 ----------
func open_meridian(mid: String, dir: String) -> String:
	if meridians.has(mid): return "已通"
	var mer: Dictionary = GameDB.get_meridian(mid)
	if mer == {}: return "无此经脉"
	var cost: Dictionary = mer.get("cost", {})
	if zhenqi < int(cost.get("zhenqi", 0)): return "真气不足"
	if int(cost.get("dan", 0)) > 0 and count_item("c_xingqidan") < int(cost["dan"]):
		return "缺少资质丹"
	zhenqi -= int(cost.get("zhenqi", 0))
	if int(cost.get("dan", 0)) > 0:
		remove_item("c_xingqidan", int(cost["dan"]))
	meridians[mid] = dir
	refresh_vitals()
	EventBus.meridian_opened.emit(mid, dir)
	EventBus.toast.emit("经脉【%s】%s！" % [mer.get("name", mid), "顺通" if dir == "shun" else "逆通"])
	return "ok"

# ---------- 品格/名声/好感 ----------
func add_morality(key: String, val: int) -> void:
	if not MORAL_KEYS.has(key): return
	morality[key] = clampi(morality[key] + val, -100, 100)
	EventBus.morality_changed.emit(morality)

func add_fame(val: int) -> void:
	fame = maxi(0, fame + val)
	var lname := fame_name()
	EventBus.fame_changed.emit(fame, lname)

func fame_name() -> String:
	var idx := 0
	for i in FAME_LEVELS.size():
		if fame >= FAME_LEVELS[i]: idx = i
	return FAME_NAMES[idx]

func add_affinity(npc_id: String, val: int) -> void:
	var rate: float = 1.0 + float(get_all_mods().get("affinity_rate", 0.0))
	affinity[npc_id] = clampi(int(affinity.get(npc_id, 0)) + int(round(val * rate)), -100, 100)
	EventBus.affinity_changed.emit(npc_id, affinity[npc_id])
	_check_affinity_rewards(npc_id)

func get_affinity(npc_id: String) -> int:
	return int(affinity.get(npc_id, 0))

# ---------- 人际四层网：送礼 / 好感阈值 / 门派贡献 / 名声门槛 ----------

## 礼签：物品 id/名 → gift_pref 标签（江南春=酒之类名实映射）
func _gift_tag(iid: String, item: Dictionary) -> String:
	var alias := {"g_jiangnanchun": "酒", "g_dianxin": "点心", "g_yanzhi": "胭脂", "g_zihua": "字画", "g_fojing": "佛经", "g_chouduan": "绸缎"}
	if alias.has(iid):
		return str(alias[iid])
	return str(item.get("name", ""))

## 送礼预览（不消耗）：{"delta": int, "mood": str}
func gift_preview(npc_id: String, iid: String) -> Dictionary:
	var npc: Dictionary = GameDB.get_npc(npc_id)
	var item: Dictionary = GameDB.get_item(iid)
	var pref: Dictionary = npc.get("gift_pref", {})
	var tag := _gift_tag(iid, item)
	var mood := "一般"
	if (pref.get("hate", []) as Array).has(tag):
		mood = "厌恶"
	elif (pref.get("love", []) as Array).has(tag):
		mood = "至爱"
	elif (pref.get("like", []) as Array).has(tag):
		mood = "喜欢"
	var val := int(item.get("gift_value", 0))
	var mult := 1.5 if mood == "至爱" else (1.0 if mood == "喜欢" else (0.6 if mood == "一般" else -1.0))
	var delta := maxi(1 if mult > 0 else -4, int(round((val / 10.0 + 2.0) * mult)))
	return {"delta": delta, "mood": mood}

## 送礼（消耗物品 + 好感 + 阈值奖励）
func gift(npc_id: String, iid: String) -> Dictionary:
	var npc: Dictionary = GameDB.get_npc(npc_id)
	var item: Dictionary = GameDB.get_item(iid)
	if npc == {} or item == {} or item.get("cat", "") != "礼物":
		return {"ok": false, "msg": "这东西不便送人。"}
	if not remove_item(iid, 1):
		return {"ok": false, "msg": "行囊里没有这样东西。"}
	var pv := gift_preview(npc_id, iid)
	add_affinity(npc_id, int(pv["delta"]))
	var msg := "%s 收下了%s，微微颔首。（好感%+d）" % [npc.get("name", npc_id), item.get("name", iid), int(pv["delta"])]
	if pv["mood"] == "至爱":
		msg = "%s 眼前一亮：%s这东西，正对心思。（好感%+d）" % [npc.get("name", npc_id), item.get("name", iid), int(pv["delta"])]
	elif pv["mood"] == "厌恶":
		msg = "%s 皱了皱眉，把%s推了回来。（好感%+d）" % [npc.get("name", npc_id), item.get("name", iid), int(pv["delta"])]
	return {"ok": true, "msg": msg, "delta": int(pv["delta"])}

## 好感阈值奖励（npcs.json affinity_rewards，一次性，flags 记账）
func _check_affinity_rewards(npc_id: String) -> void:
	var rewards: Array = GameDB.get_npc(npc_id).get("affinity_rewards", [])
	for i in rewards.size():
		var rw: Dictionary = rewards[i]
		var flag := "affinity_rw_%s_%d" % [npc_id, i]
		if flags.get(flag, false):
			continue
		if get_affinity(npc_id) >= int(rw.get("gte", 999)):
			flags[flag] = true
			_grant_rewards(rw.get("rewards", {}))
			EventBus.toast.emit("【%s】%s" % [GameDB.get_npc(npc_id).get("name", npc_id), rw.get("text", "对你另眼相看。")])

## 通用奖励发放（exp/money/items/wuxue/contrib/fame/morality）
func _grant_rewards(rw: Dictionary) -> void:
	if int(rw.get("exp", 0)) > 0: add_exp(int(rw["exp"]))
	if int(rw.get("money", 0)) != 0: add_money(int(rw["money"]))
	for iid in rw.get("items", {}):
		if int(rw["items"][iid]) > 0:
			add_item(iid, int(rw["items"][iid]))
			learn_book(iid)
	if rw.has("wuxue") and GameDB.get_wuxue(str(rw["wuxue"])) != {}:
		learn_wuxue(str(rw["wuxue"]))
	if int(rw.get("contrib", 0)) != 0: add_contrib(int(rw["contrib"]))
	if int(rw.get("fame", 0)) != 0: add_fame(int(rw["fame"]))
	for mk in rw.get("morality", {}):
		add_morality(mk, int(rw["morality"][mk]))

## 悬赏品级名声门槛（甲25 / 乙10 / 丙0）
func bounty_locked(qid: String) -> Dictionary:
	var q: Dictionary = GameDB.get_quest(qid)
	var qname: String = q.get("name", "")
	var need := 0
	if qname.contains("·甲·"):
		need = 25
	elif qname.contains("·乙·"):
		need = 10
	if fame < need:
		return {"locked": true, "need": need}
	return {"locked": false, "need": need}

# ---------- 背包/货币 ----------
func add_item(iid: String, n: int) -> void:
	if iid == "" or n == 0: return
	inventory[iid] = int(inventory.get(iid, 0)) + n
	if inventory[iid] <= 0: inventory.erase(iid)
	EventBus.inventory_changed.emit()

func remove_item(iid: String, n: int) -> bool:
	if count_item(iid) < n: return false
	add_item(iid, -n)
	return true

func count_item(iid: String) -> int:
	return int(inventory.get(iid, 0))

func money_total() -> int:
	return money_yin * 1000 + money_tong

func can_afford(t: int) -> bool:
	return money_total() >= t

func add_money(t: int) -> void:
	var total := maxi(0, money_total() + t)
	money_yin = total / 1000
	money_tong = total % 1000
	EventBus.money_changed.emit(money_tong, money_yin)

func pay(t: int) -> bool:
	if not can_afford(t): return false
	add_money(-t)
	return true

# ---------- 时辰 ----------
func advance_time(quarters: int) -> void:
	abs_quarter += quarters
	for i in quarters:
		quarter += 1
		if quarter >= 4:
			quarter = 0
			shichen += 1
			if shichen >= 12:
				shichen = 0
				day += 1
		# 每刻真气回复（规避时间墙：分钟级体感）
		var rate: float = 1.0 + float(get_all_mods().get("zhenqi_rate", 0.0))
		zhenqi += int(round(1 * rate))
		# 客栈长租房外每刻回 1 点气血
		if flags.get("inn_room", false) and i % 4 == 0:
			heal(2)
	EventBus.time_changed.emit(day, shichen, quarter)

func shichen_str() -> String:
	return GameDB.shichen_name(shichen) + "时(" + GameDB.shichen_desc(shichen) + ")"

func is_night() -> bool:
	return shichen in [22 % 12, 23 % 12, 0, 1]  # 戌亥子丑中偏夜段：戌=10? 修正：夜=子丑+亥

# ---------- 采集 ----------
func can_gather(gid: String) -> bool:
	return abs_quarter >= int(gather_cooldown.get(gid, 0))

func do_gather(gid: String) -> Dictionary:
	var out := {"ok": false, "items": {}, "msg": ""}
	for m in GameDB.maps.values():
		for g in m.get("gathers", []):
			if g.get("id", "") == gid:
				return _gather_at(g, gid)
	return out

func _gather_at(g: Dictionary, gid: String) -> Dictionary:
	var out := {"ok": false, "items": {}, "msg": ""}
	if not can_gather(gid):
		out["msg"] = "此处资源尚未恢复（%s级）。" % g.get("grade", "丁")
		return out
	var grade: String = g.get("grade", "丁")
	var roll: float = randf() + float(attrs["福缘"]) * 0.01
	var pool: Array = {"采药": ["m_caoy", "m_lingzhi"], "钓鱼": ["m_xianyu", "m_jinli"], "挖矿": ["m_tiekuang", "m_jingtie2"], "伐木": ["m_muliao", "m_muliao"]}[g.get("type", "采药")]
	var iid: String = pool[0] if roll < 0.85 else pool[1]
	var n := 1 + (1 if grade in ["乙", "甲"] and randf() < 0.4 else 0)
	add_item(iid, n)
	out["ok"] = true
	out["items"][iid] = n
	out["msg"] = "采集获得【%s】×%d。" % [GameDB.get_item(iid).get("name", iid), n]
	gather_cooldown[gid] = abs_quarter + int(GATHER_COOLDOWN_Q.get(grade, 6))
	attrs["臂力"] = mini(10, attrs["臂力"] + 1) if randf() < 0.05 else attrs["臂力"]
	add_exp(6)
	counters["gather"] = int(counters.get("gather", 0)) + 1
	counters["gather_herb"] = int(counters.get("gather_herb", 0)) + (1 if g.get("type", "") == "采药" else 0)
	advance_time(2)  # 采集半时辰
	quest_hook({"type": "gather"})
	if g.get("type", "") == "采药":
		quest_hook({"type": "collect", "item": iid})
	quest_hook({"type": "collect", "item": iid})
	if g.get("type", "") == "钓鱼":
		counters["fish"] = int(counters.get("fish", 0)) + 1
		quest_hook({"type": "fish"})
	EventBus.gathering_done.emit(gid, out["items"])
	return out

# ---------- 商店 ----------
func shop_price(iid: String, base: int) -> int:
	var disc := get_all_mods().get("shop_disc", 1.0)
	return maxi(1, int(round(base * disc)))

func buy(iid: String, base_price: int) -> String:
	var price := shop_price(iid, base_price)
	if not pay(price): return "铜钱不足"
	add_item(iid, 1)
	EventBus.toast.emit("购得【%s】。" % GameDB.get_item(iid).get("name", iid))
	return "ok"

func sell(iid: String) -> bool:
	if count_item(iid) <= 0: return false
	var it: Dictionary = GameDB.get_item(iid)
	if it.get("cat", "") == "任务": return false
	var v := maxi(1, int(it.get("price", 1)) / 2)
	remove_item(iid, 1)
	add_money(v)
	EventBus.toast.emit("售出【%s】，得 %d 文。" % [it.get("name", iid), v])
	return true

# ---------- 门派 ----------
func join_faction(fid: String) -> void:
	faction = fid
	var f: Dictionary = GameDB.get_faction(fid)
	var t: String = f.get("join_bonus", {}).get("trait", "")
	if t != "" and GameDB.get_trait(t) != {} and not traits.has(t):
		traits.append(t)
		EventBus.trait_gained.emit(t)
	EventBus.faction_changed.emit(fid, true)
	EventBus.toast.emit("拜入【%s】！获得特性【%s】。" % [f.get("name", fid), GameDB.get_trait(t).get("name", t)])

func leave_faction() -> void:
	if faction == "": return
	var f: Dictionary = GameDB.get_faction(faction)
	add_affinity(f.get("join_via", ""), -int(f.get("leave", {}).get("affinity_cost", 20)))
	faction = ""
	EventBus.faction_changed.emit("", false)

func add_contrib(v: int) -> void:
	faction_contrib = maxi(0, faction_contrib + v)
	# 门派贡献晋升（factions.json contrib_rewards，一次性）
	if faction == "":
		return
	var f: Dictionary = GameDB.get_faction(faction)
	var crs: Array = f.get("contrib_rewards", [])
	for i in crs.size():
		var rw: Dictionary = crs[i]
		var flag := "contrib_rw_%s_%d" % [faction, i]
		if flags.get(flag, false):
			continue
		if faction_contrib >= int(rw.get("gte", 999)):
			flags[flag] = true
			_grant_rewards(rw.get("rewards", {}))
			EventBus.toast.emit("【%s】%s" % [f.get("name", faction), rw.get("text", "你在门派中声望日隆。")])

# ---------- 随从 ----------
func recruit(npc_id: String) -> bool:
	if followers.has(npc_id): return false
	followers.append(npc_id)
	if party.size() < MAX_PARTY:
		party.append(npc_id)
	EventBus.follower_joined.emit(npc_id)
	EventBus.toast.emit("%s 入队！" % GameDB.get_npc(npc_id).get("name", npc_id))
	quest_hook({"type": "recruit"})
	return true

func toggle_party(npc_id: String) -> void:
	if party.has(npc_id):
		party.erase(npc_id)
	elif party.size() < MAX_PARTY and followers.has(npc_id):
		party.append(npc_id)

# ---------- 任务系统（数据驱动 do 钩子） ----------
func quest_state(qid: String) -> String:
	return quest_states.get(qid, {}).get("state", "none")

func quest_step(qid: String) -> int:
	return int(quest_states.get(qid, {}).get("step", 0))

func start_quest(qid: String, silent := false) -> void:
	if quest_states.has(qid): return
	quest_states[qid] = {"state": "active", "step": 0}
	if qid == "m8":
		EventBus.ending_reached.emit("choose")
	if not silent:
		var q: Dictionary = GameDB.get_quest(qid)
		EventBus.quest_toast.emit(qid, "新任务：%s" % q.get("name", qid))
		EventBus.quest_updated.emit(qid, "active", 0)

func advance_quest(qid: String) -> void:
	var st: Dictionary = quest_states.get(qid, {})
	if st.get("state", "") != "active": return
	st["step"] = int(st.get("step", 0)) + 1
	var q: Dictionary = GameDB.get_quest(qid)
	var steps: Array = q.get("steps", [])
	if int(st["step"]) >= steps.size():
		complete_quest(qid)
	else:
		EventBus.quest_toast.emit(qid, "任务进度：%s" % steps[int(st["step"])].get("text", ""))
		EventBus.quest_updated.emit(qid, "active", int(st["step"]))

func complete_quest(qid: String) -> void:
	var st: Dictionary = quest_states.get(qid, {})
	if st.get("state", "") != "active": return
	st["state"] = "done"
	var q: Dictionary = GameDB.get_quest(qid)
	var rw: Dictionary = q.get("rewards", {})
	var got := []
	if int(rw.get("exp", 0)) > 0: add_exp(int(rw["exp"])); got.append("修为+%d" % int(rw["exp"]))
	if int(rw.get("money", 0)) != 0: add_money(int(rw["money"])); got.append("铜钱%+d" % int(rw["money"]))
	for iid in rw.get("items", {}):
		if int(rw["items"][iid]) > 0:
			add_item(iid, int(rw["items"][iid]))
			learn_book(iid)
			got.append(GameDB.get_item(iid).get("name", iid))
	for tid in rw.get("traits", []):
		if GameDB.get_trait(tid) != {} and not traits.has(tid):
			traits.append(tid); EventBus.trait_gained.emit(tid); got.append("特性·" + GameDB.get_trait(tid).get("name", tid))
	for mk in rw.get("morality", {}):
		add_morality(mk, int(rw["morality"][mk]))
	if rw.has("wuxue") and GameDB.get_wuxue(str(rw["wuxue"])) != {}:
		learn_wuxue(str(rw["wuxue"])); got.append("武学·" + GameDB.get_wuxue(str(rw["wuxue"])).get("name", str(rw["wuxue"])))
	if int(rw.get("contrib", 0)) != 0: add_contrib(int(rw["contrib"])); got.append("门派贡献%+d" % int(rw["contrib"]))
	if int(rw.get("fame", 0)) != 0: add_fame(int(rw["fame"]))
	if q.get("type", "") == "悬赏":
		bounty_pool.erase(qid)
	EventBus.quest_toast.emit(qid, "任务完成：%s" % q.get("name", qid))
	EventBus.quest_updated.emit(qid, "done", int(st["step"]))
	EventBus.toast.emit("「%s」完成！%s" % [q.get("name", qid), "、".join(got) if got.size() > 0 else ""])
	# 奖励修为投给当前套路
	if int(rw.get("exp", 0)) > 0 and equipped.get("套路", "") != "":
		add_xiuwei(equipped["套路"], int(rw["exp"]) / 2)
	# 主线完结
	if qid == "m8":
		main_done = true
		EventBus.ending_reached.emit("choose")
	# 门派任务
	if q.get("type", "") == "门派":
		faction_quest_done[qid] = true
	# 自动衔接：解锁后继任务
	_auto_start()

func learn_book(iid: String) -> void:
	var it: Dictionary = GameDB.get_item(iid)
	if it.get("cat", "") == "秘籍" and it.has("learn"):
		learn_wuxue(it["learn"])

func _auto_start() -> void:
	for qid in GameDB.quests:
		if quest_states.has(qid): continue
		var q: Dictionary = GameDB.quests[qid]
		if not q.get("auto", false): continue
		if q.get("type", "") == "悬赏": continue  # 悬赏只从告示板接取
		var pre: Dictionary = q.get("prereq", {})
		var ok := true
		for need in pre.get("quests", []):
			if quest_state(need) != "done": ok = false; break
		if ok: start_quest(qid, true)

## 统一推进钩子：任何行为产生 do 事件时调用
func quest_hook(ev: Dictionary) -> void:
	_auto_start()
	for qid in quest_states.keys():
		var st: Dictionary = quest_states[qid]
		if st.get("state", "") != "active": continue
		var q: Dictionary = GameDB.get_quest(qid)
		var steps: Array = q.get("steps", [])
		if int(st.get("step", 0)) >= steps.size(): continue
		var do: Dictionary = steps[int(st["step"])].get("do", {})
		if _do_match(do, ev, qid, int(st["step"])):
			advance_quest(qid)
			if qid == "m7" and do.get("type", "") == "kill":
				flags["m7_boss_down"] = true

func _do_match(do: Dictionary, ev: Dictionary, qid: String, step: int) -> bool:
	var t: String = do.get("type", "")
	match t:
		"talk": return ev.get("type", "") == "talk" and ev.get("npc", "") == do.get("npc", "")
		"talk_any":
			if ev.get("type", "") != "talk": return false
			return (do.get("npcs", []) as Array).has(ev.get("npc", ""))
		"kill":
			if ev.get("type", "") != "kill": return false
			if ev.get("enemy", "") != do.get("enemy", ""): return false
			var key: String = "qkill_%s_%d" % [qid, step]
			counters[key] = int(counters.get(key, 0)) + 1
			return int(counters[key]) >= int(do.get("count", 1))
		"collect":
			return ev.get("type", "") == "collect" and ev.get("item", "") == do.get("item", "") \
				and count_item(do.get("item", "")) >= int(do.get("count", 1))
		"gather": return ev.get("type", "") == "gather" and int(counters.get("gather", 0)) >= int(do.get("count", 1))
		"fish": return ev.get("type", "") == "fish" and int(counters.get("fish", 0)) >= int(do.get("count", 1))
		"visit":
			if ev.get("type", "") != "visit": return false
			if ev.get("map", "") != do.get("map", ""): return false
			var after: int = int(do.get("after", -1))
			return after < 0 or shichen >= after
		"join_faction": return ev.get("type", "") == "join_faction"
		"recruit": return ev.get("type", "") == "recruit"
		"spar_win": return ev.get("type", "") == "spar_win" and ev.get("npc", "") == do.get("npc", "")
		"hidden": return ev.get("type", "") == "hidden" and ev.get("id", "") == do.get("id", "")
		"ending_choice": return ev.get("type", "") == "ending_choice"
	return false

# ---------- 悬赏池 ----------
func refresh_bounty_pool() -> void:
	bounty_pool.clear()
	for qid in GameDB.quests:
		if GameDB.quests[qid].get("type", "") != "悬赏": continue
		if quest_state(qid) == "done": continue
		bounty_pool.append(qid)

func accept_bounty(qid: String) -> bool:
	if not bounty_pool.has(qid): return false
	if quest_states.has(qid) and quest_states[qid].get("state", "") == "active": return false
	quest_states[qid] = {"state": "active", "step": 0}
	EventBus.quest_toast.emit(qid, "接取：%s" % GameDB.get_quest(qid).get("name", qid))
	return true

# ---------- 奇遇选项效果应用 ----------
func apply_effect(opt: Dictionary) -> String:
	var msgs := []
	if opt.has("money"):
		var mv := int(opt["money"])
		if mv < 0 and not pay(-mv): return "铜钱不足"
		add_money(mv)
	if opt.has("hp"): heal(int(opt["hp"]))
	if opt.has("items"):
		for iid in opt["items"]:
			var n := int(opt["items"][iid])
			if n < 0:
				if count_item(iid) < -n: return "物品不足"
				remove_item(iid, -n)
	for iid in opt.get("items", {}):
		var n2 := int(opt["items"][iid])
		if n2 > 0:
			add_item(iid, n2); learn_book(iid)
			msgs.append("获得【%s】" % GameDB.get_item(iid).get("name", iid))
	if opt.has("exp"): add_exp(int(opt["exp"]))
	if opt.has("affinity"):
		add_affinity(opt["affinity"].get("npc", ""), int(opt["affinity"].get("val", 0)))
	for mk in opt.get("morality", {}):
		add_morality(mk, int(opt["morality"][mk]))
	if opt.has("counter"):
		var ck: String = opt["counter"].get("key", "")
		counters[ck] = int(counters.get(ck, 0)) + int(opt["counter"].get("val", 1))
	if opt.has("learn"):
		learn_wuxue(opt["learn"])
		msgs.append("习得【%s】！" % GameDB.get_wuxue(opt["learn"]).get("name", ""))
	if opt.has("trait"):
		if not traits.has(opt["trait"]):
			traits.append(opt["trait"]); EventBus.trait_gained.emit(opt["trait"])
	if opt.has("quest"):
		start_quest(opt["quest"])
	if opt.has("quest_step"):
		var qs: Dictionary = opt["quest_step"]
		if quest_state(qs.get("quest", "")) == "active": advance_quest(qs["quest"])
	if opt.has("gamble"):
		var g: Dictionary = opt["gamble"]
		if not pay(int(g.get("stake", 0))): return "铜钱不足"
		if randi() % 100 < int(g.get("chance", 50)):
			add_money(int(g.get("stake", 0)) * int(g.get("win_mult", 2)))
			return "骰子落定——你赢了！+%d 文。" % (int(g.get("stake", 0)) * (int(g.get("win_mult", 2)) - 1))
		return "骰子落定——你输了 %d 文。" % int(g.get("stake", 0))
	if msgs.is_empty(): return opt.get("after", "")
	return "、".join(msgs) + "。" + str(opt.get("after", ""))

# ---------- 战斗结算入口 ----------
func settle_battle(res: Dictionary) -> void:
	if res.get("win", false):
		add_exp(int(res.get("exp", 0)))
		add_money(int(res.get("money", 0)))
		for d in res.get("drops", []):
			add_item(d["item"], d.get("n", 1))
			learn_book(d["item"])
		for wid in res.get("xiuwei", {}):
			add_xiuwei(wid, int(res["xiuwei"][wid]))
		for e in res.get("killed", []):
			quest_hook({"type": "kill", "enemy": e})
	if res.get("spar", false):
		if res.get("win", false):
			quest_hook({"type": "spar_win", "npc": res.get("spar_npc", "")})

# ---------- 存档 ----------
func to_save() -> Dictionary:
	return {
		"version": SAVE_VERSION, "player_name": player_name, "weapon": weapon,
		"lv": lv, "exp": exp, "hp": hp, "mp": mp, "zhenqi": zhenqi,
		"attrs": attrs, "morality": morality, "fame": fame,
		"money_tong": money_tong, "money_yin": money_yin, "inventory": inventory,
		"traits": traits, "learned": learned, "equipped": equipped, "equips": equips,
		"meridians": meridians, "formation": formation, "affinity": affinity,
		"faction": faction, "faction_contrib": faction_contrib,
		"followers": followers, "party": party, "quest_states": quest_states,
		"bounty_pool": bounty_pool, "counters": counters, "gather_cooldown": gather_cooldown,
		"day": day, "shichen": shichen, "quarter": quarter, "abs_quarter": abs_quarter,
		"faction_quest_done": faction_quest_done, "main_done": main_done, "flags": flags,
	}

func from_save(d: Dictionary) -> void:
	reset()
	inited = true
	for k in d:
		if k == "version": continue
		if k in self:
			set(k, d[k])
	refresh_vitals()
	EventBus.time_changed.emit(day, shichen, quarter)
	EventBus.money_changed.emit(money_tong, money_yin)
