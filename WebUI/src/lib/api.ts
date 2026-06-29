export type JsonPrimitive = string | number | boolean | null
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue | undefined }
export type JsonRecord = { [key: string]: JsonValue | undefined }

export type EndpointSection<T = JsonValue> = {
  value: T | null
  error: string | null
  updatedAt: string
}

export type QueueRequest = JsonRecord & {
  request_id?: string
  id?: string
  operation?: string
  purpose?: string
  kind?: string
  state?: string
  status?: string
  stage?: string
  updated_at?: string
  completed_at?: string
  submitted_at?: string
}

export type QueueSnapshotResponse = JsonRecord & {
  queue: QueueRequest[]
  active_requests: QueueRequest[]
  queue_type: string
  queued_requests?: QueueRequest[]
  queued_count?: number
  active_count?: number
}

export type StatusSnapshot = JsonRecord & {
  ready?: boolean
  server_mode?: string
  worker_stage?: string
  service?: string
  playback_queue?: QueueSnapshotResponse
  generation_queue?: QueueSnapshotResponse
  runtime_configuration?: RuntimeConfigurationSnapshot
  cached_profiles?: VoiceProfile[]
  network_audio_destinations?: NetworkAudioDestination[]
}

export type RuntimeStatusResponse = JsonRecord & {
  speech_backend?: string
  resident_state?: string
  state?: string
  default_voice_profile?: string | null
}

export type RuntimeConfigurationSnapshot = JsonRecord & {
  active_runtime_speech_backend?: string
  next_runtime_speech_backend?: string
  active_duck_media_volume?: string
  next_duck_media_volume?: string
  persisted_configuration_state?: string
  persisted_configuration_path?: string
  profile_root_path?: string
}

export type RequestListResponse = JsonRecord & {
  requests: QueueRequest[]
}

export type GenerationJobsResponse = JsonRecord

export type VoiceProfile = JsonRecord & {
  profile_name?: string
  name?: string
  id?: string
  kind?: string
  source?: string
  origin?: string
  manifest_version?: string | number
  version?: string | number
  updated_at?: string
  modified_at?: string
}

export type ProfileListResponse = JsonRecord & {
  profiles: VoiceProfile[]
}

export type TextProfileSummary = JsonRecord & {
  profile_id?: string
  id?: string
  name?: string
  display_name?: string
  kind?: string
  style?: string
}

export type TextProfilesResponse = JsonRecord & {
  text_profiles: JsonRecord & {
    stored_profiles?: TextProfileSummary[]
    active_profile?: TextProfileSummary
    effective_profile?: TextProfileSummary
    base_profile?: TextProfileSummary
    built_in_style?: string
  }
}

export type NetworkAudioDestination = JsonRecord & {
  id?: string
  name?: string
  endpoint?: JsonRecord
  capabilities?: JsonRecord
  last_seen?: string
}

export type NetworkAudioSelection = JsonRecord & {
  available_destination_count?: number
  lan_output_ready?: boolean
  selected_destination_endpoint_ready?: boolean
  shared_token_configured?: boolean
  lan_output_blocked_reasons?: string[]
}

export type ControlPanelData = {
  overview: EndpointSection<StatusSnapshot>
  status: EndpointSection<RuntimeStatusResponse>
  configuration: EndpointSection<RuntimeConfigurationSnapshot>
  playbackState: EndpointSection<JsonRecord>
  playbackQueue: EndpointSection<QueueSnapshotResponse>
  generationQueue: EndpointSection<QueueSnapshotResponse>
  requests: EndpointSection<RequestListResponse>
  generationJobs: EndpointSection<GenerationJobsResponse>
  voices: EndpointSection<ProfileListResponse>
  textProfiles: EndpointSection<TextProfilesResponse>
  networkDestinations: EndpointSection<NetworkAudioDestination[]>
  networkSelection: EndpointSection<NetworkAudioSelection>
}

