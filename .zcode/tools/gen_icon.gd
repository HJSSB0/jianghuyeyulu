extends SceneTree
## 生成 iOS 应用图标（1024×1024）：v0.6 水墨标题画居中方形裁切 + 最近邻放大
## 运行：Godot --headless --path . --script .zcode/tools/gen_icon.gd

const OUT := "res://assets/icons/icon_1024.png"

func _initialize() -> void:
	var InkPaint := load("res://scripts/art/ink_paint.gd")
	var tex: ImageTexture = InkPaint.title_art()
	var img: Image = tex.get_image()
	var side := mini(img.get_width(), img.get_height())
	var src := img.get_region(Rect2i((img.get_width() - side) / 2, 0, side, side))
	src.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons"))
	var err := src.save_png(ProjectSettings.globalize_path(OUT))
	print("ICON saved ", OUT, " 1024x1024 err=", err)
	quit(0 if err == OK else 1)
