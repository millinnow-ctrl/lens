/**
 * LensMood app state — plan, credits, history, favorites, presets, account
 * and streak, persisted to AsyncStorage. Ported from the web app's
 * src/lib/store.tsx with the same business rules:
 *
 *   - free plan = 5 develops per month (FREE_CREDITS), reset by local month
 *     key; the very first develop ever is on the house (the aha moment,
 *     mirroring web Studio's `history.length === 0` bypass)
 *   - paid plans (creator / pro / studio) never spend credits
 *   - video is Pro+ (`hasVideoPlan`), watermark applies to free exports
 *     (`isPaid` is what the export flow keys off)
 *
 * Differences from the web module, on purpose:
 *   - localStorage → AsyncStorage ('lensmood.v1' key), so hydration is async;
 *     `ready` flips true once the persisted slice has loaded. Gate the first
 *     screen (or hold the splash) on it before trusting plan/credits.
 *   - history thumbs are engine-produced file:// JPEG URIs (DevelopResult.uri)
 *     instead of data URLs; sanitize accepts both, nothing else.
 *   - session-only state (photo/roll/video/styleId/params) stays in the
 *     screens — the native store is the durable layer only, so savePreset
 *     takes the style + params explicitly instead of reading ambient state.
 *
 * Everything loaded from disk goes through sanitize() field-by-field: a
 * poisoned or legacy-format value must never brick the app on every launch.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { getStyle } from '@/engine/styles'
import type { StyleParams } from '@/engine/types'

/* ---------------------------------------------------------------- contract */

export type Plan = 'free' | 'creator' | 'pro' | 'studio'

export const FREE_CREDITS = 5
export const HISTORY_CAP = 60
export const PRESET_CAP = 20

export interface HistoryEntry {
  id: string
  /** developed thumbnail — file:// JPEG URI from the Skia engine
   *  (DevelopResult.uri); data:image/ URLs also accepted for parity */
  thumb: string
  styleId: string
  styleName: string
  date: number
}

export interface SavedPreset {
  id: string
  name: string
  styleId: string
  params: StyleParams
}

export interface User {
  name: string
  email: string
}

export interface Streak {
  /** consecutive-day shooting streak */
  count: number
  /** last develop day, 'YYYY-MM-DD' (empty when never developed) */
  last: string
}

/** the durable slice written to AsyncStorage under KEY */
export interface Persisted {
  plan: Plan
  /** local month the credit counter belongs to, 'YYYY-M' */
  creditsMonth: string
  creditsUsed: number
  history: HistoryEntry[]
  presets: SavedPreset[]
  favorites: string[]
  user: User | null
  /** every mood ever developed — fuels the collection meter and marks the
   *  first-ever develop (which is always free) */
  tried: string[]
  streak: Streak
}

const KEY = 'lensmood.v1'

const monthKey = () => {
  const d = new Date()
  return `${d.getFullYear()}-${d.getMonth()}`
}

const makeId = () => Math.random().toString(36).slice(2, 10)

const isStr = (v: unknown): v is string => typeof v === 'string'
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const PLANS: Plan[] = ['free', 'creator', 'pro', 'studio']

/* ---------------------------------------------------------------- sanitize */

/**
 * Clamp arbitrary param input to a finite 0–100 per slider, falling back to
 * the style's defaults key-by-key (same contract the web app's decodeParams
 * enforces for deep links). Returns null when the style id is unknown, so a
 * removed stock can't smuggle stale params into the engine.
 */
export function clampParams(styleId: string, raw: unknown): StyleParams | null {
  const style = getStyle(styleId)
  if (!style) return null
  const base = style.defaults
  const src = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>
  return Object.fromEntries(
    (Object.keys(base) as (keyof StyleParams)[]).map((k) => {
      const v = src[k]
      return [k, isNum(v) ? Math.max(0, Math.min(100, v)) : base[k]]
    }),
  ) as unknown as StyleParams
}

/** field-by-field validation: a poisoned or legacy-format value must never
 *  brick the app on every launch — anything malformed falls back per-field */
