import { useEffect } from 'react'
import { Stack } from 'expo-router'
import { StatusBar } from 'expo-status-bar'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { SafeAreaProvider } from 'react-native-safe-area-context'

import { AppProvider, useApp } from '@/store'
import { initPurchases, syncPlanFromCustomerInfo } from '@/purchases'
import { colors } from '@/theme/colors'

/** wires RevenueCat (when present — dev/EAS builds) to the store's plan.
 *  In Expo Go the purchases module is absent and this is a silent no-op. */
function PurchasesBridge() {
  const { setPlan } = useApp()
  useEffect(() => {
    initPurchases((info) => syncPlanFromCustomerInfo(info, setPlan))
  }, [setPlan])
  return null
}

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colors.paper }}>
      <SafeAreaProvider>
        <AppProvider>
          <PurchasesBridge />
          {/* ocean darkroom: dark glyphs on the cool paper canvas */}
          <StatusBar style="dark" />
          <Stack
            screenOptions={{
              headerShown: false,
              animation: 'slide_from_right',
              contentStyle: { backgroundColor: colors.paper },
            }}
          />
        </AppProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  )
}
