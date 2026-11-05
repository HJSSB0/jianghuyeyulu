extends Node
## EventBus —— 全局信号总线：逻辑层发信号，UI 层订阅。保持逻辑零 UI 依赖。

signal toast(msg: String)                       # 轻提示
signal time_changed(day: int, shichen: int, quarter: int)
signal money_changed(tong: int, yin: int)
signal inventory_changed
signal hp_mp_changed(hp: int, max_hp: int, mp: int, max_mp: int)
signal morality_changed(morality: Dictionary)
signal fame_changed(fame: int, level_name: String)
signal affinity_changed(npc_id: String, val: int)
signal quest_updated(quest_id: String, state: String, step: int)
signal quest_toast(quest_id: String, text: String)
signal battle_started(payload: Dictionary)
signal battle_finished(result: Dictionary)      # result: {win, exp, money, drops, retreat...}
signal ending_reached(ending_id: String)
signal gathering_done(node_id: String, items: Dictionary)
signal trait_gained(trait_id: String)
signal wuxue_learned(wuxue_id: String)
signal wuxue_breakthrough(wuxue_id: String, level: int)
signal meridian_opened(meridian_id: String, dir: String)
signal faction_changed(faction_id: String, member: bool)
signal follower_joined(follower_id: String)
signal shop_refreshed(shop_id: String)
