/**
 * JS face of the Apple Vision module. Optional by design: in a full build
 * `detectFaces` runs real on-device ML; without it (Expo Go) callers fall
 * back to the classical heuristic in src/engine/focal.ts.
 */
import { requireOptionalNativeModule } from 'expo-modules-core'

export interface VisionFace {
  x: number // normalized, top-left origin
  y: number
  w: number
  h: number
  confidence: number
}

export interface VisionMask {
  maskBase64: string // grayscale PNG
  width: number
  height: number
}

type LensmoodVisionNative = {
  detectFaces(uri: string): Promise<VisionFace[]>
  personMask(uri: string): Promise<VisionMask | null>
}

const native = requireOptionalNativeModule<LensmoodVisionNative>('LensmoodVision')

export const visionAvailable = native != null

export async function detectFacesVision(uri: string): Promise<VisionFace[] | null> {
  if (!native) return null
  try {
    return await native.detectFaces(uri)
  } catch {
    return null
  }
}

export async function personMaskVision(uri: string): Promise<VisionMask | null> {
  if (!native) return null
  try {
    return await native.personMask(uri)
  } catch {
    return null
  }
}
