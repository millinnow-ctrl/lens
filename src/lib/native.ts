import { Capacitor } from '@capacitor/core'
import { Camera, CameraResultType, CameraSource } from '@capacitor/camera'
import { Share } from '@capacitor/share'
import { Filesystem, Directory } from '@capacitor/filesystem'
import { Haptics, ImpactStyle } from '@capacitor/haptics'
import { StatusBar, Style } from '@capacitor/status-bar'
import { SplashScreen } from '@capacitor/splash-screen'

export const isNative = () => Capacitor.isNativePlatform()

/** one-time native chrome setup, safe to call on web (no-ops) */
export async function initNative(): Promise<void> {
  if (!isNative()) return
  try {
    await StatusBar.setStyle({ style: Style.Light })
    await SplashScreen.hide()
  } catch {
    /* plugin unavailable in this shell */
  }
}

export type HapticKind = 'light' | 'medium' | 'heavy'

export async function haptic(kind: HapticKind = 'light'): Promise<void> {
  if (isNative()) {
    const style =
      kind === 'heavy' ? ImpactStyle.Heavy : kind === 'medium' ? ImpactStyle.Medium : ImpactStyle.Light
    try {
      await Haptics.impact({ style })
      return
    } catch {
      /* fall through to web vibration */
    }
  }
  navigator.vibrate?.(kind === 'heavy' ? 30 : kind === 'medium' ? 18 : 8)
}

/**
 * The detent tick for dials and carousels — iOS's picker-wheel selection
 * haptic on native (crisper and quieter than an impact), a 4ms buzz on
 * Android web. One tick per detent crossing makes a scroll feel ratcheted.
 */
export async function hapticTick(): Promise<void> {
  if (isNative()) {
    try {
      await Haptics.selectionChanged()
      return
    } catch {
      /* fall through */
    }
  }
  navigator.vibrate?.(4)
}

/**
 * Native camera capture. Returns a data URL, or null when we're on the web —
 * callers fall back to an <input capture> there.
 */
export async function captureWithNativeCamera(): Promise<string | null> {
  if (!isNative()) return null
  try {
    const photo = await Camera.getPhoto({
      quality: 92,
      resultType: CameraResultType.DataUrl,
      source: CameraSource.Camera,
      correctOrientation: true,
    })
    return photo.dataUrl ?? null
  } catch {
    return null // user cancelled
  }
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve((r.result as string).split(',')[1])
    r.onerror = reject
    r.readAsDataURL(blob)
  })
}

export interface DeliverResult {
  ok: boolean
  via: 'native-share' | 'web-share' | 'download' | 'open' | 'none'
}

/**
 * Get an exported file into the user's hands on every platform:
 *  - native iOS → write to cache + system share sheet (Save Image / AirDrop / socials)
 *  - web with file-share support (iOS Safari!) → navigator.share
 *  - desktop browsers → anchor download
 *  - last resort → open in a new tab
 */
export async function deliverFile(blob: Blob, filename: string, text?: string): Promise<DeliverResult> {
  if (isNative()) {
    try {
      const { uri } = await Filesystem.writeFile({
        path: filename,
        data: await blobToBase64(blob),
        directory: Directory.Cache,
      })
      await Share.share({ files: [uri], text })
      return { ok: true, via: 'native-share' }
    } catch (e) {
      if ((e as Error)?.message?.toLowerCase().includes('cancel')) return { ok: false, via: 'none' }
      /* fall through to web paths */
    }
  }

  const file = new File([blob], filename, { type: blob.type })
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], text })
      return { ok: true, via: 'web-share' }
    } catch {
      return { ok: false, via: 'none' } // user dismissed the sheet
    }
  }

  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  if (typeof a.download === 'string') {
    a.href = url
    a.download = filename
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 30_000)
    return { ok: true, via: 'download' }
  }
  window.open(url, '_blank', 'noopener')
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
  return { ok: true, via: 'open' }
}
