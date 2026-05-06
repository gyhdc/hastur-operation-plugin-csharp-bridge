extends SceneTree

const CSharpCommandExecutorScript = preload("res://addons/hasturoperationgd_CS/csharp_command_executor.gd")
const CSharpBuildExecutorScript = preload("res://addons/hasturoperationgd_CS/csharp_build_executor.gd")
const ExecutorRouterScript = preload("res://addons/hasturoperationgd_CS/executor_router.gd")
const GAME_EXECUTOR_AUTOLOAD_KEY = "autoload/GameExecutor"
const GAME_EXECUTOR_SCRIPT_PATH = "res://addons/hasturoperationgd_CS/game_executor.gd"

var _failures: Array[String] = []
var _click_count: int = 0


class DebugSnapshotFixture:
	extends Node

	func DebugSnapshot() -> Dictionary:
		return {"status": "ok", "count": 2}


class FakeEditorInterface:
	var opened_path: String = ""
	var edited_root: Node = Node.new()
	var saved_error: int = OK
	var save_called: bool = false
	var edited_node = null
	var is_playing_scene_value: bool = false
	var play_current_scene_called: bool = false
	var play_main_scene_called: bool = false
	var stop_playing_scene_called: bool = false

	func open_scene_from_path(scene_filepath: String, _set_inherited: bool = false) -> void:
		opened_path = scene_filepath

	func get_edited_scene_root() -> Node:
		return edited_root

	func save_scene() -> int:
		save_called = true
		return saved_error

	func edit_node(node: Node) -> void:
		edited_node = node

	func is_playing_scene() -> bool:
		return is_playing_scene_value

	func play_current_scene() -> void:
		play_current_scene_called = true
		is_playing_scene_value = true

	func play_main_scene() -> void:
		play_main_scene_called = true
		is_playing_scene_value = true

	func stop_playing_scene() -> void:
		stop_playing_scene_called = true
		is_playing_scene_value = false


class FakeEditorPlugin:
	var editor_interface
	var add_autoload_calls: Array = []
	var remove_autoload_calls: Array[String] = []

	func _init(p_editor_interface) -> void:
		editor_interface = p_editor_interface

	func get_editor_interface():
		return editor_interface

	func add_autoload_singleton(autoload_name: String, autoload_path: String) -> void:
		add_autoload_calls.append({"name": autoload_name, "path": autoload_path})
		ProjectSettings.set_setting("autoload/" + autoload_name, "*" + autoload_path)

	func remove_autoload_singleton(autoload_name: String) -> void:
		remove_autoload_calls.append(autoload_name)
		ProjectSettings.set_setting("autoload/" + autoload_name, "")


func _initialize() -> void:
	_test_project_info_command()
	_test_self_check_command()
	_test_runtime_status_command()
	_test_game_executor_status_recognizes_autoload_states()
	_test_ensure_game_executor_requires_explicit_project_change()
	_test_ensure_game_executor_adds_autoload_and_starts_scene_when_allowed()
	_test_start_game_and_wait_hint_starts_scene_and_returns_hint()
	_test_command_aliases()
	_test_debug_snapshot_alias()
	_test_command_help()
	_test_open_scene_treats_editor_api_as_void()
	_test_get_edited_scene_save_scene_and_select_node()
	_test_find_nodes_filters_results()
	_test_get_and_set_property()
	_test_click_button_by_path()
	_test_build_open_inspect_stops_on_failed_build()
	_test_build_open_inspect_compact_summarizes_build_result()
	_test_build_result_output_mode_preserves_full_noncompact()
	_test_scene_tree_chunks_large_payloads()
	_test_scene_tree_compact_limits_noise()
	_test_scene_tree_compact_chunks_large_payloads()
	_test_chunk_false_returns_safe_summary_for_large_json()
	_test_inspect_node_compact_omits_default_properties()
	_test_inspect_node_compact_reads_explicit_or_default_properties()
	_test_find_nodes_compact_limits_results()
	_test_build_executor_reports_missing_csproj()
	_test_build_executor_accepts_json_options()
	_test_router_keeps_gdscript_available()
	_test_router_rejects_unknown_language()

	for failure in _failures:
		printerr(failure)
	quit(1 if _failures.size() > 0 else 0)


