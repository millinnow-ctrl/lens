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
      if Store.everythingFreeForNow {
        // Design-review doorway: the paywall is otherwise unreachable
        // while every gate is open.
        NavigationLink {
          PaywallView()
        } label: {
          Label("Preview the supporter offer", systemImage: "heart")
            .foregroundStyle(Theme.accent)
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
      if Store.everythingFreeForNow {
        Text("Everything in LensMood is free while it's being built. Pricing gets decided at the end — nothing is locked today.")
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
    if Store.everythingFreeForNow { return "Everything free for now" }
    return store.isPlus ? "Plus" : "Free"
  }
}

#Preview {
  AccountView()
}
