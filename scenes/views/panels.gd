extends Control
## Panels —— 交互面板层：对话/商店/背包/状态/武学/经脉/任务/炼制/悬赏/奇遇。
## 由 TownView 挂载，覆盖在地图之上。

var main: Node
var town: Node   # 反向引用 town_view（战斗跳转用）

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------- 通用骨架 ----------
func _clear() -> void:
	for c in get_children():
		c.queue_free()

func _base(title: String, w := 640.0, h := 420.0) -> Dictionary:
	_clear()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(w, h)
	pc.position = Vector2((960 - w) / 2, (540 - h) / 2)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 18)
	tl.add_theme_color_override("font_color", Color("e8e0d0"))
	vb.add_child(tl)
	var sep := HSeparator.new()
	vb.add_child(sep)
	return {"vb": vb, "pc": pc}

func _close_btn(vb: VBoxContainer, cb: Callable = Callable()) -> void:
	var b := Button.new()
	b.text = "离开"
	b.pressed.connect(func():
		_clear()
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if cb.is_valid(): cb.call())
	vb.add_child(b)

func _opts(vb: VBoxContainer, options: Array) -> void:
	for o in options:
		var b := Button.new()
		b.text = o.get("text", "?")
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(300, 0)
		if o.has("disabled"):
			b.disabled = bool(o["disabled"])
		b.pressed.connect(o["cb"])
		vb.add_child(b)