func _test_project_info_command() -> void:
	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "project_info", "args": {}}))
	_assert_true(result.get("compile_success", false), "project_info compiles JSON command")
	_assert_true(result.get("run_success", false), "project_info runs successfully")
	_assert_output_has_key(result, "project_info", "project_info returns output")


func _test_self_check_command() -> void:
	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "self_check", "args": {}}))
	_assert_true(result.get("compile_success", false), "self_check compiles JSON command")
	_assert_true(result.get("run_success", false), "self_check runs successfully")
	_assert_output_has_key(result, "self_check", "self_check returns output")


func _test_runtime_status_command() -> void:
	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "runtime_status", "args": {}}))
	_assert_true(result.get("compile_success", false), "runtime_status compiles JSON command")
	_assert_true(result.get("run_success", false), "runtime_status runs successfully")
	_assert_output_has_key(result, "runtime_status", "runtime_status returns output")


func _test_game_executor_status_recognizes_autoload_states() -> void:
	var snapshot = _capture_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY)
	var fake_interface = FakeEditorInterface.new()
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))

	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")
	var missing_result = executor.execute_code(JSON.stringify({"command": "game_executor_status", "args": {}}))
	var missing_data = _parse_output_json(missing_result, "game_executor_status")
	_assert_true(missing_result.get("run_success", false), "game_executor_status runs when autoload is missing")
	_assert_true(bool(missing_data.get("script_exists", false)), "game_executor_status reports bundled game executor script")
	_assert_false(bool(missing_data.get("autoload_configured", true)), "game_executor_status detects missing autoload")
	_assert_equal(str(missing_data.get("recommended_action", "")), "add_game_executor_autoload", "game_executor_status recommends adding missing autoload")

	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "*" + GAME_EXECUTOR_SCRIPT_PATH)
	var configured_result = executor.execute_code(JSON.stringify({"command": "game_executor_status", "args": {}}))
	var configured_data = _parse_output_json(configured_result, "game_executor_status")
	_assert_true(configured_result.get("run_success", false), "game_executor_status runs when autoload is configured")
	_assert_true(bool(configured_data.get("autoload_configured", false)), "game_executor_status detects configured autoload")
	_assert_equal(str(configured_data.get("autoload_name", "")), "GameExecutor", "game_executor_status reports autoload name")
	_assert_equal(str(configured_data.get("autoload_path", "")), GAME_EXECUTOR_SCRIPT_PATH, "game_executor_status normalizes leading star in autoload path")
	_assert_true(bool(configured_data.get("autoload_matches_plugin", false)), "game_executor_status detects matching plugin autoload")
	_assert_equal(str(configured_data.get("recommended_action", "")), "start_game", "game_executor_status recommends starting the game when autoload is ready")

	var game_executor_id = ResourceUID.create_id_for_path(GAME_EXECUTOR_SCRIPT_PATH)
	if not ResourceUID.has_id(game_executor_id):
		ResourceUID.add_id(game_executor_id, GAME_EXECUTOR_SCRIPT_PATH)
	else:
		ResourceUID.set_id(game_executor_id, GAME_EXECUTOR_SCRIPT_PATH)
	var game_executor_uid = ResourceUID.id_to_text(game_executor_id)
	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "*" + game_executor_uid)
	var uid_result = executor.execute_code(JSON.stringify({"command": "game_executor_status", "args": {}}))
	var uid_data = _parse_output_json(uid_result, "game_executor_status")
	_assert_true(uid_result.get("run_success", false), "game_executor_status runs when autoload uses uid path")
	_assert_true(bool(uid_data.get("autoload_configured", false)), "game_executor_status detects uid autoload as configured")
	_assert_equal(str(uid_data.get("autoload_path", "")), GAME_EXECUTOR_SCRIPT_PATH, "game_executor_status resolves uid autoload path")
	_assert_true(bool(uid_data.get("autoload_matches_plugin", false)), "game_executor_status accepts uid path for bundled game executor")
	_assert_equal(str(uid_data.get("recommended_action", "")), "start_game", "game_executor_status recommends starting the game for uid autoload")

	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "*res://custom/game_executor.gd")
	var conflict_result = executor.execute_code(JSON.stringify({"command": "game_executor_status", "args": {}}))
	var conflict_data = _parse_output_json(conflict_result, "game_executor_status")
	_assert_true(conflict_result.get("run_success", false), "game_executor_status runs when autoload path conflicts")
	_assert_true(bool(conflict_data.get("autoload_configured", false)), "game_executor_status detects conflicting autoload as configured")
	_assert_false(bool(conflict_data.get("autoload_matches_plugin", true)), "game_executor_status detects path mismatch")
	_assert_equal(str(conflict_data.get("recommended_action", "")), "resolve_game_executor_autoload_conflict", "game_executor_status reports conflict without overwriting")

	_restore_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY, snapshot)
	if ResourceUID.has_id(game_executor_id):
		ResourceUID.remove_id(game_executor_id)
	fake_interface.edited_root.free()


