/**
 * Haptics — the app's single seam over expo-haptics. Every call is a
 * fire-and-forget no-op on failure (simulator, web, silenced hardware),
 * so screens can sprinkle ticks without try/catch noise.
 *
 * Vocabulary, matched to how the app uses touch:
 *   light      — slider detents, card taps, filmstrip swipes
 *   medium     — develop kicked off, preset applied, favorite toggled on
 *   heavy      — export saved, purchase completed
 *   selection  — the tick of a segmented control / style chip changing
 *   success    — develop finished, saved to library
 *   warning    — out of credits, gated feature tapped
 */

import * as Haptics from 'expo-haptics'

const safe = (run: () => Promise<unknown>): void => {
  try {
    run().catch(() => {})
  } catch {
    /* haptics unavailable — stay silent */
  }
}

export const haptics = {
  light: (): void => safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)),
  medium: (): void => safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium)),
  heavy: (): void => safe(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy)),
  selection: (): void => safe(() => Haptics.selectionAsync()),
  success: (): void =>
    safe(() => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)),
  warning: (): void =>
    safe(() => Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning)),
}
