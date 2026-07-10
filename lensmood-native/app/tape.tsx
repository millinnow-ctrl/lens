/**
 * Tape — the camcorder processes real video. Pick a clip and it plays back
 * through the fixed 1994 tape look, live: the VHS color grade + chroma bleed +
 * grain + vignette run per-pixel on the GPU over every frame, with a counting
 * REC timecode burned over the top. No AI, no dials — one preset, like a
 * camcorder had. Save/Share hand the clip to the native exporter, which bakes
 * the SAME grade (via a LUT built from vhsGrade) into a real .mp4.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  Alert,
  PixelRatio,
  Platform,
  useWindowDimensions,
} from 'react-native'
import { Stack, router } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { StatusBar } from 'expo-status-bar'
import {
  Canvas,
  Group,
  Paint,
  Image as SkiaImage,
  RuntimeShader,
  Skia,
  fitbox,
  rect,
  useVideo,
} from '@shopify/react-native-skia'
import {
  useSharedValue,
  useDerivedValue,
  useAnimatedReaction,
  runOnJS,
} from 'react-native-reanimated'
import * as ImagePicker from 'expo-image-picker'
import * as Sharing from 'expo-sharing'
import * as MediaLibrary from 'expo-media-library'
import { VHS_SKSL, buildVhsLut } from '@/engine/vhsLook'
import { exportVhsVideo, vhsExportAvailable } from '../modules/vhs-export'
import { haptics } from '@/store'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })
const VHS_EFFECT = Skia.RuntimeEffect.Make(VHS_SKSL)!
const MAX_SECONDS = 60

function pad2(n: number) {
  return n < 10 ? `0${n}` : `${n}`
}

/** the playing tape: Skia video frames through the VHS layer effect */
function TapePlayback({ uri, w, h }: { uri: string; w: number; h: number }) {
  const paused = useSharedValue(false)
  const { currentFrame, currentTime, rotation, size } = useVideo(uri, {
    paused,
    looping: true,
    volume: 1,
  })

  // RuntimeShader layers rasterize in physical pixels — feed res + time in px/s
  const dpr = PixelRatio.get()
  const uniforms = useDerivedValue(() => ({
    t: currentTime.value / 1000,
    res: [w * dpr, h * dpr],
  }))

  // fit the raw frame (with its rotation metadata) into the stage, cover
  const frameTransform = useMemo(() => {
    const vw = size.width || w
    const vh = size.height || h
    return fitbox('cover', rect(0, 0, vw, vh), rect(0, 0, w, h), rotation as 0 | 90 | 180 | 270)
  }, [size.width, size.height, rotation, w, h])

  // counting timecode, updated once per second off the playback clock
  const [sec, setSec] = useState(0)
  useAnimatedReaction(
    () => Math.floor(currentTime.value / 1000),
    (s, prev) => {
      if (s !== prev) runOnJS(setSec)(s)
    },
  )
  const [recOn, setRecOn] = useState(true)
  useEffect(() => {
    const iv = setInterval(() => setRecOn((v) => !v), 600)
    return () => clearInterval(iv)
  }, [])

  const vw = size.width || w
  const vh = size.height || h

  return (
    <Pressable
      onPress={() => {
        paused.value = !paused.value
        haptics.light()
      }}
      accessibilityRole="button"
      accessibilityLabel="Tap to pause or play"
    >
      <View style={{ width: w, height: h }}>
        <Canvas style={{ width: w, height: h }}>
          <Group
            layer={
              <Paint>
                <RuntimeShader source={VHS_EFFECT} uniforms={uniforms} />
              </Paint>
            }
          >
            <SkiaImage
              image={currentFrame}
              x={0}
              y={0}
              width={vw}
              height={vh}
              fit="none"
              transform={frameTransform}
            />
          </Group>
        </Canvas>
        {/* the tape chrome — burned over the playback like the deck drew it */}
        <View pointerEvents="none" style={StyleSheet.absoluteFill}>
          <View style={s.recRow}>
            <View style={[s.recDot, { opacity: recOn ? 1 : 0.15 }]} />
            <Text style={s.recText}>REC</Text>
            <Text style={[s.recText, { marginLeft: 'auto' }]}>SP</Text>
          </View>
          <Text style={s.timecode}>
            0:{pad2(Math.floor(sec / 60))}:{pad2(sec % 60)}
          </Text>
        </View>
      </View>
    </Pressable>
  )
}

