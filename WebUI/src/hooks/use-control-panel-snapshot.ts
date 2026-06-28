import { useCallback, useEffect, useState } from 'react'

import { loadControlPanelSnapshot, type ControlPanelSnapshot } from '@/lib/api'

type SnapshotState = {
  snapshot: ControlPanelSnapshot | null
  loading: boolean
  refreshing: boolean
  error: string | null
}

export function useControlPanelSnapshot() {
  const [state, setState] = useState<SnapshotState>({
    snapshot: null,
    loading: true,
    refreshing: false,
    error: null,
  })

  const refresh = useCallback(async () => {
    setState((current) => ({ ...current, refreshing: true, error: null }))
    try {
      const snapshot = await loadControlPanelSnapshot()
      setState({
        snapshot,
        loading: false,
        refreshing: false,
        error: snapshot.overview.error ?? null,
      })
    } catch (caught) {
      setState((current) => ({
        ...current,
        loading: false,
        refreshing: false,
        error: caught instanceof Error ? caught.message : 'Speak Swiftly Control could not load server state.',
      }))
    }
  }, [])

  useEffect(() => {
    void refresh()
    const intervalID = window.setInterval(() => {
      void refresh()
    }, 5000)
    return () => window.clearInterval(intervalID)
  }, [refresh])

  return {
    ...state,
    refresh,
  }
}
