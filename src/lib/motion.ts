import type { Transition, Variants } from 'framer-motion'

/**
 * Shared motion vocabulary for LensMood.
 *
 * The house voice is restrained: short travel, soft springs, no overshoot on
 * large surfaces. Everything here collapses to opacity-only / instant under
 * `prefers-reduced-motion` so the app stays honest for motion-sensitive users.
 */

/** live read of the reduced-motion preference (SSR-safe) */
export const prefersReducedMotion = (): boolean =>
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true

/* ------------------------------------------------------------------ springs */

/** general-purpose soft spring — settles quickly, no visible bounce */
export const springSoft: Transition = {
  type: 'spring',
  stiffness: 320,
  damping: 34,
  mass: 0.9,
}

/** slightly livelier spring for small press/tap feedback (chips, cards) */
export const springPress: Transition = {
  type: 'spring',
  stiffness: 520,
  damping: 30,
  mass: 0.7,
}

/** a calm eased tween for opacity/position on big surfaces */
export const easeOut: Transition = {
  duration: 0.28,
  ease: [0.22, 0.61, 0.36, 1],
}

/* -------------------------------------------------------------- page routes */

/**
 * Route cross-fade: content rises 8px and fades in on enter, sinks slightly
 * and fades on exit. Kept fast (~0.28s) and layout-safe (transform + opacity
 * only). Falls back to a pure opacity cut when reduced motion is on.
 */
export const pageTransition = (reduced = prefersReducedMotion()): Variants =>
  reduced
    ? {
        initial: { opacity: 0 },
        animate: { opacity: 1, transition: { duration: 0.12 } },
        exit: { opacity: 0, transition: { duration: 0.08 } },
      }
    : {
        initial: { opacity: 0, y: 8 },
        animate: { opacity: 1, y: 0, transition: easeOut },
        exit: {
          opacity: 0,
          y: -6,
          transition: { duration: 0.18, ease: [0.4, 0, 1, 1] },
        },
      }

/* ------------------------------------------------------ staggered reveals */

/**
 * Container that reveals its children in a gentle stagger. Use with
 * `sectionChild` on each `motion.section`. The stagger is a no-op under
 * reduced motion (children simply appear).
 */
export const sectionStagger = (reduced = prefersReducedMotion()): Variants => ({
  initial: {},
  animate: {
    transition: reduced
      ? { staggerChildren: 0 }
      : { staggerChildren: 0.07, delayChildren: 0.04 },
  },
})

/** individual revealed child — subtle fade + rise, or opacity-only when reduced */
export const sectionChild = (reduced = prefersReducedMotion()): Variants =>
  reduced
    ? {
        initial: { opacity: 0 },
        animate: { opacity: 1, transition: { duration: 0.18 } },
      }
    : {
        initial: { opacity: 0, y: 12 },
        animate: { opacity: 1, y: 0, transition: springSoft },
      }

/* ------------------------------------------------------------- deck entrance */

/**
 * MoodSphere card entrance — cards settle up into place on mount with a small
 * per-card stagger. Returns instant/opacity variants under reduced motion.
 * `index` drives the delay; kept short so the whole deck lands < ~0.5s.
 */
export const deckCard = (index: number, reduced = prefersReducedMotion()): Variants =>
  reduced
    ? {
        initial: { opacity: 0 },
        animate: { opacity: 1, transition: { duration: 0.18 } },
      }
    : {
        initial: { opacity: 0, y: 18, scale: 0.94 },
        animate: {
          opacity: 1,
          y: 0,
          scale: 1,
          transition: {
            ...springSoft,
            delay: Math.min(index, 8) * 0.035,
          },
        },
      }
