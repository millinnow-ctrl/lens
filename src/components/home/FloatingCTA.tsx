import { IconCamera } from '../icons'
import { haptic } from '../../lib/native'

interface Props {
  onClick: () => void
  /** 'fixed' floats over the viewport (real mobile); 'embedded' floats inside the demo frame */
  variant?: 'fixed' | 'embedded'
}

export default function FloatingCTA({ onClick, variant = 'fixed' }: Props) {
  const pos =
    variant === 'fixed'
      ? 'fixed bottom-[calc(env(safe-area-inset-bottom)+84px)] left-1/2 -translate-x-1/2 z-40'
      : 'absolute bottom-[92px] left-1/2 -translate-x-1/2 z-40'

  return (
    <button
      onClick={() => {
        haptic('medium')
        onClick()
      }}
      className={`${pos} hm-cta hm-press inline-flex items-center gap-2 h-12 pl-4 pr-5 rounded-full bg-ink text-white text-[14px] font-semibold`}
    >
      <IconCamera size={16} />
      Start from a photo
    </button>
  )
}
