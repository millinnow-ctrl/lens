import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TabView(selection: $model.selectedTab) {
      HomeView()
        .tabItem { Label("Cameras", systemImage: "camera.aperture") }
        .tag(AppTab.cameras)

      CaptureView()
        .tabItem { Label("Capture", systemImage: "camera.fill") }
        .tag(AppTab.capture)

      GalleryView()
        .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
        .tag(AppTab.library)

      PrintRoomView()
        .tabItem { Label("Print", systemImage: "photo.artframe") }
        .tag(AppTab.printRoom)

      CamcorderView()
        .tabItem { Label("Tape", systemImage: "video.fill") }
        .tag(AppTab.tape)
    }
    .tint(Theme.accent)
    .sheet(isPresented: $model.accountPresented) {
      AccountView()
    }
  }
}
