import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'app.lensmood.ios',
  appName: 'LensMood',
  webDir: 'dist',
  ios: {
    contentInset: 'automatic',
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
    },
  },
}

export default config
