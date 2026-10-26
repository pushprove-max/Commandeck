export type Since = string | null

// The units mod's state (hooks/units-sources.ts holds the same shapes; this file must not import).
export type UnitsSeat = 'done' | 'running' | null
export type UnitsCosts = { plan: number; build: number; review: number; fix: number; total: number }
export type UnitsRow = {
  unit: string; stage: string; round: number | null; verdict: string | null; verdictRound: number | null; findings: string; usd: number
  ageSec: number | null; red: boolean; issues: number | null; built: number | null; startedAt: number | null
  closes: string[]; costs: UnitsCosts; plan: UnitsSeat; judges: UnitsSeat
}
export type UnitsProgress = { done: number; failed: number; firstFail: string | null }
export type UnitsState = {
  now: number
  snap: { note: string | null; staleMin: number | null; rows: UnitsRow[]; merged: string[]; mergedAt: { unit: string; at: number }[]; chain: null; finishedUsd: Record<string, number> }
  merges: { unit: string; status: 'running' | 'stopped' | 'refused'; m: UnitsProgress & { step: string | null; total: number | null; refused: { step: string; reason: string } | null; ended: boolean }; elapsedSec: number }[]
  tests: { owner: string; kind: string; p: UnitsProgress; total: number | null; elapsedSec: number }[]
  notes: { merges: string[]; tests: string[] }
}

declare module 'claude-code' {
  interface PluginState {
    commandeck: {
      autoDecideSince: Since
      autoDecideCount: number
      // What the units mod draws, and which of its band, pane and status line are on.
      unitsState: UnitsState | null
      unitsView: { band: boolean; pane: boolean; status: boolean }
    }
  }
}
