/**
 * Develop — the studio. Pick a photo, the meter reads it, the chosen stock
 * develops it. Stock rail to switch looks in place, named-stop fine-tune
 * panel (debounced re-develops), original/result/compare views, share and
 * save-to-Photos. Credits: first-ever develop free, then 5/month on the
 * free plan; a new (photo, stock) pairing spends one — slider tweaks never
 * do. Free-plan exports carry the engraved watermark.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  View,
  Text,
  Image,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  Alert,
  ScrollView,
  useWindowDimensions,
  Platform,
} from 'react-native'
import { Stack, router, useLocalSearchParams } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { Canvas, Image as SkiaImage, useImage } from '@shopify/react-native-skia'
import { Asset } from 'expo-asset'
import * as ImagePicker from 'expo-image-picker'
import * as Sharing from 'expo-sharing'
import * as MediaLibrary from 'expo-media-library'
import { getStyle } from '@/engine/styles'
import { analyzeScene, sceneLabel } from '@/engine/scene'
import { detectFocal, type Focal } from '@/engine/focal'
import { parseProDials, dialsToEngine } from '@/engine/proDials'
import { develop as developImage, loadImageFromUri } from '@/engine/engine'
import type { CameraStyle, StyleParams, SceneProfile, DevelopResult } from '@/engine/types'
import type { SkImage } from '@shopify/react-native-skia'
import AdjustmentPanel from '@/components/AdjustmentPanel'
import CompareSlider from '@/components/CompareSlider'
import StyleRail from '@/components/StyleRail'
import { useApp, haptics } from '@/store'
import { colors } from '@/theme/colors'

type Picked = { uri: string; width: number; height: number }
type ViewMode = 'original' | 'result' | 'compare'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

/** Curated sample shots (bundled) — trying the lenses on these never spends a credit.
 *  Each one exercises a different side of the engine: backlit face metering, night
 *  light-mapping/halation, party-flash skin relight, still-life color science. */
const SAMPLES = [
  { key: 'golden', label: 'Golden hour', src: require('../assets/samples/sample-golden.jpg') },
  { key: 'night', label: 'Neon rain', src: require('../assets/samples/sample-night.jpg') },
  { key: 'friends', label: 'Party flash', src: require('../assets/samples/sample-friends.jpg') },
  { key: 'brunch', label: 'Slow brunch', src: require('../assets/samples/sample-brunch.jpg') },
] as const

