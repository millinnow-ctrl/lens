import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { springPress } from '../../lib/motion'

const MotionLink = motion(Link)

/* prints never land perfectly square on the bench — a quiet alternating
   skew per position keeps the grid from reading machine-laid */
const LEAN = [-1.4, 1.1, 0.9, -1.2, 1.3, -0.8]

interface Props {
  to: string
  image: string
  label: string
  sublabel?: string
  /** apply a CSS filter fallback while an engine render is pending */
  filter?: string
  /** small neutral chip in the top-right, e.g. Example */
  chip?: string
  /** position in the grid — drives the print's lean */
  index?: number
}

/** a developed frame as a physical object: a labelled print on warm stock,
 *  laid slightly askew — not another rounded rectangle */
export default function RecentProjectCard({
  to,
  image,
  label,
  sublabel,
  filter,
  chip,
  index = 0,
}: Props) {
  const lean = LEAN[index % LEAN.length]
  return (
    <MotionLink
      to={to}
      initial={false}
      style={{ rotate: lean }}
      whileHover={{ y: -4, rotate: 0 }}
      whileTap={{ scale: 0.965 }}
      transition={springPress}
      className="relative block bg-[#fdfaf2] p-1.5 pb-2 rounded-[7px] shadow-[var(--shadow-e2)]"
    >
      <div className="relative overflow-hidden rounded-[4px] aspect-[4/4.1] bg-vf">
        <img
          src={image}
          alt=""
          loading="lazy"
          draggable={false}
          className="absolute inset-0 w-full h-full object-cover"
          style={filter ? { filter } : undefined}
        />
        {chip && (
          <span className="absolute top-2 right-2 rounded-full bg-black/45 backdrop-blur-sm text-white/90 text-[9.5px] font-semibold tracking-[0.04em] uppercase px-2 py-0.5">
            {chip}
          </span>
        )}
      </div>
      {/* the label lives in the print's bottom margin, like a written caption */}
      <div className="flex items-baseline justify-between gap-2 pt-1.5 px-0.5">
        <p className="type-display text-[14px] leading-tight text-ink truncate min-w-0 whitespace-nowrap">{label}</p>
        {sublabel && (
          <p className="shrink-0 font-mono text-[8.5px] tracking-[0.08em] uppercase text-fog truncate">
            {sublabel}
          </p>
        )}
      </div>
    </MotionLink>
  )
}
