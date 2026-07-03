import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { CAMERA_STYLES } from '../lib/styles'
import { FREE_CREDITS, useApp } from '../lib/store'
import sampleGolden from '../assets/sample-golden.svg'

export default function Dashboard() {
  const {
    user,
    plan,
    isPaid,
    creditsLeft,
    history,
    removeHistory,
    presets,
    removePreset,
    favorites,
    toggleFavorite,
    setAuthOpen,
    signOut,
    selectStyle,
  } = useApp()

  const favStyles = CAMERA_STYLES.filter((s) => favorites.includes(s.id))
  const usedPct = isPaid ? 100 : ((FREE_CREDITS - creditsLeft) / FREE_CREDITS) * 100

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-10 sm:py-14 pb-28">
      {/* header */}
      <div className="flex flex-wrap items-center justify-between gap-4 mb-10">
        <div>
          <p className="text-xs font-bold uppercase tracking-widest text-violet mb-1.5">Your library</p>
          <h1 className="font-display text-3xl sm:text-4xl font-semibold tracking-tight">
            {user ? `Welcome back, ${user.name}.` : 'Your darkroom.'}
          </h1>
        </div>
        <div className="flex items-center gap-2">
          {!user && (
            <button onClick={() => setAuthOpen(true)} className="pill-base pill-ghost px-5 py-2.5 text-sm">
              Sign in to sync
            </button>
          )}
          {user && (
            <button onClick={signOut} className="pill-base pill-ghost px-5 py-2.5 text-sm">
              Sign out
            </button>
          )}
          <Link to="/studio" className="pill-base pill-violet px-5 py-2.5 text-sm">
            New shot
          </Link>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_320px] gap-6 items-start">
        <div className="space-y-6 min-w-0">
          {/* recent transformations */}
          <section className="card p-6">
            <h2 className="font-display text-lg font-semibold mb-4">Recent transformations</h2>
            {history.length === 0 ? (
              <div className="text-center py-12">
                <div className="text-4xl mb-3">🎞️</div>
                <p className="text-fog text-sm mb-5">
                  Nothing developed yet. Your first roll is on the house.
                </p>
                <Link to="/studio" className="pill-base pill-primary px-6 py-2.5 text-sm">
                  Shoot your first mood
                </Link>
              </div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                {history.map((h, i) => (
                  <motion.div
                    key={h.id}
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ delay: i * 0.04 }}
                    className="group relative rounded-2xl overflow-hidden bg-mist aspect-4/5"
                  >
                    <img src={h.thumb} alt={h.styleName} className="w-full h-full object-cover" />
                    <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-ink/75 to-transparent p-2.5 pt-8">
                      <p className="text-paper text-[12px] font-semibold leading-tight">{h.styleName}</p>
                      <p className="text-paper/60 text-[10px]">
                        {new Date(h.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                      </p>
                    </div>
                    <button
                      onClick={() => removeHistory(h.id)}
                      aria-label="Delete"
                      className="absolute top-2 right-2 w-7 h-7 rounded-full bg-ink/40 text-paper/90 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center hover:bg-red-500"
                    >
                      <svg viewBox="0 0 20 20" className="w-3.5 h-3.5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <path d="M6 6l8 8M14 6l-8 8" />
                      </svg>
                    </button>
                  </motion.div>
                ))}
              </div>
            )}
          </section>

          {/* saved presets */}
          <section className="card p-6">
            <h2 className="font-display text-lg font-semibold mb-4">Saved presets</h2>
            {presets.length === 0 ? (
              <p className="text-fog text-sm">
                Fine-tune a look in the studio and hit “Save preset” — it lands here.
              </p>
            ) : (
              <ul className="divide-y divide-cloud">
                {presets.map((p) => (
                  <li key={p.id} className="flex items-center justify-between gap-3 py-3">
                    <div>
                      <p className="text-sm font-semibold">{p.name}</p>
                      <p className="text-[12px] text-fog">
                        intensity {p.params.intensity} · grain {p.params.grain} · warmth {p.params.warmth}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Link
                        to="/studio"
                        onClick={() => selectStyle(p.styleId, p.params)}
                        className="pill-base pill-ghost px-4 py-1.5 text-[12px]"
                      >
                        Use
                      </Link>
                      <button
                        onClick={() => removePreset(p.id)}
                        className="text-[12px] font-medium text-fog hover:text-red-500 transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* favorite styles */}
          <section className="card p-6">
            <h2 className="font-display text-lg font-semibold mb-4">Favorite camera styles</h2>
            {favStyles.length === 0 ? (
              <p className="text-fog text-sm">
                Tap the ♥ on any style card in the studio to keep your go-to moods here.
              </p>
            ) : (
              <div className="flex flex-wrap gap-2.5">
                {favStyles.map((s) => (
                  <span key={s.id} className="inline-flex items-center gap-2 bg-mist rounded-full pl-3 pr-1.5 py-1.5 text-[13px] font-semibold">
                    <span className="w-2.5 h-2.5 rounded-full" style={{ background: s.gradient }} />
                    {s.name}
                    <Link to={`/studio?style=${s.id}`} className="bg-paper rounded-full px-2.5 py-1 text-[11px] shadow-sm hover:shadow transition-shadow">
                      Shoot
                    </Link>
                    <button
                      onClick={() => toggleFavorite(s.id)}
                      aria-label={`Remove ${s.name} from favorites`}
                      className="w-6 h-6 rounded-full text-fog hover:text-red-500 flex items-center justify-center"
                    >
                      <svg viewBox="0 0 20 20" className="w-3 h-3" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <path d="M6 6l8 8M14 6l-8 8" />
                      </svg>
                    </button>
                  </span>
                ))}
              </div>
            )}
          </section>
        </div>

        {/* side rail */}
        <div className="space-y-6 lg:sticky lg:top-20">
          {/* credits */}
          <section className="card p-6">
            <h2 className="font-display text-lg font-semibold mb-4">
              {isPaid ? 'Your plan' : 'Free shots'}
            </h2>
            {isPaid ? (
              <div className="flex items-center gap-3">
                <span className="text-3xl">♾️</span>
                <div>
                  <p className="text-sm font-bold capitalize">{plan} plan</p>
                  <p className="text-[12px] text-fog">Unlimited developments</p>
                </div>
              </div>
            ) : (
              <>
                <div className="flex items-end justify-between mb-2">
                  <span className="font-display text-4xl font-semibold">{creditsLeft}</span>
                  <span className="text-[12px] text-fog mb-1">of {FREE_CREDITS} left this month</span>
                </div>
                <div className="h-2 rounded-full bg-mist overflow-hidden mb-5">
                  <div
                    className="h-full rounded-full bg-gradient-to-r from-violet to-[#b264ff] transition-all duration-500"
                    style={{ width: `${100 - usedPct}%` }}
                  />
                </div>
                <Link to="/pricing" className="pill-base pill-violet w-full px-5 py-3 text-sm">
                  Upgrade — unlimited from $7
                </Link>
              </>
            )}
          </section>

          {/* weekly mood */}
          <section className="relative overflow-hidden rounded-3xl bg-[#0d0d12] text-paper p-6">
            <div className="absolute -top-10 -right-10 w-40 h-40 rounded-full bg-violet/30 blur-2xl" />
            <p className="text-[11px] font-bold uppercase tracking-widest text-[#a88bff] mb-2">This week’s mood</p>
            <h3 className="font-display text-xl font-semibold mb-3">A24 Movie Still</h3>
            <img
              src={sampleGolden}
              alt=""
              className="rounded-xl aspect-video object-cover w-full mb-4"
              style={{ filter: 'saturate(0.72) contrast(1.05) brightness(0.98)' }}
            />
            <Link to="/studio?style=a24-still" className="pill-base bg-paper text-ink w-full px-5 py-2.5 text-sm font-semibold">
              Shoot it
            </Link>
          </section>
        </div>
      </div>
    </main>
  )
}
