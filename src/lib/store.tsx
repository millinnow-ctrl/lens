/* eslint-disable react-refresh/only-export-components */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { getStyle, type StyleParams } from './styles'

export type Plan = 'free' | 'creator' | 'pro' | 'studio'

export const FREE_CREDITS = 5
export const MAX_ROLL = 6

export interface HistoryEntry {
  id: string
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

export interface RollItem {
  url: string
  name: string
}

interface Persisted {
  plan: Plan
  creditsMonth: string
  creditsUsed: number
  history: HistoryEntry[]
  presets: SavedPreset[]
  favorites: string[]
  user: User | null
  /** every mood ever developed — fuels the collection meter */
  tried: string[]
  /** consecutive-day shooting streak */
  streak: { count: number; last: string }
}

const KEY = 'lensmood.v1'
const monthKey = () => {
  const d = new Date()
  return `${d.getFullYear()}-${d.getMonth()}`
}

const isStr = (v: unknown): v is string => typeof v === 'string'
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const PLANS: Plan[] = ['free', 'creator', 'pro', 'studio']

/** field-by-field validation: a poisoned or legacy-format value must never
 *  brick the app on every reload — anything malformed falls back per-field */
function sanitize(raw: unknown, fallback: Persisted): Persisted {
  if (typeof raw !== 'object' || raw === null) return fallback
  const p = raw as Record<string, unknown>
  const strArray = (v: unknown) => (Array.isArray(v) ? v.filter(isStr) : [])
  const streak = p.streak as Record<string, unknown> | null | undefined
  return {
    plan: PLANS.includes(p.plan as Plan) ? (p.plan as Plan) : fallback.plan,
    creditsMonth: isStr(p.creditsMonth) ? p.creditsMonth : fallback.creditsMonth,
    creditsUsed: isNum(p.creditsUsed) ? Math.max(0, p.creditsUsed) : fallback.creditsUsed,
    history: Array.isArray(p.history)
      ? (p.history as unknown[]).filter((h): h is HistoryEntry => {
          const e = h as Partial<HistoryEntry> | null
          return (
            !!e &&
            isStr(e.id) &&
            // thumbs are engine-produced JPEG data URLs — never load anything else
            isStr(e.thumb) &&
            e.thumb.startsWith('data:image/') &&
            isStr(e.styleId) &&
            isStr(e.styleName) &&
            isNum(e.date)
          )
        })
      : [],
    presets: Array.isArray(p.presets)
      ? (p.presets as unknown[]).filter((s): s is SavedPreset => {
          const e = s as Partial<SavedPreset> | null
          return !!e && isStr(e.id) && isStr(e.name) && isStr(e.styleId) && !!getStyle(e.styleId) &&
            typeof e.params === 'object' && e.params !== null
        })
      : [],
    favorites: strArray(p.favorites),
    user:
      typeof p.user === 'object' && p.user !== null && isStr((p.user as User).name) && isStr((p.user as User).email)
        ? { name: (p.user as User).name, email: (p.user as User).email }
        : null,
    tried: strArray(p.tried),
    streak:
      streak && isNum(streak.count) && isStr(streak.last)
        ? { count: streak.count, last: streak.last }
        : fallback.streak,
  }
}

function loadPersisted(): Persisted {
  const fallback: Persisted = {
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
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return fallback
    const p = sanitize(JSON.parse(raw), fallback)
    if (p.creditsMonth !== monthKey()) {
      p.creditsMonth = monthKey()
      p.creditsUsed = 0
    }
    return p
  } catch {
    return fallback
  }
}

interface AppState extends Persisted {
  /** active image (data/object URL) — null when a video is loaded instead */
  photo: string | null
  photoName: string | null
  /** loaded roll of images; more than one shows the filmstrip */
  roll: RollItem[]
  activeIndex: number
  /** active video object URL — mutually exclusive with photo */
  video: string | null
  styleId: string | null
  params: StyleParams | null
  authOpen: boolean
  pendingPreset: SavedPreset | null

