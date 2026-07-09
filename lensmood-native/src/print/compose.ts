/**
 * Scene composite export — renders "an iPhone photo of the finished polaroid
 * lying on the scene": plate, true mild-perspective pose, contact shadow,
 * then the vignette + fine grain every phone photo carries. Same offscreen
 * Skia surface + encode/write idiom as the engine's develop().
 */

import {
  Skia,
  BlendMode,
  TileMode,
  ImageFormat,
  processTransform3d,
  type SkImage,
} from '@shopify/react-native-skia'
import { File, Paths } from 'expo-file-system'
import { Asset } from 'expo-asset'
import { loadImageFromUri } from '@/engine/engine'
import type { DevelopResult } from '@/engine/types'
import { SCENE_POSE, type ScenePreset } from './scenes'

const OUT_W = 1242
const OUT_H = 1656

/* decoded plates + finished composites are cached per session */
const plateCache = new Map<string, SkImage>()
const outCache = new Map<string, DevelopResult>()

async function loadPlate(scene: ScenePreset): Promise<SkImage> {
  const hit = plateCache.get(scene.id)
  if (hit) return hit
  const asset = Asset.fromModule(scene.plate)
  await asset.downloadAsync()
  const img = await loadImageFromUri(asset.localUri ?? asset.uri)
  if (!img) throw new Error('Scene background could not be loaded.')
  plateCache.set(scene.id, img)
  return img
}

const rad = (d: number) => (d * Math.PI) / 180

export async function composeScenePrint(
  printUri: string,
  printW: number,
  printH: number,
  scene: ScenePreset,
): Promise<DevelopResult> {
  const cacheKey = `${printUri}::${scene.id}`
  const cached = outCache.get(cacheKey)
  if (cached) return cached

  // let the caller's spinner paint before the heavy synchronous pass
  await new Promise((r) => setTimeout(r, 30))

  const [plate, print] = await Promise.all([
    loadPlate(scene),
    loadImageFromUri(printUri).then((img) => {
      if (!img) throw new Error('The print could not be loaded.')
      return img
    }),
  ])

  const surface = Skia.Surface.MakeOffscreen(OUT_W, OUT_H)
  if (!surface) throw new Error('Could not allocate the composite surface.')
  const canvas = surface.getCanvas()

  /* 1 — scene plate, cover-fit, softly out of focus (shallow DOF: the print is
     the subject, the table falls away). One blurred draw. */
  const pw = plate.width()
  const ph = plate.height()
  const cover = Math.max(OUT_W / pw, OUT_H / ph)
  const cw = OUT_W / cover
  const chh = OUT_H / cover
  const basePaint = Skia.Paint()
  basePaint.setImageFilter(Skia.ImageFilter.MakeBlur(9, 9, TileMode.Clamp, null))
  canvas.drawImageRect(
    plate,
    Skia.XYWHRect((pw - cw) / 2, (ph - chh) / 2, cw, chh),
    Skia.XYWHRect(-16, -16, OUT_W + 32, OUT_H + 32),
    basePaint,
  )

  /* 2 — the print, posed with the SHARED camera template (same angle/roll for
     every surface) + a soft contact shadow. Only the plate above changes. */
  const cx = SCENE_POSE.cx * OUT_W
  const cy = SCENE_POSE.cy * OUT_H
  const k = (SCENE_POSE.scale * OUT_W) / printW
  canvas.save()
  canvas.concat(
    processTransform3d([
      { translate: [cx, cy] as const },
      { perspective: 1000 },
      { rotateX: rad(SCENE_POSE.tiltDeg) },
      { rotateZ: rad(SCENE_POSE.rollDeg) },
      { scale: k },
      { translate: [-printW / 2, -printH / 2] as const },
    ]),
  )
  const printPaint = Skia.Paint()
  // shadow params live in stage space — bring them into local print space
  printPaint.setImageFilter(
    Skia.ImageFilter.MakeDropShadow(
      0,
      (SCENE_POSE.shadowDrop * 2.2) / k,
      (scene.shadowRadius * 2.4) / k,
      (scene.shadowRadius * 2.4) / k,
      Skia.Color(`rgba(8,10,12,${Math.min(1, scene.shadowOpacity + 0.16)})`),
      null,
    ),
  )
  canvas.drawImage(print, 0, 0, printPaint)
  canvas.restore()

  /* 3 — vignette (the phone-photo falloff) */
  const vig = Skia.Paint()
  vig.setShader(
    Skia.Shader.MakeRadialGradient(
      { x: OUT_W / 2, y: OUT_H * 0.48 },
      Math.max(OUT_W, OUT_H) * 0.75,
      [Skia.Color('rgba(8,8,12,0)'), Skia.Color('rgba(8,8,12,0.26)')],
      [0.55, 1],
      TileMode.Clamp,
    ),
  )
  canvas.drawRect(Skia.XYWHRect(0, 0, OUT_W, OUT_H), vig)

  /* 4 — fine luminance grain, one GPU draw (fractal noise centers on
     mid-grey, so Overlay is luminance-neutral) */
  const grain = Skia.Paint()
  grain.setShader(Skia.Shader.MakeFractalNoise(0.9, 0.9, 2, 7, 0, 0))
  // desaturate the noise so the grain is mono
  grain.setColorFilter(
    Skia.ColorFilter.MakeMatrix([
      0.33, 0.33, 0.33, 0, 0,
      0.33, 0.33, 0.33, 0, 0,
      0.33, 0.33, 0.33, 0, 0,
      0, 0, 0, 1, 0,
    ]),
  )
  grain.setBlendMode(BlendMode.Overlay)
  grain.setAlphaf(0.07)
  canvas.drawRect(Skia.XYWHRect(0, 0, OUT_W, OUT_H), grain)

  /* 5 — encode + persist (develop() idiom) */
  const img = surface.makeImageSnapshot()
  const bytes = img.encodeToBytes(ImageFormat.JPEG, 90)
  const name = `lensmood-print-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`
  const file = new File(Paths.cache, name)
  if (!file.exists) file.create()
  file.write(bytes)

  const result: DevelopResult = { uri: file.uri, width: OUT_W, height: OUT_H }
  outCache.set(cacheKey, result)
  return result
}
