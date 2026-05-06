@tool
class_name HasturCSharpExecutorBackend
extends Node


signal connection_state_changed(connected: bool, executor_id: String)
signal execution_completed(entry: Dictionary)
signal history_cleared()


const ExecutorRouterScript = preload("res://addons/hasturoperationgd_CS/executor_router.gd")
const GDScriptExecutorScript = preload("res://addons/hasturoperationgd_CS/gdscript_executor.gd")
const BrokerClientScript = preload("res://addons/hasturoperationgd_CS/broker_client.gd")
const SettingsScript = preload("res://addons/hasturoperationgd_CS/hastur_operation_gd_plugin_settings.gd")

var _executor
var _router
var _broker_client
var _editor_plugin = null
var _history: Array = []
var _max_history: int = 50


func initialize(p_editor_plugin) -> void:
	_editor_plugin = p_editor_plugin


func _ready() -> void:
	_executor = GDScriptExecutorScript.new()
	_router = ExecutorRouterScript.new("editor", _editor_plugin)
	var broker_host = SettingsScript.get_broker_host()
	var broker_port = SettingsScript.get_broker_port()
	_broker_client = BrokerClientScript.new(broker_host, broker_port, "editor", _editor_plugin)
	_broker_client.connection_established.connect(_on_broker_connected)
	_broker_client.connection_lost.connect(_on_broker_disconnected)
	_broker_client.remote_execution_completed.connect(_on_remote_execution)


func _process(delta: float) -> void:
	if _broker_client:
		_broker_client.poll(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _broker_client:
			_broker_client.disconnect_client()
			_broker_client = null
		_executor = null
		_router = null


func execute_code(code: String, language: String = "gdscript") -> Dictionary:
	var start_time = Time.get_ticks_msec()
	var result = _router.execute_code(language, code, {}, _editor_plugin)
	var end_time = Time.get_ticks_msec()
	var duration_ms = end_time - start_time
	var entry = {
		"code": code,
		"language": language,
		"result": result,
		"timestamp": Time.get_time_string_from_system(),
		"duration_ms": duration_ms,
		"source": "local"
	}
	_add_to_history(entry)
	execution_completed.emit(entry)
	return result


func get_history() -> Array:
	return _history


func get_supported_languages() -> PackedStringArray:
	return ExecutorRouterScript.get_supported_languages()


func get_connection_details() -> Dictionary:
	var broker_host = SettingsScript.get_broker_host()
	var broker_port = SettingsScript.get_broker_port()
	var languages: Array = []
	for language in get_supported_languages():
		languages.append(language)
	return {
		"connected": _broker_client != null and _broker_client.is_broker_connected(),
		"executor_id": _broker_client.get_executor_id() if _broker_client != null else "",
		"broker_host": broker_host,
		"broker_port": broker_port,
		"supported_languages": languages
	}


func clear_history() -> void:
	_history.clear()
	history_cleared.emit()


func _on_broker_connected(id: String) -> void:
	connection_state_changed.emit(true, id)


func _on_broker_disconnected() -> void:
	connection_state_changed.emit(false, "")


func _on_remote_execution(code: String, result: Dictionary, duration_ms: int) -> void:
	var entry = {
		"code": code,
		"language": "remote",
		"result": result,
		"timestamp": Time.get_time_string_from_system(),
		"duration_ms": duration_ms,
		"source": "remote"
	}
	_add_to_history(entry)
	execution_completed.emit(entry)


func _add_to_history(entry: Dictionary) -> void:
	_history.append(entry)
	if _history.size() > _max_history:
		_history.pop_front()
