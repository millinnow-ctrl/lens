/**
 * BottomDock — the floating five-tab dock from the web home. Active tab sits
 * in a soft gray pill with the teal icon; Create is the dark center FAB.
 * Pure core-RN so it renders identically in Expo Go.
 */

import { View, Text, Pressable, StyleSheet } from 'react-native'
import { router, usePathname } from 'expo-router'
import Svg, { Path, Rect, Circle } from 'react-native-svg'
import { haptics } from '@/store'
import { colors } from '@/theme/colors'

type TabId = 'home' | 'styles' | 'create' | 'gallery' | 'account'

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
  { id: 'create', label: 'Create', to: '/develop' },
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
                accessibilityLabel="Create"
              >
                <View style={styles.fab}>
                  <Svg width={24} height={24} viewBox="0 0 24 24">
                    <Path d="M12 5v14M5 12h14" stroke="#fbf9f4" strokeWidth={2.4} strokeLinecap="round" />
                  </Svg>
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
