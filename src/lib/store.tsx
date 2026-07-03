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

interface Persisted {
  plan: Plan
  creditsMonth: string
  creditsUsed: number
  history: HistoryEntry[]
  presets: SavedPreset[]
  favorites: string[]
  user: User | null
}

const KEY = 'lensmood.v1'
const monthKey = () => {
  const d = new Date()
  return `${d.getFullYear()}-${d.getMonth()}`
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
  }
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return fallback
    const p = { ...fallback, ...(JSON.parse(raw) as Partial<Persisted>) }
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
  /** current working photo (data URL) — not persisted, sessions are fresh */
  photo: string | null
  photoName: string | null
  styleId: string | null
  params: StyleParams | null
  authOpen: boolean

  setPhoto: (dataUrl: string | null, name?: string) => void
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
  isPaid: boolean
}

const Ctx = createContext<AppState | null>(null)

export function AppProvider({ children }: { children: ReactNode }) {
  const [persisted, setPersisted] = useState<Persisted>(loadPersisted)
  const [photo, setPhotoState] = useState<string | null>(null)
  const [photoName, setPhotoName] = useState<string | null>(null)
  const [styleId, setStyleId] = useState<string | null>(null)
  const [params, setParamsState] = useState<StyleParams | null>(null)
  const [authOpen, setAuthOpen] = useState(false)

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

  const setPhoto = useCallback((dataUrl: string | null, name?: string) => {
    setPhotoState(dataUrl)
    setPhotoName(name ?? null)
    setStyleId(null)
    setParamsState(null)
  }, [])

  const selectStyle = useCallback((id: string, p?: StyleParams) => {
    const style = getStyle(id)
    if (!style) return
    setStyleId(id)
    setParamsState(p ?? { ...style.defaults })
  }, [])

  const clearStyle = useCallback(() => {
    setStyleId(null)
    setParamsState(null)
  }, [])

  const isPaid = persisted.plan !== 'free'
  const creditsLeft = isPaid
    ? Infinity
    : Math.max(0, FREE_CREDITS - persisted.creditsUsed)

  const spendCredit = useCallback((): boolean => {
    if (persisted.plan !== 'free') return true
    if (FREE_CREDITS - persisted.creditsUsed <= 0) return false
    setPersisted((prev) => ({ ...prev, creditsUsed: prev.creditsUsed + 1 }))
    return true
  }, [persisted.plan, persisted.creditsUsed])

  const addHistory = useCallback((e: Omit<HistoryEntry, 'id' | 'date'>) => {
    setPersisted((prev) => ({
      ...prev,
      history: [
        { ...e, id: Math.random().toString(36).slice(2, 10), date: Date.now() },
        ...prev.history,
      ].slice(0, 12),
    }))
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

  const value = useMemo<AppState>(
    () => ({
      ...persisted,
      photo,
      photoName,
      styleId,
      params,
      authOpen,
      setPhoto,
      selectStyle,
      clearStyle,
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
      isPaid,
    }),
    [
      persisted,
      photo,
      photoName,
      styleId,
      params,
      authOpen,
      setPhoto,
      selectStyle,
      clearStyle,
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
    ],
  )

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useApp(): AppState {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useApp must be used within AppProvider')
  return ctx
}
