extends RefCounted
## PixelArt —— 程序化像素美术：tile 16×16 / 角色 24×32 / 图标，全部运行时生成。
## 思路沿用兄弟项目 01game：确定性 PRNG 撒点造质感，零外部素材。

const TILE := 16

# 简易确定性 PRNG
static func _prng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

static func _mk_img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

# ---------- 地形色板 ----------
const TILE_COLORS := {
	"#": [Color("2b3140"), Color("1f2430")],   # 墙
	"T": [Color("1d3a26"), Color("16301f")],   # 树
	".": [Color("28331f"), Color("223018")],   # 地面
	",": [Color("2f4224"), Color("243a18")],   # 草丛
	"f": [Color("28331f"), Color("b8a0c9")],   # 花地
	"B": [Color("4a3a2a"), Color("5a4632")],   # 建筑
	"=": [Color("4a4238"), Color("555040")],   # 大路
	"~": [Color("1f3a4a"), Color("27506a")],   # 水
	"w": [Color("3a4a5f"), Color("556a80")],   # 井
	"b": [Color("4a3220"), Color("6a4a2a")],   # 船/码头
	"d": [Color("6a5a2a"), Color("c9a067")],   # 出口
	"+": [Color("28331f"), Color("c9a067")],   # 地面+金色标记
}

const WALKABLE := ".f,=Bwb+d"

static func is_walkable(ch: String) -> bool:
	return WALKABLE.contains(ch)

## 生成全部 tile 纹理
static func gen_tiles() -> Dictionary:
	var out := {}
	for ch in TILE_COLORS:
		var cols: Array = TILE_COLORS[ch]
		var img := _mk_img(TILE, TILE)
		var r := _prng(ch.hash() & 0x7fffffff)
		img.fill(cols[0])
		# 撒质感点
		for i in 26:
			var x := r.randi_range(0, TILE - 1)
			var y := r.randi_range(0, TILE - 1)
			img.set_pixel(x, y, cols[1])
		# 特殊元素
		match ch:
			"T":
				# 树干+树冠
				for y in range(9, 16):
					for x in range(7, 9):
						img.set_pixel(x, y, Color("4a3220"))
				for y in range(2, 10):
					var half := 6 - absi(y - 5)
					for x in range(8 - half, 8 + half):
						if x >= 0 and x < TILE:
							img.set_pixel(x, y, Color("2a5230") if (x + y) % 3 != 0 else Color("356840"))
			"#":
				for x in TILE:
					img.set_pixel(x, 0, Color("3a4254"))
			"~":
				for i in 5:
					var x := r.randi_range(1, TILE - 3)
					var y := r.randi_range(1, TILE - 2)
					img.set_pixel(x, y, Color("3a7a9a"))
					img.set_pixel(x + 1, y, Color("3a7a9a"))
			"=":
				for i in 8:
					var x := r.randi_range(0, TILE - 1)
					var y := r.randi_range(0, TILE - 1)
					img.set_pixel(x, y, Color("3f3a30"))
			"B":
				img.fill(Color("4a3a2a"))
				for y in range(2, 15):
					for x in range(2, 14):
						img.set_pixel(x, y, Color("5a4632") if (x * 7 + y * 13) % 11 != 0 else Color("4f3c2b"))
				for x in range(3, 13, 3):
					for y in range(4, 7):
						img.set_pixel(x, y, Color("c9a067"))
			"w":
				for y in range(4, 13):
					for x in range(4, 12):
						img.set_pixel(x, y, Color("1a2a3a"))
			"b":
				for x in range(1, 15):
					for y in range(8, 12):
						img.set_pixel(x, y, Color("5a4028"))
			"d":
				for i in 3:
					var y := 4 + i * 4
					for x in range(3, 13):
						img.set_pixel(x, y, Color("c9a067"))
		out[ch] = _tex(img)
	return out

