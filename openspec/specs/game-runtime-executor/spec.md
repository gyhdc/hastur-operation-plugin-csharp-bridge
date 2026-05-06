## Requirements

### Requirement: GameExecutor autoload singleton
The `_CS` plugin SHALL provide a `game_executor.gd` script at `addons/hasturoperationgd_CS/game_executor.gd` that extends `Node`. The recommended setup path is the safe editor-side `csharp-command` workflow: `game_executor_status` diagnoses the autoload state and `ensure_game_executor` adds the Autoload only when `allow_project_change:true` is explicitly provided. Manual registration in Project Settings SHALL remain supported with singleton name `"GameExecutor"`. The GameExecutor SHALL reuse the existing broker client and executor classes without modifying authentication, the TCP protocol, default ports, GDScript executor behavior, or existing C# command behavior.

#### Scenario: User manually adds GameExecutor as Autoload
- **WHEN** a user adds `res://addons/hasturoperationgd_CS/game_executor.gd` as an Autoload named `GameExecutor` in Project Settings
- **THEN** the GameExecutor node SHALL be available in the scene tree as `/root/GameExecutor` when the game runs

#### Scenario: Agent diagnoses missing Autoload
- **WHEN** the user has not registered `game_executor.gd` as an Autoload
- **THEN** `csharp-command` `game_executor_status` on the editor executor SHALL report `autoload_configured: false`, `script_exists`, `script_path`, `autoload_name`, `autoload_path`, `autoload_matches_plugin`, `is_playing_scene`, and `recommended_action: "add_game_executor_autoload"` without modifying the project

#### Scenario: Agent adds Autoload with explicit authorization
- **WHEN** `csharp-command` `ensure_game_executor` is sent to the editor executor with `allow_project_change: true`
- **THEN** it SHALL call `EditorPlugin.add_autoload_singleton("GameExecutor", "res://addons/hasturoperationgd_CS/game_executor.gd")` when the autoload is missing
- **AND** it SHALL NOT overwrite an existing `autoload/GameExecutor` that points to a different normalized path

#### Scenario: Agent starts game and waits for runtime executor
- **WHEN** an agent starts the game through `start_game`, `ensure_game_executor` with `start_game: true`, or `start_game_and_wait_hint`
- **THEN** it SHALL poll `GET /api/executors/runtime-status?project_path=<path>` until a same-project `type: "game"` executor is connected before sending runtime inspection commands

### Requirement: Debug-build-only execution guard
The GameExecutor SHALL check `OS.is_debug_build()` in `_ready()`. If the build is not a debug build, the GameExecutor SHALL free itself immediately without connecting to the broker-server.

#### Scenario: Running in debug build
- **WHEN** the game is launched from the editor (debug build) and `OS.is_debug_build()` returns `true`
- **THEN** the GameExecutor SHALL proceed to connect to the broker-server

#### Scenario: Running in release/exported build
- **WHEN** the game is an exported release build and `OS.is_debug_build()` returns `false`
- **THEN** the GameExecutor SHALL call `queue_free()` on itself and SHALL NOT connect to the broker-server

### Requirement: Broker connection and registration
The GameExecutor SHALL connect to the broker-server using the configured `hastur_operation/broker_host` and `hastur_operation/broker_port` project settings. Upon connection, it SHALL send a `register` message with `type: "game"` to identify itself as a game runtime executor.

#### Scenario: GameExecutor connects and registers
- **WHEN** the game starts in debug mode and the broker-server is reachable
- **THEN** the GameExecutor SHALL connect via TCP, send a registration with `type: "game"`, project metadata, and the game process PID
- **THEN** the GameExecutor SHALL receive and store its executor ID

#### Scenario: Broker-server unreachable on game start
- **WHEN** the game starts and the broker-server is not reachable
- **THEN** the GameExecutor SHALL retry connection with exponential backoff without blocking the game

### Requirement: Remote code execution in game runtime
The GameExecutor SHALL receive `execute` messages from the broker-server, execute the provided GDScript code using `GDScriptExecutor`, and return the results via the broker-server.

#### Scenario: Execute code in running game
- **WHEN** the GameExecutor receives `{"type": "execute", "data": {"request_id": "...", "code": "executeContext.output(\"fps\", Engine.get_frames_per_second())", "language": "gdscript"}}`
- **THEN** the GameExecutor SHALL execute the code in the game process context and return the result including any outputs

#### Scenario: Code accesses game scene tree
- **WHEN** an agent sends code like `get_tree().current_scene` through the GameExecutor
- **THEN** the code SHALL execute with full access to the game's scene tree, nodes, and runtime state

#### Scenario: Safe C# runtime inspection commands
- **WHEN** an agent sends `csharp-command` to a same-project `type: "game"` executor
- **THEN** `runtime_status`, `scene_tree`, `find_nodes`, `inspect_node`, `get_property`, and `call_debug_method` SHALL inspect the running game scene tree and C# node state without arbitrary C# eval or runtime source injection
- **AND** `call_debug_method` SHALL remain restricted to safe method prefixes such as `Debug`, `Hastur`, `Get`, and `Capture`

### Requirement: Graceful shutdown on game exit
The GameExecutor SHALL cleanly disconnect from the broker-server when the game process is exiting, by handling `NOTIFICATION_WM_CLOSE_REQUEST` and `NOTIFICATION_PREDELETE_CLEANUP` to prevent ghost executor entries.

#### Scenario: Game closes normally
- **WHEN** the game window is closed or the game stops
- **THEN** the GameExecutor SHALL disconnect from the broker-server before the process exits

#### Scenario: Game crashes
- **WHEN** the game process crashes unexpectedly
- **THEN** the broker-server SHALL detect the disconnection via the existing heartbeat timeout mechanism
