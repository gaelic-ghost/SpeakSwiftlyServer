import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import App from '@/App'

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

function jsonResponse(value: unknown) {
  return new Response(JSON.stringify(value), {
    headers: { 'content-type': 'application/json' },
  })
}

describe('App', () => {
  const fetchMock = vi.fn()

  beforeEach(() => {
    Object.defineProperty(window, 'matchMedia', {
      writable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        matches: false,
        media: query,
        onchange: null,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
        dispatchEvent: vi.fn(),
      })),
    })
    fetchMock.mockImplementation((input: RequestInfo | URL) => {
      const path = String(input)
      return Promise.resolve(jsonResponse(endpointPayloads[path] ?? { ok: true }))
    })
    vi.stubGlobal('fetch', fetchMock)
  })

  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
    vi.clearAllMocks()
  })

  it('uses tabs as the single navigation pattern and reveals every section', async () => {
    const user = userEvent.setup()
    render(<App />)

    await screen.findByText('Playback control')
    expect(screen.queryByRole('navigation', { name: 'Control panel sections' })).toBeNull()
    expect(screen.queryByRole('link')).toBeNull()

    await user.click(screen.getByRole('tab', { name: 'Profiles' }))
    expect(await screen.findByText('Voice profiles')).toBeTruthy()

    await user.click(screen.getByRole('tab', { name: 'Network' }))
    expect(await screen.findByText('Network audio')).toBeTruthy()

    await user.click(screen.getByRole('tab', { name: 'Raw state' }))
    expect(await screen.findByText('Raw endpoint state')).toBeTruthy()
  })

  it('sends each visible control to its existing HTTP route', async () => {
    const user = userEvent.setup()
    render(<App />)

    await screen.findByRole('button', { name: 'Pause' })
    const actions = [
      ['Pause', '/playback/pause', 'POST'],
      ['Resume', '/playback/resume', 'POST'],
      ['Clear queue', '/playback/queue', 'DELETE'],
      ['Clear generation', '/generation/queue', 'DELETE'],
      ['Reload models', '/models/reload', 'POST'],
      ['Unload models', '/models/unload', 'POST'],
      ['Cancel', '/requests/request-1', 'DELETE'],
    ] as const

    for (const [label, path, method] of actions) {
      await user.click(screen.getByRole('button', { name: label }))
      await waitFor(() => {
        expect(fetchMock).toHaveBeenCalledWith(path, expect.objectContaining({ method }))
      })
      expect(await screen.findByText(`${label} accepted by the local server.`)).toBeTruthy()
    }
  })
})
