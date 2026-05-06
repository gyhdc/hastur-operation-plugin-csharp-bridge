export interface ExecutorInfo {
	id: string
	project_name: string
	project_path: string
	editor_pid: number
	plugin_version: string
	editor_version: string
	supported_languages: string[]
	connected_at: string
	status: 'connected' | 'disconnected'
	type: 'editor' | 'game'
}

export interface ExecutorEvent {
	timestamp: string
	event: 'registered' | 'disconnected'
	executor_id: string
	project_name: string
	project_path: string
	type: 'editor' | 'game'
	reason: string
}

export interface RecommendedNextRequest {
	method: string
	path: string
	body?: Record<string, unknown>
	hint: string
}

export interface RuntimeExecutorStatus {
	project_path: string
	editor_connected: boolean
	game_connected: boolean
	editor_executors: ExecutorInfo[]
	game_executors: ExecutorInfo[]
	recommended_next_request: RecommendedNextRequest
}

export interface TcpMessage {
	type: string
	data?: unknown
}

export interface ExecuteRequest {
	request_id: string
	code: string
	language: string
}

export interface ExecuteResult {
	request_id: string
	compile_success: boolean
	compile_error: string
	run_success: boolean
	run_error: string
	outputs: [string, string][]
}

export interface ApiResponse {
	success: boolean
	error?: string
	hint?: string
	data?: unknown
}
