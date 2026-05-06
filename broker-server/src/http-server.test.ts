import assert from 'node:assert/strict'
import { once } from 'node:events'
import { createServer, type Server } from 'node:http'
import test from 'node:test'

import { ExecutorManager } from './executor-manager.js'
import { createHttpApp } from './http-server.js'
import type { TcpServer } from './tcp-server.js'
import type { ExecuteResult, ExecutorInfo } from './types.js'

const AUTH_TOKEN = 'test-token'

interface CapturedExecuteCall {
	executorId: string
	code: string
	language: string
}

function makeExecutor(overrides: Partial<ExecutorInfo> = {}): ExecutorInfo {
	return {
		id: 'exec-1',
		project_name: 'DemoProject',
		project_path: 'E:/DemoProject',
		editor_pid: 1234,
		plugin_version: '0.1',
		editor_version: '4.6.2',
		supported_languages: ['gdscript'],
		connected_at: new Date(0).toISOString(),
		status: 'connected',
		type: 'editor',
		...overrides,
	}
}

async function startTestServer(languages: string[], extraExecutors: ExecutorInfo[] = []) {
	const executorManager = new ExecutorManager()
	executorManager.add(makeExecutor({ supported_languages: languages }))
	for (const executor of extraExecutors) {
		executorManager.add(executor)
	}

	const calls: CapturedExecuteCall[] = []
	const tcpServer = {
		getConnectedCount: (): number => executorManager.getAll().length,
		sendExecute: async (executorId: string, code: string, language: string): Promise<ExecuteResult> => {
			calls.push({ executorId, code, language })
			return {
				request_id: 'request-1',
				compile_success: true,
				compile_error: '',
				run_success: true,
				run_error: '',
				outputs: [['ok', language]],
			}
		},
	} as TcpServer

	const app = createHttpApp(executorManager, tcpServer, AUTH_TOKEN, 5301, 5302, { authTokenSource: 'test' })
	const server = createServer(app)
	server.listen(0, '127.0.0.1')
	await once(server, 'listening')
	const address = server.address()
	assert(address && typeof address === 'object')

	return {
		baseUrl: `http://127.0.0.1:${address.port}`,
		calls,
		close: () => new Promise<void>((resolve, reject) => {
			server.close((error?: Error) => {
				if (error) reject(error)
				else resolve()
			})
		}),
	}
}

async function postExecute(baseUrl: string, body: Record<string, unknown>) {
	return fetch(`${baseUrl}/api/execute`, {
		method: 'POST',
		headers: {
			authorization: `Bearer ${AUTH_TOKEN}`,
			'content-type': 'application/json',
		},
		body: JSON.stringify(body),
	})
}

async function getRuntimeStatus(baseUrl: string, projectPath: string, includeAuth = true) {
	return fetch(`${baseUrl}/api/executors/runtime-status?project_path=${encodeURIComponent(projectPath)}`, {
		headers: includeAuth ? { authorization: `Bearer ${AUTH_TOKEN}` } : undefined,
	})
}

test('POST /api/execute keeps legacy requests on gdscript by default', async () => {
	const server = await startTestServer(['gdscript'])
	try {
		const response = await postExecute(server.baseUrl, {
			code: 'executeContext.output("hello", "world")',
			executor_id: 'exec-1',
		})

		assert.equal(response.status, 200)
		assert.equal(server.calls.length, 1)
		assert.equal(server.calls[0].language, 'gdscript')
	} finally {
		await server.close()
	}
})

test('POST /api/execute forwards the requested supported language', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await postExecute(server.baseUrl, {
			code: '{"command":"project_info","args":{}}',
			executor_id: 'exec-1',
			language: 'csharp-command',
		})

		assert.equal(response.status, 200)
		assert.equal(server.calls.length, 1)
		assert.equal(server.calls[0].language, 'csharp-command')
	} finally {
		await server.close()
	}
})

