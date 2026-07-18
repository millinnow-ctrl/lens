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
            .font(.footnote.weight(.medium))   // 13pt at the default size
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
        .scaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
      Text("Everything is free right now. This is a preview of the supporter offer — nothing is locked.")
        .font(.footnote.weight(.medium))   // 13pt at the default size
    }
    .foregroundStyle(Theme.inkSoft)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Twelve more cameras")
        .font(.title.weight(.heavy))   // 28pt at the default size
        .foregroundStyle(Theme.ink)
      Text("Six cameras are yours free, forever, at full resolution. Plus opens the other twelve — and every camera we add later.")
        .font(.subheadline)   // 15pt at the default size
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
        .font(.subheadline.weight(.semibold))   // 15pt at the default size
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
  }

  private var freeForeverCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Free forever — with or without Plus")
        .font(.subheadline.weight(.bold))   // 15pt at the default size
        .foregroundStyle(Theme.ink)
      bullet("Six full cameras: \(freeStocks.map(\.name).joined(separator: ", "))")
      bullet("Full-resolution export of every photo and tape")
      bullet("Importing, saving, and sharing — never gated")
      Divider()
      Text("Plus adds \(plusStocks.count) signature cameras: \(plusStocks.map(\.name).joined(separator: ", "))")
        .font(.footnote)   // 13pt at the default size
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
    .font(.caption)   // 12pt at the default size
    .foregroundStyle(Theme.fog)
  }

  private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "checkmark")
        .scaledFont(size: 11, weight: .bold, relativeTo: .caption2)
        .foregroundStyle(Theme.accent)
        .padding(.top, 3)
      Text(text)
        .scaledFont(size: 14, relativeTo: .footnote)
        .foregroundStyle(Theme.inkSoft)
    }
  }

  // MARK: actions

  private func buy(_ product: Product?) {
    guard !busy else { return }
    guard let product else {
      // Degraded mode: no products configured in App Store Connect yet.
      notice = "Purchases aren't set up yet — prices shown are placeholders."
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
            .scaledFont(size: 10, weight: .bold, design: .monospaced, relativeTo: .caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .kerning(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent, in: Capsule())
        } else {
          // Keeps the two cards vertically aligned without a fake badge.
          Text(" ")
            .scaledFont(size: 10, weight: .bold, design: .monospaced, relativeTo: .caption2)
            .padding(.vertical, 4)
        }
        Text(title)
          .font(.callout.weight(.bold))   // 16pt at the default size
          .foregroundStyle(Theme.ink)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(price)
            .scaledFont(size: 24, weight: .heavy, relativeTo: .title2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Theme.ink)
          Text(cadence)
            .font(.caption.weight(.medium))   // 12pt at the default size
            .foregroundStyle(Theme.fog)
        }
        Text(detail)
          .font(.caption)   // 12pt at the default size
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