  setImage: (url: string, name?: string) => void
  setRoll: (items: RollItem[]) => void
  setActiveIndex: (i: number) => void
  setVideo: (url: string, name?: string) => void
  clearMedia: () => void
  selectStyle: (id: string, params?: StyleParams) => void
  clearStyle: () => void
  setParams: (p: StyleParams) => void
  creditsLeft: number
  spendCredit: () => boolean
  addHistory: (e: Omit<HistoryEntry, 'id' | 'date'>) => void
  removeHistory: (id: string) => void
  savePreset: (name: string) => void
  removePreset: (id: string) => void
  toggleFavorite: (styleId: string) => void
  setPlan: (p: Plan) => void
  signIn: (u: User) => void
  signOut: () => void
  setAuthOpen: (open: boolean) => void
  setPendingPreset: (p: SavedPreset | null) => void
  isPaid: boolean
  hasVideoPlan: boolean
}

const Ctx = createContext<AppState | null>(null)

export function AppProvider({ children }: { children: ReactNode }) {
  const [persisted, setPersisted] = useState<Persisted>(loadPersisted)
  const [roll, setRollState] = useState<RollItem[]>([])
  const [activeIndex, setActiveIndexState] = useState(0)
  const [video, setVideoState] = useState<string | null>(null)
  const [photoName, setPhotoName] = useState<string | null>(null)
  const [styleId, setStyleId] = useState<string | null>(null)
  const [params, setParamsState] = useState<StyleParams | null>(null)
  const [authOpen, setAuthOpen] = useState(false)
  const [pendingPreset, setPendingPreset] = useState<SavedPreset | null>(null)

  useEffect(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(persisted))
    } catch {
      /* storage full — drop oldest history and retry once */
      try {
        localStorage.setItem(
          KEY,
          JSON.stringify({ ...persisted, history: persisted.history.slice(0, 4) }),
        )
      } catch {
        /* give up quietly */
      }
    }
  }, [persisted])

  const resetLook = useCallback(() => {
    setStyleId(null)
    setParamsState(null)
  }, [])

  const releaseVideo = useCallback((current: string | null) => {
    if (current?.startsWith('blob:')) URL.revokeObjectURL(current)
  }, [])

  const setImage = useCallback(
    (url: string, name?: string) => {
      setVideoState((v) => {
        releaseVideo(v)
        return null
      })
      setRollState([{ url, name: name ?? 'photo' }])
      setActiveIndexState(0)
      setPhotoName(name ?? null)
      resetLook()
    },
    [resetLook, releaseVideo],
  )

  const setRoll = useCallback(
    (items: RollItem[]) => {
      if (items.length === 0) return
      setVideoState((v) => {
        releaseVideo(v)
        return null
      })
      setRollState(items.slice(0, MAX_ROLL))
      setActiveIndexState(0)
      setPhotoName(items[0].name)
      resetLook()
    },
    [resetLook, releaseVideo],
  )

  const setActiveIndex = useCallback(
    (i: number) => {
      setActiveIndexState(i)
      setRollState((r) => {
        setPhotoName(r[i]?.name ?? null)
        return r
      })
      resetLook()
    },
    [resetLook],
  )

  const setVideo = useCallback(
    (url: string, name?: string) => {
      setVideoState((v) => {
        releaseVideo(v)
        return url
      })
      setRollState([])
      setActiveIndexState(0)
      setPhotoName(name ?? null)
      resetLook()
    },
    [resetLook, releaseVideo],
  )

  const clearMedia = useCallback(() => {
    setVideoState((v) => {
      releaseVideo(v)
      return null
    })
    setRollState([])
    setActiveIndexState(0)
    setPhotoName(null)
    resetLook()
  }, [resetLook, releaseVideo])

  const selectStyle = useCallback((id: string, p?: StyleParams) => {
    const style = getStyle(id)
    if (!style) return
    setStyleId(id)
    setParamsState(p ?? { ...style.defaults })
  }, [])

  const isPaid = persisted.plan !== 'free'
  const hasVideoPlan = persisted.plan === 'pro' || persisted.plan === 'studio'
  const creditsLeft = isPaid ? Infinity : Math.max(0, FREE_CREDITS - persisted.creditsUsed)

  const spendCredit = useCallback((): boolean => {
    if (persisted.plan !== 'free') return true
    if (FREE_CREDITS - persisted.creditsUsed <= 0) return false
    setPersisted((prev) => ({ ...prev, creditsUsed: prev.creditsUsed + 1 }))
    return true
  }, [persisted.plan, persisted.creditsUsed])

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
        history: [
          { ...e, id: Math.random().toString(36).slice(2, 10), date: Date.now() },
          ...prev.history,
        ].slice(0, 12),
        tried: prev.tried.includes(e.styleId) ? prev.tried : [...prev.tried, e.styleId],
        streak,
      }
    })
  }, [])

  const removeHistory = useCallback((id: string) => {
    setPersisted((prev) => ({ ...prev, history: prev.history.filter((h) => h.id !== id) }))
  }, [])

  const savePreset = useCallback(
    (name: string) => {
      if (!styleId || !params) return
      setPersisted((prev) => ({
        ...prev,
        presets: [
          { id: Math.random().toString(36).slice(2, 10), name, styleId, params: { ...params } },
          ...prev.presets,
        ].slice(0, 20),
      }))
    },
    [styleId, params],
  )

  const removePreset = useCallback((id: string) => {
    setPersisted((prev) => ({ ...prev, presets: prev.presets.filter((p) => p.id !== id) }))
  }, [])

  const toggleFavorite = useCallback((id: string) => {
    setPersisted((prev) => ({
      ...prev,
      favorites: prev.favorites.includes(id)
        ? prev.favorites.filter((f) => f !== id)
        : [...prev.favorites, id],
    }))
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

  const photo = video ? null : (roll[activeIndex]?.url ?? null)

  const value = useMemo<AppState>(
    () => ({
      ...persisted,
      photo,
      photoName,
      roll,
      activeIndex,
      video,
      styleId,
      params,
      authOpen,
      pendingPreset,
      setImage,
      setRoll,
      setActiveIndex,
      setVideo,
      clearMedia,
      selectStyle,
      clearStyle: resetLook,
      setParams: setParamsState,
      creditsLeft,
      spendCredit,
      addHistory,
      removeHistory,
      savePreset,
      removePreset,
      toggleFavorite,
      setPlan,
      signIn,
      signOut,
      setAuthOpen,
      setPendingPreset,
      isPaid,
      hasVideoPlan,
    }),
    [
      persisted,
      photo,
      photoName,
      roll,
      activeIndex,
      video,
      styleId,
      params,
      authOpen,
      pendingPreset,
      setImage,
      setRoll,
      setActiveIndex,
      setVideo,
      clearMedia,
      selectStyle,
      resetLook,
      creditsLeft,
      spendCredit,
      addHistory,
      removeHistory,
      savePreset,
      removePreset,
      toggleFavorite,
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
