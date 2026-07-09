/**
 * Perspective compositing for the Print Room.
 *
 * The Polaroid is treated as a physical card photographed by a phone held at a
 * fixed downward angle — a reusable "3D template". `projectCardQuad` builds the
 * same destination quad every time (one camera pose), so only the printed image
 * inside the frame changes between surfaces. `warpImage` maps the flat card into
 * that quad with true projective foreshortening (grid-subdivided affine
 * triangles), which is what sells "a real photo of a real print" rather than a
 * flat digital overlay.
 */

export type Pt = [number, number]

/** invert a 3×3 (column-major-agnostic, row arrays) */
function invert3(m: number[][]): number[][] {
  const [a, b, c] = m[0]
  const [d, e, f] = m[1]
  const [g, h, i] = m[2]
  const A = e * i - f * h
  const B = -(d * i - f * g)
  const C = d * h - e * g
  const det = a * A + b * B + c * C
  const id = 1 / det
  return [
    [A * id, (c * h - b * i) * id, (b * f - c * e) * id],
    [B * id, (a * i - c * g) * id, (c * d - a * f) * id],
    [C * id, (b * g - a * h) * id, (a * e - b * d) * id],
  ]
}

/** solve the affine (a,b,c,d,e,f) mapping three src points → three dst points */
function affineFromTriangles(s: Pt[], d: Pt[]) {
  const S = [
    [s[0][0], s[0][1], 1],
    [s[1][0], s[1][1], 1],
    [s[2][0], s[2][1], 1],
  ]
  const Si = invert3(S)
  const dx = [d[0][0], d[1][0], d[2][0]]
  const dy = [d[0][1], d[1][1], d[2][1]]
  const a = Si[0][0] * dx[0] + Si[0][1] * dx[1] + Si[0][2] * dx[2]
  const c = Si[1][0] * dx[0] + Si[1][1] * dx[1] + Si[1][2] * dx[2]
  const e = Si[2][0] * dx[0] + Si[2][1] * dx[1] + Si[2][2] * dx[2]
  const b = Si[0][0] * dy[0] + Si[0][1] * dy[1] + Si[0][2] * dy[2]
  const dd = Si[1][0] * dy[0] + Si[1][1] * dy[1] + Si[1][2] * dy[2]
  const ff = Si[2][0] * dy[0] + Si[2][1] * dy[1] + Si[2][2] * dy[2]
  return { a, b, c, dd, e, ff }
}

/** homography mapping the unit square (0..1)² → four dst corners TL,TR,BR,BL */
function homographyUnitToQuad(q: Pt[]): (u: number, v: number) => Pt {
  // solve the projective map with corners (0,0)(1,0)(1,1)(0,1)
  const [tl, tr, br, bl] = q
  // build 8×8 system for h = [a b c d e f g h]
  const src: Pt[] = [
    [0, 0],
    [1, 0],
    [1, 1],
    [0, 1],
  ]
  const dst = [tl, tr, br, bl]
  const A: number[][] = []
  const rhs: number[] = []
  for (let k = 0; k < 4; k++) {
    const [x, y] = src[k]
    const [X, Y] = dst[k]
    A.push([x, y, 1, 0, 0, 0, -x * X, -y * X])
    rhs.push(X)
    A.push([0, 0, 0, x, y, 1, -x * Y, -y * Y])
    rhs.push(Y)
  }
  const h = solve8(A, rhs)
  const [a, b, c, d, e, f, g, hh] = h
  return (u, v) => {
    const denom = g * u + hh * v + 1
    return [(a * u + b * v + c) / denom, (d * u + e * v + f) / denom]
  }
}

/** Gaussian elimination for an 8×8 system */
function solve8(A: number[][], rhs: number[]): number[] {
  const n = 8
  const M = A.map((row, i) => [...row, rhs[i]])
  for (let col = 0; col < n; col++) {
    let piv = col
    for (let r = col + 1; r < n; r++) if (Math.abs(M[r][col]) > Math.abs(M[piv][col])) piv = r
    ;[M[col], M[piv]] = [M[piv], M[col]]
    const pv = M[col][col]
    for (let c = col; c <= n; c++) M[col][c] /= pv
    for (let r = 0; r < n; r++) {
      if (r === col) continue
      const factor = M[r][col]
      for (let c = col; c <= n; c++) M[r][c] -= factor * M[col][c]
    }
  }
  return M.map((row) => row[n])
}

/**
 * Warp `img` into the destination quad (TL,TR,BR,BL) with projective
 * foreshortening, using an N×N grid of affine triangles.
 */