# ---------- 角色 ----------
## 生成 24×32 小人（dir: "d"/"u"/"l"/"r"，frame 0/1），主色=门派/身份
static func gen_char(base_seed: int, main_col: Color, skin: Color = Color("d9b090")) -> Dictionary:
	var out := {}
	for dir in ["d", "u", "l", "r"]:
		for frame in 2:
			var img := _mk_img(24, 32)
			var r := _prng(base_seed + dir.hash() + frame)
			# 腿（走路交替）
			var leg_off := 1 if frame == 1 else 0
			img.fill(Color(0, 0, 0, 0))
			var leg_col := Color("2a2f3a")
			for x in range(9, 11):
				for y in range(24 + leg_off, 31):
					img.set_pixel(x, y, leg_col)
			for x in range(13, 15):
				for y in range(24 + (1 - leg_off), 31):
					img.set_pixel(x, y, leg_col)
			# 身
			for y in range(14, 25):
				for x in range(7, 17):
					img.set_pixel(x, y, main_col if (x + y) % 7 != 0 else main_col.darkened(0.15))
			# 腰带
			for x in range(7, 17):
				img.set_pixel(x, 21, Color("c9a067"))
			# 头
			for y in range(5, 13):
				for x in range(8, 16):
					if Vector2(x - 11.5, y - 9).length() < 4.2:
						img.set_pixel(x, y, skin)
			# 发/斗笠
			for y in range(4, 8):
				for x in range(7, 17):
					if Vector2(x - 11.5, (y - 7) * 1.4).length() < 4.6:
						img.set_pixel(x, y, Color("2a2530"))
			# 眼
			if dir == "d":
				img.set_pixel(10, 10, Color("1a1a1a"))
				img.set_pixel(13, 10, Color("1a1a1a"))
			elif dir == "l":
				img.set_pixel(9, 10, Color("1a1a1a"))
			elif dir == "r":
				img.set_pixel(14, 10, Color("1a1a1a"))
			# 武器剪影（简）
			if dir in ["l", "r"] and frame == 1:
				var wx := 4 if dir == "l" else 19
				for y in range(12, 24):
					img.set_pixel(wx, y, Color("8a94a8"))
			out[dir + str(frame)] = _tex(img)
	return out

## 战斗单位头像（20×20 圆头色块）
static func gen_face(seed_v: int, main_col: Color) -> ImageTexture:
	var img := _mk_img(20, 20)
	var r := _prng(seed_v)
	img.fill(Color(0, 0, 0, 0))
	for y in range(2, 18):
		for x in range(2, 18):
			if Vector2(x - 10, y - 10).length() < 8:
				img.set_pixel(x, y, main_col)
	for y in range(3, 9):
		for x in range(4, 16):
			if Vector2(x - 10, (y - 6) * 1.3).length() < 7:
				img.set_pixel(x, y, Color("2a2530"))
	img.set_pixel(7, 11, Color("1a1a1a"))
	img.set_pixel(12, 11, Color("1a1a1a"))
	return _tex(img)

## 标题画：雨夜山门剪影 240×120
static func gen_title_art() -> ImageTexture:
	var w := 240
	var h := 120
	var img := _mk_img(w, h)
	var r := _prng(777)
	# 夜空
	img.fill(Color("10141f"))
	# 月
	for y in range(10, 34):
		for x in range(180, 208):
			if Vector2(x - 194, y - 22).length() < 11:
				img.set_pixel(x, y, Color("d9d4c0"))
	for y in range(14, 30):
		for x in range(184, 202):
			if Vector2(x - 200, y - 20).length() < 9:
				img.set_pixel(x, y, Color("10141f"))
	# 远山
	for x in w:
		var yh := 78 - int(12.0 * sin(float(x) * 0.04) + 8.0 * sin(float(x) * 0.09))
		for y in range(yh, h):
			img.set_pixel(x, y, Color("161d2b"))
	# 近山与山门
	for x in w:
		var yh2 := 96 - int(16.0 * sin(float(x) * 0.07 + 2.0))
		for y in range(yh2, h):
			img.set_pixel(x, y, Color("0d1119"))
	# 牌坊
	for y in range(58, 110):
		for x in range(112, 128):
			if x in [112, 113, 126, 127] or y in [60, 61]:
				img.set_pixel(x, y, Color("0a0d14"))
	# 雨
	for i in 220:
		var x := r.randi_range(0, w - 1)
		var y := r.randi_range(0, h - 1)
		img.set_pixel(x, y, Color("4a5a70aa"))
		if y + 1 < h:
			img.set_pixel(x, y + 1, Color("3a4a6066"))
	return _tex(img)
