import SwiftUI

struct AccountView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var showPaywall = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .center, spacing: 8) {
            TechnicalLabel(text: "LensMood")
            Text("Your darkroom")
              .font(.system(size: 32, weight: .heavy))
              .foregroundStyle(Theme.ink)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)

          Button {
            showPaywall = true
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
              VStack(alignment: .leading, spacing: 2) {
                Text("LensMood Premium").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text("Every look, high-res export, seasonal drops")
                  .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
              }
              Spacer()
              Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.brandFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .oceanCardShadow()
          }
          .buttonStyle(.plain)
          .accessibilityLabel("LensMood Premium. See plans.")

          InstrumentPanel {
            VStack(alignment: .leading, spacing: 0) {
              accountRow("Processing", value: "On device")
              Divider().overlay(Theme.hairline)
              accountRow("Film library", value: "18 looks")
              Divider().overlay(Theme.hairline)
              accountRow("Version", value: "1.0.0")
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            TechnicalLabel(text: "Privacy")
            Text("Photos are read only when you choose them and saved only when you ask.")
              .font(.system(size: 14))
              .foregroundStyle(Theme.inkSoft)
              .lineSpacing(4)
          }
        }
        .padding(Theme.pagePadding)
      }
      .background(Theme.paper)
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showPaywall) {
        PaywallView(triggerSurface: "account")
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .foregroundStyle(Theme.ink)
        }
      }
    }
  }

  private func accountRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(Theme.ink)
      Spacer()
      Text(value)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.fog)
    }
    .font(.system(size: 15))
    .padding(16)
  }
}
