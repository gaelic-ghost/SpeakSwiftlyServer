export type EndpointSection<T = unknown> = {
  value: T | null
  error: string | null
  updatedAt: string
}

export type ControlPanelSnapshot = {
  overview: EndpointSection
  status: EndpointSection
  configuration: EndpointSection
  playbackState: EndpointSection
  playbackQueue: EndpointSection
  generationQueue: EndpointSection
  requests: EndpointSection
  generationJobs: EndpointSection
  voices: EndpointSection
  textProfiles: EndpointSection
  networkDestinations: EndpointSection
  networkSelection: EndpointSection
}

const endpoints = {
  overview: '/overview',
  status: '/status',
  configuration: '/configuration',
  playbackState: '/playback/state',
  playbackQueue: '/playback/queue',
  generationQueue: '/generation/queue',
  requests: '/requests',
  generationJobs: '/generation/jobs',
  voices: '/voices',
  textProfiles: '/text-profiles',
  networkDestinations: '/network-audio/destinations',
  networkSelection: '/network-audio/selection',
} as const

export async function loadControlPanelSnapshot(): Promise<ControlPanelSnapshot> {
  const updatedAt = new Date().toISOString()
  let overview: unknown
  try {
    overview = await fetchJson(endpoints.overview)
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : `Request to ${endpoints.overview} failed.`
    return offlineSnapshot(message, updatedAt)
  }

  const entries = await Promise.all(
    Object.entries(endpoints).map(async ([name, path]) => {
      if (name === 'overview') {
        return [name, { value: overview, error: null, updatedAt }] as const
      }
      try {
        return [name, { value: await fetchJson(path), error: null, updatedAt }] as const
      } catch (caught) {
        return [
          name,
          {
            value: null,
            error: caught instanceof Error ? caught.message : `Request to ${path} failed.`,
            updatedAt,
          },
        ] as const
      }
    }),
  )

  return Object.fromEntries(entries) as ControlPanelSnapshot
}

export function pausePlayback() {
  return postJson('/playback/pause')
}

export function resumePlayback() {
  return postJson('/playback/resume')
}

export function clearPlaybackQueue() {
  return deleteJson('/playback/queue')
}

export function clearGenerationQueue() {
  return deleteJson('/generation/queue')
}

export function reloadModels() {
  return postJson('/models/reload')
}

export function unloadModels() {
  return postJson('/models/unload')
}

export function cancelRequest(requestID: string) {
  return deleteJson(`/requests/${encodeURIComponent(requestID)}`)
}

async function postJson(path: string) {
  return fetchJson(path, { method: 'POST' })
}

async function deleteJson(path: string) {
  return fetchJson(path, { method: 'DELETE' })
}

async function fetchJson(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(path, {
    headers: {
      accept: 'application/json',
      ...init?.headers,
    },
    ...init,
  })

  if (!response.ok) {
    const message = await response.text().catch(() => '')
    throw new Error(`HTTP ${response.status} from ${path}${message ? `: ${message}` : ''}`)
  }

  if (response.status === 204) {
    return null
  }

  const contentType = response.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    return response.text()
  }

  return response.json()
}

function offlineSnapshot(message: string, updatedAt: string): ControlPanelSnapshot {
  const offlineSection = { value: null, error: message, updatedAt }
  return {
    overview: offlineSection,
    status: offlineSection,
    configuration: offlineSection,
    playbackState: offlineSection,
    playbackQueue: offlineSection,
    generationQueue: offlineSection,
    requests: offlineSection,
    generationJobs: offlineSection,
    voices: offlineSection,
    textProfiles: offlineSection,
    networkDestinations: offlineSection,
    networkSelection: offlineSection,
  }
}