func _test_ensure_game_executor_requires_explicit_project_change() -> void:
	var snapshot = _capture_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY)
	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")
	var fake_interface = FakeEditorInterface.new()
	var fake_plugin = FakeEditorPlugin.new(fake_interface)
	var executor = CSharpCommandExecutorScript.new("editor", fake_plugin)

	var result = executor.execute_code(JSON.stringify({"command": "ensure_game_executor", "args": {}}))
	var data = _parse_output_json(result, "ensure_game_executor")
	_assert_true(result.get("run_success", false), "ensure_game_executor diagnostics succeed without authorization")
	_assert_true(bool(data.get("project_change_required", false)), "ensure_game_executor reports project change requirement")
	_assert_false(bool(data.get("autoload_added", true)), "ensure_game_executor does not add autoload without authorization")
	_assert_equal(fake_plugin.add_autoload_calls.size(), 0, "ensure_game_executor does not call add_autoload_singleton without authorization")
	_assert_equal(str(ProjectSettings.get_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")), "", "ensure_game_executor leaves autoload unset without authorization")

	_restore_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY, snapshot)
	fake_interface.edited_root.free()


func _test_ensure_game_executor_adds_autoload_and_starts_scene_when_allowed() -> void:
	var snapshot = _capture_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY)
	ProjectSettings.set_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")
	var fake_interface = FakeEditorInterface.new()
	var fake_plugin = FakeEditorPlugin.new(fake_interface)
	var executor = CSharpCommandExecutorScript.new("editor", fake_plugin)
	var scene_path = "res://tests/empty_scene.tscn"

	var result = executor.execute_code(JSON.stringify({"command": "ensure_game_executor", "args": {"allow_project_change": true, "start_game": true, "scene_path": scene_path}}))
	var data = _parse_output_json(result, "ensure_game_executor")
	_assert_true(result.get("run_success", false), "ensure_game_executor runs with explicit authorization")
	_assert_false(bool(data.get("project_change_required", true)), "ensure_game_executor clears project_change_required after adding autoload")
	_assert_true(bool(data.get("autoload_added", false)), "ensure_game_executor reports autoload addition")
	_assert_equal(fake_plugin.add_autoload_calls.size(), 1, "ensure_game_executor calls add_autoload_singleton once")
	if fake_plugin.add_autoload_calls.size() > 0:
		_assert_equal(str(fake_plugin.add_autoload_calls[0].get("name", "")), "GameExecutor", "ensure_game_executor uses fixed GameExecutor autoload name")
		_assert_equal(str(fake_plugin.add_autoload_calls[0].get("path", "")), GAME_EXECUTOR_SCRIPT_PATH, "ensure_game_executor uses bundled _CS game executor path")
	_assert_equal(fake_interface.opened_path, scene_path, "ensure_game_executor opens requested scene before starting")
	_assert_true(fake_interface.play_current_scene_called, "ensure_game_executor starts the requested current scene")
	_assert_false(fake_interface.play_main_scene_called, "ensure_game_executor does not fall back to main scene for explicit scene_path")
	_assert_equal(str(ProjectSettings.get_setting(GAME_EXECUTOR_AUTOLOAD_KEY, "")), "*" + GAME_EXECUTOR_SCRIPT_PATH, "ensure_game_executor fake autoload mutates ProjectSettings")

	_restore_project_setting(GAME_EXECUTOR_AUTOLOAD_KEY, snapshot)
	fake_interface.edited_root.free()