type Clip = { uri: string; w: number; h: number }

export default function Tape() {
  const insets = useSafeAreaInsets()
  const { width: screenW, height: screenH } = useWindowDimensions()
  const [clip, setClip] = useState<Clip | null>(null)
  const [busy, setBusy] = useState<'pick' | 'save' | 'share' | null>(null)
  const exportedRef = useRef<{ src: string; out: string } | null>(null)

  const pickClip = useCallback(async () => {
    setBusy('pick')
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync()
      if (!perm.granted) {
        Alert.alert('Photos access needed', 'Allow photo access to film from your library.')
        return
      }
      const res = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ImagePicker.MediaTypeOptions.Videos,
      })
      if (res.canceled || !res.assets?.[0]) return
      const a = res.assets[0]
      if ((a.duration ?? 0) > MAX_SECONDS * 1000) {
        Alert.alert('Keep it under a minute', 'Tapes work best with clips up to 60 seconds.')
        return
      }
      exportedRef.current = null
      setClip({ uri: a.uri, w: a.width ?? 1080, h: a.height ?? 1920 })
    } finally {
      setBusy(null)
    }
  }, [])

  /** bake the look into a real mp4 (cached per clip so Save+Share reuse it) */
  const bakeTape = useCallback(async (): Promise<string> => {
    if (!clip) throw new Error('No clip loaded.')
    if (exportedRef.current?.src === clip.uri) return exportedRef.current.out
    const lut = buildVhsLut()
    const out = await exportVhsVideo(clip.uri, lut.data, lut.dim)
    exportedRef.current = { src: clip.uri, out }
    return out
  }, [clip])

  const saveTape = useCallback(async () => {
    setBusy('save')
    try {
      const out = await bakeTape()
      const perm = await MediaLibrary.requestPermissionsAsync()
      if (!perm.granted) throw new Error('Allow Photos access to save the tape.')
      await MediaLibrary.saveToLibraryAsync(out)
      haptics.light()
      Alert.alert('Saved', 'Your tape is in Photos.')
    } catch (e) {
      Alert.alert('Could not save', e instanceof Error ? e.message : 'Something went wrong.')
    } finally {
      setBusy(null)
    }
  }, [bakeTape])

  const shareTape = useCallback(async () => {
    setBusy('share')
    try {
      const out = await bakeTape()
      await Sharing.shareAsync(out, { mimeType: 'video/mp4' })
    } catch (e) {
      Alert.alert('Could not share', e instanceof Error ? e.message : 'Something went wrong.')
    } finally {
      setBusy(null)
    }
  }, [bakeTape])

  // stage: fit the clip's aspect inside the screen
  const stageW = screenW - 24
  const aspect = clip ? Math.max(0.45, Math.min(clip.w / clip.h, 2.2)) : 9 / 16
  const stageH = Math.min(stageW / aspect, screenH * 0.62)
  const stageWFit = stageH * aspect

  return (
    <View style={[s.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar style="light" />

      <View style={s.topbar}>
        <Pressable
          onPress={() => router.back()}
          hitSlop={12}
          style={({ pressed }) => [s.back, pressed && { opacity: 0.6 }]}
          accessibilityRole="button"
          accessibilityLabel="Back"
        >
          <Text style={s.backText}>‹ Back</Text>
        </Pressable>
        <Text style={s.title}>Camcorder</Text>
        <View style={s.back} />
      </View>

      {!clip ? (
        <View style={s.emptyWrap}>
          <View style={s.emptyDeck}>
            <View style={s.recRowStatic}>
              <View style={s.recDot} />
              <Text style={s.recText}>REC</Text>
            </View>
            <Text style={s.emptyTitle}>Film it like 1994.</Text>
            <Text style={s.emptyBody}>
              Pick any clip and it plays back off a tape — grain, counting timecode, that VHS
              color. One look, no dials.
            </Text>
          </View>
          <Pressable
            onPress={pickClip}
            disabled={busy === 'pick'}
            style={({ pressed }) => [s.cta, pressed && { opacity: 0.9 }, busy === 'pick' && { opacity: 0.7 }]}
            accessibilityRole="button"
            accessibilityLabel="Pick a clip"
          >
            {busy === 'pick' ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={s.ctaText}>Pick a clip</Text>
            )}
          </Pressable>
        </View>
      ) : (
        <View style={s.playerWrap}>
          <View style={s.stage}>
            <TapePlayback uri={clip.uri} w={Math.round(stageWFit)} h={Math.round(stageH)} />
          </View>
          <Text style={s.hint}>Tap the tape to pause. Sound plays through.</Text>
          <View style={s.actions}>
            <Pressable
              onPress={saveTape}
              disabled={busy != null}
              style={({ pressed }) => [s.btn, s.btnPrimary, pressed && { opacity: 0.9 }, busy != null && { opacity: 0.6 }]}
            >
              {busy === 'save' ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={s.btnPrimaryText}>Save to Photos</Text>
              )}
            </Pressable>
            <View style={s.row}>
              <Pressable
                onPress={shareTape}
                disabled={busy != null}
                style={({ pressed }) => [s.btn, s.btnGhost, { flex: 1 }, pressed && { opacity: 0.85 }, busy != null && { opacity: 0.6 }]}
              >
                {busy === 'share' ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={s.btnGhostText}>Share</Text>
                )}
              </Pressable>
              <Pressable
                onPress={pickClip}
                disabled={busy != null}
                style={({ pressed }) => [s.btn, s.btnGhost, { flex: 1 }, pressed && { opacity: 0.85 }, busy != null && { opacity: 0.6 }]}
              >
                <Text style={s.btnGhostText}>New clip</Text>
              </Pressable>
            </View>
            {!vhsExportAvailable && (
              <Text style={s.exportNote}>
                Saving tapes needs the full LensMood build — the preview above is the real look.
              </Text>
            )}
          </View>
        </View>
      )}
    </View>
  )
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0b0f12' },
  topbar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  back: { width: 72 },
  backText: { color: '#eaf6fb', fontSize: 16, fontWeight: '700' },
  title: {
    flex: 1,
    textAlign: 'center',
    color: 'rgba(255,255,255,0.95)',
    fontSize: 18,
    fontWeight: '800',
    letterSpacing: -0.3,
  },

  emptyWrap: { flex: 1, justifyContent: 'center', paddingHorizontal: 20, gap: 18 },
  emptyDeck: {
    borderRadius: 22,
    backgroundColor: '#141a1f',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.14)',
    padding: 24,
    gap: 10,
  },
  recRowStatic: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  emptyTitle: { color: '#fff', fontSize: 26, fontWeight: '800', letterSpacing: -0.4 },
  emptyBody: { color: 'rgba(255,255,255,0.65)', fontSize: 15, lineHeight: 21 },
  cta: {
    height: 56,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.accent,
    shadowColor: colors.accent,
    shadowOpacity: 0.5,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 6 },
    elevation: 8,
  },
  ctaText: { color: '#fff', fontSize: 17, fontWeight: '800' },

  playerWrap: { flex: 1, alignItems: 'center', paddingTop: 6 },
  stage: { borderRadius: 18, overflow: 'hidden', backgroundColor: '#000' },
  hint: { color: 'rgba(255,255,255,0.5)', fontSize: 13, marginTop: 10 },

  recRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    paddingHorizontal: 16,
    paddingTop: 14,
  },
  recDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#e1251b' },
  recText: {
    color: 'rgba(255,240,220,0.95)',
    fontSize: 13,
    fontWeight: '700',
    fontFamily: MONO,
    letterSpacing: 1,
  },
  timecode: {
    position: 'absolute',
    left: 16,
    bottom: 12,
    color: 'rgba(255,240,220,0.95)',
    fontSize: 15,
    fontWeight: '700',
    fontFamily: MONO,
    letterSpacing: 1.5,
    textShadowColor: 'rgba(0,0,0,0.6)',
    textShadowRadius: 4,
    textShadowOffset: { width: 0, height: 1 },
  },

  actions: { alignSelf: 'stretch', paddingHorizontal: 20, paddingTop: 18, gap: 10 },
  row: { flexDirection: 'row', gap: 10 },
  btn: { height: 52, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  btnPrimary: { backgroundColor: colors.accent },
  btnPrimaryText: { color: '#fff', fontSize: 16, fontWeight: '800' },
  btnGhost: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.2)',
  },
  btnGhostText: { color: '#fff', fontSize: 15.5, fontWeight: '700' },
  exportNote: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 12.5,
    textAlign: 'center',
    marginTop: 4,
  },
})
