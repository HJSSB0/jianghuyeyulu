extends RefCounted
## InkPaint —— 程序化水墨画：标题画、结局变体、大地图宣纸底、物品图标。
## 构图契约见 docs/06；意象锚点见 docs/05（雨·月·灯）。

const INK := Color("221d17")
const INK_SOFT := Color("4a4238")
const PAPER := Color("e9dfc6")
const PAPER_DARK := Color("d8cbaa")
const GOLD := Color("c9a067")
const CINNABAR := Color("b03a2e")
const NIGHT := Color("12100c")

static var _cache: Dictionary = {}

# ---------- 标题画（960×540） ----------

static func title_art() -> ImageTexture:
	if _cache.has("title"):
		return _cache.get("title")
	var W := 960
	var H := 540
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 20261106
	# 夜色纸底（雨夜的宣纸：偏暗的纸色 + 颗粒）
	for yy in H:
		for xx in W:
			var g := 0.30 + 0.05 * r.randf() + 0.10 * (1.0 - float(yy) / H)
			img.set_pixel(xx, yy, Color(g * 0.62, g * 0.58, g * 0.50))
	# 弯月（右上，留白之月）
	_crescent(img, 760, 96, 44, Color("e9dfc6"))
	# 三层远山（前深后淡，占下半）
	_mountains(img, W, H, 300, [Color("2c3336"), Color("3a4448"), Color("4a5558")])
	# 山门剪影（左侧中景：门柱+顶+灯笼光）
	_gate_silhouette(img, 150, 300, Color("1a1713"))
	# 水面线 + 孤舟 + 灯
	var water_y := 452
	for xx in W:
		img.set_pixel(xx, water_y, Color("161511"))
		if xx % 7 == 0:
			img.set_pixel(xx, water_y + 3 + (xx / 11) % 2, Color("26231d"))
	_boat(img, 600, water_y - 10)
	# 雨丝（细密斜线，全画幅）
	for i in 620:
		var rx := r.randi_range(0, W - 1)
		var ry := r.randi_range(0, H - 1)
		var ln := r.randi_range(4, 9)
		for l in ln:
			var px := rx + l
			var py := ry + l * 2
			if px < W and py < H:
				img.set_pixel(px, py, Color(0.10, 0.10, 0.09, 0.5))
	# 暗角（画外留黑）
	_vignette(img, W, H, 0.5)
	var t := ImageTexture.create_from_image(img)
	_cache["title"] = t
	return t

# ---------- 结局画（960×540，按结局 id） ----------

static func ending_art(kind: String) -> ImageTexture:
	var key := "end_" + kind
	if _cache.has(key):
		return _cache.get(key)
	var W := 960
	var H := 540
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind) % 100000
	var dawn: bool = kind == "world"
	for yy in H:
		for xx in W:
			var g := 0.34 + 0.05 * r.randf() + 0.16 * (1.0 - float(yy) / H)
			var c := Color(g * (0.66 if dawn else 0.60), g * (0.60 if dawn else 0.56), g * 0.50)
			img.set_pixel(xx, yy, c)
	if dawn:
		_crescent(img, 480, 110, 30, Color("e0d0a0"))
		_mountains(img, W, H, 330, [Color("4a4438"), Color("5c5546"), Color("6e6654")])
		_gate_silhouette(img, 420, 300, Color("241f18"))
		# 晨光金线
		for i in 40:
			var lx := r.randi_range(0, W - 1)
			var ly := r.randi_range(120, 360)
			img.set_pixel(lx, ly, Color(0.75, 0.65, 0.42, 0.6))
	elif kind == "dark":
		_crescent(img, 700, 100, 52, Color("c9c2b4"))
		_mountains(img, W, H, 320, [Color("23282e"), Color("2c333a"), Color("363e46")])
		# 月鉴倒影（竖向光柱）
		for yy in range(150, 470):
			for xx in range(688, 712):
				if (xx + yy) % 3 != 0:
					img.set_pixel(xx, yy, Color(0.55, 0.53, 0.48, 0.35))
	else:
		# 出世：村井炊烟
		_mountains(img, W, H, 330, [Color("39443c"), Color("485448"), Color("576456")])
		# 井台
		for yy in range(400, 452):
			for xx in range(440, 520):
				img.set_pixel(xx, yy, Color("6e6552") if yy > 430 else Color("8a7f68"))
		# 炊烟（摇曳竖线）
		for i in 24:
			var sx := 478 + (i % 5)
			var sy := 400 - i * 6 - r.randi_range(0, 3)
			if sy > 40:
				img.set_pixel(sx + int(sin(i * 0.7) * 6), sy, Color(0.72, 0.70, 0.62, 0.5))
		_vignette(img, W, H, 0.42)
		var t2 := ImageTexture.create_from_image(img)
		_cache[key] = t2
		return t2
	_boat(img, 300, 470)
	_vignette(img, W, H, 0.42)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

# ---------- 大地图宣纸底（960×540） ----------

