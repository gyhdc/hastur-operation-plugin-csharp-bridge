class_name HasturCSharpCommandExecutor
extends RefCounted


const ExecutionContextScript = preload("res://addons/hasturoperationgd_CS/execution_context.gd")
const CSharpDiagnosticsScript = preload("res://addons/hasturoperationgd_CS/csharp_diagnostics.gd")
const CSharpBuildExecutorScript = preload("res://addons/hasturoperationgd_CS/csharp_build_executor.gd")
const SAFE_METHOD_PREFIXES = ["Debug", "Hastur", "Get", "Capture"]
const DEFAULT_OUTPUT_CHUNK_LENGTH = 700
const GAME_EXECUTOR_AUTOLOAD_NAME = "GameExecutor"
const GAME_EXECUTOR_AUTOLOAD_KEY = "autoload/GameExecutor"
const GAME_EXECUTOR_SCRIPT_PATH = "res://addons/hasturoperationgd_CS/game_executor.gd"

var _executor_type: String = "editor"
var _editor_plugin_ref = null


func _init(executor_type: String = "editor", editor_plugin = null) -> void:
	_executor_type = executor_type
	_editor_plugin_ref = editor_plugin


func execute_code(code: String, execute_context: Dictionary = {}, editor_plugin = null) -> Dictionary:
	if editor_plugin != null:
		_editor_plugin_ref = editor_plugin

	var result = _base_result()
	var payload_result = _parse_payload(code)
	if not payload_result.ok:
		result.compile_error = payload_result.error
		return result

	result.compile_success = true
	var payload: Dictionary = payload_result.payload
	var command = str(payload.get("command", ""))
	var args = payload.get("args", {})
	if not args is Dictionary:
		result.run_error = "csharp-command args must be a JSON object"
		return result

	var ctx = ExecutionContextScript.new(_editor_plugin_ref)
	match command:
		"command_help":
			_run_command_help(args, ctx, result)
		"project_info":
			_run_project_info(args, ctx, result)
		"self_check":
			_run_self_check(args, ctx, result)
		"game_executor_status":
			_run_game_executor_status(args, ctx, result)
		"ensure_game_executor":
			_run_ensure_game_executor(args, ctx, result)
		"start_game_and_wait_hint":
			_run_start_game_and_wait_hint(args, ctx, result)
		"get_edited_scene":
			_run_get_edited_scene(args, ctx, result)
		"scene_tree":
			_run_scene_tree(args, ctx, result)
		"node_snapshot", "inspect_node":
			_run_node_snapshot(args, ctx, result, command)
		"list_nodes":
			_run_list_nodes(args, ctx, result)
		"find_nodes":
			_run_find_nodes(args, ctx, result)
		"get_property":
			_run_get_property(args, ctx, result)
		"set_property":
			_run_set_property(args, ctx, result)
		"get_signals":
			_run_get_signals(args, ctx, result)
		"get_groups":
			_run_get_groups(args, ctx, result)
		"debug_snapshot":
			_run_debug_snapshot(args, ctx, result)
		"call_method", "call_debug_method":
			_run_call_method(args, ctx, result, command)
		"open_scene":
			_run_open_scene(args, ctx, result)
		"save_scene":
			_run_save_scene(args, ctx, result)
		"select_node":
			_run_select_node(args, ctx, result)
		"click_button":
			_run_click_button(args, ctx, result)
		"build_open_inspect":
			_run_build_open_inspect(args, ctx, result)
		"start_game":
			_run_start_game(args, ctx, result)
		"stop_game":
			_run_stop_game(args, ctx, result)
		"reload_project_scripts":
			_run_reload_project_scripts(args, ctx, result)
		"runtime_status":
			_run_runtime_status(args, ctx, result)
		_:
			result.run_error = "Unsupported csharp-command: %s" % command

	result.outputs = ctx.get_outputs()
	return result


static func has_csharp_project() -> bool:
	return _find_csproj_path() != ""


static func has_csharp_runtime() -> bool:
	return ClassDB.class_exists("CSharpScript")


static func get_project_csproj_files() -> Array:
	return CSharpDiagnosticsScript.get_project_csproj_files()


static func _find_csproj_path() -> String:
	return CSharpDiagnosticsScript.find_csproj_path()


static func _join_path(base: String, file_name: String) -> String:
	return CSharpDiagnosticsScript._join_path(base, file_name)


func _parse_payload(code: String) -> Dictionary:
	if code.strip_edges() == "":
		return {"ok": false, "error": "csharp-command payload is empty", "payload": {}}

	var json = JSON.new()
	var parse_error = json.parse(code)
	if parse_error != OK:
		return {"ok": false, "error": "Invalid csharp-command JSON: %s at line %d" % [json.get_error_message(), json.get_error_line()], "payload": {}}
	if not json.data is Dictionary:
		return {"ok": false, "error": "csharp-command payload must be a JSON object", "payload": {}}
	return {"ok": true, "error": "", "payload": json.data}


