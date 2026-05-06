[English](README.en.md)

# Hastur Operation Plugin C# Bridge

这是一个面向 Godot 的远程执行插件和 broker server。它保留原项目的 GDScript 远程执行能力，同时补上 Godot .NET/C# 项目最需要的开发闭环：C# 构建诊断、编辑器场景检查、运行态场景检查、安全属性读写、按钮交互，以及显式调试快照。

本项目基于 [rayxuln/hastur-operation-plugin](https://github.com/rayxuln/hastur-operation-plugin) 的思路和架构继续扩展。原项目的核心价值是让 coding agent 能通过 HTTP 控制 Godot 编辑器；本 fork 的重点是让 C# 项目也能顺手开发。不尝试做任意 C# eval，而是采用更稳定的路线：正常写 C# 文件，正常构建，再通过结构化命令观察编辑器和运行中游戏。

同时优化了原项目有的Godot编辑器输出噪音过多，加大token消耗的问题（真没额度了），并且编写了小脚本辅助agent使用常用功能，节省token消耗。

## 它解决什么问题？

agent 擅于改文件和执行命令，但 Godot 编辑器是 GUI 应用，很多关键信息存在于编辑器场景树、运行态场景树、资源系统和项目设置里，单靠终端很难稳定观察。编写的demo实时运行状态也无法检测，难以调试。

这个 C# Bridge 版本提供：

- 兼容原有 `gdscript`：可在 editor executor 或 game executor 中执行 GDScript 片段/类。
- 新增 `csharp-build`：执行 `dotnet build` 或 Godot solution build，并返回结构化 error、warning、diagnostics 和 raw output。
- 新增 `csharp-command`：通过白名单命令打开场景、检查节点、读取/设置简单属性、点击按钮、调用显式调试方法。
- 区分 editor executor 和 game executor：既能检查编辑器当前场景，也能检查运行中游戏的真实节点状态。
- 提供 `debug_snapshot` / `DebugSnapshot()`：用低成本、可重复的方式读取 C# 游戏对象状态，不需要运行时注入 C# 源码。

## 环境要求

- Godot 4.x；C# 项目需要 Godot .NET/Mono 版本。当前开发和验证基于 Godot 4.6.x Mono。
- Node.js 18+，用于运行 broker server。
- 能发送 HTTP 请求并加载项目 skill 的 coding agent，例如 Codex 或 Claude。

GDScript-only 项目仍可使用原来的 `gdscript` 路径。只有当插件检测到 C# 项目和 C# 运行时可用时，才会向 broker 声明 `csharp-command` 和 `csharp-build`。

## 快速开始

### 1. 启动 Broker Server

```bash
cd broker-server
npm install
npm run dev
# 项目目录的run.bat可以在windows下一键启动服务器。
```

默认配置：

- HTTP API：`http://localhost:5302`
- TCP relay：`localhost:5301`
- Auth：如果没有显式传入 token，broker 会在终端打印一行 `auth-token <token>`。

也可以手动指定端口和 token：

```bash
npx tsx src/index.ts --http-port 5302 --tcp-port 5301 --auth-token your-secret-token
```

### 2. 安装 Godot 插件

把 `addons/hasturoperationgd_CS/` 复制到目标 Godot 项目的 `addons/` 目录，然后在 **项目 > 项目设置 > 插件** 中启用 **HasturOperationGD C# Bridge**。

插件会按照 **Project Settings > Hastur Operation GD** 中的配置连接 broker TCP 端口，默认是 `localhost:5301`。编辑器 Dock 会显示连接状态。

### 3.给Agent装上skill

将项目目录的skills下的godot相关skill加入你当前所用agnet的skills文件夹**（相对原项目skill增强了对codex的支持）**

Agent会自动参照文档学习操作Godot编辑器。

### 4. 把 token 给 Agent

复制控制台输出，向 agent 提供：

- Auth header：`Authorization: Bearer <token>`

查看已连接 executor：

```bash
curl -s -H "Authorization: Bearer <token>" http://localhost:5302/api/executors
```

**如果加载了项目中的skills，Agent将会学习操作方式，直接进行开发。**

多步工作中，优先用 `project_path` 加 `type` 定位，而不是长期复用 executor id：

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "self_check",
  "args": {}
}
```

## 工作原理

整体仍是一个轻量中继架构：

```text
+----------------+        HTTP        +----------------+        TCP        +----------------------+
| Coding Agent   |  <-------------->  | Broker Server  |  <------------>  | Godot Editor Plugin  |
| Codex/Claude   |                    | Node/Express   |                  | HasturOperationGD_CS |
+----------------+                    +----------------+                  +----------------------+
                                                                                     |
                                                                                     | 调试运行时可选
                                                                                     v
                                                                            +----------------------+
                                                                            | GameExecutor runtime |
                                                                            | type: "game"         |
                                                                            +----------------------+