static func world_map_base() -> ImageTexture:
	if _cache.has("worldmap"):
		return _cache.get("worldmap")
	var W := 960
	var H := 540
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 555
	for yy in H:
		for xx in W:
			var g := 0.86 + 0.07 * r.randf()
			img.set_pixel(xx, yy, Color(g * 0.93, g * 0.88, g * 0.75))
	# 墨色山脉走向（三组）
	_ink_ridge(img, 120, 150, 260, 60, r)
	_ink_ridge(img, 560, 110, 300, 70, r)
	_ink_ridge(img, 300, 330, 340, 50, r)
	# 水域（留白波光）
	for i in 3:
		var wx := 60 + i * 320
		for xx in range(wx, wx + 200):
			var wy := 470 - (xx % 9)
			img.set_pixel(xx, wy, Color("8fa3a8"))
			img.set_pixel(xx + 3, wy + 3, Color("a8b8ba"))
	# 边框：墨线双边 + 四角朱印点
	for xx in W:
		for b in [2, 3, 8]:
			img.set_pixel(xx, b, INK)
			img.set_pixel(xx, H - 1 - b, INK)
	for yy in H:
		for b in [2, 3, 8]:
			img.set_pixel(b, yy, INK)
			img.set_pixel(W - 1 - b, yy, INK)
	for c in [Vector2(14, 14), Vector2(W - 15, 14), Vector2(14, H - 15), Vector2(W - 15, H - 15)]:
		for dx in 3:
			for dy in 3:
				img.set_pixel(int(c.x) + dx - 1, int(c.y) + dy - 1, CINNABAR)
	var t := ImageTexture.create_from_image(img)
	_cache["worldmap"] = t
	return t

# ---------- 物品图标（16×16，按类别） ----------

## 对话框横卷（48×32 NinePatch 素材）：宣纸底+墨框+两端卷轴轴头
static func dialog_box_tex() -> ImageTexture:
	if _cache.has("dlgbox"):
		return _cache.get("dlgbox")
	var W := 48
	var H := 32
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 41
	for yy in H:
		for xx in W:
			var g := 0.88 + 0.06 * r.randf()
			img.set_pixel(xx, yy, Color(g * 0.93, g * 0.88, g * 0.76))
	for yy in H:
		for b in 2:
			img.set_pixel(6 + b, yy, INK)
			img.set_pixel(W - 7 - b, yy, INK)
	for xx in range(6, W - 6):
		img.set_pixel(xx, 1, INK)
		img.set_pixel(xx, H - 2, INK)
	# 两端卷轴轴头（深木+金盖）
	for xx in [0, 1, W - 2, W - 1]:
		for yy in range(2, H - 2):
			img.set_pixel(xx, yy, Color("5e4732"))
	for xx in [2, W - 3]:
		for yy in range(3, H - 3):
			img.set_pixel(xx, yy, GOLD)
	var t := ImageTexture.create_from_image(img)
	_cache["dlgbox"] = t
	return t

## 头像框（24×24）：透明心 + 墨环 + 描金内圈
static func portrait_frame_tex() -> ImageTexture:
	if _cache.has("ptframe"):
		return _cache.get("ptframe")
	var S := 24
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var cx := float(S) / 2.0
	for yy in S:
		for xx in S:
			var d := Vector2(xx - cx + 0.5, yy - cy_of(S) + 0.5).length()
			if d >= S / 2.0 - 1.5:
				img.set_pixel(xx, yy, INK)
			elif d >= S / 2.0 - 3.5:
				img.set_pixel(xx, yy, GOLD)
	var t := ImageTexture.create_from_image(img)
	_cache["ptframe"] = t
	return t

static func cy_of(s: int) -> float:
	return float(s) / 2.0

static func icon_tex(cat: String) -> ImageTexture:
	var key := "icon_" + cat
	if _cache.has(key):
		return _cache.get(key)
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	match cat:
		"剑", "刀", "武器":
			for i in 9:
				img.set_pixel(4 + i, 11 - i, Color("c9c9c9"))
				img.set_pixel(5 + i, 11 - i, Color("8a8a8a"))
			img.set_pixel(3, 12, GOLD)
			img.set_pixel(2, 13, GOLD)
			img.set_pixel(4, 13, Color("5e4732"))
			img.set_pixel(5, 14, Color("5e4732"))
		"丹", "药":
			for yy in range(6, 12):
				for xx in range(6, 11):
					var d := Vector2(xx - 8, (yy - 9) * 1.4).length()
					img.set_pixel(xx, yy, Color("b03a2e") if d < 2.6 else (INK if d < 3.2 else Color.TRANSPARENT))
		"书", "秘籍":
			for yy in range(3, 13):
				for xx in range(3, 13):
					img.set_pixel(xx, yy, Color("8a5a3a") if xx < 8 else Color("6e4630"))
			for yy in range(4, 12):
				img.set_pixel(8, yy, PAPER)
				img.set_pixel(10, yy, INK_SOFT)
		"材料", "矿":
			for i in 5:
				var px := 3 + (i * 5) % 9
				var py := 4 + (i * 7) % 8
				for yy in 3:
					for xx in 3:
						if Vector2(xx - 1, yy - 1).length() < 1.8:
							img.set_pixel(px + xx, py + yy, Color("9a8a70") if (xx + yy) % 2 == 0 else Color("7d6a4d"))
		"食物":
			for yy in range(7, 12):
				for xx in range(4, 12):
					img.set_pixel(xx, yy, Color("d8b088") if yy > 8 else Color("c9a067"))
		_:
			for yy in range(4, 12):
				for xx in range(4, 12):
					img.set_pixel(xx, yy, Color("8a8a80"))
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

