/**
 * Print Lab — the polaroid becomes a physical object. Flash + shutter click,
 * the print ejects from a slot black and undeveloped, chemistry clears it
 * over ~2.7s while it settles onto a staged surface (wood / sand / linen /
 * marble / grass) with a real contact shadow. Share/Save export a Skia
 * composite of the scene — an "iPhone photo of the finished polaroid".
 */

import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  View,
  Text,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Alert,
  useWindowDimensions,
  Platform,
} from 'react-native'
import { Stack, router, useLocalSearchParams } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { StatusBar } from 'expo-status-bar'
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withDelay,
  withSpring,
  withSequence,
  interpolate,
  Easing,
  runOnJS,
} from 'react-native-reanimated'
import * as Sharing from 'expo-sharing'
import * as MediaLibrary from 'expo-media-library'
import DevelopingPrint from '@/print/DevelopingPrint'
import { composeScenePrint } from '@/print/compose'
import { SCENES, type ScenePreset } from '@/print/scenes'
import { usePrintSounds } from '@/print/sounds'
import { haptics } from '@/store'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

/** one print run — remounts per runKey so the full ceremony replays */
function PrintRun({
  uri,
  printW,
  printH,
  scene,
  stageW,
  stageH,
  onSettled,
}: {
  uri: string
  printW: number
  printH: number
  scene: ScenePreset
  stageW: number
  stageH: number
  onSettled: () => void
}) {
  // fixed layout size (largest preset); per-scene size difference rides the
  // transform scale so a scene switch can spring without re-layout
  const BASE = 0.64
  const w = BASE * stageW
  const h = (w * printH) / printW
  const slotY = stageH - 74 // the eject slot bar sits near the bottom

  const eject = useSharedValue(0) // 0 = in slot, 1 = fully out
  const settle = useSharedValue(0) // 0 = eject pose, 1 = scene pose
  const wobble = useSharedValue(0) // deg
  const progress = useSharedValue(0) // chemistry
  // target pose — springs to a new preset when the scene chips change
  const tx = useSharedValue(scene.x)
  const ty = useSharedValue(scene.y)
  const tscale = useSharedValue(scene.scale / BASE)
  const trotZ = useSharedValue(scene.rotateZ)
  const trotX = useSharedValue(scene.rotateX ?? 0)
  const tshadow = useSharedValue(scene.shadow.opacity)

  useEffect(() => {
    eject.value = withDelay(150, withTiming(1, { duration: 900, easing: Easing.out(Easing.cubic) }))
    wobble.value = withDelay(
      150,
      withSequence(
        withTiming(-1.8, { duration: 320, easing: Easing.out(Easing.quad) }),
        withTiming(1.1, { duration: 260 }),
        withSpring(0, { damping: 7, stiffness: 90 }),
      ),
    )
    progress.value = withDelay(
      650,
      withTiming(1, { duration: 2700, easing: Easing.bezier(0.61, 0.02, 0.34, 0.99) }, (done) => {
        if (done) runOnJS(onSettled)()
      }),
    )
    settle.value = withDelay(1100, withSpring(1, { damping: 14, stiffness: 110, mass: 0.9 }))
    // the timeline runs exactly once per mount — runKey remounts for replays
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    // scene switch: the settled print glides to the new spot — chemistry
    // does NOT replay (only "Print again" restarts the ceremony)
    const spring = { damping: 16, stiffness: 120 }
    tx.value = withSpring(scene.x, spring)
    ty.value = withSpring(scene.y, spring)
    tscale.value = withSpring(scene.scale / BASE, spring)
    trotZ.value = withSpring(scene.rotateZ, spring)
    trotX.value = withSpring(scene.rotateX ?? 0, spring)
    tshadow.value = withSpring(scene.shadow.opacity, spring)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scene])

  const pose = useAnimatedStyle(() => {
    const t = settle.value
    // eject pose: centered horizontally, rising out of the slot
    const ejectX = stageW / 2 - w / 2
    const ejectY = slotY - eject.value * (h + 26)
    // scene pose: the art-directed landing spot
    const sceneX = tx.value * stageW - w / 2
    const sceneY = ty.value * stageH - h / 2
    return {
      left: interpolate(t, [0, 1], [ejectX, sceneX]),
      top: interpolate(t, [0, 1], [ejectY, sceneY]),
      transform: [
        { perspective: 800 },
        { rotateX: `${trotX.value * t}deg` },
        { rotateZ: `${wobble.value + trotZ.value * t}deg` },
        { scale: interpolate(t, [0, 1], [1, tscale.value]) },
      ],
      shadowOpacity: tshadow.value * t,
    }
  })

  return (
    <Animated.View
      style={[
        {
          position: 'absolute',
          width: w,
          height: h,
          backgroundColor: '#000', // opaque backing so the iOS shadow follows the pose
          shadowColor: '#02070a',
          shadowRadius: scene.shadow.radius,
          shadowOffset: scene.shadow.offset,
          elevation: 8,
        },
        pose,
      ]}
    >
      <DevelopingPrint uri={uri} width={w} height={h} progress={progress} />
    </Animated.View>
  )
}

