/**
 * Focal — where the subject is, so the engine can lock flash/vignette to the
 * face and keep smoothing on skin.
 *
 * On the web this ran MediaPipe BlazeFace in-process. The native port ships an
 * M1 stub that always reports "no face": the develop engine already degrades
 * gracefully with `focal = null` (flash centers frame, smoothing covers the
 * whole image, DoF is skipped), so every stock still develops correctly. A
 * real on-device detector (Vision / ML Kit / a TFLite BlazeFace via
 * react-native-fast-tflite) is a post-M1 upgrade — swap the body of
 * `detectFocal` and the scene meter + engine pick it up unchanged.
 */

import type { SkImage } from '@shopify/react-native-skia'
import type { Focal } from '@/engine/types'

export type { Focal }

/**
 * Find the strongest face and return its normalized center + radius, or null
 * when there is none. M1: always null (no bundled face model yet).
 */
export async function detectFocal(_image: SkImage): Promise<Focal | null> {
  return null
}
