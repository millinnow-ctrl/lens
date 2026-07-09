/**
 * Print Room — the polaroid becomes a physical object you can post.
 * Pick a shot, hit PRINT: snap-flash + shutter click, a real film clip of the
 * printer ejecting the black undeveloped print (the same clip every time —
 * the machine is the constant), then YOUR print develops and lands on a real
 * staged surface (wooden chair / beach sand / linen / café marble / grass).
 * Download exports a composite that looks like a photo you took of the print.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { renderStyled, loadImage } from '../lib/engine'
import { CAMERA_STYLES } from '../lib/styles'
import ejectClipMp4 from '../assets/print/eject.mp4'
import ejectClipWebm from '../assets/print/eject.webm'
import plateWood from '../assets/print/wood.jpg'
import plateSand from '../assets/print/sand.jpg'
import plateLinen from '../assets/print/linen.jpg'
import plateMarble from '../assets/print/marble.jpg'
import plateGrass from '../assets/print/grass.jpg'
import sampleGolden from '../assets/sample-golden.jpg'
import sampleBrunch from '../assets/sample-brunch.jpg'
import sampleFriends from '../assets/sample-friends.jpg'
import sampleStreet from '../assets/sample-street.jpg'

interface Surface {
  id: string
  label: string
  plate: string
  x: number // print center, 0..1 of composite
  y: number
  scale: number // print width fraction
  rot: number // deg
  shadow: { blur: number; alpha: number; dy: number }
}

const SURFACES: Surface[] = [
  { id: 'wood', label: 'Wooden chair', plate: plateWood, x: 0.5, y: 0.52, scale: 0.62, rot: -4, shadow: { blur: 26, alpha: 0.36, dy: 16 } },
  { id: 'sand', label: 'Beach sand', plate: plateSand, x: 0.52, y: 0.5, scale: 0.6, rot: 7, shadow: { blur: 34, alpha: 0.24, dy: 12 } },
  { id: 'linen', label: 'Linen sheet', plate: plateLinen, x: 0.48, y: 0.53, scale: 0.64, rot: -9, shadow: { blur: 30, alpha: 0.24, dy: 11 } },
  { id: 'marble', label: 'Café marble', plate: plateMarble, x: 0.55, y: 0.48, scale: 0.58, rot: 3, shadow: { blur: 18, alpha: 0.4, dy: 9 } },
  { id: 'grass', label: 'Grass', plate: plateGrass, x: 0.5, y: 0.5, scale: 0.62, rot: -6, shadow: { blur: 38, alpha: 0.2, dy: 10 } },
]

const SAMPLES = [
  { id: 'golden', label: 'Golden hour', src: sampleGolden },
  { id: 'brunch', label: 'Brunch', src: sampleBrunch },
  { id: 'friends', label: 'Friends', src: sampleFriends },
  { id: 'street', label: 'Street', src: sampleStreet },
]

type Phase = 'pick' | 'idle' | 'clip' | 'develop' | 'settled'

/** a camera click, synthesized — no audio asset needed on the web */
function playShutterClick() {
  try {
    const ctx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)()
    const now = ctx.currentTime
    // the mechanical snap: a short filtered noise burst
    const len = Math.floor(ctx.sampleRate * 0.05)
    const buf = ctx.createBuffer(1, len, ctx.sampleRate)
    const data = buf.getChannelData(0)
    for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (len * 0.18))
    const src = ctx.createBufferSource()
    src.buffer = buf
    const hp = ctx.createBiquadFilter()
    hp.type = 'highpass'
    hp.frequency.value = 1800
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.5, now)
    src.connect(hp).connect(g).connect(ctx.destination)
    src.start(now)
    // the leaf-shutter ping underneath
    const osc = ctx.createOscillator()
    osc.type = 'square'
    osc.frequency.setValueAtTime(2600, now)
    osc.frequency.exponentialRampToValueAtTime(900, now + 0.04)
    const og = ctx.createGain()
    og.gain.setValueAtTime(0.12, now)
    og.gain.exponentialRampToValueAtTime(0.0001, now + 0.06)
    osc.connect(og).connect(ctx.destination)
    osc.start(now)
    osc.stop(now + 0.07)
    setTimeout(() => void ctx.close(), 400)
  } catch {
    /* audio blocked — the flash still sells the snap */
  }
}