func _run_command_help(_args: Dictionary, ctx, result: Dictionary) -> void:
	_output_json(ctx, "command_help", {
		"commands": [
			"project_info",
			"self_check",
			"command_help",
			"runtime_status",
			"game_executor_status",
			"ensure_game_executor",
			"start_game_and_wait_hint",
			"get_edited_scene",
			"scene_tree",
			"list_nodes",
			"find_nodes",
			"inspect_node",
			"get_property",
			"set_property",
			"get_signals",
			"get_groups",
			"debug_snapshot",
			"call_debug_method",
			"open_scene",
			"save_scene",
			"select_node",
			"click_button",
			"build_open_inspect",
			"start_game",
			"stop_game",
			"reload_project_scripts"
		],
		"scopes": ["edited", "runtime"],
		"filters": ["path", "max_depth", "name_filter", "class_filter", "script_filter", "text_filter", "limit", "child_limit", "compact", "chunk", "chunk_length", "max_output_chunks", "include_internal", "include_script"],
		"safe_method_prefixes": SAFE_METHOD_PREFIXES,
		"set_property_value_types": ["null", "bool", "int", "float", "string", "Array", "Vector2", "Vector2i", "Vector3", "Vector3i", "Color", "Rect2"]
	})
	result.run_success = true


func _run_project_info(_args: Dictionary, ctx, result: Dictionary) -> void:
	var info = CSharpDiagnosticsScript.collect(_executor_type, _editor_plugin_ref, false)
	_output_json(ctx, "project_info", info)
	result.run_success = true


func _run_self_check(args: Dictionary, ctx, result: Dictionary) -> void:
	var include_dotnet_info = bool(args.get("include_dotnet_info", false))
	var info = CSharpDiagnosticsScript.collect(_executor_type, _editor_plugin_ref, include_dotnet_info)
	info["game_executor"] = _collect_game_executor_status()
	_output_json(ctx, "self_check", info, args)
	result.run_success = true


