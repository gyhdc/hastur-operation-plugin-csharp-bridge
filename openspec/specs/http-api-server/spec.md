## Requirements

### Requirement: Bearer token authentication
All HTTP API endpoints SHALL require a valid Bearer token in the `Authorization` header. Requests without a valid token SHALL receive a 401 response with a JSON body containing `success: false`, an error message, and a `hint` field guiding correct authentication.

#### Scenario: Valid auth token provided
- **WHEN** a request includes `Authorization: Bearer <valid-token>`
- **THEN** the request SHALL be processed normally

#### Scenario: Missing auth header
- **WHEN** a request is made without an `Authorization` header
- **THEN** the response SHALL be HTTP 401 with body `{"success": false, "error": "Authentication required", "hint": "Include an Authorization header with Bearer token: Authorization: Bearer <token>. The token was printed when the broker-server started."}`

#### Scenario: Invalid auth token
- **WHEN** a request includes an incorrect Bearer token
- **THEN** the response SHALL be HTTP 401 with body `{"success": false, "error": "Invalid authentication token", "hint": "Check the auth token. It was printed when the broker-server started with --auth-token or auto-generated."}`

### Requirement: List registered executors endpoint
The HTTP API SHALL provide a `GET /api/executors` endpoint that returns a JSON array of all currently registered Hastur Executor instances. Each executor entry SHALL include `id`, `project_name`, `project_path`, `editor_pid`, `plugin_version`, `editor_version`, `supported_languages`, `connected_at` (ISO 8601 timestamp), `status` ("connected" or "disconnected"), and `type` (`"editor"` or `"game"`).

#### Scenario: Query executors when both editor and game executors are connected
- **WHEN** a `GET /api/executors` request is made and one editor executor and one game executor are registered and connected
- **THEN** the response SHALL be HTTP 200 with body `{"success": true, "data": [{"id": "...", "type": "editor", ...}, {"id": "...", "type": "game", ...}]}`

#### Scenario: Query executors when no executors connected
- **WHEN** a `GET /api/executors` request is made and no executors are registered
- **THEN** the response SHALL be HTTP 200 with body `{"success": true, "data": [], "hint": "No Hastur Executors are currently connected. Ensure the Hastur Executor plugin is enabled in a Godot editor and can reach the broker-server."}`

### Requirement: Same-project runtime status endpoint
The HTTP API SHALL provide a read-only `GET /api/executors/runtime-status?project_path=<path>` endpoint that requires Bearer token authentication, validates `project_path`, matches connected executors by normalized same-project path, and returns `editor_connected`, `game_connected`, `editor_executors`, `game_executors`, and an AI-agent-friendly `recommended_next_request` without replacing `GET /api/executors`.

#### Scenario: Missing project_path
- **WHEN** a `GET /api/executors/runtime-status` request is made without `project_path`
- **THEN** the response SHALL be HTTP 400 with `success: false`, an error mentioning `project_path`, and an actionable `hint`

#### Scenario: Only editor executor connected
- **WHEN** a `GET /api/executors/runtime-status?project_path=<project>` request matches a connected editor executor but no same-project game executor
- **THEN** the response SHALL be HTTP 200 with `editor_connected: true`, `game_connected: false`, matching editor executors, no game executors, and a recommended next request to run `csharp-command` `game_executor_status` on `type: "editor"`

#### Scenario: Editor and game executors connected
- **WHEN** the request matches both a connected editor executor and same-project game executor
- **THEN** the response SHALL be HTTP 200 with `editor_connected: true`, `game_connected: true`, both executor lists, and a recommended next request to run `csharp-command` `runtime_status` on `type: "game"`

#### Scenario: No matching project
- **WHEN** the request does not match any connected executor project path
- **THEN** the response SHALL be HTTP 200 with both connected flags false, empty executor lists, a `hint`, and a recommended next request to `GET /api/executors`

### Requirement: Broker diagnostics endpoint
The HTTP API SHALL provide a read-only `GET /api/diagnostics` endpoint that requires Bearer token authentication and returns broker-oriented diagnostics without exposing the full auth token. The response SHALL include broker ports, token source, connected executor count, advertised languages, executor details, and recent executor connection events.

#### Scenario: Query broker diagnostics
- **WHEN** a valid authenticated `GET /api/diagnostics` request is made
- **THEN** the response SHALL be HTTP 200 with `success: true`, `status: "ok"`, `tcp_port`, `http_port`, `executors_connected`, `tcp_connections_registered`, `languages`, `auth_token_source`, `copy_hint`, `executors`, and `recent_executor_events`
- **AND** the response SHALL NOT include the full auth token value

### Requirement: Execute code endpoint
The HTTP API SHALL provide a `POST /api/execute` endpoint that accepts a JSON body with one of `executor_id` (exact match) or `project_name`/`project_path` (fuzzy match). GDScript requests SHALL include a non-empty `code` string. `csharp-command` requests SHALL accept either a `code` JSON string or direct `command` and optional `args` fields, which the broker normalizes into the existing TCP `code` payload. `csharp-build` requests SHALL accept an omitted `code` field as an empty build command body, legacy JSON in `code`, or direct `args` object fields normalized into the TCP `code` payload. An optional `type` field (`"editor"` or `"game"`) SHALL filter the executor search to only match executors of that type. When no `type` is specified, the search SHALL match executors of any type. When multiple executors match and no `type` filter is given, the first connected result SHALL be returned.

