import type { ExecutorEvent, ExecutorInfo } from './types.js'

export class ExecutorManager {
	private executors: Map<string, ExecutorInfo> = new Map()
	private recentEvents: ExecutorEvent[] = []
	private maxRecentEvents = 25

	add(executor: ExecutorInfo, reason = 'register'): void {
		this.executors.set(executor.id, executor)
		this.recordEvent('registered', executor, reason)
	}

	remove(id: string, reason = 'disconnect'): boolean {
		const executor = this.executors.get(id)
		const removed = this.executors.delete(id)
		if (executor) {
			this.recordEvent('disconnected', executor, reason)
		}
		return removed
	}

	get(id: string): ExecutorInfo | undefined {
		return this.executors.get(id)
	}

	getAll(): ExecutorInfo[] {
		return Array.from(this.executors.values())
	}

	findAllByProjectPath(path: string): ExecutorInfo[] {
		const normalized = normalizeProjectPath(path)
		return this.getAll().filter((executor) => (
			executor.status === 'connected'
			&& normalizeProjectPath(executor.project_path) === normalized
		))
	}

	getRecentEvents(): ExecutorEvent[] {
		return [...this.recentEvents]
	}

	findById(id: string): ExecutorInfo | undefined {
		return this.executors.get(id)
	}

	findByProjectName(name: string, type?: 'editor' | 'game'): ExecutorInfo | undefined {
		const lower = name.toLowerCase()
		for (const executor of this.executors.values()) {
			if (executor.project_name.toLowerCase().includes(lower) && executor.status === 'connected') {
				if (type && executor.type !== type) continue
				return executor
			}
		}
		return undefined
	}

	findByProjectPath(path: string, type?: 'editor' | 'game'): ExecutorInfo | undefined {
		const lower = path.toLowerCase()
		for (const executor of this.executors.values()) {
			if (executor.project_path.toLowerCase().includes(lower) && executor.status === 'connected') {
				if (type && executor.type !== type) continue
				return executor
			}
		}
		return undefined
	}

	private recordEvent(event: ExecutorEvent['event'], executor: ExecutorInfo, reason: string): void {
		this.recentEvents.push({
			timestamp: new Date().toISOString(),
			event,
			executor_id: executor.id,
			project_name: executor.project_name,
			project_path: executor.project_path,
			type: executor.type,
			reason,
		})
		if (this.recentEvents.length > this.maxRecentEvents) {
			this.recentEvents.splice(0, this.recentEvents.length - this.maxRecentEvents)
		}
	}
}

function normalizeProjectPath(path: string): string {
	return path.trim().replace(/\\/g, '/').replace(/\/+$/g, '').toLowerCase()
}
