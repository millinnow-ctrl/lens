/**
 * StyleRail — the horizontal stock switcher under the viewfinder. Each chip
 * carries the stock's gradient swatch + name; the active one gets the ocean
 * ring. Selecting re-develops in place (the screen owns credits/paywall).
 */

import { memo } from 'react'
import { FlatList, View, Text, Pressable, StyleSheet, Platform } from 'react-native'
import Svg, { Defs, LinearGradient, Stop, Rect } from 'react-native-svg'
import { CAMERA_STYLES } from '@/engine/styles'
import type { CameraStyle } from '@/engine/types'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

function stops(css: string): [string, string] {
  const hits = css.match(/#[0-9a-fA-F]{3,8}/g) ?? []
  return [hits[0] ?? colors.accent, hits[1] ?? hits[0] ?? colors.clay]
}

const Chip = memo(function Chip({
  item,
  active,
  onSelect,
}: {
  item: CameraStyle
  active: boolean
  onSelect: (s: CameraStyle) => void
}) {
  const [g0, g1] = stops(item.gradient)
  return (
    <Pressable
      onPress={() => onSelect(item)}
      style={({ pressed }) => [styles.chip, active && styles.chipActive, pressed && { opacity: 0.85 }]}
      accessibilityRole="button"
      accessibilityLabel={`Develop with ${item.name}`}
    >
      <View style={styles.swatch}>
        <Svg width={40} height={40}>
          <Defs>
            <LinearGradient id={`rail-${item.id}`} x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor={g0} />
              <Stop offset="1" stopColor={g1} />
            </LinearGradient>
          </Defs>
          <Rect x="0" y="0" width="40" height="40" rx="12" fill={`url(#rail-${item.id})`} />
        </Svg>
      </View>
      <Text style={[styles.name, active && styles.nameActive]} numberOfLines={1}>
        {item.name}
      </Text>
    </Pressable>
  )
})

interface Props {
  activeId: string | null
  onSelect: (style: CameraStyle) => void
}

export default function StyleRail({ activeId, onSelect }: Props) {
  return (
    <FlatList
      horizontal
      data={CAMERA_STYLES}
      keyExtractor={(s) => s.id}
      renderItem={({ item }) => <Chip item={item} active={item.id === activeId} onSelect={onSelect} />}
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.rail}
    />
  )
}

const styles = StyleSheet.create({
  rail: { paddingHorizontal: 12, gap: 8, paddingVertical: 4 },
  chip: {
    alignItems: 'center',
    gap: 4,
    padding: 6,
    borderRadius: 14,
    width: 68,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  chipActive: {
    borderColor: colors.accent,
    backgroundColor: colors.surface,
  },
  swatch: { borderRadius: 12, overflow: 'hidden' },
  name: {
    color: colors.inkSoft,
    fontSize: 9,
    letterSpacing: 0.2,
    fontFamily: MONO,
    fontWeight: '600',
  },
  nameActive: { color: colors.ink },
})
