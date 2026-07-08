/**
 * The LM-1 Pro Camera — LensMood's in-app camera. iOS-camera-style dark UI
 * over a live CameraView, plus the dial deck of a flagship body: ƒ, ISO, EV,
 * WB. iPhones expose none of those to ANY app (aperture is physically
 * fixed), so the dials do what makes them real here: they drive the LM-1
 * engine's develop of the shot — ƒ sets depth-of-field, ISO sets grain/
 * denoise, EV biases the meter, WB sets color — and the whole shot then
 * develops through the pro-body stock's AI relight profile.
 */

import { useCallback, useMemo, useRef, useState } from 'react'
import { View, Text, Pressable, StyleSheet, Platform, useWindowDimensions } from 'react-native'
import { Stack, router } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { StatusBar } from 'expo-status-bar'
import { CameraView, useCameraPermissions, type FlashMode } from 'expo-camera'
import { F_STOPS, ISOS, EVS, WBS, type ProDials } from '@/engine/proDials'
import { usePrintSounds } from '@/print/sounds'
import { haptics } from '@/store'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

/* --------------------------------------------------------------- UI bits */

function Dial<T extends number | string>({
  label,
  values,
  value,
  format,
  onChange,
}: {
  label: string
  values: readonly T[]
  value: T
  format: (v: T) => string
  onChange: (v: T) => void
}) {
  return (
    <View style={s.dial}>
      <Text style={s.dialLabel}>{label}</Text>
      <View style={s.dialRow}>
        {values.map((v) => {
          const active = v === value
          return (
            <Pressable
              key={String(v)}
              onPress={() => {
                haptics.selection()
                onChange(v)
              }}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              style={({ pressed }) => [s.detent, active && s.detentActive, pressed && { opacity: 0.8 }]}
            >
              <Text style={[s.detentText, active && s.detentTextActive]}>{format(v)}</Text>
            </Pressable>
          )
        })}
      </View>
    </View>
  )
}

/* ---------------------------------------------------------------- screen */