func _body(vb: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	l.add_theme_font_size_override("font_size", 14)
	vb.add_child(l)
	return l

# ---------- NPC 交互主面板 ----------
func npc_dialog(npc_id: String) -> void:
	var n: Dictionary = GameDB.get_npc(npc_id)
	var aff: int = GameState.get_affinity(npc_id)
	var b := _base("%s · %s   （好感 %d）" % [n.get("name", npc_id), n.get("title", ""), aff], 660, 470)
	var vb: VBoxContainer = b["vb"]
	var greets: Array = n.get("greet", ["……"])
	_body(vb, greets[randi() % greets.size()])

	var opts := []
	# 交谈：推进任务 + 好感
	opts.append({"text": "交谈", "cb": func():
		GameState.add_affinity(npc_id, 2)
		GameState.quest_hook({"type": "talk", "npc": npc_id})
		main.toast_panel("你与%s攀谈几句。（好感+2）" % n.get("name", npc_id))
		npc_dialog(npc_id)})
	# 送礼
	var gifts := _gift_list()
	if gifts.size() > 0:
		opts.append({"text": "送礼", "cb": func(): _gift_pick(npc_id)})
	# 请教
	var iq: Dictionary = n.get("inquire", {})
	if not iq.is_empty():
		opts.append({"text": "请教（%d文）" % int(iq.get("cost", 100)), "cb": func(): _inquire(npc_id)})
	# 切磋
	if n.has("spar"):
		opts.append({"text": "切磋一番", "cb": func():
			_clear()
			town.start_spar(npc_id)})
	# 商店
	if n.has("shop"):
		var shop: Dictionary = GameDB.get_shop(n["shop"])
		if _shop_available(n):
			opts.append({"text": "买卖（%s）" % shop.get("name", ""), "cb": func(): shop_panel(n["shop"])})
		else:
			opts.append({"text": "买卖（%s·此刻不在营业）" % shop.get("name", ""), "cb": func(): pass, "disabled": true})
	# 随从招募
	if n.get("role", "") == "随从":
		if GameState.followers.has(npc_id):
			opts.append({"text": "编入/调离队伍", "cb": func():
				GameState.toggle_party(npc_id)
				main.toast_panel("调整了队伍编成。")
				npc_dialog(npc_id)})
		elif aff >= 30:
			opts.append({"text": "邀其同行", "cb": func():
				GameState.recruit(npc_id)
				_after_affinity_event(npc_id)
				npc_dialog(npc_id)})
		else:
			opts.append({"text": "邀其同行（好感需30，当前%d）" % aff, "disabled": true, "cb": func(): pass})
	# 门派
	if n.has("faction"):
		_append_faction_opts(opts, n)
	# 任务交付类 NPC（主线/随从任务 talk 由 quest_hook 处理，这里提示）
	if n.get("role", "") == "任务":
		opts.append({"text": "请教江湖路（任务提示）", "cb": func():
			_body_hint(npc_id)
			npc_dialog(npc_id)})
	# 悬赏告示板
	if npc_id == "tie_putou":
		opts.append({"text": "查看悬赏告示板", "cb": func(): bounty_panel()})
	# 客栈住宿
	if npc_id == "wu_san":
		opts.append({"text": "住店歇息（20文，回满并睡到卯时）", "cb": func(): _inn_rest()})
		opts.append({"text": "租下长住客房（2000文：炼丹台+每刻回气）", "cb": func(): _inn_room()})
	# 奇遇
	var enc := _match_encounter(npc_id)
	for eid in enc:
		opts.append({"text": "◆ " + GameDB.encounters[eid].get("name", eid), "cb": func(): encounter_panel(eid)})
	_opts(vb, opts)
	_close_btn(vb, func(): town.resume())

func _body_hint(npc_id: String) -> void:
	var hints := {
		"gu_laozhang": "「去村东找玄尘老先生吧，他懂武艺。」",
		"xuanchen": "「打坐修炼（状态面板·修炼）最能精进。江州城在村子东南。」",
		"meng_qian": "「铁剑门在城北剑冢峰，伏虎禅寺在临安镇旁，烟波楼得从江州坐船。」",
		"tie_putou": "「拜月教近来频频现身……你若见着黑衣人，速来报官。」",
		"sun_daifu": "「采回的草药可以炼丹。材料齐了就来。」",
	}
	if hints.has(npc_id):
		main.toast_panel(hints[npc_id])

func _gift_list() -> Array:
	var out := []
	for iid in GameState.inventory:
		var it: Dictionary = GameDB.get_item(iid)
		if it.get("cat", "") in ["礼物", "消耗", "材料"] and int(GameState.inventory[iid]) > 0:
			out.append(iid)
	return out

func _gift_pick(npc_id: String) -> void:
	var n: Dictionary = GameDB.get_npc(npc_id)
	var b := _base("送礼 → %s" % n.get("name", npc_id), 560, 420)
	var vb: VBoxContainer = b["vb"]
	var pref: Dictionary = n.get("gift_pref", {})
	var opts := []
	for iid in _gift_list():
		var it: Dictionary = GameDB.get_item(iid)
		var val := int(it.get("gift_value", 0))
		var mood := "一般"
		var col := Color("8a94a8")
		if (pref.get("love", []) as Array).has(it.get("name", "")):
			mood = "至爱"; col = Color("c96a8a")
		elif (pref.get("like", []) as Array).has(it.get("name", "")):
			mood = "喜欢"; col = Color("7ab86a")
		elif (pref.get("hate", []) as Array).has(it.get("name", "")):
			mood = "厌恶"; col = Color("c96a5a")
		var aff_gain: int = maxi(1, int(round((val / 10.0 + 2.0) * (1.5 if mood == "至爱" else 1.0 if mood == "喜欢" else 0.6 if mood == "一般" else -1.0))))
		opts.append({"text": "【%s】×%d（%s，好感%+d）" % [it.get("name", iid), GameState.inventory[iid], mood, aff_gain], "cb": func():
			if GameState.remove_item(iid, 1):
				GameState.add_affinity(npc_id, aff_gain)
				main.toast_panel("%s 收下了%s。（好感%+d）" % [n.get("name", npc_id), it.get("name", iid), aff_gain])
				_after_affinity_event(npc_id)
			npc_dialog(npc_id)})
	_opts(vb, opts)
	_close_btn(vb, func(): npc_dialog(npc_id))

func _inquire(npc_id: String) -> void:
	var n: Dictionary = GameDB.get_npc(npc_id)
	var iq: Dictionary = n.get("inquire", {})
	if not GameState.pay(int(iq.get("cost", 100))):
		main.toast_panel("铜钱不足。")
		return
	GameState.add_affinity(npc_id, int(iq.get("affinity", 20)))
	GameState.add_exp(int(iq.get("exp", 40)))
	GameState.advance_time(1)
	main.toast_panel("听了%s一席话，受益匪浅。（修为+%d）" % [n.get("name", npc_id), int(iq.get("exp", 40))])
	npc_dialog(npc_id)

func _after_affinity_event(npc_id: String) -> void:
	# 随从个人任务触发
	var triggers := {"liumianmian": "f_liu1", "qin_wuyi": "f_qin1", "bai_zhi": "f_bai1"}
	if triggers.has(npc_id) and GameState.quest_state(triggers[npc_id]) == "none":
		GameState.start_quest(triggers[npc_id])
	# 高好感奇遇提示
	if GameState.get_affinity(npc_id) >= 60:
		main.toast_panel("%s 对你颇为信任了（好感60：易物/私密事件解锁）。" % GameDB.get_npc(npc_id).get("name", npc_id))

func _shop_available(n: Dictionary) -> bool:
	if n.get("night_only", false):
		return GameState.shichen in [0, 1]
	if n.has("hours"):
		return (n["hours"] as Array).has(GameDB.shichen_name(GameState.shichen))
	return true

func _inn_rest() -> void:
	if not GameState.pay(20):
		main.toast_panel("铜钱不足。")
		return
	GameState.hp = GameState.get_panel()["hp_max"]
	GameState.mp = GameState.get_panel()["mp_max"]
	GameState.advance_time(maxi(1, (12 - GameState.shichen) % 12 * 4 + 4))  # 睡到明日卯时
	EventBus.hp_mp_changed.emit(GameState.hp, GameState.get_panel()["hp_max"], GameState.mp, GameState.get_panel()["mp_max"])
	main.toast_panel("一夜好眠。气血内力尽复。")
	npc_dialog("wu_san")

func _inn_room() -> void:
	if GameState.flags.get("inn_room", false):
		main.toast_panel("你已租下长住客房。")
		return
	if not GameState.pay(2000):
		main.toast_panel("铜钱不足（需2000文）。")
		return
	GameState.flags["inn_room"] = true
	main.toast_panel("长住客房已租下：内置炼丹台，休息恢复更快。")

func _append_faction_opts(opts: Array, n: Dictionary) -> void:
	var fid: String = n["faction"]
	var f: Dictionary = GameDB.get_faction(fid)
	if GameState.faction == fid:
		opts.append({"text": "门派贡献阁（贡献%d）" % GameState.faction_contrib, "cb": func(): sect_shop_panel(fid)})
		if n["id"] == f.get("elder", ""):
			opts.append({"text": "退出师门", "cb": func():
				GameState.leave_faction()
				main.toast_panel("你退出了%s。" % f.get("name", fid))
				npc_dialog(n["id"])})
	elif GameState.faction == "":
		var jq: String = f.get("join_quest", "")
		var done := GameState.quest_state(jq) == "done" if jq != "" else false
		opts.append({"text": "请求拜入%s" % f.get("name", fid), "cb": func():
			if jq != "" and not done:
				if GameState.quest_state(jq) == "none":
					GameState.start_quest(jq)
				main.toast_panel("「先完成入门试炼：%s。」" % GameDB.get_quest(jq).get("name", jq))
			else:
				GameState.join_faction(fid)
				GameState.quest_hook({"type": "join_faction"})
			npc_dialog(n["id"])})
	else:
		opts.append({"text": "（你已身在%s）" % GameDB.get_faction(GameState.faction).get("name", ""), "disabled": true, "cb": func(): pass})

func _match_encounter(npc_id: String) -> Array:
	var out := []
	for eid in GameDB.encounters:
		var e: Dictionary = GameDB.encounters[eid]
		var tr: Dictionary = e.get("trigger", {})
		if tr.get("npc", "") != npc_id:
			continue
		if not _enc_cond_ok(tr):
			continue
		out.append(eid)
	return out

func _enc_cond_ok(tr: Dictionary) -> bool:
	if tr.has("shichen_gte") and GameState.shichen < int(tr["shichen_gte"]) and GameState.shichen > 2:
		return false
	if tr.has("counter_gte"):
		var cg: Dictionary = tr["counter_gte"]
		if int(GameState.counters.get(cg["key"], 0)) < int(cg["val"]):
			return false
	if tr.has("money_gte") and GameState.money_total() < int(tr["money_gte"]):
		return false
	if tr.has("lv_gte") and GameState.lv < int(tr["lv_gte"]):
		return false
	if tr.has("attr_gte"):
		var ag: Dictionary = tr["attr_gte"]
		if int(GameState.attrs.get(ag["attr"], 0)) < int(ag["val"]):
			return false
	if tr.has("quest_gte"):
		var qg: Dictionary = tr["quest_gte"]
		if GameState.quest_state(qg["quest"]) != "active" or GameState.quest_step(qg["quest"]) < int(qg["step"]):
			return false
	if tr.has("once") and GameState.flags.get("enc_" + tr["once"], false):
		return false
	return true

# ---------- 地图事件 ----------
func event_prompt(ev: Dictionary) -> void:
	var b := _base("◆ " + ev.get("name", "事件"), 620, 320)
	var vb: VBoxContainer = b["vb"]
	_body(vb, ev.get("intro", "……"))
	_opts(vb, [{"text": "迎战！", "cb": func():
		_clear()
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		town.start_custom_battle(ev, ev.get("id", "evt"))}])
	_close_btn(vb, func(): town.resume())

# ---------- 奇遇 ----------
func encounter_panel(eid: String) -> void:
	var e: Dictionary = GameDB.encounters[eid]
	var b := _base("◆ %s" % e.get("name", eid), 620, 360)
	var vb: VBoxContainer = b["vb"]
	_body(vb, e.get("text", "……"))
	var opts := []
	for o in e.get("options", []):
		var opt: Dictionary = o
		opts.append({"text": opt.get("text", "…"), "cb": func(): _enc_apply(eid, opt)})
	_opts(vb, opts)
	_close_btn(vb, func(): town.resume())

func _enc_apply(eid: String, opt: Dictionary) -> void:
	# 战斗类选项
	if opt.has("battle"):
		GameState.flags["enc_" + eid] = true
		_clear()
		town.start_custom_battle(opt["battle"], eid)
		return
	if opt.has("luck_check"):
		var lc: Dictionary = opt["luck_check"]
		var roll: int = randi() % 10 + int(GameState.attrs["福缘"])
		if roll >= int(lc.get("dc", 6)):
			main.toast_panel(str(lc.get("success", "")))
		else:
			main.toast_panel(str(lc.get("fail", "")))
			if lc.has("fail_battle"):
				_clear()
				town.start_custom_battle(lc["fail_battle"], eid)
				return
	var msg: String = GameState.apply_effect(opt)
	GameState.flags["enc_" + eid] = true
	if msg != "":
		main.toast_panel(msg)
	town.resume()

# ---------- 商店 ----------
func shop_panel(shop_id: String) -> void:
	var s: Dictionary = GameDB.get_shop(shop_id)
	var b := _base("%s   （铜钱 %d｜银两 %d）" % [s.get("name", shop_id), GameState.money_tong, GameState.money_yin], 680, 460)
	var vb: VBoxContainer = b["vb"]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 330)
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in s.get("items", []):
		var iid: String = entry["item"]
		var it: Dictionary = GameDB.get_item(iid)
		if it == {}: continue
		var contrib := int(entry.get("contrib", -1))
		var price := GameState.shop_price(iid, int(entry.get("price", it.get("price", 100)))) if contrib < 0 else contrib
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var unit: String = "贡献" if contrib >= 0 else "文"
		lbl.text = "【%s】%s  —— %d %s" % [it.get("name", iid), _grade_tag(it), price, unit]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var buy := Button.new()
		buy.text = "买"
		var can_afford: bool = GameState.faction_contrib >= contrib if contrib >= 0 else GameState.can_afford(price)
		buy.disabled = not can_afford
		buy.pressed.connect(func():
			if contrib >= 0:
				if GameState.faction_contrib < contrib: return
				GameState.add_contrib(-contrib)
				GameState.add_item(iid, 1)
				GameState.learn_book(iid)
				main.toast_panel("以%d贡献换得【%s】。" % [contrib, it.get("name", iid)])
			else:
				var r: String = GameState.buy(iid, price)
				if r == "ok": GameState.learn_book(iid)
				else: main.toast_panel(r)
			shop_panel(shop_id))
		row.add_child(buy)
		list.add_child(row)
	# 卖出区
	var sell_hdr := Label.new()
	sell_hdr.text = "—— 卖出（半价，任务物除外）——"
	sell_hdr.add_theme_color_override("font_color", Color("7a8aa0"))
	vb.add_child(sell_hdr)
	var sell_scroll := ScrollContainer.new()
	sell_scroll.custom_minimum_size = Vector2(650, 60)
	vb.add_child(sell_scroll)
	var sell_list := HFlowContainer.new()
	sell_scroll.add_child(sell_list)
	for iid in GameState.inventory:
		var it2: Dictionary = GameDB.get_item(iid)
		if it2.get("cat", "") == "任务" or int(GameState.inventory[iid]) <= 0: continue
		var sb := Button.new()
		sb.text = "%s×%d (+%d)" % [it2.get("name", iid), GameState.inventory[iid], maxi(1, int(it2.get("price", 1)) / 2)]
		sb.add_theme_font_size_override("font_size", 12)
		sb.pressed.connect(func():
			GameState.sell(iid)
			shop_panel(shop_id))
		sell_list.add_child(sb)
	_close_btn(vb, func(): town.resume())

