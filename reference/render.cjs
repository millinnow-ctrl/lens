const { createCanvas, loadImage, GlobalFonts } = require('@napi-rs/canvas')
const { writeFileSync } = require('fs')
const path = require('path')
// DOM shim: the engine only asks document for canvases
global.HTMLVideoElement = class HTMLVideoElement {}
global.HTMLImageElement = class HTMLImageElement {}
global.HTMLCanvasElement = class HTMLCanvasElement {}
global.document = { createElement: (tag) => { if (tag !== 'canvas') throw new Error(tag); return createCanvas(1, 1) } }
const SP = __dirname
const { renderStyled } = require(path.join(SP, 'out', 'engine.js'))
const { CAMERA_STYLES } = require(path.join(SP, 'out', 'styles.js'))

const PHOTOS = process.argv[2].split(',')
const STOCKS = process.argv[3].split(',')

async function main() {
  for (const ph of PHOTOS) {
    const img = await loadImage(path.join(SP, 'photos', `sample-${ph}.jpg`))
    const cell = 560
    const tiles = []
    // original first
    tiles.push({ label: 'Original', canvas: cover(img, cell) })
    for (const id of STOCKS) {
      const st = CAMERA_STYLES.find((s) => s.id === id)
      if (!st) { console.log('missing stock', id); continue }
      const out = renderStyled(img, st, { ...st.defaults }, { maxSize: 900, watermark: false })
      tiles.push({ label: st.name, canvas: cover(out, cell) })
    }
    // compose grid 2 cols
    const cols = 2, rows = Math.ceil(tiles.length / cols), pad = 14, labelH = 44
    const W = cols * cell + pad * (cols + 1)
    const H = rows * (cell + labelH) + pad * (rows + 1)
    const grid = createCanvas(W, H)
    const g = grid.getContext('2d')
    g.fillStyle = '#101418'; g.fillRect(0, 0, W, H)
    tiles.forEach((t, i) => {
      const cx = pad + (i % cols) * (cell + pad)
      const cy = pad + Math.floor(i / cols) * (cell + labelH + pad)
      g.drawImage(t.canvas, cx, cy)
      g.fillStyle = '#eef2f5'; g.font = '600 22px sans-serif'
      g.fillText(t.label, cx + 4, cy + cell + 30)
    })
    writeFileSync(path.join(SP, `preview-${ph}.png`), grid.toBuffer('image/png'))
    console.log('wrote preview-' + ph)
  }
}
function cover(src, size) {
  const c = createCanvas(size, size); const x = c.getContext('2d')
  const sw = src.width, sh = src.height, s = Math.max(size / sw, size / sh)
  x.drawImage(src, (size - sw * s) / 2, (size - sh * s) / 2, sw * s, sh * s)
  return c
}
main().catch((e) => { console.error('FAILED:', e.message); console.error(e.stack.split('\n').slice(0,4).join('\n')); process.exit(1) })
