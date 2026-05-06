class_name HasturCSharpExecutorRouter
extends RefCounted


const CSharpBuildExecutorScript = preload("res://addons/hasturoperationgd_CS/csharp_build_executor.gd")
const CSharpCommandExecutorScript = preload("res://addons/hasturoperationgd_CS/csharp_command_executor.gd")
const GDScriptExecutorScript = preload("res://addons/hasturoperationgd_CS/gdscript_executor.gd")

var _executor_type: String = "editor"
var _editor_plugin_ref = null
var _gdscript_executor
var _csharp_command_executor
var _csharp_build_executor


func _init(executor_type: String = "editor", editor_plugin = null) -> void:
	_executor_type = executor_type
	_editor_plugin_ref = editor_plugin
	_gdscript_executor = GDScriptExecutorScript.new()
	_csharp_command_executor = CSharpCommandExecutorScript.new(executor_type, editor_plugin)
	_csharp_build_executor = CSharpBuildExecutorScript.new()


static func get_supported_languages() -> PackedStringArray:
	var languages = PackedStringArray(["gdscript"])
	if CSharpCommandExecutorScript.has_csharp_project() and CSharpCommandExecutorScript.has_csharp_runtime():
		languages.append("csharp-command")
		languages.append("csharp-build")
	return languages


func execute_code(language: String, code: String, execute_context: Dictionary = {}, editor_plugin = null) -> Dictionary:
	var requested_language = language.strip_edges()
	if requested_language == "":
		requested_language = "gdscript"

	match requested_language:
		"gdscript":
			return _gdscript_executor.execute_code(code, execute_context, editor_plugin)
		"csharp-command":
			if not _is_language_supported("csharp-command"):
				return _unsupported_language_result(requested_language)
			return _csharp_command_executor.execute_code(code, execute_context, editor_plugin)
		"csharp-build":
			if not _is_language_supported("csharp-build"):
				return _unsupported_language_result(requested_language)
			return _csharp_build_executor.execute_code(code, execute_context, editor_plugin)
		_:
			return _unsupported_language_result(requested_language)


func _is_language_supported(language: String) -> bool:
	return language in get_supported_languages()


func _unsupported_language_result(language: String) -> Dictionary:
	return {
		"compile_success": false,
		"compile_error": "Unsupported language: %s. Supported languages: %s" % [language, ", ".join(get_supported_languages())],
		"run_success": false,
		"run_error": "",
		"outputs": []
	}