const endpointPaths = {
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

type EndpointName = keyof typeof endpointPaths

type EndpointValue<Name extends EndpointName> = ControlPanelData[Name] extends EndpointSection<infer Value>
  ? Value
  : never

export async function loadControlPanelData(): Promise<ControlPanelData> {
  const updatedAt = new Date().toISOString()
  let overview: StatusSnapshot
  try {
    overview = await getOverview()
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : `Request to ${endpointPaths.overview} failed.`
    return offlineData(message, updatedAt)
  }

  const entries = await Promise.all(
    (Object.keys(endpointPaths) as EndpointName[]).map(async (name) => {
      if (name === 'overview') {
        return [name, okSection(overview, updatedAt)] as const
      }
      return [name, await loadEndpointSection(name, updatedAt)] as const
    }),
  )

  return Object.fromEntries(entries) as ControlPanelData
}

export function getOverview() {
  return fetchJson<StatusSnapshot>(endpointPaths.overview)
}

export function getStatus() {
  return fetchJson<RuntimeStatusResponse>(endpointPaths.status)
}

export function getConfiguration() {
  return fetchJson<RuntimeConfigurationSnapshot>(endpointPaths.configuration)
}

export function getPlaybackState() {
  return fetchJson<JsonRecord>(endpointPaths.playbackState)
}

export function getPlaybackQueue() {
  return fetchJson<QueueSnapshotResponse>(endpointPaths.playbackQueue)
}

export function getGenerationQueue() {
  return fetchJson<QueueSnapshotResponse>(endpointPaths.generationQueue)
}

export function getRequests() {
  return fetchJson<RequestListResponse>(endpointPaths.requests)
}

export function getGenerationJobs() {
  return fetchJson<GenerationJobsResponse>(endpointPaths.generationJobs)
}

export function getVoices() {
  return fetchJson<ProfileListResponse>(endpointPaths.voices)
}

export function getTextProfiles() {
  return fetchJson<TextProfilesResponse>(endpointPaths.textProfiles)
}

export function getNetworkDestinations() {
  return fetchJson<NetworkAudioDestination[]>(endpointPaths.networkDestinations)
}

export function getNetworkSelection() {
  return fetchJson<NetworkAudioSelection>(endpointPaths.networkSelection)
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

async function loadEndpointSection<Name extends EndpointName>(
  name: Name,
  updatedAt: string,
): Promise<EndpointSection<EndpointValue<Name>>> {
  try {
    const value = await fetchJson<EndpointValue<Name>>(endpointPaths[name])
    return okSection(value, updatedAt)
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : `Request to ${endpointPaths[name]} failed.`
    return { value: null, error: message, updatedAt }
  }
}

function okSection<T>(value: T, updatedAt: string): EndpointSection<T> {
  return { value, error: null, updatedAt }
}

async function postJson(path: string) {
  return fetchJson<JsonValue>(path, { method: 'POST' })
}

async function deleteJson(path: string) {
  return fetchJson<JsonValue>(path, { method: 'DELETE' })
}

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
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
    return null as T
  }

  const contentType = response.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    const bodyPreview = await response.text().catch(() => '')
    throw new Error(`Expected JSON from ${path}, received ${contentType || 'no content type'}${bodyPreview ? `: ${bodyPreview}` : ''}`)
  }

  return response.json() as Promise<T>
}

function offlineData(message: string, updatedAt: string): ControlPanelData {
  return {
    overview: offlineSection(message, updatedAt),
    status: offlineSection(message, updatedAt),
    configuration: offlineSection(message, updatedAt),
    playbackState: offlineSection(message, updatedAt),
    playbackQueue: offlineSection(message, updatedAt),
    generationQueue: offlineSection(message, updatedAt),
    requests: offlineSection(message, updatedAt),
    generationJobs: offlineSection(message, updatedAt),
    voices: offlineSection(message, updatedAt),
    textProfiles: offlineSection(message, updatedAt),
    networkDestinations: offlineSection(message, updatedAt),
    networkSelection: offlineSection(message, updatedAt),
  }
}

function offlineSection<T>(message: string, updatedAt: string): EndpointSection<T> {
  return { value: null, error: message, updatedAt }
}
