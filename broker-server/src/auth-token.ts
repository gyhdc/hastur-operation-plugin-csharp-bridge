import crypto from 'crypto'

export type AuthTokenSource = 'cli' | 'env' | 'generated'

export interface AuthTokenResolution {
	token: string
	source: AuthTokenSource
	generated: boolean
}

export interface ResolveAuthTokenOptions {
	cliToken?: string
	envToken?: string
	generateToken?: () => string
}

function normalizeToken(token: string | undefined): string {
	return token?.trim() ?? ''
}

function isShellPlaceholder(token: string): boolean {
	return token === '%HASTUR_AUTH_TOKEN%'
		|| token === '$HASTUR_AUTH_TOKEN'
		|| token === '${HASTUR_AUTH_TOKEN}'
}

export function resolveAuthToken(options: ResolveAuthTokenOptions = {}): AuthTokenResolution {
	const cliToken = normalizeToken(options.cliToken)
	if (cliToken && !isShellPlaceholder(cliToken)) {
		return { token: cliToken, source: 'cli', generated: false }
	}

	const envToken = normalizeToken(options.envToken)
	if (envToken && !isShellPlaceholder(envToken)) {
		return { token: envToken, source: 'env', generated: false }
	}

	const generateToken = options.generateToken ?? (() => crypto.randomBytes(32).toString('hex'))
	return {
		token: generateToken(),
		source: 'generated',
		generated: true,
	}
}
