import { expect, test } from '@playwright/test'

const endpointPayloads: Record<string, unknown> = {
  '/overview': { ready: true, server_mode: 'ready' },
  '/status': { speech_backend: 'qwen3', resident_state: 'ready' },
  '/configuration': { active_runtime_speech_backend: 'qwen3' },
  '/playback/state': { state: 'idle' },
  '/playback/queue': { queue: [], active_requests: [], queue_type: 'playback' },
  '/generation/queue': { queue: [], active_requests: [], queue_type: 'generation' },
  '/requests': { requests: [{ request_id: 'request-1', operation: 'speech', state: 'queued' }] },
  '/generation/jobs': { jobs: [] },
  '/voices': { profiles: [{ profile_name: 'swift-signal' }] },
  '/text-profiles': { text_profiles: { stored_profiles: [] } },
  '/network-audio/destinations': [],
  '/network-audio/selection': { available_destination_count: 0 },
}

test('keeps one working navigation model and sends every control request', async ({ page }) => {
  const controlRequests: Array<{ method: string; path: string }> = []

  await page.route('**/*', async (route) => {
    const request = route.request()
    const url = new URL(request.url())
    const payload = endpointPayloads[url.pathname]
    const isControlRequest = request.method() !== 'GET' && url.pathname !== '/control-panel/'

    if (payload !== undefined && request.method() === 'GET') {
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify(payload) })
      return
    }

    if (isControlRequest) {
      controlRequests.push({ method: request.method(), path: url.pathname })
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true }) })
      return
    }

    await route.continue()
  })

  await page.goto('/')
  await expect(page.getByText('Playback control')).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Control panel sections' })).toHaveCount(0)
  await expect(page.getByRole('link')).toHaveCount(0)

  for (const [tab, heading] of [
    ['Profiles', 'Voice profiles'],
    ['Network', 'Network audio'],
    ['Raw state', 'Raw endpoint state'],
  ] as const) {
    await page.getByRole('tab', { name: tab }).click()
    await expect(page.getByText(heading)).toBeVisible()
  }

  await page.getByRole('tab', { name: 'Operations' }).click()
  for (const [label, path, method] of [
    ['Pause', '/playback/pause', 'POST'],
    ['Resume', '/playback/resume', 'POST'],
    ['Clear queue', '/playback/queue', 'DELETE'],
    ['Clear generation', '/generation/queue', 'DELETE'],
    ['Reload models', '/models/reload', 'POST'],
    ['Unload models', '/models/unload', 'POST'],
    ['Cancel', '/requests/request-1', 'DELETE'],
  ] as const) {
    await page.getByRole('button', { name: label }).click()
    await expect(page.getByText(`${label} accepted by the local server.`)).toBeVisible()
    await expect.poll(() => controlRequests).toContainEqual({ method, path })
  }
})
