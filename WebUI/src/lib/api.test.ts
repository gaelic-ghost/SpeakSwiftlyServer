import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  cancelRequest,
  clearGenerationQueue,
  clearPlaybackQueue,
  loadControlPanelData,
  pausePlayback,
  reloadModels,
  resumePlayback,
  unloadModels,
} from '@/lib/api'

function jsonResponse(value: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      ...init.headers,
    },
    ...init,
  })
}

describe('loadControlPanelData', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  it('loads overview first and keeps partial endpoint failures local to their sections', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-06-28T12:00:00Z'))
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const path = String(input)
      if (path === '/overview') {
        return jsonResponse({ ready: true })
      }
      if (path === '/playback/queue') {
        return new Response('queue unavailable', { status: 503 })
      }
      return jsonResponse({ path })
    })
    vi.stubGlobal('fetch', fetchMock)

    const data = await loadControlPanelData()

    expect(data.overview).toEqual({
      value: { ready: true },
      error: null,
      updatedAt: '2026-06-28T12:00:00.000Z',
    })
    expect(data.status.value).toEqual({ path: '/status' })
    expect(data.playbackQueue.value).toBeNull()
    expect(data.playbackQueue.error).toContain('HTTP 503 from /playback/queue')
    expect(data.generationQueue.error).toBeNull()
  })

  it('preserves existing endpoint response shapes without normalizing them', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-06-28T12:10:00Z'))
    const payloads: Record<string, unknown> = {
      '/overview': {
        server_mode: 'ready',
        worker_stage: 'resident_model_ready',
      },
      '/status': {
        speech_backend: 'qwen3_big_8bit',
        resident_state: 'ready',
      },
      '/configuration': {
        active_runtime_speech_backend: 'qwen3_big_8bit',
      },
      '/playback/state': {
        state: 'idle',
      },
      '/playback/queue': {
        queue: [{ request_id: 'queued-playback' }],
        active_requests: [],
        queue_type: 'playback',
      },
      '/generation/queue': {
        queue: [],
        active_requests: [{ request_id: 'active-generation' }],
        queue_type: 'generation',
      },
      '/requests': {
        requests: [{ request_id: 'retained-request' }],
      },
      '/generation/jobs': {
        jobs: [{ id: 'job-1' }],
      },
      '/voices': {
        profiles: [{ profile_name: 'swift-signal' }],
      },
      '/text-profiles': {
        text_profiles: {
          stored_profiles: [{ profile_id: 'default' }],
        },
      },
      '/network-audio/destinations': [
        {
          id: 'receiver-1',
          name: 'Receiver',
        },
      ],
      '/network-audio/selection': {
        available_destination_count: 1,
      },
    }
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: RequestInfo | URL) => jsonResponse(payloads[String(input)])),
    )

    const data = await loadControlPanelData()

    expect(data.playbackQueue.value?.queue).toEqual([{ request_id: 'queued-playback' }])
    expect(data.generationQueue.value?.active_requests).toEqual([{ request_id: 'active-generation' }])
    expect(data.requests.value?.requests).toEqual([{ request_id: 'retained-request' }])
    expect(data.voices.value?.profiles).toEqual([{ profile_name: 'swift-signal' }])
    expect(data.textProfiles.value?.text_profiles.stored_profiles).toEqual([{ profile_id: 'default' }])
    expect(data.networkDestinations.value).toEqual([{ id: 'receiver-1', name: 'Receiver' }])
  })

  it('returns an offline snapshot when overview cannot be loaded', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-06-28T12:05:00Z'))
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('connection refused')
      }),
    )

    const data = await loadControlPanelData()

    expect(data.overview.value).toBeNull()
    expect(data.overview.error).toBe('connection refused')
    expect(data.status.error).toBe('connection refused')
    expect(data.networkSelection.updatedAt).toBe('2026-06-28T12:05:00.000Z')
  })
})

describe('control route helpers', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it.each([
    ['pausePlayback', pausePlayback, '/playback/pause', 'POST'],
    ['resumePlayback', resumePlayback, '/playback/resume', 'POST'],
    ['clearPlaybackQueue', clearPlaybackQueue, '/playback/queue', 'DELETE'],
    ['clearGenerationQueue', clearGenerationQueue, '/generation/queue', 'DELETE'],
    ['reloadModels', reloadModels, '/models/reload', 'POST'],
    ['unloadModels', unloadModels, '/models/unload', 'POST'],
  ])('sends %s to the expected HTTP route', async (_name, action, path, method) => {
    const fetchMock = vi.fn(async () => jsonResponse({ ok: true }))
    vi.stubGlobal('fetch', fetchMock)

    await action()

    expect(fetchMock).toHaveBeenCalledWith(path, expect.objectContaining({ method }))
  })

  it('encodes request ids before cancellation', async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ cancelled: true }))
    vi.stubGlobal('fetch', fetchMock)

    await cancelRequest('request id/with slash')

    expect(fetchMock).toHaveBeenCalledWith(
      '/requests/request%20id%2Fwith%20slash',
      expect.objectContaining({ method: 'DELETE' }),
    )
  })
})
