/**
 * Node test for the camcorder look (src/engine/vhsLook.ts) — the pure math
 * behind the tape: grade behavior, clamping, monotonicity, and LUT integrity.
 * Runs headless (no Skia, no device): `npm run test:look`.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const work = mkdtempSync(join(tmpdir(), 'vhslook-'))

// compile the single module outside the project so app tsconfig doesn't apply
execFileSync(
  process.execPath,
  [
    join(root, 'node_modules', 'typescript', 'lib', 'tsc.js'),
    join(root, 'src', 'engine', 'vhsLook.ts'),
    '--outDir', work,
    '--module', 'esnext',
    '--target', 'es2020',
  ],
  { cwd: work, stdio: 'inherit' },
)

const { vhsGrade, buildVhsLut, VHS_SKSL } = await import(pathToFileURL(join(work, 'vhsLook.js')).href)

const luma = ([r, g, b]) => 0.299 * r + 0.587 * g + 0.114 * b
let failures = 0
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`)
  if (!ok) failures++
}

const black = vhsGrade(0, 0, 0)
const white = vhsGrade(1, 1, 1)
check('black lifted (smoky tape)', luma(black) > 0.02 && luma(black) < 0.09, luma(black).toFixed(3))
check('white compressed below clip', luma(white) > 0.93 && luma(white) <= 1.0, luma(white).toFixed(3))
check('shadow teal cast', black[1] > black[0])
check('highlight cream cast', white[0] >= white[1])

const mid = vhsGrade(0.5, 0.5, 0.5)
check('mid gray stays mid', luma(mid) > 0.45 && luma(mid) < 0.55, luma(mid).toFixed(3))

let monotonic = true
let prev = -1
for (let i = 0; i <= 32; i++) {
  const v = luma(vhsGrade(i / 32, i / 32, i / 32))
  if (v < prev) monotonic = false
  prev = v
}
check('gray ramp monotonic', monotonic)

const sat = (c) => {
  const mx = Math.max(...c)
  const mn = Math.min(...c)
  return mx === 0 ? 0 : (mx - mn) / mx
}
check('saturation reduced', sat(vhsGrade(1, 0, 0)) < 0.98)

let clamped = true
for (let r = 0; r <= 4; r++)
  for (let g = 0; g <= 4; g++)
    for (let b = 0; b <= 4; b++) {
      const o = vhsGrade(r / 4, g / 4, b / 4)
      if (o.some((v) => v < 0 || v > 1)) clamped = false
    }
check('full cube sweep clamped', clamped)

const lut = buildVhsLut(33)
const bytes = Buffer.from(lut.data, 'base64')
check('LUT byte size', bytes.length === 33 ** 3 * 4 * 4, `${bytes.length}`)
const first = new Float32Array(bytes.buffer, bytes.byteOffset, 4)
const b0 = vhsGrade(0, 0, 0)
check(
  'LUT[0] == grade(0,0,0)',
  Math.abs(first[0] - b0[0]) < 1e-6 && Math.abs(first[1] - b0[1]) < 1e-6 && first[3] === 1,
)
const last = new Float32Array(bytes.buffer, bytes.byteOffset + (33 ** 3 - 1) * 16, 4)
const w1 = vhsGrade(1, 1, 1)
check('LUT[last] == grade(1,1,1)', Math.abs(last[0] - w1[0]) < 1e-6 && Math.abs(last[1] - w1[1]) < 1e-6)

// the live-preview shader must compile in Skia itself, or the app would crash
// at launch on device — CanvasKit ships the same SkSL compiler
try {
  const require_ = (await import('node:module')).createRequire(import.meta.url)
  const CanvasKitInit = require_('canvaskit-wasm/bin/canvaskit.js')
  const CK = await CanvasKitInit({
    locateFile: (f) => require_.resolve(`canvaskit-wasm/bin/${f}`),
  })
  check('VHS_SKSL compiles in Skia', CK.RuntimeEffect.Make(VHS_SKSL) != null)
} catch {
  console.log('SKIP VHS_SKSL Skia compile (canvaskit unavailable)')
}

rmSync(work, { recursive: true, force: true })
console.log(failures === 0 ? '\nALL PASS' : `\n${failures} FAILURES`)
process.exit(failures ? 1 : 0)