func _test_start_game_and_wait_hint_starts_scene_and_returns_hint() -> void:
	var fake_interface = FakeEditorInterface.new()
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))
	var scene_path = "res://tests/empty_scene.tscn"

	var result = executor.execute_code(JSON.stringify({"command": "start_game_and_wait_hint", "args": {"scene_path": scene_path}}))
	var data = _parse_output_json(result, "start_game_and_wait_hint")
	_assert_true(result.get("run_success", false), "start_game_and_wait_hint runs successfully")
	_assert_equal(fake_interface.opened_path, scene_path, "start_game_and_wait_hint opens requested scene")
	_assert_true(fake_interface.play_current_scene_called, "start_game_and_wait_hint starts current scene")
	_assert_contains(str(data.get("recommended_next_request", "")), "/api/executors/runtime-status", "start_game_and_wait_hint points agents at broker runtime-status polling")
	fake_interface.edited_root.free()


func _test_command_aliases() -> void:
	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "inspect_node", "args": {"scope": "runtime", "path": "/root", "properties": ["name"]}}))
	_assert_true(result.get("compile_success", false), "inspect_node compiles JSON command")
	_assert_true(result.get("run_success", false), "inspect_node runs successfully")
	_assert_output_has_key(result, "inspect_node", "inspect_node returns output")


func _test_debug_snapshot_alias() -> void:
	var node = DebugSnapshotFixture.new()
	node.name = "HasturDebugSnapshotFixture"
	root.add_child(node)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "debug_snapshot", "args": {"scope": "runtime", "path": "/root/HasturDebugSnapshotFixture"}}))
	var data = _parse_output_json(result, "debug_snapshot")
	var invalid_result = executor.execute_code(JSON.stringify({"command": "debug_snapshot", "args": {"scope": "runtime", "path": "/root/HasturDebugSnapshotFixture", "method": "UnsafeSnapshot"}}))
	root.remove_child(node)
	node.free()

	_assert_true(result.get("compile_success", false), "debug_snapshot compiles JSON command")
	_assert_true(result.get("run_success", false), "debug_snapshot runs successfully")
	_assert_equal(str(data.get("method", "")), "DebugSnapshot", "debug_snapshot defaults to DebugSnapshot method")
	var value = data.get("value", {}) as Dictionary
	_assert_equal(str(value.get("status", "")), "ok", "debug_snapshot returns DebugSnapshot value")
	_assert_false(invalid_result.get("run_success", true), "debug_snapshot rejects unsafe method names")
	_assert_contains(str(invalid_result.get("run_error", "")), "not allowed", "debug_snapshot keeps call_debug_method safety checks")


func _test_command_help() -> void:
	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "command_help", "args": {}}))
	_assert_true(result.get("compile_success", false), "command_help compiles JSON command")
	_assert_true(result.get("run_success", false), "command_help runs successfully")
	var help = _parse_output_json(result, "command_help")
	_assert_true("find_nodes" in help.get("commands", []), "command_help lists new C# bridge commands")
	_assert_true("debug_snapshot" in help.get("commands", []), "command_help lists debug_snapshot alias")
	_assert_true("game_executor_status" in help.get("commands", []), "command_help lists game executor status command")
	_assert_true("ensure_game_executor" in help.get("commands", []), "command_help lists game executor ensure command")
	_assert_true("start_game_and_wait_hint" in help.get("commands", []), "command_help lists start-and-wait hint command")


func _test_open_scene_treats_editor_api_as_void() -> void:
	var fake_interface = FakeEditorInterface.new()
	fake_interface.edited_root.name = "TestScene"
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))
	var scene_path = "res://tests/empty_scene.tscn"
	var result = executor.execute_code(JSON.stringify({"command": "open_scene", "args": {"path": scene_path}}))
	_assert_true(result.get("compile_success", false), "open_scene compiles JSON command")
	_assert_true(result.get("run_success", false), "open_scene runs successfully when open_scene_from_path returns void")
	_assert_equal(fake_interface.opened_path, scene_path, "open_scene calls EditorInterface.open_scene_from_path")
	_assert_output_has_key(result, "open_scene", "open_scene returns output")
	fake_interface.edited_root.free()