export default function Develop() {
  const insets = useSafeAreaInsets()
  const { width: screenW } = useWindowDimensions()
  const {
    style: styleParam,
    shot,
    w: shotW,
    h: shotH,
    pro,
  } = useLocalSearchParams<{ style?: string; shot?: string; w?: string; h?: string; pro?: string }>()
  const { isPaid, spendCredit, addHistory, creditsLeft } = useApp()

  const [style, setStyle] = useState<CameraStyle | undefined>(() => getStyle(styleParam))
  const [params, setParams] = useState<StyleParams | null>(style ? { ...style.defaults } : null)
  const [photo, setPhoto] = useState<Picked | null>(null)
  const [result, setResult] = useState<DevelopResult | null>(null)
  // frameless companion of a framed (polaroid) result, so the compare wipe
  // stays pixel-aligned with the original; null for the other stocks
  const [compareResult, setCompareResult] = useState<DevelopResult | null>(null)
  const [developing, setDeveloping] = useState(false)
  // the develop is a real staged pipeline — this is the current stage the engine
  // is actually working on (scene read → subject recognition → develop), shown so
  // the compute is visible rather than an instant filter flip
  const [phase, setPhase] = useState('Developing')
  const [view, setView] = useState<ViewMode>('result')
  const [meter, setMeter] = useState<string | null>(null)

  const [libPerm, requestLibPerm] = ImagePicker.useMediaLibraryPermissions()
  const [savePerm, requestSavePerm] = MediaLibrary.usePermissions()

  // decoded source + its meter reading + subject lock, cached per photo
  const sourceRef = useRef<SkImage | null>(null)
  const sceneRef = useRef<SceneProfile | null>(null)
  const focalRef = useRef<Focal | null>(null)
  // dial settings for a shot that arrived from the in-app camera —
  // they ride on top of whichever stock is selected
  const proRef = useRef<ReturnType<typeof dialsToEngine> | null>(null)
  // which (photo, stock) pairings have already been paid for
  const chargedRef = useRef<Set<string>>(new Set())
  // bundled sample shots develop free — their uris bypass the credit gate
  const sampleUrisRef = useRef<Set<string>>(new Set())
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const runIdRef = useRef(0)

  const originalImg = useImage(photo?.uri ?? null)
  const resultImg = useImage(result?.uri ?? null)

  /** run the engine on the cached source (assumes credit already handled).
   *  commit=true records history — new photos and stock switches only, so
   *  slider fine-tuning doesn't spam the gallery with near-duplicates */
  const runDevelop = useCallback(
    async (st: CameraStyle, p: StyleParams, commit = false) => {
      const img = sourceRef.current
      if (!img) return
      const myRun = ++runIdRef.current
      setDeveloping(true)
      setPhase('Developing')
      // yield so the phase paints before the heavy synchronous render pass
      await new Promise((r) => setTimeout(r, 30))
      try {
        if (!sceneRef.current) sceneRef.current = analyzeScene(img, focalRef.current)
        // the camera's dials ride along with its shot, whatever stock develops it
        const lensOverride = proRef.current?.lensOverride
        const developed = await developImage(img, st, p, {
          scene: sceneRef.current,
          maxSize: 1280,
          watermark: !isPaid,
          focal: focalRef.current,
          lensOverride,
        })
        if (myRun !== runIdRef.current) return // superseded by a newer run
        setResult(developed)
        if (st.character.polaroidFrame && p.intensity > 15) {
          const frameless = await developImage(img, st, p, {
            scene: sceneRef.current,
            maxSize: 1280,
            watermark: !isPaid,
            focal: focalRef.current,
            lensOverride,
            frame: false,
          })
          if (myRun !== runIdRef.current) return
          setCompareResult(frameless)
        } else {
          setCompareResult(null)
        }
        setView('result')
        if (commit) addHistory({ thumb: developed.uri, styleId: st.id, styleName: st.name })
        haptics.light()
      } catch (e) {
        if (myRun === runIdRef.current)
          Alert.alert('Develop failed', e instanceof Error ? e.message : 'Something went wrong.')
      } finally {
        if (myRun === runIdRef.current) setDeveloping(false)
      }
    },
    [isPaid, addHistory],
  )

  /** develop with the credit gate — used for new photos and stock switches */
  const developCharged = useCallback(
    (st: CameraStyle, p: StyleParams, photoUri: string) => {
      if (sampleUrisRef.current.has(photoUri)) {
        void runDevelop(st, p, true)
        return
      }
      // premium stocks are paid-kit only for real photos (samples showcase free)
      if (st.tier === 'premium' && !isPaid) {
        setDeveloping(false) // clear the staged-develop spinner before the gate
        haptics.warning()
        router.push('/paywall')
        return
      }
      const key = `${photoUri}::${st.id}`
      if (!chargedRef.current.has(key)) {
        if (!spendCredit()) {
          setDeveloping(false)
          haptics.warning()
          router.push('/paywall')
          return
        }
        chargedRef.current.add(key)
      }
      void runDevelop(st, p, true)
    },
    [spendCredit, runDevelop, isPaid],
  )

  /** decode + meter a chosen photo, then develop — shared by the picker,
   *  samples, and shots arriving from the Pro Camera (paramsOverride) */
  const loadPicked = useCallback(
    async (picked: Picked, paramsOverride?: StyleParams) => {
      haptics.medium()
      setPhoto(picked)
      setResult(null)
      setCompareResult(null)
      sourceRef.current = null
      sceneRef.current = null
      focalRef.current = null
      const img = await loadImageFromUri(picked.uri)
      if (!img) {
        Alert.alert('Photo error', 'That photo could not be decoded.')
        return
      }
      sourceRef.current = img
      // real staged recognition — each stage is genuine work (not a timer); the
      // yields just let the phase label paint between passes so the compute shows
      setDeveloping(true)
      setPhase('Finding your subject')
      await new Promise((r) => setTimeout(r, 16))
      // the subject finder feeds face metering, DoF, relight, and smoothing —
      // Apple Vision on full builds, the classical heuristic otherwise
      focalRef.current = await detectFocal(img, picked.uri)
      setPhase('Reading the light')
      await new Promise((r) => setTimeout(r, 16))
      sceneRef.current = analyzeScene(img, focalRef.current)
      // the lens showing its work: what it read, what it locked, what it mapped
      const bits = [sceneLabel(sceneRef.current)]
      if (focalRef.current) bits.push('FACE LOCK')
      if (sceneRef.current.lights.length)
        bits.push(`${sceneRef.current.lights.length} LIGHT${sceneRef.current.lights.length > 1 ? 'S' : ''}`)
      if (proRef.current) bits.push(proRef.current.readout)
      setMeter(bits.join(' · '))
      const effective = paramsOverride ?? params
      if (style && effective) developCharged(style, effective, picked.uri)
    },
    [style, params, developCharged],
  )

  /* a shot arriving from the Pro Camera: apply its dials, then develop it */
  const shotHandledRef = useRef(false)
  useEffect(() => {
    if (!shot || shotHandledRef.current || !style || !params) return
    shotHandledRef.current = true
    const dials = parseProDials(pro)
    let effective = params
    if (dials) {
      proRef.current = dialsToEngine(dials)
      effective = { ...params, grain: proRef.current.params.grain, warmth: proRef.current.params.warmth }
      setParams(effective)
    }
    void loadPicked({ uri: shot, width: Number(shotW) || 0, height: Number(shotH) || 0 }, effective)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shot, style, params])

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
    await loadPicked({ uri: a.uri, width: a.width ?? 0, height: a.height ?? 0 })
  }, [libPerm, requestLibPerm, loadPicked])

  /** shooting happens in the in-app LensMood Camera — its shot routes back here */
  const shootPhoto = useCallback(() => {
    haptics.medium()
    router.push('/camera')
  }, [])

  const loadSample = useCallback(
    async (sample: (typeof SAMPLES)[number]) => {
      try {
        const asset = Asset.fromModule(sample.src)
        await asset.downloadAsync()
        const uri = asset.localUri ?? asset.uri
        sampleUrisRef.current.add(uri)
        await loadPicked({ uri, width: asset.width ?? 0, height: asset.height ?? 0 })
      } catch {
        Alert.alert('Sample unavailable', 'That sample shot could not be loaded.')
      }
    },
    [loadPicked],
  )

  /** switching stocks on the rail — premium stocks are part of the paid kit */
  const onSelectStyle = useCallback(
    (st: CameraStyle) => {
      if (st.tier === 'premium' && !isPaid) {
        haptics.warning()
        router.push('/paywall')
        return
      }
      haptics.selection()
      setStyle(st)
      const fresh = { ...st.defaults }
      setParams(fresh)
      if (photo) developCharged(st, fresh, photo.uri)
    },
    [photo, developCharged, isPaid],
  )

  /** fine-tune changes re-develop free, debounced */
  const onParamsChange = useCallback(
    (p: StyleParams) => {
      setParams(p)
      if (!photo || !style) return
      if (debounceRef.current) clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => void runDevelop(style, p), 250)
    },
    [photo, style, runDevelop],
  )

  useEffect(
    () => () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
      runIdRef.current++ // cancel in-flight completions after unmount
    },
    [],
  )

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
      haptics.success()
      Alert.alert('Saved', 'Your develop is in Photos.')
    } catch (e) {
      Alert.alert('Save failed', e instanceof Error ? e.message : 'Could not save the image.')
    }
  }, [result, savePerm, requestSavePerm])

  // frame geometry — the result view sizes to the developed print (a framed
  // polaroid is taller than the photo), other views to the source photo
  const frameW = screenW - 32
  const photoAspect = photo && photo.width && photo.height ? photo.height / photo.width : 4 / 3
  const aspect =
    view === 'result' && result && result.width ? result.height / result.width : photoAspect
  const frameH = Math.min(Math.round(frameW * aspect), Math.round(screenW * 1.2))

  const canCompare = !!photo && !!result
  // a framed polaroid compares via its frameless companion — hold the pill
  // until that second render lands so the wipe never shows the padded print
  const compareReady =
    !style?.character.polaroidFrame || (params?.intensity ?? 0) <= 15 || !!compareResult
  const showingImg = view === 'original' ? originalImg : resultImg
  const viewModes: ViewMode[] = ['original', 'result', 'compare']

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false }} />

      {/* top bar — stock name + the meter's reading of the scene */}
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
          <Text style={styles.exif} numberOfLines={1}>
            {meter ? `METER · ${meter}` : (style?.exif ?? '')}
          </Text>
        </View>
        <View style={styles.credits}>
          {!isPaid && <Text style={styles.creditsText}>{creditsLeft} LEFT</Text>}
        </View>
      </View>

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={{ paddingBottom: insets.bottom + 24 }}
        showsVerticalScrollIndicator={false}
      >
        {/* stage */}
        <View style={styles.stage}>
          {photo && result && view === 'compare' ? (
            <CompareSlider
              beforeUri={photo.uri}
              afterUri={compareResult?.uri ?? result.uri}
              afterLabel={style?.name ?? 'Developed'}
              width={frameW}
              height={frameH}
            />
          ) : (
            <View style={[styles.frame, { width: frameW, height: frameH }]}>
              {photo ? (
                <Canvas style={StyleSheet.absoluteFill}>
                  {showingImg && (
                    <SkiaImage image={showingImg} x={0} y={0} width={frameW} height={frameH} fit="contain" />
                  )}
                </Canvas>
              ) : (
                <View style={styles.empty}>
                  <Text style={styles.emptyText}>Load a photo</Text>
                  <Text style={styles.emptySub}>
                    It develops right here on your phone through {style?.name ?? 'your chosen look'}.
                    Nothing gets uploaded.
                  </Text>
                  <Text style={styles.sampleLabel}>Or try a sample — it's free</Text>
                  <View style={styles.sampleRow}>
                    {SAMPLES.map((s) => (
                      <Pressable
                        key={s.key}
                        onPress={() => void loadSample(s)}
                        accessibilityRole="button"
                        accessibilityLabel={`Try the ${s.label} sample shot`}
                        style={({ pressed }) => [
                          styles.sampleItem,
                          pressed && { opacity: 0.8, transform: [{ scale: 0.96 }] },
                        ]}
                      >
                        <Image source={s.src} style={styles.sampleThumb} />
                        <Text style={styles.sampleName} numberOfLines={1}>
                          {s.label}
                        </Text>
                      </Pressable>
                    ))}
                  </View>
                </View>
              )}
              {developing && (
                <View style={styles.developing}>
                  <ActivityIndicator color="#fff" />
                  <Text style={styles.developingText}>{phase.toLowerCase()}…</Text>
                </View>
              )}
            </View>
          )}

          {/* view switch */}
          {canCompare && (
            <View style={styles.segment}>
              {viewModes.map((m) => {
                const active = view === m
                const disabled = m === 'compare' && !compareReady
                return (
                  <Pressable
                    key={m}
                    onPress={() => !disabled && setView(m)}
                    disabled={disabled}
                    style={({ pressed }) => [
                      styles.segItem,
                      active && styles.segItemActive,
                      disabled && { opacity: 0.4 },
                      pressed && { opacity: 0.85 },
                    ]}
                  >
                    <Text style={[styles.segText, active && styles.segTextActive]}>
                      {m === 'original' ? 'Original' : m === 'result' ? 'LensMood' : 'Compare'}
                    </Text>
                  </Pressable>
                )
              })}
            </View>
          )}
        </View>

        {/* stock rail */}
        <View style={styles.railWrap}>
          <Text style={styles.sectionLabel}>Camera mood</Text>
          <StyleRail activeId={style?.id ?? null} onSelect={onSelectStyle} />
        </View>

        {/* actions */}
        <View style={styles.actions}>
          <View style={styles.exportRow}>
            <Pressable
              onPress={pickPhoto}
              style={({ pressed }) => [
                styles.btn,
                styles.btnPrimary,
                styles.exportBtn,
                pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] },
              ]}
            >
              <Text style={styles.btnPrimaryText}>{photo ? 'New photo' : 'Pick a photo'}</Text>
            </Pressable>
            <Pressable
              onPress={shootPhoto}
              style={({ pressed }) => [
                styles.btn,
                styles.btnGhost,
                styles.exportBtn,
                pressed && { opacity: 0.85 },
              ]}
              accessibilityRole="button"
              accessibilityLabel="Shoot a photo with the camera"
            >
              <Text style={styles.btnGhostText}>Shoot</Text>
            </Pressable>
          </View>
          {result && style?.character.polaroidFrame && (params?.intensity ?? 0) > 15 && (
            <Pressable
              onPress={() => {
                haptics.medium()
                router.push({
                  pathname: '/print',
                  params: { uri: result.uri, w: String(result.width), h: String(result.height) },
                })
              }}
              style={({ pressed }) => [
                styles.btn,
                styles.btnSecondary,
                pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] },
              ]}
              accessibilityRole="button"
              accessibilityLabel="Print it — stage the polaroid in a scene"
            >
              <Text style={styles.btnSecondaryText}>Print it</Text>
            </Pressable>
          )}
          {result && (
            <View style={styles.exportRow}>
              <Pressable
                onPress={saveToPhotos}
                style={({ pressed }) => [styles.btn, styles.btnGhost, styles.exportBtn, pressed && { opacity: 0.85 }]}
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
          {!isPaid && result && (
            <Pressable onPress={() => router.push('/paywall')} hitSlop={8}>
              <Text style={styles.upsell}>Remove the watermark — see plans</Text>
            </Pressable>
          )}
        </View>

        {/* fine-tune */}
        {style && params && photo && (
          <View style={styles.panelWrap}>
            <AdjustmentPanel style={style} params={params} onChange={onParamsChange} disabled={developing} />
          </View>
        )}
      </ScrollView>
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  scroll: { flex: 1 },
  topbar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  back: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 40,
    paddingLeft: 12,
    paddingRight: 18,
    borderRadius: 999,
    backgroundColor: colors.surface,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.12)',
    shadowColor: colors.ink,
    shadowOpacity: 0.1,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
  },
  backText: { color: colors.ink, fontSize: 16, fontWeight: '700' },
  titleWrap: { flex: 1, alignItems: 'center' },
  title: { color: colors.ink, fontSize: 16, fontWeight: '700', letterSpacing: -0.2 },
  exif: { color: colors.fog, fontSize: 10.5, letterSpacing: 0.3, fontFamily: MONO, marginTop: 2 },
  credits: { width: 64, alignItems: 'flex-end' },
  creditsText: { color: colors.fog, fontSize: 10, letterSpacing: 0.8, fontFamily: MONO, fontWeight: '600' },

  stage: { alignItems: 'center', gap: 14, paddingHorizontal: 16, paddingTop: 4 },
  frame: {
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: colors.viewfinder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  empty: { alignItems: 'center', padding: 24, gap: 8 },
  emptyText: { color: 'rgba(255,255,255,0.9)', fontSize: 16, fontWeight: '700' },
  emptySub: { color: 'rgba(255,255,255,0.55)', fontSize: 13, textAlign: 'center', lineHeight: 18 },
  sampleLabel: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 13.5,
    fontWeight: '600',
    marginTop: 12,
  },
  sampleRow: { flexDirection: 'row', gap: 12, marginTop: 2 },
  sampleItem: { alignItems: 'center', gap: 5 },
  sampleThumb: {
    width: 56,
    height: 72,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  sampleName: { color: 'rgba(255,255,255,0.55)', fontSize: 10.5, maxWidth: 62 },
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
    backgroundColor: 'rgb(226,232,237)',
    borderRadius: 999,
    padding: 4,
  },
  segItem: { paddingHorizontal: 18, paddingVertical: 8, borderRadius: 999 },
  segItemActive: {
    backgroundColor: colors.surface,
    shadowColor: colors.ink,
    shadowOpacity: 0.12,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  segText: { color: colors.inkSoft, fontSize: 13.5, fontWeight: '600' },
  segTextActive: { color: colors.ink },

  railWrap: { marginTop: 16, gap: 6 },
  sectionLabel: {
    color: colors.inkSoft,
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: -0.2,
    paddingHorizontal: 18,
  },

  actions: { paddingHorizontal: 16, paddingTop: 14, gap: 10 },
  btn: { height: 52, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
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
  upsell: {
    color: colors.accent,
    fontSize: 13,
    fontWeight: '600',
    textAlign: 'center',
    paddingVertical: 4,
  },

  panelWrap: { marginTop: 18, paddingHorizontal: 16 },
})
