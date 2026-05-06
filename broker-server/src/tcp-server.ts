import * as net from 'net'
import * as crypto from 'crypto'
import { ExecutorManager } from './executor-manager.js'
import type { ExecutorInfo, TcpMessage, ExecuteResult } from './types.js'

interface PendingRequest {
	resolve: (result: ExecuteResult) => void
	reject: (error: Error) => void
	timer: ReturnType<typeof setTimeout>
}

interface ConnectionContext {
	socket: net.Socket
	executorId: string | null
	lastMessageTime: number
	pingSent: boolean
	pingSentTime: number | null
	buffer: string
	pendingRequests: Map<string, PendingRequest>
}

export class TcpServer {
	private server: net.Server | null = null
	private executorManager: ExecutorManager
	private connections: Map<string, ConnectionContext> = new Map()
	private heartbeatInterval: ReturnType<typeof setInterval> | null = null

	constructor(executorManager: ExecutorManager) {
		this.executorManager = executorManager
	}

	async start(host: string, port: number): Promise<void> {
		this.server = net.createServer((socket) => this.handleConnection(socket))
		return new Promise((resolve) => {
			this.server!.listen(port, host, () => {
				this.startHeartbeatCheck()
				resolve()
			})
		})
	}

	async stop(): Promise<void> {
		if (this.heartbeatInterval) {
			clearInterval(this.heartbeatInterval)
			this.heartbeatInterval = null
		}

		for (const [, ctx] of this.connections) {
			for (const [, pending] of ctx.pendingRequests) {
				clearTimeout(pending.timer)
				pending.reject(new Error('Server shutting down'))
			}
			ctx.socket.destroy()
		}
		this.connections.clear()

		if (this.server) {
			return new Promise((resolve) => {
				this.server!.close(() => resolve())
			})
		}
	}

	sendExecute(executorId: string, code: string, language: string): Promise<ExecuteResult> {
		for (const [, ctx] of this.connections) {
			if (ctx.executorId === executorId) {
				const requestId = crypto.randomUUID()
				const message = JSON.stringify({
					type: 'execute',
					data: { request_id: requestId, code, language },
				}) + '\n'

				return new Promise((resolve, reject) => {
					const timer = setTimeout(() => {
						ctx.pendingRequests.delete(requestId)
						reject(new Error('TIMEOUT'))
					}, 30000)

					ctx.pendingRequests.set(requestId, { resolve, reject, timer })
					ctx.socket.write(message)
				})
			}
		}
		return Promise.reject(new Error('Executor not connected'))
	}

	getConnectedCount(): number {
		let count = 0
		for (const [, ctx] of this.connections) {
			if (ctx.executorId) count++
		}
		return count
	}

	private handleConnection(socket: net.Socket): void {
		const socketId = crypto.randomUUID()
		const ctx: ConnectionContext = {
			socket,
			executorId: null,
			lastMessageTime: Date.now(),
			pingSent: false,
			pingSentTime: null,
			buffer: '',
			pendingRequests: new Map(),
		}
		this.connections.set(socketId, ctx)

		socket.on('data', (data) => {
			ctx.buffer += data.toString()
			const lines = ctx.buffer.split('\n')
			ctx.buffer = lines.pop()!

			for (const line of lines) {
				if (line.trim()) {
					this.handleMessage(socketId, line.trim())
				}
			}
		})

		socket.on('close', () => {
			this.handleDisconnection(socketId)
		})

		socket.on('error', () => {
			// handled by close event
		})
	}

	private handleMessage(socketId: string, raw: string): void {
		const ctx = this.connections.get(socketId)
		if (!ctx) return

		ctx.lastMessageTime = Date.now()
		ctx.pingSent = false
		ctx.pingSentTime = null

		let message: TcpMessage
		try {
			message = JSON.parse(raw)
		} catch {
			return
		}

		switch (message.type) {
			case 'register':
				this.handleRegister(socketId, message.data as Record<string, unknown>)
				break
			case 'execute_result':
				this.handleExecuteResult(socketId, message.data as Record<string, unknown>)
				break
			case 'pong':
				break
		}
	}

