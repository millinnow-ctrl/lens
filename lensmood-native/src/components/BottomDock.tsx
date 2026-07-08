/**
 * BottomDock — the floating five-tab dock from the web home. Active tab sits
 * in a soft gray pill with the teal icon; Create is the dark center FAB.
 * Pure core-RN so it renders identically in Expo Go.
 */

import { View, Text, Pressable, StyleSheet } from 'react-native'
import { router, usePathname } from 'expo-router'
import Svg, {
  Path,
  Rect,
  Circle,
  Defs,
  LinearGradient,
  RadialGradient,
  Stop,
  Ellipse,
} from 'react-native-svg'
import { haptics } from '@/store'
import { colors } from '@/theme/colors'

type TabId = 'home' | 'styles' | 'create' | 'gallery' | 'account'

/** the LM-1 — a 3D drawing of a Canon-class DSLR: inked outlines, graphite
 *  body with a top-light, rounded EOS pentaprism hump, gripped right side,
 *  and the signature red ring on the lens. Reads like the real object. */
function DslrIcon() {
  return (
    <Svg width={32} height={32} viewBox="0 0 32 32">
      <Defs>
        <LinearGradient id="lmBody" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#95a4b1" />
          <Stop offset="0.3" stopColor="#5f7080" />
          <Stop offset="1" stopColor="#1e2933" />
        </LinearGradient>
        <LinearGradient id="lmPrism" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#7a8b99" />
          <Stop offset="1" stopColor="#2b3843" />
        </LinearGradient>
        <LinearGradient id="lmGrip" x1="0" y1="0" x2="1" y2="0">
          <Stop offset="0" stopColor="#161f28" />
          <Stop offset="1" stopColor="#3d4c5e" />
        </LinearGradient>
        <RadialGradient id="lmGlass" cx="0.38" cy="0.34" r="0.85">
          <Stop offset="0" stopColor="#4585b3" />
          <Stop offset="0.5" stopColor="#143650" />
          <Stop offset="1" stopColor="#07121d" />
        </RadialGradient>
      </Defs>
      {/* pentaprism hump — the EOS silhouette, rounded */}
      <Path
        d="M11 8.4c0-2 1.6-3.6 3.4-3.6h3.2c1.8 0 3.4 1.6 3.4 3.6Z"
        fill="url(#lmPrism)"
        stroke="#0d151c"
        strokeWidth="0.7"
      />
      {/* shutter nub + mode dial */}
      <Rect x="5.4" y="5.9" width="4.2" height="2.9" rx="1.4" fill={colors.accent} stroke="#0d151c" strokeWidth="0.6" />
      <Rect x="23" y="6.1" width="3.8" height="2.5" rx="1.1" fill="#4a5a68" stroke="#0d151c" strokeWidth="0.6" />
      {/* body — inked outline reads as a drawing */}
      <Rect x="2.4" y="8.2" width="27.2" height="18.2" rx="3.8" fill="url(#lmBody)" stroke="#0d151c" strokeWidth="0.9" />
      {/* grip with finger notch */}
      <Path
        d="M25.4 9.6h2c1.1 0 2 .9 2 2v11.2c0 1.1-.9 2-2 2h-2c-.7 0-1.2-.7-1-1.4.8-2.4.8-9.9 0-12.4-.2-.7.3-1.4 1-1.4Z"
        fill="url(#lmGrip)"
        stroke="#0d151c"
        strokeWidth="0.7"
      />
      {/* lens barrel */}
      <Circle cx="14.4" cy="17.3" r="7.6" fill="#0c141c" stroke="#0d151c" strokeWidth="0.9" />
      {/* THE red ring */}
      <Circle cx="14.4" cy="17.3" r="6.5" fill="none" stroke="#d92b2b" strokeWidth="1.5" />
      <Circle cx="14.4" cy="17.3" r="5.2" fill="none" stroke="#45535f" strokeWidth="0.9" />
      {/* glass + glint */}
      <Circle cx="14.4" cy="17.3" r="4.2" fill="url(#lmGlass)" />
      <Ellipse cx="12.8" cy="15.5" rx="1.7" ry="1.1" fill="rgba(255,255,255,0.6)" />
    </Svg>
  )
}

