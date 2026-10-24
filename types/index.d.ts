export type Since = string | null

declare module 'claude-code' {
  interface PluginState {
    commandeck: { autoDecideSince: Since; autoDecideCount: number }
  }
}