func _grade_tag(it: Dictionary) -> String:
	if it.has("grade"):
		return "·" + str(it["grade"])
	return ""

func sect_shop_panel(fid: String) -> void:
	shop_panel("sect_" + fid)

# ---------- 悬赏 ----------
func bounty_panel() -> void:
	var b := _base("悬赏告示板", 620, 440)
	var vb: VBoxContainer = b["vb"]
	GameState.refresh_bounty_pool()
	if GameState.bounty_pool.is_empty():
		_body(vb, "暂无悬赏。")
	var opts := []
	for qid in GameState.bounty_pool:
		var q: Dictionary = GameDB.get_quest(qid)
		var st := GameState.quest_state(qid)
		var txt := "%s\n    %s（赏 %d 文）" % [q.get("name", qid), q.get("desc", ""), int(q.get("rewards", {}).get("money", 0))]
		if st == "active":
			opts.append({"text": "▶ " + txt + " [进行中]", "disabled": true, "cb": func(): pass})
		else:
			opts.append({"text": txt, "cb": func():
				GameState.accept_bounty(qid)
				bounty_panel()})
	_opts(vb, opts)
	_close_btn(vb, func(): town.resume())

# ---------- 炼制 ----------
func craft_panel() -> void:
	var b := _base("炼丹 / 烹饪", 620, 440)
	var vb: VBoxContainer = b["vb"]
	var opts := []
	for rid in GameDB.recipes:
		var r: Dictionary = GameDB.recipes[rid]
		var mats_ok := true
		var mat_txt := []
		for m in r.get("mats", {}):
			var need: int = int(r["mats"][m])
			var have := GameState.count_item(m)
			mat_txt.append("%s%d/%d" % [GameDB.get_item(m).get("name", m), have, need])
			if have < need: mats_ok = false
		opts.append({"text": "%s（%s）→ %s ×%d%s" % [
			r.get("name", rid), "、".join(mat_txt),
			GameDB.get_item(r.get("out", "")).get("name", "?"), int(r.get("count", 1)),
			"" if mats_ok else "  [材料不足]"],
			"disabled": not mats_ok, "cb": func(): _do_craft(rid)})
	_opts(vb, opts)
	_close_btn(vb, func(): town.resume())