export function sanitize(raw: unknown, fallback: Persisted): Persisted {
  if (typeof raw !== 'object' || raw === null) return fallback
  const p = raw as Record<string, unknown>
  const strArray = (v: unknown) => (Array.isArray(v) ? v.filter(isStr) : [])
  const streak = p.streak as Record<string, unknown> | null | undefined
  return {
    plan: PLANS.includes(p.plan as Plan) ? (p.plan as Plan) : fallback.plan,
    creditsMonth: isStr(p.creditsMonth) ? p.creditsMonth : fallback.creditsMonth,
    creditsUsed: isNum(p.creditsUsed) ? Math.max(0, p.creditsUsed) : fallback.creditsUsed,
    history: Array.isArray(p.history)
      ? (p.history as unknown[])
          .filter((h): h is HistoryEntry => {
            const e = h as Partial<HistoryEntry> | null
            return (
              !!e &&
              isStr(e.id) &&
              // thumbs are engine-produced JPEGs — a local cache file on
              // native, a data URL on web. Never load anything else.
              isStr(e.thumb) &&
              (e.thumb.startsWith('file://') || e.thumb.startsWith('data:image/')) &&
              isStr(e.styleId) &&
              isStr(e.styleName) &&
              isNum(e.date)
            )
          })
          .slice(0, HISTORY_CAP)
      : [],
    presets: Array.isArray(p.presets)
      ? (p.presets as unknown[])
          .filter((s): s is SavedPreset => {
            const e = s as Partial<SavedPreset> | null
            return (
              !!e &&
              isStr(e.id) &&
              isStr(e.name) &&
              isStr(e.styleId) &&
              !!getStyle(e.styleId) &&
              typeof e.params === 'object' &&
              e.params !== null
            )
          })
          // clamp every param to a finite 0–100 so a poisoned preset can't
          // feed NaN or absurd values into the engine
          .map((e) => ({ ...e, params: clampParams(e.styleId, e.params)! }))
          .slice(0, PRESET_CAP)
      : [],
    favorites: strArray(p.favorites),
    user:
      typeof p.user === 'object' &&
      p.user !== null &&
      isStr((p.user as User).name) &&
      isStr((p.user as User).email)
        ? { name: (p.user as User).name, email: (p.user as User).email }
        : null,
    tried: strArray(p.tried),
    streak:
      streak && isNum(streak.count) && isStr(streak.last)
        ? { count: Math.max(0, streak.count), last: streak.last }
        : fallback.streak,
  }
}

export function freshPersisted(): Persisted {
  return {
    plan: 'free',
    creditsMonth: monthKey(),
    creditsUsed: 0,
    history: [],
    presets: [],
    favorites: [],
    user: null,
    tried: [],
    streak: { count: 0, last: '' },
  }
}

/* ----------------------------------------------------------------- context */

export interface AppState extends Persisted {
  /** true once the AsyncStorage slice has hydrated — gate plan/credit UI on it */
  ready: boolean

  /** Infinity on paid plans; 0..FREE_CREDITS on free, month-rollover aware */
  creditsLeft: number
  /** true while the very first develop ever is still unspent — it's free */
  firstDevelopFree: boolean
  /** call before developing. true = allowed (paid, first-ever, or a credit
   *  was just spent); false = out of credits, show the paywall */
  spendCredit: () => boolean

  addHistory: (e: Omit<HistoryEntry, 'id' | 'date'>) => void
  removeHistory: (id: string) => void

  toggleFavorite: (styleId: string) => void

  /** clamps params 0..100 against the style's defaults; null if styleId unknown */
  savePreset: (name: string, styleId: string, params: StyleParams) => SavedPreset | null
  /** look up a saved preset (params come back as a fresh clone) */
  applyPreset: (id: string) => SavedPreset | null
  removePreset: (id: string) => void

  setPlan: (p: Plan) => void
  signIn: (u: User) => void
  signOut: () => void

  isPaid: boolean
  /** video develops are Pro and Studio only */
  hasVideoPlan: boolean
}

const Ctx = createContext<AppState | null>(null)

