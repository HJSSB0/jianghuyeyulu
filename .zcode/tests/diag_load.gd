extends SceneTree
## 数据加载专项诊断
func _initialize() -> void:
	var GDB: Node = root.get_node("GameDB")
	print("-- before manual load_all --")
	print("wuxue = ", GDB.get("wuxue").size())
	print("file_exists wuxue.json: ", FileAccess.file_exists("res://data/wuxue.json"))
	GDB.load_all()
	print("-- after manual load_all --")
	for t in ["wuxue", "items", "npcs", "quests", "encounters", "factions", "formations", "meridians", "traits", "shops", "recipes", "enemies"]:
		print(t, " = ", GDB.get(t).size())
	print("maps = ", GDB.get("maps").size(), "  world nodes = ", GDB.get("world").get("nodes", {}).size())
	print("last_errors = ", GDB.get("last_errors").size())
	for e in GDB.get("last_errors"):
		print("  ERR: ", e)
	quit(0)
