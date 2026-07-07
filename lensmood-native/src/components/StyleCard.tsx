/**
 * StyleCard — one camera stock in the chooser grid. Ocean surface card with
 * the stock's accent gradient as a header bar, its name + tagline, a mono EXIF
 * readout, and a tier/badge pill. Native Pressable with a subtle scale + dim
 * on press.
 */

import { memo } from 'react'
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native'
import Svg, { Defs, LinearGradient, Stop, Rect } from 'react-native-svg'
import type { CameraStyle } from '@/engine/types'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

/** pull the hex stops out of a CSS gradient string like
 *  'linear-gradient(135deg,#ffb84d,#ff7a59)' — the ported styles data keeps
 *  its web gradient strings, so we parse rather than restructure them. */
function gradientStops(css: string): [string, string] {
  const hits = css.match(/#[0-9a-fA-F]{3,8}/g) ?? []
  const a = hits[0] ?? colors.accent
  const b = hits[1] ?? hits[0] ?? colors.deepTeal
  return [a, b]
}

function badgeLabel(badge?: string) {
  if (!badge) return null
  return badge.toUpperCase()
}

function StyleCardBase({
  style,
  onPress,
}: {
  style: CameraStyle
  onPress: (style: CameraStyle) => void
}) {
  const [g0, g1] = gradientStops(style.gradient)
  const premium = style.tier === 'premium'

  return (
    <Pressable
      onPress={() => onPress(style)}
      style={({ pressed }) => [
        styles.card,
        pressed && { transform: [{ scale: 0.975 }], opacity: 0.92 },
      ]}
      accessibilityRole="button"
      accessibilityLabel={`${style.name}. ${style.tagline}`}
    >
      {/* accent gradient header */}
      <View style={styles.header}>
        <Svg width="100%" height="100%">
          <Defs>
            <LinearGradient id={`g${style.id}`} x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor={g0} />
              <Stop offset="1" stopColor={g1} />
            </LinearGradient>
          </Defs>
          <Rect x="0" y="0" width="100%" height="100%" fill={`url(#g${style.id})`} />
        </Svg>

        <View style={styles.pillRow}>
          {premium && (
            <View style={[styles.pill, styles.pillPro]}>
              <Text style={styles.pillProText}>PRO</Text>
            </View>
          )}
          {style.badge && (
            <View style={[styles.pill, styles.pillBadge]}>
              <Text style={styles.pillBadgeText}>{badgeLabel(style.badge)}</Text>
            </View>
          )}
        </View>
      </View>

      {/* body */}
      <View style={styles.body}>
        <Text style={styles.name} numberOfLines={1}>
          {style.name}
        </Text>
        <Text style={styles.tagline} numberOfLines={2}>
          {style.tagline}
        </Text>
        <Text style={styles.exif} numberOfLines={1}>
          {style.exif}
        </Text>
      </View>
    </Pressable>
  )
}

export const StyleCard = memo(StyleCardBase)
export default StyleCard

const styles = StyleSheet.create({
  card: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: 18,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.08)',
    // soft ocean elevation
    shadowColor: colors.ink,
    shadowOpacity: 0.08,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 3,
  },
  header: {
    height: 78,
    justifyContent: 'flex-start',
    alignItems: 'flex-end',
    padding: 8,
  },
  pillRow: { flexDirection: 'row', gap: 6 },
  pill: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  pillPro: { backgroundColor: 'rgba(12,85,104,0.92)' },
  pillProText: { color: '#fff', fontSize: 10, fontWeight: '800', letterSpacing: 0.5 },
  pillBadge: { backgroundColor: 'rgba(255,255,255,0.92)' },
  pillBadgeText: {
    color: colors.deepTeal,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  body: { padding: 12, gap: 3 },
  name: { color: colors.ink, fontSize: 15, fontWeight: '700', letterSpacing: -0.2 },
  tagline: { color: colors.inkSoft, fontSize: 12, lineHeight: 16, minHeight: 32 },
  exif: {
    marginTop: 4,
    color: colors.fog,
    fontSize: 10.5,
    letterSpacing: 0.3,
    fontFamily: MONO,
  },
})