func _do_craft(rid: String) -> void:
	var r: Dictionary = GameDB.recipes[rid]
	for m in r.get("mats", {}):
		GameState.remove_item(m, int(r["mats"][m]))
	GameState.add_item(r["out"], int(r.get("count", 1)))
	GameState.advance_time(2)
	main.toast_panel("炼成了【%s】×%d。（耗时半个时辰）" % [GameDB.get_item(r["out"]).get("name", ""), int(r.get("count", 1))])
	craft_panel()

# ---------- 状态菜单（多页签） ----------
func status_panel() -> void:
	var b := _base("%s 的行囊与修行" % GameState.player_name, 760, 480)
	var vb: VBoxContainer = b["vb"]
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(740, 400)
	vb.add_child(tabs)
	tabs.add_child(_tab_status())
	tabs.add_child(_tab_wuxue())
	tabs.add_child(_tab_meridian())
	tabs.add_child(_tab_quests())
	tabs.add_child(_tab_inv())
	tabs.add_child(_tab_cloud())
	_close_btn(vb, func(): town.resume())

func _tab_status() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "状态"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var p: Dictionary = GameState.get_panel()
	var mods := GameState.get_all_mods()
	var trait_s := "无"
	if GameState.traits.size() > 0:
		var tnames := []
		for t in GameState.traits:
			tnames.append(str(GameDB.get_trait(t).get("name", t)))
		trait_s = "、".join(tnames)
	var party_s := "无"
	if GameState.party.size() > 0:
		var pnames := []
		for f in GameState.party:
			pnames.append(str(GameDB.get_npc(f).get("name", f)))
		party_s = "、".join(pnames)
	var faction_s := "无门无派"
	if GameState.faction != "":
		faction_s = str(GameDB.get_faction(GameState.faction).get("name", "无门无派"))
	var l := Label.new()
	l.text = "%s · 等级%d（修为 %d/%d） · %s\n五维：臂力%d 体质%d 敏捷%d 悟性%d 福缘%d\n气血 %d/%d   内力 %d/%d   真气 %d\n攻%d 防%d 速%d 命中%d%% 闪避%d%% 暴击%d%%\n门派：%s（贡献%d）   阵法：%s\n名声：%s（%d）   品格：仁%d 义%d 勇%d\n特性：%s\n随从：%s" % [
		GameState.player_name, GameState.lv, GameState.exp, GameState.exp_need(GameState.lv), GameState.shichen_str(),
		GameState.attrs["臂力"], GameState.attrs["体质"], GameState.attrs["敏捷"], GameState.attrs["悟性"], GameState.attrs["福缘"],
		GameState.hp, p["hp_max"], GameState.mp, p["mp_max"], GameState.zhenqi,
		p["atk"], p["def"], p["spd"], p["hit"], p["dodge"], p["crit"],
		faction_s,
		GameState.faction_contrib, GameDB.get_formation(GameState.formation).get("name", GameState.formation),
		GameState.fame_name(), GameState.fame,
		GameState.morality["仁"], GameState.morality["义"], GameState.morality["勇"],
		trait_s,
		party_s,
	]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	# 打坐
	var med := Button.new()
	med.text = "打坐修炼（2个时辰：回复气血内力+套路修为）"
	med.pressed.connect(func():
		GameState.advance_time(8)
		GameState.heal(GameState.get_panel()["hp_max"] / 3, GameState.get_panel()["mp_max"] / 3)
		var wid: String = GameState.equipped["套路"]
		GameState.add_xiuwei(wid, 20)
		main.toast_panel("打坐吐纳，气息绵长。（【%s】修为+20）" % GameDB.get_wuxue(wid).get("name", wid))
		status_panel())
	vb.add_child(med)
	# 阵法选择
	var fh := Label.new()
	fh.text = "行军阵法："
	vb.add_child(fh)
	var frow := HBoxContainer.new()
	vb.add_child(frow)
	for fid in GameDB.formations:
		var f: Dictionary = GameDB.formations[fid]
		var fb := Button.new()
		fb.text = "%s\n%s" % [f.get("name", fid), f.get("bonus", {}).get("text", "")]
		fb.toggle_mode = true
		fb.button_pressed = GameState.formation == fid
		fb.add_theme_font_size_override("font_size", 12)
		fb.custom_minimum_size = Vector2(140, 50)
		fb.pressed.connect(func():
			GameState.formation = fid
			status_panel())
		frow.add_child(fb)
	return sc

