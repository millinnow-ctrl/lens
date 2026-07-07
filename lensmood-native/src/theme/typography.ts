import { Platform } from 'react-native'

/**
 * Type system — ported from src/index.css @theme. On iOS the default RN system
 * font IS SF Pro, so `sans` is left undefined (RN falls back to San Francisco).
 * Plex Mono was the web camera-spec voice; the native equivalent is Menlo
 * (iOS) / monospace (Android).
 */
export const fonts = {
  sans: undefined as string | undefined, // iOS system = SF Pro; Android = Roboto
  mono: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
} as const

/** the whole scale rides one notch heavier — SF at true 400 reads wispy */
export const weights = {
  normal: '500',
  medium: '600',
  semibold: '700',
  bold: '800',
} as const

export const type = {
  display: { fontFamily: fonts.sans, fontWeight: weights.bold, letterSpacing: -0.5 },
  brand: { fontFamily: fonts.sans, fontWeight: weights.bold, letterSpacing: -0.4 },
  labelMono: {
    fontFamily: fonts.mono,
    fontSize: 11,
    fontWeight: weights.semibold,
    letterSpacing: 1.4,
  },
  valueMono: { fontFamily: fonts.mono, fontSize: 12, fontWeight: weights.medium },
} as const
