import { isNative } from './native'
import type { Plan } from './store'

/**
 * Purchases — platform-aware subscription layer.
 *
 * App Store guideline 3.1.1: digital subscriptions unlocked inside the iOS
 * app MUST go through Apple In-App Purchase — no web checkout, no link-outs.
 * This module is the single seam: the web build keeps the demo checkout,
 * the native build routes through StoreKit.
 *
 * Product IDs registered in App Store Connect (auto-renewable, group
 * "LensMood Membership"):
 */
export const IAP_PRODUCTS: Record<Exclude<Plan, 'free'>, string> = {
  creator: 'app.lensmood.ios.creator.monthly',
  pro: 'app.lensmood.ios.pro.monthly',
  studio: 'app.lensmood.ios.studio.monthly',
}

export type PurchaseResult =
  | { ok: true; plan: Exclude<Plan, 'free'> }
  | { ok: false; reason: 'cancelled' | 'unavailable' | 'failed' }

/** true when checkout must go through Apple IAP instead of the web flow */
export const requiresAppStoreBilling = (): boolean => isNative()

/**
 * Native purchase entry point. Wired for a StoreKit bridge (RevenueCat or
 * capacitor-subscriptions); until the bridge ships in the binary this
 * resolves 'unavailable' so the UI can explain rather than dead-end.
 */
export async function purchaseNative(plan: Exclude<Plan, 'free'>): Promise<PurchaseResult> {
  const bridge = (window as unknown as { LensMoodIAP?: { purchase(id: string): Promise<boolean> } })
    .LensMoodIAP
  if (!bridge) return { ok: false, reason: 'unavailable' }
  try {
    const done = await bridge.purchase(IAP_PRODUCTS[plan])
    return done ? { ok: true, plan } : { ok: false, reason: 'cancelled' }
  } catch {
    return { ok: false, reason: 'failed' }
  }
}

/** App Review requires a visible Restore Purchases affordance wherever IAP is sold */
export async function restorePurchases(): Promise<Exclude<Plan, 'free'> | null> {
  const bridge = (
    window as unknown as { LensMoodIAP?: { restore(): Promise<string | null> } }
  ).LensMoodIAP
  if (!bridge) return null
  try {
    const productId = await bridge.restore()
    const entry = Object.entries(IAP_PRODUCTS).find(([, id]) => id === productId)
    return (entry?.[0] as Exclude<Plan, 'free'>) ?? null
  } catch {
    return null
  }
}
