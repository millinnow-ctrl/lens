/**
 * Print Room — the polaroid becomes a physical object you can post. Opened
 * from the dock it's a shelf of your developed shots; pick one, hit PRINT:
 * flash + shutter click, a real film clip of the printer ejecting the black
 * undeveloped print, then YOUR print develops (~2.7s chemistry) and settles
 * onto a staged surface (wood / sand / linen / marble / grass) with a real
 * contact shadow. Share/Save export a Skia composite — an "iPhone photo of
 * the finished polaroid".
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
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
import { VideoView, useVideoPlayer } from 'expo-video'
import DevelopingPrint from '@/print/DevelopingPrint'
import { composeScenePrint } from '@/print/compose'
import { SCENES, type ScenePreset } from '@/print/scenes'
import { usePrintSounds } from '@/print/sounds'
import { useApp, haptics } from '@/store'
import { colors } from '@/theme/colors'

/** the printer clip — a real film of the black undeveloped print ejecting.
 *  Generic on purpose: the SAME clip plays for every photo (the machine is
 *  the constant; your photo is what develops after). */
const EJECT_CLIP = require('../assets/print/eject.mp4')
const EJECT_MS = 3000 // hard fallback if playback stalls

/** the fullscreen printing clip that opens the ceremony */
function EjectClip({ onDone }: { onDone: () => void }) {
  const done = useRef(false)
  const finish = useCallback(() => {
    if (done.current) return
    done.current = true
    onDone()
  }, [onDone])
  const player = useVideoPlayer(EJECT_CLIP, (p) => {
    p.loop = false
    p.muted = true
    p.play()
  })
  useEffect(() => {
    const sub = player.addListener('playToEnd', finish)
    const t = setTimeout(finish, EJECT_MS + 800)
    return () => {
      sub.remove()
      clearTimeout(t)
    }
  }, [player, finish])
  return (
    <View style={StyleSheet.absoluteFill}>
      <VideoView
        player={player}
        style={StyleSheet.absoluteFill}
        contentFit="cover"
        nativeControls={false}
      />
    </View>
  )
}

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

type Picked = { uri: string; w: number; h: number }
type Phase = 'idle' | 'clip' | 'run'

