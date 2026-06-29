import { describe, expect, it } from 'vitest'

import {
  describeValue,
  formatDateTime,
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
      nested: { state: 'ready' },
    }

    expect(isRecord(source)).toBe(true)
    expect(getString(source, 'name')).toBe('default')
    expect(getString(source, 'empty')).toBeNull()
    expect(getRecord(source, 'nested')).toEqual({ state: 'ready' })
  })

  it('formats values for compact control panel readouts', () => {
    expect(sectionValue({ value: { ready: true }, error: null, updatedAt: 'now' })).toEqual({ ready: true })
    expect(sectionValue(null)).toBeNull()
    expect(describeValue(null)).toBe('—')
    expect(describeValue(['a', 'b'])).toBe('2 items')
    expect(describeValue({ id: 'request-1', state: 'queued' })).toBe('request-1')
    expect(formatDateTime('not-a-date')).toBe('not-a-date')
  })
})