func _tab_wuxue() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "武学"
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	for slot in ["套路", "内功", "轻功"]:
		var hdr := Label.new()
		hdr.text = "—— %s（当前：%s）——" % [slot, GameDB.get_wuxue(GameState.equipped[slot]).get("name", "无")]
		hdr.add_theme_color_override("font_color", Color("c9a067"))
		vb.add_child(hdr)
		for wid in GameState.learned:
			var w: Dictionary = GameDB.get_wuxue(wid)
			if w.get("kind", "") != slot: continue
			var lv: int = GameState.wuxue_lv(wid)
			var xw: int = int(GameState.learned[wid].get("xiuwei", 0))
			var need: int = lv * 100
			var traits_s: String = "、".join(w.get("traits", []))
			var row := HBoxContainer.new()
			vb.add_child(row)
			var lbl := Label.new()
			var sub: String = w.get("desc", "")
			if slot == "套路" and w.has("moves"):
				var mv_names := []
				for m in w["moves"]:
					mv_names.append(str(m.get("name", "")))
				sub += "  招式：" + "、".join(mv_names)
			lbl.text = "【%s】%s级 第%d重（修为%d/%d）\n    %s\n    词条：%s" % [
				w.get("name", wid), w.get("grade", ""), lv, xw, need, sub, traits_s]
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var eq := Button.new()
			eq.text = "装备"
			eq.disabled = GameState.equipped[slot] == wid
			var slot_capture: String = slot
			var wid_capture: String = wid
			eq.pressed.connect(func():
				GameState.equip_wuxue(slot_capture, wid_capture)
				status_panel())
			row.add_child(eq)
			# 修炼投修为
			var xiulian := Button.new()
			xiulian.text = "参悟(1时辰+15修为)"
			xiulian.add_theme_font_size_override("font_size", 12)
			xiulian.pressed.connect(func():
				GameState.advance_time(4)
				GameState.add_xiuwei(wid_capture, 15)
				main.toast_panel("参悟【%s】。（修为+15）" % w.get("name", wid_capture))
				status_panel())
			row.add_child(xiulian)
	return sc

