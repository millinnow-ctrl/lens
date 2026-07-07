/**
 * Paywall — membership, ported from the web PricingPage. Monthly/annual
 * toggle (annual = two months free), three plan cards, restore purchases.
 * With RevenueCat configured (dev/EAS build) purchases are real StoreKit;
 * in Expo Go it explains itself instead of silently failing.
 */

import { useEffect, useMemo, useState } from 'react'
import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Platform } from 'react-native'
import { Stack, router } from 'expo-router'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import { useApp, haptics, type Plan } from '@/store'
import { getPackages, purchase, restore, purchasesAvailable } from '@/purchases'
import { colors } from '@/theme/colors'

const MONO = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' })

interface Tier {
  id: Exclude<Plan, 'free'>
  name: string
  monthly: number
  blurb: string
  features: string[]
}

/** local price table — RevenueCat's localized prices win when configured */
const TIERS: Tier[] = [
  {
    id: 'creator',
    name: 'Creator',
    monthly: 8,
    blurb: 'For the daily poster.',
    features: ['Unlimited develops', 'No watermark', 'All 18 cameras', 'Saved presets'],
  },
  {
    id: 'pro',
    name: 'Pro',
    monthly: 15,
    blurb: 'For the obsessed.',
    features: ['Everything in Creator', 'HD exports', 'Premium camera packs', 'Video support', 'Batch uploads'],
  },
  {
    id: 'studio',
    name: 'Studio',
    monthly: 29,
    blurb: 'For the professionals.',
    features: ['Everything in Pro', '4K video', 'Priority rendering', 'Commercial license'],
  },
]

const ANNUAL_MONTHS = 10 // two months free

