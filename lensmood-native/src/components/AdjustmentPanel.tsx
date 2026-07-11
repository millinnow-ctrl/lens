/**
 * AdjustmentPanel — the studio's fine-tune surface, ported from the web app's
 * AdjustmentPanel + StepControl pair (src/components/{AdjustmentPanel,
 * StepControl}.tsx). Recipes (quick presets) up top, then one detented
 * StepControl per engine param. Every control speaks named stops ("Chunky",
 * "Golden") — never a raw 0–100 number — while the engine value stays numeric
 * underneath (LEVEL_SCALES.values), so presets and deep links are untouched.
 *
 * Native translation of the web's pointer rail: each stop is a Pressable hit
 * cell, the active puck is a reanimated view that springs between detents,
 * and a store-haptics tick fires only when the detent actually changes.
 * The panel itself never talks to the engine — it calls onChange and the
 * develop screen debounces the re-develop (~250ms).
 */

import { useEffect, useState } from 'react'
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native'
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated'
import { QUICK_PRESETS } from '@/engine/styles'
import type { CameraStyle, StyleParams } from '@/engine/types'
import { useApp, haptics } from '@/store'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

/* -------------------------------------------------------------- the scales */

export interface LevelScale {
  /** which StyleParams field this scale drives */
  param: keyof StyleParams
  label: string
  /** stop names, low → high */
  stops: string[]
  /** engine value for each stop (same length as stops) */
  values: number[]
}

/** ported 1:1 from the web app's src/lib/levels.ts */
export const LEVEL_SCALES: LevelScale[] = [
  {
    param: 'intensity',
    label: 'Character',
    stops: ['Trace', 'Soft', 'Balanced', 'Full', 'Pushed'],
    values: [25, 45, 65, 82, 100],
  },
  {
    param: 'grain',
    label: 'Grain',
    stops: ['None', 'Fine', 'Soft', 'Heavy', 'Chunky'],
    values: [0, 18, 38, 62, 85],
  },
  {
    param: 'contrast',
    label: 'Contrast',
    stops: ['Flat', 'Gentle', 'Neutral', 'Punchy', 'Hard'],
    values: [22, 36, 50, 66, 82],
  },
  {
    param: 'warmth',
    label: 'Temperature',
    stops: ['Cold', 'Cool', 'Neutral', 'Warm', 'Golden'],
    values: [12, 32, 50, 68, 88],
  },
  {
    param: 'flash',
    label: 'Flash',
    stops: ['Off', 'Kiss', 'Fill', 'Party', 'Blast'],
    values: [0, 25, 50, 72, 95],
  },
  {
    param: 'shadows',
    label: 'Shadows',
    stops: ['Open', 'Lifted', 'Deep', 'Crushed'],
    values: [12, 35, 62, 86],
  },
  {
    param: 'smoothing',
    label: 'Skin',
    stops: ['Off', 'Touch', 'Studio'],
    values: [0, 30, 60],
  },
]

/** index of the stop closest to an arbitrary engine value (presets, links) */
export const nearestStop = (scale: LevelScale, value: number): number => {
  let best = 0
  let bestDist = Infinity
  scale.values.forEach((v, i) => {
    const d = Math.abs(v - value)
    if (d < bestDist) {
      bestDist = d
      best = i
    }
  })
  return best
}

/* ------------------------------------------------------------ StepControl */

const PUCK = 18
const MARK_W = 2
const TRACK_H = 36

/**
 * One detented dial from a LevelScale. Label engraved left, the current STOP
 * NAME on the right where a number would be; the puck snaps between etched
 * detents with a haptic tick. Stops are Pressable cells; the puck rides a
 * reanimated translateX.
 */