func _run_scene_tree(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var compact = _is_compact(args)
	var max_depth = clampi(int(args.get("max_depth", 2 if compact else 8)), 0, 32)
	var path = str(args.get("path", ""))
	var root = _find_node(path, scope) if path != "" else _get_scope_root(scope)
	if root == null:
		result.run_error = "Node not found for scene_tree path: %s" % path if path != "" else _no_scope_root_error(scope)
		return

	var tree_data = _serialize_node(root, 0, max_depth, args)
	if compact:
		tree_data["compact"] = true
	_output_json(ctx, "scene_tree", tree_data, args)
	result.run_success = true


func _run_node_snapshot(args: Dictionary, ctx, result: Dictionary, output_key: String = "node_snapshot") -> void:
	var scope = str(args.get("scope", _default_scope()))
	var path = str(args.get("path", ""))
	var node = _find_node(path, scope)
	if node == null:
		result.run_error = "Node not found: %s" % path
		return

	var requested_properties = args.get("properties", [])
	if requested_properties == null:
		requested_properties = []
	if not requested_properties is Array:
		result.run_error = "%s properties must be an array" % output_key
		return
	if requested_properties.is_empty() and (not _is_compact(args) or bool(args.get("include_default_properties", false))):
		requested_properties = _default_property_names(node)

	var properties = {}
	for property_name in requested_properties:
		var key = str(property_name)
		properties[key] = _read_property(node, key)

	var snapshot = _serialize_node_shallow(node, _include_script(args))
	if _is_compact(args):
		snapshot["compact"] = true
	snapshot["properties"] = properties
	_output_json(ctx, output_key, snapshot, args)
	result.run_success = true


func _run_list_nodes(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var compact = _is_compact(args)
	var max_depth = clampi(int(args.get("max_depth", 4 if compact else 8)), 0, 32)
	var path = str(args.get("path", ""))
	var root = _find_node(path, scope) if path != "" else _get_scope_root(scope)
	if root == null:
		result.run_error = "Node not found for list_nodes path: %s" % path if path != "" else _no_scope_root_error(scope)
		return

	var nodes: Array = []
	var limit = clampi(int(args.get("limit", 50 if compact else 500)), 1, 5000)
	_collect_nodes(root, 0, max_depth, nodes, args, limit, false)
	_output_json(ctx, "list_nodes", {
		"scope": scope,
		"path": _safe_node_path(root),
		"count": nodes.size(),
		"limit": limit,
		"hit_limit": nodes.size() >= limit,
		"compact": compact,
		"nodes": nodes
	}, args)
	result.run_success = true


func _run_get_edited_scene(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "get_edited_scene requires an editor executor"
		return
	var edited_scene = _get_edited_scene_root()
	_output_json(ctx, "get_edited_scene", {
		"has_edited_scene": edited_scene != null,
		"edited_scene": _serialize_node_shallow(edited_scene, bool(args.get("include_script", true))) if edited_scene != null else null
	}, args)
	result.run_success = true


func _run_find_nodes(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var compact = _is_compact(args)
	var max_depth = clampi(int(args.get("max_depth", 4 if compact else 8)), 0, 32)
	var path = str(args.get("path", ""))
	var root = _find_node(path, scope) if path != "" else _get_scope_root(scope)
	if root == null:
		result.run_error = "Node not found for find_nodes path: %s" % path if path != "" else _no_scope_root_error(scope)
		return

	var limit = clampi(int(args.get("limit", 25 if compact else 100)), 1, 1000)
	var nodes: Array = []
	_collect_nodes(root, 0, max_depth, nodes, args, limit, true)
	_output_json(ctx, "find_nodes", {
		"scope": scope,
		"path": _safe_node_path(root),
		"count": nodes.size(),
		"limit": limit,
		"hit_limit": nodes.size() >= limit,
		"compact": compact,
		"nodes": nodes
	}, args)
	result.run_success = true


func _run_get_property(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var path = str(args.get("path", ""))
	var property_name = str(args.get("property", args.get("name", "")))
	if property_name.strip_edges() == "":
		result.run_error = "get_property requires args.property"
		return

	var node = _find_node(path, scope)
	if node == null:
		result.run_error = "Node not found: %s" % path
		return
	var resolved = _resolve_property_name(node, property_name)
	if resolved == "":
		result.run_error = "Property not found: %s" % property_name
		return

	_output_json(ctx, "get_property", {
		"path": _safe_node_path(node),
		"property": property_name,
		"resolved_property": resolved,
		"value": _variant_to_jsonable(node.get(resolved))
	}, args)
	result.run_success = true


func _run_set_property(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var path = str(args.get("path", ""))
	var property_name = str(args.get("property", args.get("name", "")))
	if property_name.strip_edges() == "":
		result.run_error = "set_property requires args.property"
		return
	if not args.has("value"):
		result.run_error = "set_property requires args.value"
		return

	var node = _find_node(path, scope)
	if node == null:
		result.run_error = "Node not found: %s" % path
		return
	var resolved = _resolve_property_name(node, property_name)
	if resolved == "":
		result.run_error = "Property not found: %s" % property_name
		return

	var conversion = _json_to_variant(args.get("value"))
	if not conversion.ok:
		result.run_error = "Unsupported set_property value: %s" % conversion.error
		return

	var before = node.get(resolved)
	node.set(resolved, conversion.value)
	var after = node.get(resolved)
	_output_json(ctx, "set_property", {
		"path": _safe_node_path(node),
		"property": property_name,
		"resolved_property": resolved,
		"before": _variant_to_jsonable(before),
		"after": _variant_to_jsonable(after)
	}, args)
	result.run_success = true


func _run_get_signals(args: Dictionary, ctx, result: Dictionary) -> void:
	var node = _find_node(str(args.get("path", "")), str(args.get("scope", _default_scope())))
	if node == null:
		result.run_error = "Node not found: %s" % str(args.get("path", ""))
		return

	var signals: Array = []
	for signal_info in node.get_signal_list():
		signals.append(_variant_to_jsonable(signal_info))
	_output_json(ctx, "get_signals", {
		"path": str(node.get_path()),
		"signals": signals
	}, args)
	result.run_success = true


func _run_get_groups(args: Dictionary, ctx, result: Dictionary) -> void:
	var node = _find_node(str(args.get("path", "")), str(args.get("scope", _default_scope())))
	if node == null:
		result.run_error = "Node not found: %s" % str(args.get("path", ""))
		return

	_output_json(ctx, "get_groups", {
		"path": str(node.get_path()),
		"groups": _variant_to_jsonable(node.get_groups())
	}, args)
	result.run_success = true


func _run_call_method(args: Dictionary, ctx, result: Dictionary, output_key: String = "call_method") -> void:
	var scope = str(args.get("scope", _default_scope()))
	var path = str(args.get("path", ""))
	var method = str(args.get("method", ""))
	var call_args = args.get("args", [])

	if not call_args is Array:
		result.run_error = "%s args must be an array" % output_key
		return
	if not _is_safe_method(method):
		result.run_error = "Method is not allowed for csharp-command: %s" % method
		return

	var node = _find_node(path, scope)
	if node == null:
		result.run_error = "Node not found: %s" % path
		return
	if not node.has_method(method):
		result.run_error = "Node does not expose method: %s" % method
		return

	var value = node.callv(method, call_args)
	_output_json(ctx, output_key, {
		"path": path,
		"method": method,
		"value": _variant_to_jsonable(value)
	}, args)
	result.run_success = true


func _run_debug_snapshot(args: Dictionary, ctx, result: Dictionary) -> void:
	var snapshot_args = args.duplicate(true)
	if not snapshot_args.has("method") or str(snapshot_args.get("method", "")).strip_edges() == "":
		snapshot_args["method"] = "DebugSnapshot"
	_run_call_method(snapshot_args, ctx, result, "debug_snapshot")


func _run_open_scene(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "open_scene requires an editor executor"
		return

	var scene_path = str(args.get("path", args.get("scene_path", "")))
	if scene_path.strip_edges() == "":
		result.run_error = "open_scene requires args.path or args.scene_path"
		return
	if not scene_path.begins_with("res://"):
		result.run_error = "open_scene path must use res://: %s" % scene_path
		return

	if not FileAccess.file_exists(scene_path):
		result.run_error = "open_scene path does not exist: %s" % scene_path
		return

	editor_interface.open_scene_from_path(scene_path)
	_output_json(ctx, "open_scene", {
		"path": scene_path,
		"opened": true,
		"edited_scene": _serialize_node_shallow(_get_edited_scene_root())
	}, args)
	result.run_success = true


func _run_save_scene(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "save_scene requires an editor executor"
		return
	if not editor_interface.has_method("save_scene"):
		result.run_error = "EditorInterface.save_scene is not available"
		return

	var error_code = int(editor_interface.save_scene())
	_output_json(ctx, "save_scene", {
		"error_code": error_code,
		"succeeded": error_code == OK,
		"edited_scene": _serialize_node_shallow(_get_edited_scene_root())
	}, args)
	result.run_success = error_code == OK
	if not result.run_success:
		result.run_error = "save_scene failed with error code %d" % error_code


func _run_select_node(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "select_node requires an editor executor"
		return
	if not editor_interface.has_method("edit_node"):
		result.run_error = "EditorInterface.edit_node is not available"
		return

	var scope = str(args.get("scope", "edited"))
	var path = str(args.get("path", "."))
	var node = _find_node(path, scope)
	if node == null:
		result.run_error = "Node not found: %s" % path
		return

	editor_interface.edit_node(node)
	_output_json(ctx, "select_node", {
		"selected": _serialize_node_shallow(node)
	}, args)
	result.run_success = true


func _run_click_button(args: Dictionary, ctx, result: Dictionary) -> void:
	var scope = str(args.get("scope", _default_scope()))
	var path = str(args.get("path", ""))
	var node: Node = null
	if path != "":
		node = _find_node(path, scope)
	else:
		var root = _get_scope_root(scope)
		if root == null:
			result.run_error = _no_scope_root_error(scope)
			return
		var search_args = args.duplicate()
		search_args["class_filter"] = str(args.get("class_filter", "BaseButton"))
		var matches: Array = []
		_collect_nodes(root, 0, clampi(int(args.get("max_depth", 8)), 0, 32), matches, search_args, 2, true)
		if matches.size() == 1:
			node = _find_node(str(matches[0].get("path", "")), scope)
		elif matches.size() > 1:
			result.run_error = "click_button matched multiple buttons; provide args.path or a narrower filter"
			return
	if node == null:
		result.run_error = "Button not found"
		return
	if not node is BaseButton:
		result.run_error = "click_button target is not a BaseButton: %s" % node.get_class()
		return

	var button = node as BaseButton
	if button.disabled:
		result.run_error = "click_button target is disabled: %s" % _safe_node_path(button)
		return
	button.emit_signal("pressed")
	var text_property = _resolve_property_name(button, "text")
	_output_json(ctx, "click_button", {
		"clicked": true,
		"button": _serialize_node_shallow(button),
		"text": str(button.get(text_property)) if text_property != "" else ""
	}, args)
	result.run_success = true


func _run_build_open_inspect(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "build_open_inspect requires an editor executor"
		return

	var build_args = args.get("build_args", args.get("build", {}))
	if build_args == null:
		build_args = {}
	if not build_args is Dictionary:
		result.run_error = "build_open_inspect build_args must be a JSON object"
		return

	var build_executor = CSharpBuildExecutorScript.new()
	var build_result = build_executor.execute_code(JSON.stringify(build_args), {}, _editor_plugin_ref)
	var build_succeeded = bool(build_result.get("run_success", false))
	if not build_succeeded:
		_output_json(ctx, "build_open_inspect", {
			"build_succeeded": false,
			"build_result": _build_result_for_output(build_result, args),
			"opened": false
		}, args)
		result.run_success = false
		result.run_error = str(build_result.get("run_error", "csharp-build failed"))
		return

	var scene_path = str(args.get("scene_path", args.get("path", "")))
	var opened = false
	if scene_path != "":
		if not scene_path.begins_with("res://"):
			result.run_error = "build_open_inspect scene_path must use res://: %s" % scene_path
			return
		if not FileAccess.file_exists(scene_path):
			result.run_error = "build_open_inspect scene_path does not exist: %s" % scene_path
			return
		editor_interface.open_scene_from_path(scene_path)
		opened = true

	var inspect_args = args.get("inspect_args", {})
	if inspect_args == null:
		inspect_args = {}
	if not inspect_args is Dictionary:
		result.run_error = "build_open_inspect inspect_args must be a JSON object"
		return
	if args.has("compact") and not inspect_args.has("compact"):
		inspect_args["compact"] = bool(args.get("compact", false))
	var root = _find_node(str(inspect_args.get("path", "")), str(inspect_args.get("scope", "edited"))) if str(inspect_args.get("path", "")) != "" else _get_edited_scene_root()
	var max_depth = clampi(int(inspect_args.get("max_depth", 2)), 0, 32)
	var scene_tree = _serialize_node(root, 0, max_depth, inspect_args) if root != null else null
	if scene_tree is Dictionary and _is_compact(inspect_args):
		scene_tree["compact"] = true
	_output_json(ctx, "build_open_inspect", {
		"build_succeeded": true,
		"build_result": _build_result_for_output(build_result, args),
		"opened": opened,
		"scene_path": scene_path,
		"edited_scene": _serialize_node_shallow(_get_edited_scene_root(), _include_script(inspect_args)),
		"scene_tree": scene_tree
	}, args)
	result.run_success = true


func _run_start_game(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "start_game requires an editor executor"
		return

	var scene_path = str(args.get("scene_path", ""))
	if scene_path != "":
		if not scene_path.begins_with("res://"):
			result.run_error = "start_game scene_path must use res://: %s" % scene_path
			return
		editor_interface.open_scene_from_path(scene_path)
		if editor_interface.has_method("play_current_scene"):
			editor_interface.play_current_scene()
		else:
			editor_interface.play_main_scene()
	else:
		editor_interface.play_main_scene()

	_output_json(ctx, "start_game", {"scene_path": scene_path}, args)
	result.run_success = true


func _run_stop_game(_args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "stop_game requires an editor executor"
		return

	editor_interface.stop_playing_scene()
	_output_json(ctx, "stop_game", {"stopped": true})
	result.run_success = true


func _run_reload_project_scripts(_args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "reload_project_scripts requires an editor executor"
		return

	if editor_interface.has_method("get_resource_filesystem"):
		var filesystem = editor_interface.get_resource_filesystem()
		if filesystem != null:
			filesystem.scan()
	_output_json(ctx, "reload_project_scripts", {"resource_filesystem_scan": true})
	result.run_success = true


func _run_runtime_status(_args: Dictionary, ctx, result: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var current_scene = tree.current_scene if tree != null else null
	var root = tree.root if tree != null else null
	var status = {
		"executor_type": _executor_type,
		"has_scene_tree": tree != null,
		"is_debug_build": OS.is_debug_build(),
		"fps": Engine.get_frames_per_second(),
		"root_path": _safe_node_path(root),
		"root_child_count": root.get_child_count() if root != null else 0,
		"current_scene": _serialize_node_shallow(current_scene) if current_scene != null else null,
		"editor": CSharpDiagnosticsScript._editor_status(_editor_plugin_ref)
	}
	_output_json(ctx, "runtime_status", status)
	result.run_success = true


func _run_game_executor_status(args: Dictionary, ctx, result: Dictionary) -> void:
	_output_json(ctx, "game_executor_status", _collect_game_executor_status(), args)
	result.run_success = true


func _run_ensure_game_executor(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "ensure_game_executor requires an editor executor"
		return

	var allow_project_change = bool(args.get("allow_project_change", false))
	var start_requested = bool(args.get("start_game", false))
	var status = _collect_game_executor_status()
	var response = status.duplicate(true)
	response["allow_project_change"] = allow_project_change
	response["start_requested"] = start_requested
	response["autoload_added"] = false
	response["project_change_required"] = false
	response["autoload_conflict"] = false

	if not bool(status.get("script_exists", false)):
		response["project_change_required"] = false
		response["hint"] = "Bundled GameExecutor script is missing from the _CS plugin."
		_output_json(ctx, "ensure_game_executor", response, args)
		result.run_error = "GameExecutor script is missing: %s" % GAME_EXECUTOR_SCRIPT_PATH
		return

	if bool(status.get("autoload_configured", false)) and not bool(status.get("autoload_matches_plugin", false)):
		response["autoload_conflict"] = true
		response["hint"] = "autoload/GameExecutor exists but points elsewhere. Resolve the conflict manually; this command will not overwrite an existing different autoload."
		_output_json(ctx, "ensure_game_executor", response, args)
		result.run_success = true
		return

	if not bool(status.get("autoload_configured", false)):
		response["project_change_required"] = true
		if not allow_project_change:
			response["hint"] = "Re-run ensure_game_executor with allow_project_change:true to add GameExecutor autoload."
			_output_json(ctx, "ensure_game_executor", response, args)
			result.run_success = true
			return
		if _editor_plugin_ref == null or not _editor_plugin_ref.has_method("add_autoload_singleton"):
			response["hint"] = "EditorPlugin.add_autoload_singleton is unavailable."
			_output_json(ctx, "ensure_game_executor", response, args)
			result.run_error = "EditorPlugin.add_autoload_singleton is unavailable"
			return
		_editor_plugin_ref.add_autoload_singleton(GAME_EXECUTOR_AUTOLOAD_NAME, GAME_EXECUTOR_SCRIPT_PATH)
		response = _collect_game_executor_status()
		response["allow_project_change"] = allow_project_change
		response["start_requested"] = start_requested
		response["autoload_added"] = true
		response["project_change_required"] = false
		response["autoload_conflict"] = false

	if start_requested:
		var start_result = _start_game_from_editor_interface(editor_interface, args)
		response["start"] = start_result
		if not bool(start_result.get("ok", false)):
			_output_json(ctx, "ensure_game_executor", response, args)
			result.run_error = str(start_result.get("error", "Failed to start game"))
			return

	response["recommended_next_request"] = _runtime_status_poll_hint()
	_output_json(ctx, "ensure_game_executor", response, args)
	result.run_success = true


func _run_start_game_and_wait_hint(args: Dictionary, ctx, result: Dictionary) -> void:
	var editor_interface = _get_editor_interface()
	if editor_interface == null:
		result.run_error = "start_game_and_wait_hint requires an editor executor"
		return

	var start_result = _start_game_from_editor_interface(editor_interface, args)
	var response = {
		"project_path": ProjectSettings.globalize_path("res://"),
		"start": start_result,
		"recommended_next_request": _runtime_status_poll_hint(),
		"recommended_runtime_commands": ["runtime_status", "scene_tree", "find_nodes", "inspect_node", "get_property", "call_debug_method"]
	}
	if not bool(start_result.get("ok", false)):
		_output_json(ctx, "start_game_and_wait_hint", response, args)
		result.run_error = str(start_result.get("error", "Failed to start game"))
		return

	_output_json(ctx, "start_game_and_wait_hint", response, args)
	result.run_success = true


func _collect_game_executor_status() -> Dictionary:
	var raw_autoload = ProjectSettings.get_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")
	var autoload_path = _normalize_autoload_path(raw_autoload)
	var autoload_configured = autoload_path != ""
	var autoload_matches_plugin = autoload_configured and autoload_path == GAME_EXECUTOR_SCRIPT_PATH
	var script_exists = ResourceLoader.exists(GAME_EXECUTOR_SCRIPT_PATH) or FileAccess.file_exists(GAME_EXECUTOR_SCRIPT_PATH)
	var editor_status = CSharpDiagnosticsScript._editor_status(_editor_plugin_ref)
	var is_playing_scene = bool(editor_status.get("is_playing_scene", false))
	return {
		"script_exists": script_exists,
		"script_path": GAME_EXECUTOR_SCRIPT_PATH,
		"autoload_configured": autoload_configured,
		"autoload_name": GAME_EXECUTOR_AUTOLOAD_NAME if autoload_configured else "",
		"autoload_path": autoload_path,
		"autoload_matches_plugin": autoload_matches_plugin,
		"is_playing_scene": is_playing_scene,
		"recommended_action": _game_executor_recommended_action(script_exists, autoload_configured, autoload_matches_plugin, is_playing_scene)
	}


func _normalize_autoload_path(value: Variant) -> String:
	var autoload_path = str(value).strip_edges()
	if autoload_path.begins_with("*"):
		autoload_path = autoload_path.substr(1)
	if autoload_path.begins_with("uid://"):
		var resolved_path = ResourceUID.ensure_path(autoload_path)
		if resolved_path != "":
			autoload_path = resolved_path
	return autoload_path


func _game_executor_recommended_action(script_exists: bool, autoload_configured: bool, autoload_matches_plugin: bool, is_playing_scene: bool) -> String:
	if not script_exists:
		return "restore_game_executor_script"
	if not autoload_configured:
		return "add_game_executor_autoload"
	if not autoload_matches_plugin:
		return "resolve_game_executor_autoload_conflict"
	if not is_playing_scene:
		return "start_game"
	return "poll_broker_runtime_status"


func _start_game_from_editor_interface(editor_interface, args: Dictionary) -> Dictionary:
	var scene_path = str(args.get("scene_path", ""))
	var started_current_scene = false
	var started_main_scene = false
	if scene_path != "":
		if not scene_path.begins_with("res://"):
			return {"ok": false, "error": "scene_path must use res://: %s" % scene_path, "scene_path": scene_path}
		editor_interface.open_scene_from_path(scene_path)
		if editor_interface.has_method("play_current_scene"):
			editor_interface.play_current_scene()
			started_current_scene = true
		elif editor_interface.has_method("play_main_scene"):
			editor_interface.play_main_scene()
			started_main_scene = true
		else:
			return {"ok": false, "error": "EditorInterface play_current_scene/play_main_scene is unavailable", "scene_path": scene_path}
	else:
		if not editor_interface.has_method("play_main_scene"):
			return {"ok": false, "error": "EditorInterface.play_main_scene is unavailable", "scene_path": scene_path}
		editor_interface.play_main_scene()
		started_main_scene = true

	return {
		"ok": true,
		"scene_path": scene_path,
		"opened_scene": scene_path != "",
		"started_current_scene": started_current_scene,
		"started_main_scene": started_main_scene,
		"is_playing_scene": editor_interface.is_playing_scene() if editor_interface.has_method("is_playing_scene") else false
	}


func _runtime_status_poll_hint() -> String:
	var project_path = ProjectSettings.globalize_path("res://")
	return "GET /api/executors/runtime-status?project_path=%s, then use csharp-command on type:\"game\" when game_connected is true." % project_path.uri_encode()


func _output_json(ctx, key: String, value: Variant, args: Dictionary = {}) -> void:
	var json_text = JSON.stringify(value)
	var chunk_length = clampi(int(args.get("chunk_length", DEFAULT_OUTPUT_CHUNK_LENGTH)), 100, DEFAULT_OUTPUT_CHUNK_LENGTH)
	var chunk_enabled = bool(args.get("chunk", true))
	if not chunk_enabled or json_text.length() <= chunk_length:
		if not chunk_enabled and json_text.length() > chunk_length:
			ctx.output(key, JSON.stringify({
				"truncated": true,
				"chunked": false,
				"key": key,
				"total_length": json_text.length(),
				"safe_length": chunk_length,
				"hint": "Output omitted because chunk:false and JSON exceeds the safe single-output length. Re-run with chunk:true or narrower args."
			}))
		else:
			ctx.output(key, json_text)
		return

	var max_chunks = clampi(int(args.get("max_output_chunks", 40)), 1, 200)
	var total_chunks = ceili(float(json_text.length()) / float(chunk_length))
	var emitted_chunks = mini(total_chunks, max_chunks)
	ctx.output(key, JSON.stringify({
		"chunked": true,
		"key": key,
		"total_length": json_text.length(),
		"chunk_length": chunk_length,
		"total_chunks": total_chunks,
		"emitted_chunks": emitted_chunks,
		"truncated": emitted_chunks < total_chunks,
		"hint": "Concatenate %s_chunk_001..%s_chunk_%03d to reconstruct JSON." % [key, key, emitted_chunks]
	}))
	for i in range(emitted_chunks):
		ctx.output("%s_chunk_%03d" % [key, i + 1], json_text.substr(i * chunk_length, chunk_length))


func _base_result() -> Dictionary:
	return {
		"compile_success": false,
		"compile_error": "",
		"run_success": false,
		"run_error": "",
		"outputs": []
	}


func _default_scope() -> String:
	return "runtime" if _executor_type == "game" else "edited"


func _is_compact(args: Dictionary) -> bool:
	return bool(args.get("compact", false))


func _include_script(args: Dictionary) -> bool:
	return bool(args.get("include_script", not _is_compact(args)))


func _no_scope_root_error(scope: String) -> String:
	if scope == "runtime" and _executor_type != "game":
		return "No runtime scene root available from this editor executor. Start the game with the GameExecutor autoload, then target the game executor."
	if scope == "edited" and _executor_type == "game":
		return "Edited scene scope is only available from the editor executor."
	return "No scene root available for scope: %s" % scope


func _get_scope_root(scope: String) -> Node:
	if scope == "runtime":
		var tree = Engine.get_main_loop() as SceneTree
		return tree.root if tree != null else null
	if scope == "edited":
		return _get_edited_scene_root()
	return null


func _get_edited_scene_root() -> Node:
	var editor_interface = _get_editor_interface()
	if editor_interface != null and editor_interface.has_method("get_edited_scene_root"):
		return editor_interface.get_edited_scene_root()
	return null


func _get_editor_interface():
	if _editor_plugin_ref != null and _editor_plugin_ref.has_method("get_editor_interface"):
		return _editor_plugin_ref.get_editor_interface()
	return null


func _find_node(path: String, scope: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree != null and path.begins_with("/"):
		if path == "/root" or path == "/" + str(tree.root.name) or _safe_node_path(tree.root) == path:
			return tree.root
		if not tree.root.is_inside_tree():
			return _find_node_by_absolute_path(tree.root, path)
		return tree.root.get_node_or_null(NodePath(path))

	var root = _get_scope_root(scope)
	if root == null:
		return null
	if path == "" or path == ".":
		return root
	if _safe_node_path(root) == path:
		return root
	return root.get_node_or_null(NodePath(path))


func _find_node_by_absolute_path(root: Node, path: String) -> Node:
	if root == null:
		return null
	var parts = path.split("/", false)
	if parts.size() == 0:
		return root
	var index = 0
	if parts[0] == str(root.name):
		index = 1
	var current = root
	while index < parts.size():
		current = _find_direct_child(current, parts[index])
		if current == null:
			return null
		index += 1
	return current


func _find_direct_child(node: Node, child_name: String) -> Node:
	for child in node.get_children():
		if child is Node and str(child.name) == child_name:
			return child
	return null


func _serialize_node(node: Node, depth: int, max_depth: int, args: Dictionary = {}) -> Dictionary:
	var compact = _is_compact(args)
	var data = _serialize_node_compact(node, depth == 0) if compact else _serialize_node_shallow(node, _include_script(args))
	if depth < max_depth:
		var children: Array = []
		var matching_child_count = 0
		var child_limit = clampi(int(args.get("child_limit", 25 if compact else 0)), 0, 5000)
		for child in node.get_children(bool(args.get("include_internal", false))):
			if child is Node:
				if _node_matches_filters(child, args):
					matching_child_count += 1
					if child_limit == 0 or children.size() < child_limit:
						children.append(_serialize_node(child, depth + 1, max_depth, args))
		var omitted_child_count = maxi(matching_child_count - children.size(), 0)
		if not compact or not children.is_empty():
			data["children"] = children
		if compact and omitted_child_count > 0:
			data["children_truncated"] = true
			data["omitted_child_count"] = omitted_child_count
	return data


func _serialize_node_shallow(node: Node, include_script: bool = true) -> Dictionary:
	if node == null:
		return {}
	var script = node.get_script()
	var data = {
		"name": node.name,
		"class": node.get_class(),
		"path": _safe_node_path(node),
		"child_count": node.get_child_count(),
		"owner": _safe_node_path(node.owner) if node.owner != null else "",
		"scene_file_path": node.scene_file_path
	}
	if include_script:
		data["script"] = _script_to_jsonable(script)
	return data


func _serialize_node_compact(node: Node, include_path: bool = true) -> Dictionary:
	if node == null:
		return {}
	var data = {
		"name": node.name,
		"class": node.get_class(),
		"child_count": node.get_child_count()
	}
	if include_path:
		data["path"] = _safe_node_path(node)
	return data


func _collect_nodes(node: Node, depth: int, max_depth: int, nodes: Array, args: Dictionary = {}, limit: int = 500, only_matches: bool = false) -> void:
	if nodes.size() >= limit:
		return
	if not only_matches or _node_matches_filters(node, args):
		var data = _serialize_node_compact(node, true) if _is_compact(args) else _serialize_node_shallow(node, _include_script(args))
		data["depth"] = depth
		nodes.append(data)
		if nodes.size() >= limit:
			return
	if depth >= max_depth:
		return
	for child in node.get_children(bool(args.get("include_internal", false))):
		if child is Node:
			_collect_nodes(child, depth + 1, max_depth, nodes, args, limit, only_matches)


func _node_matches_filters(node: Node, args: Dictionary) -> bool:
	var name_filter = str(args.get("name_filter", ""))
	if name_filter != "" and str(node.name).to_lower().find(name_filter.to_lower()) == -1:
		return false

	var class_filter = str(args.get("class_filter", ""))
	if class_filter != "" and not _class_matches(node, class_filter):
		return false

	var script_filter = str(args.get("script_filter", ""))
	if script_filter != "":
		var script = node.get_script()
		var script_path = script.resource_path if script is Resource else ""
		if script_path.to_lower().find(script_filter.to_lower()) == -1:
			return false

	var text_filter = str(args.get("text_filter", ""))
	if text_filter != "":
		var text_property = _resolve_property_name(node, "text")
		var text_value = str(node.get(text_property)) if text_property != "" else ""
		if text_value.to_lower().find(text_filter.to_lower()) == -1:
			return false

	return true


func _class_matches(node: Node, class_filter: String) -> bool:
	if class_filter == "":
		return true
	if node.get_class() == class_filter:
		return true
	if node.is_class(class_filter):
		return true
	return node.get_class().to_lower().find(class_filter.to_lower()) != -1


func _script_to_jsonable(script) -> Variant:
	if script == null:
		return null
	return {
		"class": script.get_class(),
		"resource_path": script.resource_path if script is Resource else ""
	}


func _read_property(node: Node, requested_name: String) -> Dictionary:
	var resolved = _resolve_property_name(node, requested_name)
	if resolved == "":
		return {"found": false, "error": "Property not found"}
	return {
		"found": true,
		"name": resolved,
		"value": _variant_to_jsonable(node.get(resolved))
	}


func _resolve_property_name(node: Node, requested_name: String) -> String:
	var requested_lower = requested_name.to_lower()
	var snake_name = _to_snake_case(requested_name)
	for property in node.get_property_list():
		var property_name = str(property.get("name", ""))
		if property_name == requested_name:
			return property_name
		if property_name == snake_name:
			return property_name
		if property_name.to_lower() == requested_lower:
			return property_name
	return ""


func _to_snake_case(value: String) -> String:
	var result = ""
	for i in range(value.length()):
		var character = value.substr(i, 1)
		var code = value.unicode_at(i)
		if code >= 65 and code <= 90:
			if i > 0:
				result += "_"
			result += character.to_lower()
		else:
			result += character
	return result


func _default_property_names(node: Node) -> Array:
	var candidates = ["name", "visible", "position", "global_position", "rotation", "scale", "size", "text", "disabled", "button_pressed"]
	var available: Array = []
	for candidate in candidates:
		if _resolve_property_name(node, candidate) != "":
			available.append(candidate)
	return available


func _json_to_variant(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return {"ok": true, "error": "", "value": value}
		TYPE_ARRAY:
			var converted: Array = []
			for item in value:
				var item_result = _json_to_variant(item)
				if not item_result.ok:
					return item_result
				converted.append(item_result.value)
			return {"ok": true, "error": "", "value": converted}
		TYPE_DICTIONARY:
			return _typed_dictionary_to_variant(value)
		_:
			return {"ok": false, "error": "unsupported JSON value type %d" % typeof(value), "value": null}


func _typed_dictionary_to_variant(value: Dictionary) -> Dictionary:
	var type_name = str(value.get("type", ""))
	match type_name:
		"Vector2":
			return {"ok": true, "error": "", "value": Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))}
		"Vector2i":
			return {"ok": true, "error": "", "value": Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))}
		"Vector3":
			return {"ok": true, "error": "", "value": Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))}
		"Vector3i":
			return {"ok": true, "error": "", "value": Vector3i(int(value.get("x", 0)), int(value.get("y", 0)), int(value.get("z", 0)))}
		"Color":
			return {"ok": true, "error": "", "value": Color(float(value.get("r", 0.0)), float(value.get("g", 0.0)), float(value.get("b", 0.0)), float(value.get("a", 1.0)))}
		"Rect2":
			var position_result = _json_to_variant(value.get("position", {"type": "Vector2"}))
			var size_result = _json_to_variant(value.get("size", {"type": "Vector2"}))
			if not position_result.ok:
				return position_result
			if not size_result.ok:
				return size_result
			if not (position_result.value is Vector2) or not (size_result.value is Vector2):
				return {"ok": false, "error": "Rect2 position and size must be Vector2 typed dictionaries", "value": null}
			return {"ok": true, "error": "", "value": Rect2(position_result.value, size_result.value)}
		_:
			return {"ok": false, "error": "dictionary values must include a supported type field", "value": null}


func _execution_result_to_jsonable(execution_result: Dictionary) -> Dictionary:
	return {
		"compile_success": bool(execution_result.get("compile_success", false)),
		"compile_error": str(execution_result.get("compile_error", "")),
		"run_success": bool(execution_result.get("run_success", false)),
		"run_error": str(execution_result.get("run_error", "")),
		"outputs": _variant_to_jsonable(execution_result.get("outputs", []))
	}


func _build_result_for_output(execution_result: Dictionary, args: Dictionary = {}) -> Dictionary:
	if not _is_compact(args):
		return _execution_result_to_jsonable(execution_result)
	var output_keys: Array = []
	for output in execution_result.get("outputs", []):
		if output is Array and output.size() >= 1:
			output_keys.append(str(output[0]))
	return {
		"compile_success": bool(execution_result.get("compile_success", false)),
		"compile_error": str(execution_result.get("compile_error", "")),
		"run_success": bool(execution_result.get("run_success", false)),
		"run_error": str(execution_result.get("run_error", "")),
		"output_keys": output_keys
	}


func _is_safe_method(method: String) -> bool:
	for prefix in SAFE_METHOD_PREFIXES:
		if method.begins_with(prefix):
			return true
	return false


func _variant_to_jsonable(value: Variant, depth: int = 0) -> Variant:
	if depth > 8:
		return str(value)

	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return {"type": "Vector2", "x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"type": "Vector2i", "x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"type": "Vector3i", "x": value.x, "y": value.y, "z": value.z}
		TYPE_RECT2:
			return {"type": "Rect2", "position": _variant_to_jsonable(value.position, depth + 1), "size": _variant_to_jsonable(value.size, depth + 1)}
		TYPE_COLOR:
			return {"type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_ARRAY:
			var array: Array = []
			for item in value:
				array.append(_variant_to_jsonable(item, depth + 1))
			return array
		TYPE_DICTIONARY:
			var dictionary = {}
			for key in value.keys():
				dictionary[str(key)] = _variant_to_jsonable(value[key], depth + 1)
			return dictionary
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Node:
				return {"type": "Node", "class": value.get_class(), "path": _safe_node_path(value)}
			if value is Resource:
				return {"type": "Resource", "class": value.get_class(), "resource_path": value.resource_path}
			return {"type": "Object", "class": value.get_class()}
		_:
			return str(value)


func _safe_node_path(node: Node) -> String:
	if node == null:
		return ""
	if node.is_inside_tree():
		return str(node.get_path())
	if node.name != "":
		return "/" + str(node.name)
	return ""
