import type { EndpointSection } from '@/lib/api'

export function sectionValue(section: EndpointSection | null | undefined) {
  return section?.value ?? null
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function getRecord(source: unknown, key: string) {
  if (!isRecord(source)) {
    return null
  }
  const value = source[key]
  return isRecord(value) ? value : null
}

export function getArray(source: unknown, key: string) {
  if (!isRecord(source)) {
    return []
  }
  const value = source[key]
  return Array.isArray(value) ? value : []
}

export function firstArray(source: unknown) {
  if (Array.isArray(source)) {
    return source
  }
  if (!isRecord(source)) {
    return null
  }
  return recordEntries(source)
    .map(([, value]) => value)
    .find((value): value is unknown[] => Array.isArray(value)) ?? null
}

export function firstRecord(source: unknown) {
  if (!Array.isArray(source)) {
    return null
  }
  return source.find(isRecord) ?? null
}

export function getString(source: unknown, key: string) {
  if (!isRecord(source)) {
    return null
  }
  const value = source[key]
  return typeof value === 'string' && value.trim() ? value : null
}

export function getNumber(source: unknown, key: string) {
  if (!isRecord(source)) {
    return null
  }
  const value = source[key]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

export function getBool(source: unknown, key: string) {
  if (!isRecord(source)) {
    return null
  }
  const value = source[key]
  return typeof value === 'boolean' ? value : null
}

export function recordEntries(source: Record<string, unknown>) {
  return Object.entries(source)
}

export function describeValue(value: unknown): string {
  if (value === null || value === undefined || value === '') {
    return '—'
  }
  if (typeof value === 'string') {
    return value
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value)
  }
  if (Array.isArray(value)) {
    return `${value.length} item${value.length === 1 ? '' : 's'}`
  }
  if (isRecord(value)) {
    const preferred = getString(value, 'name') ?? getString(value, 'id') ?? getString(value, 'state')
    return preferred ?? `${Object.keys(value).length} fields`
  }
  return String(value)
}

export function formatDateTime(value: unknown) {
  if (typeof value !== 'string' || !value.trim()) {
    return '—'
  }
  const timestamp = Date.parse(value)
  if (Number.isNaN(timestamp)) {
    return value
  }
  return new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(timestamp)
}
