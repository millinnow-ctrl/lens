import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from '../components/Modal'
import AnimatedNumber from '../components/AnimatedNumber'
import { IconCheck } from '../components/icons'
import { useApp, type Plan } from '../lib/store'
import { purchaseNative, requiresAppStoreBilling, restorePurchases } from '../lib/purchases'

interface Tier {
  id: Plan
  name: string
  price: number
  blurb: string
  cta: string
  highlight?: boolean
  features: string[]
}

const TIERS: Tier[] = [
  {
    id: 'free',
    name: 'Free',
    price: 0,
    blurb: 'For the first roll.',
    cta: 'Start free',
    features: [
      '5 developments / month',
      'Standard quality exports',
      'Basic camera styles',
      '“Shot on LensMood” watermark',
    ],
  },
  {
    id: 'creator',
    name: 'Creator',
    price: 7,
    blurb: 'For people who post.',
    cta: 'Go Creator',
    highlight: true,
    features: [
      'Unlimited basic exports',
      'No watermark',
      'All camera styles',
      'Faster generation',
    ],
  },
  {
    id: 'pro',
    name: 'Pro',
    price: 15,
    blurb: 'For the obsessed.',
    cta: 'Go Pro',
    features: [
      'Everything in Creator',
      'HD exports',
      'Premium camera packs',
      'Video support',
      'Batch uploads',
    ],
  },
  {
    id: 'studio',
    name: 'Studio',
    price: 29,
    blurb: 'For brands and small teams.',
    cta: 'Go Studio',
    features: [
      'Everything in Pro',
      'Creator tools for TikTok/Reels',
      'Brand presets',
      'Priority generation',
      'Commercial use',
    ],
  },
]

