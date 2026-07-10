/**
 * Account — plan status, credits, restore purchases. Kept intentionally
 * light: the darkroom is the product, this is the service hatch.
 */

import { View, Text, Pressable, StyleSheet, Alert } from 'react-native'
import { Stack, router } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import Logo from '@/components/Logo'
import { useApp, FREE_CREDITS } from '@/store'
import { restore, purchasesAvailable } from '@/purchases'
import { colors } from '@/theme/colors'

export default function Account() {
  const insets = useSafeAreaInsets()
  const { plan, isPaid, creditsLeft, setPlan, history } = useApp()

  const doRestore = async () => {
    if (!purchasesAvailable()) {
      Alert.alert('Purchases need a real build', 'Restore works in the dev/TestFlight build — Expo Go is a preview.')
      return
    }
    const restored = await restore()
    if (restored && restored !== 'free') {
      setPlan(restored)
      Alert.alert('Restored', `Your ${restored} membership is back.`)
    } else {
      Alert.alert('Nothing to restore', 'No active membership on this Apple ID.')
    }
  }

  return (
    <View style={[styles.root, { paddingTop: insets.top }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={styles.topbar}>
        <Pressable onPress={() => router.back()} hitSlop={12}>
          <Text style={styles.back}>‹ Back</Text>
        </Pressable>
      </View>

      <View style={styles.header}>
        <Logo />
      </View>

      <View style={styles.cards}>
        <View style={styles.card}>
          <Text style={styles.cardLabel}>Your plan</Text>
          <Text style={styles.cardValue}>{plan.charAt(0).toUpperCase() + plan.slice(1)}</Text>
          <Text style={styles.cardSub}>
            {isPaid
              ? 'Unlimited develops, no watermark.'
              : `${creditsLeft} of ${FREE_CREDITS} free develops left this month.`}
          </Text>
          {!isPaid && (
            <Pressable
              onPress={() => router.push('/paywall')}
              style={({ pressed }) => [styles.cta, pressed && { opacity: 0.9 }]}
            >
              <Text style={styles.ctaText}>See plans</Text>
            </Pressable>
          )}
        </View>

        <View style={styles.card}>
          <Text style={styles.cardLabel}>Your darkroom</Text>
          <Text style={styles.cardValue}>{history.length} develops</Text>
          <Text style={styles.cardSub}>Everything renders on this phone. Nothing is ever uploaded.</Text>
        </View>

        <Pressable onPress={doRestore} hitSlop={8}>
          <Text style={styles.restore}>Restore purchases</Text>
        </Pressable>
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  topbar: { paddingHorizontal: 16, paddingVertical: 10 },
  back: { color: colors.accent, fontSize: 16, fontWeight: '600' },
  header: { alignItems: 'center', marginTop: 8, marginBottom: 22 },
  cards: { paddingHorizontal: 20, gap: 14 },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 22,
    padding: 20,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.10)',
  },
  cardLabel: { color: colors.inkSoft, fontSize: 14, fontWeight: '700' },
  cardValue: { color: colors.ink, fontSize: 22, fontWeight: '800', letterSpacing: -0.3, marginTop: 6 },
  cardSub: { color: colors.inkSoft, fontSize: 13.5, lineHeight: 19, marginTop: 4 },
  cta: {
    height: 44,
    borderRadius: 13,
    backgroundColor: colors.accent,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 14,
  },
  ctaText: { color: '#fff', fontSize: 14.5, fontWeight: '700' },
  restore: { color: colors.accent, fontSize: 14, fontWeight: '600', textAlign: 'center', marginTop: 10 },
})
