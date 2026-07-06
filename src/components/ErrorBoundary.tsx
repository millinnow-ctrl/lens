import { Component, type ReactNode } from 'react'

interface Props {
  children: ReactNode
}
interface State {
  error: Error | null
}

/**
 * Last line of defense — a crash must never white-screen the app forever.
 * The fallback is branded, apologetic, and offers a real way out: reload,
 * or clear the app's saved state (the only thing that can crash-loop us).
 */
export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  private reload = () => window.location.reload()

  private reset = () => {
    try {
      // clear only our own keys — the develop history, streaks and welcome flag
      for (const key of Object.keys(localStorage)) {
        if (key.startsWith('lensmood.')) localStorage.removeItem(key)
      }
    } catch {
      /* storage unavailable — reload alone may recover */
    }
    window.location.reload()
  }

  render() {
    if (!this.state.error) return this.props.children
    return (
      <main className="min-h-dvh flex items-center justify-center bg-paper px-6">
        <div className="max-w-sm w-full bg-surface border border-hairline rounded-[24px] shadow-[var(--shadow-e3)] p-7">
          <p className="font-mono font-semibold text-[10px] tracking-[0.18em] uppercase text-fog mb-2">
            The darkroom · error
          </p>
          <h1 className="type-display text-[24px] mb-2">Something jammed the shutter.</h1>
          <p className="text-[14px] text-ink-soft leading-relaxed mb-6">
            An unexpected error stopped the app. Reloading usually clears it — if it keeps
            happening, resetting the saved roll will.
          </p>
          <div className="flex items-center gap-3">
            <button onClick={this.reload} className="btn btn-primary">
              Reload
            </button>
            <button onClick={this.reset} className="btn btn-outline">
              Reset &amp; reload
            </button>
          </div>
        </div>
      </main>
    )
  }
}
