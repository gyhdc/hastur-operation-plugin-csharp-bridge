class_name HasturCSharpDiagnostics
extends RefCounted


const SettingsScript = preload("res://addons/hasturoperationgd_CS/hastur_operation_gd_plugin_settings.gd")


static func collect(executor_type: String = "editor", editor_plugin = null, include_dotnet_info: bool = false) -> Dictionary:
	var version_info = Engine.get_version_info()
	var project_root = ProjectSettings.globalize_path("res://")
	var csproj_files = get_project_csproj_files()
	var dotnet = _probe_dotnet(include_dotnet_info)
	return {
		"project_name": ProjectSettings.get_setting("application/config/name", "Unnamed"),
		"project_path": project_root,
		"executor_type": executor_type,
		"editor_version": str(version_info.get("string", "")),
		"is_debug_build": OS.is_debug_build(),
		"has_csproj": not csproj_files.is_empty(),
		"csproj_files": csproj_files,
		"has_csharp_runtime": ClassDB.class_exists("CSharpScript"),
		"dotnet": dotnet,
		"broker": {
			"host": SettingsScript.get_broker_host(),
			"port": SettingsScript.get_broker_port()
		},
		"addon": {
			"path": "res://addons/hasturoperationgd_CS",
			"paths_ok": _addon_paths_ok()
		},
		"editor": _editor_status(editor_plugin)
	}


static func get_project_csproj_files() -> Array:
	var files: Array = []
	var project_root = ProjectSettings.globalize_path("res://")
	var dir = DirAccess.open(project_root)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".csproj"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


static func find_csproj_path(requested: String = "") -> String:
	var project_root = ProjectSettings.globalize_path("res://")
	var files = get_project_csproj_files()
	if requested.strip_edges() != "":
		for file_name in files:
			if file_name == requested or _join_path(project_root, file_name) == requested:
				return _join_path(project_root, file_name)
		return ""
	if files.is_empty():
		return ""
	return _join_path(project_root, str(files[0]))


static func _join_path(base: String, file_name: String) -> String:
	if base.ends_with("/") or base.ends_with("\\"):
		return base + file_name
	return base + "/" + file_name


static func _probe_dotnet(include_info: bool) -> Dictionary:
	var output: Array = []
	OS.set_environment("DOTNET_CLI_UI_LANGUAGE", "en")
	var args = ["--info"] if include_info else ["--version"]
	var exit_code = OS.execute("dotnet", args, output, true, false)
	return {
		"available": exit_code == 0,
		"exit_code": exit_code,
		"command": "dotnet " + " ".join(args),
		"output": "\n".join(output)
	}


static func _addon_paths_ok() -> bool:
	return ResourceLoader.exists("res://addons/hasturoperationgd_CS/broker_client.gd") \
		and ResourceLoader.exists("res://addons/hasturoperationgd_CS/executor_router.gd") \
		and ResourceLoader.exists("res://addons/hasturoperationgd_CS/csharp_command_executor.gd")


static func _editor_status(editor_plugin) -> Dictionary:
	if editor_plugin == null or not editor_plugin.has_method("get_editor_interface"):
		return {
			"available": false
		}

	var editor_interface = editor_plugin.get_editor_interface()
	var edited_scene = null
	var is_playing = false
	if editor_interface != null:
		if editor_interface.has_method("get_edited_scene_root"):
			edited_scene = editor_interface.get_edited_scene_root()
		if editor_interface.has_method("is_playing_scene"):
			is_playing = editor_interface.is_playing_scene()
	return {
		"available": editor_interface != null,
		"is_playing_scene": is_playing,
		"edited_scene": str(edited_scene.scene_file_path) if edited_scene != null else ""
	}