export default function ProCamera() {
  const insets = useSafeAreaInsets()
  const { width: screenW } = useWindowDimensions()
  const [perm, requestPerm] = useCameraPermissions()
  const camRef = useRef<CameraView>(null)
  const sounds = usePrintSounds()

  const [facing, setFacing] = useState<'back' | 'front'>('back')
  const [flash, setFlash] = useState<FlashMode>('off')
  const [zoomIdx, setZoomIdx] = useState(0) // 1x / 2x
  const [grid, setGrid] = useState(true)
  const [busy, setBusy] = useState(false)
  const [dials, setDials] = useState<ProDials>({ f: 2.8, iso: 200, ev: 0, wb: 'AWB' })

  const viewH = Math.round((screenW * 4) / 3)
  const readout = useMemo(
    () =>
      `ƒ${dials.f} · ISO ${dials.iso} · ${dials.ev > 0 ? '+' : ''}${dials.ev.toFixed(1)} EV · ${dials.wb}`,
    [dials],
  )

  const shoot = useCallback(async () => {
    const cam = camRef.current
    if (!cam || busy) return
    setBusy(true)
    haptics.heavy()
    sounds.shutter()
    try {
      const pic = await cam.takePictureAsync({ quality: 1, exif: false })
      if (!pic?.uri) return
      router.replace({
        pathname: '/develop',
        params: {
          style: 'pro-body',
          shot: pic.uri,
          w: String(pic.width ?? 0),
          h: String(pic.height ?? 0),
          pro: JSON.stringify(dials),
        },
      })
    } catch {
      /* capture failed — stay on the camera, the shutter simply didn't fire */
    } finally {
      setBusy(false)
    }
  }, [busy, dials, sounds])

  /* permission gates */
  if (!perm) return <View style={s.root} />
  if (!perm.granted) {
    return (
      <View style={[s.root, s.permWrap, { paddingTop: insets.top }]}>
        <Stack.Screen options={{ headerShown: false }} />
        <StatusBar style="light" />
        <Text style={s.permTitle}>The LM-1 needs the lens.</Text>
        <Text style={s.permSub}>
          Allow camera access to shoot through the pro body. Photos never leave your phone.
        </Text>
        <Pressable
          onPress={() => (perm.canAskAgain ? requestPerm() : null)}
          style={({ pressed }) => [s.btn, s.btnPrimary, pressed && { opacity: 0.9 }]}
        >
          <Text style={s.btnPrimaryText}>
            {perm.canAskAgain ? 'Allow camera' : 'Enable in Settings'}
          </Text>
        </Pressable>
        <Pressable onPress={() => router.back()} hitSlop={12} style={{ marginTop: 14 }}>
          <Text style={s.permBack}>‹ Back</Text>
        </Pressable>
      </View>
    )
  }

  return (
    <View style={[s.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false, animation: 'fade' }} />
      <StatusBar style="light" />

      {/* top bar */}
      <View style={s.topbar}>
        <Pressable onPress={() => router.back()} hitSlop={12} style={s.topBtn}>
          <Text style={s.topBtnText}>‹</Text>
        </Pressable>
        <Pressable
          onPress={() => {
            haptics.selection()
            setFlash((f) => (f === 'off' ? 'auto' : f === 'auto' ? 'on' : 'off'))
          }}
          hitSlop={10}
          style={s.topBtn}
        >
          <Text style={[s.topBtnText, s.topBtnSmall, flash !== 'off' && { color: '#ffd76a' }]}>
            {flash === 'off' ? '⚡︎ OFF' : flash === 'auto' ? '⚡︎ AUTO' : '⚡︎ ON'}
          </Text>
        </Pressable>
        <View style={s.badge}>
          <Text style={s.badgeText}>LM-1 PRO BODY</Text>
        </View>
        <Pressable
          onPress={() => {
            haptics.selection()
            setGrid((g) => !g)
          }}
          hitSlop={10}
          style={s.topBtn}
        >
          <Text style={[s.topBtnText, s.topBtnSmall, grid && { color: '#9fdceb' }]}>▦</Text>
        </Pressable>
        <Pressable
          onPress={() => {
            haptics.selection()
            setFacing((f) => (f === 'back' ? 'front' : 'back'))
          }}
          hitSlop={10}
          style={s.topBtn}
        >
          <Text style={[s.topBtnText, s.topBtnSmall]}>⟲</Text>
        </Pressable>
      </View>

      {/* viewfinder */}
      <View style={{ width: screenW, height: viewH }}>
        <CameraView
          ref={camRef}
          style={StyleSheet.absoluteFill}
          facing={facing}
          flash={flash}
          zoom={zoomIdx === 0 ? 0 : 0.18}
          animateShutter={false}
        />
        {grid && (
          <View pointerEvents="none" style={StyleSheet.absoluteFill}>
            <View style={[s.gridLine, { left: '33.3%', width: StyleSheet.hairlineWidth, height: '100%' }]} />
            <View style={[s.gridLine, { left: '66.6%', width: StyleSheet.hairlineWidth, height: '100%' }]} />
            <View style={[s.gridLine, { top: '33.3%', height: StyleSheet.hairlineWidth, width: '100%' }]} />
            <View style={[s.gridLine, { top: '66.6%', height: StyleSheet.hairlineWidth, width: '100%' }]} />
          </View>
        )}
        {/* live LCD readout */}
        <View style={s.lcd}>
          <Text style={s.lcdText}>{readout}</Text>
        </View>
        {/* zoom chips */}
        <View style={s.zoomRow}>
          {(['1x', '2x'] as const).map((z, i) => (
            <Pressable
              key={z}
              onPress={() => {
                haptics.selection()
                setZoomIdx(i)
              }}
              style={[s.zoomChip, zoomIdx === i && s.zoomChipActive]}
            >
              <Text style={[s.zoomText, zoomIdx === i && s.zoomTextActive]}>{z}</Text>
            </Pressable>
          ))}
        </View>
      </View>

      {/* dial deck */}
      <View style={s.deck}>
        <Dial label="ƒ" values={F_STOPS} value={dials.f} format={(v) => `${v}`}
          onChange={(f) => setDials((d) => ({ ...d, f }))} />
        <Dial label="ISO" values={ISOS} value={dials.iso} format={(v) => `${v}`}
          onChange={(iso) => setDials((d) => ({ ...d, iso }))} />
        <Dial label="EV" values={EVS} value={dials.ev}
          format={(v) => (v === 0 ? '0' : `${v > 0 ? '+' : ''}${v}`)}
          onChange={(ev) => setDials((d) => ({ ...d, ev }))} />
        <Dial label="WB" values={WBS} value={dials.wb} format={(v) => v}
          onChange={(wb) => setDials((d) => ({ ...d, wb }))} />
      </View>

      {/* shutter row */}
      <View style={[s.shutterRow, { paddingBottom: insets.bottom + 10 }]}>
        <View style={s.shutterSide} />
        <Pressable
          onPress={shoot}
          disabled={busy}
          accessibilityRole="button"
          accessibilityLabel="Shutter — take the shot"
          style={({ pressed }) => [s.shutterOuter, pressed && { transform: [{ scale: 0.93 }] }]}
        >
          <View style={[s.shutterInner, busy && { opacity: 0.4 }]} />
        </Pressable>
        <View style={s.shutterSide}>
          <Text style={s.credit}>
            Dials develop through the LM-1 engine. Handling inspired by Canon & Nikon flagship
            bodies — not affiliated.
          </Text>
        </View>
      </View>
    </View>
  )
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#05080a' },
  permWrap: { alignItems: 'center', justifyContent: 'center', padding: 32, gap: 10 },
  permTitle: { color: '#fff', fontSize: 22, fontWeight: '800' },
  permSub: { color: 'rgba(255,255,255,0.6)', fontSize: 14, textAlign: 'center', lineHeight: 20 },
  permBack: { color: '#9fdceb', fontSize: 16, fontWeight: '600' },
  btn: { height: 50, borderRadius: 14, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 26, marginTop: 12 },
  btnPrimary: { backgroundColor: colors.accent },
  btnPrimaryText: { color: '#fff', fontSize: 16, fontWeight: '700' },

  topbar: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, paddingVertical: 8, gap: 6 },
  topBtn: { paddingHorizontal: 8, paddingVertical: 4 },
  topBtnText: { color: 'rgba(255,255,255,0.9)', fontSize: 24, fontWeight: '600' },
  topBtnSmall: { fontSize: 13, fontFamily: MONO, fontWeight: '700' },
  badge: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badgeText: {
    color: 'rgba(255,255,255,0.92)',
    fontSize: 11,
    letterSpacing: 2,
    fontFamily: MONO,
    fontWeight: '700',
  },

  gridLine: { position: 'absolute', backgroundColor: 'rgba(255,255,255,0.28)' },
  lcd: {
    position: 'absolute',
    top: 10,
    alignSelf: 'center',
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 8,
    backgroundColor: 'rgba(4,8,10,0.66)',
  },
  lcdText: { color: '#d9f2da', fontSize: 12, fontFamily: MONO, fontWeight: '600', letterSpacing: 0.6 },
  zoomRow: { position: 'absolute', bottom: 10, alignSelf: 'center', flexDirection: 'row', gap: 8 },
  zoomChip: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(4,8,10,0.55)',
  },
  zoomChipActive: { backgroundColor: 'rgba(255,255,255,0.92)' },
  zoomText: { color: 'rgba(255,255,255,0.9)', fontSize: 13, fontWeight: '700' },
  zoomTextActive: { color: '#0b141a' },

  deck: { paddingTop: 10, gap: 8 },
  dial: { gap: 4 },
  dialLabel: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 10,
    letterSpacing: 1.6,
    fontFamily: MONO,
    fontWeight: '700',
    paddingHorizontal: 16,
  },
  dialRow: { flexDirection: 'row', flexWrap: 'nowrap', gap: 6, paddingHorizontal: 14 },
  detent: {
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 9,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.14)',
  },
  detentActive: { backgroundColor: '#fff', borderColor: '#fff' },
  detentText: { color: 'rgba(255,255,255,0.85)', fontSize: 12.5, fontFamily: MONO, fontWeight: '700' },
  detentTextActive: { color: '#0b141a' },

  shutterRow: { flexDirection: 'row', alignItems: 'center', paddingTop: 12, paddingHorizontal: 18 },
  shutterSide: { flex: 1, justifyContent: 'center' },
  shutterOuter: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 4,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  shutterInner: { width: 60, height: 60, borderRadius: 30, backgroundColor: '#fff' },
  credit: {
    color: 'rgba(255,255,255,0.38)',
    fontSize: 9.5,
    lineHeight: 13,
    fontFamily: MONO,
    paddingLeft: 10,
  },
})
