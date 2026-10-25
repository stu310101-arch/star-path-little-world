extends SceneTree
## Validate imported mip data, not merely the .import configuration string.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var folder: String = "res://assets/discussion_garden/shared_textures"
	var failures: Array[String] = []
	var checked: Array[Dictionary] = []
	for filename: String in DirAccess.get_files_at(folder):
		if filename.get_extension() not in ["png", "jpg", "webp"]: continue
		var path: String = folder.path_join(filename)
		var texture: Texture2D = ResourceLoader.load(path) as Texture2D
		if texture == null:
			failures.append("Cannot load " + path)
			continue
		var pixels: Image = texture.get_image()
		if pixels == null:
			failures.append("Cannot inspect imported image " + path)
			continue
		checked.append({"path":path,"width":pixels.get_width(),"height":pixels.get_height(),"mipmaps":pixels.has_mipmaps(),"mipmap_count":pixels.get_mipmap_count()})
		if not pixels.has_mipmaps(): failures.append("Imported image has no mipmaps: " + path)
		await process_frame
	if checked.is_empty(): failures.append("No shared textures checked")
	var report: Dictionary = {"checked":checked,"count":checked.size(),"failures":failures}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("DISCUSSION_TEXTURE_MIPS ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
