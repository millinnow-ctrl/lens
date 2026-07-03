import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import Modal from '../components/Modal'
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
      '5 transformations / month',
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
    blurb: 'For brands & creators at scale.',
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
      <div className="text-center mb-12">
        <p className="text-xs font-bold uppercase tracking-widest text-violet mb-2">Pricing</p>
        <h1 className="font-display text-4xl sm:text-6xl font-semibold tracking-tight mb-4">
          Rent the camera bag.
        </h1>
        <p className="text-fog max-w-xl mx-auto">
          Every plan is month-to-month. Cancel whenever — your photos keep the mood forever.
        </p>
      </div>

      <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4 items-stretch">
        {TIERS.map((tier, i) => {
          const current = plan === tier.id
          return (
            <motion.div
              key={tier.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.07 }}
              className={`relative flex flex-col rounded-3xl p-6 ${
                tier.highlight
                  ? 'bg-ink text-paper shadow-2xl ring-1 ring-ink xl:-translate-y-3'
                  : 'card'
              }`}
            >
              {tier.highlight && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 text-[11px] font-bold uppercase tracking-wide bg-violet text-paper px-3 py-1 rounded-full whitespace-nowrap">
                  Most popular
                </span>
              )}
              <h2 className={`font-display text-xl font-semibold ${tier.highlight ? '' : 'text-ink'}`}>
                {tier.name}
              </h2>
              <p className={`text-[13px] mb-4 ${tier.highlight ? 'text-paper/60' : 'text-fog'}`}>
                {tier.blurb}
              </p>
              <p className="mb-5">
                <span className="font-display text-4xl font-semibold">${tier.price}</span>
                <span className={`text-sm ${tier.highlight ? 'text-paper/60' : 'text-fog'}`}>/month</span>
              </p>
              <ul className="space-y-2.5 mb-7 flex-1">
                {tier.features.map((f) => (
                  <li key={f} className="flex items-start gap-2.5 text-[13.5px]">
                    <svg viewBox="0 0 16 16" className={`w-4 h-4 mt-0.5 shrink-0 ${tier.highlight ? 'text-[#a88bff]' : 'text-violet'}`} fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M3 8.5l3.5 3.5L13 5" />
                    </svg>
                    <span className={tier.highlight ? 'text-paper/85' : 'text-ink-soft'}>{f}</span>
                  </li>
                ))}
              </ul>
              <button
                onClick={() => choose(tier)}
                disabled={current}
                className={`pill-base w-full px-5 py-3 text-sm ${
                  current
                    ? 'bg-cloud text-fog cursor-default'
                    : tier.highlight
                      ? 'pill-violet'
                      : 'pill-primary'
                }`}
              >
                {current ? '✓ Current plan' : tier.cta}
              </button>
            </motion.div>
          )
        })}
      </div>

      <p className="text-center text-[13px] text-fog mt-10">
        Prices in USD. This is a demo — checkout is simulated and no card is ever asked for.
      </p>

      {/* mock checkout */}
      <Modal open={!!checkout} onClose={() => setCheckout(null)}>
        <div className="p-8 text-center">
          {!done ? (
            <>
              <div className="text-4xl mb-3">🛒</div>
              <h3 className="font-display text-2xl font-semibold mb-2">
                {checkout?.name} — ${checkout?.price}/mo
              </h3>
              <p className="text-sm text-fog mb-6">
                Demo checkout: one click, no card. In production this is where Stripe takes the
                wheel.
              </p>
              <button onClick={confirm} className="w-full pill-base pill-violet px-5 py-3 text-sm mb-2.5">
                Confirm upgrade
              </button>
              <button onClick={() => setCheckout(null)} className="w-full text-[13px] font-medium text-fog hover:text-ink py-2 transition-colors">
                Cancel
              </button>
            </>
          ) : (
            <>
              <motion.div initial={{ scale: 0 }} animate={{ scale: 1 }} transition={{ type: 'spring', stiffness: 300, damping: 18 }} className="text-5xl mb-3">
                🎉
              </motion.div>
              <h3 className="font-display text-2xl font-semibold mb-2">Welcome to {checkout?.name}</h3>
              <p className="text-sm text-fog mb-6">
                Watermarks off. Premium moods unlocked. Go make something worth posting.
              </p>
              <button
                onClick={() => {
                  setCheckout(null)
                  navigate('/studio')
                }}
                className="w-full pill-base pill-primary px-5 py-3 text-sm"
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
