extends RefCounted
## Pathfinding —— 网格 A* 寻路（纯逻辑，headless 可测）。
## 烟雨式点击移动的路径引擎：find_path 返回不含起点的逐格路径，不可达返回空数组。
## 对角步要求两侧正交格均可走（与 town_view._begin_step 防穿角规则一致）。

static func find_path(w: int, h: int, walkable: Callable, start: Vector2i, goal: Vector2i, allow_diag := false) -> Array:
	if start == goal:
		return []
	if _oob(goal, w, h) or not walkable.call(goal.x, goal.y):
		return []
	var open: Array = [start]
	var g := {start: 0}
	var f := {start: _heur(start, goal)}
	var came := {}
	var closed := {}
	while open.size() > 0:
		# 地图 ≤ 540 格，线性扫描取 f 最小足够
		var bi := 0
		for i in open.size():
			if int(f.get(open[i], 1 << 30)) < int(f.get(open[bi], 1 << 30)):
				bi = i
		var cur: Vector2i = open[bi]
		if cur == goal:
			return _rebuild(came, cur)
		open.remove_at(bi)
		closed[cur] = true
		for nb in _neighbors(cur, w, h, walkable, allow_diag):
			if closed.has(nb):
				continue
			var ng: int = int(g[cur]) + 1
			if not g.has(nb) or ng < int(g[nb]):
				g[nb] = ng
				f[nb] = ng + _heur(nb, goal)
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return []

static func _neighbors(c: Vector2i, w: int, h: int, walkable: Callable, allow_diag: bool) -> Array:
	var out: Array = []
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = c + d
		if not _oob(n, w, h) and walkable.call(n.x, n.y):
			out.append(n)
	if allow_diag:
		for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var n: Vector2i = c + d
			if _oob(n, w, h) or not walkable.call(n.x, n.y):
				continue
			var side1: Vector2i = Vector2i(c.x + d.x, c.y)
			var side2: Vector2i = Vector2i(c.x, c.y + d.y)
			if walkable.call(side1.x, side1.y) and walkable.call(side2.x, side2.y):
				out.append(n)
	return out

static func _oob(c: Vector2i, w: int, h: int) -> bool:
	return c.x < 0 or c.y < 0 or c.x >= w or c.y >= h

static func _heur(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _rebuild(came: Dictionary, cur: Vector2i) -> Array:
	var path: Array = [cur]
	while came.has(cur):
		cur = came[cur]
		path.push_front(cur)
	path.pop_front()   # 去掉起点
	return path
