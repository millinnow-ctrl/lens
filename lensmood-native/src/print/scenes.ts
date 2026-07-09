/**
 * Print Lab scene presets — each plate is a top-down flat-lay surface with an
 * art-directed landing spot for the print. Positions are normalized to the
 * stage; rotation/scale/shadow are tuned per material (hard surfaces cast
 * tighter, darker contact shadows; diffuse ones wider and lighter).
 */

export interface ScenePreset {
  id: 'wood' | 'sand' | 'linen' | 'marble' | 'grass'
  label: string
  /** require() id of the plate JPEG (1200×1600 portrait) */
  plate: number
  /** print CENTER, 0..1 of stage width/height */
  x: number
  y: number
  /** print width as a fraction of stage width */
  scale: number
  /** flat-lay pose */
  rotateZ: number
  /** subtle foreshorten (deg, with perspective) */
  rotateX?: number
  shadow: { opacity: number; radius: number; offset: { width: number; height: number } }
}

export const SCENES: ScenePreset[] = [
  {
    id: 'wood',
    label: 'Wooden chair',
    plate: require('../../assets/scenes/wood.jpg'),
    x: 0.5,
    y: 0.52,
    scale: 0.62,
    rotateZ: -4,
    rotateX: 2.5,
    shadow: { opacity: 0.34, radius: 14, offset: { width: 0, height: 10 } },
  },
  {
    id: 'sand',
    label: 'Beach sand',
    plate: require('../../assets/scenes/sand.jpg'),
    x: 0.52,
    y: 0.5,
    scale: 0.6,
    rotateZ: 7,
    rotateX: 1.5,
    shadow: { opacity: 0.22, radius: 20, offset: { width: 0, height: 8 } },
  },
  {
    id: 'linen',
    label: 'Linen sheet',
    plate: require('../../assets/scenes/linen.jpg'),
    x: 0.48,
    y: 0.53,
    scale: 0.64,
    rotateZ: -9,
    rotateX: 2,
    shadow: { opacity: 0.22, radius: 16, offset: { width: 0, height: 7 } },
  },
  {
    id: 'marble',
    label: 'Café marble',
    plate: require('../../assets/scenes/marble.jpg'),
    x: 0.55,
    y: 0.48,
    scale: 0.58,
    rotateZ: 3,
    rotateX: 3,
    shadow: { opacity: 0.38, radius: 10, offset: { width: 0, height: 6 } },
  },
  {
    id: 'grass',
    label: 'Grass',
    plate: require('../../assets/scenes/grass.jpg'),
    x: 0.5,
    y: 0.5,
    scale: 0.62,
    rotateZ: -6,
    rotateX: 1,
    shadow: { opacity: 0.18, radius: 22, offset: { width: 0, height: 6 } },
  },
]
