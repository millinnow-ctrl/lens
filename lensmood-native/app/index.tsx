/**
 * Home — the ocean entry screen. Living hero (rotating word + start CTA),
 * category chips over the 18-stock catalog, floating bottom dock.
 */

import { useCallback, useMemo, useState } from 'react'
import {
  View,
  Text,
  FlatList,
  Pressable,
  StyleSheet,
  useWindowDimensions,
  type ListRenderItemInfo,
} from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { router } from 'expo-router'
import { CAMERA_STYLES } from '@/engine/styles'
import type { CameraStyle } from '@/engine/types'
import { colors } from '@/theme/colors'
import Logo from '@/components/Logo'
import StyleCard from '@/components/StyleCard'
import HeroCard from '@/components/HeroCard'
import BottomDock from '@/components/BottomDock'

/** which looks belong to which shelf */
const CATEGORIES = [
  { id: 'all', label: 'All' },
  { id: 'film', label: 'Film' },
  { id: 'flash', label: 'Flash' },
  { id: 'video', label: 'Video' },
  { id: 'editorial', label: 'Editorial' },
  { id: 'bw', label: 'B&W' },
] as const
type CategoryId = (typeof CATEGORIES)[number]['id']

const CATEGORY_STYLES: Record<CategoryId, string[]> = {
  all: [],
  film: ['disposable', 'leica-street', 'a24-still', 'film-noir', 'polaroid', 'super-8', 'lomo', 'kodachrome', 'tintype'],
  flash: ['iphone-flash', 'y2k-digicam', 'disposable', 'photobooth', 'tokyo-neon', 'point-shoot'],
  video: ['camcorder-90s', 'y2k-digicam', 'security-cam', 'super-8'],
  editorial: ['gq-editorial', 'leica-street', 'a24-still', 'pastel-cinema'],
  bw: ['film-noir', 'tintype', 'photobooth', 'security-cam'],
}

export default function Home() {
  const insets = useSafeAreaInsets()
  const { width: screenW } = useWindowDimensions()
  const [category, setCategory] = useState<CategoryId>('all')

  const shelf = useMemo(() => {
    if (category === 'all') return CAMERA_STYLES
    const ids = CATEGORY_STYLES[category]
    return CAMERA_STYLES.filter((st) => ids.includes(st.id))
  }, [category])

  const openStyle = useCallback((style: CameraStyle) => {
    router.push({ pathname: '/develop', params: { style: style.id } })
  }, [])

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<CameraStyle>) => (
      <View style={[s.cell, index % 2 === 0 ? s.cellLeft : s.cellRight]}>
        <StyleCard style={item} onPress={openStyle} />
      </View>
    ),
    [openStyle],
  )

  const Header = (
    <View>
      {/* brand lockup */}
      <View style={s.header}>
        <Logo />
        <Pressable
          onPress={() => router.push('/paywall')}
          style={({ pressed }) => [s.proPill, pressed && { opacity: 0.85 }]}
          accessibilityRole="button"
          accessibilityLabel="See plans"
        >
          <Text style={s.proText}>Pro</Text>
        </Pressable>
      </View>

      <HeroCard width={screenW - 28} onStart={() => router.push('/develop')} />

      {/* video — the camcorder is the whole story, so it gets one big card */}
      <View style={s.caseHead}>
        <Text style={s.h2}>Video</Text>
      </View>
      <Pressable
        onPress={() => router.push('/tape')}
        accessibilityRole="button"
        accessibilityLabel="Open the camcorder"
        style={({ pressed }) => [s.videoCard, pressed && { transform: [{ scale: 0.985 }] }]}
      >
        <View style={s.videoRecRow}>
          <View style={s.videoRecDot} />
          <Text style={s.videoRecText}>REC</Text>
          <Text style={[s.videoRecText, { marginLeft: 'auto' }]}>SP · 0:00:00</Text>
        </View>
        <Text style={s.videoTitle}>Camcorder</Text>
        <Text style={s.videoSub}>
          Drop in a clip and it films like 1994 — tape grain, counting timecode, that VHS color.
        </Text>
        <View style={s.videoCtaPill}>
          <Text style={s.videoCtaText}>Pick a clip ›</Text>
        </View>
      </Pressable>

      {/* the case */}
      <View style={s.caseHead}>
        <Text style={s.h2}>Explore looks</Text>
        <Text style={s.h2sub}>{CAMERA_STYLES.length} cameras, one tap each</Text>
      </View>
      <FlatList
        horizontal
        data={CATEGORIES as unknown as { id: CategoryId; label: string }[]}
        keyExtractor={(c) => c.id}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={s.chips}
        renderItem={({ item }) => {
          const on = category === item.id
          return (
            <Pressable onPress={() => setCategory(item.id)} style={[s.chip, on && s.chipOn]}>
              <Text style={[s.chipText, on && s.chipTextOn]}>{item.label}</Text>
            </Pressable>
          )
        }}
      />
    </View>
  )

  return (
    <View style={s.root}>
      <FlatList
        data={shelf}
        keyExtractor={(item) => item.id}
        renderItem={renderItem}
        numColumns={2}
        ListHeaderComponent={Header}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={[
          s.content,
          { paddingTop: insets.top + 6, paddingBottom: insets.bottom + 116 },
        ]}
      />
      <BottomDock bottomInset={insets.bottom} />
    </View>
  )
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  content: { paddingHorizontal: 14 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingBottom: 8,
  },
  proPill: {
    backgroundColor: colors.surface,
    borderRadius: 999,
    paddingHorizontal: 18,
    height: 38,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.10)',
  },
  proText: { color: colors.ink, fontSize: 15, fontWeight: '700' },

  caseHead: { marginTop: 22, gap: 2, paddingHorizontal: 2 },
  h2: { color: colors.ink, fontSize: 26, fontWeight: '800', letterSpacing: -0.4 },
  h2sub: { color: colors.fog, fontSize: 14, fontWeight: '500' },

  videoCard: {
    marginTop: 12,
    borderRadius: 22,
    backgroundColor: colors.viewfinder,
    padding: 20,
    gap: 6,
    shadowColor: '#02070a',
    shadowOpacity: 0.28,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 8 },
    elevation: 6,
  },
  videoRecRow: { flexDirection: 'row', alignItems: 'center', gap: 7, marginBottom: 6 },
  videoRecDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#e1251b' },
  videoRecText: {
    color: 'rgba(255,240,220,0.9)',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
  },
  videoTitle: { color: '#fff', fontSize: 24, fontWeight: '800', letterSpacing: -0.4 },
  videoSub: { color: 'rgba(255,255,255,0.68)', fontSize: 14, lineHeight: 19 },
  videoCtaPill: {
    alignSelf: 'flex-start',
    marginTop: 10,
    backgroundColor: colors.accent,
    borderRadius: 999,
    paddingHorizontal: 18,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  videoCtaText: { color: '#fff', fontSize: 14.5, fontWeight: '700' },

  chips: { gap: 8, paddingVertical: 12, paddingHorizontal: 2 },
  chip: {
    paddingHorizontal: 16,
    height: 36,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surface,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.10)',
  },
  chipOn: { backgroundColor: colors.accent, borderColor: colors.accent },
  chipText: { color: colors.inkSoft, fontSize: 13.5, fontWeight: '600' },
  chipTextOn: { color: '#fff' },

  cell: { flex: 1, marginBottom: 14 },
  cellLeft: { marginRight: 7 },
  cellRight: { marginLeft: 7 },
})
