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
  @Binding var isPresented: Bool
  let text: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if isPresented {
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
          .onAppear {
            UIAccessibility.post(notification: .announcement, argument: text)
          }
          // task(id:) so a save landing while the tick is up restarts the
          // clock instead of racing the old dismissal
          .task(id: isPresented) {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
              isPresented = false
            }
          }
          .allowsHitTesting(false)
        }
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
        value: isPresented
      )
  }
}

extension View {
  /// A transient, self-dismissing save confirmation — success without an
  /// OK button.
  func savedTick(isPresented: Binding<Bool>, text: String = "Saved to Photos") -> some View {
    modifier(SavedTickModifier(isPresented: isPresented, text: text))
  }
}