```

1. Coding agent 使用 Bearer token 向 broker 发送 HTTP 请求。
2. Broker 完成认证，并通过 TCP 把请求转发到匹配的 Godot executor。
3. Godot 插件执行 GDScript、C# bridge 命令或 C# build 请求，并返回结构化结果。
4. 当 `GameExecutor` 作为 autoload 安装，且游戏以 debug 模式运行时，broker 会额外看到一个 `type:"game"` executor，用于检查运行态。

## 项目结构

```text
hastur-operation-plugin-csharp-bridge/
|-- addons/
|   `-- hasturoperationgd_CS/          # 复制到目标 Godot 项目的插件目录
|       |-- plugin.cfg                 # 插件声明
|       |-- hasturoperationgd.gd       # EditorPlugin 入口
|       |-- executor_router.gd         # 分发 gdscript/csharp-command/csharp-build 请求
|       |-- gdscript_executor.gd       # 原有 GDScript 片段/类执行器
|       |-- csharp_command_executor.gd # C# bridge 安全命令面
|       |-- csharp_build_executor.gd   # dotnet/Godot 构建诊断
|       |-- csharp_diagnostics.gd      # C# 项目和运行时检测
|       |-- game_executor.gd           # 可选运行态 autoload，提供 type:"game"
|       |-- broker_client.gd           # editor/game executor 共用的 TCP 客户端
|       `-- executor_dock.gd           # 编辑器 Dock 状态面板
|-- broker-server/                     # Node.js HTTP/TCP 中继服务
|-- skills/                            # Agent 使用 Godot/Hastur 的 skill 文档
|-- openspec/                          # broker/plugin API 行为声明
|-- tests/                             # Godot headless 插件测试
`-- README.md / README.en.md
```

## 

## 推荐 C# Agent 工作流

C# 文件仍然是源代码事实来源。本插件不提供类似 GDScript 的任意 C# eval。

1. 用 `GET /api/executors` 发现 executor。
2. 用 `csharp-build` 构建项目。
3. 场景结构变化后，用一次 `build_open_inspect` 构建、打开并快速检查。
4. 需要运行态状态时，先对 editor executor 调用 `game_executor_status`。
5. 如果 runtime autoload 缺失，且用户明确允许改项目，再调用 `ensure_game_executor` 并传 `allow_project_change:true`。
6. 用 `start_game_and_wait_hint` 或 `start_game` 启动游戏。
7. 轮询 `GET /api/executors/runtime-status?project_path=<url-encoded-project-path>`，直到 `game_connected:true`。
8. 对 `type:"game"` 发送 `csharp-command`，使用 `runtime_status`、`debug_snapshot`、聚焦 `find_nodes`、`get_property`、`inspect_node` 或 `call_debug_method`。

典型构建请求：

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-build",
  "args": {
    "mode": "dotnet",
    "configuration": "Debug"
  }
}
```

典型编辑器检查请求：

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "build_open_inspect",
  "args": {
    "compact": true,
    "build_args": { "mode": "dotnet", "configuration": "Debug" },
    "scene_path": "res://scenes/Main.tscn",
    "inspect_args": { "compact": true, "max_depth": 2, "child_limit": 8 }
  }
}
```

