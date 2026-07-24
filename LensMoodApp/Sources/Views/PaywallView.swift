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

/// Where the offer is standing when it appears: at a locked camera's film
/// door (carrying the frames the user already kept on that camera), or
/// browsed cold (AccountView's design preview / account offer row).
enum PaywallContext {
  case reload(stock: Stock, kept: [UIImage])
  case browse
}

struct PaywallView: View {
  var context: PaywallContext = .browse
  /// true when presented as a sheet (the develop doors): the purchase
  /// surface must name itself and offer an explicit way out — swipe-down
  /// alone is not a visible dismiss affordance
  var showsDone = false

  @ObservedObject private var store = Store.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize

  @State private var busy = false
  @State private var notice: String?

  private var freeStocks: [Stock] {
    Stock.all.filter { PlusCatalog.freeForeverStockIDs.contains($0.id) }
  }

  private var isReloadContext: Bool {
    if case .reload = context { return true }
    return false
  }

  private var surfaceName: String {
    isReloadContext ? "develop-reload" : "account"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if Store.allGatesOpen {
          previewBanner
        }
        if case .reload(let stock, let kept) = context {
          reloadSection(stock: stock, kept: kept)
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
    .toolbar {
      if showsDone {
        // .navigationBarTrailing (not .topBarTrailing) — iOS 16 floor.
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
            .font(.callout.weight(.semibold))   // 16pt at the default size
            .foregroundStyle(Theme.accent)
        }
      }
    }
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
        .accessibilityHidden(true)   // decorative — the text carries the meaning
      Text("Everything's free right now — a preview of the supporter offer. Nothing is locked.")
        .font(.footnote.weight(.medium))   // 13pt at the default size
    }
    .foregroundStyle(Theme.inkSoft)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
  }

  /// the film-door context leads with the camera being bought and the
  /// frames the user already kept on it — the offer stands on the user's
  /// own photographs, never on stock art
  private func reloadSection(stock: Stock, kept: [UIImage]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        TechnicalLabel(text: "Out of film")
        Spacer()
        Text("0 OF \(ExposureRoll.loadedExposures) EXP")
          .scaledFont(size: 11, weight: .bold, design: .monospaced, relativeTo: .caption2)
          .tracking(0.8)
          .foregroundStyle(Theme.fog)
      }
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
          .frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 2) {
          Text(stock.name)
            .font(.body.weight(.bold))   // 17pt at the default size
            .foregroundStyle(Theme.ink)
          Text(stock.tagline)
            .font(.footnote)   // 13pt at the default size
            .foregroundStyle(Theme.inkSoft)
        }
        Spacer(minLength: 0)
      }
      if !kept.isEmpty {
        HStack(spacing: 8) {
          ForEach(Array(kept.prefix(3).enumerated()), id: \.offset) { _, frame in
            Image(uiImage: frame)
              .resizable()
              .scaledToFill()
              .frame(width: 64, height: 80)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
        }
        Text("What you developed is yours, on your Roll.")
          .font(.footnote)   // 13pt at the default size
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(stock.name), out of film. The \(ExposureRoll.loadedExposures) loaded exposures are spent; what you developed is yours."
    )
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(isReloadContext ? "Load every camera for good" : "Twelve more cameras")
        .font(.title.weight(.heavy))   // 28pt at the default size
        .foregroundStyle(Theme.ink)
      Text(isReloadContext
        ? "Six cameras free forever, full resolution. Plus loads this one and every other — including cameras we add later."
        : "Six cameras free forever, at full resolution. Plus opens the other twelve, and every camera we add later.")
        .font(.subheadline)   // 15pt at the default size
        .foregroundStyle(Theme.inkSoft)
    }
    .padding(.top, 4)
  }

  /// Accessibility type sizes: side by side, each card would offer its
  /// grown price and detail ~150pt of width — they stack full-width instead.
  @ViewBuilder
  private var offerRow: some View {
    if typeSize.isAccessibilitySize {
      VStack(spacing: 12) {
        yearlyOffer
        lifetimeOffer
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        yearlyOffer
        lifetimeOffer
      }
    }
  }

  private var yearlyOffer: some View {
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
  }

  private var lifetimeOffer: some View {
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
      bullet("Every locked camera comes loaded with \(ExposureRoll.loadedExposures) exposures — full-resolution develops you keep")
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
      // six across at regular sizes; three at accessibility sizes, where a
      // sixth-width cell reduces every camera name to one or two glyphs
      columns: Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: typeSize.isAccessibilitySize ? 3 : 6
      ),
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
      Text("Both offers unlock the same cameras. No weekly plans, no trials that become charges, no watermarks.")
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
        .accessibilityHidden(true)   // decorative bullet mark — VoiceOver reads the text alone
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

#Preview("Film-door context") {
  NavigationStack {
    PaywallView(context: .reload(
      stock: Stock.find("tintype"),
      kept: [BundleMedia.image("style-tintype") ?? UIImage()]
    ))
  }
}