func _tab_meridian() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "经脉"
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var info := Label.new()
	info.text = "真气 %d（打坐与行动自然恢复）。每条经脉顺通/逆通二择一。资质丹=行气丹替代。"
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("7a8aa0"))
	vb.add_child(info)
	for mid in GameDB.meridians:
		var m: Dictionary = GameDB.meridians[mid]
		var row := HBoxContainer.new()
		vb.add_child(row)
		var cur: String = GameState.meridians.get(mid, "")
		var lbl := Label.new()
		lbl.text = "%s：%s｜%s\n%s    %s    （需真气%d·行气丹%d）" % [
			m.get("name", mid),
			("已顺通" if cur == "shun" else ("已逆通" if cur == "ni" else "未通")),
			m.get("desc", ""),
			m.get("shun", {}).get("text", ""), m.get("ni", {}).get("text", ""),
			int(m.get("cost", {}).get("zhenqi", 0)), int(m.get("cost", {}).get("dan", 0))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		if cur == "":
			var mid_capture: String = mid
			var bs := Button.new()
			bs.text = "顺通"
			bs.pressed.connect(func():
				var r: String = GameState.open_meridian(mid_capture, "shun")
				if r != "ok": main.toast_panel(r)
				status_panel())
			row.add_child(bs)
			var bn := Button.new()
			bn.text = "逆通"
			bn.pressed.connect(func():
				var r: String = GameState.open_meridian(mid_capture, "ni")
				if r != "ok": main.toast_panel(r)
				status_panel())
			row.add_child(bn)
	return sc

func _tab_quests() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "任务"
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var groups := {"主线": [], "门派": [], "随从": [], "悬赏": []}
	for qid in GameState.quest_states:
		var st: Dictionary = GameState.quest_states[qid]
		var q: Dictionary = GameDB.get_quest(qid)
		var typ: String = q.get("type", "主线")
		if not groups.has(typ): typ = "主线"
		var state_s: String = "✓完成" if st["state"] == "done" else "▶ %d/%d" % [int(st["step"]), q.get("steps", []).size()]
		var cur_step: int = int(st["step"])
		var steps: Array = q.get("steps", [])
		var step_txt: String = ""
		if st["state"] == "active" and cur_step < steps.size():
			step_txt = "\n    当前：%s（%s）" % [steps[cur_step].get("text", ""), steps[cur_step].get("hint", "")]
		groups[typ].append("【%s】%s %s%s" % [q.get("name", qid), state_s, q.get("desc", ""), step_txt])
	for typ in groups:
		if (groups[typ] as Array).is_empty(): continue
		var hdr := Label.new()
		hdr.text = "—— %s ——" % typ
		hdr.add_theme_color_override("font_color", Color("c9a067"))
		vb.add_child(hdr)
		for line in groups[typ]:
			var l := Label.new()
			l.text = line
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 13)
			vb.add_child(l)
	return sc