test('POST /api/execute accepts direct csharp-command command and args fields', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await postExecute(server.baseUrl, {
			command: 'scene_tree',
			args: { scope: 'edited', max_depth: 2 },
			executor_id: 'exec-1',
			language: 'csharp-command',
		})

		assert.equal(response.status, 200)
		assert.equal(server.calls.length, 1)
		assert.equal(server.calls[0].language, 'csharp-command')
		assert.equal(server.calls[0].code, '{"command":"scene_tree","args":{"scope":"edited","max_depth":2}}')
	} finally {
		await server.close()
	}
})

test('POST /api/execute accepts empty csharp-build body', async () => {
	const server = await startTestServer(['gdscript', 'csharp-build'])
	try {
		const response = await postExecute(server.baseUrl, {
			executor_id: 'exec-1',
			language: 'csharp-build',
		})

		assert.equal(response.status, 200)
		assert.equal(server.calls.length, 1)
		assert.equal(server.calls[0].language, 'csharp-build')
		assert.equal(server.calls[0].code, '')
	} finally {
		await server.close()
	}
})

test('POST /api/execute accepts direct csharp-build args object', async () => {
	const server = await startTestServer(['gdscript', 'csharp-build'])
	try {
		const response = await postExecute(server.baseUrl, {
			args: { mode: 'dotnet', configuration: 'Release', csproj: 'Demo.csproj' },
			executor_id: 'exec-1',
			language: 'csharp-build',
		})

		assert.equal(response.status, 200)
		assert.equal(server.calls.length, 1)
		assert.equal(server.calls[0].language, 'csharp-build')
		assert.equal(server.calls[0].code, '{"mode":"dotnet","configuration":"Release","csproj":"Demo.csproj"}')
	} finally {
		await server.close()
	}
})

test('POST /api/execute rejects non-object csharp-build args', async () => {
	const server = await startTestServer(['gdscript', 'csharp-build'])
	try {
		const response = await postExecute(server.baseUrl, {
			args: ['bad'],
			executor_id: 'exec-1',
			language: 'csharp-build',
		})
		const body = await response.json() as { success: boolean; error: string; hint: string }

		assert.equal(response.status, 400)
		assert.equal(body.success, false)
		assert.match(body.error, /Invalid field: args/)
		assert.match(body.hint, /csharp-build/)
		assert.equal(server.calls.length, 0)
	} finally {
		await server.close()
	}
})

test('POST /api/execute rejects languages not advertised by the executor', async () => {
	const server = await startTestServer(['gdscript'])
	try {
		const response = await postExecute(server.baseUrl, {
			code: '{"command":"project_info","args":{}}',
			executor_id: 'exec-1',
			language: 'csharp-command',
		})
		const body = await response.json() as { success: boolean; error: string; hint: string }

		assert.equal(response.status, 400)
		assert.equal(body.success, false)
		assert.match(body.error, /Unsupported language/)
		assert.match(body.hint, /gdscript/)
		assert.deepEqual((body as { data?: { supported_languages?: string[] } }).data?.supported_languages, ['gdscript'])
		assert.equal(server.calls.length, 0)
	} finally {
		await server.close()
	}
})

test('GET /api/diagnostics reports broker and executor capability state', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command', 'csharp-build'])
	try {
		const response = await fetch(`${server.baseUrl}/api/diagnostics`, {
			headers: {
				authorization: `Bearer ${AUTH_TOKEN}`,
			},
		})
		const body = await response.json() as {
			success: boolean
			data: {
				status: string
				tcp_port: number
				http_port: number
				executors_connected: number
				languages: string[]
				auth_token_source: string
				copy_hint: string
			}
		}

		assert.equal(response.status, 200)
		assert.equal(body.success, true)
		assert.equal(body.data.status, 'ok')
		assert.equal(body.data.tcp_port, 5301)
		assert.equal(body.data.http_port, 5302)
		assert.equal(body.data.executors_connected, 1)
		assert.deepEqual(body.data.languages, ['csharp-build', 'csharp-command', 'gdscript'])
		assert.equal(body.data.auth_token_source, 'test')
		assert.match(body.data.copy_hint, /auth-token/)
		assert.doesNotMatch(body.data.copy_hint, new RegExp(AUTH_TOKEN))
	} finally {
		await server.close()
	}
})

