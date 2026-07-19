import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TabView(selection: $model.selectedTab) {
      HomeView()
        .toolbar(.hidden, for: .tabBar)
        .tag(AppTab.cameras)

      CaptureView()
        .toolbar(.hidden, for: .tabBar)
        .tag(AppTab.capture)

      GalleryView()
        .toolbar(.hidden, for: .tabBar)
        .tag(AppTab.library)

      PrintRoomView()
        .toolbar(.hidden, for: .tabBar)
        .tag(AppTab.printRoom)

      CamcorderView()
        .toolbar(.hidden, for: .tabBar)
        .tag(AppTab.tape)
    }
    .tint(Theme.accent)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      // the camera is a full-screen instrument — no app dock over it
      if model.selectedTab != .capture { OceanDock() }
    }
    .sheet(isPresented: $model.accountPresented) {
      AccountView()
    }
    // widget taps arrive here: lensmood://develop/<stockID>
    .onOpenURL { model.open(url: $0) }
  }
}

/// OceanDock — the floating five-slot dock from the approved reference
/// design: white capsule dock, active tab in a soft pill with the teal icon,
/// and the camera always in the middle as the filled pill.
private struct OceanDock: View {
  @EnvironmentObject private var model: AppModel

  // the capture pill grows with the type setting so the dock stays balanced
  // when the slot icons and labels scale up
  @ScaledMetric(relativeTo: .title3) private var capturePillWidth: CGFloat = 62
  @ScaledMetric(relativeTo: .title3) private var capturePillHeight: CGFloat = 44

  var body: some View {
    HStack(spacing: 2) {
      slot(.cameras, icon: "camera.aperture", label: "Cameras")
      slot(.library, icon: "rectangle.stack.fill", label: "Library")
      captureButton
      slot(.printRoom, icon: "photo.artframe", label: "Print")
      slot(.tape, icon: "video.fill", label: "Tape")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Theme.surface)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    .oceanCardShadow(deep: true)
    .padding(.horizontal, 14)
    .padding(.top, 4)
    .padding(.bottom, 4)
    // Five slots plus the capture pill cannot host accessibility-size text on
    // one row (labels fell to unreadable truncation at AX5, and the scaled
    // pill crowded the slots off small screens). Like UIKit's tab bar, the
    // dock's own chrome stops growing at the largest regular size — each slot
    // instead offers the system large-content viewer (press and hold) with
    // its full-size icon and name.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityElement(children: .contain)
  }

  /// the camera is the product — it sits in the middle, filled, always
  private var captureButton: some View {
    let on = model.selectedTab == .capture
    return Button {
      model.selectedTab = .capture
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    } label: {
      ZStack {
        Capsule()
          .fill(Theme.brandFill)
          .frame(width: capturePillWidth, height: capturePillHeight)
          .shadow(color: Theme.clayDeep.opacity(on ? 0.45 : 0.3), radius: 8, y: 4)
        Image(systemName: "camera.fill")
          .scaledFont(size: 19, weight: .semibold, relativeTo: .title3)
          .foregroundStyle(.white)
      }
      .scaleEffect(on ? 1.06 : 1)
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityShowsLargeContentViewer {
      Label("Capture", systemImage: "camera.fill")
    }
    .accessibilityLabel("Capture")
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  private func slot(_ tab: AppTab, icon: String, label: String) -> some View {
    let on = model.selectedTab == tab
    return Button {
      model.selectedTab = tab
      UISelectionFeedbackGenerator().selectionChanged()
    } label: {
      VStack(spacing: 3) {
        Image(systemName: icon)
          .scaledFont(size: 18, weight: .medium, relativeTo: .title3)
        Text(label)
          .scaledFont(size: 10, weight: on ? .bold : .medium, relativeTo: .caption2)
          // the dock is one tight row of five — a grown label may shrink a
          // touch rather than wrap or push its neighbors
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(on ? Theme.accent : Theme.fog)
      .padding(.horizontal, 6)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(on ? AnyShapeStyle(Theme.paper) : AnyShapeStyle(Color.clear))
      .clipShape(Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityShowsLargeContentViewer {
      Label(label, systemImage: icon)
    }
    .accessibilityLabel(label)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}
