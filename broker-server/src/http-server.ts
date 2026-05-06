import express, { type Request, type Response, type NextFunction } from 'express'
import { ExecutorManager } from './executor-manager.js'
import { TcpServer } from './tcp-server.js'
import { createAuthMiddleware } from './auth.js'
import type { ApiResponse, ExecutorInfo, RecommendedNextRequest, RuntimeExecutorStatus } from './types.js'

interface HttpAppOptions {
	authTokenSource?: string
}

interface NormalizedCodeResult {
	ok: boolean
	code: string
	error?: string
	hint?: string
}

export function createHttpApp(
	executorManager: ExecutorManager,
	tcpServer: TcpServer,
	authToken: string,
	tcpPort: number,
	httpPort: number,
	options: HttpAppOptions = {},
) {
	const app = express()
	const authMiddleware = createAuthMiddleware(authToken)
	const authTokenSource = options.authTokenSource ?? 'unknown'

	app.use(express.json())

	app.get('/api/health', (_req: Request, res: Response) => {
		res.json({
			success: true,
			data: {
				status: 'ok',
				tcp_port: tcpPort,
				http_port: httpPort,
				executors_connected: executorManager.getAll().length,
			},
		})
	})

	app.use('/api', (req: Request, res: Response, next: NextFunction) => {
		if (req.path === '/health') {
			next()
			return
		}
		authMiddleware(req, res, next)
	})

	app.get('/api/executors', (_req: Request, res: Response) => {
		const executors = executorManager.getAll()
		const response: ApiResponse = {
			success: true,
			data: executors,
		}
		if (executors.length === 0) {
			response.hint = 'No Hastur Executors are currently connected. Ensure the Hastur Executor plugin is enabled in a Godot editor and can reach the broker-server.'
		}
		res.json(response)
	})

	app.get('/api/executors/runtime-status', (req: Request, res: Response) => {
		const projectPath = req.query.project_path
		if (typeof projectPath !== 'string' || projectPath.trim() === '') {
			res.status(400).json({
				success: false,
				error: 'Missing required query parameter: project_path',
				hint: 'Call GET /api/executors/runtime-status?project_path=<absolute project path> to check same-project editor/game executor state.',
			} satisfies ApiResponse)
			return
		}

		const displayProjectPath = normalizeProjectPathForDisplay(projectPath)
		const executors = executorManager.findAllByProjectPath(projectPath)
		const editorExecutors = executors.filter((executor) => executor.type === 'editor')
		const gameExecutors = executors.filter((executor) => executor.type === 'game')
		const data: RuntimeExecutorStatus = {
			project_path: displayProjectPath,
			editor_connected: editorExecutors.length > 0,
			game_connected: gameExecutors.length > 0,
			editor_executors: editorExecutors,
			game_executors: gameExecutors,
			recommended_next_request: buildRuntimeStatusRecommendation(displayProjectPath, editorExecutors, gameExecutors),
		}
		const response: ApiResponse = {
			success: true,
			data,
		}
		if (executors.length === 0) {
			response.hint = 'No connected Hastur Executor matched this project_path. Use GET /api/executors to list connected projects, then retry with the exact project_path.'
		} else if (gameExecutors.length === 0) {
			response.hint = 'An editor executor is connected for this project, but no same-project game executor is connected yet. Run csharp-command game_executor_status on the editor, then start the game after the GameExecutor autoload is configured.'
		} else {
			response.hint = 'A same-project game executor is connected. Send csharp-command runtime_status, scene_tree, find_nodes, inspect_node, get_property, or call_debug_method with type:"game".'
		}
		res.json(response)
	})

	app.get('/api/diagnostics', (_req: Request, res: Response) => {
		const executors = executorManager.getAll()
		const languages = Array.from(new Set(executors.flatMap((executor) => executor.supported_languages))).sort()
		res.json({
			success: true,
			data: {
				status: 'ok',
				tcp_port: tcpPort,
				http_port: httpPort,
				executors_connected: executors.length,
				tcp_connections_registered: tcpServer.getConnectedCount(),
				languages,
				auth_token_source: authTokenSource,
				copy_hint: 'Copy the full token from the broker console line that starts with: auth-token ',
				executors,
				recent_executor_events: executorManager.getRecentEvents(),
			},
		})
	})

	app.post('/api/executors', (_req: Request, res: Response) => {
		res.status(405).json({
			success: false,
			error: 'Method not allowed',
			hint: 'GET /api/executors to list executors, POST /api/execute to execute code',
		})
	})

	app.post('/api/execute', async (req: Request, res: Response) => {
		const { code, command, args, executor_id, project_name, project_path, type, language: requestedLanguage } = req.body

		if (!executor_id && !project_name && !project_path) {
			res.status(400).json({
				success: false,
				error: 'No executor identifier provided',
				hint: 'Provide one of: executor_id (exact match), project_name (fuzzy match), or project_path (fuzzy match) to target a specific executor. Optionally specify type: "editor" or "game".',
			})
			return
		}

		if (requestedLanguage !== undefined && typeof requestedLanguage !== 'string') {
			res.status(400).json({
				success: false,
				error: 'Invalid field: language',
				hint: 'The optional language field must be a string. Omit it to use gdscript.',
			})
			return
		}

		const language = requestedLanguage && requestedLanguage.trim() !== '' ? requestedLanguage.trim() : 'gdscript'
		const normalizedCode = normalizeExecuteCode(code, command, args, language)
		if (!normalizedCode.ok) {
			res.status(400).json({
				success: false,
				error: normalizedCode.error,
				hint: normalizedCode.hint,
			})
			return
		}

		const executorType = type as ('editor' | 'game') | undefined
		let executor
		if (executor_id) {
			executor = executorManager.findById(executor_id)
			if (executor && executorType && executor.type !== executorType) {
				executor = undefined
			}
		} else if (project_name) {
			executor = executorManager.findByProjectName(project_name, executorType)
		} else if (project_path) {
			executor = executorManager.findByProjectPath(project_path, executorType)
		}

		if (!executor) {
			res.status(404).json({
				success: false,
				error: 'No connected Hastur Executor matched the query',
				hint: 'Use GET /api/executors to list available executors. You can filter by type: "editor" or "game".',
			})
			return
		}

		if (!executor.supported_languages.includes(language)) {
			res.status(400).json({
				success: false,
				error: `Unsupported language: ${language}`,
				hint: `The selected executor supports: ${executor.supported_languages.join(', ') || 'none'}. Use GET /api/executors to inspect capabilities.`,
				data: {
					executor_id: executor.id,
					supported_languages: executor.supported_languages,
				},
			})
			return
		}

		try {
			const result = await tcpServer.sendExecute(executor.id, normalizedCode.code, language)
			res.json({ success: true, data: result })
		} catch (err: unknown) {
			const error = err as Error
			if (error.message === 'TIMEOUT') {
				res.status(504).json({
					success: false,
					error: 'Executor execution timed out (30s)',
					hint: 'The code execution took too long. Try simplifying the code or check if the Godot editor is responsive.',
				})
			} else {
				res.status(500).json({
					success: false,
					error: error.message || 'Execution failed',
					hint: 'An unexpected error occurred during code execution.',
				})
			}
		}
	})

	app.use((_req: Request, res: Response) => {
		res.status(404).json({
			success: false,
			error: 'Route not found',
			hint: 'Available endpoints: GET /api/executors - List connected Hastur Executors, POST /api/execute - Execute code on a Hastur Executor',
		})
	})

	return app
}

