/**
 * HeroCard — the living hero from the web home, native. A dark viewfinder
 * card with the chrome strip, the rotating warm word (mood. / look. /
 * texture. / glow.) and the white "Start with a photo" pill. Poster is a
 * Skia-drawn dusk gradient until a bundled clip/poster asset lands.
 */

import { useEffect, useState } from 'react'
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native'
import { Canvas, Rect, LinearGradient, vec, RadialGradient, Circle } from '@shopify/react-native-skia'
import Animated, { FadeInDown, FadeOutUp } from 'react-native-reanimated'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

const WORDS = ['mood.', 'look.', 'texture.', 'glow.']
const WORD_HOLD = 3400

interface Props {
  width: number
  onStart: () => void
}

export default function HeroCard({ width, onStart }: Props) {
  const [w, setW] = useState(0)
  const height = Math.round(width * 0.92)

  useEffect(() => {
    const t = setInterval(() => setW((v) => (v + 1) % WORDS.length), WORD_HOLD)
    return () => clearInterval(t)
  }, [])

  return (
    <View style={[styles.card, { width }]}>
      {/* chrome strip */}
      <View style={styles.chrome}>
        <View style={styles.liveRow}>
          <View style={styles.liveDot} />
          <Text style={styles.chromeText}>MATCHA HOUR</Text>
        </View>
        <Text style={styles.chromeText}>ƒ1.4 · 50MM · WARM</Text>
      </View>

      {/* frame */}
      <View style={{ height }}>
        <Canvas style={StyleSheet.absoluteFill}>
          {/* dusk-road gradient poster */}
          <Rect x={0} y={0} width={width} height={height}>
            <LinearGradient
              start={vec(0, 0)}
              end={vec(width * 0.2, height)}
              colors={['#2c3e50', '#7a6247', '#c99b62', '#8a5a33']}
            />
          </Rect>
          {/* low sun */}
          <Circle cx={width * 0.78} cy={height * 0.42} r={width * 0.3}>
            <RadialGradient
              c={vec(width * 0.78, height * 0.42)}
              r={width * 0.3}
              colors={['rgba(255,238,200,0.95)', 'rgba(255,200,120,0.25)', 'rgba(255,200,120,0)']}
            />
          </Circle>
        </Canvas>
        {/* scrim */}
        <View style={styles.scrim} />

        <View style={styles.tag}>
          <View style={styles.tagDot} />
          <Text style={styles.tagText}>SHOT ON LENSMOOD</Text>
        </View>

        <View style={styles.words}>
          <View style={styles.h1Row}>
            <Text style={styles.h1}>Every photo has a </Text>
            <Animated.Text
              key={WORDS[w]}
              entering={FadeInDown.duration(340)}
              exiting={FadeOutUp.duration(280)}
              style={[styles.h1, styles.word]}
            >
              {WORDS[w]}
            </Animated.Text>
          </View>
          <Text style={styles.sub}>The $7,000 camera look, from your camera roll.</Text>
          <Pressable
            onPress={onStart}
            style={({ pressed }) => [styles.cta, pressed && { opacity: 0.92, transform: [{ scale: 0.99 }] }]}
            accessibilityRole="button"
          >
            <Text style={styles.ctaText}>Start with a photo</Text>
          </Pressable>
        </View>
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 28,
    overflow: 'hidden',
    backgroundColor: colors.viewfinder,
  },
  chrome: {
    height: 36,
    paddingHorizontal: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.10)',
  },
  liveRow: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  liveDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.accentLight },
  chromeText: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 10,
    letterSpacing: 1.4,
    fontFamily: MONO,
    fontWeight: '600',
  },
  scrim: {
    // darkened lower half so the words always read over the poster
    ...StyleSheet.absoluteFillObject,
    top: '30%',
    backgroundColor: 'rgba(8,12,16,0.38)',
  },
  tag: {
    position: 'absolute',
    top: 12,
    left: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'rgba(0,0,0,0.45)',
    borderRadius: 999,
    paddingHorizontal: 10,
    height: 24,
  },
  tagDot: { width: 4, height: 4, borderRadius: 2, backgroundColor: colors.accentLight },
  tagText: {
    color: 'rgba(255,255,255,0.9)',
    fontSize: 9,
    letterSpacing: 1.4,
    fontFamily: MONO,
    fontWeight: '600',
  },
  words: { position: 'absolute', left: 16, right: 16, bottom: 16, gap: 6 },
  h1Row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'baseline' },
  h1: {
    color: '#fff',
    fontSize: 28,
    lineHeight: 32,
    fontWeight: '800',
    letterSpacing: -0.4,
    textShadowColor: 'rgba(0,0,0,0.5)',
    textShadowRadius: 12,
    textShadowOffset: { width: 0, height: 1 },
  },
  word: { color: '#e8b25f', fontStyle: 'italic' },
  sub: {
    color: 'rgba(255,255,255,0.85)',
    fontSize: 13,
    textShadowColor: 'rgba(0,0,0,0.55)',
    textShadowRadius: 8,
    textShadowOffset: { width: 0, height: 1 },
  },
  cta: {
    marginTop: 10,
    alignSelf: 'flex-start',
    backgroundColor: '#fff',
    borderRadius: 999,
    paddingHorizontal: 22,
    height: 46,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#0a141c',
    shadowOpacity: 0.35,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 6 },
    elevation: 4,
  },
  ctaText: { color: colors.ink, fontSize: 15, fontWeight: '700' },
})
