const GENERIC = [
  'POV: your photo was shot on a $7,000 camera',
  'this used to be a normal photo',
  'my camera roll entered its cinematic era',
  'no new camera. just a new mood.',
]

const BY_STYLE: Record<string, string[]> = {
  disposable: [
    'from a night that never happened',
    'the flash did what the flash does best',
  ],
  'iphone-flash': [
    'flash on. standards up.',
    '2:47am. the flash showed up.',
  ],
  'camcorder-90s': [
    'home video from a memory I just invented',
    '● REC — taping over dad’s golf tournament for this',
  ],
  'leica-street': [
    'shot on Leica* (*emotionally)',
    'the streets said cinema today',
  ],
  'gq-editorial': [
    'accidentally became a magazine cover',
    'GQ called. I let it ring.',
  ],
  'a24-still': [
    'I turned my photo into an A24 movie still',
    'this frame has a Letterboxd review now',
  ],
  'film-noir': [
    'in this town, everyone’s got a secret',
    'color left. drama stayed.',
  ],
  'y2k-digicam': [
    'recovered from a 2003 memory card 💿',
    'the digicam flash never lied',
  ],
  polaroid: [
    'shook it for dramatic effect',
    'instant film, instant feelings',
  ],
}

export function randomCaption(styleId?: string): string {
  const pool = [...GENERIC, ...(styleId ? BY_STYLE[styleId] ?? [] : [])]
  return pool[Math.floor(Math.random() * pool.length)]
}

export const HASHTAGS = '#LensMood #shotonlensmood #cameramood #cinematic'
