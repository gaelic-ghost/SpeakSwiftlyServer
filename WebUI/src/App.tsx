import {
  ActivityIcon,
  AudioLinesIcon,
  BanIcon,
  CircleDotIcon,
  DatabaseIcon,
  FileAudioIcon,
  GaugeIcon,
  LoaderCircleIcon,
  Mic2Icon,
  PauseIcon,
  PlayIcon,
  RefreshCcwIcon,
  RotateCcwIcon,
  ServerIcon,
  Settings2Icon,
  Trash2Icon,
  WavesIcon,
} from 'lucide-react'
import { useMemo } from 'react'
import { toast } from 'sonner'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { cancelRequest, clearGenerationQueue, clearPlaybackQueue, pausePlayback, reloadModels, resumePlayback, unloadModels } from '@/lib/api'
import { describeValue, firstArray, firstRecord, formatDateTime, getArray, getBool, getNumber, getRecord, getString, isRecord, recordEntries, sectionValue } from '@/lib/shape'
import { useControlPanelSnapshot } from '@/hooks/use-control-panel-snapshot'

const navigationItems = [
  { label: 'Overview', icon: GaugeIcon },
  { label: 'Playback', icon: AudioLinesIcon },
  { label: 'Requests', icon: ActivityIcon },
  { label: 'Voices', icon: Mic2Icon },
  { label: 'Profiles', icon: FileAudioIcon },
  { label: 'Network', icon: WavesIcon },
  { label: 'Config', icon: Settings2Icon },
]