function normalizeExecuteCode(code: unknown, command: unknown, args: unknown, language: string): NormalizedCodeResult {
	if (language === 'csharp-command') {
		if (typeof code === 'string' && code.trim() !== '') {
			return { ok: true, code }
		}
		if (typeof command !== 'string' || command.trim() === '') {
			return {
				ok: false,
				code: '',
				error: 'Missing csharp-command payload',
				hint: 'For language "csharp-command", provide either code as a JSON string or direct fields like {"language":"csharp-command","command":"scene_tree","args":{"scope":"edited"}}.',
			}
		}
		if (args !== undefined && !isPlainObject(args)) {
			return {
				ok: false,
				code: '',
				error: 'Invalid field: args',
				hint: 'For direct csharp-command requests, args must be a JSON object when provided.',
			}
		}
		return {
			ok: true,
			code: JSON.stringify({ command: command.trim(), args: args ?? {} }),
		}
	}

	if (language === 'csharp-build') {
		if (typeof code === 'string' && code.trim() !== '') {
			return { ok: true, code }
		}
		if (args !== undefined) {
			if (!isPlainObject(args)) {
				return {
					ok: false,
					code: '',
					error: 'Invalid field: args',
					hint: 'For language "csharp-build", args must be a JSON object when provided. Example: {"language":"csharp-build","args":{"mode":"dotnet","configuration":"Debug"}}.',
				}
			}
			return { ok: true, code: JSON.stringify(args) }
		}
		if (code === undefined || code === null || code === '') {
			return { ok: true, code: '' }
		}
		if (typeof code !== 'string') {
			return {
				ok: false,
				code: '',
				error: 'Invalid field: code',
				hint: 'For language "csharp-build", code is optional; when provided it must be a JSON string.',
			}
		}
		return { ok: true, code }
	}

	if (typeof code !== 'string' || code.trim() === '') {
		return {
			ok: false,
			code: '',
			error: 'Missing required field: code',
			hint: 'The request body must include a non-empty code field containing GDScript code. Example: {"code": "print(\\"hello\\")"}',
		}
	}
	return { ok: true, code }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function normalizeProjectPathForDisplay(projectPath: string): string {
	return projectPath.trim().replace(/\\/g, '/').replace(/\/+$/g, '')
}

function buildRuntimeStatusRecommendation(
	projectPath: string,
	editorExecutors: ExecutorInfo[],
	gameExecutors: ExecutorInfo[],
): RecommendedNextRequest {
	if (gameExecutors.length > 0) {
		return {
			method: 'POST',
			path: '/api/execute',
			body: {
				project_path: projectPath,
				type: 'game',
				language: 'csharp-command',
				command: 'runtime_status',
				args: {},
			},
			hint: 'The game executor is connected. Query runtime_status first, then inspect live runtime scene_tree/find_nodes/properties as needed.',
		}
	}
	if (editorExecutors.length > 0) {
		return {
			method: 'POST',
			path: '/api/execute',
			body: {
				project_path: projectPath,
				type: 'editor',
				language: 'csharp-command',
				command: 'game_executor_status',
				args: {},
			},
			hint: 'The editor executor is connected but no game executor is connected. Run game_executor_status first; if it reports project_change_required, explicitly call ensure_game_executor with allow_project_change:true before starting the game.',
		}
	}
	return {
		method: 'GET',
		path: '/api/executors',
		hint: 'No same-project executor is connected. List executors and verify the Godot editor plugin is enabled for the intended project.',
	}
}
