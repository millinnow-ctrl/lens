/**
 * Print Lab scene presets. The camera pose is a SHARED bird's-eye template —
 * the phone held straight down over the surface — so the Polaroid keeps its
 * true proportions and the uploaded photo drops into the same window every
 * time. Only the plate (and how its material takes the contact shadow /
 * reflected warmth) changes between scenes.
 */

export interface ScenePreset {
  id: 'wood' | 'linen' | 'marble' | 'concrete'
  label: string
  /** require() id of the plate JPEG (top-down flat surface) */
  plate: number
  /** contact-shadow strength for this material (hard = darker/tighter) */
  shadowOpacity: number
  shadowRadius: number
  /** reflected warmth the surface throws back onto the print (0..1) */
  warmth: number
}

/**
 * The ONE camera pose, shared by every scene: straight down (bird's-eye), the
 * print lying flat with a small casual roll. No tilt — overhead keeps the
 * print's real proportions.
 */
export const SCENE_POSE = {
  /** print centre, 0..1 of stage */
  cx: 0.5,
  cy: 0.52,
  /** print width as a fraction of stage width */
  scale: 0.66,
  /** small casual in-plane rotation (deg) */
  rollDeg: -4,
  /** contact-shadow drop, in stage px */
  shadowDrop: 20,
} as const

export const SCENES: ScenePreset[] = [
  {
    id: 'wood',
    label: 'Warm oak',
    plate: require('../../assets/scenes/wood.jpg'),
    shadowOpacity: 0.3,
    shadowRadius: 16,
    warmth: 0.06,
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
    label: 'Marble',
    plate: require('../../assets/scenes/marble.jpg'),
    shadowOpacity: 0.26,
    shadowRadius: 14,
    warmth: 0.0,
  },
  {
    id: 'concrete',
    label: 'Plaster',
    plate: require('../../assets/scenes/concrete.jpg'),
    shadowOpacity: 0.24,
    shadowRadius: 16,
    warmth: 0.02,
  },
]
