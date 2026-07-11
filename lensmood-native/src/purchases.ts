/**
 * Subscriptions — RevenueCat (StoreKit under the hood), loaded lazily so the
 * app still runs where the native module doesn't exist (Expo Go). In a dev
 * client / EAS build with an API key configured, purchases are real; in Expo
 * Go every call degrades to a clearly-labelled demo mode.
 *
 * Setup (one-time, on the RevenueCat dashboard):
 *   1. Create an iOS app for bundle id app.lensmood.native.
 *   2. Create entitlements with ids: creator, pro, studio.
 *   3. Attach your App Store Connect subscription products to them.
 *   4. Put the public Apple API key in app.json → expo.extra.revenueCatIosKey.
 */

import { Platform } from 'react-native'
import Constants from 'expo-constants'
import type { Plan } from '@/store'

/* eslint-disable @typescript-eslint/no-explicit-any */
type PurchasesModule = any
type CustomerInfo = any
type PurchasesPackage = any

let Purchases: PurchasesModule | null = null
let configured = false

/** the native module is absent in Expo Go — require() it defensively */
function loadModule(): PurchasesModule | null {
  if (Purchases) return Purchases
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mod = require('react-native-purchases')
    Purchases = mod?.default ?? mod
  } catch {
    Purchases = null
  }
  return Purchases
}

function apiKey(): string | null {
  const extra = (Constants.expoConfig?.extra ?? {}) as Record<string, unknown>
  const key = extra.revenueCatIosKey
  return typeof key === 'string' && key.length > 0 && !key.startsWith('YOUR_') ? key : null
}

/** true when real purchases are wired (dev/EAS build + key present) */
export function purchasesAvailable(): boolean {
  return configured
}

/** entitlement id → store plan, strongest wins */
export function planFromEntitlements(active: Record<string, unknown>): Plan {
  if (active.studio) return 'studio'
  if (active.pro) return 'pro'
  if (active.creator) return 'creator'
  return 'free'
}

export function syncPlanFromCustomerInfo(info: CustomerInfo, setPlan: (p: Plan) => void) {
  const active = info?.entitlements?.active ?? {}
  setPlan(planFromEntitlements(active))
}

/** configure RevenueCat and start listening for entitlement changes.
 *  Safe to call unconditionally — no-ops without the module or a key. */
export function initPurchases(onCustomerInfo: (info: CustomerInfo) => void) {
  const mod = loadModule()
  const key = apiKey()
  if (!mod || !key || Platform.OS !== 'ios') return
  try {
    mod.configure({ apiKey: key })
    configured = true
    mod.addCustomerInfoUpdateListener(onCustomerInfo)
    mod.getCustomerInfo().then(onCustomerInfo).catch(() => {})
  } catch {
    configured = false
  }
}

/** current offering's packages, or null in demo mode */
export async function getPackages(): Promise<PurchasesPackage[] | null> {
  if (!configured || !Purchases) return null
  try {
    const offerings = await Purchases.getOfferings()
    return offerings?.current?.availablePackages ?? null
  } catch {
    return null
  }
}

export type PurchaseOutcome =
  | { ok: true; plan: Plan }
  | { ok: false; reason: 'cancelled' | 'unavailable' | 'error' }

export async function purchase(pkg: PurchasesPackage): Promise<PurchaseOutcome> {
  if (!configured || !Purchases) return { ok: false, reason: 'unavailable' }
  try {
    const { customerInfo } = await Purchases.purchasePackage(pkg)
    return { ok: true, plan: planFromEntitlements(customerInfo?.entitlements?.active ?? {}) }
  } catch (e) {
    const cancelled = (e as { userCancelled?: boolean })?.userCancelled
    return { ok: false, reason: cancelled ? 'cancelled' : 'error' }
  }
}

export async function restore(): Promise<Plan | null> {
  if (!configured || !Purchases) return null
  try {
    const info = await Purchases.restorePurchases()
    return planFromEntitlements(info?.entitlements?.active ?? {})
  } catch {
    return null
  }
}
