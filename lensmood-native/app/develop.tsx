/**
 * Develop — pick a photo, meter the scene, and run it through the selected
 * camera stock on an offscreen Skia surface. Shows the result in a Skia
 * <Canvas>, a segmented Original / Result toggle, and export to Photos / share.
 *
 * The heavy lifting lives in the engine: analyzeScene() reads the scene on a
 * downscaled thumbnail, renderStyled() develops to a cached JPEG and returns a
 * { uri, width, height } DevelopResult that <Image>, Sharing, and MediaLibrary
 * can all consume directly.
 */

import { useCallback, useMemo, useState } from 'react'
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  Alert,
  useWindowDimensions,
  Platform,
} from 'react-native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { router, useLocalSearchParams, Stack } from 'expo-router'
import { Canvas, Image as SkiaImage, useImage } from '@shopify/react-native-skia'
import * as ImagePicker from 'expo-image-picker'
import * as Sharing from 'expo-sharing'
import * as MediaLibrary from 'expo-media-library'
import { getStyle } from '@/engine/styles'
import { analyzeScene } from '@/engine/scene'
import { develop as developImage, loadImageFromUri } from '@/engine/engine'
import type { DevelopResult } from '@/engine/types'
import { colors } from '@/theme/colors'

type Picked = { uri: string; width: number; height: number }
type ViewMode = 'original' | 'result'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