export function StepControl({
  scale,
  value,
  onChange,
}: {
  scale: LevelScale
  value: number
  onChange: (v: number) => void
}) {
  const count = scale.stops.length
  const index = nearestStop(scale, value)
  const [trackW, setTrackW] = useState(0)
  const x = useSharedValue(0)

  /** detent centers live on [PUCK/2 .. trackW - PUCK/2] so the puck never
   *  clips at the rail's ends (mirrors the web's 2px edge insets) */
  const centerFor = (i: number, w: number) =>
    PUCK / 2 + (count > 1 ? i / (count - 1) : 0) * (w - PUCK)

  useEffect(() => {
    if (trackW <= 0) return
    x.value = withTiming(centerFor(index, trackW) - PUCK / 2, { duration: 180 })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [index, trackW, count])

  const puckStyle = useAnimatedStyle(() => ({ transform: [{ translateX: x.value }] }))

  const commit = (i: number) => {
    if (i === index) return
    haptics.light()
    onChange(scale.values[i])
  }

  return (
    <View>
      {/* header row: label left, current stop name right */}
      <View style={sc.header}>
        <Text style={sc.label}>{scale.label.toUpperCase()}</Text>
        <Text style={sc.stopName}>{scale.stops[index].toUpperCase()}</Text>
      </View>

      <View
        style={sc.track}
        onLayout={(e) => setTrackW(e.nativeEvent.layout.width)}
        accessibilityRole="adjustable"
        accessibilityLabel={scale.label}
        accessibilityValue={{ min: 0, max: count - 1, now: index, text: scale.stops[index] }}
      >
        {/* recessed channel the detents are milled into */}
        <View style={sc.channel} pointerEvents="none" />

        {/* etched detents — passed marks read teal, upcoming ink */}
        {trackW > 0 &&
          scale.stops.map((_, i) => {
            const passed = i < index
            return (
              <View
                key={i}
                pointerEvents="none"
                style={[
                  sc.mark,
                  {
                    left: centerFor(i, trackW) - MARK_W / 2,
                    height: passed ? 15 : 11,
                    backgroundColor: passed ? colors.accent : 'rgba(23,36,45,0.28)',
                  },
                ]}
              />
            )
          })}

        {/* the machined puck */}
        {trackW > 0 && <Animated.View pointerEvents="none" style={[sc.puck, puckStyle]} />}

        {/* pressable stop cells — equal hit zones across the rail */}
        <View style={sc.cells}>
          {scale.stops.map((name, i) => (
            <Pressable
              key={name}
              style={sc.cell}
              onPress={() => commit(i)}
              hitSlop={{ top: 6, bottom: 6 }}
              accessibilityRole="button"
              accessibilityLabel={`${scale.label}: ${name}`}
              accessibilityState={{ selected: i === index }}
            />
          ))}
        </View>
      </View>
    </View>
  )
}

const sc = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  label: {
    color: colors.inkSoft,
    fontFamily: MONO,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1.6,
  },
  stopName: {
    color: colors.ink,
    fontFamily: MONO,
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 1.2,
  },
  track: { height: TRACK_H, justifyContent: 'center' },
  channel: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: TRACK_H / 2 - 2.5,
    height: 5,
    borderRadius: 999,
    backgroundColor: 'rgba(23,36,45,0.07)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.12)',
  },
  mark: {
    position: 'absolute',
    top: '50%',
    width: MARK_W,
    borderRadius: 999,
    transform: [{ translateY: -7 }],
  },
  puck: {
    position: 'absolute',
    left: 0,
    top: TRACK_H / 2 - PUCK / 2,
    width: PUCK,
    height: PUCK,
    borderRadius: 999,
    backgroundColor: colors.accent,
    borderWidth: 1.5,
    borderColor: 'rgba(255,255,255,0.85)',
    shadowColor: colors.ink,
    shadowOpacity: 0.3,
    shadowRadius: 3,
    shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  },
  cells: { ...StyleSheet.absoluteFillObject, flexDirection: 'row' },
  cell: { flex: 1, height: TRACK_H },
})

/* ------------------------------------------------------------- the panel */

interface Props {
  style: CameraStyle
  params: StyleParams
  onChange: (p: StyleParams) => void
  /** dim + lock the controls (e.g. while a photo is still loading) */
  disabled?: boolean
}

