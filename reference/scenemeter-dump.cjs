/**
 * Scene-meter parity dump — golden numbers for the Swift SceneAnalyzer port.
 *
 * Runs the compiled reference scene meter (reference/out/scene.js, the tsc
 * output of reference/lib/scene.ts — same math as the frozen
 * lensmood-native/src/engine/scene.ts) headless over every photo in
 * fixtures/manifest.json and dumps every field of the resulting SceneProfile
 * (plus sceneLabel / sceneNotes) to
 * ../LensMoodApp/Tests/Fixtures/scene-metrics.json.
 *
 * Each photo is analyzed twice: once with focal=null (pass 3 dormant, same as
 * the render fixtures) and once with a fixed synthetic focal probe so the
 * face-ellipse metering pass is exercised too. The probe value is arbitrary
 * but committed with the fixture so the Swift test replays it exactly.
 *
 * Usage (from reference/):
 *   NODE_PATH=../lensmood-native/node_modules node scenemeter-dump.cjs
 */
const { createCanvas, loadImage } = require('@napi-rs/canvas')
const { writeFileSync, readFileSync } = require('fs')
const path = require('path')

// DOM shim — same as fixtures.cjs: the meter only asks document for canvases
global.HTMLVideoElement = class {}
global.HTMLImageElement = class {}
global.HTMLCanvasElement = class {}
global.document = { createElement: (t) => { if (t !== 'canvas') throw new Error(t); return createCanvas(1, 1) } }

const SP = __dirname
const { analyzeScene, sceneLabel, sceneNotes } = require(path.join(SP, 'out', 'scene.js'))

/** fixed synthetic focal probe (face center x, y normalized; r as fraction of
 *  the longest edge) — exercises pass 3 identically on both sides */
const FOCAL = { x: 0.5, y: 0.42, r: 0.2 }

function dump(p) {
  return {
    analyzed: p.analyzed,
    key: p.key,
    p01: p.p01,
    p50: p.p50,
    p99: p.p99,
    illum: p.illum,
    sat: p.sat,
    faceLum: p.faceLum,
    lights: p.lights.map((l) => ({ x: l.x, y: l.y, r: l.r, intensity: l.intensity, tint: l.tint })),
    label: sceneLabel(p),
    notes: sceneNotes(p),
  }
}

async function main() {
  const manifest = JSON.parse(readFileSync(path.join(SP, 'fixtures', 'manifest.json')))
  const out = {
    generator: 'reference/scenemeter-dump.cjs',
    meter: 'lensmood-native/src/engine/scene.ts (frozen reference; compiled twin reference/out/scene.js)',
    thumb: 96,
    focalProbe: FOCAL,
    photos: {},
  }
  for (const p of manifest.photos) {
    const img = await loadImage(path.join(SP, p.file))
    const noFocal = analyzeScene(img, null)
    const withFocal = analyzeScene(img, FOCAL)
    out.photos[p.id] = {
      file: p.file,
      width: img.width,
      height: img.height,
      noFocal: dump(noFocal),
      withFocal: dump(withFocal),
    }
    console.log(
      `${p.id}: key=${noFocal.key.toFixed(4)} p50=${noFocal.p50.toFixed(4)} ` +
        `illum=[${noFocal.illum.map((v) => v.toFixed(3)).join(',')}] ` +
        `lights=${noFocal.lights.length} faceLum=${withFocal.faceLum?.toFixed(4)} label=${sceneLabel(noFocal)}`,
    )
  }
  const dest = path.join(SP, '..', 'LensMoodApp', 'Tests', 'Fixtures', 'scene-metrics.json')
  writeFileSync(dest, JSON.stringify(out, null, 2) + '\n')
  console.log(`\nwrote ${path.relative(path.join(SP, '..'), dest)} (${Object.keys(out.photos).length} photos)`)
}

main().catch((e) => { console.error('FAILED:', e); process.exit(1) })