export default function PricingPage() {
  const { plan, setPlan, user, setAuthOpen } = useApp()
  const navigate = useNavigate()
  const [checkout, setCheckout] = useState<Tier | null>(null)
  const [done, setDone] = useState(false)
  const [restoreMsg, setRestoreMsg] = useState<string | null>(null)
  const appStore = requiresAppStoreBilling()

  // "Current plan" only makes sense once you actually have an account
  const isCurrent = (tier: Tier) => plan === tier.id && (tier.id !== 'free' || !!user)

  const choose = async (tier: Tier) => {
    if (tier.id === 'free') {
      navigate('/studio')
      return
    }
    if (!user) {
      setAuthOpen(true)
      return
    }
    // on iOS, subscriptions must go through Apple In-App Purchase (3.1.1)
    if (appStore) {
      const res = await purchaseNative(tier.id)
      if (res.ok) setPlan(res.plan)
      else if (res.reason === 'unavailable')
        setRestoreMsg('Subscriptions arrive with the App Store release.')
      return
    }
    setCheckout(tier)
    setDone(false)
  }

  const restore = async () => {
    const restored = await restorePurchases()
    if (restored) {
      setPlan(restored)
      setRestoreMsg('Purchases restored.')
    } else {
      setRestoreMsg('Nothing to restore on this Apple ID.')
    }
    setTimeout(() => setRestoreMsg(null), 3000)
  }

  const confirm = () => {
    if (!checkout) return
    setPlan(checkout.id)
    setDone(true)
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-16 sm:py-24 pb-28">
      <div className="mb-14 sm:mb-16 max-w-2xl">
        <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-violet mb-4">
          Membership
        </p>
        <h1 className="type-display tracking-optical-lg text-4xl sm:text-6xl mb-5">
          Rent the camera bag.
        </h1>
        <p className="text-[15px] leading-[1.65] text-ink-soft max-w-md">
          Every plan is month-to-month. What you export is yours to keep.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 items-stretch">
        {TIERS.map((tier, i) => {
          const current = isCurrent(tier)
          return (
            <motion.div
              key={tier.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15, ease: 'easeOut', delay: i * 0.05 }}
              className={
                tier.highlight
                  ? 'relative z-10 bg-surface rounded-[24px] border border-clay/30 shadow-[var(--shadow-e4)] lg:scale-[1.05] lg:-translate-y-3'
                  : 'relative bg-surface rounded-[24px] border border-[rgb(60_42_24/0.1)] shadow-[var(--shadow-e2)]'
              }
            >
              <div className="relative flex flex-col h-full p-6 sm:p-7 bg-surface rounded-[24px]">
                {/* reserved badge slot keeps titles/prices on shared baselines —
                    wherever cards actually sit side by side */}
                <div className={tier.highlight ? 'h-6 mb-5' : 'hidden md:block h-6 mb-5'}>
                  {tier.highlight && (
                    <span className="inline-flex items-center gap-1.5 text-[10px] font-semibold tracking-[0.1em] uppercase px-2.5 py-1 rounded-full bg-clay text-white shadow-[0_2px_6px_rgb(60_20_10/0.3)]">
                      <span className="w-1 h-1 rounded-full bg-white/90" aria-hidden />
                      The working roll
                    </span>
                  )}
                </div>
                <h2 className="font-sans font-semibold text-[17px] tracking-[-0.01em]">{tier.name}</h2>
                <p className="font-mono font-semibold text-[10px] tracking-[0.1em] text-fog tnum mt-1">
                  LM·MEMBER · TIER 0{i + 1}
                </p>
                <p className="text-[13px] leading-relaxed mt-2.5 mb-6 text-fog">{tier.blurb}</p>
                <p className="mb-7 flex items-baseline gap-1">
                  <AnimatedNumber
                    value={tier.price}
                    format={(n) => `$${Math.round(n)}`}
                    className="text-[40px] leading-none font-bold tracking-[-0.02em]"
                  />
                  <span className="text-[13px] text-fog">/month</span>
                </p>
                <ul className="mb-8 flex-1 space-y-3">
                  {tier.features.map((f) => {
                    const caveat =
                      f.toLowerCase().includes('watermark included') || f.includes('” watermark')
                    return (
                      <li key={f} className="flex items-start gap-2.5 text-[13px] leading-snug">
                        {caveat ? (
                          <span className="mt-0.5 shrink-0 w-[15px] text-center text-[13px] leading-none text-fog">
                            —
                          </span>
                        ) : (
                          <IconCheck size={15} className="mt-px shrink-0 text-ink" />
                        )}
                        <span className="text-ink-soft">{f}</span>
                      </li>
                    )
                  })}
                </ul>
                <button
                  onClick={() => choose(tier)}
                  disabled={current}
                  className={`btn w-full ${
                    current ? 'btn-outline' : tier.highlight ? 'btn-primary' : 'btn-outline'
                  }`}
                >
                  {current ? 'Current plan' : tier.cta}
                </button>
              </div>
            </motion.div>
          )
        })}
      </div>

      {/* what every plan includes — fills the shelf + reinforces the "case" metaphor */}
      <div className="mt-10 grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[
          { k: '18', l: 'cameras in the case' },
          { k: 'On-device', l: 'nothing is uploaded' },
          { k: 'Unlimited', l: 're-develops per shot' },
          { k: 'No lock-in', l: 'cancel any month' },
        ].map((s) => (
          <div key={s.l} className="panel px-4 py-4">
            <p className="font-mono text-[12px] tracking-[0.12em] uppercase text-clay tabular-nums">{s.k}</p>
            <p className="text-[13px] text-ink-soft mt-1 leading-snug">{s.l}</p>
          </div>
        ))}
      </div>

      <div className="mt-8 flex flex-wrap items-center gap-x-5 gap-y-2">
        <p className="text-[13px] text-fog">
          {appStore
            ? 'Billed through your Apple ID. Manage or cancel in Settings.'
            : 'Prices in USD. Month-to-month, cancel anytime.'}
        </p>
        {appStore && (
          <button onClick={restore} className="text-[13px] font-semibold text-violet">
            Restore purchases
          </button>
        )}
        {restoreMsg && <p className="text-[13px] font-semibold text-ink-soft">{restoreMsg}</p>}
      </div>

      {/* mock checkout */}
      <Modal open={!!checkout} onClose={() => setCheckout(null)}>
        <div className="p-8">
          {!done ? (
            <>
              <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-violet mb-3">
                Checkout
              </p>
              <h3 className="type-display text-2xl mb-2">
                {checkout?.name} — <span className="tabular-nums">${checkout?.price}</span>/mo
              </h3>
              <p className="text-[13px] text-fog mb-6">
                Demo checkout. One click, no card, nothing charged.
              </p>
              <button onClick={confirm} className="btn btn-primary w-full mb-2.5">
                Confirm upgrade
              </button>
              <button onClick={() => setCheckout(null)} className="btn btn-quiet w-full">
                Cancel
              </button>
            </>
          ) : (
            <>
              <div className="w-12 h-12 mb-4 rounded-full bg-violet/10 text-violet flex items-center justify-center">
                <IconCheck size={28} />
              </div>
              <h3 className="type-display text-2xl mb-2">Welcome to {checkout?.name}</h3>
              <p className="text-[13px] text-fog mb-6">
                Watermarks off. The whole case is yours.
              </p>
              <button
                onClick={() => {
                  setCheckout(null)
                  navigate('/studio')
                }}
                className="btn btn-primary w-full"
              >
                Open the studio
              </button>
            </>
          )}
        </div>
      </Modal>
    </main>
  )
}
