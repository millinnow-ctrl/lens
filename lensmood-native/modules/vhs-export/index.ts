/**
 * JS face of the native VHS exporter. The module only exists in a real build
 * (EAS / dev client) — in environments without it we surface a clear error and
 * the UI shows the live preview as the source of truth.
 */
import { requireOptionalNativeModule } from 'expo-modules-core'

type VhsExportNative = {
  exportVideo(videoUri: string, lutBase64: string, lutDim: number): Promise<string>
}

const native = requireOptionalNativeModule<VhsExportNative>('VhsExport')

export const vhsExportAvailable = native != null

/** bake the tape look into a real .mp4; resolves to a file:// uri in caches */
export async function exportVhsVideo(
  videoUri: string,
  lutBase64: string,
  lutDim: number,
): Promise<string> {
  if (!native) {
    throw new Error('Saving tapes needs the full LensMood app build.')
  }
  return native.exportVideo(videoUri, lutBase64, lutDim)
}
