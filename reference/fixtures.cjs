/**
 * Golden fixtures — the parity anchor for the SwiftUI FilmEngine.
 *
 * gen    : render every stock x every photo -> fixtures/{baseline,extended}/...
 *          + manifest.json (engine commit, input hashes, dims, color model,
 *          tolerance version) + labeled review grids.
 * verify : re-render and compare SHA256 against the manifest (drift guard; the
 *          reference engine is deterministic by design).
 * degrade: build labeled synthetic-degraded variants (underexposed / noisy /
 *          blurry) from the real baseline photos -> photos-extended/.
 *
 * Color model: display-referred sRGB, 8-bit, unmanaged (the reference
 * engine's native behavior — owner ruling 2026-07-11: parity in this model
 * first; linear-light/HDR later as labeled intentional refinement).
 *
 * Usage (from reference/):
 *   NODE_PATH=../lensmood-native/node_modules node fixtures.cjs degrade
 *   NODE_PATH=../lensmood-native/node_modules node fixtures.cjs gen
 *   NODE_PATH=../lensmood-native/node_modules node fixtures.cjs verify
 */
const { createCanvas, loadImage } = require('@napi-rs/canvas')
const { writeFileSync, readFileSync, mkdirSync, existsSync, readdirSync } = require('fs')
const { createHash } = require('crypto')
const { execSync } = require('child_process')
const path = require('path')

global.HTMLVideoElement = class {}
global.HTMLImageElement = class {}
global.HTMLCanvasElement = class {}
global.document = { createElement: (t) => { if (t !== 'canvas') throw new Error(t); return createCanvas(1, 1) } }

const SP = __dirname
const { renderStyled } = require(path.join(SP, 'out', 'engine.js'))
const { CAMERA_STYLES } = require(path.join(SP, 'out', 'styles.js'))
const STOCKS = CAMERA_STYLES.filter((s) => s.id !== 'pro-body')


/** Harness-level determinism (engine untouched): the reference product uses
 *  wall-clock timestamps (security-cam) and Math.random (camcorder dropouts).
 *  Fixtures pin both — seeded per (photo,stock), date fixed — and record it. */
const PINNED_DATE_MS = Date.UTC(2026, 0, 1, 12, 0, 0)
const RealDate = Date
function seededRandom(seedStr) {
  let h = 2166136261
  for (let i = 0; i < seedStr.length; i++) { h ^= seedStr.charCodeAt(i); h = Math.imul(h, 16777619) }
  return function () {
    h = Math.imul(h ^ (h >>> 15), 2246822507); h = Math.imul(h ^ (h >>> 13), 3266489909)
    return ((h ^= h >>> 16) >>> 0) / 4294967296
  }
}
function withDeterminism(seedStr, fn) {
  const realRandom = Math.random
  Math.random = seededRandom(seedStr)
  class PinnedDate extends RealDate {
    constructor(...a) { a.length === 0 ? super(PINNED_DATE_MS) : super(...a) }
    static now() { return PINNED_DATE_MS }
  }
  global.Date = PinnedDate
  try { return fn() } finally { Math.random = realRandom; global.Date = RealDate }
}

const MAX_SIZE = 560
const TOLERANCE_VERSION = 1
const sha = (buf) => createHash('sha256').update(buf).digest('hex')

/** deterministic hash noise for the degraded variants (no Math.random) */
function detNoise(i, seed) {
  const x = Math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
  return x - Math.floor(x)
}

const BASELINE = ['golden', 'friends', 'brunch', 'street', 'night', 'concert', 'dog']

async function degrade() {
  const outDir = path.join(SP, 'photos-extended')
  mkdirSync(outDir, { recursive: true })
  const jobs = [
    // [source real photo, variant id, transform]
    ['golden', 'underexposed', (d, i) => Math.max(0, d * 0.22)],
    ['friends', 'noisy', (d, i, ch) => Math.min(255, Math.max(0, d + (detNoise(i * 4 + ch, 7) - 0.5) * 64))],
    ['brunch', 'blurry', null], // handled via canvas blur below
  ]
  for (const [src, variant, fn] of jobs) {
    const img = await loadImage(path.join(SP, 'photos', `sample-${src}.jpg`))
    const cv = createCanvas(img.width, img.height)
    const x = cv.getContext('2d')
    if (variant === 'blurry') {
      x.filter = 'blur(6px)'
      x.drawImage(img, 0, 0)
    } else {
      x.drawImage(img, 0, 0)
      const im = x.getImageData(0, 0, img.width, img.height)
      for (let i = 0; i < im.data.length; i += 4)
        for (let ch = 0; ch < 3; ch++) im.data[i + ch] = fn(im.data[i + ch], i / 4, ch)
      x.putImageData(im, 0, 0)
    }
    writeFileSync(path.join(outDir, `degraded-${variant}-from-${src}.png`), cv.toBuffer('image/png'))
    console.log(`wrote degraded-${variant}-from-${src}.png`)
  }
}

function listPhotos() {
  const photos = BASELINE.map((id) => ({
    id,
    set: 'baseline',
    file: `photos/sample-${id}.jpg`,
    kind: 'real-original',
    note: 'owner-approved real photograph (project sample set)',
  }))
  const extDir = path.join(SP, 'photos-extended')
  if (existsSync(extDir))
    for (const f of readdirSync(extDir).filter((f) => /\.(png|jpg|jpeg)$/i.test(f))) {
      const synthetic = f.startsWith('degraded-')
      photos.push({
        id: f.replace(/\.(png|jpg|jpeg)$/i, ''),
        set: 'extended',
        file: `photos-extended/${f}`,
        kind: synthetic ? 'synthetic-degraded' : 'real-provided',
        note: synthetic
          ? 'SYNTHETIC: deterministic degradation of a real baseline photo (technical edge case)'
          : 'real photograph provided/licensed by owner',
      })
    }
  return photos
}

