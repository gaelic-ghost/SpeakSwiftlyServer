import { describe, expect, it } from 'vitest'

import {
  describeValue,
  firstArray,
  firstRecord,
  formatDateTime,
  getArray,
  getBool,
  getNumber,
  getRecord,
  getString,
  isRecord,
  sectionValue,
} from '@/lib/shape'

describe('shape helpers', () => {
  it('extracts typed values without trusting arbitrary JSON shapes', () => {
    const source = {
      name: 'default',
      empty: '',
      count: 3,
      ready: true,
      nested: { state: 'ready' },
      rows: [{ id: 'one' }],
    }

    expect(isRecord(source)).toBe(true)
    expect(getString(source, 'name')).toBe('default')
    expect(getString(source, 'empty')).toBeNull()
    expect(getNumber(source, 'count')).toBe(3)
    expect(getBool(source, 'ready')).toBe(true)
    expect(getRecord(source, 'nested')).toEqual({ state: 'ready' })
    expect(getArray(source, 'rows')).toEqual([{ id: 'one' }])
  })

  it('finds the first useful array or record in flexible response payloads', () => {
    expect(firstArray({ metadata: { count: 1 }, requests: [{ id: 'queued' }] })).toEqual([{ id: 'queued' }])
    expect(firstArray(['direct'])).toEqual(['direct'])
    expect(firstRecord([null, 'skip', { id: 'first-record' }])).toEqual({ id: 'first-record' })
  })

  it('formats values for compact dashboard readouts', () => {
    expect(sectionValue({ value: { ready: true }, error: null, updatedAt: 'now' })).toEqual({ ready: true })
    expect(sectionValue(null)).toBeNull()
    expect(describeValue(null)).toBe('—')
    expect(describeValue(['a', 'b'])).toBe('2 items')
    expect(describeValue({ id: 'request-1', state: 'queued' })).toBe('request-1')
    expect(formatDateTime('not-a-date')).toBe('not-a-date')
  })
})
