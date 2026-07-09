/**
 * Print Lab scene presets. The camera pose is a SHARED template — one iPhone
 * angle, focal length and roll for every surface — so the Polaroid feels like
 * the same physical print restaged, not a fresh mock-up each time. Only the
 * plate (and how its material scatters the contact shadow / reflected warmth)
 * changes between scenes.
 */

export interface ScenePreset {
  id: 'wood' | 'sand' | 'linen' | 'marble' | 'grass'
  label: string
  /** require() id of the plate JPEG (1200×1600 portrait) */
  plate: number
  /** contact-shadow strength for this material (hard = darker/tighter) */
  shadowOpacity: number
  shadowRadius: number
  /** reflected warmth the surface throws back onto the print (0..1) */
  warmth: number
}

/**
 * The ONE camera pose, shared by every scene. `tiltDeg` is the downward camera
 * angle (a phone held above the table), `rollDeg` the casual in-plane rotation.
 * These map to a processTransform3d rotateX/rotateZ in compose.ts.
 */
export const SCENE_POSE = {
  /** print centre, 0..1 of stage */
  cx: 0.5,
  cy: 0.54,
  /** print width as a fraction of stage width (near edge) */
  scale: 0.66,
  tiltDeg: 50,
  rollDeg: -8,
  /** gentler tilt for the live develop animation (kept legible on screen);
   *  the exported composite uses the full tiltDeg for the "photo of the print" */
  previewTiltDeg: 16,
  /** contact-shadow drop, in stage px */
  shadowDrop: 26,
} as const

export const SCENES: ScenePreset[] = [
  {
    id: 'wood',
    label: 'Warm oak',
    plate: require('../../assets/scenes/wood.jpg'),
    shadowOpacity: 0.34,
    shadowRadius: 16,
    warmth: 0.06,
  },
  {
    id: 'sand',
    label: 'Beach sand',
    plate: require('../../assets/scenes/sand.jpg'),
    shadowOpacity: 0.22,
    shadowRadius: 22,
    warmth: 0.05,
  },
  {
    id: 'linen',
    label: 'Linen',
    plate: require('../../assets/scenes/linen.jpg'),
    shadowOpacity: 0.2,
    shadowRadius: 18,
    warmth: 0.02,
  },
  {
    id: 'marble',
    label: 'Café marble',
    plate: require('../../assets/scenes/marble.jpg'),
    shadowOpacity: 0.3,
    shadowRadius: 12,
    warmth: 0.0,
  },
  {
    id: 'grass',
    label: 'Summer grass',
    plate: require('../../assets/scenes/grass.jpg'),
    shadowOpacity: 0.24,
    shadowRadius: 24,
    warmth: 0.01,
  },
]
