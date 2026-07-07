import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'app.lensmood.ios',
  appName: 'LensMood',
  webDir: 'dist',
  ios: {
    // edge-to-edge: the web layer handles the safe area itself via
    // env(safe-area-inset-top) — 'automatic' would inset the whole webview
    // below the status bar and double the gap above the header
    contentInset: 'never',
    backgroundColor: "#f6f5f1",
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 900,
      launchAutoHide: true,
      backgroundColor: "#f6f5f1",
      showSpinner: false,
    },
    StatusBar: {
      style: 'LIGHT',
      backgroundColor: "#f6f5f1",
      overlaysWebView: true,
    },
  },
}

export default config
