// SavedTick — a non-blocking save confirmation.
//
// A successful save used to raise an alert that demanded an OK tap — an
// interruption for good news. HIG: avoid using an alert to deliver
// information that doesn't require action. The tick is a transient capsule
// that names what happened, announces itself to VoiceOver, and leaves on its
// own. Error alerts everywhere remain alerts — errors require action.

import SwiftUI
import UIKit

struct SavedTickModifier: ViewModifier {
  /// a monotonically increasing save counter — the caller bumps it on every
  /// save. Keying on the count (not a Bool) means a second save while the tick
  /// is still up restarts the clock: `true` set over `true` is no change, so
  /// the second confirmation used to ride — and be cut short by — the first
  /// save's timer.
  let trigger: Int
  let text: String
  /// the trigger value currently on screen; nil = hidden. The modifier owns
  /// its own dismissal, so the caller only ever counts up.
  @State private var shown: Int?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if shown != nil {
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
              .foregroundStyle(Theme.accent)
            Text(text)
              .font(.subheadline.weight(.semibold))   // 15pt at the default size
              .foregroundStyle(Theme.ink)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .padding(.horizontal, 18)
          .frame(minHeight: 44)
          .background(Theme.surface, in: Capsule())
          .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
          .oceanCardShadow(deep: true)
          .padding(.horizontal, Theme.pagePadding)
          .padding(.bottom, 12)
          .transition(reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity))
          // task(id: shown) so each save (a new count) restarts the clock
          // instead of racing the old dismissal
          .task(id: shown) {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
              shown = nil
            }
          }
          .allowsHitTesting(false)
        }
      }
      .onChange(of: trigger) { newValue in
        guard newValue > 0 else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
          shown = newValue
        }
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
        value: shown
      )
  }
}

extension View {
  /// A transient, self-dismissing save confirmation — success without an OK
  /// button. Drive it with a counter bumped on each save (`saveTick += 1`), so
  /// repeated saves each get their full moment on screen.
  func savedTick(trigger: Int, text: String = "Saved to Photos") -> some View {
    modifier(SavedTickModifier(trigger: trigger, text: text))
  }
}
