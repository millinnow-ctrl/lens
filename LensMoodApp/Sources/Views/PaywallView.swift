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

/// Where the offer is standing when it appears: over the user's own developed
/// frame at the keep moment, or browsed cold (AccountView's design preview).
enum PaywallContext {
  case keep(preview: UIImage, stock: Stock)
  case browse
}

struct PaywallView: View {
  var context: PaywallContext = .browse

  @ObservedObject private var store = Store.shared
  @Environment(\.dismiss) private var dismiss

  @State private var busy = false
  @State private var notice: String?

  private var freeStocks: [Stock] {
    Stock.all.filter { PlusCatalog.freeForeverStockIDs.contains($0.id) }
  }

  private var isKeepContext: Bool {
    if case .keep = context { return true }
    return false
  }

  private var surfaceName: String {
    isKeepContext ? "develop-keep" : "account"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if Store.allGatesOpen {
          previewBanner
        }
        if case .keep(let preview, let stock) = context {
          keepContextSection(preview: preview, stock: stock)
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
      Analytics.log(.paywallViewed(surface: surfaceName))
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

  /// the keep context leads with the user's own frame — the offer stands
  /// over the photograph it is about, never over stock art
  private func keepContextSection(preview: UIImage, stock: Stock) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Color.clear
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .overlay(
          Image(uiImage: preview)
            .resizable()
            .scaledToFill()
        )
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text("Your photograph, developed on \(stock.name).")
        .font(.footnote)   // 13pt at the default size
        .foregroundStyle(Theme.inkSoft)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(isKeepContext ? "Keep the darkroom open" : "Twelve more cameras")
        .font(.title.weight(.heavy))   // 28pt at the default size
        .foregroundStyle(Theme.ink)
      Text(isKeepContext
        ? "Six cameras are yours free forever, full resolution. Plus opens the other twelve — including this one — and every camera we add later."
        : "Six cameras are yours free, forever, at full resolution. Plus opens the other twelve — and every camera we add later.")
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
      shelfGrid
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
  }

  /// the whole shelf at a glance — all 18 cameras in catalog order, gradient
  /// swatches like the develop rail's chips. Free is the labeled exception;
  /// Plus cameras carry no caption.
  private var shelfGrid: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
      spacing: 10
    ) {
      ForEach(Stock.all) { stock in
        shelfCell(stock)
      }
    }
  }

  private func shelfCell(_ stock: Stock) -> some View {
    let free = PlusCatalog.freeForeverStockIDs.contains(stock.id)
    return VStack(spacing: 3) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
          )
        )
        .frame(width: 40, height: 40)
      Text(stock.name)
        .font(.caption2)   // 11pt at the default size
        .foregroundStyle(Theme.inkSoft)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      if free {
        Text("FREE")
          .scaledFont(size: 8.5, weight: .bold, design: .monospaced, relativeTo: .caption2)
          .foregroundStyle(Theme.accent)
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(free ? "\(stock.name), free forever" : "\(stock.name), in Plus")
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

#Preview("Keep context") {
  NavigationStack {
    PaywallView(context: .keep(
      preview: BundleMedia.image("style-polaroid") ?? UIImage(),
      stock: Stock.all[8]
    ))
  }
}
