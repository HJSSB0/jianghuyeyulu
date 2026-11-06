extends RefCounted
## ArtLib —— 程序化水墨美术枢纽（v0.4 大侠立志传式重制，零外部素材）。
## 场景 = pixel_world；角色 = pixel_char；画幅 = ink_paint；UI = ui_theme。
## 本文件保持视图层既有 API 形状（ground/prop/char/ui_bar/mood_art），实现全部换为新生成器。
## 一切确定性生成；缺失/超纲输入返回兜底，headless/CI 安全。

const PixelWorld := preload("res://scripts/art/pixel_world.gd")
const PixelChar := preload("res://scripts/art/pixel_char.gd")
const InkPaint := preload("res://scripts/art/ink_paint.gd")

const DIR8_ROWS := {
	"south": 0, "south-east": 1, "east": 2, "north-east": 3,
	"north": 4, "north-west": 5, "west": 6, "south-west": 7,
}
const DIR4_ROWS := {"down": 0, "left": 1, "right": 2, "up": 3}

# 字符 → 场景组件（pixel_world 中必须存在同名画法）
const PROP_TABLE := {
	"T": ["ginkgo_tree", "autumn_maple", "dense_bamboo", "bamboo_grove", "ferns", "mountain_rocks"],
	"B": ["mountain_cottage", "wood_shed", "tea_stall", "outdoor_kitchen", "mountain_shrine", "tea_pavilion"],
	"w": ["well"],
	"b": ["bamboo_bridge", "footbridge"],
	"d": ["mountain_gateway"],
	"f": ["herb_planter", "vegetable_planter", "clothesline", "firewood"],
	"+": ["stone_steps", "stepping_rocks"],
}

# 每图装饰（底边锚定；depth 可强制，前景 9999）
const MAP_DECOR := {
	"village": [
		{"prop": "distant_mountains", "cell": Vector2(14, 1)},
		{"prop": "cliff_mass", "cell": Vector2(2, 2)},
		{"prop": "lantern_post", "cell": Vector2(9, 8)},
	],
	"jiangzhou": [
		{"prop": "cliff_ridge", "cell": Vector2(3, 1)},
		{"prop": "distant_mountains", "cell": Vector2(20, 1)},
		{"prop": "horse_post", "cell": Vector2(14, 10)},
	],
}

# 角色主色（圣经人物 → 视觉身份）
const ACTOR_COL := {
	"swordsman": Color("3f545c"),   # 主角：青黛
	"bandit": Color("2a2a30"),      # 黑衣/山贼：玄色
	"traveler": Color(0, 0, 0, 0),  # 通用 NPC：哈希配色
}

static var _sprite_cache: Dictionary = {}

static func cell_rand(x: int, y: int, salt: int = 0) -> int:
	return PixelWorld.cell_rand(x, y, salt)

static func available() -> bool:
	return true   # 纯程序化，永远可用

# ---------- 地形（委托 pixel_world） ----------

static func ground_kind(ch: String) -> String:
	return PixelWorld.ground_kind(ch)

static func ground_tex(kind: String, x: int, y: int) -> ImageTexture:
	return PixelWorld.ground_tex(kind, x, y)

static func prop_for(ch: String, x: int, y: int) -> String:
	var candidates: Array = PROP_TABLE.get(ch, [])
	if candidates.is_empty():
		return ""
	return str(candidates[cell_rand(x, y, 31) % candidates.size()])

static func prop_tex(name: String) -> ImageTexture:
	return PixelWorld.prop_tex(name)

static func map_decor(map_id: String) -> Array:
	return MAP_DECOR.get(map_id, [])

# ---------- 角色（委托 pixel_char） ----------

## 8 方向名 → 4 向名（程序化角色只有 4 向）
static func dir8_to_dir4(dir8: String) -> String:
	match dir8:
		"north", "north-west", "north-east":
			return "up"
		"west":
			return "left"
		"east":
			return "right"
		_:
			return "down"

static func _actor_sprites(actor: String) -> Dictionary:
	if _sprite_cache.has(actor):
		return _sprite_cache.get(actor)
	var col: Color = ACTOR_COL.get(actor, Color(0, 0, 0, 0))
	var sprites: Dictionary = PixelChar.gen_char_sprites(hash(actor) & 0xffff, col)
	_sprite_cache[actor] = sprites
	return sprites

## 角色动作帧：anim ∈ {"idle","walk"}；frame 自动取模
static func char_frame(actor: String, anim: String, dir8: String, frame: int) -> ImageTexture:
	var sprites := _actor_sprites(actor)
	var dir4 := dir8_to_dir4(dir8)
	var frames: Array = sprites.get(dir4, [])
	if frames.is_empty():
		return null
	var f := 0 if anim == "idle" else 1 + posmod(frame, 3)
	return frames[f % frames.size()]