export default function Paywall() {
  const insets = useSafeAreaInsets()
  const { plan, setPlan } = useApp()
  const [annual, setAnnual] = useState(false)
  const [busy, setBusy] = useState<string | null>(null)
  const [rcPackages, setRcPackages] = useState<Awaited<ReturnType<typeof getPackages>>>(null)

  useEffect(() => {
    getPackages().then(setRcPackages)
  }, [])

  /** find the RevenueCat package for a tier + cycle, if offerings loaded */
  const pkgFor = useMemo(
    () => (tier: Tier) => {
      if (!rcPackages) return null
      const want = `${tier.id}_${annual ? 'annual' : 'monthly'}`
      return (
        rcPackages.find((p: { identifier?: string }) =>
          (p.identifier ?? '').toLowerCase().includes(want),
        ) ?? null
      )
    },
    [rcPackages, annual],
  )

  const buy = async (tier: Tier) => {
    haptics.medium()
    if (!purchasesAvailable()) {
      Alert.alert(
        'Purchases need a real build',
        'Subscriptions run through Apple In-App Purchase, which needs the dev/TestFlight build (see the README). In Expo Go this is a preview only.',
      )
      return
    }
    const pkg = pkgFor(tier)
    if (!pkg) {
      Alert.alert('Store unavailable', 'Could not load products from the App Store. Try again shortly.')
      return
    }
    setBusy(tier.id)
    const out = await purchase(pkg)
    setBusy(null)
    if (out.ok) {
      setPlan(out.plan)
      haptics.success()
      Alert.alert('Welcome to ' + tier.name, 'Your membership is active.')
      router.back()
    } else if (out.reason === 'error') {
      Alert.alert('Purchase failed', 'Nothing was charged. Please try again.')
    }
  }

  const doRestore = async () => {
    if (!purchasesAvailable()) {
      Alert.alert('Purchases need a real build', 'Restore works in the dev/TestFlight build.')
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
      <Stack.Screen options={{ headerShown: false, presentation: 'modal' }} />
      <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + 28 }} showsVerticalScrollIndicator={false}>
        <View style={styles.topbar}>
          <Pressable onPress={() => router.back()} hitSlop={12}>
            <Text style={styles.close}>✕</Text>
          </Pressable>
        </View>

        <Text style={styles.eyebrow}>MEMBERSHIP</Text>
        <Text style={styles.h1}>Every camera.{'\n'}No limits.</Text>

        {/* cycle toggle */}
        <View style={styles.cycleWrap}>
          <View style={styles.cycle}>
            {(['monthly', 'annual'] as const).map((c) => {
              const on = annual === (c === 'annual')
              return (
                <Pressable
                  key={c}
                  onPress={() => {
                    haptics.selection()
                    setAnnual(c === 'annual')
                  }}
                  style={[styles.cycleItem, on && styles.cycleItemOn]}
                >
                  <Text style={[styles.cycleText, on && styles.cycleTextOn]}>
                    {c === 'monthly' ? 'Monthly' : 'Annual · 2 months free'}
                  </Text>
                </Pressable>
              )
            })}
          </View>
        </View>

        {/* plans */}
        <View style={styles.cards}>
          {TIERS.map((tier) => {
            const current = plan === tier.id
            const monthlyRate = annual ? (tier.monthly * ANNUAL_MONTHS) / 12 : tier.monthly
            const featured = tier.id === 'pro'
            return (
              <View key={tier.id} style={[styles.card, featured && styles.cardFeatured]}>
                {featured && (
                  <View style={styles.popular}>
                    <Text style={styles.popularText}>MOST POPULAR</Text>
                  </View>
                )}
                <Text style={[styles.planName, featured && styles.onDark]}>{tier.name}</Text>
                <Text style={[styles.blurb, featured && styles.onDarkSoft]}>{tier.blurb}</Text>
                <View style={styles.priceRow}>
                  <Text style={[styles.price, featured && styles.onDark]}>
                    ${monthlyRate % 1 === 0 ? monthlyRate : monthlyRate.toFixed(2)}
                  </Text>
                  <Text style={[styles.per, featured && styles.onDarkSoft]}>/mo</Text>
                </View>
                {annual && (
                  <Text style={[styles.annualNote, featured && styles.onDarkSoft]}>
                    billed ${tier.monthly * ANNUAL_MONTHS}/yr
                  </Text>
                )}
                <View style={styles.features}>
                  {tier.features.map((f) => (
                    <Text key={f} style={[styles.feature, featured && styles.onDarkSoft]}>
                      · {f}
                    </Text>
                  ))}
                </View>
                <Pressable
                  disabled={current || busy !== null}
                  onPress={() => buy(tier)}
                  style={({ pressed }) => [
                    styles.cta,
                    featured ? styles.ctaLight : styles.ctaDark,
                    (current || pressed) && { opacity: 0.75 },
                  ]}
                >
                  <Text style={[styles.ctaText, featured ? { color: colors.clay } : { color: '#fff' }]}>
                    {current ? 'Current plan' : busy === tier.id ? '…' : `Go ${tier.name}`}
                  </Text>
                </Pressable>
              </View>
            )
          })}
        </View>

        <Pressable onPress={doRestore} hitSlop={8}>
          <Text style={styles.restore}>Restore purchases</Text>
        </Pressable>
        <Text style={styles.legal}>
          Subscriptions bill through your Apple ID and renew until cancelled in Settings. Photos never
          leave your device on any plan.
        </Text>
      </ScrollView>
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.paper },
  topbar: { flexDirection: 'row', justifyContent: 'flex-end', paddingHorizontal: 18, paddingVertical: 8 },
  close: { fontSize: 20, color: colors.inkSoft, padding: 4 },
  eyebrow: {
    color: colors.accent,
    fontSize: 11,
    letterSpacing: 2.2,
    fontFamily: MONO,
    fontWeight: '600',
    paddingHorizontal: 20,
  },
  h1: {
    color: colors.ink,
    fontSize: 34,
    lineHeight: 38,
    fontWeight: '800',
    letterSpacing: -0.6,
    paddingHorizontal: 20,
    marginTop: 8,
  },

  cycleWrap: { paddingHorizontal: 20, marginTop: 18 },
  cycle: { flexDirection: 'row', backgroundColor: 'rgb(226,232,237)', borderRadius: 999, padding: 4 },
  cycleItem: { flex: 1, paddingVertical: 9, borderRadius: 999, alignItems: 'center' },
  cycleItemOn: {
    backgroundColor: colors.surface,
    shadowColor: colors.ink,
    shadowOpacity: 0.1,
    shadowRadius: 5,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
  cycleText: { color: colors.inkSoft, fontSize: 13, fontWeight: '600' },
  cycleTextOn: { color: colors.ink },

  cards: { paddingHorizontal: 20, gap: 14, marginTop: 18 },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 24,
    padding: 20,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(23,36,45,0.10)',
  },
  cardFeatured: { backgroundColor: colors.clay, borderColor: 'transparent' },
  popular: {
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(255,255,255,0.16)',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
    marginBottom: 10,
  },
  popularText: { color: '#fff', fontSize: 9, letterSpacing: 1.4, fontFamily: MONO, fontWeight: '700' },
  planName: { color: colors.ink, fontSize: 20, fontWeight: '800', letterSpacing: -0.3 },
  blurb: { color: colors.inkSoft, fontSize: 13, marginTop: 2 },
  priceRow: { flexDirection: 'row', alignItems: 'baseline', marginTop: 12 },
  price: { color: colors.ink, fontSize: 34, fontWeight: '800', letterSpacing: -0.8 },
  per: { color: colors.inkSoft, fontSize: 14, marginLeft: 2 },
  annualNote: { color: colors.fog, fontSize: 12, marginTop: 2 },
  features: { marginTop: 12, gap: 5 },
  feature: { color: colors.inkSoft, fontSize: 13.5, lineHeight: 19 },
  onDark: { color: '#fff' },
  onDarkSoft: { color: 'rgba(255,255,255,0.78)' },
  cta: { height: 48, borderRadius: 14, alignItems: 'center', justifyContent: 'center', marginTop: 16 },
  ctaDark: { backgroundColor: colors.ink },
  ctaLight: { backgroundColor: '#fff' },
  ctaText: { fontSize: 15, fontWeight: '700' },

  restore: { color: colors.accent, fontSize: 14, fontWeight: '600', textAlign: 'center', marginTop: 22 },
  legal: {
    color: colors.fog,
    fontSize: 11.5,
    lineHeight: 16,
    textAlign: 'center',
    paddingHorizontal: 32,
    marginTop: 12,
  },
})
