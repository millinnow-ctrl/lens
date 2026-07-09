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
import { projectCardQuad, warpImage, type Pt } from '../lib/perspective'
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
  /** how dark the contact shadow reads on this material (soft sand vs hard marble) */
  shadowAlpha: number
  /** how much the surface warms the reflected light on the print */
  warmth: number
}

const SURFACES: Surface[] = [
  { id: 'wood', label: 'Warm oak', plate: plateWood, shadowAlpha: 0.34, warmth: 0.06 },
  { id: 'sand', label: 'Beach sand', plate: plateSand, shadowAlpha: 0.22, warmth: 0.05 },
  { id: 'linen', label: 'Linen', plate: plateLinen, shadowAlpha: 0.2, warmth: 0.02 },
  { id: 'marble', label: 'Café marble', plate: plateMarble, shadowAlpha: 0.3, warmth: 0.0 },
  { id: 'grass', label: 'Summer grass', plate: plateGrass, shadowAlpha: 0.24, warmth: 0.01 },
]

/**
 * The ONE camera pose, shared by every surface — a phone held above the table
 * at a fixed downward tilt with a natural casual roll. Only the printed image
 * (and the table under it) changes; the geometry, focal length and shadow are
 * constant. This is what makes the feature feel like the same physical Polaroid
 * restaged, not a fresh mock-up each time.
 */
const POSE = { cx: 0.5, cy: 0.55, size: 0.7, tiltDeg: 52, rollDeg: -8 } as const
const CARD_W = 1000
const CARD_H = 1140
const CARD_ASPECT = CARD_W / CARD_H

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

/**
 * Build a classic instant-film card at fixed proportions from the graded photo.
 * The proportions never change, so the perspective template stays consistent —
 * only the picture in the window differs. Adds paper grain and a recessed
 * emulsion window so the print reads as a physical object, not a flat frame.
 */
function buildPolaroidCard(photo: HTMLCanvasElement): HTMLCanvasElement {
  const card = document.createElement('canvas')
  card.width = CARD_W
  card.height = CARD_H
  const c = card.getContext('2d')!
  // paper: warm off-white, very slightly cooler at top
  const paper = c.createLinearGradient(0, 0, 0, CARD_H)
  paper.addColorStop(0, '#fdfdfa')
  paper.addColorStop(0.75, '#f7f4ec')
  paper.addColorStop(1, '#efeadd')
  c.fillStyle = paper
  c.fillRect(0, 0, CARD_W, CARD_H)

  // the square emulsion window (classic instant-film geometry)
  const margin = 68
  const win = CARD_W - margin * 2
  const wx = margin
  const wy = margin
  // fit the photo cover into the window
  const scale = Math.max(win / photo.width, win / photo.height)
  const dw = photo.width * scale
  const dh = photo.height * scale
  c.save()
  c.beginPath()
  c.rect(wx, wy, win, win)
  c.clip()
  c.drawImage(photo, wx + (win - dw) / 2, wy + (win - dh) / 2, dw, dh)
  c.restore()

  // recessed emulsion: thin dark inner edge + faint gloss
  c.save()
  c.strokeStyle = 'rgba(20,22,20,0.28)'
  c.lineWidth = 2
  c.strokeRect(wx + 0.5, wy + 0.5, win - 1, win - 1)
  const gloss = c.createLinearGradient(wx, wy, wx, wy + win)
  gloss.addColorStop(0, 'rgba(255,255,255,0.10)')
  gloss.addColorStop(0.12, 'rgba(255,255,255,0)')
  c.fillStyle = gloss
  c.fillRect(wx, wy, win, win)
  c.restore()

  // paper grain across the border
  const grain = c.getImageData(0, 0, CARD_W, CARD_H)
  const gd = grain.data
  for (let i = 0; i < gd.length; i += 4) {
    const n = (Math.random() - 0.5) * 7
    gd[i] += n
    gd[i + 1] += n
    gd[i + 2] += n
  }
  c.putImageData(grain, 0, 0)
  return card
}

