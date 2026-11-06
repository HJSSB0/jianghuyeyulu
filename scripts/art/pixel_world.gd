extends RefCounted
## PixelWorld —— 32px 斜45°俯视程序化 tile 集与场景组件（docs/06 规范）。
## 一切确定性：同坐标同输出。顶面亮、立面暗、墨线收边。

const T := 32
const INK := Color("221d17")
const PAPER := Color("e9dfc6")
const GOLD := Color("c9a067")
const CINNABAR := Color("b03a2e")

static var _tile_cache: Dictionary = {}
static var _prop_cache: Dictionary = {}

static func cell_rand(x: int, y: int, salt: int = 0) -> int:
	return absi(int(x) * 73856093 ^ int(y) * 19349663 ^ salt * 83492791)

# ---------- 地形 tile ----------

## 地形字符 → 地面材质名（与 town_view 的字符集对应）
static func ground_kind(ch: String) -> String:
	match ch:
		"=", "+":
			return "slab"
		"~":
			return "water"
		"#":
			return "stone"
		"B":
			return "earth"
		_:
			return "grass"

static func ground_tex(kind: String, x: int, y: int) -> ImageTexture:
	var key := "%s_%d_%d" % [kind, x, y]
	if _tile_cache.has(key):
		return _tile_cache.get(key)
	var img := Image.create_empty(T, T, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = cell_rand(x, y, 17)
	match kind:
		"grass":
			_fill(img, Color("6b7c48"))
			for i in 26:
				_px(img, r, Color("49582f"))
			for i in 7:
				_blade(img, r)
		"slab":
			_fill(img, Color("9a8f78"))
			for i in 18:
				_px(img, r, Color("837a66"))
			# 石板缝（两横一竖错缝）
			for xx in T:
				img.set_pixel(xx, 10, Color("6e6552"))
				img.set_pixel(xx, 24, Color("6e6552"))
			img.set_pixel(16, 0, Color("6e6552"))
			img.set_pixel(16, 10, Color("6e6552"))
			img.set_pixel(8, 24, Color("6e6552"))
		"water":
			_fill(img, Color("4a6a72"))
			for i in 10:
				var wy := r.randi_range(2, T - 3)
				var wx := r.randi_range(0, T - 10)
				for l in r.randi_range(4, 8):
					img.set_pixel((wx + l) % T, wy, Color("37525a"))
			for i in 4:
				_px(img, r, Color("7a9aa0"))
		"stone":
			_fill(img, Color("7d6a4d"))
			for i in 20:
				_px(img, r, Color("6a5a42"))
			# 山石块面 + 墨缝
			for yy in [8, 18, 28]:
				for xx in T:
					img.set_pixel(xx, yy, INK)
			for xx in [12, 24]:
				for yy in range(0, 8):
					img.set_pixel(xx, yy, INK)
				for yy in range(18, 28):
					img.set_pixel(xx, yy, INK)
			for i in 8:
				_px(img, r, Color("9a8a70"))
		"earth":
			_fill(img, Color("a58a62"))
			for i in 22:
				_px(img, r, Color("8f7752"))
			for i in 6:
				_px(img, r, Color("b89a6e"))
		"plank":
			_fill(img, Color("8a6a48"))
			for yy in [7, 15, 23, 31]:
				for xx in T:
					img.set_pixel(xx, yy, Color("5e4732"))
			for i in 10:
				_px(img, r, Color("75583c"))
		_:
			_fill(img, Color("6b7c48"))
	_tex_cache(key, img)
	return _tile_cache.get(key)

static func _tex_cache(key: String, img: Image) -> void:
	_tile_cache[key] = ImageTexture.create_from_image(img)

# ---------- 场景组件（多格，底边中心锚定） ----------

static func prop_tex(name: String) -> ImageTexture:
	if _prop_cache.has(name):
		return _prop_cache.get(name)
	var img := _paint_prop(name)
	var t: ImageTexture = null
	if img != null:
		t = ImageTexture.create_from_image(img)
	_prop_cache[name] = t
	return t

static func _paint_prop(name: String) -> Image:
	var r := RandomNumberGenerator.new()
	r.seed = hash(name)
	match name:
		"dense_bamboo":
			return _bamboo(64, 72, r, true)
		"bamboo_grove":
			return _bamboo(96, 80, r, false)
		"ginkgo_tree":
			return _round_tree(80, 88, r, Color("6b7c48"))
		"autumn_maple":
			return _round_tree(80, 88, r, Color("a8623a"))
		"ferns":
			return _bush(48, 40, r)
		"mountain_rocks":
			return _rocks(64, 48, r)
		"mountain_cottage":
			return _house(96, 88, r, true)
		"wood_shed":
			return _house(80, 64, r, false)
		"tea_stall":
			return _stall(80, 72, r)
		"outdoor_kitchen":
			return _kitchen(80, 72, r)
		"mountain_shrine":
			return _shrine(64, 80, r)
		"tea_pavilion":
			return _pavilion(96, 80, r)
		"well":
			return _well(32, 40)
		"bamboo_bridge", "footbridge":
			return _bridge(64, 40)
		"mountain_gateway":
			return _gateway(96, 96, r)
		"herb_planter", "vegetable_planter":
			return _planter(48, 40, r)
		"clothesline":
			return _clothesline(64, 40, r)
		"firewood":
			return _firewood(48, 32, r)
		"stone_steps", "stepping_rocks":
			return _steps(64, 32, r)
		"lantern_post":
			return _lantern(16, 48)
		"horse_post":
			return _horse_post(32, 48, r)
		"distant_mountains":
			return _far_mountains(288, 96, r)
		"cliff_mass", "cliff_ridge":
			return _cliff(160, 96, r)
		_:
			return _bush(32, 32, r)

# ---------- 组件画法 ----------

static func _house(w: int, h: int, r: RandomNumberGenerator, big: bool) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var roof_h := int(h * 0.42)
	var body_top := roof_h
	# 屋顶：顶面亮纹 + 屋脊墨线 + 挑檐
	for yy in range(2, roof_h):
		var t := float(yy - 2) / float(roof_h - 2)
		var half := int(w * 0.5 * (0.30 + 0.70 * t))
		for xx in range(w / 2 - half, w / 2 + half):
			var c := Color("4a4440") if yy % 4 < 2 else Color("3a3634")
			img.set_pixel(xx, yy, c)
	for xx in range(w / 2 - int(w * 0.14), w / 2 + int(w * 0.14)):
		img.set_pixel(xx, 2, INK)
	# 檐口墨线（出挑 2px）
	for xx in range(w / 2 - int(w * 0.5) - 2, w / 2 + int(w * 0.5) + 2):
		var ex := clampi(xx, 0, w - 1)
		img.set_pixel(ex, roof_h - 1, INK)
	# 墙立面（暗木构）
	for yy in range(body_top, h - 4):
		for xx in range(int(w * 0.18), int(w * 0.82)):
			img.set_pixel(xx, yy, Color("8a6a48") if (xx + yy) % 7 != 0 else Color("75583c"))
	# 门（墨框内暖光）与窗（点金）
	var door_w := 10
	var dx := w / 2 - door_w / 2
	for yy in range(h - 4 - 18, h - 4):
		for xx in range(dx, dx + door_w):
			img.set_pixel(xx, yy, Color("2a2018"))
	for xx in range(dx + 2, dx + door_w - 2):
		for yy in range(h - 4 - 14, h - 4 - 4):
			img.set_pixel(xx, yy, Color("c98a3a"))
	var wx1 := int(w * 0.28)
	var wx2 := int(w * 0.68)
	for yy in range(body_top + 6, body_top + 14):
		img.set_pixel(wx1, yy, GOLD)
		img.set_pixel(wx2, yy, GOLD)
	# 台基
	for xx in range(int(w * 0.14), int(w * 0.86)):
		for yy in range(h - 4, h):
			img.set_pixel(xx, yy, Color("9a8f78"))
	for xx in range(int(w * 0.14), int(w * 0.86)):
		img.set_pixel(xx, h - 4, INK)
	return img

static func _round_tree(w: int, h: int, r: RandomNumberGenerator, leaf: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var trunk_x := w / 2
	for yy in range(h - 20, h):
		for xx in range(trunk_x - 3, trunk_x + 3):
			img.set_pixel(xx, yy, Color("5e4732") if xx == trunk_x - 3 or xx == trunk_x + 2 else Color("75583c"))
	for xx in range(trunk_x - 3, trunk_x + 3):
		img.set_pixel(xx, h - 20, INK)
	var cx := w / 2
	var cy := int(h * 0.34)
	var rad := int(w * 0.42)
	for yy in range(maxi(0, cy - rad), mini(h, cy + rad)):
		for xx in range(maxi(0, cx - rad), mini(w, cx + rad)):
			var d := Vector2(xx - cx, (yy - cy) * 1.25).length()
			if d < rad:
				var edge := d > rad - 2.0
				var c := leaf.darkened(0.35) if (xx + yy) % 5 == 0 else leaf
				img.set_pixel(xx, yy, leaf.darkened(0.55) if edge else c)
	for i in 14:
		var px := r.randi_range(cx - rad + 3, cx + rad - 3)
		var py := r.randi_range(cy - rad + 3, cy + rad - 3)
		if Vector2(px - cx, (py - cy) * 1.25).length() < rad - 3:
			img.set_pixel(px, py, leaf.darkened(0.4))
	return img

static func _bamboo(w: int, h: int, r: RandomNumberGenerator, dense: bool) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var n := 7 if dense else 5
	for i in n:
		var bx := 4 + i * (w - 8) / n + r.randi_range(-2, 2)
		var top := r.randi_range(2, 8)
		for yy in range(top, h):
			img.set_pixel(bx, yy, Color("5e7a3a") if yy % 5 != 0 else Color("46622c"))
		# 竹节
		for yy in range(top + 4, h, 7):
			img.set_pixel(bx, yy, INK)
		# 叶
		for l in 5:
			var ly := top + r.randi_range(0, 10)
			var lx := bx + r.randi_range(-5, 5)
			img.set_pixel(clampi(lx, 0, w - 1), clampi(ly, 0, h - 1), Color("6b7c48"))
	return img

static func _bush(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var cx := w / 2
	var cy := int(h * 0.45)
	for yy in range(h):
		for xx in range(w):
			var d := Vector2(xx - cx, (yy - cy) * 1.6).length()
			if d < w * 0.42:
				img.set_pixel(xx, yy, INK if d > w * 0.42 - 2 else (Color("49582f") if (xx * yy) % 4 == 0 else Color("6b7c48")))
	return img

static func _rocks(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for k in 3:
		var rx := 4 + k * (w - 12) / 3
		var ry := h - 14 - (k % 2) * 8
		var rw := 14 + (k % 3) * 4
		var rh := 12 + (k % 2) * 6
		for yy in range(ry, ry + rh):
			for xx in range(rx, rx + rw):
				var top := yy < ry + rh / 3
				img.set_pixel(xx, yy, Color("9a8a70") if top else Color("7d6a4d"))
		for xx in range(rx, rx + rw):
			img.set_pixel(xx, ry, INK)
			img.set_pixel(xx, ry + rh - 1, INK)
	return img

static func _stall(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 布篷（暖色条纹）
	for yy in range(2, 16):
		for xx in range(2, w - 2):
			img.set_pixel(xx, yy, Color("b03a2e") if (xx / 6) % 2 == 0 else Color("e0d8c0"))
	for xx in range(2, w - 2):
		img.set_pixel(xx, 2, INK)
		img.set_pixel(xx, 15, INK)
	# 摊台
	for yy in range(28, h - 4):
		for xx in range(6, w - 6):
			img.set_pixel(xx, yy, Color("8a6a48"))
	for xx in range(6, w - 6):
		img.set_pixel(xx, 28, INK)
	# 货物点
	for i in 6:
		img.set_pixel(10 + i * 9, 26, Color("c9a067") if i % 2 == 0 else Color("7ab86a"))
	# 柱
	for xx in [4, w - 5]:
		for yy in range(16, h - 4):
			img.set_pixel(xx, yy, Color("5e4732"))
	return img

static func _kitchen(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 棚顶
	for yy in range(2, 14):
		for xx in range(2, w - 2):
			img.set_pixel(xx, yy, Color("4a4440") if yy % 4 < 2 else Color("3a3634"))
	for xx in range(2, w - 2):
		img.set_pixel(xx, 13, INK)
	# 灶台
	for yy in range(26, h - 4):
		for xx in range(8, w - 8):
			img.set_pixel(xx, yy, Color("7d6a4d"))
	for xx in range(8, w - 8):
		img.set_pixel(xx, 26, INK)
	# 大锅（墨圈）
	for yy in range(18, 26):
		for xx in range(w / 2 - 10, w / 2 + 10):
			var d := Vector2(xx - w / 2.0, (yy - 21) * 1.6).length()
			if d < 10:
				img.set_pixel(xx, yy, Color("33302a"))
	# 火光
	for xx in range(w / 2 - 4, w / 2 + 4):
		img.set_pixel(xx, h - 8, Color("c96a2a"))
	return img

static func _shrine(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 小庙：顶 + 拱门
	for yy in range(2, 22):
		var t := float(yy - 2) / 20.0
		var half := int(w * 0.5 * (0.2 + 0.8 * t))
		for xx in range(w / 2 - half, w / 2 + half):
			img.set_pixel(xx, yy, Color("4a4440") if yy % 4 < 2 else Color("3a3634"))
	for xx in range(w / 2 - int(w * 0.5), w / 2 + int(w * 0.5)):
		img.set_pixel(xx, 21, INK)
	for yy in range(22, h - 4):
		for xx in range(w / 2 - 12, w / 2 + 12):
			img.set_pixel(xx, yy, Color("9a8a70"))
	var dw := 8
	for yy in range(h - 4 - 16, h - 4):
		for xx in range(w / 2 - dw / 2, w / 2 + dw / 2):
			img.set_pixel(xx, yy, Color("2a2018"))
	for xx in range(w / 2 - 12, w / 2 + 12):
		img.set_pixel(xx, h - 4, INK)
	return img

static func _pavilion(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 攒尖顶
	for yy in range(2, 20):
		var t := float(yy - 2) / 18.0
		var half := int(w * 0.5 * (0.12 + 0.88 * t))
		for xx in range(w / 2 - half, w / 2 + half):
			img.set_pixel(xx, yy, Color("3f545c") if yy % 4 < 2 else Color("33454c"))
	for xx in range(w / 2 - int(w * 0.5) - 2, w / 2 + int(w * 0.5) + 2):
		img.set_pixel(clampi(xx, 0, w - 1), 19, INK)
	# 四柱
	for xx in [int(w * 0.22), int(w * 0.78)]:
		for yy in range(20, h - 4):
			img.set_pixel(xx, yy, Color("8a6a48"))
	# 栏杆
	for yy in range(h - 12, h - 4):
		for xx in range(int(w * 0.12), int(w * 0.88)):
			img.set_pixel(xx, yy, Color("75583c") if yy % 3 == 0 else Color("00000000"))
	for xx in range(int(w * 0.12), int(w * 0.88)):
		img.set_pixel(xx, h - 12, Color("8a6a48"))
		img.set_pixel(xx, h - 5, INK)
	return img

static func _well(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 石台
	for yy in range(h - 14, h):
		for xx in range(2, w - 2):
			img.set_pixel(xx, yy, Color("9a8a70") if yy > h - 10 else Color("7d6a4d"))
	for yy in range(h - 14, h):
		img.set_pixel(2, yy, INK)
		img.set_pixel(w - 3, yy, INK)
	# 木架 + 辘轳
	for xx in [4, w - 5]:
		for yy in range(6, h - 12):
			img.set_pixel(xx, yy, Color("75583c"))
	for xx in range(4, w - 4):
		img.set_pixel(xx, 6, Color("5e4732"))
	for yy in range(8, 14):
		img.set_pixel(w / 2, yy, Color("33302a"))
	return img

static func _bridge(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 拱背桥面
	for xx in range(w):
		var t := float(xx) / (w - 1)
		var arch := int(sin(t * PI) * 10.0)
		for yy in range(h - 8 - arch, h - arch):
			img.set_pixel(xx, yy, Color("8a6a48"))
		img.set_pixel(xx, h - 8 - arch, INK)
		for yy in range(h - 8 - arch, h - arch, 4):
			img.set_pixel(xx, yy, Color("5e4732"))
	return img

static func _gateway(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 双柱 + 顶檐 + 匾
	for px in [8, w - 12]:
		for yy in range(20, h):
			for xx in range(px, px + 5):
				img.set_pixel(xx, yy, Color("8a6a48"))
			img.set_pixel(px, yy, INK)
	for yy in range(4, 18):
		var t := float(yy - 4) / 14.0
		var half := int(w * 0.5 * (0.4 + 0.6 * t))
		for xx in range(w / 2 - half, w / 2 + half):
			img.set_pixel(xx, yy, Color("4a4440") if yy % 4 < 2 else Color("3a3634"))
	for xx in range(w / 2 - int(w * 0.5) - 1, w / 2 + int(w * 0.5) + 1):
		img.set_pixel(clampi(xx, 0, w - 1), 17, INK)
	# 匾额（墨底金字）
	for yy in range(22, 32):
		for xx in range(w / 2 - 16, w / 2 + 16):
			img.set_pixel(xx, yy, Color("2a2018"))
	for xx in range(w / 2 - 13, w / 2 + 13, 3):
		img.set_pixel(xx, 26, GOLD)
	# 灯笼一对
	for lx in [w / 2 - 22, w / 2 + 18]:
		for yy in range(34, 44):
			for xx in range(lx, lx + 8):
				var d := Vector2(xx - lx - 4, (yy - 39) * 1.3).length()
				if d < 4:
					img.set_pixel(xx, yy, Color("c96a5a"))
		img.set_pixel(lx + 3, 33, INK)
	return img

static func _planter(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for yy in range(h - 10, h):
		for xx in range(2, w - 2):
			img.set_pixel(xx, yy, Color("75583c"))
	for xx in range(2, w - 2):
		img.set_pixel(xx, h - 10, INK)
	for i in 5:
		var px := 5 + i * 8
		for yy in range(h - 18, h - 10):
			img.set_pixel(px, yy, Color("49582f"))
			img.set_pixel(px + 2, yy + 2, Color("6b7c48"))
	return img

static func _clothesline(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for px in [2, w - 4]:
		for yy in range(4, h):
			img.set_pixel(px, yy, Color("75583c"))
	for xx in range(2, w - 2):
		img.set_pixel(xx, 6, Color("33302a"))
	for i in 3:
		var cx := 10 + i * 18
		for yy in range(8, 26):
			for xx in range(cx, cx + 12):
				img.set_pixel(xx, yy, [Color("7a9aa0"), Color("b08a60"), Color("8a9aa0")][i])
	for i in 3:
		var cx := 10 + i * 18
		for xx in range(cx, cx + 12):
			img.set_pixel(xx, 26, INK)
	return img

static func _firewood(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for row in 3:
		for i in 5:
			var lx := 3 + i * 8 + (row % 2) * 3
			var ly := h - 8 - row * 7
			for yy in range(ly, ly + 6):
				for xx in range(lx, lx + 7):
					img.set_pixel(xx, yy, Color("75583c"))
			for yy in range(ly, ly + 6):
				img.set_pixel(lx, yy, Color("4e3c2a"))
				img.set_pixel(lx + 6, yy, Color("a58a62"))
	return img

static func _steps(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for s in 3:
		var yy := h - 8 - s * 8
		for xx in range(4 + s * 4, w - 4 - s * 4):
			for dy in 7:
				img.set_pixel(xx, yy + dy, Color("9a8a70") if dy == 0 else Color("7d6a4d"))
			img.set_pixel(xx, yy, INK)
	return img

static func _lantern(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for yy in range(10, h):
		img.set_pixel(w / 2, yy, Color("5e4732"))
	for yy in range(6, 8):
		img.set_pixel(w / 2, yy, INK)
	for yy in range(8, 20):
		for xx in range(2, w - 2):
			var d := Vector2(xx - w / 2.0 + 0.5, (yy - 14) * 1.4).length()
			if d < 6:
				img.set_pixel(xx, yy, Color("c96a5a") if d < 4.4 else INK)
	for xx in range(3, w - 3):
		img.set_pixel(xx, 12, Color("c98a3a"))
	return img

static func _horse_post(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for yy in range(8, h):
		for xx in range(w / 2 - 3, w / 2 + 3):
			img.set_pixel(xx, yy, Color("75583c"))
	for xx in range(w / 2 - 3, w / 2 + 3):
		img.set_pixel(xx, 8, INK)
	for yy in range(12, 15):
		for xx in range(2, w - 2):
			img.set_pixel(xx, yy, Color("5e4732"))
	img.set_pixel(w / 2, 16, Color("b03a2e"))
	return img

static func _far_mountains(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 三层墨色远山（前深后淡）
	var layers := [Color("3a4a52"), Color("55666e"), Color("75858c")]
	for li in layers.size():
		var base_y := h - 18 - li * 22
		var amp := 26 - li * 6
		var rr := RandomNumberGenerator.new()
		rr.seed = 31337 + li
		var ph := [rr.randf() * 6.28, rr.randf() * 6.28]
		for xx in w:
			var yv := base_y - int((sin(xx * 0.02 + ph[0]) * 0.6 + sin(xx * 0.045 + ph[1]) * 0.4) * amp)
			for yy in range(maxi(0, yv), mini(yv, h)):
				img.set_pixel(xx, yy, layers[li])
			if yv >= 0 and yv < h:
				img.set_pixel(xx, yv, Color("2a3338"))
	return img

static func _cliff(w: int, h: int, r: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 崖壁：横向层理 + 竖向节理
	for yy in range(h):
		for xx in range(w):
			var top := yy < h * 0.25
			var c := Color("9a8a70") if top else (Color("7d6a4d") if (xx / 5 + yy / 4) % 2 == 0 else Color("6a5a42"))
			img.set_pixel(xx, yy, c)
	for yy in range(h):
		img.set_pixel(0, yy, INK)
		img.set_pixel(w - 1, yy, INK)
	for xx in range(w):
		img.set_pixel(xx, 0, INK)
	for i in 6:
		var vx := r.randi_range(6, w - 6)
		var vy := r.randi_range(4, h - 10)
		var vlen := r.randi_range(6, 16)
		for yy in range(vy, mini(vy + vlen, h)):
			img.set_pixel(vx, yy, INK)
	return img

# ---------- 基础笔触 ----------

static func _fill(img: Image, col: Color) -> void:
	for yy in img.get_height():
		for xx in img.get_width():
			img.set_pixel(xx, yy, col)

static func _px(img: Image, r: RandomNumberGenerator, col: Color) -> void:
	img.set_pixel(r.randi_range(0, img.get_width() - 1), r.randi_range(0, img.get_height() - 1), col)

static func _blade(img: Image, r: RandomNumberGenerator) -> void:
	var bx := r.randi_range(1, img.get_width() - 2)
	var by := r.randi_range(4, img.get_height() - 2)
	img.set_pixel(bx, by, Color("49582f"))
	img.set_pixel(bx + r.randi_range(-1, 1), by - 1, Color("49582f"))
