/**
 * LensMood mark — the ocean launch icon ported to react-native-svg:
 * a glossy cobalt lens in a dark barrel, wrapped by a teal focus ring that
 * opens toward a four-point glint. Geometry is 1:1 with the web
 * src/components/Logo.tsx ApertureMark (viewBox 0 0 48 48) so the native app
 * and the web app draw the identical mark.
 *
 * `Logo` renders the mark + the LensMood wordmark ("Mood" in accent teal).
 */

import { useId } from 'react'
import { View, Text, StyleSheet, Platform } from 'react-native'
import Svg, {
  Defs,
  LinearGradient,
  RadialGradient,
  Stop,
  ClipPath,
  Rect,
  Circle,
  Path,
  Ellipse,
  G,
} from 'react-native-svg'
import { colors } from '@/theme/colors'

const TAU = Math.PI * 2

/** open focus ring — an arc with its gap aimed at the top-right glint.
 *  Ported verbatim from the web mark. */
const ringArc = (cx: number, cy: number, r: number) => {
  const a0 = (-14 / 360) * TAU // gap edge, upper right
  const a1 = (-76 / 360) * TAU + TAU // sweep the long way around
  const p = (a: number) =>
    `${(cx + r * Math.cos(a)).toFixed(2)} ${(cy + r * Math.sin(a)).toFixed(2)}`
  return `M${p(a0)} A${r} ${r} 0 1 1 ${p(a1)}`
}

// static — same for every instance
const RING_PATH = ringArc(23, 26, 17.6)

export function ApertureMark({
  size = 28,
  /** draw the white rounded-square tile behind the lens */
  tile = true,
}: {
  size?: number
  tile?: boolean
}) {
  // gradient / clip ids must be unique per instance — otherwise every
  // url(#...) ref in the document resolves to the first id and the paint
  // silently drops out when the first instance is unmounted / hidden.
  const uid = useId().replace(/[:]/g, '')
  const ring = `lmRing${uid}`
  const glass = `lmGlass${uid}`
  const core = `lmCore${uid}`
  const clip = `lmClip${uid}`

  return (
    <Svg width={size} height={size} viewBox="0 0 48 48">
      <Defs>
        <LinearGradient id={ring} x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#33b3c8" />
          <Stop offset="1" stopColor="#0b6a7d" />
        </LinearGradient>
        <RadialGradient id={glass} cx="0.38" cy="0.3" r="0.85">
          <Stop offset="0" stopColor="#5b8ff0" />
          <Stop offset="0.55" stopColor="#2846c8" />
          <Stop offset="1" stopColor="#122a6e" />
        </RadialGradient>
        <RadialGradient id={core} cx="0.4" cy="0.35" r="0.9">
          <Stop offset="0" stopColor="#7aa8ff" />
          <Stop offset="1" stopColor="#1f3f96" />
        </RadialGradient>
        <ClipPath id={clip}>
          <Circle cx="23" cy="26" r="10.2" />
        </ClipPath>
      </Defs>

      {tile && (
        <Rect
          x="0.5"
          y="0.5"
          width="47"
          height="47"
          rx="12"
          fill="#ffffff"
          stroke="#000000"
          strokeOpacity="0.06"
        />
      )}

      {/* focus ring, open toward the glint */}
      <Path
        d={RING_PATH}
        fill="none"
        stroke={`url(#${ring})`}
        strokeWidth="3.3"
        strokeLinecap="round"
      />

      {/* four-point glint sitting in the ring's opening */}
      <Path
        d="M39.5 4.5 C40.2 7.8 41.9 9.4 45 10 C41.9 10.6 40.2 12.2 39.5 15.5 C38.8 12.2 37.1 10.6 34 10 C37.1 9.4 38.8 7.8 39.5 4.5 Z"
        fill={`url(#${ring})`}
      />

      {/* lens barrel with an inscribed teal ring */}
      <Circle cx="23" cy="26" r="13.2" fill="#0b1322" />
      <Circle cx="23" cy="26" r="11.4" fill="none" stroke="#1a8ba0" strokeWidth="1.5" />

      {/* cobalt-blue glass, stepped elements, glossy sweep */}
      <Circle cx="23" cy="26" r="10.2" fill={`url(#${glass})`} />
      <Circle
        cx="23"
        cy="26"
        r="6.6"
        fill="none"
        stroke="#0a1c4a"
        strokeWidth="1.4"
        strokeOpacity="0.75"
      />
      <Circle cx="23" cy="26" r="3.7" fill={`url(#${core})`} />
      <G clipPath={`url(#${clip})`}>
        <Ellipse
          cx="28"
          cy="19.5"
          rx="9.5"
          ry="5.2"
          origin="28, 19.5"
          rotation={-32}
          fill="#ffffff"
          opacity={0.26}
        />
      </G>
    </Svg>
  )
}

export default function Logo({
  markSize = 34,
  wordSize = 22,
}: {
  markSize?: number
  wordSize?: number
}) {
  return (
    <View style={styles.row}>
      <ApertureMark size={markSize} tile={false} />
      <Text style={[styles.word, { fontSize: wordSize }]}>
        Lens
        <Text style={styles.mood}>Mood</Text>
      </Text>
    </View>
  )
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  word: {
    color: colors.ink,
    fontWeight: '800',
    letterSpacing: -0.5,
    ...Platform.select({ ios: { fontFamily: 'System' }, default: {} }),
  },
  mood: { color: colors.accent, fontWeight: '800' },
})
