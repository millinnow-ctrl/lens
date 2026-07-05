import { useEffect } from 'react'

let openCount = 0

/**
 * Marks the document while any bottom sheet is presented so fixed chrome
 * (the dock) can bow out of the way — sheets and tab bars never collide.
 * Ref-counted: overlapping sheets keep the flag up until the last closes.
 */
export function useSheetOpen(open: boolean): void {
  useEffect(() => {
    if (!open) return
    openCount++
    document.body.dataset.sheetOpen = 'true'
    return () => {
      openCount--
      if (openCount <= 0) {
        openCount = 0
        delete document.body.dataset.sheetOpen
      }
    }
  }, [open])
}
