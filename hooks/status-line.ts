import type { EngineInterface } from 'claude-code'

// The plugin has one status line and two features that write it: the units summary and auto-decide's mode. Each sets
// only its own part here; the line shows the parts joined, written when the joined text changes.
const parts: { units?: string; autodecide?: string } = {}
let shown: string | undefined

export function setStatus($: EngineInterface, part: 'units' | 'autodecide', text: string | undefined): void {
  parts[part] = text
  const line = [parts.units, parts.autodecide].filter(Boolean).join(' · ') || undefined
  if (line === shown) return
  shown = line
  $.ui.status(line)
}

// A new session starts with no part set.
export function resetStatus(): void {
  parts.units = parts.autodecide = shown = undefined
}
