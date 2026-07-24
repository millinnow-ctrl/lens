// Account — quiet housekeeping, and the only doorway to the paywall while
// Store.everythingFreeForNow is true ("Preview the supporter offer").
//
// Never-list #3 (docs/PROFIT_ENGINE.md): once the gate flips, a Plus member
// sees a thank-you line here instead of any offer row — a paying user is
// never shown an upsell again.

import SwiftUI

struct AccountView: View {
  @ObservedObject private var store = Store.shared
  @Environment(\.dismiss) private var dismiss

  private var appVersion: String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return v ?? "1.0.0"
  }

  /// App Review safety: the supporter-offer preview only appears when real
  /// App Store products loaded (so a reviewer never lands on placeholder
  /// prices) — except in DEBUG builds, where design review stays possible
  /// without any App Store Connect setup.
  private var showsOfferPreview: Bool {
    #if DEBUG
      return true
    #else
      return !store.products.isEmpty
    #endif
  }

  var body: some View {
    NavigationStack {
      List {
        membershipSection
        privacySection
        aboutSection
      }
      .scrollContentBackground(.hidden)
      .background(Theme.paper)
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // .navigationBarTrailing (not .topBarTrailing) — iOS 16 floor.
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
            .font(.callout.weight(.semibold))   // 16pt at the default size
            .foregroundStyle(Theme.accent)
        }
      }
      // Load products here (not only on the paywall) so the offer-preview
      // row can appear in release builds once App Store products exist.
      .task { await store.start() }
    }
  }

  private var membershipSection: some View {
    Section {
      HStack {
        Text("Membership")
          .foregroundStyle(Theme.ink)
        Spacer()
        Text(membershipLabel)
          .scaledFont(size: 14, weight: .semibold, relativeTo: .footnote)
          .foregroundStyle(Theme.inkSoft)
      }
      if Store.allGatesOpen {
        // Design-review doorway: the paywall is otherwise unreachable
        // while every gate is open. Hidden in release builds until real
        // products load, so App Review never sees placeholder prices.
        if showsOfferPreview {
          NavigationLink {
            PaywallView()
          } label: {
            Label("Preview the supporter offer", systemImage: "heart")
              .foregroundStyle(Theme.accent)
          }
        }
      } else if store.isPlus {
        Text("You keep the darkroom open. Thank you.")
          .scaledFont(size: 14, relativeTo: .footnote)
          .foregroundStyle(Theme.inkSoft)
      } else {
        NavigationLink {
          PaywallView()
        } label: {
          Label("Get the twelve signature cameras", systemImage: "camera")
            .foregroundStyle(Theme.accent)
        }
      }
    } footer: {
      if Store.allGatesOpen {
        Text("Everything's free while LensMood is being built. Pricing is decided at the end.")
      }
    }
    .listRowBackground(Theme.surface)
  }

  private var privacySection: some View {
    Section {
      Label {
        Text("Photos develop on your phone. Nothing uploads. Ever.")
          .scaledFont(size: 14, relativeTo: .footnote)
          .foregroundStyle(Theme.inkSoft)
      } icon: {
        Image(systemName: "lock")
          .foregroundStyle(Theme.accent)
      }
    }
    .listRowBackground(Theme.surface)
  }

  private var aboutSection: some View {
    Section {
      HStack {
        Text("Version")
          .foregroundStyle(Theme.ink)
        Spacer()
        Text(appVersion)
          .scaledFont(size: 14, design: .monospaced, relativeTo: .footnote)
          .foregroundStyle(Theme.fog)
      }
    }
    .listRowBackground(Theme.surface)
  }

  private var membershipLabel: String {
    if Store.allGatesOpen { return "Everything free for now" }
    return store.isPlus ? "Plus" : "Free"
  }
}

#Preview {
  AccountView()
}
