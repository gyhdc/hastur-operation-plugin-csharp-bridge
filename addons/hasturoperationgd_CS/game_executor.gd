extends Node


const BrokerClientScript = preload("res://addons/hasturoperationgd_CS/broker_client.gd")
const SettingsScript = preload("res://addons/hasturoperationgd_CS/hastur_operation_gd_plugin_settings.gd")

var _broker_client


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	var broker_host = SettingsScript.get_broker_host()
	var broker_port = SettingsScript.get_broker_port()
	_broker_client = BrokerClientScript.new(broker_host, broker_port, "game")


func _process(delta: float) -> void:
	if _broker_client:
		_broker_client.poll(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _broker_client:
			_broker_client.disconnect_client()
			_broker_client = null
