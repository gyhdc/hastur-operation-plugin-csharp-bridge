class_name HasturCSharpBuildExecutor
extends RefCounted


const CSharpDiagnosticsScript = preload("res://addons/hasturoperationgd_CS/csharp_diagnostics.gd")
const ExecutionContextScript = preload("res://addons/hasturoperationgd_CS/execution_context.gd")


func execute_code(code: String, execute_context: Dictionary = {}, editor_plugin = null) -> Dictionary:
	var result = _base_result()
	var options_result = _parse_options(code)
	if not options_result.ok:
		result.compile_error = options_result.error
		return result

	result.compile_success = true
	var ctx = ExecutionContextScript.new(editor_plugin)
	var options: Dictionary = options_result.options
	var mode = str(options.get("mode", "dotnet"))
	var configuration = str(options.get("configuration", "Debug"))
	var requested_csproj = str(options.get("csproj", ""))

	var csproj_path = CSharpDiagnosticsScript.find_csproj_path(requested_csproj)
	if csproj_path == "":
		var missing = requested_csproj if requested_csproj != "" else ".csproj"
		result.run_error = "No matching %s found in project root: %s" % [missing, ProjectSettings.globalize_path("res://")]
		result.outputs = ctx.get_outputs()
		return result

	var start_time = Time.get_ticks_msec()
	var output: Array = []
	var exit_code = 1
	var command_line = ""
	OS.set_environment("DOTNET_CLI_UI_LANGUAGE", "en")
	OS.set_environment("DOTNET_SKIP_FIRST_TIME_EXPERIENCE", "1")

	match mode:
		"dotnet":
			var dotnet_args = ["build", csproj_path, "--nologo", "--configuration", configuration]
			command_line = "dotnet " + " ".join(dotnet_args)
			exit_code = OS.execute("dotnet", dotnet_args, output, true, false)
		"godot":
			var godot_path = OS.get_executable_path()
			var project_root = ProjectSettings.globalize_path("res://")
			var godot_args = ["--headless", "--path", project_root, "--build-solutions", "--quit"]
			command_line = godot_path + " " + " ".join(godot_args)
			exit_code = OS.execute(godot_path, godot_args, output, true, false)
		_:
			result.run_error = "Unsupported csharp-build mode: %s" % mode
			result.outputs = ctx.get_outputs()
			return result

	var duration_ms = Time.get_ticks_msec() - start_time
	var build_output = "\n".join(output)
	var errors = _extract_errors(build_output)
	var warnings = _extract_warnings(build_output)
	var diagnostics = []
	diagnostics.append_array(errors)
	diagnostics.append_array(warnings)
	var summary = {
		"mode": mode,
		"configuration": configuration,
		"csproj": csproj_path,
		"command": command_line,
		"exit_code": exit_code,
		"duration_ms": duration_ms,
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"first_error": errors[0] if errors.size() > 0 else "",
		"succeeded": exit_code == 0
	}

	ctx.output("exit_code", str(exit_code))
	ctx.output("duration_ms", str(duration_ms))
	ctx.output("build_summary", JSON.stringify(summary))
	ctx.output("errors", JSON.stringify(errors))
	ctx.output("warnings", JSON.stringify(warnings))
	ctx.output("diagnostics", JSON.stringify(diagnostics))
	_output_text(ctx, "raw_output", build_output, options)

	result.run_success = exit_code == 0
	if not result.run_success:
		result.run_error = "csharp-build failed with exit code %d" % exit_code
	result.outputs = ctx.get_outputs()
	return result


func _parse_options(code: String) -> Dictionary:
	if code.strip_edges() == "":
		return {"ok": true, "error": "", "options": {}}

	var json = JSON.new()
	var parse_error = json.parse(code)
	if parse_error != OK:
		return {"ok": false, "error": "Invalid csharp-build JSON: %s at line %d" % [json.get_error_message(), json.get_error_line()], "options": {}}
	if not json.data is Dictionary:
		return {"ok": false, "error": "csharp-build payload must be a JSON object", "options": {}}
	return {"ok": true, "error": "", "options": json.data}


func _extract_errors(output: String) -> Array:
	var errors: Array = []
	for raw_line in output.split("\n"):
		var line = raw_line.strip_edges()
		if line.find("error CS") != -1 or line.find(": error ") != -1:
			errors.append(line)
	return errors


func _extract_warnings(output: String) -> Array:
	var warnings: Array = []
	for raw_line in output.split("\n"):
		var line = raw_line.strip_edges()
		if line.find("warning CS") != -1 or line.find(": warning ") != -1:
			warnings.append(line)
	return warnings


func _output_text(ctx, key: String, value: String, options: Dictionary) -> void:
	var chunk_enabled = bool(options.get("chunk", true))
	var chunk_length = clampi(int(options.get("chunk_length", 700)), 100, 700)
	if not chunk_enabled or value.length() <= chunk_length:
		ctx.output(key, value)
		return

	var max_chunks = clampi(int(options.get("max_output_chunks", 40)), 1, 200)
	var total_chunks = ceili(float(value.length()) / float(chunk_length))
	var emitted_chunks = mini(total_chunks, max_chunks)
	ctx.output(key, JSON.stringify({
		"chunked": true,
		"key": key,
		"total_length": value.length(),
		"chunk_length": chunk_length,
		"total_chunks": total_chunks,
		"emitted_chunks": emitted_chunks,
		"truncated": emitted_chunks < total_chunks,
		"hint": "Concatenate %s_chunk_001..%s_chunk_%03d to reconstruct text." % [key, key, emitted_chunks]
	}))
	for i in range(emitted_chunks):
		ctx.output("%s_chunk_%03d" % [key, i + 1], value.substr(i * chunk_length, chunk_length))


func _base_result() -> Dictionary:
	return {
		"compile_success": false,
		"compile_error": "",
		"run_success": false,
		"run_error": "",
		"outputs": []
	}
