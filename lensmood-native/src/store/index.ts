/**
 * Barrel for the app-state layer — import from '@/store'.
 */

export {
  AppProvider,
  useApp,
  sanitize,
  clampParams,
  freshPersisted,
  FREE_CREDITS,
  HISTORY_CAP,
  PRESET_CAP,
  type AppState,
  type Persisted,
  type Plan,
  type HistoryEntry,
  type SavedPreset,
  type User,
  type Streak,
} from './store'

export { haptics } from './haptics'