static func char_foot(_actor: String, _anim: String) -> Vector2:
	return Vector2(8, 23)   # 16×24 帧，脚底基线

static func anim_info(_actor: String, anim: String) -> Dictionary:
	return {"fps": 8.0 if anim == "walk" else 3.0, "frames": 4}

static func dir8_of(facing: Vector2i) -> String:
	if facing == Vector2i(0, 1):
		return "south"
	if facing == Vector2i(1, 1):
		return "south-east"
	if facing == Vector2i(1, 0):
		return "east"
	if facing == Vector2i(1, -1):
		return "north-east"
	if facing == Vector2i(0, -1):
		return "north"
	if facing == Vector2i(-1, -1):
		return "north-west"
	if facing == Vector2i(-1, 0):
		return "west"
	return "south-west"

static func dir4_of(facing: Vector2i) -> String:
	if absi(facing.x) >= absi(facing.y):
		if facing.x > 0:
			return "right"
		if facing.x < 0:
			return "left"
	if facing.y < 0:
		return "up"
	return "down"

## NPC 帧（通用村民；dir4 ∈ down/left/right/up）
static func traveler_frame(dir4: String, frame: int) -> ImageTexture:
	var sprites := _actor_sprites("traveler")
	var frames: Array = sprites.get(dir4, [])
	if frames.is_empty():
		return null
	return frames[posmod(frame, frames.size())]

# ---------- UI 纹理（程序化） ----------

static func ui_bar(kind: String) -> ImageTexture:
	var col := Color("b03a2e") if kind == "hp" else (Color("3f545c") if kind == "mp" else Color("c9803a"))
	var img := Image.create_empty(46, 4, false, Image.FORMAT_RGBA8)
	for yy in 4:
		for xx in 46:
			var t := float(xx) / 46.0
			img.set_pixel(xx, yy, col.lightened(0.15 * (1.0 - t)))
	return ImageTexture.create_from_image(img)

static func ui_bar_frame() -> ImageTexture:
	var img := Image.create_empty(48, 8, false, Image.FORMAT_RGBA8)
	for yy in 8:
		for xx in 48:
			var edge := xx < 1 or yy < 1 or xx > 46 or yy > 6
			img.set_pixel(xx, yy, Color("221d17") if edge else Color("e9dfc6"))
	return ImageTexture.create_from_image(img)

static func ui_dialog_box() -> ImageTexture:
	return InkPaint.dialog_box_tex()

static func ui_portrait_frame() -> ImageTexture:
	return InkPaint.portrait_frame_tex()

## NPC 水墨头像（自带墨环框），role 提供袍色语义
static func npc_face(npc_id: String) -> ImageTexture:
	var n: Dictionary = GameDB.get_npc(npc_id)
	var role: String = n.get("role", "闲人")
	var col: Color = {"任务": Color("3f545c"), "随从": Color("5a4a6a"), "杂货": Color("8a6a3a"), "药铺": Color("4a6a4a"),
		"武器": Color("7a4632"), "酒馆": Color("6a5230"), "门派": Color("33505c"), "黑市": Color("2a2a30"), "奇遇": Color("8a5a2a")}.get(role, Color("6a5a48"))
	var img: Image = PixelChar.gen_face_img(hash(npc_id) & 0xffff, col)
	var S := 24
	var cx := float(S) / 2.0
	for yy in S:
		for xx in S:
			var d := Vector2(xx - cx + 0.5, yy - cx + 0.5).length()
			if d >= S / 2.0 - 1.5:
				img.set_pixel(xx, yy, Color("221d17"))
			elif d >= S / 2.0 - 3.0:
				img.set_pixel(xx, yy, Color("c9a067"))
	return ImageTexture.create_from_image(img)

# ---------- 画幅（委托 ink_paint） ----------

static func mood_art(name: String) -> ImageTexture:
	# 兼容旧调用名：标题/结局 → 新水墨画
	if name == "07_immortal_gate" or name == "title":
		return InkPaint.title_art()
	if name == "22_peach_blossom_stream":
		return InkPaint.ending_art("world")
	if name == "ending_world":
		return InkPaint.ending_art("world")
	if name == "ending_hidden":
		return InkPaint.ending_art("hidden")
	if name == "ending_dark":
		return InkPaint.ending_art("dark")
	if name == "worldmap":
		return InkPaint.world_map_base()
	return InkPaint.title_art()

static func title_art() -> ImageTexture:
	return InkPaint.title_art()

static func ending_art(kind: String) -> ImageTexture:
	return InkPaint.ending_art(kind)

static func world_map_base() -> ImageTexture:
	return InkPaint.world_map_base()

static func icon_tex(cat: String) -> ImageTexture:
	return InkPaint.icon_tex(cat)