func _test_get_edited_scene_save_scene_and_select_node() -> void:
	var fake_interface = FakeEditorInterface.new()
	fake_interface.edited_root.name = "EditedRoot"
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))

	var edited_result = executor.execute_code(JSON.stringify({"command": "get_edited_scene", "args": {}}))
	_assert_true(edited_result.get("run_success", false), "get_edited_scene runs successfully")
	_assert_output_has_key(edited_result, "get_edited_scene", "get_edited_scene returns output")

	var save_result = executor.execute_code(JSON.stringify({"command": "save_scene", "args": {}}))
	_assert_true(save_result.get("run_success", false), "save_scene runs successfully")
	_assert_true(fake_interface.save_called, "save_scene calls EditorInterface.save_scene")

	var select_result = executor.execute_code(JSON.stringify({"command": "select_node", "args": {"scope": "edited", "path": "."}}))
	_assert_true(select_result.get("run_success", false), "select_node runs successfully")
	_assert_equal(fake_interface.edited_node, fake_interface.edited_root, "select_node calls EditorInterface.edit_node")
	fake_interface.edited_root.free()


func _test_find_nodes_filters_results() -> void:
	var holder = Node.new()
	holder.name = "HasturFindFixture"
	root.add_child(holder)
	var start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Launch"
	holder.add_child(start_button)
	var ignored_button = Button.new()
	ignored_button.name = "IgnoredButton"
	ignored_button.text = "Other"
	holder.add_child(ignored_button)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "find_nodes", "args": {"scope": "runtime", "path": "/root/HasturFindFixture", "name_filter": "Start", "class_filter": "Button", "max_depth": 2}}))
	var data = _parse_output_json(result, "find_nodes")
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("run_success", false), "find_nodes runs successfully")
	_assert_equal(int(data.get("count", -1)), 1, "find_nodes applies name and class filters")


func _test_get_and_set_property() -> void:
	var node = Node2D.new()
	node.name = "HasturPropertyFixture"
	root.add_child(node)

	var executor = CSharpCommandExecutorScript.new("game")
	var set_result = executor.execute_code(JSON.stringify({"command": "set_property", "args": {"scope": "runtime", "path": "/root/HasturPropertyFixture", "property": "Position", "value": {"type": "Vector2", "x": 12, "y": 34}}}))
	var get_result = executor.execute_code(JSON.stringify({"command": "get_property", "args": {"scope": "runtime", "path": "/root/HasturPropertyFixture", "property": "position"}}))
	var get_data = _parse_output_json(get_result, "get_property")
	root.remove_child(node)
	node.free()

	_assert_true(set_result.get("run_success", false), "set_property runs successfully")
	_assert_true(get_result.get("run_success", false), "get_property runs successfully")
	var value = get_data.get("value", {})
	_assert_equal(int(value.get("x", 0)), 12, "get_property returns updated Vector2 x")
	_assert_equal(int(value.get("y", 0)), 34, "get_property returns updated Vector2 y")


func _test_click_button_by_path() -> void:
	_click_count = 0
	var button = Button.new()
	button.name = "HasturClickButton"
	button.text = "Launch"
	button.pressed.connect(func(): _click_count += 1)
	root.add_child(button)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "click_button", "args": {"scope": "runtime", "path": "/root/HasturClickButton"}}))
	root.remove_child(button)
	button.free()

	_assert_true(result.get("run_success", false), "click_button runs successfully")
	_assert_equal(_click_count, 1, "click_button emits pressed once")


func _test_build_open_inspect_stops_on_failed_build() -> void:
	var fake_interface = FakeEditorInterface.new()
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))
	var result = executor.execute_code(JSON.stringify({"command": "build_open_inspect", "args": {"build_args": {"csproj": "missing.csproj"}, "scene_path": "res://tests/empty_scene.tscn"}}))
	var data = _parse_output_json(result, "build_open_inspect")

	_assert_true(result.get("compile_success", false), "build_open_inspect compiles JSON command")
	_assert_false(result.get("run_success", true), "build_open_inspect stops when csharp-build fails")
	_assert_equal(fake_interface.opened_path, "", "build_open_inspect does not open scene after failed build")
	_assert_false(bool(data.get("build_succeeded", true)), "build_open_inspect reports failed build")
	fake_interface.edited_root.free()


