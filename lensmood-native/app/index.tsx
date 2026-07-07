/**
 * Home — the ocean entry screen. A LensMood wordmark header over a scrollable
 * two-column grid of all 18 camera stocks. Tapping a card carries its id to
 * the develop screen (/develop?style=<id>).
 */

import { useCallback } from 'react'
import { View, Text, FlatList, StyleSheet, Platform, ListRenderItemInfo } from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { router } from 'expo-router'
import { CAMERA_STYLES } from '@/engine/styles'
import type { CameraStyle } from '@/engine/types'
import { colors } from '@/theme/colors'
import Logo from '@/components/Logo'
import StyleCard from '@/components/StyleCard'

export default function Home() {
  const insets = useSafeAreaInsets()

  const openStyle = useCallback((style: CameraStyle) => {
    router.push({ pathname: '/develop', params: { style: style.id } })
  }, [])

  const renderItem = useCallback(
    ({ item, index }: ListRenderItemInfo<CameraStyle>) => (
      <View style={[styles.cell, index % 2 === 0 ? styles.cellLeft : styles.cellRight]}>
        <StyleCard style={item} onPress={openStyle} />
      </View>
    ),
    [openStyle],
  )

  return (
    <FlatList
      style={styles.list}
      data={CAMERA_STYLES}
      keyExtractor={(s) => s.id}
      numColumns={2}
      renderItem={renderItem}
      showsVerticalScrollIndicator={false}
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + 8, paddingBottom: insets.bottom + 28 },
      ]}
      ListHeaderComponent={
        <View style={styles.header}>
          <Logo markSize={36} wordSize={24} />
          <Text style={styles.kicker}>Develop any photo through a real camera's eye.</Text>
          <Text style={styles.section}>Choose a stock</Text>
        </View>
      }
    />
  )
}

const styles = StyleSheet.create({
  list: { flex: 1, backgroundColor: colors.paper },
  content: { paddingHorizontal: 14 },
  header: { paddingBottom: 12, paddingTop: 6, gap: 10 },
  kicker: {
    color: colors.inkSoft,
    fontSize: 14,
    lineHeight: 20,
    ...Platform.select({ ios: { fontFamily: 'System' }, default: {} }),
  },
  section: {
    marginTop: 6,
    color: colors.ink,
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.4,
    textTransform: 'uppercase',
  },
  cell: { flex: 1, marginBottom: 14 },
  cellLeft: { marginRight: 7 },
  cellRight: { marginLeft: 7 },
})
