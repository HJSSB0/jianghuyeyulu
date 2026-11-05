extends SceneTree
## 生成 iOS 应用图标（1024×1024）：复用程序化标题画右半（月亮+山峦），最近邻放大保像素风。
## 运行：Godot --headless --path . --script .zcode/tools/gen_icon.gd

const OUT := "res://assets/icons/icon_1024.png"

func _initialize() -> void:
	var PixelArt := load("res://scripts/art/pixel_art.gd")
	var tex: ImageTexture = PixelArt.gen_title_art()
	var img: Image = tex.get_image()
	var src := img.get_region(Rect2i(120, 0, 120, 120))
	src.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons"))
	var err := src.save_png(ProjectSettings.globalize_path(OUT))
	print("ICON saved ", OUT, " 1024x1024 err=", err)
	quit(0 if err == OK else 1)