/** composite the developed polaroid onto the chosen surface, like a photo of it */
async function composeOnSurface(print: HTMLCanvasElement, surface: Surface): Promise<HTMLCanvasElement> {
  const W = 1080
  const H = 1440
  const out = document.createElement('canvas')
  out.width = W
  out.height = H
  const x = out.getContext('2d')!
  const plate = await loadImage(surface.plate)
  const pw = plate.width
  const ph = plate.height
  const sc = Math.max(W / pw, H / ph)
  x.drawImage(plate, (W - pw * sc) / 2, (H - ph * sc) / 2, pw * sc, ph * sc)

  const w = surface.scale * W
  const h = (w * print.height) / print.width
  x.save()
  x.translate(surface.x * W, surface.y * H)
  x.rotate((surface.rot * Math.PI) / 180)
  x.shadowColor = `rgba(4,10,14,${surface.shadow.alpha})`
  x.shadowBlur = surface.shadow.blur
  x.shadowOffsetY = surface.shadow.dy
  x.drawImage(print, -w / 2, -h / 2, w, h)
  x.restore()

  // gentle vignette so it reads like a phone photo of the scene
  const vg = x.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 0.78)
  vg.addColorStop(0, 'rgba(0,0,0,0)')
  vg.addColorStop(1, 'rgba(0,0,0,0.16)')
  x.fillStyle = vg
  x.fillRect(0, 0, W, H)
  return out
}

