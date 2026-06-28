import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  cancelRequest,
  clearGenerationQueue,
  clearPlaybackQueue,
  loadControlPanelSnapshot,
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

describe('loadControlPanelSnapshot', () => {
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

    const snapshot = await loadControlPanelSnapshot()

    expect(snapshot.overview).toEqual({
      value: { ready: true },
      error: null,
      updatedAt: '2026-06-28T12:00:00.000Z',
    })
    expect(snapshot.status.value).toEqual({ path: '/status' })
    expect(snapshot.playbackQueue.value).toBeNull()
    expect(snapshot.playbackQueue.error).toContain('HTTP 503 from /playback/queue')
    expect(snapshot.generationQueue.error).toBeNull()
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

    const snapshot = await loadControlPanelSnapshot()

    expect(snapshot.overview.value).toBeNull()
    expect(snapshot.overview.error).toBe('connection refused')
    expect(snapshot.status.error).toBe('connection refused')
    expect(snapshot.networkSelection.updatedAt).toBe('2026-06-28T12:05:00.000Z')
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