func _tab_inv() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "背包"
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var info := Label.new()
	info.text = "铜钱%d·银两%d。点击物品使用/装备。" % [GameState.money_tong, GameState.money_yin]
	info.add_theme_font_size_override("font_size", 13)
	vb.add_child(info)
	for iid in GameState.inventory:
		var it: Dictionary = GameDB.get_item(iid)
		if it == {}: continue
		var row := HBoxContainer.new()
		vb.add_child(row)
		var lbl := Label.new()
		var extra: String = it.get("desc", "")
		if it.get("cat", "") == "装备" and it.has("equip"):
			extra += "（%s·%s）" % [it["equip"], it.get("weapon", "通用")]
		lbl.text = "【%s】×%d  %s" % [it.get("name", iid), GameState.inventory[iid], extra]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var act := _item_action(it, iid)
		if act != null:
			row.add_child(act)
		# 已装备标记
		for slot in GameState.equips:
			if GameState.equips[slot] == iid:
				var tag := Label.new()
				tag.text = "已装"
				tag.add_theme_color_override("font_color", Color("c9a067"))
				row.add_child(tag)
	return sc

func _item_action(it: Dictionary, iid: String) -> Button:
	var act := Button.new()
	if it.get("cat", "") == "消耗" and it.has("use"):
		act.text = "使用"
		var use: Dictionary = it["use"]
		act.pressed.connect(func():
			if GameState.remove_item(iid, 1):
				if use.has("hp") or use.has("mp"):
					GameState.heal(int(use.get("hp", 0)), int(use.get("mp", 0)))
					main.toast_panel("用了【%s】。" % it.get("name", iid))
				if use.has("cure"):
					for st in use["cure"]:
						pass  # 战外状态简化：直接提示
					main.toast_panel("毒伤尽去。")
				if use.has("battle_buff"):
					GameState.flags["pre_buff"] = use["battle_buff"]
					main.toast_panel("药力鼓荡（下场战斗生效）。")
			status_panel())
	elif it.get("cat", "") == "秘籍":
		act.text = "参悟"
		act.disabled = true
		act.tooltip_text = "阅读即自动习得"
	elif it.get("cat", "") == "装备":
		act.text = "装备"
		var slot: String = it.get("equip", "武器")
		act.pressed.connect(func():
			GameState.equips[slot] = iid
			GameState.refresh_vitals()
			main.toast_panel("装备了【%s】。" % it.get("name", iid))
			status_panel())
	else:
		return null
	return act

