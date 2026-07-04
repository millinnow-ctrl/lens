import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from '../components/Modal'
import { IconCheck } from '../components/icons'
import { useApp, type Plan } from '../lib/store'

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
    blurb: 'For trying the vibe on.',
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

  // "Current plan" only makes sense once you actually have an account
  const isCurrent = (tier: Tier) => plan === tier.id && (tier.id !== 'free' || !!user)

  const choose = (tier: Tier) => {
    if (tier.id === 'free') {
      navigate('/studio')
      return
    }
    if (!user) {
      setAuthOpen(true)
      return
    }
    setCheckout(tier)
    setDone(false)
  }

  const confirm = () => {
    if (!checkout) return
    setPlan(checkout.id)
    setDone(true)
  }

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-14 sm:py-20 pb-28">
      <div className="mb-12 max-w-2xl">
        <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3">
          Pricing
        </p>
        <h1 className="type-display text-4xl sm:text-6xl mb-4">
          Rent the <span className="grad-text">camera bag.</span>
        </h1>
        <p className="text-ink-soft">
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
                  ? 'relative z-10 grad-fill rounded-[26px] p-[2px] aura-soft shadow-[0_18px_44px_-14px_rgb(139_92_246/0.45)] lg:scale-[1.04] lg:-translate-y-1.5'
                  : 'relative bg-surface rounded-[24px] border border-ink/5 shadow-[0_2px_12px_rgb(23_19_31/0.05)]'
              }
            >
              <div className="relative flex flex-col h-full p-6 bg-surface rounded-[24px]">
                {/* reserved badge slot keeps titles/prices on shared baselines —
                    only where cards actually sit side by side */}
                <div className={tier.highlight ? 'h-5 mb-4' : 'hidden lg:block h-5 mb-4'}>
                  {tier.highlight && (
                    <span className="inline-flex items-center text-[10px] font-semibold tracking-[0.08em] uppercase px-2.5 py-1 rounded-full grad-fill text-white">
                      Most popular
                    </span>
                  )}
                </div>
                <h2 className="font-sans font-semibold text-[16px]">{tier.name}</h2>
                <p className="text-[13px] mb-5 text-fog">{tier.blurb}</p>
                <p className="mb-6">
                  <span className="text-4xl font-bold tracking-tight tabular-nums">
                    ${tier.price}
                  </span>
                  <span className="text-[13px] text-fog">/month</span>
                </p>
                <ul className="mb-7 flex-1 space-y-2.5">
                  {tier.features.map((f) => {
                    const caveat =
                      f.toLowerCase().includes('watermark included') || f.includes('” watermark')
                    return (
                      <li key={f} className="flex items-start gap-2.5 text-[13px]">
                        {caveat ? (
                          <span className="mt-px shrink-0 text-[12px] leading-none text-fog">
                            —
                          </span>
                        ) : (
                          <IconCheck size={15} className="mt-0.5 shrink-0 text-violet" />
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

      <p className="text-[13px] text-fog mt-8">Prices in USD. Month-to-month, cancel anytime.</p>

      {/* mock checkout */}
      <Modal open={!!checkout} onClose={() => setCheckout(null)}>
        <div className="p-8">
          {!done ? (
            <>
              <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3">
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
