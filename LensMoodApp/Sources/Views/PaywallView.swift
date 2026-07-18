// Paywall — the supporter offer, built calm on purpose.
//
// Design: docs/PROFIT_ENGINE.md §3. Two offers side by side, lifetime
// highlighted as the one-time purchase, restore always present. No
// countdowns, no fake discounts, no confirm-shaming, no pre-selected
// anything. While Store.everythingFreeForNow is true this screen is
// unreachable in normal flow — AccountView links it as a design preview.
//
// With no App Store Connect products yet, StoreKit loads nothing; the
// screen then renders the full design with PlusCatalog.PlaceholderPrice
// values (clearly marked in code — real prices always come from
// Product.displayPrice once products exist).

import StoreKit
import SwiftUI

struct PaywallView: View {
  @ObservedObject private var store = Store.shared
  @Environment(\.dismiss) private var dismiss

  @State private var busy = false
  @State private var notice: String?

  private var freeStocks: [Stock] {
    Stock.all.filter { PlusCatalog.freeForeverStockIDs.contains($0.id) }
  }

  private var plusStocks: [Stock] {
    Stock.all.filter { !PlusCatalog.freeForeverStockIDs.contains($0.id) }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if Store.everythingFreeForNow {
          previewBanner
        }
        header
        offerRow
        if let notice {
          Text(notice)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        restoreButton
        freeForeverCard
        footnotes
      }
      .padding(16)
      .padding(.bottom, 24)
    }
    .background(Theme.paper)
    .navigationTitle("LensMood Plus")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      Analytics.log(.paywallViewed(surface: "account"))
      await store.start()
    }
  }

  // MARK: pieces

  private var previewBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "hammer")
        .font(.system(size: 13, weight: .semibold))
      Text("Everything is free right now. This is a preview of the supporter offer — nothing is locked.")
        .font(.system(size: 13, weight: .medium))
    }
    .foregroundStyle(Theme.inkSoft)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Twelve more cameras")
        .font(.system(size: 28, weight: .heavy))
        .foregroundStyle(Theme.ink)
      Text("Six cameras are yours free, forever, at full resolution. Plus opens the other twelve — and every camera we add later.")
        .font(.system(size: 15))
        .foregroundStyle(Theme.inkSoft)
    }
    .padding(.top, 4)
  }

  private var offerRow: some View {
    HStack(alignment: .top, spacing: 12) {
      OfferCard(
        title: "Yearly",
        // Placeholder shown only while no App Store product is loaded.
        price: store.yearlyProduct?.displayPrice ?? PlusCatalog.PlaceholderPrice.yearly,
        cadence: "per year",
        detail: "Billed once a year through your Apple ID. Cancel anytime.",
        tag: nil,
        highlighted: false,
        disabled: busy
      ) {
        buy(store.yearlyProduct)
      }
      OfferCard(
        title: "Lifetime",
        // Placeholder shown only while no App Store product is loaded.
        price: store.lifetimeProduct?.displayPrice ?? PlusCatalog.PlaceholderPrice.lifetime,
        cadence: "once",
        detail: "Yours for good. Future cameras included.",
        tag: "ONE-TIME PURCHASE",
        highlighted: true,
        disabled: busy
      ) {
        buy(store.lifetimeProduct)
      }
    }
  }

  private var restoreButton: some View {
    Button {
      guard !busy else { return }
      busy = true
      notice = nil
      Task {
        let restored = await store.restore()
        notice = restored
          ? "Plus restored — welcome back."
          : "Nothing to restore on this Apple ID yet."
        busy = false
      }
    } label: {
      Text("Restore purchases")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
  }

  private var freeForeverCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Free forever — with or without Plus")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Theme.ink)
      bullet("Six full cameras: \(freeStocks.map(\.name).joined(separator: ", "))")
      bullet("Full-resolution export of every photo and tape")
      bullet("Importing, saving, and sharing — never gated")
      Divider()
      Text("Plus adds \(plusStocks.count) signature cameras: \(plusStocks.map(\.name).joined(separator: ", "))")
        .font(.system(size: 13))
        .foregroundStyle(Theme.inkSoft)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
  }

  private var footnotes: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Both offers unlock exactly the same cameras. No weekly plans, no trials that flip into charges, no watermarks at any tier.")
      Text("Photos develop on your phone and never upload — free or Plus.")
    }
    .font(.system(size: 12))
    .foregroundStyle(Theme.fog)
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "checkmark")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Theme.accent)
        .padding(.top, 3)
      Text(text)
        .font(.system(size: 14))
        .foregroundStyle(Theme.inkSoft)
    }
  }

  // MARK: actions

  private func buy(_ product: Product?) {
    guard !busy else { return }
    guard let product else {
      // Degraded mode: no products configured in App Store Connect yet.
      // Copy stays status-free — never expose development state in UI copy.
      notice = "The App Store couldn't load these offers. Nothing was charged — please try again later."
      return
    }
    busy = true
    notice = nil
    Task {
      switch await store.purchase(product) {
      case .success:
        notice = "Thank you — the darkroom stays open."
      case .cancelled:
        notice = nil
      case .pending:
        notice = "Waiting for approval — it unlocks automatically once approved."
      case .unavailable, .failed:
        notice = "The App Store couldn't complete that. Nothing was charged."
      }
      busy = false
    }
  }
}

// MARK: - Offer card

private struct OfferCard: View {
  let title: String
  let price: String
  let cadence: String
  let detail: String
  let tag: String?
  let highlighted: Bool
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        if let tag {
          Text(tag)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent, in: Capsule())
        } else {
          // Keeps the two cards vertically aligned without a fake badge.
          Text(" ")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.vertical, 4)
        }
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Theme.ink)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(price)
            .font(.system(size: 24, weight: .heavy))
            .foregroundStyle(Theme.ink)
          Text(cadence)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.fog)
        }
        Text(detail)
          .font(.system(size: 12))
          .foregroundStyle(Theme.inkSoft)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay(
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(
            highlighted ? Theme.accent : Theme.ink.opacity(0.08),
            lineWidth: highlighted ? 2 : 1
          )
      )
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.6 : 1)
  }
}

#Preview {
  NavigationStack {
    PaywallView()
  }
}