func _test_build_open_inspect_compact_summarizes_build_result() -> void:
	var fake_interface = FakeEditorInterface.new()
	var executor = CSharpCommandExecutorScript.new("editor", FakeEditorPlugin.new(fake_interface))
	var result = executor.execute_code(JSON.stringify({"command": "build_open_inspect", "args": {"compact": true, "build_args": {"csproj": "missing.csproj"}, "scene_path": "res://tests/empty_scene.tscn"}}))
	var data = _parse_output_json(result, "build_open_inspect")
	var build_result = data.get("build_result", {}) as Dictionary

	_assert_false(result.get("run_success", true), "compact build_open_inspect still fails when build fails")
	_assert_false(bool(data.get("build_succeeded", true)), "compact build_open_inspect reports failed build")
	_assert_true(build_result.has("output_keys"), "compact build_open_inspect returns build output key summary")
	_assert_false(build_result.has("outputs"), "compact build_open_inspect omits nested build outputs")
	fake_interface.edited_root.free()


func _test_build_result_output_mode_preserves_full_noncompact() -> void:
	var executor = CSharpCommandExecutorScript.new("editor")
	var build_result = {
		"compile_success": true,
		"compile_error": "",
		"run_success": true,
		"run_error": "",
		"outputs": [["build_summary", "{}"], ["raw_output", "ok"]]
	}
	var full_result = executor._build_result_for_output(build_result, {})
	var compact_result = executor._build_result_for_output(build_result, {"compact": true})

	_assert_true(full_result.has("outputs"), "noncompact build result preserves nested outputs")
	_assert_false(compact_result.has("outputs"), "compact build result omits nested outputs")
	var output_keys = compact_result.get("output_keys", []) as Array
	_assert_equal(output_keys.size(), 2, "compact build result summarizes output keys")
	_assert_equal(str(output_keys[0]), "build_summary", "compact build result keeps first output key")


func _test_scene_tree_chunks_large_payloads() -> void:
	var holder = Node.new()
	holder.name = "HasturChunkFixture"
	root.add_child(holder)
	for i in range(80):
		var child = Node.new()
		child.name = "ChunkChild%03d" % i
		holder.add_child(child)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "scene_tree", "args": {"scope": "runtime", "path": "/root/HasturChunkFixture", "max_depth": 1}}))
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("compile_success", false), "large scene_tree compiles JSON command")
	_assert_true(result.get("run_success", false), "large scene_tree runs successfully")
	_assert_output_has_key(result, "scene_tree", "large scene_tree returns summary output")
	_assert_output_has_key(result, "scene_tree_chunk_001", "large scene_tree emits chunked output")


func _test_scene_tree_compact_limits_noise() -> void:
	var holder = Node.new()
	holder.name = "HasturCompactTreeFixture"
	root.add_child(holder)
	for i in range(80):
		var child = Node.new()
		child.name = "CompactChild%03d" % i
		holder.add_child(child)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "scene_tree", "args": {"scope": "runtime", "path": "/root/HasturCompactTreeFixture", "compact": true, "child_limit": 10}}))
	var data = _parse_output_json(result, "scene_tree")
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("compile_success", false), "compact scene_tree compiles JSON command")
	_assert_true(result.get("run_success", false), "compact scene_tree runs successfully")
	_assert_true(bool(data.get("compact", false)), "compact scene_tree reports compact mode")
	_assert_equal(int(data.get("child_count", -1)), 80, "compact scene_tree keeps real child count")
	_assert_equal(int(data.get("omitted_child_count", -1)), 70, "compact scene_tree reports omitted children")
	_assert_true(bool(data.get("children_truncated", false)), "compact scene_tree reports truncated children")
	_assert_equal((data.get("children", []) as Array).size(), 10, "compact scene_tree limits returned children")


func _test_scene_tree_compact_chunks_large_payloads() -> void:
	var holder = Node.new()
	holder.name = "HasturCompactChunkFixture"
	root.add_child(holder)
	for i in range(80):
		var child = Node.new()
		child.name = "CompactChunkChild%03d" % i
		holder.add_child(child)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "scene_tree", "args": {"scope": "runtime", "path": "/root/HasturCompactChunkFixture", "compact": true, "max_depth": 1, "child_limit": 80}}))
	var data = _parse_output_json(result, "scene_tree")
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("compile_success", false), "large compact scene_tree compiles JSON command")
	_assert_true(result.get("run_success", false), "large compact scene_tree runs successfully")
	_assert_output_has_key(result, "scene_tree_chunk_001", "large compact scene_tree emits chunked output")
	_assert_true(bool(data.get("compact", false)), "large compact scene_tree remains parseable after chunk reconstruction")
	_assert_equal((data.get("children", []) as Array).size(), 80, "large compact scene_tree reconstructs all requested children")


