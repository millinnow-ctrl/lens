/**
 * CompareSlider — the before/after wipe from the web app, native. The
 * original sits underneath; the developed frame is clipped to the drag
 * position. Core-RN PanResponder (no external gesture deps) so it works
 * identically in Expo Go and dev builds.
 */

import { useMemo, useRef, useState } from 'react'
import { View, Image, Text, PanResponder, StyleSheet, Platform } from 'react-native'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

interface Props {
  beforeUri: string
  afterUri: string
  afterLabel: string
  width: number
  height: number
}

export default function CompareSlider({ beforeUri, afterUri, afterLabel, width, height }: Props) {
  const [x, setX] = useState(width * 0.5)
  const xRef = useRef(width * 0.5)

  const pan = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 2,
        onPanResponderGrant: (e) => {
          const nx = Math.max(12, Math.min(width - 12, e.nativeEvent.locationX))
          xRef.current = nx
          setX(nx)
        },
        onPanResponderMove: (e) => {
          const nx = Math.max(12, Math.min(width - 12, e.nativeEvent.locationX))
          xRef.current = nx
          setX(nx)
        },
      }),
    [width],
  )

  return (
    <View style={[styles.root, { width, height }]} {...pan.panHandlers}>
      {/* original underneath */}
      <Image source={{ uri: beforeUri }} style={styles.img} resizeMode="cover" />
      {/* developed frame clipped to the handle */}
      <View style={[styles.clip, { width: x }]} pointerEvents="none">
        <Image source={{ uri: afterUri }} style={[styles.img, { width, height }]} resizeMode="cover" />
      </View>

      {/* labels */}
      <View style={[styles.chip, styles.chipLeft]} pointerEvents="none">
        <Text style={styles.chipText}>{afterLabel.toUpperCase()}</Text>
      </View>
      <View style={[styles.chip, styles.chipRight]} pointerEvents="none">
        <Text style={styles.chipText}>ORIGINAL</Text>
      </View>

      {/* handle */}
      <View style={[styles.handleLine, { left: x - 1 }]} pointerEvents="none" />
      <View style={[styles.handleKnob, { left: x - 18, top: height / 2 - 18 }]} pointerEvents="none">
        <Text style={styles.handleGlyph}>‹ ›</Text>
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  root: {
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: colors.viewfinder,
  },
  img: { ...StyleSheet.absoluteFillObject, width: '100%', height: '100%' },
  clip: {
    ...StyleSheet.absoluteFillObject,
    overflow: 'hidden',
  },
  chip: {
    position: 'absolute',
    top: 12,
    paddingHorizontal: 10,
    height: 24,
    borderRadius: 999,
    backgroundColor: 'rgba(10,14,18,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  chipLeft: { left: 12 },
  chipRight: { right: 12 },
  chipText: {
    color: 'rgba(255,255,255,0.92)',
    fontSize: 9.5,
    letterSpacing: 1.2,
    fontFamily: MONO,
    fontWeight: '600',
  },
  handleLine: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: 2,
    backgroundColor: 'rgba(255,255,255,0.9)',
  },
  handleKnob: {
    position: 'absolute',
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.95)',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.25,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  },
  handleGlyph: { color: colors.ink, fontSize: 13, fontWeight: '700', letterSpacing: 1 },
})