# ---------- 画法基元 ----------

static func _crescent(img: Image, cx: int, cy: int, rad: int, col: Color) -> void:
	for yy in range(cy - rad, cy + rad):
		for xx in range(cx - rad, cx + rad):
			var d1 := Vector2(xx - cx, yy - cy).length()
			var d2 := Vector2(xx - cx - rad * 0.42, yy - cy - rad * 0.10).length()
			if d1 < rad and d2 > rad * 0.86:
				img.set_pixel(xx, yy, col)

static func _mountains(img: Image, W: int, H: int, base_y: int, cols: Array) -> void:
	for li in cols.size():
		var rr := RandomNumberGenerator.new()
		rr.seed = 700 + li * 13
		var ph := [rr.randf() * 6.28, rr.randf() * 6.28]
		var amp := 46 - li * 12
		var col: Color = cols[li]
		for xx in W:
			var yv := base_y - int((sin(xx * 0.012 + ph[0]) * 0.65 + sin(xx * 0.031 + ph[1]) * 0.35) * amp)
			for yy in range(maxi(0, yv), H):
				img.set_pixel(xx, yy, col)
			img.set_pixel(xx, maxi(0, yv), col.lightened(0.12))

static func _gate_silhouette(img: Image, cx: int, base_y: int, col: Color) -> void:
	var w := 190
	# 双柱
	for px in [cx - w / 2, cx + w / 2 - 22]:
		for yy in range(base_y - 120, base_y):
			for xx in range(px, px + 20):
				img.set_pixel(xx, yy, col)
	# 顶檐（两层出挑）
	for layer in 2:
		var ly := base_y - 120 - 14 - layer * 12
		var half := w / 2 + 14 + layer * 8
		for xx in range(cx - half, cx + half):
			img.set_pixel(xx, ly, col)
			img.set_pixel(xx, ly + 1, col)
		for yy in range(base_y - 148, base_y - 120):
			var t := float(base_y - 120 - yy) / 28.0
			var half2 := int(w * 0.5 * (0.3 + 0.7 * t))
			for xx in range(cx - half2, cx + half2):
				img.set_pixel(xx, yy, col)
	# 匾（留白一块）
	for yy in range(base_y - 108, base_y - 92):
		for xx in range(cx - 30, cx + 30):
			img.set_pixel(xx, yy, Color("0c0a08"))
	# 灯笼两点（暖光）
	for lx in [cx - w / 2 + 6, cx + w / 2 - 14]:
		for yy in range(base_y - 96, base_y - 82):
			for xx in range(lx, lx + 10):
				var d := Vector2(xx - lx - 5, (yy - (base_y - 89)) * 1.3).length()
				if d < 5:
					img.set_pixel(xx, yy, Color("c98a3a"))

static func _boat(img: Image, cx: int, water_y: int) -> void:
	for xx in range(cx - 26, cx + 26):
		var t := 1.0 - absf(float(xx - cx)) / 26.0
		var dy := int(t * 6.0)
		for yy in range(water_y - dy, water_y - dy + 4):
			img.set_pixel(xx, yy, Color("0c0a08"))
	# 船头灯
	img.set_pixel(cx + 20, water_y - 12, Color("c98a3a"))
	img.set_pixel(cx + 20, water_y - 11, Color("c98a3a"))

static func _ink_ridge(img: Image, ox: int, oy: int, w: int, amp: int, r: RandomNumberGenerator) -> void:
	var ph := r.randf() * 6.28
	for xx in w:
		var yv := oy - int((sin(xx * 0.02 + ph) * 0.7 + sin(xx * 0.05 + ph * 2.0) * 0.3) * amp)
		for yy in range(maxi(0, yv), maxi(0, yv) + 6):
			var px := ox + xx
			if px >= 0 and px < img.get_width() and yy >= 0 and yy < img.get_height():
				img.set_pixel(px, yy, Color(0.16, 0.14, 0.11, 0.55))
		if ox + xx >= 0 and ox + xx < img.get_width() and yv >= 0 and yv < img.get_height():
			img.set_pixel(ox + xx, yv, Color(0.10, 0.09, 0.07, 0.8))

static func _vignette(img: Image, W: int, H: int, strength: float) -> void:
	for yy in H:
		for xx in W:
			var edge := minf(minf(xx, W - 1 - xx) / float(W) * 2.0, minf(yy, H - 1 - yy) / float(H) * 2.0)
			if edge < 0.35:
				var k := (1.0 - edge / 0.35) * strength
				var c := img.get_pixel(xx, yy)
				img.set_pixel(xx, yy, c.lerp(NIGHT, k))
