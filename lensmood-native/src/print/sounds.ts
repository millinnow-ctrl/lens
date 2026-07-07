/**
 * Print Lab sounds — the same safe-seam philosophy as store/haptics.ts:
 * audio is flavor, so every call is wrapped and failure is silence, never
 * a crash. Camera sounds fire even with the mute switch on (that's what a
 * real instant camera does), hence playsInSilentMode.
 */

import { useEffect } from 'react'
import { useAudioPlayer, setAudioModeAsync, type AudioPlayer } from 'expo-audio'

const SHUTTER = require('../../assets/sounds/shutter-click.wav')
const MOTOR = require('../../assets/sounds/print-motor.wav')

/* players do not auto-rewind after finishing — seek first, every time */
const replay = (p: AudioPlayer) => {
  try {
    void p.seekTo(0)
    p.play()
  } catch {
    /* audio unavailable — stay silent */
  }
}

export function usePrintSounds() {
  const shutter = useAudioPlayer(SHUTTER)
  const motor = useAudioPlayer(MOTOR)
  useEffect(() => {
    setAudioModeAsync({ playsInSilentMode: true, interruptionMode: 'mixWithOthers' }).catch(
      () => {},
    )
  }, [])
  return {
    shutter: () => replay(shutter),
    motor: () => replay(motor),
  }
}