export default function Develop() {
  const insets = useSafeAreaInsets()
  const { width: screenW } = useWindowDimensions()
  const { style: styleId } = useLocalSearchParams<{ style?: string }>()
  const style = useMemo(() => getStyle(styleId), [styleId])

  const [photo, setPhoto] = useState<Picked | null>(null)
  const [result, setResult] = useState<DevelopResult | null>(null)
  const [developing, setDeveloping] = useState(false)
  const [view, setView] = useState<ViewMode>('result')

  const [libPerm, requestLibPerm] = ImagePicker.useMediaLibraryPermissions()
  const [savePerm, requestSavePerm] = MediaLibrary.usePermissions()

  // Skia decodes both frames; whichever the toggle selects is drawn.
  const originalImg = useImage(photo?.uri ?? null)
  const resultImg = useImage(result?.uri ?? null)

  const develop = useCallback(
    async (picked: Picked) => {
      if (!style) return
      setDeveloping(true)
      setView('result')
      setResult(null)
      try {
        const img = await loadImageFromUri(picked.uri)
        if (!img) throw new Error('That photo could not be decoded.')
        const scene = analyzeScene(img)
        const developed = await developImage(img, style, style.defaults, {
          scene,
          maxSize: 1280,
        })
        setResult(developed)
      } catch (e) {
        Alert.alert('Develop failed', e instanceof Error ? e.message : 'Something went wrong.')
        setView('original')
      } finally {
        setDeveloping(false)
      }
    },
    [style],
  )

  const pickPhoto = useCallback(async () => {
    if (libPerm && !libPerm.granted && libPerm.canAskAgain) {
      const req = await requestLibPerm()
      if (!req.granted) return
    }
    const res = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      quality: 1,
      exif: false,
    })
    if (res.canceled || !res.assets?.length) return
    const a = res.assets[0]
    const picked: Picked = { uri: a.uri, width: a.width ?? 0, height: a.height ?? 0 }
    setPhoto(picked)
    develop(picked)
  }, [libPerm, requestLibPerm, develop])

  const share = useCallback(async () => {
    if (!result) return
    if (!(await Sharing.isAvailableAsync())) {
      Alert.alert('Sharing unavailable', 'This device cannot share files.')
      return
    }
    await Sharing.shareAsync(result.uri, {
      mimeType: 'image/jpeg',
      dialogTitle: 'Share your develop',
      UTI: 'public.jpeg',
    })
  }, [result])

  const saveToPhotos = useCallback(async () => {
    if (!result) return
    if (!savePerm?.granted) {
      const req = await requestSavePerm()
      if (!req.granted) {
        Alert.alert('Permission needed', 'Allow photo access to save to your camera roll.')
        return
      }
    }
    try {
      await MediaLibrary.saveToLibraryAsync(result.uri)
      Alert.alert('Saved', 'Your develop is in Photos.')
    } catch (e) {
      Alert.alert('Save failed', e instanceof Error ? e.message : 'Could not save the image.')
    }
  }, [result, savePerm, requestSavePerm])

  // canvas geometry — fit the frame to the content width, preserve aspect
  const frameW = screenW - 32
  const aspect = photo && photo.width && photo.height ? photo.height / photo.width : 4 / 3
  const frameH = Math.round(frameW * aspect)

  const showingImg = view === 'result' ? resultImg : originalImg
  const canToggle = !!photo && !!result

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false }} />

      {/* top bar */}
      <View style={styles.topbar}>
        <Pressable
          onPress={() => router.back()}
          hitSlop={12}
          style={({ pressed }) => [styles.back, pressed && { opacity: 0.5 }]}
          accessibilityRole="button"
          accessibilityLabel="Back"
        >
          <Text style={styles.backText}>‹ Back</Text>
        </Pressable>
        <View style={styles.titleWrap}>
          <Text style={styles.title} numberOfLines={1}>
            {style?.name ?? 'Develop'}
          </Text>
          {!!style && (
            <Text style={styles.exif} numberOfLines={1}>
              {style.exif}
            </Text>
          )}
        </View>
        <View style={styles.backSpacer} />
      </View>

      {/* stage */}
      <View style={styles.stage}>
        <View
          style={[
            styles.frame,
            { width: frameW, height: Math.min(frameH, screenW * 1.25) },
          ]}
        >
          {photo ? (
            <>
              <Canvas style={StyleSheet.absoluteFill}>
                {showingImg && (
                  <SkiaImage
                    image={showingImg}
                    x={0}
                    y={0}
                    width={frameW}
                    height={Math.min(frameH, screenW * 1.25)}
                    fit="contain"
                  />
                )}
              </Canvas>
              {developing && (
                <View style={styles.developing}>
                  <ActivityIndicator color="#fff" />
                  <Text style={styles.developingText}>developing…</Text>
                </View>
              )}
            </>
          ) : (
            <View style={styles.empty}>
              <Text style={styles.emptyText}>No photo yet</Text>
              <Text style={styles.emptySub}>
                Pick a photo to develop it through {style?.name ?? 'this stock'}.
              </Text>
            </View>
          )}
        </View>

        {/* Original / Result toggle */}
        {canToggle && (
          <View style={styles.segment}>
            {(['original', 'result'] as ViewMode[]).map((m) => {
              const active = view === m
              return (
                <Pressable
                  key={m}
                  onPress={() => setView(m)}
                  style={({ pressed }) => [
                    styles.segItem,
                    active && styles.segItemActive,
                    pressed && { opacity: 0.85 },
                  ]}
                >
                  <Text style={[styles.segText, active && styles.segTextActive]}>
                    {m === 'original' ? 'Original' : 'Result'}
                  </Text>
                </Pressable>
              )
            })}
          </View>
        )}
      </View>

      {/* actions */}
      <View style={[styles.actions, { paddingBottom: insets.bottom + 14 }]}>
        <Pressable
          onPress={pickPhoto}
          style={({ pressed }) => [
            styles.btn,
            styles.btnPrimary,
            pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] },
          ]}
        >
          <Text style={styles.btnPrimaryText}>{photo ? 'Pick another photo' : 'Pick a photo'}</Text>
        </Pressable>

        {result && (
          <View style={styles.exportRow}>
            <Pressable
              onPress={saveToPhotos}
              style={({ pressed }) => [
                styles.btn,
                styles.btnGhost,
                styles.exportBtn,
                pressed && { opacity: 0.85 },
              ]}
            >
              <Text style={styles.btnGhostText}>Save to Photos</Text>
            </Pressable>
            <Pressable
              onPress={share}
              style={({ pressed }) => [
                styles.btn,
                styles.btnSecondary,
                styles.exportBtn,
                pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] },
              ]}
            >
              <Text style={styles.btnSecondaryText}>Share</Text>
            </Pressable>
          </View>
        )}
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  topbar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  back: { width: 64 },
  backSpacer: { width: 64 },
  backText: { color: colors.accent, fontSize: 16, fontWeight: '600' },
  titleWrap: { flex: 1, alignItems: 'center' },
  title: { color: colors.ink, fontSize: 16, fontWeight: '700', letterSpacing: -0.2 },
  exif: { color: colors.fog, fontSize: 10.5, letterSpacing: 0.3, fontFamily: MONO, marginTop: 2 },

  stage: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16, paddingHorizontal: 16 },
  frame: {
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: colors.viewfinder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  empty: { alignItems: 'center', padding: 24, gap: 8 },
  emptyText: { color: 'rgba(255,255,255,0.9)', fontSize: 16, fontWeight: '700' },
  emptySub: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 18,
  },
  developing: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(20,26,31,0.45)',
    gap: 10,
  },
  developingText: { color: '#fff', fontSize: 13, letterSpacing: 0.3, fontFamily: MONO },

  segment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(23,36,45,0.06)',
    borderRadius: 999,
    padding: 4,
  },
  segItem: { paddingHorizontal: 22, paddingVertical: 8, borderRadius: 999 },
  segItemActive: {
    backgroundColor: colors.surface,
    shadowColor: colors.ink,
    shadowOpacity: 0.12,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  segText: { color: colors.inkSoft, fontSize: 14, fontWeight: '600' },
  segTextActive: { color: colors.ink },

  actions: { paddingHorizontal: 16, paddingTop: 8, gap: 10 },
  btn: {
    height: 52,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnPrimary: { backgroundColor: colors.accent },
  btnPrimaryText: { color: '#fff', fontSize: 16, fontWeight: '700' },
  btnSecondary: { backgroundColor: colors.deepTeal },
  btnSecondaryText: { color: '#fff', fontSize: 16, fontWeight: '700' },
  btnGhost: {
    backgroundColor: colors.surface,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.14)',
  },
  btnGhostText: { color: colors.ink, fontSize: 16, fontWeight: '700' },
  exportRow: { flexDirection: 'row', gap: 10 },
  exportBtn: { flex: 1 },
})