	private handleRegister(socketId: string, data: Record<string, unknown>): void {
		const ctx = this.connections.get(socketId)
		if (!ctx) return

		const requiredFields = ['project_name', 'project_path', 'editor_pid', 'type']
		const missing = requiredFields.filter((f) => data[f] === undefined || data[f] === null || data[f] === '')
		if (missing.length > 0) {
			this.sendToSocket(socketId, {
				type: 'register_result',
				data: { success: false, error: `Missing required fields: ${missing.join(', ')}` },
			})
			return
		}

		const id = this.generateDeterministicId(
			data.project_name as string,
			data.project_path as string,
			data.editor_pid as number,
		)

		for (const [otherSocketId, otherCtx] of this.connections) {
			if (otherCtx.executorId === id && otherSocketId !== socketId) {
				for (const [, pending] of otherCtx.pendingRequests) {
					clearTimeout(pending.timer)
					pending.reject(new Error('Executor disconnected'))
				}
				otherCtx.socket.destroy()
				this.connections.delete(otherSocketId)
			}
		}

		ctx.executorId = id
		const executorInfo: ExecutorInfo = {
			id,
			project_name: data.project_name as string,
			project_path: data.project_path as string,
			editor_pid: data.editor_pid as number,
			plugin_version: (data.plugin_version as string) || '',
			editor_version: (data.editor_version as string) || '',
			supported_languages: (data.supported_languages as string[]) || [],
			connected_at: new Date().toISOString(),
			status: 'connected',
			type: (data.type as 'editor' | 'game') || 'editor',
		}
		this.executorManager.add(executorInfo, 'register message accepted')

		this.sendToSocket(socketId, {
			type: 'register_result',
			data: { success: true, id },
		})
	}

	private handleExecuteResult(socketId: string, data: Record<string, unknown>): void {
		const ctx = this.connections.get(socketId)
		if (!ctx) return

		const requestId = data.request_id as string
		const pending = ctx.pendingRequests.get(requestId)
		if (pending) {
			clearTimeout(pending.timer)
			ctx.pendingRequests.delete(requestId)
			pending.resolve(data as unknown as ExecuteResult)
		}
	}

	private handleDisconnection(socketId: string): void {
		const ctx = this.connections.get(socketId)
		if (!ctx) return

		if (ctx.executorId) {
			this.executorManager.remove(ctx.executorId, 'socket closed')
		}

		for (const [, pending] of ctx.pendingRequests) {
			clearTimeout(pending.timer)
			pending.reject(new Error('Executor disconnected'))
		}

		this.connections.delete(socketId)
	}

	private generateDeterministicId(projectName: string, projectPath: string, editorPid: number): string {
		const input = `${projectName}|${projectPath}|${editorPid}`
		const hash = crypto.createHash('sha256').update(input).digest('hex')
		return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`
	}

	private sendToSocket(socketId: string, message: TcpMessage): void {
		const ctx = this.connections.get(socketId)
		if (ctx && !ctx.socket.destroyed) {
			ctx.socket.write(JSON.stringify(message) + '\n')
		}
	}

	private startHeartbeatCheck(): void {
		this.heartbeatInterval = setInterval(() => {
			const now = Date.now()
			for (const [socketId, ctx] of this.connections) {
				if (!ctx.executorId) continue

				const idle = now - ctx.lastMessageTime
				if (idle > 60000) {
					if (ctx.pingSent && ctx.pingSentTime && now - ctx.pingSentTime > 10000) {
						ctx.socket.destroy()
					} else if (!ctx.pingSent) {
						ctx.pingSent = true
						ctx.pingSentTime = now
						this.sendToSocket(socketId, { type: 'ping' })
					}
				}
			}
		}, 5000)
	}
}