export default function PrintRoom() {
  const [phase, setPhase] = useState<Phase>('pick')
  const [busy, setBusy] = useState(false)
  const [surface, setSurface] = useState<Surface>(SURFACES[0])
  const [flashOn, setFlashOn] = useState(false)
  const printRef = useRef<HTMLCanvasElement | null>(null)
  const [compositeUrl, setCompositeUrl] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)

  const polaroidStyle = useMemo(() => CAMERA_STYLES.find((s) => s.id === 'polaroid')!, [])

  /** develop the chosen photo through the Polaroid stock (framed) */
  const develop = useCallback(
    async (src: string) => {
      setBusy(true)
      try {
        const img = await loadImage(src)
        printRef.current = renderStyled(img, polaroidStyle, { ...polaroidStyle.defaults }, { maxSize: 1000 })
        setCompositeUrl(null)
        setPhase('idle')
      } finally {
        setBusy(false)
      }
    },
    [polaroidStyle],
  )

  const onUpload = useCallback(
    (f: File | undefined) => {
      if (!f) return
      const url = URL.createObjectURL(f)
      void develop(url).finally(() => URL.revokeObjectURL(url))
    },
    [develop],
  )

  /** PRINT — flash + click, then the printer clip */
  const firePrint = useCallback(() => {
    playShutterClick()
    setFlashOn(true)
    setTimeout(() => setFlashOn(false), 240)
    setTimeout(() => setPhase('clip'), 120)
  }, [])

  /** the clip finished — composite the print on the surface and develop it in */
  const onClipDone = useCallback(async () => {
    if (!printRef.current) return
    const c = await composeOnSurface(printRef.current, surface)
    setCompositeUrl(c.toDataURL('image/jpeg', 0.92))
    setPhase('develop')
    setTimeout(() => setPhase('settled'), 2800)
  }, [surface])

  // re-stage instantly when the surface changes after settle
  useEffect(() => {
    if ((phase === 'develop' || phase === 'settled') && printRef.current) {
      void composeOnSurface(printRef.current, surface).then((c) =>
        setCompositeUrl(c.toDataURL('image/jpeg', 0.92)),
      )
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [surface])

  // safety: never hang on the clip if playback stalls
  useEffect(() => {
    if (phase !== 'clip') return
    const t = setTimeout(() => void onClipDone(), 4200)
    return () => clearTimeout(t)
  }, [phase, onClipDone])

  const download = useCallback(() => {
    if (!compositeUrl) return
    const a = document.createElement('a')
    a.href = compositeUrl
    a.download = 'lensmood-print.jpg'
    a.click()
  }, [compositeUrl])

  return (
    <main className="mx-auto w-full max-w-lg px-4 pb-32 pt-6 min-h-screen">
      <header className="mb-5">
        <p className="font-mono text-[11px] tracking-[0.22em] text-[var(--fog,#5c6b76)]">PRINT ROOM</p>
        <h1 className="mt-1 text-2xl font-extrabold tracking-tight">Print it. Stage it. Post it.</h1>
        <p className="mt-1 text-sm text-[var(--fog,#5c6b76)]">
          Your shot becomes a real polaroid — printed, developed, and photographed on a surface.
        </p>
      </header>

      {phase === 'pick' && (
        <section>
          <p className="font-mono mb-3 text-[11px] tracking-[0.18em] text-[var(--fog,#5c6b76)]">
            PICK A SHOT TO PRINT
          </p>
          <div className="grid grid-cols-2 gap-3">
            {SAMPLES.map((s) => (
              <button
                key={s.id}
                type="button"
                onClick={() => void develop(s.src)}
                disabled={busy}
                className="group overflow-hidden rounded-xl border border-black/10 bg-white shadow-sm transition hover:shadow-md disabled:opacity-60"
              >
                <img src={s.src} alt={s.label} className="aspect-[3/4] w-full object-cover transition group-hover:scale-[1.02]" />
                <span className="block px-2 py-1.5 text-left text-xs font-semibold">{s.label}</span>
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            disabled={busy}
            className="btn btn-primary mt-4 w-full disabled:opacity-60"
          >
            {busy ? 'Developing…' : 'Use your own photo'}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => onUpload(e.target.files?.[0])}
          />
        </section>
      )}

      {phase !== 'pick' && (
        <section>
          {/* the stage */}
          <div className="relative overflow-hidden rounded-2xl bg-[#0b0f12] shadow-lg" style={{ aspectRatio: '3 / 4' }}>
            {/* idle: the framed print waits over the surface, armed */}
            {phase === 'idle' && printRef.current && (
              <>
                <img src={surface.plate} alt="" className="absolute inset-0 h-full w-full object-cover opacity-70" />
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-6">
                  <img
                    src={printRef.current.toDataURL('image/jpeg', 0.9)}
                    alt="Your print, ready"
                    className="w-[56%] rotate-[-3deg] shadow-2xl"
                  />
                  <button
                    type="button"
                    onClick={firePrint}
                    className="rounded-full bg-[var(--accent,#0e7490)] px-12 py-4 font-mono text-base font-extrabold tracking-[0.28em] text-white shadow-xl transition active:scale-95"
                  >
                    PRINT
                  </button>
                </div>
              </>
            )}

            {/* the printer clip — the same film for every shot. Both codecs so
                every browser plays it (Safari/iOS take the mp4, Chromium webm) */}
            {phase === 'clip' && (
              <video
                ref={videoRef}
                muted
                autoPlay
                playsInline
                onEnded={() => void onClipDone()}
                className="absolute inset-0 h-full w-full object-cover"
              >
                <source src={ejectClipWebm} type="video/webm" />
                <source src={ejectClipMp4} type="video/mp4" />
              </video>
            )}

            {/* your print develops on the surface */}
            {(phase === 'develop' || phase === 'settled') && compositeUrl && (
              <img
                src={compositeUrl}
                alt="Your print staged on the surface"
                className="absolute inset-0 h-full w-full object-cover"
                style={
                  phase === 'develop'
                    ? { animation: 'lm-print-develop 2.8s cubic-bezier(0.61,0.02,0.34,0.99) both' }
                    : undefined
                }
              />
            )}

            {/* snap flash */}
            <div
              className="pointer-events-none absolute inset-0 bg-white transition-opacity duration-200"
              style={{ opacity: flashOn ? 1 : 0 }}
            />
          </div>

          {/* surfaces */}
          <p className="font-mono mt-5 mb-2 text-[11px] tracking-[0.18em] text-[var(--fog,#5c6b76)]">SET THE SCENE</p>
          <div className="flex gap-2 overflow-x-auto pb-1">
            {SURFACES.map((s) => (
              <button
                key={s.id}
                type="button"
                onClick={() => setSurface(s)}
                className={`shrink-0 rounded-full border px-4 py-2 text-sm font-semibold transition ${
                  s.id === surface.id
                    ? 'border-transparent bg-[var(--ink,#17242d)] text-white'
                    : 'border-black/15 bg-white text-[var(--ink,#17242d)] hover:border-black/30'
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>

          {/* actions */}
          <div className="mt-4 flex flex-col gap-2.5">
            {phase !== 'idle' && (
              <button
                type="button"
                onClick={firePrint}
                disabled={phase === 'clip'}
                className="btn w-full border border-black/15 bg-white font-semibold disabled:opacity-50"
              >
                Print again
              </button>
            )}
            <div className="flex gap-2.5">
              <button
                type="button"
                onClick={() => {
                  setPhase('pick')
                  setCompositeUrl(null)
                }}
                className="btn flex-1 border border-black/15 bg-white font-semibold"
              >
                New shot
              </button>
              <button
                type="button"
                onClick={download}
                disabled={phase !== 'settled'}
                className="btn btn-primary flex-1 disabled:opacity-50"
              >
                Download
              </button>
            </div>
            <p className="text-center font-mono text-[11px] text-[var(--fog,#5c6b76)]">
              {phase === 'idle' && 'press PRINT — flash, eject, and watch it develop.'}
              {phase === 'clip' && 'printing…'}
              {phase === 'develop' && 'developing…'}
              {phase === 'settled' && 'exports look like a photo you took of the print.'}
            </p>
          </div>
        </section>
      )}
    </main>
  )
}
