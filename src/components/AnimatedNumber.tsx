import { useEffect } from 'react'
import { motion, useSpring, useTransform } from 'framer-motion'
import { prefersReducedMotion } from '../lib/motion'

interface Props {
  value: number
  /** format the (rounded) spring value into display text — e.g. add "$" */
  format?: (n: number) => string
  /** start the count from this value on first mount (default 0 → counts up) */
  from?: number
  className?: string
}

/**
 * A number that springs to its value — counts up on first paint and eases
 * between values on change. The small, expensive-feeling detail premium
 * apps sweat and templates never bother with. Honours reduced-motion.
 */
export default function AnimatedNumber({ value, format, from = 0, className }: Props) {
  const reduced = prefersReducedMotion()
  const spring = useSpring(reduced ? value : from, { stiffness: 90, damping: 20, mass: 0.9 })
  const text = useTransform(spring, (v) => (format ? format(v) : String(Math.round(v))))

  useEffect(() => {
    spring.set(value)
  }, [value, spring])

  if (reduced) return <span className={className}>{format ? format(value) : Math.round(value)}</span>
  return (
    <motion.span className={className} style={{ fontVariantNumeric: 'tabular-nums' }}>
      {text}
    </motion.span>
  )
}