async function gen() {
  const engineCommit = execSync('git rev-parse HEAD', { cwd: SP }).toString().trim()
  const photos = listPhotos()
  const manifest = {
    version: 1,
    toleranceVersion: TOLERANCE_VERSION,
    engine: {
      commit: engineCommit,
      twin: 'reference/lib/engine.ts',
      colorModel: 'display-referred sRGB, 8-bit, unmanaged (reference-native)',
      renderOptions: { maxSize: MAX_SIZE, watermark: false, frame: true, focal: null, scene: 'analyzed (adaptive)' },
      determinism: { pinnedDateUTC: '2026-01-01T12:00:00Z', rng: 'fnv1a-seeded per photo/stock (harness-level; engine untouched)' },
      knownLimit: 'focal=null in headless harness: face-lock adaptive paths dormant; covered in Phase B via recorded per-photo focal',
    },
    tolerances: { meanAbsChannel: 2.0, p99AbsChannel: 12.0, note: 'v1 defaults; per-stock overrides may be added with owner approval' },
    photos: [],
    fixtures: [],
  }
  for (const p of photos) {
    const buf = readFileSync(path.join(SP, p.file))
    manifest.photos.push({ ...p, sha256: sha(buf) })
    const img = await loadImage(path.join(SP, p.file))
    const outDir = path.join(SP, 'fixtures', p.set, p.id)
    mkdirSync(outDir, { recursive: true })
    const cell = 300
    const tiles = [{ label: 'Original', c: cover(img, cell) }]
    for (const st of STOCKS) {
      const out = withDeterminism(`${p.id}/${st.id}`, () =>
        renderStyled(img, st, { ...st.defaults }, { maxSize: MAX_SIZE, watermark: false }))
      const png = out.toBuffer('image/png')
      const file = `fixtures/${p.set}/${p.id}/${st.id}.png`
      writeFileSync(path.join(SP, file), png)
      manifest.fixtures.push({ photo: p.id, stock: st.id, file, sha256: sha(png), width: out.width, height: out.height })
      tiles.push({ label: st.name, c: cover(out, cell) })
    }
    // labeled review grid (4 cols)
    const cols = 4, rows = Math.ceil(tiles.length / cols), pad = 10, lh = 30
    const G = createCanvas(cols * cell + pad * (cols + 1), rows * (cell + lh) + pad * (rows + 1))
    const g = G.getContext('2d')
    g.fillStyle = '#101418'; g.fillRect(0, 0, G.width, G.height)
    tiles.forEach((t, i) => {
      const cx = pad + (i % cols) * (cell + pad), cy = pad + Math.floor(i / cols) * (cell + lh + pad)
      g.drawImage(t.c, cx, cy)
      g.fillStyle = '#eef2f5'; g.font = '600 15px sans-serif'; g.fillText(t.label, cx + 2, cy + cell + 20)
    })
    writeFileSync(path.join(SP, 'fixtures', p.set, `${p.id}-grid.png`), G.toBuffer('image/png'))
    console.log(`fixtures: ${p.id} (${p.set}) — ${STOCKS.length} stocks + grid`)
  }
  writeFileSync(path.join(SP, 'fixtures', 'manifest.json'), JSON.stringify(manifest, null, 2))
  console.log(`\nmanifest: ${manifest.fixtures.length} fixtures, ${manifest.photos.length} photos, engine ${engineCommit.slice(0, 9)}`)
}

async function verify() {
  const manifest = JSON.parse(readFileSync(path.join(SP, 'fixtures', 'manifest.json')))
  let fail = 0
  for (const p of manifest.photos) {
    const img = await loadImage(path.join(SP, p.file))
    if (sha(readFileSync(path.join(SP, p.file))) !== p.sha256) { console.log(`FAIL input drift: ${p.id}`); fail++; continue }
    for (const fx of manifest.fixtures.filter((f) => f.photo === p.id)) {
      const st = STOCKS.find((s) => s.id === fx.stock)
      const out = withDeterminism(`${p.id}/${fx.stock}`, () =>
        renderStyled(img, st, { ...st.defaults }, { maxSize: MAX_SIZE, watermark: false }))
      const png = out.toBuffer('image/png')
      if (sha(png) !== fx.sha256) { console.log(`FAIL render drift: ${fx.photo}/${fx.stock}`); fail++ }
      if (process.env.FIXTURES_OUT) {
        const d = path.join(process.env.FIXTURES_OUT, p.set, p.id)
        mkdirSync(d, { recursive: true })
        writeFileSync(path.join(d, `${fx.stock}.png`), png)
      }
    }
    console.log(`verified: ${p.id}`)
  }
  console.log(fail === 0 ? '\nALL FIXTURES REPRODUCE EXACTLY' : `\n${fail} DRIFTS`)
  process.exit(fail ? 1 : 0)
}

function cover(src, size) {
  const c = createCanvas(size, size), x = c.getContext('2d')
  const s = Math.max(size / src.width, size / src.height)
  x.drawImage(src, (size - src.width * s) / 2, (size - src.height * s) / 2, src.width * s, src.height * s)
  return c
}

const cmd = process.argv[2]
if (cmd === 'gen') gen()
else if (cmd === 'verify') verify()
else if (cmd === 'degrade') degrade()
else { console.log('usage: fixtures.cjs gen|verify|degrade'); process.exit(2) }
