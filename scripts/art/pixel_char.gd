extends RefCounted
## PixelChar —— 程序化像素角色（16×24，4 向 × 4 帧）与水墨点绘头像。
## 确定性：同 seed 同输出。样式遵循 docs/06（墨线收边、顶亮立面暗）。

const W := 16
const H := 24
const INK := Color("221d17")
const SKIN := Color("d8b088")
const SKIN_DARK := Color("b08a60")

static var _cache: Dictionary = {}

## 生成一套角色精灵：{"south": [Tex x4], "north": ..., "west": ..., "east": ...}
## seed 决定发色/袍色；main_col 可强制袍色（随从/主角用）
static func gen_char_sprites(seed_v: int, main_col: Color = Color(0, 0, 0, 0)) -> Dictionary:
	var key := "c%d_%s" % [seed_v, main_col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var hair: Color = [Color("1d1a16"), Color("3a2c20"), Color("5a4632"), Color("2a2a30")][rng.randi() % 4]
	var robe: Color = main_col if main_col.a > 0 else [Color("3f545c"), Color("6b7c48"), Color("8a5a3a"), Color("5a4a6a"), Color("7d6a4d")][rng.randi() % 5]
	var robe_dark := robe.darkened(0.25)
	var sash: Color = Color("c9a067") if rng.randf() < 0.4 else robe_dark
	var out := {}
	for dir_name in ["south", "north", "west", "east"]:
		var frames: Array = []
		for f in 4:
			var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
			_draw_body(img, dir_name, f, hair, robe, robe_dark, sash, rng)
			frames.append(_tex(img))
		out[dir_name] = frames
	_cache[key] = out
	return out

static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

## 身体绘制：f=0 待机，1-3 行走（腿部交替+身体起伏 1px）
static func _draw_body(img: Image, dir_name: String, f: int, hair: Color, robe: Color, robe_dark: Color, sash: Color, rng: RandomNumberGenerator) -> void:
	var bob := (1 if f in [1, 3] else 0)
	var leg_a := (f == 1)
	var leg_b := (f == 3)
	# 腿（先画，被袍摆压上）
	var leg_col := Color("33302a")
	if dir_name != "north":
		pxset(img, 6, 20 + (1 if leg_a else 0), leg_col)
		pxset(img, 7, 20 + (1 if leg_a else 0), leg_col)
		pxset(img, 9, 20 + (1 if leg_b else 0), leg_col)
		pxset(img, 10, 20 + (1 if leg_b else 0), leg_col)
	else:
		for lx in [6, 7, 9, 10]:
			pxset(img, lx, 20, leg_col)
	# 袍身（3×7 立面：中间亮、两侧暗——顶亮立面暗）
	for yy in range(13 + bob, 21):
		for xx in range(5, 12):
			var col := robe if xx in [6, 7, 8, 9, 10] else robe_dark
			if yy == 21 - 1 and dir_name != "north":
				col = robe_dark  # 袍摆暗
			pxset(img, xx, yy, col)
	# 腰带
	for xx in range(5, 12):
		pxset(img, xx, 16 + bob, sash)
	# 头（发+脸）
	var head_y := 6 + bob
	for yy in range(head_y, head_y + 5):
		for xx in range(5, 12):
			pxset(img, xx, yy, hair)
	if dir_name == "north":
		pass   # 背面：全发
	else:
		# 脸区
		var face_l := 7
		var face_r := 9
		if dir_name == "west":
			face_l = 6
			face_r = 8
		elif dir_name == "east":
			face_l = 8
			face_r = 10
		for yy in range(head_y + 2, head_y + 5):
			for xx in range(face_l, face_r + 1):
				pxset(img, xx, yy, SKIN)
		# 眼（侧面单眼偏移）
		var eye_y := head_y + 3
		if dir_name == "south":
			pxset(img, 7, eye_y, INK)
			pxset(img, 9, eye_y, INK)
		elif dir_name == "west":
			pxset(img, 6, eye_y, INK)
		else:
			pxset(img, 10, eye_y, INK)
	# 墨线外轮廓（简化：上下左右包边）
	for xx in range(5, 12):
		pxset(img, xx, head_y - 1, INK)
		pxset(img, xx, 21, INK)
	# 武器（侧面：背后斜杠一柄）
	if dir_name in ["west", "east"]:
		var wx := (13 if dir_name == "east" else 2)
		for yy in range(10, 17):
			pxset(img, wx, yy, Color("7a6a50"))
		pxset(img, wx, 9, Color("c9a067"))

static func pxset(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, col)

## 水墨点绘头像（24×24）：发/脸/衣领 + 朱砂一点（唇或印记）——返回 Image 供烘焙
static func gen_face_img(seed_v: int, main_col: Color) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var S := 24
	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	var hair: Color = [Color("1d1a16"), Color("3a2c20"), Color("6a6a66")][rng.randi() % 3]
	var robe: Color = main_col if main_col.a > 0 else [Color("3f545c"), Color("6b7c48"), Color("8a5a3a")][rng.randi() % 3]
	# 底：宣纸
	for yy in S:
		for xx in S:
			var g := 0.90 + 0.06 * rng.randf()
			img.set_pixel(xx, yy, Color(g * 0.93, g * 0.88, g * 0.76))
	# 发
	for yy in range(3, 10):
		for xx in range(5, 19):
			if not (yy > 8 and xx in range(7, 17)):
				img.set_pixel(xx, yy, hair)
	# 脸
	for yy in range(8, 17):
		for xx in range(7, 17):
			var edge := (xx in [7, 16] or yy == 16)
			img.set_pixel(xx, yy, SKIN_DARK if edge else SKIN)
	# 眉眼（古龙式：眼是两条懒墨）
	for xx in range(8, 12):
		img.set_pixel(xx, 11, INK)
		img.set_pixel(xx, 13, INK)
		img.set_pixel(xx + 4, 11, INK)
		img.set_pixel(xx + 4, 13, INK)
	# 领口
	for xx in range(6, 18):
		img.set_pixel(xx, 18, robe)
		img.set_pixel(xx, 19, robe.darkened(0.3))
	# 朱砂一点
	img.set_pixel(rng.randi() % 6 + 9, 15, Color("b03a2e"))
	return img

static func gen_face(seed_v: int, main_col: Color) -> ImageTexture:
	var key := "f%d_%s" % [seed_v, main_col.to_html()]
	if _cache.has(key):
		return _cache.get(key)
	var t := ImageTexture.create_from_image(gen_face_img(seed_v, main_col))
	_cache[key] = t
	return t