func _test_chunk_false_returns_safe_summary_for_large_json() -> void:
	var holder = Node.new()
	holder.name = "HasturNoChunkFixture"
	root.add_child(holder)
	for i in range(80):
		var child = Node.new()
		child.name = "NoChunkChild%03d" % i
		holder.add_child(child)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "scene_tree", "args": {"scope": "runtime", "path": "/root/HasturNoChunkFixture", "compact": true, "max_depth": 1, "child_limit": 80, "chunk": false}}))
	var data = _parse_output_json(result, "scene_tree")
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("run_success", false), "chunk false large scene_tree command still runs")
	_assert_output_missing_key(result, "scene_tree_chunk_001", "chunk false does not emit chunks")
	_assert_true(bool(data.get("truncated", false)), "chunk false large JSON returns a valid truncation summary")
	_assert_equal(str(data.get("key", "")), "scene_tree", "chunk false summary reports original key")


func _test_inspect_node_compact_omits_default_properties() -> void:
	var node = Node2D.new()
	node.name = "HasturCompactInspectFixture"
	node.position = Vector2(5, 7)
	root.add_child(node)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "inspect_node", "args": {"scope": "runtime", "path": "/root/HasturCompactInspectFixture", "compact": true}}))
	var data = _parse_output_json(result, "inspect_node")
	root.remove_child(node)
	node.free()

	_assert_true(result.get("run_success", false), "compact inspect_node runs successfully")
	_assert_true(bool(data.get("compact", false)), "compact inspect_node reports compact mode")
	var properties = data.get("properties", {}) as Dictionary
	_assert_equal(properties.size(), 0, "compact inspect_node omits default properties")
	_assert_false(data.has("script"), "compact inspect_node omits script payload by default")


func _test_inspect_node_compact_reads_explicit_or_default_properties() -> void:
	var node = Node2D.new()
	node.name = "HasturCompactInspectPropertiesFixture"
	node.position = Vector2(11, 13)
	root.add_child(node)

	var executor = CSharpCommandExecutorScript.new("game")
	var explicit_result = executor.execute_code(JSON.stringify({"command": "inspect_node", "args": {"scope": "runtime", "path": "/root/HasturCompactInspectPropertiesFixture", "compact": true, "properties": ["position"]}}))
	var explicit_data = _parse_output_json(explicit_result, "inspect_node")
	var default_result = executor.execute_code(JSON.stringify({"command": "inspect_node", "args": {"scope": "runtime", "path": "/root/HasturCompactInspectPropertiesFixture", "compact": true, "include_default_properties": true}}))
	var default_data = _parse_output_json(default_result, "inspect_node")
	root.remove_child(node)
	node.free()

	var explicit_properties = explicit_data.get("properties", {}) as Dictionary
	_assert_true(explicit_properties.has("position"), "compact inspect_node reads explicit properties")
	var default_properties = default_data.get("properties", {}) as Dictionary
	_assert_true(default_properties.has("position"), "compact inspect_node can opt into default properties")


func _test_find_nodes_compact_limits_results() -> void:
	var holder = Node.new()
	holder.name = "HasturCompactFindFixture"
	root.add_child(holder)
	for i in range(12):
		var child = Button.new()
		child.name = "CompactButton%03d" % i
		child.text = "Compact"
		holder.add_child(child)

	var executor = CSharpCommandExecutorScript.new("game")
	var result = executor.execute_code(JSON.stringify({"command": "find_nodes", "args": {"scope": "runtime", "path": "/root/HasturCompactFindFixture", "compact": true, "class_filter": "Button", "max_depth": 1, "limit": 5}}))
	var data = _parse_output_json(result, "find_nodes")
	root.remove_child(holder)
	holder.free()

	_assert_true(result.get("compile_success", false), "compact find_nodes compiles JSON command")
	_assert_true(result.get("run_success", false), "compact find_nodes runs successfully")
	_assert_true(bool(data.get("compact", false)), "compact find_nodes reports compact mode")
	_assert_equal(int(data.get("count", -1)), 5, "compact find_nodes respects requested limit")
	_assert_equal(int(data.get("limit", -1)), 5, "compact find_nodes reports limit")
	_assert_true(bool(data.get("hit_limit", false)), "compact find_nodes reports hit limit")
	var nodes = data.get("nodes", []) as Array
	_assert_equal(nodes.size(), 5, "compact find_nodes returns limited nodes")
	if not nodes.is_empty():
		_assert_false((nodes[0] as Dictionary).has("script"), "compact find_nodes omits script payload by default")


