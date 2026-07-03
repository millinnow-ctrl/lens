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
        <p className="label-mono mb-3">Pricing</p>
        <h1 className="type-display text-4xl sm:text-6xl mb-4">Rent the camera bag.</h1>
        <p className="text-ink-soft">
          Every plan is month-to-month. Cancel whenever — your photos keep the mood forever.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 border border-hairline bg-surface">
        {TIERS.map((tier, i) => {
          const current = isCurrent(tier)
          return (
            <motion.div
              key={tier.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15, ease: 'easeOut', delay: i * 0.05 }}
              className={`relative flex flex-col p-6 border-hairline border-t first:border-t-0 lg:border-t-0 lg:border-l lg:first:border-l-0 ${
                tier.highlight ? 'bg-ink text-paper' : ''
              }`}
            >
              {/* reserved badge slot keeps titles/prices on shared baselines */}
              <div className="h-5 mb-4">
                {tier.highlight && (
                  <span className="inline-flex items-center font-mono text-[10px] font-semibold tracking-[0.1em] uppercase px-1.5 py-0.5 rounded-xs border border-paper/70 text-paper">
                    Most popular
                  </span>
                )}
              </div>
              <h2 className="font-sans font-semibold text-[16px]">{tier.name}</h2>
              <p className={`text-[13px] mb-5 ${tier.highlight ? 'text-paper/60' : 'text-fog'}`}>
                {tier.blurb}
              </p>
              <p className="mb-6">
                <span className="font-mono text-4xl tabular-nums">${tier.price}</span>
                <span className={`text-[13px] ${tier.highlight ? 'text-paper/60' : 'text-fog'}`}>
                  /month
                </span>
              </p>
              <ul className="mb-7 flex-1 divide-y divide-hairline/60 border-y border-hairline/60">
                {tier.features.map((f) => {
                  const caveat = f.toLowerCase().includes('watermark included') || f.includes('” watermark')
                  return (
                    <li key={f} className="flex items-start gap-2.5 text-[13px] py-2">
                      {caveat ? (
                        <span className={`mt-px shrink-0 font-mono text-[12px] leading-none ${tier.highlight ? 'text-paper/50' : 'text-fog'}`}>
                          —
                        </span>
                      ) : (
                        <IconCheck
                          size={13}
                          className={`mt-0.5 shrink-0 ${tier.highlight ? 'text-paper' : 'text-ink'}`}
                        />
                      )}
                      <span className={tier.highlight ? 'text-paper/85' : 'text-ink-soft'}>{f}</span>
                    </li>
                  )
                })}
              </ul>
              <button
                onClick={() => choose(tier)}
                disabled={current}
                className={`btn w-full ${
                  current
                    ? tier.highlight
                      ? 'border border-paper/50 text-paper/60 cursor-default'
                      : 'btn-outline'
                    : tier.highlight
                      ? 'bg-paper text-ink hover:bg-white'
                      : 'btn-primary'
                }`}
              >
                {current ? 'Current plan' : tier.cta}
              </button>
            </motion.div>
          )
        })}
      </div>

      <p className="text-[13px] text-fog mt-8">
        Prices in USD. This is a demo — checkout is simulated and no card is ever asked for.
      </p>

      {/* mock checkout */}
      <Modal open={!!checkout} onClose={() => setCheckout(null)}>
        <div className="p-8">
          {!done ? (
            <>
              <p className="label-mono mb-3">Checkout</p>
              <h3 className="type-display text-2xl mb-2">
                {checkout?.name} —{' '}
                <span className="font-mono tabular-nums">${checkout?.price}</span>/mo
              </h3>
              <p className="text-[13px] text-fog mb-6">
                Demo checkout: one click, no card. In production this is where Stripe takes the
                wheel.
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
              <div className="w-12 h-12 mb-4 rounded-xs border border-signal text-signal flex items-center justify-center">
                <IconCheck size={28} />
              </div>
              <h3 className="type-display text-2xl mb-2">Welcome to {checkout?.name}</h3>
              <p className="text-[13px] text-fog mb-6">
                Watermarks off. Premium moods unlocked.
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