/** fill a quad path */
function quadPath(x: CanvasRenderingContext2D, q: Pt[]) {
  x.beginPath()
  x.moveTo(q[0][0], q[0][1])
  x.lineTo(q[1][0], q[1][1])
  x.lineTo(q[2][0], q[2][1])
  x.lineTo(q[3][0], q[3][1])
  x.closePath()
}

/**
 * Photograph the card on the surface: cover-fit the (defocused) plate, lay a
 * soft contact shadow under the card, extrude a visible paper edge, then warp
 * the card into the fixed camera quad. The result looks like a phone photo of a
 * real Polaroid — the same pose every time, only the picture and table change.
 */
async function composeOnSurface(card: HTMLCanvasElement, surface: Surface): Promise<HTMLCanvasElement> {
  const W = 1080
  const H = 1440
  const out = document.createElement('canvas')
  out.width = W
  out.height = H
  const x = out.getContext('2d')!

  // 1 — surface, cover-fit and softly out of focus (shallow DOF, print is the subject)
  const plate = await loadImage(surface.plate)
  const pw = plate.width
  const ph = plate.height
  const sc = Math.max(W / pw, H / ph)
  x.save()
  x.filter = 'blur(7px) saturate(1.04) brightness(1.02)'
  x.drawImage(plate, (W - pw * sc) / 2 - 14, (H - ph * sc) / 2 - 14, pw * sc + 28, ph * sc + 28)
  x.restore()

  // the fixed pose quad (TL,TR,BR,BL), shared by every surface
  const quad = projectCardQuad({
    W,
    H,
    cardAspect: CARD_ASPECT,
    cx: POSE.cx,
    cy: POSE.cy,
    size: POSE.size,
    tiltDeg: POSE.tiltDeg,
    rollDeg: POSE.rollDeg,
  })

  // 2 — soft contact shadow: the card's silhouette, pushed down/back and blurred
  const shadowShift = 22
  const shadowQuad: Pt[] = quad.map(([px, py], i) => {
    // grow slightly outward from the card centre so the penumbra spills past the edges
    const cxq = (quad[0][0] + quad[1][0] + quad[2][0] + quad[3][0]) / 4
    const cyq = (quad[0][1] + quad[1][1] + quad[2][1] + quad[3][1]) / 4
    const gx = (px - cxq) * 0.04
    const gy = (py - cyq) * 0.04
    // near edge (bottom, i=2,3) casts a longer, softer shadow
    const far = i >= 2 ? shadowShift : shadowShift * 0.5
    return [px + gx, py + gy + far]
  })
  x.save()
  x.filter = 'blur(18px)'
  x.globalAlpha = surface.shadowAlpha
  x.fillStyle = 'rgb(18,16,14)'
  quadPath(x, shadowQuad)
  x.fill()
  x.restore()
  // a tighter, darker contact line right under the near edge
  x.save()
  x.filter = 'blur(6px)'
  x.globalAlpha = surface.shadowAlpha * 0.9
  x.fillStyle = 'rgb(12,10,8)'
  const contact: Pt[] = [
    quad[3],
    quad[2],
    [quad[2][0], quad[2][1] + 10],
    [quad[3][0], quad[3][1] + 10],
  ]
  quadPath(x, contact)
  x.fill()
  x.restore()

  // 3 — visible paper thickness: a cream edge extruded beneath the card
  const edge = 7
  const edgeQuad: Pt[] = quad.map(([px, py]) => [px, py + edge])
  x.save()
  x.fillStyle = '#d9d3c4'
  quadPath(x, edgeQuad)
  x.fill()
  x.restore()

  // 4 — the card itself, warped into the fixed pose
  warpImage(x, card, quad, 20)

  // 5 — reflected surface warmth + gentle top-key sheen on the print
  x.save()
  quadPath(x, quad)
  x.clip()
  if (surface.warmth > 0) {
    x.globalCompositeOperation = 'soft-light'
    x.fillStyle = `rgba(255,196,120,${surface.warmth})`
    x.fillRect(0, 0, W, H)
  }
  // a soft diffuse key falling from top-left, believable ambient light
  x.globalCompositeOperation = 'source-over'
  const key = x.createLinearGradient(quad[0][0], quad[0][1], quad[2][0], quad[2][1])
  key.addColorStop(0, 'rgba(255,255,255,0.10)')
  key.addColorStop(0.35, 'rgba(255,255,255,0)')
  key.addColorStop(1, 'rgba(20,18,26,0.06)')
  x.fillStyle = key
  x.fillRect(0, 0, W, H)
  x.restore()

  // 6 — phone-photo finish: gentle vignette + fine grain over everything
  const vg = x.createRadialGradient(W / 2, H * 0.46, H * 0.32, W / 2, H * 0.5, H * 0.82)
  vg.addColorStop(0, 'rgba(0,0,0,0)')
  vg.addColorStop(1, 'rgba(0,0,0,0.18)')
  x.fillStyle = vg
  x.fillRect(0, 0, W, H)
  const fin = x.getImageData(0, 0, W, H)
  const fd = fin.data
  for (let i = 0; i < fd.length; i += 4) {
    const n = (Math.random() - 0.5) * 4
    fd[i] += n
    fd[i + 1] += n
    fd[i + 2] += n
  }
  x.putImageData(fin, 0, 0)
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
        // grade through the Polaroid stock but WITHOUT its built-in frame — we
        // build our own fixed-proportion card so the 3D template stays consistent
        const graded = renderStyled(
          img,
          polaroidStyle,
          { ...polaroidStyle.defaults },
          { maxSize: 1000, frame: false },
        )
        printRef.current = buildPolaroidCard(graded)
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

  /** Share — native share sheet with the composited print, download fallback */
  const share = useCallback(async () => {
    if (!compositeUrl) return
    try {
      const blob = await (await fetch(compositeUrl)).blob()
      const file = new File([blob], 'lensmood-print.jpg', { type: 'image/jpeg' })
      const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean }
      if (nav.canShare?.({ files: [file] }) && nav.share) {
        await nav.share({
          files: [file],
          title: 'My LensMood print',
          text: 'Printed with LensMood',
        })
        return
      }
    } catch {
      /* share cancelled or unsupported — fall through to download */
    }
    const a = document.createElement('a')
    a.href = compositeUrl
    a.download = 'lensmood-print.jpg'
    a.click()
  }, [compositeUrl])

  return (
    <main className="mx-auto w-full max-w-lg px-4 pb-32 pt-6 min-h-screen">
      <header className="mb-6">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-[var(--ink,#17242d)]/[0.06] px-3 py-1 text-[12px] font-semibold text-[var(--ink,#17242d)]">
          <span className="h-1.5 w-1.5 rounded-full bg-[var(--accent,#0e7490)]" />
          Print Room
        </span>
        <h1 className="mt-3 text-[26px] font-extrabold leading-[1.1] tracking-tight">
          Turn your shot into a print you can hold.
        </h1>
        <p className="mt-2 text-[15px] leading-snug text-[var(--fog,#5c6b76)]">
          We develop it as a real instant photo, set it on a table, and shoot it like you would.
        </p>
      </header>

      {phase === 'pick' && (
        <section>
          <h2 className="mb-3 text-[17px] font-bold tracking-tight">Choose a shot to print</h2>
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
          <div className="mt-6 mb-2.5 flex items-baseline justify-between">
            <h2 className="text-[17px] font-bold tracking-tight">Set the table</h2>
            <span className="text-[13px] text-[var(--fog,#5c6b76)]">where it rests</span>
          </div>
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
                onClick={() => void share()}
                disabled={phase !== 'settled'}
                className="btn btn-primary flex-1 inline-flex items-center justify-center gap-2 disabled:opacity-50"
              >
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden>
                  <path
                    d="M12 3v12M12 3 8 7M12 3l4 4"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                  <path
                    d="M5 12v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
                Share
              </button>
            </div>
            <p className="text-center text-[13px] text-[var(--fog,#5c6b76)]">
              {phase === 'idle' && 'Hit print — flash, eject, and watch it develop.'}
              {phase === 'clip' && 'Printing…'}
              {phase === 'develop' && 'Developing…'}
              {phase === 'settled' && 'Saved just like a photo you snapped of the print.'}
            </p>
          </div>
        </section>
      )}
    </main>
  )
}