func _test_build_executor_reports_missing_csproj() -> void:
	var executor = CSharpBuildExecutorScript.new()
	var result = executor.execute_code("")
	_assert_true(result.get("compile_success", false), "csharp-build accepts empty command body")
	_assert_false(result.get("run_success", true), "csharp-build fails gracefully without a csproj")
	_assert_contains(result.get("run_error", ""), ".csproj", "csharp-build explains missing csproj")


func _test_build_executor_accepts_json_options() -> void:
	var executor = CSharpBuildExecutorScript.new()
	var result = executor.execute_code(JSON.stringify({"mode": "dotnet", "configuration": "Debug", "csproj": "missing.csproj"}))
	_assert_true(result.get("compile_success", false), "csharp-build accepts JSON command body")
	_assert_false(result.get("run_success", true), "csharp-build fails gracefully when requested csproj is missing")
	_assert_contains(result.get("run_error", ""), "missing.csproj", "csharp-build reports requested missing csproj")


func _test_router_keeps_gdscript_available() -> void:
	var languages = ExecutorRouterScript.get_supported_languages()
	_assert_true("gdscript" in languages, "router always advertises gdscript")


func _test_router_rejects_unknown_language() -> void:
	var router = ExecutorRouterScript.new("game")
	var result = router.execute_code("python", "print('no')")
	_assert_false(result.get("compile_success", true), "router rejects unknown language")
	_assert_contains(result.get("compile_error", ""), "Unsupported language", "router reports unsupported language")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append("Expected true: " + message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_failures.append("Expected false: " + message)


func _assert_contains(value: String, expected: String, message: String) -> void:
	if expected not in value:
		_failures.append("%s. Expected '%s' to contain '%s'." % [message, value, expected])


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_failures.append("%s. Expected '%s', got '%s'." % [message, expected, actual])


func _capture_project_setting(key: String) -> Dictionary:
	return {
		"had": ProjectSettings.has_setting(key),
		"value": ProjectSettings.get_setting(key, null)
	}


func _restore_project_setting(key: String, snapshot: Dictionary) -> void:
	if bool(snapshot.get("had", false)):
		ProjectSettings.set_setting(key, snapshot.get("value"))
	else:
		ProjectSettings.set_setting(key, "")


func _assert_output_has_key(result: Dictionary, key: String, message: String) -> void:
	var outputs = result.get("outputs", [])
	for output in outputs:
		if output is Array and output.size() >= 1 and output[0] == key:
			return
	_failures.append(message + ". Missing key: " + key)


func _assert_output_missing_key(result: Dictionary, key: String, message: String) -> void:
	var outputs = result.get("outputs", [])
	for output in outputs:
		if output is Array and output.size() >= 1 and output[0] == key:
			_failures.append(message + ". Unexpected key: " + key)
			return


func _output_value(result: Dictionary, key: String) -> String:
	var outputs = result.get("outputs", [])
	for output in outputs:
		if output is Array and output.size() >= 2 and output[0] == key:
			return str(output[1])
	return ""


func _parse_output_json(result: Dictionary, key: String) -> Dictionary:
	var text = _output_value(result, key)
	if text == "":
		_failures.append("Missing JSON output key: " + key)
		return {}
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		_failures.append("Output key %s is not valid JSON: %s" % [key, json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		_failures.append("Output key %s is not a JSON object" % key)
		return {}
	if bool(json.data.get("chunked", false)) and str(json.data.get("key", "")) == key:
		return _parse_chunked_output_json(result, key, int(json.data.get("emitted_chunks", 0)))
	return json.data


func _parse_chunked_output_json(result: Dictionary, key: String, emitted_chunks: int) -> Dictionary:
	var text = ""
	for i in range(emitted_chunks):
		text += _output_value(result, "%s_chunk_%03d" % [key, i + 1])
	if text == "":
		_failures.append("Missing chunked JSON output for key: " + key)
		return {}
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		_failures.append("Chunked output key %s is not valid JSON: %s" % [key, json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		_failures.append("Chunked output key %s is not a JSON object" % key)
		return {}
	return json.data
