/**
 * Gallery — the darkroom's contact sheet. Every develop lands here from the
 * store's history; tap for a large view + share, long-press to remove.
 */

import { useState } from 'react'
import {
  View,
  Text,
  FlatList,
  Image,
  Pressable,
  StyleSheet,
  Alert,
  Modal,
  useWindowDimensions,
} from 'react-native'
import { Stack, router } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import * as Sharing from 'expo-sharing'
import { File } from 'expo-file-system'
import { useApp, haptics, type HistoryEntry } from '@/store'
import BottomDock from '@/components/BottomDock'
import { colors } from '@/theme/colors'

export default function Gallery() {
  const insets = useSafeAreaInsets()
  const { width: screenW } = useWindowDimensions()
  const { history, removeHistory } = useApp()
  const [openEntry, setOpenEntry] = useState<HistoryEntry | null>(null)

  const cell = (screenW - 16 * 2 - 10 * 2) / 3

  const share = async (entry: HistoryEntry) => {
    try {
      // iOS may purge the cache directory — the persisted uri can be gone
      if (entry.thumb.startsWith('file://') && !new File(entry.thumb).exists) {
        Alert.alert(
          'Print faded',
          'iOS cleared this develop from temporary storage. Re-develop the photo to share it again.',
        )
        return
      }
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(entry.thumb, { mimeType: 'image/jpeg', UTI: 'public.jpeg' })
      }
    } catch {
      Alert.alert('Share failed', 'This develop could not be shared.')
    }
  }

  const confirmRemove = (entry: HistoryEntry) => {
    haptics.warning()
    Alert.alert('Remove develop?', `${entry.styleName} — this only removes it from the gallery.`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Remove', style: 'destructive', onPress: () => removeHistory(entry.id) },
    ])
  }

  return (
    <View style={[s.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={s.head}>
        <Text style={s.h1}>Your darkroom.</Text>
        <Text style={s.headSub}>Everything you've developed, kept on this phone.</Text>
      </View>

      {history.length === 0 ? (
        <View style={s.empty}>
          <Text style={s.emptyTitle}>Nothing developed yet.</Text>
          <Text style={s.emptySub}>Your first roll is on the house.</Text>
          <Pressable
            onPress={() => router.push('/develop')}
            style={({ pressed }) => [s.cta, pressed && { opacity: 0.9 }]}
          >
            <Text style={s.ctaText}>Load a photo</Text>
          </Pressable>
        </View>
      ) : (
        <FlatList
          data={history}
          keyExtractor={(e) => e.id}
          numColumns={3}
          columnWrapperStyle={{ gap: 10, paddingHorizontal: 16 }}
          contentContainerStyle={{ gap: 10, paddingBottom: insets.bottom + 116 }}
          showsVerticalScrollIndicator={false}
          renderItem={({ item }) => (
            <Pressable
              onPress={() => setOpenEntry(item)}
              onLongPress={() => confirmRemove(item)}
              style={({ pressed }) => [pressed && { opacity: 0.85 }]}
            >
              <Image source={{ uri: item.thumb }} style={[s.thumb, { width: cell, height: cell * 1.25 }]} />
              <Text style={s.thumbLabel} numberOfLines={1}>
                {item.styleName}
              </Text>
            </Pressable>
          )}
        />
      )}

      {/* large view */}
      <Modal visible={!!openEntry} transparent animationType="fade" onRequestClose={() => setOpenEntry(null)}>
        <View style={s.viewer}>
          {openEntry && (
            <>
              <Image
                source={{ uri: openEntry.thumb }}
                style={{ width: screenW - 32, height: (screenW - 32) * 1.25, borderRadius: 18 }}
                resizeMode="contain"
              />
              <Text style={s.viewerLabel}>{openEntry.styleName}</Text>
              <View style={s.viewerRow}>
                <Pressable onPress={() => share(openEntry)} style={({ pressed }) => [s.viewerBtn, pressed && { opacity: 0.85 }]}>
                  <Text style={s.viewerBtnText}>Share</Text>
                </Pressable>
                <Pressable onPress={() => setOpenEntry(null)} style={({ pressed }) => [s.viewerBtn, s.viewerClose, pressed && { opacity: 0.85 }]}>
                  <Text style={[s.viewerBtnText, { color: colors.ink }]}>Close</Text>
                </Pressable>
              </View>
            </>
          )}
        </View>
      </Modal>

      <BottomDock bottomInset={insets.bottom} />
    </View>
  )
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  head: { paddingHorizontal: 18, paddingTop: 10, paddingBottom: 16, gap: 4 },
  h1: { color: colors.ink, fontSize: 30, fontWeight: '800', letterSpacing: -0.5 },
  headSub: { color: colors.inkSoft, fontSize: 14.5 },

  empty: { alignItems: 'center', marginTop: 60, gap: 6, paddingHorizontal: 32 },
  emptyTitle: { color: colors.ink, fontSize: 17, fontWeight: '700' },
  emptySub: { color: colors.inkSoft, fontSize: 14 },
  cta: {
    marginTop: 16,
    backgroundColor: colors.accent,
    borderRadius: 14,
    height: 48,
    paddingHorizontal: 26,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ctaText: { color: '#fff', fontSize: 15, fontWeight: '700' },

  thumb: { borderRadius: 14, backgroundColor: colors.viewfinder },
  thumbLabel: { color: colors.inkSoft, fontSize: 12, fontWeight: '600', marginTop: 4 },

  viewer: {
    flex: 1,
    backgroundColor: 'rgba(10,14,18,0.92)',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 14,
  },
  viewerLabel: { color: 'rgba(255,255,255,0.85)', fontSize: 15, fontWeight: '700' },
  viewerRow: { flexDirection: 'row', gap: 10 },
  viewerBtn: {
    backgroundColor: colors.accent,
    borderRadius: 12,
    height: 44,
    paddingHorizontal: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewerClose: { backgroundColor: '#fff' },
  viewerBtnText: { color: '#fff', fontSize: 14.5, fontWeight: '700' },
})