# ---------- 云同步（双端互通） ----------
func _tab_cloud() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "云同步"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "双端云存档互通：电脑上传 → 手机拉取（或反向）。需先启动 server/save_server.mjs，双端填同一地址与账号。保存时若已配置会自动上传。"
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color("7a8aa0"))
	vb.add_child(info)
	var gh := Label.new()
	gh.text = "服务器与账号"
	vb.add_child(gh)
	var url := LineEdit.new()
	url.placeholder_text = "服务器地址 如 http://192.168.1.5:8787"
	url.text = CloudSync.base_url
	var un := LineEdit.new()
	un.placeholder_text = "用户名（2-24 位字母数字）"
	un.text = CloudSync.user
	var pw := LineEdit.new()
	pw.placeholder_text = "PIN 码（≥4 位）"
	pw.secret = true
	pw.text = CloudSync.pin
	for e in [url, un, pw]:
		vb.add_child(e)
	var st := Label.new()
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_theme_font_size_override("font_size", 13)
	var cb_box := VBoxContainer.new()
	vb.add_child(_cloud_btn("保存配置", func(): _cloud_save_cfg(url, un, pw, st)))
	vb.add_child(_cloud_btn("注册新账号", func(): _cloud_do_reg(url, un, pw, st)))
	vb.add_child(_cloud_btn("上传本地存档到云端", func(): _cloud_do_push(url, un, pw, st)))
	vb.add_child(_cloud_btn("查看云端存档（拉取 / 冲突裁决）", func(): _cloud_do_peek(url, un, pw, st, cb_box)))
	vb.add_child(st)
	vb.add_child(cb_box)
	return sc

func _cloud_save_cfg(url: LineEdit, un: LineEdit, pw: LineEdit, st: Label) -> void:
	CloudSync.save_config(url.text, un.text, pw.text)
	st.text = "配置已保存（%s @ %s）" % [CloudSync.user, CloudSync.base_url]

func _cloud_do_reg(url: LineEdit, un: LineEdit, pw: LineEdit, st: Label) -> void:
	CloudSync.save_config(url.text, un.text, pw.text)
	CloudSync.register(CloudSync.user, CloudSync.pin, _cloud_reg_cb.bind(st))

func _cloud_do_push(url: LineEdit, un: LineEdit, pw: LineEdit, st: Label) -> void:
	CloudSync.save_config(url.text, un.text, pw.text)
	CloudSync.push(_cloud_push_cb.bind(st))

func _cloud_do_peek(url: LineEdit, un: LineEdit, pw: LineEdit, st: Label, cb_box: VBoxContainer) -> void:
	CloudSync.save_config(url.text, un.text, pw.text)
	st.text = "正在查询云端…"
	CloudSync.peek(_cloud_peek_cb.bind(st, cb_box))

func _cloud_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _cloud_reg_cb(ok: bool, data: Dictionary, st: Label) -> void:
	st.text = "注册成功，可以上传/拉取了。" if ok else "注册失败：" + str(data.get("error", ""))

func _cloud_push_cb(ok: bool, data: Dictionary, st: Label) -> void:
	st.text = "已上传本地存档。" if ok else "上传失败：" + str(data.get("error", ""))

## 云端状态展示 + 冲突裁决：按时间戳给建议，并提供"下载/覆盖"双向按钮
func _cloud_peek_cb(ok: bool, data: Dictionary, st: Label, cb_box: VBoxContainer) -> void:
	for c in cb_box.get_children():
		c.queue_free()
	if not ok:
		st.text = "查询失败：" + str(data.get("error", ""))
		return
	if not bool(data.get("exists", false)):
		st.text = "云端暂无存档，可先「上传本地存档到云端」。"
		return
	var local_ms := CloudSync.local_saved_at_ms()
	var cloud_ms := int(data.get("pushed_at_ms", 0))
	var dev: String = str(data.get("device_id", "")).right(8)
	var v := CloudSync.verdict(local_ms, cloud_ms)
	var verdict_s := "本地较新，可放心用本地覆盖云端" if v == 1 else ("云端较新，建议下载云端" if v == -1 else "两端接近，请自行选择保留哪份")
	st.text = "云端存档：%s 由设备 …%s 上传。裁决：%s。" % [Time.get_datetime_string_from_unix_time(cloud_ms / 1000, true), dev, verdict_s]
	cb_box.add_child(_cloud_btn("下载云端存档并应用到本机", func():
		CloudSync.pull(_cloud_pull_cb.bind(st))))
	cb_box.add_child(_cloud_btn("上传本地存档覆盖云端", func():
		CloudSync.push(_cloud_push_cb.bind(st))))

func _cloud_pull_cb(ok: bool, data: Dictionary, st: Label) -> void:
	if not ok:
		st.text = "拉取失败：" + str(data.get("error", ""))
		return
	var sd: Dictionary = data.get("save", {})
	if SaveSystem.apply_save_dict(sd) and SaveSystem.write_save_dict(sd):
		main.toast_panel("云端存档已应用。")
		status_panel()   # 重开面板刷新数值
	else:
		st.text = "云端存档格式异常，未应用。"