典型运行态快照请求：

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "game",
  "language": "csharp-command",
  "command": "debug_snapshot",
  "args": {
    "scope": "runtime",
    "path": "/root/Main/Player"
  }
}
```

在 C# 节点里暴露小型调试方法：

```csharp
public Godot.Collections.Dictionary DebugSnapshot() => new()
{
    ["state"] = _state,
    ["position"] = GlobalPosition,
    ["health"] = _health
};
```

`debug_snapshot` 默认调用 `DebugSnapshot()`。`call_debug_method` 只允许 `Debug`、`Hastur`、`Get`、`Capture` 这类安全前缀的方法。

## API Reference

除 `GET /api/health` 外，所有接口都需要 Bearer token。

### `GET /api/health`

健康检查，不需要认证。

### `GET /api/executors`

列出已连接的 editor executor 和 game executor。每个 executor 包含项目元数据、支持语言、连接状态和 `type`（`"editor"` 或 `"game"`）。

### `GET /api/executors/runtime-status?project_path=<path>`

只读运行态检查接口。返回：

- `editor_connected`
- `game_connected`
- `editor_executors`
- `game_executors`
- `recommended_next_request`

启动游戏后，使用这个接口等待同项目的 `type:"game"` executor 连接成功，再读取运行态节点。

### `GET /api/diagnostics`

返回 broker 诊断信息：端口、token 来源、已连接 executor 数量、已声明语言、executor 详情和最近连接事件。该接口不会返回完整 token；完整 token 只能从 broker 控制台输出复制。

### `POST /api/execute`

在选中的 executor 上执行一次请求。

常用请求字段：

| Field | Type | Notes |
| --- | --- | --- |
| `executor_id` | string | 精确指定 executor。 |
| `project_name` | string | 按项目名模糊匹配。 |
| `project_path` | string | 按项目路径模糊/归一化匹配。 |
| `type` | `"editor"` 或 `"game"` | editor/game 同时连接时建议显式传入。 |
| `language` | string | 默认是 `gdscript`；C# bridge 使用 `csharp-command` 或 `csharp-build`。 |
| `code` | string | GDScript 代码，或旧版 bridge JSON 字符串。 |
| `command` | string | 直接传 `csharp-command` 命令名。 |
| `args` | object | 直接传 `csharp-command` 或 `csharp-build` 参数。 |

必须提供一个目标字段：`executor_id`、`project_name` 或 `project_path`。`type` 只是过滤该目标。

GDScript 示例：

```json
{
  "project_name": "my-game",
  "type": "editor",
  "code": "executeContext.output(\"hello\", \"from gdscript\")"
}
```

直接 `csharp-command` 示例：

```json
{
  "project_path": "E:/Godot/projects/my-game",
  "type": "editor",
  "language": "csharp-command",
  "command": "find_nodes",
  "args": {
    "scope": "edited",
    "path": ".",
    "class_filter": "Button",
    "limit": 20,
    "compact": true
  }
}
```

旧版 `code` 包裹格式仍兼容：

```json
{
  "project_name": "my-game",
  "language": "csharp-command",
  "code": "{\"command\":\"project_info\",\"args\":{}}"
}
```

响应格式：

```json
{
  "success": true,
  "data": {
    "request_id": "uuid",
    "compile_success": true,
    "compile_error": "",
    "run_success": true,
    "run_error": "",
    "outputs": [["key", "value"]]
  }
}
```

`outputs` 中的 value 都是字符串。命令返回 JSON 时由调用方自行解析。大型输出可能拆成 `<key>_chunk_001`、`<key>_chunk_002` 等。

## C# Bridge Commands

不确定当前插件版本支持什么时，先调用 `command_help`。常用命令包括：

- 项目/构建：`project_info`、`self_check`、`reload_project_scripts`、`build_open_inspect`，以及 `csharp-build`。
- Game executor 设置：`game_executor_status`、`ensure_game_executor`、`start_game_and_wait_hint`、`start_game`、`stop_game`、`runtime_status`。
- 场景检查：`get_edited_scene`、`scene_tree`、`list_nodes`、`find_nodes`、`inspect_node`。
- 属性/交互：`get_property`、`set_property`、`get_signals`、`get_groups`、`select_node`、`click_button`。
- 调试钩子：`debug_snapshot`、`call_debug_method`。

聚焦检查参数：

- `scope`：`edited` 或 `runtime`
- `path`：节点路径
- `compact`：简洁输出
- `max_depth`、`child_limit`、`limit`
- `name_filter`、`class_filter`、`script_filter`、`text_filter`
- `include_script`、`include_internal`、`chunk`、`max_output_chunks`

`set_property` 支持 JSON 基础值，也支持显式 typed dict，例如：

```json
{ "type": "Vector2", "x": 12, "y": 34 }
```

```json
{ "type": "Color", "r": 1, "g": 1, "b": 1, "a": 1 }
```

## GDScript 兼容性

如果省略 `language`，请求默认按 `gdscript` 执行。

Snippet mode 会被包装进 `RefCounted` 辅助类。访问场景树时建议使用：

```gdscript
var tree = Engine.get_main_loop() as SceneTree
var scene = tree.edited_scene_root
executeContext.output("scene_name", scene.name if scene != null else "")
```

如果代码包含 `extends`，则进入 full class mode，需要自己定义 `func execute(executeContext):`。

## 安全边界

这个工具能在 Godot 编辑器和 debug 游戏进程里执行代码。请把 broker token 当成密码处理。

- Broker 默认保持 localhost，不要暴露到公网。
- 不要把 auth token 写进公开仓库。
- C# 项目日常检查优先用 `csharp-command`，少用原始运行态 GDScript 探针。
- `GameExecutor` 只在 debug build 中连接 broker，非 debug build 会自动释放自身。
- `ensure_game_executor` 只有在显式传 `allow_project_change:true` 时才会添加 autoload，并且不会覆盖冲突的现有 `GameExecutor`。
- C# bridge 不提供任意 C# eval，也不做运行时 C# 源码注入。

## 测试

Broker 测试：

```bash
cd broker-server
npm test
npm run build
```

Godot 插件冒烟测试：

```bash
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path . --script res://tests/test_csharp_bridge.gd
```

## 许可证

MIT