export default function PrintRoom() {
  const insets = useSafeAreaInsets()
  const { width: screenW, height: screenH } = useWindowDimensions()
  const params = useLocalSearchParams<{ uri?: string; w?: string; h?: string }>()
  const fromDevelop =
    typeof params.uri === 'string' && Number(params.w) > 0 && Number(params.h) > 0
  const { history } = useApp()

  // opened from the dock: a shelf of your developed shots; from Develop: preloaded
  const [pick, setPick] = useState<Picked | null>(() =>
    fromDevelop ? { uri: params.uri as string, w: Number(params.w), h: Number(params.h) } : null,
  )
  const [phase, setPhase] = useState<Phase>('idle')

  const sounds = usePrintSounds()
  const [scene, setScene] = useState<ScenePreset>(SCENES[0])
  const [runKey, setRunKey] = useState(0)
  const [settled, setSettled] = useState(false)
  const [composing, setComposing] = useState(false)
  const [savePerm, requestSavePerm] = MediaLibrary.usePermissions()
  const flash = useSharedValue(0)

  const uri = pick?.uri ?? ''
  const printW = pick?.w ?? 0
  const printH = pick?.h ?? 0

  const stageW = screenW
  const stageH = Math.min(screenH * 0.62, stageW * 1.32)

  /** PRINT: snap-flash + shutter click, then the printer clip, then the run */
  const firePrint = useCallback(() => {
    setSettled(false)
    haptics.heavy()
    sounds.shutter()
    flash.value = 1
    flash.value = withTiming(0, { duration: 260, easing: Easing.out(Easing.quad) })
    setPhase('clip')
    setTimeout(() => sounds.motor(), 250)
  }, [sounds, flash])

  const onClipDone = useCallback(() => {
    setPhase('run')
    setRunKey((k) => k + 1)
    setTimeout(() => haptics.light(), 500)
  }, [])

  /** pick a shot from the shelf — read its true pixel size, then arm the stage */
  const pickShot = useCallback((thumb: string) => {
    haptics.selection()
    Image.getSize(
      thumb,
      (w, h) => {
        setSettled(false)
        setPhase('idle')
        setPick({ uri: thumb, w, h })
      },
      () => Alert.alert('Print error', 'That shot could not be read.'),
    )
  }, [])

  const goBack = useCallback(() => {
    if (pick && !fromDevelop) {
      // back to the shelf, not out of the room
      setPick(null)
      setPhase('idle')
      setSettled(false)
      return
    }
    if (router.canGoBack()) router.back()
    else router.replace('/')
  }, [pick, fromDevelop])

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

  /* ---- the shelf: pick which shot to print (dock entry, nothing picked) ---- */
  if (!pick) {
    return (
      <View style={[styles.root, { paddingTop: insets.top }]}>
        <Stack.Screen options={{ headerShown: false, animation: 'fade_from_bottom' }} />
        <StatusBar style="light" />
        <View style={styles.topbar}>
          <Pressable
            onPress={goBack}
            hitSlop={12}
            style={({ pressed }) => [styles.back, pressed && { opacity: 0.5 }]}
            accessibilityRole="button"
            accessibilityLabel="Back"
          >
            <Text style={styles.backText}>‹ Back</Text>
          </Pressable>
          <Text style={styles.title}>PRINT ROOM</Text>
          <View style={styles.back} />
        </View>
        {history.length === 0 ? (
          <View style={styles.emptyWrap}>
            <Text style={styles.emptyTitle}>Nothing to print yet</Text>
            <Text style={styles.emptyBody}>
              Develop a shot with any lens, then bring it here to print it and stage it on a real
              surface.
            </Text>
            <Pressable
              onPress={() => router.push('/')}
              style={({ pressed }) => [styles.btn, styles.btnPrimary, styles.emptyBtn, pressed && { opacity: 0.9 }]}
            >
              <Text style={styles.btnPrimaryText}>Pick a lens</Text>
            </Pressable>
          </View>
        ) : (
          <ScrollView
            style={{ flex: 1 }}
            contentContainerStyle={{ paddingBottom: insets.bottom + 96 }}
            showsVerticalScrollIndicator={false}
          >
            <Text style={styles.sectionLabel}>YOUR SHOTS — TAP ONE TO PRINT</Text>
            <View style={styles.shelf}>
              {history.map((h) => (
                <Pressable
                  key={h.id}
                  onPress={() => pickShot(h.thumb)}
                  accessibilityRole="button"
                  accessibilityLabel={`Print your ${h.styleName} shot`}
                  style={({ pressed }) => [styles.shelfCard, pressed && { opacity: 0.85 }]}
                >
                  <View style={styles.shelfPaper}>
                    <Image source={{ uri: h.thumb }} style={styles.shelfImg} resizeMode="cover" />
                    <Text numberOfLines={1} style={styles.shelfCaption}>
                      {h.styleName}
                    </Text>
                  </View>
                </Pressable>
              ))}
            </View>
          </ScrollView>
        )}
      </View>
    )
  }

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false, animation: 'fade_from_bottom' }} />
      <StatusBar style="light" />

      {/* top bar */}
      <View style={styles.topbar}>
        <Pressable
          onPress={goBack}
          hitSlop={12}
          style={({ pressed }) => [styles.back, pressed && { opacity: 0.5 }]}
          accessibilityRole="button"
          accessibilityLabel="Back"
        >
          <Text style={styles.backText}>‹ Back</Text>
        </Pressable>
        <Text style={styles.title}>PRINT ROOM</Text>
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
          {phase === 'run' && (
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
          )}
          {/* the printer film clip — the black print ejects, same for every shot */}
          {phase === 'clip' && <EjectClip onDone={onClipDone} />}
          {/* armed: the big PRINT moment */}
          {phase === 'idle' && (
            <View style={styles.armWrap}>
              <Pressable
                onPress={firePrint}
                accessibilityRole="button"
                accessibilityLabel="Print this shot"
                style={({ pressed }) => [styles.printBtn, pressed && { transform: [{ scale: 0.97 }] }]}
              >
                <Text style={styles.printBtnText}>PRINT</Text>
              </Pressable>
            </View>
          )}
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
          {phase !== 'idle' && (
            <Pressable
              onPress={firePrint}
              disabled={phase === 'clip'}
              style={({ pressed }) => [
                styles.btn,
                styles.btnGhost,
                phase === 'clip' && { opacity: 0.5 },
                pressed && { opacity: 0.85 },
              ]}
            >
              <Text style={styles.btnGhostText}>Print again</Text>
            </Pressable>
          )}
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
              : phase === 'idle'
                ? 'press PRINT — flash, eject, and watch it develop.'
                : phase === 'clip'
                  ? 'printing…'
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

  /* the armed PRINT moment */
  armWrap: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'flex-end',
    paddingBottom: 108,
  },
  printBtn: {
    paddingHorizontal: 44,
    height: 58,
    borderRadius: 29,
    backgroundColor: colors.accent,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#02070a',
    shadowOpacity: 0.45,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 8 },
    elevation: 8,
  },
  printBtnText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '800',
    letterSpacing: 3,
    fontFamily: MONO,
  },

  /* the shelf — your developed shots as small paper prints */
  shelf: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 14,
    gap: 12,
  },
  shelfCard: { width: '30.5%' },
  shelfPaper: {
    backgroundColor: '#fdfcf8',
    borderRadius: 4,
    padding: 5,
    paddingBottom: 4,
    shadowColor: '#02070a',
    shadowOpacity: 0.4,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  shelfImg: { width: '100%', aspectRatio: 3 / 4, borderRadius: 2, backgroundColor: '#111' },
  shelfCaption: {
    color: '#3a3f45',
    fontSize: 9,
    fontFamily: MONO,
    textAlign: 'center',
    paddingTop: 4,
  },
  emptyWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 36, gap: 10 },
  emptyTitle: { color: 'rgba(255,255,255,0.95)', fontSize: 20, fontWeight: '800' },
  emptyBody: { color: 'rgba(255,255,255,0.55)', fontSize: 14, textAlign: 'center', lineHeight: 20 },
  emptyBtn: { alignSelf: 'stretch', marginTop: 10 },
})
