import { useState, type ReactNode } from 'react'

/**
 * Desktop demo shell: renders the mobile app inside a device frame with a
 * mock status bar, so the home screen presents like a real app screenshot.
 * On actual phones the app renders full-bleed and this component is unused.
 */
export default function PhoneFrame({
  children,
  chrome,
}: {
  children: ReactNode
  /** overlays that must float inside the frame (dock, CTA, sheets) */
  chrome?: (container: HTMLElement | null) => ReactNode
}) {
  const [inner, setInner] = useState<HTMLElement | null>(null)

  return (
    <div className="flex justify-center items-start py-12 px-6">
      <div className="w-[400px] h-[844px] rounded-[54px] bg-[#0c0c0b] p-[11px] shadow-[0_50px_140px_-40px_rgb(12_12_11/0.55)] relative shrink-0">
        {/* side buttons */}
        <div className="absolute -left-[2px] top-[170px] w-[3px] h-16 rounded-l bg-[#232322]" aria-hidden />
        <div className="absolute -right-[2px] top-[210px] w-[3px] h-24 rounded-r bg-[#232322]" aria-hidden />
        <div ref={setInner} className="relative w-full h-full rounded-[44px] overflow-hidden hm-canvas flex flex-col">
          {/* mock status bar */}
          <div className="shrink-0 h-12 px-8 pt-2 flex items-center justify-between pointer-events-none select-none">
            <span className="text-[14px] font-semibold tracking-tight tabular-nums">9:41</span>
            <span className="flex items-center gap-1.5" aria-hidden>
              <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor">
                <rect x="0" y="7" width="3" height="4" rx="0.8" />
                <rect x="4.5" y="5" width="3" height="6" rx="0.8" />
                <rect x="9" y="2.5" width="3" height="8.5" rx="0.8" />
                <rect x="13.5" y="0" width="3" height="11" rx="0.8" />
              </svg>
              <svg width="16" height="11" viewBox="0 0 16 11" fill="currentColor">
                <path d="M8 9.2a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8ZM8 5.6c1.7 0 3.2.7 4.3 1.8l-1.4 1.4A4.1 4.1 0 0 0 8 7.6c-1.1 0-2.1.4-2.9 1.2L3.7 7.4A6.1 6.1 0 0 1 8 5.6Zm0-3.7c2.7 0 5.2 1.1 7 2.9l-1.4 1.4A8 8 0 0 0 8 3.9a8 8 0 0 0-5.6 2.3L1 4.8a10 10 0 0 1 7-2.9Z" transform="translate(0 -1.9)" />
              </svg>
              <svg width="25" height="12" viewBox="0 0 25 12" fill="none" stroke="currentColor">
                <rect x="0.5" y="0.5" width="21" height="11" rx="3" strokeOpacity="0.4" />
                <rect x="2" y="2" width="16" height="8" rx="1.5" fill="currentColor" stroke="none" />
                <path d="M23.5 4v4a2 2 0 0 0 0-4Z" fill="currentColor" stroke="none" fillOpacity="0.4" />
              </svg>
            </span>
          </div>
          <div className="flex-1 overflow-y-auto no-scrollbar overscroll-contain">{children}</div>
          {chrome?.(inner)}
        </div>
      </div>
    </div>
  )
}
