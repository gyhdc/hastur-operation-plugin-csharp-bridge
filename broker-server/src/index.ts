import { Command } from 'commander'
import { ExecutorManager } from './executor-manager.js'
import { TcpServer } from './tcp-server.js'
import { createHttpApp } from './http-server.js'
import { resolveAuthToken } from './auth-token.js'

const program = new Command()

program
	.option('--tcp-port <port>', 'TCP port for executor connections', '5301')
	.option('--http-port <port>', 'HTTP port for API', '5302')
	.option('--host <host>', 'Host to bind to', 'localhost')
	.option('--auth-token <token>', 'Authentication token for HTTP API')
	.parse()

const options = program.opts()
const tcpPort = parseInt(options.tcpPort as string, 10)
const httpPort = parseInt(options.httpPort as string, 10)
const host = options.host as string

const authTokenResolution = resolveAuthToken({
	cliToken: options.authToken as string | undefined,
	envToken: process.env.HASTUR_AUTH_TOKEN,
})
const authToken = authTokenResolution.token

console.log(`Auth token source: ${authTokenResolution.source}`)
console.log(`Auth token: ${authToken}`)
console.log(`Copy for new Codex sessions: auth-token ${authToken}`)

const executorManager = new ExecutorManager()
const tcpServer = new TcpServer(executorManager)
const app = createHttpApp(executorManager, tcpServer, authToken, tcpPort, httpPort, {
	authTokenSource: authTokenResolution.source,
})

async function main(): Promise<void> {
	await tcpServer.start(host, tcpPort)
	console.log(`TCP server listening on ${host}:${tcpPort}`)

	const httpServer = app.listen(httpPort, host, () => {
		console.log(`HTTP server listening on ${host}:${httpPort}`)
	})

	const shutdown = async (): Promise<void> => {
		console.log('Shutting down...')
		await tcpServer.stop()
		httpServer.close()
		process.exit(0)
	}

	process.on('SIGINT', shutdown)
	process.on('SIGTERM', shutdown)
}

main().catch((err: unknown) => {
	console.error('Failed to start:', err)
	process.exit(1)
})