function App() {
  const { snapshot, loading, refreshing, error, refresh } = useControlPanelSnapshot()

  const overview = sectionValue(snapshot?.overview)
  const status = sectionValue(snapshot?.status)
  const configuration = sectionValue(snapshot?.configuration)
  const playbackState = sectionValue(snapshot?.playbackState)
  const playbackQueue = sectionValue(snapshot?.playbackQueue)
  const generationQueue = sectionValue(snapshot?.generationQueue)
  const requests = sectionValue(snapshot?.requests)
  const voices = sectionValue(snapshot?.voices)
  const textProfiles = sectionValue(snapshot?.textProfiles)
  const networkDestinations = sectionValue(snapshot?.networkDestinations)

  const ready = getBool(overview, 'ready') ?? getBool(status, 'ready') ?? false
  const health = getString(overview, 'health') ?? getString(status, 'health') ?? (ready ? 'ready' : 'starting')
  const backend = getString(status, 'speech_backend') ?? getString(configuration, 'speech_backend') ?? 'unknown'
  const activeRequest =
    getString(playbackState, 'active_request_id') ??
    getString(firstRecord(getArray(playbackQueue, 'active_requests')), 'request_id') ??
    'none'
  const playbackQueued = getNumber(playbackQueue, 'queued_count') ?? firstArray(playbackQueue)?.length ?? 0
  const generationQueued = getNumber(generationQueue, 'queued_count') ?? firstArray(generationQueue)?.length ?? 0
  const requestRows = extractRows(requests, ['requests', 'items', 'jobs']).slice(0, 8)
  const voiceRows = extractRows(voices, ['voices', 'profiles', 'items']).slice(0, 6)
  const profileRows = extractRows(textProfiles, ['stored_profiles', 'profiles', 'items']).slice(0, 5)
  const destinationRows = extractRows(networkDestinations, ['destinations', 'items']).slice(0, 5)

  const statusCards = useMemo<MetricCardProps[]>(
    () => [
      {
        label: 'Service',
        value: ready ? 'Ready' : humanize(health),
        detail: getString(overview, 'server_mode') ?? 'local runtime',
        tone: ready ? 'good' : 'warn',
        icon: ServerIcon,
      },
      {
        label: 'Backend',
        value: humanize(backend),
        detail: getString(status, 'runtime_state') ?? getString(status, 'state') ?? 'runtime state',
        tone: backend === 'unknown' ? 'muted' : 'good',
        icon: DatabaseIcon,
      },
      {
        label: 'Playback',
        value: activeRequest === 'none' ? 'Idle' : 'Active',
        detail: activeRequest,
        tone: activeRequest === 'none' ? 'muted' : 'good',
        icon: AudioLinesIcon,
      },
      {
        label: 'Queues',
        value: `${playbackQueued + generationQueued}`,
        detail: `${playbackQueued} playback / ${generationQueued} generation`,
        tone: playbackQueued + generationQueued > 0 ? 'warn' : 'muted',
        icon: ActivityIcon,
      },
    ],
    [activeRequest, backend, generationQueued, health, overview, playbackQueued, ready, status],
  )

  return (
    <TooltipProvider>
      <div className="min-h-svh bg-background text-foreground">
        <div className="control-shell">
          <aside className="control-rail">
            <div className="brand-mark">
              <CircleDotIcon aria-hidden="true" />
              <div>
                <p>Speak Swiftly</p>
                <span>Control</span>
              </div>
            </div>
            <nav aria-label="Control panel sections" className="rail-nav">
              {navigationItems.map((item) => (
                <a href={`#${item.label.toLowerCase()}`} key={item.label}>
                  <item.icon aria-hidden="true" />
                  <span>{item.label}</span>
                </a>
              ))}
            </nav>
          </aside>

          <main className="control-main">
            <header className="top-strip">
              <div>
                <p className="micro-label">Localhost operator surface</p>
                <h1>Speak Swiftly Control</h1>
              </div>
              <div className="top-actions">
                <StatusPip label={ready ? 'Ready' : 'Not ready'} tone={ready ? 'good' : 'warn'} />
                <Button variant="outline" size="sm" onClick={() => void refresh()} disabled={refreshing}>
                  {refreshing ? <LoaderCircleIcon data-icon="inline-start" className="animate-spin" /> : <RefreshCcwIcon data-icon="inline-start" />}
                  Refresh
                </Button>
              </div>
            </header>

            {error ? (
              <Alert variant="destructive">
                <BanIcon aria-hidden="true" />
                <AlertTitle>Control panel could not reach the local server.</AlertTitle>
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            ) : null}

            <section className="status-grid" aria-label="Runtime summary">
              {loading
                ? Array.from({ length: 4 }, (_, index) => <StatusSkeleton key={index} />)
                : statusCards.map((card) => <MetricCard key={card.label} {...card} />)}
            </section>

            <Tabs defaultValue="operations" className="flex flex-col gap-4">
              <TabsList>
                <TabsTrigger value="operations">Operations</TabsTrigger>
                <TabsTrigger value="profiles">Profiles</TabsTrigger>
                <TabsTrigger value="network">Network</TabsTrigger>
                <TabsTrigger value="raw">Raw state</TabsTrigger>
              </TabsList>

              <TabsContent value="operations" className="dashboard-grid">
                <Card id="playback">
                  <CardHeader>
                    <CardTitle>Playback control</CardTitle>
                    <CardDescription>Active output, queue depth, and safe local controls.</CardDescription>
                  </CardHeader>
                  <CardContent className="panel-stack">
                    <div className="segmented-readout">
                      <Readout label="Active request" value={activeRequest} />
                      <Readout label="Queued" value={String(playbackQueued)} />
                      <Readout label="State" value={describeValue(getString(playbackState, 'state'))} />
                    </div>
                    <div className="action-row">
                      <ControlButton action={pausePlayback} label="Pause" icon={PauseIcon} after={refresh} />
                      <ControlButton action={resumePlayback} label="Resume" icon={PlayIcon} after={refresh} />
                      <ControlButton action={clearPlaybackQueue} label="Clear queue" icon={Trash2Icon} after={refresh} destructive />
                    </div>
                    <Progress value={Math.min(100, playbackQueued * 18)} aria-label="Playback queue pressure" />
                  </CardContent>
                </Card>

                <Card id="requests" className="wide-card">
                  <CardHeader>
                    <CardTitle>Recent requests</CardTitle>
                    <CardDescription>Retained jobs and active work visible through the HTTP request cache.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <DataTable
                      emptyLabel="No retained requests returned by /requests."
                      rows={requestRows}
                      columns={[
                        { label: 'Request', keys: ['request_id', 'id'] },
                        { label: 'Operation', keys: ['operation', 'purpose', 'kind'] },
                        { label: 'State', keys: ['state', 'status', 'stage'] },
                        { label: 'Updated', keys: ['updated_at', 'completed_at', 'submitted_at'], formatter: formatDateTime },
                      ]}
                      rowAction={(row) => {
                        const requestID = getString(row, 'request_id') ?? getString(row, 'id')
                        return requestID ? (
                          <ControlButton
                            action={() => cancelRequest(requestID)}
                            label="Cancel"
                            icon={BanIcon}
                            after={refresh}
                            destructive
                            compact
                          />
                        ) : null
                      }}
                    />
                  </CardContent>
                </Card>

                <Card id="generation">
                  <CardHeader>
                    <CardTitle>Generation queue</CardTitle>
                    <CardDescription>File and batch generation pressure.</CardDescription>
                  </CardHeader>
                  <CardContent className="panel-stack">
                    <div className="segmented-readout">
                      <Readout label="Queued" value={String(generationQueued)} />
                      <Readout label="Updated" value={formatDateTime(getString(generationQueue, 'refreshed_at'))} />
                    </div>
                    <div className="action-row">
                      <ControlButton action={clearGenerationQueue} label="Clear generation" icon={Trash2Icon} after={refresh} destructive />
                    </div>
                  </CardContent>
                </Card>

                <Card id="configuration">
                  <CardHeader>
                    <CardTitle>Runtime controls</CardTitle>
                    <CardDescription>Model lifecycle controls exposed by existing HTTP routes.</CardDescription>
                  </CardHeader>
                  <CardContent className="panel-stack">
                    <div className="action-row">
                      <ControlButton action={reloadModels} label="Reload models" icon={RotateCcwIcon} after={refresh} />
                      <ControlButton action={unloadModels} label="Unload models" icon={BanIcon} after={refresh} destructive />
                    </div>
                    <KeyValueList source={configuration} keys={['speech_backend', 'duck_media_volume', 'default_voice_profile_name']} />
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="profiles" className="dashboard-grid">
                <Card id="voices" className="wide-card">
                  <CardHeader>
                    <CardTitle>Voice profiles</CardTitle>
                    <CardDescription>Cached voice profile inventory from /voices.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <DataTable
                      emptyLabel="No voice profiles returned by /voices."
                      rows={voiceRows}
                      columns={[
                        { label: 'Name', keys: ['profile_name', 'name', 'id'] },
                        { label: 'Kind', keys: ['kind', 'source', 'origin'] },
                        { label: 'Version', keys: ['manifest_version', 'version'] },
                        { label: 'Updated', keys: ['updated_at', 'modified_at'], formatter: formatDateTime },
                      ]}
                    />
                  </CardContent>
                </Card>

                <Card id="profiles">
                  <CardHeader>
                    <CardTitle>Text profiles</CardTitle>
                    <CardDescription>Stored and active text-normalization state.</CardDescription>
                  </CardHeader>
                  <CardContent className="panel-stack">
                    <KeyValueList source={textProfiles} keys={['active_profile_id', 'active_style', 'base_profile_id']} />
                    <Separator />
                    <DataTable
                      emptyLabel="No stored text profiles returned."
                      rows={profileRows}
                      columns={[
                        { label: 'Profile', keys: ['profile_id', 'id', 'name'] },
                        { label: 'Name', keys: ['name', 'display_name'] },
                        { label: 'Kind', keys: ['kind', 'style'] },
                      ]}
                    />
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="network" className="dashboard-grid">
                <Card id="network" className="wide-card">
                  <CardHeader>
                    <CardTitle>Network audio</CardTitle>
                    <CardDescription>Destination discovery and selected LAN output state.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <DataTable
                      emptyLabel="No network-audio destinations returned."
                      rows={destinationRows}
                      columns={[
                        { label: 'Destination', keys: ['name', 'destination_id', 'id'] },
                        { label: 'State', keys: ['state', 'readiness', 'status'] },
                        { label: 'Endpoint', keys: ['endpoint', 'host_port', 'base_url'] },
                        { label: 'Updated', keys: ['updated_at', 'last_seen_at'], formatter: formatDateTime },
                      ]}
                    />
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="raw" className="dashboard-grid">
                <Card className="wide-card">
                  <CardHeader>
                    <CardTitle>Raw endpoint state</CardTitle>
                    <CardDescription>Compact JSON snapshots for diagnostics without new API shaping.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <ScrollArea className="raw-state">
                      <pre>{JSON.stringify(snapshot, null, 2)}</pre>
                    </ScrollArea>
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </main>
        </div>
      </div>
      <Toaster richColors position="bottom-right" />
    </TooltipProvider>
  )
}