#### Scenario: Execute code by executor ID
- **WHEN** a `POST /api/execute` is made with `{"code": "print(\"hello\")", "executor_id": "<valid-id>"}`
- **THEN** the broker SHALL send the code to the specified executor via TCP and return the execution result

#### Scenario: Execute code by project name with type filter
- **WHEN** a `POST /api/execute` is made with `{"code": "print(\"hello\")", "project_name": "my-game", "type": "game"}`
- **THEN** the broker SHALL find the first connected game executor whose project_name contains "my-game" and forward the code

#### Scenario: Execute code by project name without type filter
- **WHEN** a `POST /api/execute` is made with `{"code": "print(\"hello\")", "project_name": "my-game"}`
- **THEN** the broker SHALL find the first connected executor of any type whose project_name contains "my-game" and forward the code

#### Scenario: No matching executor found with type filter
- **WHEN** a `POST /api/execute` is made with `{"code": "print(\"hello\")", "project_name": "my-game", "type": "game"}`
- **AND** no game executor with that project name is connected
- **THEN** the response SHALL be HTTP 404 with `{"success": false, "error": "No connected Hastur Executor matched the query", "hint": "Use GET /api/executors to list available executors. You can filter by type: \"editor\" or \"game\"."}`

#### Scenario: Missing code field for default GDScript request
- **WHEN** a `POST /api/execute` is made without a `code` field and without a bridge language that permits omitted code
- **THEN** the response SHALL be HTTP 400 with `{"success": false, "error": "Missing required field: code", "hint": "The request body must include a non-empty code field containing GDScript code. Example: {\"code\": \"print(\\\"hello\\\")\"}"}`

#### Scenario: Direct C# command fields
- **WHEN** a `POST /api/execute` is made with `{"language": "csharp-command", "command": "scene_tree", "args": {"scope": "edited"}, "executor_id": "<valid-id>"}`
- **THEN** the broker SHALL forward `{"command":"scene_tree","args":{"scope":"edited"}}` as the TCP `code` payload with language `csharp-command`

#### Scenario: Empty C# build body
- **WHEN** a `POST /api/execute` is made with `{"language": "csharp-build", "executor_id": "<valid-id>"}`
- **THEN** the broker SHALL forward an empty string as the TCP `code` payload with language `csharp-build`

#### Scenario: Direct C# build args
- **WHEN** a `POST /api/execute` is made with `{"language": "csharp-build", "args": {"mode": "dotnet", "configuration": "Debug"}, "executor_id": "<valid-id>"}`
- **THEN** the broker SHALL forward `{"mode":"dotnet","configuration":"Debug"}` as the TCP `code` payload with language `csharp-build`

#### Scenario: Invalid direct C# build args
- **WHEN** a `POST /api/execute` is made with `{"language": "csharp-build", "args": ["bad"], "executor_id": "<valid-id>"}`
- **THEN** the response SHALL be HTTP 400 with `{"success": false, "error": "Invalid field: args", "hint": "<actionable csharp-build args guidance>"}`

#### Scenario: No identifier provided
- **WHEN** a `POST /api/execute` is made with `{"code": "print(\"hello\")"}` but no executor_id, project_name, or project_path
- **THEN** the response SHALL be HTTP 400 with `{"success": false, "error": "No executor identifier provided", "hint": "Provide one of: executor_id (exact match), project_name (fuzzy match), or project_path (fuzzy match) to target a specific executor. Optionally specify type: \"editor\" or \"game\"."}`

#### Scenario: Executor execution timeout
- **WHEN** the executor does not respond within 30 seconds
- **THEN** the response SHALL be HTTP 504 with `{"success": false, "error": "Executor execution timed out (30s)", "hint": "The code execution took too long. Try simplifying the code or check if the executor is responsive."}`

### Requirement: AI-agent-friendly error responses
All HTTP API error responses SHALL include a `hint` field with actionable guidance. The `success` field SHALL always be present. Response structure SHALL be `{"success": boolean, "error"?: string, "hint"?: string, "data"?: object}`.

#### Scenario: 404 route not found
- **WHEN** a request is made to an undefined route
- **THEN** the response SHALL be HTTP 404 with `{"success": false, "error": "Route not found", "hint": "Available endpoints: GET /api/executors - List connected Hastur Executors, POST /api/execute - Execute code on a Hastur Executor"}`

#### Scenario: Method not allowed
- **WHEN** a `POST` request is made to `/api/executors`
- **THEN** the response SHALL be HTTP 405 with `{"success": false, "error": "Method not allowed", "hint": "GET /api/executors to list executors, POST /api/execute to execute code"}`

### Requirement: Health check endpoint
The HTTP API SHALL provide a `GET /api/health` endpoint that returns server status without requiring authentication.

#### Scenario: Health check
- **WHEN** a `GET /api/health` request is made
- **THEN** the response SHALL be HTTP 200 with `{"success": true, "data": {"status": "ok", "tcp_port": <port>, "http_port": <port>, "executors_connected": <count>}}`