export default function PrintLab() {
  const insets = useSafeAreaInsets()
  const { width: screenW, height: screenH } = useWindowDimensions()
  const params = useLocalSearchParams<{ uri?: string; w?: string; h?: string }>()
  const uri = typeof params.uri === 'string' ? params.uri : ''
  const printW = Number(params.w) || 0
  const printH = Number(params.h) || 0

  const sounds = usePrintSounds()
  const [scene, setScene] = useState<ScenePreset>(SCENES[0])
  const [runKey, setRunKey] = useState(0)
  const [settled, setSettled] = useState(false)
  const [composing, setComposing] = useState(false)
  const [savePerm, requestSavePerm] = MediaLibrary.usePermissions()
  const flash = useSharedValue(0)

  // invalid deep-link / missing params → straight back
  useEffect(() => {
    if (!uri || !printW || !printH) router.back()
  }, [uri, printW, printH])

  const stageW = screenW
  const stageH = Math.min(screenH * 0.62, stageW * 1.32)

  const firePrint = useCallback(() => {
    setSettled(false)
    haptics.heavy()
    sounds.shutter()
    flash.value = 1
    flash.value = withTiming(0, { duration: 260, easing: Easing.out(Easing.quad) })
    setTimeout(() => sounds.motor(), 150)
    setTimeout(() => haptics.light(), 1100)
  }, [sounds, flash])

  // the ceremony auto-fires on arrival, and re-fires on every "Print again"
  useEffect(() => {
    if (!uri) return
    firePrint()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runKey])

  const onSettled = useCallback(() => {
    setSettled(true)
    haptics.success()
  }, [])

  const selectScene = useCallback((s: ScenePreset) => {
    haptics.selection()
    setScene(s)
  }, [])

  const compose = useCallback(async (): Promise<string | null> => {
    setComposing(true)
    try {
      const out = await composeScenePrint(uri, printW, printH, scene)
      return out.uri
    } catch (e) {
      Alert.alert('Export failed', e instanceof Error ? e.message : 'Something went wrong.')
      return null
    } finally {
      setComposing(false)
    }
  }, [uri, printW, printH, scene])

  const share = useCallback(async () => {
    const out = await compose()
    if (!out) return
    if (!(await Sharing.isAvailableAsync())) {
      Alert.alert('Sharing unavailable', 'This device cannot share files.')
      return
    }
    await Sharing.shareAsync(out, {
      mimeType: 'image/jpeg',
      dialogTitle: 'Share your print',
      UTI: 'public.jpeg',
    })
  }, [compose])

  const saveToPhotos = useCallback(async () => {
    const out = await compose()
    if (!out) return
    if (!savePerm?.granted) {
      const req = await requestSavePerm()
      if (!req.granted) {
        Alert.alert('Permission needed', 'Allow photo access to save to your camera roll.')
        return
      }
    }
    try {
      await MediaLibrary.saveToLibraryAsync(out)
      haptics.success()
      Alert.alert('Saved', 'Your print is in Photos.')
    } catch (e) {
      Alert.alert('Save failed', e instanceof Error ? e.message : 'Could not save the image.')
    }
  }, [compose, savePerm, requestSavePerm])

  const flashStyle = useAnimatedStyle(() => ({ opacity: flash.value }))
  const sceneIndex = useMemo(() => SCENES.findIndex((s) => s.id === scene.id), [scene])

  if (!uri) return null

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false, animation: 'fade_from_bottom' }} />
      <StatusBar style="light" />

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
        <Text style={styles.title}>PRINT LAB</Text>
        <View style={styles.back} />
      </View>

      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}
        showsVerticalScrollIndicator={false}
      >
        {/* stage */}
        <View style={[styles.stage, { width: stageW, height: stageH }]}>
          <Image
            source={scene.plate}
            style={StyleSheet.absoluteFill}
            resizeMode="cover"
            accessibilityIgnoresInvertColors
          />
          {/* eject slot */}
          <View style={styles.slot} />
          <PrintRun
            key={`run-${runKey}`}
            uri={uri}
            printW={printW}
            printH={printH}
            scene={scene}
            stageW={stageW}
            stageH={stageH}
            onSettled={onSettled}
          />
          {/* shutter flash */}
          <Animated.View pointerEvents="none" style={[styles.flash, flashStyle]} />
        </View>

        {/* scene chips */}
        <Text style={styles.sectionLabel}>SET THE SCENE</Text>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chips}
        >
          {SCENES.map((s, i) => {
            const active = s.id === scene.id
            return (
              <Pressable
                key={s.id}
                onPress={() => selectScene(s)}
                accessibilityRole="button"
                accessibilityState={{ selected: active }}
                style={({ pressed }) => [
                  styles.chip,
                  active && styles.chipActive,
                  pressed && { opacity: 0.85 },
                ]}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>{s.label}</Text>
              </Pressable>
            )
          })}
        </ScrollView>

        {/* actions */}
        <View style={styles.actions}>
          <Pressable
            onPress={() => setRunKey((k) => k + 1)}
            style={({ pressed }) => [styles.btn, styles.btnGhost, pressed && { opacity: 0.85 }]}
          >
            <Text style={styles.btnGhostText}>Print again</Text>
          </Pressable>
          <View style={styles.exportRow}>
            <Pressable
              onPress={saveToPhotos}
              disabled={composing || !settled}
              style={({ pressed }) => [
                styles.btn,
                styles.btnGhost,
                styles.exportBtn,
                (composing || !settled) && { opacity: 0.5 },
                pressed && { opacity: 0.85 },
              ]}
            >
              <Text style={styles.btnGhostText}>Save to Photos</Text>
            </Pressable>
            <Pressable
              onPress={share}
              disabled={composing || !settled}
              style={({ pressed }) => [
                styles.btn,
                styles.btnPrimary,
                styles.exportBtn,
                (composing || !settled) && { opacity: 0.6 },
                pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] },
              ]}
            >
              {composing ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.btnPrimaryText}>Share the shot</Text>
              )}
            </Pressable>
          </View>
          <Text style={styles.hint}>
            {settled
              ? `Scene ${sceneIndex + 1} of ${SCENES.length} — exports look like a photo you took of the print.`
              : 'developing…'}
          </Text>
        </View>
      </ScrollView>
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.viewfinder },
  topbar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  back: { width: 64 },
  backText: { color: '#9fdceb', fontSize: 16, fontWeight: '600' },
  title: {
    flex: 1,
    textAlign: 'center',
    color: 'rgba(255,255,255,0.92)',
    fontSize: 12,
    letterSpacing: 2.2,
    fontFamily: MONO,
    fontWeight: '600',
  },

  stage: { overflow: 'hidden', backgroundColor: '#0b0f12' },
  slot: {
    position: 'absolute',
    left: '14%',
    right: '14%',
    bottom: 64,
    height: 10,
    borderRadius: 5,
    backgroundColor: 'rgba(6,9,11,0.85)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.14)',
  },
  flash: { ...StyleSheet.absoluteFillObject, backgroundColor: '#fff' },

  sectionLabel: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 10,
    letterSpacing: 1.6,
    fontFamily: MONO,
    fontWeight: '600',
    paddingHorizontal: 18,
    marginTop: 16,
    marginBottom: 8,
  },
  chips: { paddingHorizontal: 14, gap: 8 },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 9,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.16)',
  },
  chipActive: { backgroundColor: '#fff', borderColor: '#fff' },
  chipText: { color: 'rgba(255,255,255,0.85)', fontSize: 13.5, fontWeight: '600' },
  chipTextActive: { color: colors.ink },

  actions: { paddingHorizontal: 16, paddingTop: 18, gap: 10 },
  btn: { height: 52, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  btnPrimary: { backgroundColor: colors.accent },
  btnPrimaryText: { color: '#fff', fontSize: 16, fontWeight: '700' },
  btnGhost: {
    backgroundColor: 'rgba(255,255,255,0.09)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.2)',
  },
  btnGhostText: { color: 'rgba(255,255,255,0.95)', fontSize: 16, fontWeight: '700' },
  exportRow: { flexDirection: 'row', gap: 10 },
  exportBtn: { flex: 1 },
  hint: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 11.5,
    fontFamily: MONO,
    textAlign: 'center',
    paddingVertical: 4,
  },
})