type Tone = 'good' | 'warn' | 'danger' | 'muted'

function StatusPip({ label, tone }: { label: string; tone: Tone }) {
  return <Badge data-tone={tone}>{label}</Badge>
}

type MetricCardProps = {
  label: string
  value: string
  detail: string
  tone: Tone
  icon: typeof ServerIcon
}

function MetricCard({
  label,
  value,
  detail,
  tone,
  icon: Icon,
}: MetricCardProps) {
  return (
    <Card className="metric-card" data-tone={tone}>
      <CardContent>
        <Icon aria-hidden="true" />
        <div>
          <p>{label}</p>
          <strong>{value}</strong>
          <span>{detail}</span>
        </div>
      </CardContent>
    </Card>
  )
}

function StatusSkeleton() {
  return (
    <Card className="metric-card">
      <CardContent>
        <Skeleton className="size-10" />
        <div className="flex flex-1 flex-col gap-2">
          <Skeleton className="h-3 w-20" />
          <Skeleton className="h-6 w-28" />
          <Skeleton className="h-3 w-full" />
        </div>
      </CardContent>
    </Card>
  )
}

function Readout({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function ControlButton({
  action,
  after,
  label,
  icon: Icon,
  destructive = false,
  compact = false,
}: {
  action: () => Promise<unknown>
  after: () => Promise<void>
  label: string
  icon: typeof ServerIcon
  destructive?: boolean
  compact?: boolean
}) {
  return (
    <Button
      variant={destructive ? 'destructive' : 'outline'}
      size={compact ? 'sm' : 'default'}
      onClick={() => {
        void action()
          .then(() => {
            toast.success(`${label} accepted by the local server.`)
            return after()
          })
          .catch((caught: unknown) => {
            toast.error(caught instanceof Error ? caught.message : `${label} failed.`)
          })
      }}
    >
      <Icon data-icon="inline-start" />
      {label}
    </Button>
  )
}

type Column = {
  label: string
  keys: string[]
  formatter?: (value: unknown) => string
}

function DataTable({
  rows,
  columns,
  emptyLabel,
  rowAction,
}: {
  rows: Record<string, unknown>[]
  columns: Column[]
  emptyLabel: string
  rowAction?: (row: Record<string, unknown>) => React.ReactNode
}) {
  if (rows.length === 0) {
    return <p className="empty-copy">{emptyLabel}</p>
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          {columns.map((column) => (
            <TableHead key={column.label}>{column.label}</TableHead>
          ))}
          {rowAction ? <TableHead>Action</TableHead> : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((row, index) => (
          <TableRow key={`${getString(row, 'id') ?? getString(row, 'request_id') ?? index}`}>
            {columns.map((column) => (
              <TableCell key={column.label}>
                {formatCell(row, column)}
              </TableCell>
            ))}
            {rowAction ? <TableCell>{rowAction(row)}</TableCell> : null}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

function KeyValueList({ source, keys }: { source: unknown; keys: string[] }) {
  if (!isRecord(source)) {
    return <p className="empty-copy">This endpoint did not return object-shaped state.</p>
  }

  return (
    <dl className="key-values">
      {keys.map((key) => (
        <div key={key}>
          <dt>{humanize(key)}</dt>
          <dd>{describeValue(source[key])}</dd>
        </div>
      ))}
    </dl>
  )
}

function extractRows(source: unknown, keys: string[]): Record<string, unknown>[] {
  if (Array.isArray(source)) {
    return source.filter(isRecord)
  }
  if (!isRecord(source)) {
    return []
  }
  for (const key of keys) {
    const value = source[key]
    if (Array.isArray(value)) {
      return value.filter(isRecord)
    }
  }
  const nested = recordEntries(source)
    .map(([, value]) => value)
    .find((value) => Array.isArray(value))
  return Array.isArray(nested) ? nested.filter(isRecord) : []
}

function formatCell(row: Record<string, unknown>, column: Column) {
  for (const key of column.keys) {
    const direct = row[key]
    if (direct !== undefined && direct !== null && direct !== '') {
      return column.formatter ? column.formatter(direct) : describeValue(direct)
    }
    const nested = getRecord(row, key)
    if (nested) {
      return describeValue(nested)
    }
  }
  return '—'
}

function humanize(value: string) {
  return value
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

export default App