test('GET /api/executors/runtime-status requires auth', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await getRuntimeStatus(server.baseUrl, 'E:/DemoProject', false)
		const body = await response.json() as { success: boolean; error: string }

		assert.equal(response.status, 401)
		assert.equal(body.success, false)
		assert.match(body.error, /Authentication required/)
	} finally {
		await server.close()
	}
})

test('GET /api/executors/runtime-status validates project_path', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await fetch(`${server.baseUrl}/api/executors/runtime-status`, {
			headers: {
				authorization: `Bearer ${AUTH_TOKEN}`,
			},
		})
		const body = await response.json() as { success: boolean; error: string; hint: string }

		assert.equal(response.status, 400)
		assert.equal(body.success, false)
		assert.match(body.error, /project_path/)
		assert.match(body.hint, /project_path/)
	} finally {
		await server.close()
	}
})

test('GET /api/executors/runtime-status reports editor-only project state', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await getRuntimeStatus(server.baseUrl, 'E:\\DemoProject')
		const body = await response.json() as {
			success: boolean
			data: {
				project_path: string
				editor_connected: boolean
				game_connected: boolean
				editor_executors: ExecutorInfo[]
				game_executors: ExecutorInfo[]
				recommended_next_request: { method: string; path: string; body: Record<string, unknown> }
			}
		}

		assert.equal(response.status, 200)
		assert.equal(body.success, true)
		assert.equal(body.data.project_path, 'E:/DemoProject')
		assert.equal(body.data.editor_connected, true)
		assert.equal(body.data.game_connected, false)
		assert.equal(body.data.editor_executors.length, 1)
		assert.equal(body.data.game_executors.length, 0)
		assert.equal(body.data.recommended_next_request.method, 'POST')
		assert.equal(body.data.recommended_next_request.path, '/api/execute')
		assert.equal(body.data.recommended_next_request.body.type, 'editor')
		assert.equal(body.data.recommended_next_request.body.command, 'game_executor_status')
	} finally {
		await server.close()
	}
})

test('GET /api/executors/runtime-status reports editor and game project state', async () => {
	const gameExecutor = makeExecutor({
		id: 'exec-game',
		type: 'game',
		editor_pid: 2345,
		supported_languages: ['gdscript', 'csharp-command'],
		connected_at: new Date(1).toISOString(),
	})
	const server = await startTestServer(['gdscript', 'csharp-command'], [gameExecutor])
	try {
		const response = await getRuntimeStatus(server.baseUrl, 'E:/DemoProject')
		const body = await response.json() as {
			success: boolean
			data: {
				editor_connected: boolean
				game_connected: boolean
				editor_executors: ExecutorInfo[]
				game_executors: ExecutorInfo[]
				recommended_next_request: { method: string; path: string; body: Record<string, unknown> }
			}
		}

		assert.equal(response.status, 200)
		assert.equal(body.success, true)
		assert.equal(body.data.editor_connected, true)
		assert.equal(body.data.game_connected, true)
		assert.equal(body.data.editor_executors.length, 1)
		assert.equal(body.data.game_executors.length, 1)
		assert.equal(body.data.recommended_next_request.body.type, 'game')
		assert.equal(body.data.recommended_next_request.body.command, 'runtime_status')
	} finally {
		await server.close()
	}
})

test('GET /api/executors/runtime-status reports no matching project', async () => {
	const server = await startTestServer(['gdscript', 'csharp-command'])
	try {
		const response = await getRuntimeStatus(server.baseUrl, 'E:/MissingProject')
		const body = await response.json() as {
			success: boolean
			hint: string
			data: {
				editor_connected: boolean
				game_connected: boolean
				editor_executors: ExecutorInfo[]
				game_executors: ExecutorInfo[]
				recommended_next_request: { method: string; path: string }
			}
		}

		assert.equal(response.status, 200)
		assert.equal(body.success, true)
		assert.equal(body.data.editor_connected, false)
		assert.equal(body.data.game_connected, false)
		assert.equal(body.data.editor_executors.length, 0)
		assert.equal(body.data.game_executors.length, 0)
		assert.equal(body.data.recommended_next_request.method, 'GET')
		assert.equal(body.data.recommended_next_request.path, '/api/executors')
		assert.match(body.hint, /No connected/)
	} finally {
		await server.close()
	}
})
