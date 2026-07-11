// Home — the case: a big Video (camcorder) card, then the 18 lenses.
// Pure SwiftUI: native scrolling, native transitions, SF type.

import SwiftUI

struct HomeView: View {
  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header
          videoCard
          VStack(alignment: .leading, spacing: 2) {
            Text("Explore looks")
              .font(.system(size: 26, weight: .heavy))
              .foregroundStyle(Theme.ink)
            Text("18 cameras, one tap each")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(Theme.fog)
          }
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Stock.all) { stock in
              NavigationLink(value: stock) {
                StockCard(stock: stock)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
      }
      .background(Theme.paper)
      .navigationDestination(for: Stock.self) { stock in
        DevelopView(stock: stock)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Circle()
        .strokeBorder(Theme.accent, lineWidth: 4)
        .background(Circle().fill(Theme.accent).padding(7))
        .frame(width: 26, height: 26)
      Text("LensMood")
        .font(.system(size: 24, weight: .heavy))
        .foregroundStyle(Theme.ink)
      Spacer()
    }
    .padding(.top, 8)
  }

  private var videoCard: some View {
    NavigationLink(value: Stock.all.first { $0.id == "camcorder-90s" } ?? Stock.all[0]) {
      ZStack(alignment: .bottomLeading) {
        RoundedRectangle(cornerRadius: 22)
          .fill(Theme.viewfinder)
          .aspectRatio(16.0 / 9.0, contentMode: .fit)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Circle().fill(Theme.recRed).frame(width: 9, height: 9)
            Text("REC")
              .font(.system(size: 12, weight: .bold))
              .kerning(1)
              .foregroundStyle(.white.opacity(0.95))
          }
          Spacer()
          Text("Camcorder")
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(.white)
          Text("Any clip, filmed like 1994 — tap to load a tape.")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .buttonStyle(.plain)
  }
}

struct StockCard: View {
  let stock: Stock

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      LinearGradient(
        colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(height: 74)
      VStack(alignment: .leading, spacing: 3) {
        Text(stock.name)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text(stock.tagline)
          .font(.system(size: 12.5))
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2, reservesSpace: true)
        Text(stock.exif)
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .foregroundStyle(Theme.fog)
          .lineLimit(1)
          .padding(.top, 4)
      }
      .padding(12)
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 4)
  }
}

#Preview {
  HomeView()
}
