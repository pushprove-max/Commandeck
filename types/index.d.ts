export type Since = string | null

// The units mod's state (hooks/units-sources.ts holds the same shapes; this file must not import).
export type UnitsSeat = 'done' | 'running' | null
export type UnitsCosts = { plan: number; build: number; review: number; fix: number; total: number }
export type UnitsRow = {
  unit: string; stage: string; round: number | null; verdict: string | null; verdictRound: number | null; findings: string; usd: number
  ageSec: number | null; red: boolean; issues: number | null; built: number | null; startedAt: number | null
  closes: string[]; costs: UnitsCosts; plan: UnitsSeat; judges: UnitsSeat
  model: string | null; effort: string | null; working: boolean; stageSince: number | null
  // #555; undefined: the snapshot lacks the key, null: the collector failed.
  context?: UnitsCtx | null; compactions?: number | null; rounds?: UnitsDot[]; judgeRounds?: UnitsDot[]
  history?: { stage: string; from: number; to: number | null }[]; tools?: { tool: string; ts: number; running: boolean }[]
  step?: { kind: string; start: number; end: number | null; errors: number }
}
export type UnitsCtx = { tokens: number; line: number | null }
export type UnitsDot = 'GO' | 'NO-GO' | null
export type UnitsProgress = { done: number; failed: number; firstFail: string | null }
export type UnitsState = {
  now: number
  snap: {
    note: string | null; staleMin: number | null; rows: UnitsRow[]; merged: string[]; mergedAt: { unit: string; at: number }[]; chain: null; finishedUsd: Record<string, number>
    limit: { pct: number; resetsAt: number } | null; asks: { id: string; question: string; askedAt: number | null; unit: string | null }[]; unread: string[]
    gates?: { blocks: number; lastHour: number; items: { at: number; hook: string }[] } | null
    seatCtx?: { main: UnitsCtx | null | undefined; chiefOfStaff: UnitsCtx | null | undefined; mainCompactions: number | null }
    unpushed?: string[] | null
  }
  events?: { at: number; unit: string; event: string }[] | null
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
      // The working mark's turn (0-3); only the motion clock moves it.
      unitsFrame: number
      // The pane keys: the unit expanded to its last tool calls, and the section moved first (in memory only).
      unitsExpanded: string | null
      unitsFocus: string | null
    }
  }
}