export function AppProvider({ children }: { children: ReactNode }) {
  const [persisted, setPersisted] = useState<Persisted>(freshPersisted)
  const [ready, setReady] = useState(false)

  /* hydrate once — sanitize whatever is on disk, then apply the month reset */
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      let next = freshPersisted()
      try {
        const raw = await AsyncStorage.getItem(KEY)
        if (raw) next = sanitize(JSON.parse(raw), next)
      } catch {
        /* unreadable slice — start fresh */
      }
      if (next.creditsMonth !== monthKey()) {
        next.creditsMonth = monthKey()
        next.creditsUsed = 0
      }
      if (!cancelled) {
        setPersisted(next)
        setReady(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  /* persist every change after hydration */
  useEffect(() => {
    if (!ready) return
    ;(async () => {
      try {
        await AsyncStorage.setItem(KEY, JSON.stringify(persisted))
      } catch {
        /* storage full — drop most history and retry once */
        try {
          await AsyncStorage.setItem(
            KEY,
            JSON.stringify({ ...persisted, history: persisted.history.slice(0, 10) }),
          )
        } catch {
          /* give up quietly */
        }
      }
    })()
  }, [persisted, ready])

  const isPaid = persisted.plan !== 'free'
  const hasVideoPlan = persisted.plan === 'pro' || persisted.plan === 'studio'
  const firstDevelopFree = persisted.tried.length === 0 && persisted.history.length === 0

  /* month-rollover aware: if the app has stayed open across a month boundary,
   * the stale counter reads as zero used */
  const usedThisMonth = persisted.creditsMonth === monthKey() ? persisted.creditsUsed : 0
  const creditsLeft = isPaid ? Infinity : Math.max(0, FREE_CREDITS - usedThisMonth)

  const spendCredit = useCallback((): boolean => {
    if (persisted.plan !== 'free') return true
    // the very first develop is always on the house — the aha moment
    if (persisted.tried.length === 0 && persisted.history.length === 0) return true
    const used = persisted.creditsMonth === monthKey() ? persisted.creditsUsed : 0
    if (FREE_CREDITS - used <= 0) return false
    setPersisted((prev) => {
      const sameMonth = prev.creditsMonth === monthKey()
      return {
        ...prev,
        creditsMonth: monthKey(),
        creditsUsed: sameMonth ? prev.creditsUsed + 1 : 1,
      }
    })
    return true
  }, [
    persisted.plan,
    persisted.creditsMonth,
    persisted.creditsUsed,
    persisted.tried.length,
    persisted.history.length,
  ])

  const addHistory = useCallback((e: Omit<HistoryEntry, 'id' | 'date'>) => {
    setPersisted((prev) => {
      const today = new Date().toISOString().slice(0, 10)
      const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
      const streak =
        prev.streak.last === today
          ? prev.streak
          : { count: prev.streak.last === yesterday ? prev.streak.count + 1 : 1, last: today }
      return {
        ...prev,
        history: [{ ...e, id: makeId(), date: Date.now() }, ...prev.history].slice(
          0,
          HISTORY_CAP,
        ),
        tried: prev.tried.includes(e.styleId) ? prev.tried : [...prev.tried, e.styleId],
        streak,
      }
    })
  }, [])

  const removeHistory = useCallback((id: string) => {
    setPersisted((prev) => ({ ...prev, history: prev.history.filter((h) => h.id !== id) }))
  }, [])

  const toggleFavorite = useCallback((styleId: string) => {
    setPersisted((prev) => ({
      ...prev,
      favorites: prev.favorites.includes(styleId)
        ? prev.favorites.filter((f) => f !== styleId)
        : [...prev.favorites, styleId],
    }))
  }, [])

  const savePreset = useCallback(
    (name: string, styleId: string, params: StyleParams): SavedPreset | null => {
      const clamped = clampParams(styleId, params)
      if (!clamped) return null
      const preset: SavedPreset = { id: makeId(), name, styleId, params: clamped }
      setPersisted((prev) => ({
        ...prev,
        presets: [preset, ...prev.presets].slice(0, PRESET_CAP),
      }))
      return preset
    },
    [],
  )

  const applyPreset = useCallback(
    (id: string): SavedPreset | null => {
      const p = persisted.presets.find((s) => s.id === id)
      return p ? { ...p, params: { ...p.params } } : null
    },
    [persisted.presets],
  )

  const removePreset = useCallback((id: string) => {
    setPersisted((prev) => ({ ...prev, presets: prev.presets.filter((p) => p.id !== id) }))
  }, [])

  const setPlan = useCallback((p: Plan) => {
    setPersisted((prev) => ({ ...prev, plan: p }))
  }, [])

  const signIn = useCallback((u: User) => {
    setPersisted((prev) => ({ ...prev, user: u }))
  }, [])

  const signOut = useCallback(() => {
    setPersisted((prev) => ({ ...prev, user: null, plan: 'free' }))
  }, [])

  const value = useMemo<AppState>(
    () => ({
      ...persisted,
      ready,
      creditsLeft,
      firstDevelopFree,
      spendCredit,
      addHistory,
      removeHistory,
      toggleFavorite,
      savePreset,
      applyPreset,
      removePreset,
      setPlan,
      signIn,
      signOut,
      isPaid,
      hasVideoPlan,
    }),
    [
      persisted,
      ready,
      creditsLeft,
      firstDevelopFree,
      spendCredit,
      addHistory,
      removeHistory,
      toggleFavorite,
      savePreset,
      applyPreset,
      removePreset,
      setPlan,
      signIn,
      signOut,
      isPaid,
      hasVideoPlan,
    ],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useApp(): AppState {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useApp must be used within AppProvider')
  return ctx
}
