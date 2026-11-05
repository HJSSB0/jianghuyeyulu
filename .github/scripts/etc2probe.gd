extends SceneTree
# CI 诊断探针：打印 iOS 导出静默校验所依赖的 ETC2/ASTC 设置在 runner 上的实际读值
func _init():
	print("probe_etc2=", ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", "KEY_MISSING"))
	var n := 0
	for p in ProjectSettings.get_property_list():
		if "vram" in str(p.name):
			print("registered: ", p.name)
			n += 1
	print("registered_count=", n)
	print("os=", OS.get_name())
	quit()