const ICON = (id: TabId, color: string) => {
  const p = { stroke: color, strokeWidth: 1.8, fill: 'none' as const, strokeLinecap: 'round' as const }
  switch (id) {
    case 'home':
      return (
        <Svg width={22} height={22} viewBox="0 0 24 24">
          <Path d="M4 11.5 12 4l8 7.5" {...p} />
          <Path d="M6.5 10.5V20h11v-9.5" {...p} />
        </Svg>
      )
    case 'styles':
      return (
        <Svg width={22} height={22} viewBox="0 0 24 24">
          <Rect x="4" y="4" width="7" height="7" rx="2" {...p} />
          <Rect x="13" y="4" width="7" height="7" rx="2" {...p} />
          <Rect x="4" y="13" width="7" height="7" rx="2" {...p} />
          <Rect x="13" y="13" width="7" height="7" rx="2" {...p} />
        </Svg>
      )
    case 'gallery':
      return (
        <Svg width={22} height={22} viewBox="0 0 24 24">
          <Rect x="4" y="5" width="16" height="14" rx="3" {...p} />
          <Circle cx="9" cy="10" r="1.6" {...p} />
          <Path d="M5 17.5 10 13l4 3.5 2.5-2 2.5 2" {...p} />
        </Svg>
      )
    case 'account':
      return (
        <Svg width={22} height={22} viewBox="0 0 24 24">
          <Circle cx="12" cy="8.5" r="3.4" {...p} />
          <Path d="M5.5 19.5c1.2-3.4 3.6-5 6.5-5s5.3 1.6 6.5 5" {...p} />
        </Svg>
      )
    default:
      return null
  }
}

const TABS: { id: TabId; label: string; to: string }[] = [
  { id: 'home', label: 'Home', to: '/' },
  { id: 'styles', label: 'Styles', to: '/develop' },
  { id: 'create', label: 'Camera', to: '/camera' },
  { id: 'gallery', label: 'Gallery', to: '/gallery' },
  { id: 'account', label: 'Account', to: '/account' },
]

export default function BottomDock({ bottomInset }: { bottomInset: number }) {
  const pathname = usePathname()
  const activeId: TabId | '' =
    pathname === '/' ? 'home' : pathname.startsWith('/develop') ? 'styles' : pathname.startsWith('/gallery') ? 'gallery' : ''

  return (
    <View style={[styles.wrap, { bottom: bottomInset + 10 }]} pointerEvents="box-none">
      <View style={styles.dock}>
        {TABS.map((t) => {
          const active = t.id === activeId
          if (t.id === 'create') {
            return (
              <Pressable
                key={t.id}
                onPress={() => {
                  haptics.medium()
                  router.push(t.to)
                }}
                style={styles.tab}
                accessibilityRole="button"
                accessibilityLabel="Camera — shoot with the LM-1 pro body"
              >
                <View style={styles.fab}>
                  <DslrIcon />
                </View>
                <Text style={[styles.label, { color: colors.ink, fontWeight: '600' }]}>{t.label}</Text>
              </Pressable>
            )
          }
          const tint = active ? colors.accent : colors.fog
          return (
            <Pressable
              key={t.id}
              onPress={() => {
                haptics.light()
                router.push(t.to)
              }}
              style={styles.tab}
              accessibilityRole="button"
              accessibilityLabel={t.label}
            >
              <View style={[styles.iconPill, active && styles.iconPillActive]}>{ICON(t.id, tint)}</View>
              <Text style={[styles.label, { color: tint }, active && { fontWeight: '600' }]}>{t.label}</Text>
            </Pressable>
          )
        })}
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 16, right: 16 },
  dock: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.94)',
    borderRadius: 30,
    paddingVertical: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.08)',
    shadowColor: '#121f2b',
    shadowOpacity: 0.18,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 10 },
    elevation: 8,
  },
  tab: { flex: 1, alignItems: 'center', gap: 3 },
  iconPill: {
    height: 28,
    paddingHorizontal: 14,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconPillActive: { backgroundColor: 'rgba(23,36,45,0.06)' },
  fab: {
    marginTop: -26,
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: colors.ink,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    shadowColor: '#0a141c',
    shadowOpacity: 0.3,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 5 },
    elevation: 6,
  },
  label: { fontSize: 10.5 },
})