export function AdjustmentPanel({ style, params, onChange, disabled = false }: Props) {
  const { savePreset } = useApp()
  const [activePreset, setActivePreset] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  // a new stock means a new recipe conversation
  useEffect(() => setActivePreset(null), [style.id])

  useEffect(() => {
    if (!saved) return
    const t = setTimeout(() => setSaved(false), 1600)
    return () => clearTimeout(t)
  }, [saved])

  const setParam = (k: keyof StyleParams, v: number) => {
    setActivePreset(null)
    onChange({ ...params, [k]: v })
  }

  const applyRecipe = (id: string, next: StyleParams) => {
    haptics.medium()
    setActivePreset(id)
    onChange(next)
  }

  return (
    <View
      style={[panel.root, disabled && { opacity: 0.45 }]}
      pointerEvents={disabled ? 'none' : 'auto'}
    >
      {/* recipes */}
      <View>
        <Text style={panel.section}>RECIPES</Text>
        <View style={panel.chipRow}>
          {QUICK_PRESETS.map((p) => {
            const on = activePreset === p.id
            return (
              <Pressable
                key={p.id}
                onPress={() => applyRecipe(p.id, p.apply({ ...style.defaults }))}
                style={({ pressed }) => [
                  panel.chip,
                  on && panel.chipOn,
                  pressed && { opacity: 0.8, transform: [{ scale: 0.97 }] },
                ]}
                accessibilityRole="button"
                accessibilityState={{ selected: on }}
              >
                {on && <View style={panel.chipDot} />}
                <Text style={[panel.chipText, on && panel.chipTextOn]}>{p.name.toUpperCase()}</Text>
              </Pressable>
            )
          })}
        </View>
      </View>

      <View style={panel.divider} />

      {/* detented dials — fixed order, never reflow (muscle memory) */}
      <View style={panel.dials}>
        {LEVEL_SCALES.map((scale) => (
          <StepControl
            key={scale.param}
            scale={scale}
            value={params[scale.param]}
            onChange={(v) => setParam(scale.param, v)}
          />
        ))}
      </View>

      {/* reset + save preset */}
      <View style={panel.footer}>
        <Pressable
          onPress={() => {
            haptics.medium()
            setActivePreset(null)
            onChange({ ...style.defaults })
          }}
          style={({ pressed }) => [panel.reset, pressed && { opacity: 0.7 }]}
          accessibilityRole="button"
          accessibilityLabel={`Reset to ${style.name}`}
        >
          <View style={panel.resetKey}>
            <Text style={panel.resetGlyph}>↺</Text>
          </View>
          <Text style={panel.resetText} numberOfLines={1}>
            RESET TO {style.name.toUpperCase()}
          </Text>
        </Pressable>

        <Pressable
          onPress={() => {
            const p = savePreset(`${style.name} · mine`, style.id, params)
            if (p) {
              haptics.success()
              setSaved(true)
            }
          }}
          style={({ pressed }) => [panel.save, pressed && { opacity: 0.8 }]}
          accessibilityRole="button"
          accessibilityLabel="Save preset"
        >
          <Text style={panel.saveText}>{saved ? '✓ Saved' : 'Save preset'}</Text>
        </Pressable>
      </View>
    </View>
  )
}

export default AdjustmentPanel

const panel = StyleSheet.create({
  root: { gap: 16 },
  section: {
    color: colors.fog,
    fontFamily: MONO,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1.6,
    marginBottom: 10,
  },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    height: 32,
    paddingHorizontal: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(23,36,45,0.18)',
  },
  chipOn: { backgroundColor: colors.ink, borderColor: colors.ink },
  chipDot: { width: 6, height: 6, borderRadius: 999, backgroundColor: colors.accentLight },
  chipText: {
    color: colors.inkSoft,
    fontFamily: MONO,
    fontSize: 10.5,
    fontWeight: '600',
    letterSpacing: 1,
  },
  chipTextOn: { color: '#f2f6f8' },
  divider: { height: StyleSheet.hairlineWidth, backgroundColor: colors.hairline },
  dials: { gap: 14 },
  footer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingTop: 2,
  },
  reset: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    height: 32,
    paddingLeft: 4,
    paddingRight: 12,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(23,36,45,0.18)',
    flexShrink: 1,
  },
  resetKey: {
    width: 24,
    height: 24,
    borderRadius: 999,
    backgroundColor: 'rgba(23,36,45,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  resetGlyph: { color: colors.inkSoft, fontSize: 13, fontWeight: '700', lineHeight: 15 },
  resetText: {
    color: colors.fog,
    fontFamily: MONO,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1.2,
    flexShrink: 1,
  },
  save: {
    height: 32,
    paddingHorizontal: 14,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(23,36,45,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  saveText: { color: colors.ink, fontSize: 12, fontWeight: '700' },
})
