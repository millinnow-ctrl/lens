/**
 * The chemistry pass — draws the framed polaroid through an animated color
 * matrix so the whole print (paper border included, exactly like a real
 * ejecting Polaroid) starts near-black with a blue-green chemical cast and
 * clears to the final image. A static radial haze whose opacity tracks
 * (1 - progress) makes the center clear first. All animated props are
 * SharedValues, so every frame is GPU-only — no JS-thread re-render.
 */

import {
  Canvas,
  Image as SkiaImage,
  Rect,
  RadialGradient,
  ColorMatrix,
  useImage,
  vec,
} from '@shopify/react-native-skia'
import { useDerivedValue, type SharedValue } from 'react-native-reanimated'

interface Props {
  /** framed polaroid JPEG from the engine (cache file uri) */
  uri: string
  /** on-screen layout size */
  width: number
  height: number
  /** 0 = undeveloped, 1 = final — the parent drives the timeline */
  progress: SharedValue<number>
}

export default function DevelopingPrint({ uri, width, height, progress }: Props) {
  const img = useImage(uri)

  const matrix = useDerivedValue(() => {
    const p = progress.value
    const b = 0.04 + 0.96 * p // brightness: near-black -> full
    const s = 0.15 + 0.85 * p // saturation: grey-green -> full colour
    const oR = -0.015 * (1 - p) // chemical cast offsets, fade out
    const oG = 0.045 * (1 - p)
    const oB = 0.035 * (1 - p)
    const lr = 0.213 * (1 - s)
    const lg = 0.715 * (1 - s)
    const lb = 0.072 * (1 - s)
    return [
      b * (lr + s), b * lg, b * lb, 0, oR,
      b * lr, b * (lg + s), b * lb, 0, oG,
      b * lr, b * lg, b * (lb + s), 0, oB,
      0, 0, 0, 1, 0,
    ]
  })
  const hazeOpacity = useDerivedValue(() => 0.85 * (1 - progress.value))

  return (
    <Canvas style={{ width, height }}>
      <SkiaImage image={img} x={0} y={0} width={width} height={height} fit="fill">
        <ColorMatrix matrix={matrix} />
      </SkiaImage>
      <Rect x={0} y={0} width={width} height={height} opacity={hazeOpacity}>
        <RadialGradient
          c={vec(width / 2, height * 0.44)}
          r={Math.max(width, height) * 0.75}
          colors={['rgba(18,30,27,0)', 'rgba(14,24,22,0.35)', 'rgba(10,18,17,0.7)']}
          positions={[0.25, 0.7, 1]}
        />
      </Rect>
    </Canvas>
  )
}
