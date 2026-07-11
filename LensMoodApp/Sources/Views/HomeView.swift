import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var model: AppModel

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          introduction
          tapeFeature
          cameraHeader

          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Stock.all) { stock in
              NavigationLink(value: stock) {
                StockCard(stock: stock)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Opens \(stock.name) development")
            }
          }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 36)
      }
      .background(Theme.paper)
      .navigationDestination(for: Stock.self) { stock in
        DevelopView(stock: stock)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: 8) {
            ApertureMark()
            Text("LensMood")
              .font(.system(size: 19, weight: .bold))
              .foregroundStyle(Theme.ink)
          }
          .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.accountPresented = true
          } label: {
            Image(systemName: "person.crop.circle")
              .font(.system(size: 20))
              .foregroundStyle(Theme.ink)
          }
          .accessibilityLabel("Account and privacy")
        }
      }
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 10) {
      TechnicalLabel(text: "Camera personalities")
      Text("Choose how the camera thinks.")
        .font(.system(size: 36, weight: .bold, design: .serif))
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text("Each camera reads the light, subject, shadows, and color before developing your photograph.")
        .font(.system(size: 16))
        .foregroundStyle(Theme.inkSoft)
        .lineSpacing(4)
    }
    .padding(.top, 14)
  }

  private var tapeFeature: some View {
    Button {
      model.selectedTab = .tape
    } label: {
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Theme.viewfinder)
          .aspectRatio(16.0 / 9.0, contentMode: .fit)

        VStack(alignment: .leading, spacing: 0) {
          HStack {
            HStack(spacing: 6) {
              Circle().fill(Theme.recRed).frame(width: 8, height: 8)
              Text("REC")
            }
            Spacer()
            Text("TAPE 94")
          }
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .tracking(1.1)
          .foregroundStyle(Theme.viewfinderChrome)

          Spacer()

          Text("One tape. No controls.")
            .font(.system(size: 24, weight: .bold, design: .serif))
            .foregroundStyle(Theme.paper)
          Text("Soft color, slow grain, continuously visible.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.viewfinderChrome)
            .padding(.top, 4)
        }
        .padding(16)
      }
      .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open Tape 94 camcorder")
  }

  private var cameraHeader: some View {
    HStack(alignment: .lastTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        TechnicalLabel(text: "The camera case")
        Text("18 points of view")
          .font(.system(size: 24, weight: .bold, design: .serif))
          .foregroundStyle(Theme.ink)
      }
      Spacer()
      Text("01–18")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Theme.fog)
    }
    .padding(.top, 4)
  }
}

struct StockCard: View {
  let stock: Stock

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        LinearGradient(
          colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Image(systemName: stock.symbol)
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.82))
          .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
      }
      .frame(height: 104)

      VStack(alignment: .leading, spacing: 5) {
        Text(stock.name)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text(stock.tagline)
          .font(.system(size: 12.5))
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2, reservesSpace: true)
        Divider().overlay(Theme.hairline)
          .padding(.vertical, 4)
        Text(stock.bestFor.uppercased())
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(Theme.fog)
          .lineLimit(1)
      }
      .padding(12)
    }
    .background(Theme.surface)
    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    .contentShape(Rectangle())
  }
}

private struct ApertureMark: View {
  var body: some View {
    ZStack {
      Circle().stroke(Theme.ink, lineWidth: 1.5)
      Circle().fill(Theme.ink).frame(width: 8, height: 8)
      Circle().fill(Theme.accent).frame(width: 3, height: 3)
    }
    .frame(width: 22, height: 22)
  }
}

#Preview {
  HomeView().environmentObject(AppModel())
}
