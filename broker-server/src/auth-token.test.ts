import assert from 'node:assert/strict'
import test from 'node:test'

import { resolveAuthToken } from './auth-token.js'

test('resolveAuthToken uses explicit CLI token first', () => {
	const result = resolveAuthToken({
		cliToken: 'cli-token',
		envToken: 'env-token',
		generateToken: () => 'generated-token',
	})

	assert.equal(result.token, 'cli-token')
	assert.equal(result.source, 'cli')
	assert.equal(result.generated, false)
})

test('resolveAuthToken falls back to environment token', () => {
	const result = resolveAuthToken({
		envToken: 'env-token',
		generateToken: () => 'generated-token',
	})

	assert.equal(result.token, 'env-token')
	assert.equal(result.source, 'env')
	assert.equal(result.generated, false)
})

test('resolveAuthToken ignores shell placeholders and generates a real token', () => {
	const result = resolveAuthToken({
		cliToken: '%HASTUR_AUTH_TOKEN%',
		generateToken: () => 'generated-token',
	})

	assert.equal(result.token, 'generated-token')
	assert.equal(result.source, 'generated')
	assert.equal(result.generated, true)
})
