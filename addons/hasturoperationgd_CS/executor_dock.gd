@tool
extends Control


var _code_edit: CodeEdit
var _result_edit: CodeEdit
var _status_label: Label
var _details_label: Label
var _id_label: LineEdit
var _language_option: OptionButton
var _history_list: ItemList
var _backend


func initialize(backend) -> void:
	_backend = backend


func _ready() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var status_bar = HBoxContainer.new()
	_status_label = Label.new()
	_status_label.text = "Disconnected"
	_status_label.add_theme_color_override("font_color", Color.RED)
	status_bar.add_child(_status_label)

	_details_label = Label.new()
	_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_label.clip_text = true
	status_bar.add_child(_details_label)
	vbox.add_child(status_bar)

	_id_label = LineEdit.new()
	_id_label.text = ""
	_id_label.visible = false
	_id_label.editable = false
	_id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_label.tooltip_text = "Click and Ctrl+C to copy executor id"
	vbox.add_child(_id_label)

	var command_bar = HBoxContainer.new()
	_language_option = OptionButton.new()
	_language_option.custom_minimum_size = Vector2(150, 0)
	command_bar.add_child(_language_option)

	var execute_button = Button.new()
	execute_button.text = "Execute"
	execute_button.pressed.connect(_on_execute_pressed)
	command_bar.add_child(execute_button)

	var self_check_button = Button.new()
	self_check_button.text = "Self Check"
	self_check_button.pressed.connect(_use_self_check_template)
	command_bar.add_child(self_check_button)

	var status_button = Button.new()
	status_button.text = "Runtime"
	status_button.pressed.connect(_use_runtime_status_template)
	command_bar.add_child(status_button)

	var build_button = Button.new()
	build_button.text = "Build"
	build_button.pressed.connect(_use_build_template)
	command_bar.add_child(build_button)
	vbox.add_child(command_bar)

	_code_edit = CodeEdit.new()
	_code_edit.custom_minimum_size = Vector2(0, 190)
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_code_edit)

	_result_edit = CodeEdit.new()
	_result_edit.custom_minimum_size = Vector2(0, 130)
	_result_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_edit.editable = false
	_result_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_result_edit)

	var history_vbox = VBoxContainer.new()
	history_vbox.custom_minimum_size = Vector2(0, 110)
	history_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var history_header = HBoxContainer.new()
	var history_title = Label.new()
	history_title.text = "Execution History"
	history_header.add_child(history_title)

	var clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_history)
	history_header.add_child(clear_button)
	history_vbox.add_child(history_header)

	_history_list = ItemList.new()
	_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_list.item_selected.connect(_on_history_selected)
	history_vbox.add_child(_history_list)
	vbox.add_child(history_vbox)

	if _backend:
		_backend.connection_state_changed.connect(_on_connection_state_changed)
		_backend.execution_completed.connect(_on_execution_completed)
		_backend.history_cleared.connect(_on_history_cleared)

	_populate_languages()
	_refresh_connection_details()
	_use_self_check_template()


func _populate_languages() -> void:
	_language_option.clear()
	if not _backend:
		_language_option.add_item("gdscript")
		return
	for language in _backend.get_supported_languages():
		_language_option.add_item(str(language))


func _selected_language() -> String:
	if _language_option.item_count == 0:
		return "gdscript"
	return _language_option.get_item_text(_language_option.selected)


func _select_language(language: String) -> void:
	for i in range(_language_option.item_count):
		if _language_option.get_item_text(i) == language:
			_language_option.select(i)
			return


func _on_execute_pressed() -> void:
	if not _backend:
		return
	var code = _code_edit.text
	var language = _selected_language()
	_backend.execute_code(code, language)


func _use_self_check_template() -> void:
	_select_language("csharp-command")
	_code_edit.text = JSON.stringify({"command": "self_check", "args": {}}, "\t")


func _use_runtime_status_template() -> void:
	_select_language("csharp-command")
	_code_edit.text = JSON.stringify({"command": "runtime_status", "args": {}}, "\t")


func _use_build_template() -> void:
	_select_language("csharp-build")
	_code_edit.text = JSON.stringify({"mode": "dotnet", "configuration": "Debug"}, "\t")


func _display_result(result: Dictionary) -> void:
	var text = ""

	if result.compile_success:
		text += "Compile: SUCCESS\n"
	else:
		text += "Compile: FAILED\n"
		text += str(result.compile_error) + "\n"

	if not result.compile_success:
		text += "Run: (skipped)\n"
	elif result.run_success:
		text += "Run: SUCCESS\n"
	else:
		text += "Run: FAILED\n"
		text += str(result.run_error) + "\n"

	if result.outputs.size() > 0:
		text += "---\n"
		text += "Output:\n"
		for entry in result.outputs:
			text += str(entry[0]) + ":\n" + _format_output_value(str(entry[1])) + "\n"

	_result_edit.text = text


func _format_output_value(value: String) -> String:
	var trimmed = value.strip_edges()
	if not (trimmed.begins_with("{") or trimmed.begins_with("[")):
		return value
	var json = JSON.new()
	if json.parse(trimmed) != OK:
		return value
	return JSON.stringify(json.data, "\t")


func _on_connection_state_changed(connected: bool, executor_id: String) -> void:
	if connected:
		_status_label.text = "Connected"
		_status_label.add_theme_color_override("font_color", Color.GREEN)
		_id_label.text = "Executor ID: " + executor_id
		_id_label.visible = true
	else:
		_status_label.text = "Disconnected"
		_status_label.add_theme_color_override("font_color", Color.RED)
		_id_label.text = ""
		_id_label.visible = false
	_refresh_connection_details()


func _refresh_connection_details() -> void:
	if not _backend:
		_details_label.text = ""
		return
	var details = _backend.get_connection_details()
	_details_label.text = "%s:%d | %s" % [
		str(details.get("broker_host", "localhost")),
		int(details.get("broker_port", 5301)),
		", ".join(details.get("supported_languages", []))
	]


func _on_execution_completed(entry: Dictionary) -> void:
	if entry.source == "local":
		_display_result(entry.result)
	_refresh_history_list()
	_refresh_connection_details()


func _refresh_history_list() -> void:
	if not _backend:
		return
	_history_list.clear()
	var history = _backend.get_history()
	for entry in history:
		var status_str = "OK"
		if not entry.result.get("compile_success", false):
			status_str = "FAIL"
		elif not entry.result.get("run_success", false):
			status_str = "FAIL"
		var language = str(entry.get("language", "gdscript"))
		var display = "[%s] %s - %dms (%s)" % [status_str, entry.timestamp, entry.duration_ms, language]
		var idx = _history_list.add_item(display)
		if status_str == "OK":
			_history_list.set_item_custom_fg_color(idx, Color.GREEN)
		else:
			_history_list.set_item_custom_fg_color(idx, Color.RED)
	if _history_list.item_count > 0:
		_history_list.select(_history_list.item_count - 1)
		_history_list.ensure_current_is_visible()


func _on_history_selected(index: int) -> void:
	if not _backend:
		return
	var history = _backend.get_history()
	if index < 0 or index >= history.size():
		return
	var entry = history[index]
	_code_edit.text = entry.code
	if entry.has("language"):
		_select_language(str(entry.language))
	_display_result(entry.result)


func _on_clear_history() -> void:
	if _backend:
		_backend.clear_history()


func _on_history_cleared() -> void:
	_history_list.clear()
