import SwiftUI

struct AccountView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 8) {
            TechnicalLabel(text: "LensMood")
            Text("Your darkroom")
              .font(.system(size: 32, weight: .heavy))
              .foregroundStyle(Theme.ink)
            Text("Processing remains on this device. All camera personalities are available. You can decide what belongs in your library before anything is saved.")
              .font(.system(size: 15))
              .foregroundStyle(Theme.inkSoft)
              .lineSpacing(4)
          }

          InstrumentPanel {
            VStack(alignment: .leading, spacing: 0) {
              accountRow("Processing", value: "On device")
              Divider().overlay(Theme.hairline)
              accountRow("Camera library", value: "18 available")
              Divider().overlay(Theme.hairline)
              accountRow("Develop access", value: "Available")
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            TechnicalLabel(text: "Privacy")
            Text("LensMood does not need an account to develop photographs. Photos are read only when you choose them and are saved only when you ask.")
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