export function warpImage(
  ctx: CanvasRenderingContext2D,
  img: CanvasImageSource,
  quad: Pt[],
  grid = 18,
) {
  const iw = (img as HTMLCanvasElement).width
  const ih = (img as HTMLCanvasElement).height
  const map = homographyUnitToQuad(quad)
  // precompute grid of dest points + matching src pixel points
  const dPts: Pt[][] = []
  const sPts: Pt[][] = []
  for (let r = 0; r <= grid; r++) {
    dPts[r] = []
    sPts[r] = []
    for (let c = 0; c <= grid; c++) {
      const u = c / grid
      const v = r / grid
      dPts[r][c] = map(u, v)
      sPts[r][c] = [u * iw, v * ih]
    }
  }
  for (let r = 0; r < grid; r++) {
    for (let c = 0; c < grid; c++) {
      const s00 = sPts[r][c]
      const s10 = sPts[r][c + 1]
      const s11 = sPts[r + 1][c + 1]
      const s01 = sPts[r + 1][c]
      const d00 = dPts[r][c]
      const d10 = dPts[r][c + 1]
      const d11 = dPts[r + 1][c + 1]
      const d01 = dPts[r + 1][c]
      drawTri(ctx, img, [s00, s10, s11], [d00, d10, d11])
      drawTri(ctx, img, [s00, s11, s01], [d00, d11, d01])
    }
  }
}

function drawTri(ctx: CanvasRenderingContext2D, img: CanvasImageSource, s: Pt[], d: Pt[]) {
  const { a, b, c, dd, e, ff } = affineFromTriangles(s, d)
  ctx.save()
  ctx.beginPath()
  // inflate the clip triangle so adjacent cells overlap by a couple of px —
  // otherwise the antialiased clip edges leave hairline seams across the warp
  const cx = (d[0][0] + d[1][0] + d[2][0]) / 3
  const cy = (d[0][1] + d[1][1] + d[2][1]) / 3
  const grow = 1.8
  const p = d.map(([x, y]) => {
    const dx = x - cx
    const dy = y - cy
    const len = Math.hypot(dx, dy) || 1
    return [x + (dx / len) * grow, y + (dy / len) * grow] as Pt
  })
  ctx.moveTo(p[0][0], p[0][1])
  ctx.lineTo(p[1][0], p[1][1])
  ctx.lineTo(p[2][0], p[2][1])
  ctx.closePath()
  ctx.clip()
  ctx.transform(a, b, c, dd, e, ff)
  ctx.drawImage(img, 0, 0)
  ctx.restore()
}

/**
 * The reusable camera pose. Projects a card of aspect `cardW:cardH` (in card
 * units) sitting flat on a surface, viewed by a phone held above at a fixed
 * downward tilt and slight roll. Returns the four dst corners TL,TR,BR,BL in
 * composite pixels. Identical geometry for every surface → the "3D template".
 */
export function projectCardQuad(opts: {
  W: number
  H: number
  cardAspect: number // cardW / cardH
  cx: number // 0..1 center of the card on the composite
  cy: number
  size: number // fraction of W the card's near edge spans
  tiltDeg: number // downward camera tilt (0 = overhead, 90 = flat-on)
  rollDeg: number // in-plane rotation
}): Pt[] {
  const { W, H, cardAspect, cx, cy, size, tiltDeg, rollDeg } = opts
  const hw = 0.5
  const hh = 0.5 / cardAspect
  // card-local corners TL,TR,BR,BL (y down)
  const local: Pt[] = [
    [-hw, -hh],
    [hw, -hh],
    [hw, hh],
    [-hw, hh],
  ]
  const t = (tiltDeg * Math.PI) / 180
  const roll = (rollDeg * Math.PI) / 180
  const cosR = Math.cos(roll)
  const sinR = Math.sin(roll)
  const camDist = 3.2
  const proj = local.map(([x, y]) => {
    // in-plane roll
    const rx = x * cosR - y * sinR
    const ry = x * sinR + y * cosR
    // tilt the plane about its horizontal axis: far edge (−ry) recedes in depth
    const depth = ry * Math.sin(t) // +y (bottom, near) gains depth toward camera
    const planeY = ry * Math.cos(t)
    const z = camDist - depth
    const f = camDist // focal ~ camDist keeps near edge ~unit
    return [ (rx * f) / z, (planeY * f) / z ] as Pt
  })
  // normalise so the widest span maps to `size * W`
  let maxSpan = 0
  for (const [px] of proj) maxSpan = Math.max(maxSpan, Math.abs(px))
  const scale = (size * W) / (maxSpan * 2)
  return proj.map(([px, py]) => [cx * W + px * scale, cy * H + py * scale] as Pt)
}
