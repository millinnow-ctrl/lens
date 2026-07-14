import StoreKit
import SwiftUI

/// LensMood Premium paywall (scaffold — not gating anything yet).
///
/// Ethics first (FTC dark-pattern guidance): outcome-framed benefits, plans and
/// billing period shown plainly, annual as the value anchor, an explicit Restore
/// control, Terms + Privacy links, honest auto-renew copy, no fake urgency, no
/// confirm-shaming, and no gate on a vulnerable moment — a good premium moment
/// is *after* a user has created something they love.
struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var store = Store()
  @State private var plan: Plan = .annual

  var triggerSurface: String = "account"

  enum Plan { case annual, monthly }

  private let benefits: [(icon: String, title: String, detail: String)] = [
    ("camera.aperture", "Every look, unlocked", "The full film library and future look drops"),
    ("square.and.arrow.up", "High-resolution export", "Full-quality saves and batch exports"),
    ("slider.horizontal.3", "Advanced controls", "Fine grain, halation, and color to taste"),
    ("sparkles", "Seasonal collections", "New limited looks as they arrive"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 6) {
            Text("LensMood Premium")
              .font(.system(size: 30, weight: .heavy))
              .foregroundStyle(Theme.ink)
            Text("See your photographs in every film.")
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(Theme.inkSoft)
          }

          VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits, id: \.title) { benefit in
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: benefit.icon)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(Theme.accent)
                  .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                  Text(benefit.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                  Text(benefit.detail).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                }
              }
            }
          }

          VStack(spacing: 10) {
            planCard(.annual, title: "Annual", price: priceText(store.annual), caption: "Best value", featured: true)
            planCard(.monthly, title: "Monthly", price: priceText(store.monthly), caption: "Flexible", featured: false)
          }

          Button {
            Task {
              Analytics.log(.paywallViewed(surface: triggerSurface))
              if let product = plan == .annual ? store.annual : store.monthly {
                _ = await store.purchase(product)
              }
            }
          } label: {
            Text(store.purchasing ? "Please wait…" : "Continue")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
          .disabled(store.purchasing)

          Text("Auto-renews until cancelled. Cancel anytime in Settings. Payment is charged to your Apple ID.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.fog)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

          HStack(spacing: 18) {
            Button("Restore") { Task { await store.restore() } }
            Link("Terms", destination: URL(string: "https://lensmood.app/terms")!)
            Link("Privacy", destination: URL(string: "https://lensmood.app/privacy")!)
          }
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Theme.inkSoft)
          .frame(maxWidth: .infinity)
        }
        .padding(Theme.pagePadding)
      }
      .background(Theme.paper)
      .navigationTitle("Premium")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Not now") { dismiss() }.foregroundStyle(Theme.inkSoft)
        }
      }
      .task {
        await store.loadProducts()
        Analytics.log(.paywallViewed(surface: triggerSurface))
      }
    }
  }

  private func planCard(_ value: Plan, title: String, price: String, caption: String, featured: Bool) -> some View {
    let selected = plan == value
    return Button {
      plan = value
      UISelectionFeedbackGenerator().selectionChanged()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(selected ? Theme.accent : Theme.fog)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
          Text(caption).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
        }
        Spacer()
        Text(price).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.ink)
      }
      .padding(16)
      .frame(maxWidth: .infinity)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(title) plan, \(price), \(caption)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// Real price when a product is configured; a neutral placeholder until then.
  private func priceText(_ product: Product?) -> String {
    product?.displayPrice ?? "—"
  }
}
