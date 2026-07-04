import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { IconCheck, IconClose, IconFilm, IconTrash } from '../components/icons'
import { loadImage, renderStyled } from '../lib/engine'
import { CAMERA_STYLES, getStyle } from '../lib/styles'
import { FREE_CREDITS, useApp } from '../lib/store'
import sampleFriends from '../assets/sample-friends.jpg'

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
    setPendingPreset,
    tried,
  } = useApp()

  const favStyles = CAMERA_STYLES.filter((s) => favorites.includes(s.id))
  const usedPct = isPaid ? 100 : ((FREE_CREDITS - creditsLeft) / FREE_CREDITS) * 100

  // the featured card shows the real Tokyo Neon grade, developed by the engine
  const [featuredThumb, setFeaturedThumb] = useState<string | null>(null)
  useEffect(() => {
    let cancelled = false
    loadImage(sampleFriends).then((img) => {
      if (cancelled) return
      const neon = getStyle('tokyo-neon')!
      const canvas = renderStyled(img, neon, neon.defaults, { maxSize: 560 })
      setFeaturedThumb(canvas.toDataURL('image/jpeg', 0.8))
    })
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <main className="max-w-7xl mx-auto px-4 sm:px-6 py-12 sm:py-16 pb-28">
      {/* header */}
      <div className="flex flex-wrap items-end justify-between gap-4 mb-12 pb-8 border-b border-hairline">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-violet mb-3">
            Your library
          </p>
          <h1 className="type-display tracking-optical-lg text-3xl sm:text-5xl">
            {user ? `Welcome back, ${user.name}.` : 'Your darkroom.'}
          </h1>
        </div>
        <div className="flex items-center gap-2">
          {!user && (
            <button onClick={() => setAuthOpen(true)} className="btn btn-outline">
              Sign in to sync
            </button>
          )}
          {user && (
            <button onClick={signOut} className="btn btn-quiet">
              Sign out
            </button>
          )}
          <Link to="/studio" className="btn btn-primary">
            New shot
          </Link>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_320px] gap-6 lg:gap-8 items-start">
        <div className="space-y-8 min-w-0">
          {/* recent transformations — contact sheet */}
          <section>
            <div className="flex items-baseline justify-between gap-3 mb-4 px-0.5">
              <h2 className="font-sans font-semibold text-[16px] tracking-[-0.01em]">Contact sheet</h2>
              {history.length > 0 && (
                <span className="value-mono uppercase tracking-[0.08em]">
                  {String(history.length).padStart(2, '0')} {history.length === 1 ? 'frame' : 'frames'}
                </span>
              )}
            </div>
            {history.length === 0 ? (
              <div className="panel p-8 sm:p-10">
                <IconFilm size={24} className="text-violet mb-4" />
                <p className="text-fog text-sm mb-5">
                  Nothing developed yet. Your first roll is on the house.
                </p>
                <Link to="/studio" className="btn btn-primary">
                  Shoot your first mood
                </Link>
              </div>
            ) : (
              <div className="bg-vf rounded-[24px] p-4 sm:p-5 shadow-[inset_0_1px_0_rgb(255_255_255/0.07),0_2px_12px_rgb(23_19_31/0.10)]">
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
                  {history.map((h, i) => (
                    <motion.div
                      key={h.id}
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ duration: 0.15, ease: 'easeOut', delay: i * 0.03 }}
                      className="group relative"
                    >
                      <div className="relative overflow-hidden rounded-[12px] aspect-4/5 bg-elevated">
                        <img src={h.thumb} alt={h.styleName} className="w-full h-full object-cover" />
                        <button
                          onClick={() => removeHistory(h.id)}
                          aria-label="Delete"
                          className="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-vf/75 border border-white/25 text-paper opacity-0 group-hover:opacity-100 hover:border-signal hover:text-signal transition-opacity flex items-center justify-center"
                        >
                          <IconTrash size={12} />
                        </button>
                      </div>
                      <div className="mt-1.5 flex items-baseline justify-between gap-2 font-mono text-[10px] tracking-[0.08em] uppercase text-vf-chrome tabular-nums">
                        <span className="truncate">
                          {String(i + 1).padStart(2, '0')} · {h.styleName}
                        </span>
                        <span className="tabular-nums shrink-0">
                          {new Date(h.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                        </span>
                      </div>
                    </motion.div>
                  ))}
                  {/* ghost frames fill out the sheet */}
                  {history.length < 4 &&
                    Array.from({ length: 4 - history.length }).map((_, i) => (
                      <div key={`ghost-${i}`} aria-hidden>
                        {/* an unexposed film frame — solid cell, not a dashed drop-zone */}
                        <div className="rounded-[12px] aspect-4/5 bg-[#100c17] shadow-[inset_0_0_0_1px_rgb(255_255_255/0.04),inset_0_1px_10px_rgb(0_0_0/0.5)]" />
                        <p className="mt-1.5 font-mono text-[10px] tracking-[0.08em] uppercase text-white/20 tabular-nums">
                          {String(history.length + i + 1).padStart(2, '0')} · —
                        </p>
                      </div>
                    ))}
                </div>
              </div>
            )}
          </section>

          {/* saved presets */}
          <section className="panel p-6 sm:p-7">
            <h2 className="font-sans font-semibold text-[16px] tracking-[-0.01em] mb-5">Saved presets</h2>
            {presets.length === 0 ? (
              <div>
                <div className="border border-dashed border-hairline rounded-[14px] px-4 py-3 mb-3 font-mono text-[11px] tracking-[0.1em] uppercase text-fog">
                  Preset·00 — empty slot
                </div>
                <p className="text-fog text-sm">
                  Fine-tune a look in the studio and hit “Save preset” — it lands here.{' '}
                  <Link to="/studio" className="text-ink underline underline-offset-3">
                    Open studio
                  </Link>
                </p>
              </div>
            ) : (
              <ul className="divide-y divide-hairline border-t border-hairline">
                {presets.map((p) => (
                  <li key={p.id} className="flex items-center justify-between gap-3 py-3">
                    <div className="min-w-0">
                      <p className="font-sans font-semibold text-[14px] truncate">{p.name}</p>
                      <p className="value-mono uppercase">
                        INT {p.params.intensity} · GRN {p.params.grain} · WRM {p.params.warmth}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <Link
                        to="/studio"
                        onClick={() => setPendingPreset(p)}
                        className="btn btn-sm btn-outline"
                      >
                        Use
                      </Link>
                      <button
                        onClick={() => removePreset(p.id)}
                        className="btn btn-sm btn-quiet text-[12px]"
                      >
                        Delete
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* the case — full mood collection */}
          <section className="panel p-6 sm:p-7">
            <div className="flex items-baseline justify-between mb-5">
              <h2 className="font-sans font-semibold text-[16px] tracking-[-0.01em]">The case</h2>
              <span className="value-mono uppercase tracking-[0.08em] tabular-nums">
                {tried.length}/{CAMERA_STYLES.length} stocks shot
              </span>
            </div>
            <div className="grid grid-cols-3 sm:grid-cols-6 gap-3">
              {CAMERA_STYLES.map((s, i) => {
                const shot = tried.includes(s.id)
                const thumb = history.find((h) => h.styleId === s.id)?.thumb
                return (
                  <Link
                    key={s.id}
                    to={`/studio?style=${s.id}`}
                    className={`relative aspect-4/5 rounded-[14px] overflow-hidden border transition-colors ${
                      shot
                        ? 'border-ink/10 shadow-[0_2px_8px_rgb(23_19_31/0.06)]'
                        : 'border-dashed border-hairline hover:border-violet/50'
                    }`}
                  >
                    {shot && thumb ? (
                      <>
                        <img src={thumb} alt={s.name} className="w-full h-full object-cover" />
                        <span className="absolute inset-x-0 bottom-0 h-[42%] bg-gradient-to-t from-black/65 to-transparent" />
                        <span className="absolute bottom-1.5 inset-x-1.5 text-[10px] font-medium text-white leading-tight line-clamp-1">
                          {s.name}
                        </span>
                        <span className="absolute top-1.5 right-1.5 w-[18px] h-[18px] rounded-full bg-violet text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.35),0_1px_3px_rgb(23_19_31/0.35)] flex items-center justify-center">
                          <IconCheck size={10} />
                        </span>
                      </>
                    ) : shot ? (
                      <span className="absolute inset-0 bg-violet/10 flex items-center justify-center">
                        <span className="w-[18px] h-[18px] rounded-full bg-violet text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.35),0_1px_3px_rgb(23_19_31/0.35)] flex items-center justify-center">
                          <IconCheck size={10} />
                        </span>
                      </span>
                    ) : null}
                    <span
                      className={`absolute top-1.5 left-1.5 font-mono text-[9px] tracking-[0.08em] tabular-nums ${
                        shot
                          ? 'text-white bg-vf/60 px-1.5 py-0.5 rounded-full shadow-[inset_0_1px_0_rgb(255_255_255/0.12)]'
                          : 'text-fog'
                      }`}
                    >
                      LM·{String(i + 1).padStart(2, '0')}
                    </span>
                    {!shot && s.tier === 'premium' && (
                      <span className="absolute top-1.5 right-1.5 tag text-[8px]">PRO</span>
                    )}
                    {!shot && (
                      <span className="absolute bottom-1.5 inset-x-1.5 text-[10px] text-fog leading-tight line-clamp-2">
                        {s.name}
                      </span>
                    )}
                  </Link>
                )
              })}
            </div>
            <p className="text-fog text-[12px] mt-4">
              {tried.length === CAMERA_STYLES.length
                ? 'Full case. Every stock, shot.'
                : 'The case doesn’t fill itself.'}
            </p>
          </section>

          {/* favorite styles */}
          <section className="panel p-6 sm:p-7">
            <h2 className="font-sans font-semibold text-[16px] tracking-[-0.01em] mb-5">Favorite camera styles</h2>
            {favStyles.length === 0 ? (
              <p className="text-fog text-sm">
                Tap the heart on any style card in the studio to keep your go-to moods here.
              </p>
            ) : (
              <div className="flex flex-wrap gap-2.5">
                {favStyles.map((s) => (
                  <span
                    key={s.id}
                    className="inline-flex items-center gap-2.5 rounded-full border border-ink/10 bg-surface px-3.5 py-2 shadow-[0_1px_4px_rgb(23_19_31/0.04)]"
                  >
                    <span className="w-2 h-2 rounded-full shrink-0" style={{ background: s.gradient }} />
                    <span className="font-sans font-semibold text-[13px]">{s.name}</span>
                    <Link
                      to={`/studio?style=${s.id}`}
                      className="text-[12px] font-medium text-ink-soft hover:text-ink hover:underline underline-offset-2"
                    >
                      Shoot
                    </Link>
                    <button
                      onClick={() => toggleFavorite(s.id)}
                      aria-label={`Remove ${s.name} from favorites`}
                      className="w-5 h-5 flex items-center justify-center text-fog hover:text-signal transition-colors"
                    >
                      <IconClose size={12} />
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
          <section className="panel p-6">
            {isPaid ? (
              <>
                <p className="text-[13px] font-semibold text-ink-soft mb-3">Your plan</p>
                <p className="font-sans font-semibold text-[16px] capitalize mb-1">{plan}</p>
                <p className="text-[13px] font-semibold text-violet">Unlimited</p>
              </>
            ) : (
              <>
                <p className="text-[13px] font-semibold text-ink-soft mb-3">Free shots</p>
                <p className="font-sans font-bold text-5xl tracking-[-0.02em] tabular-nums mb-4">
                  {creditsLeft}/{FREE_CREDITS}
                </p>
                <div className="h-1.5 rounded-full bg-ink/[0.06] overflow-hidden mb-5">
                  <div
                    className="h-full rounded-full bg-violet transition-all duration-500"
                    style={{ width: `${100 - usedPct}%` }}
                  />
                </div>
                <Link to="/pricing" className="btn btn-primary w-full">
                  Upgrade
                </Link>
              </>
            )}
          </section>

          {/* weekly mood */}
          <section className="bg-vf rounded-[24px] p-6 shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_2px_12px_rgb(23_19_31/0.1)]">
            <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-orchid mb-2.5">Featured this week</p>
            <h3 className="font-sans font-semibold text-[18px] tracking-[-0.01em] text-paper mb-4">Tokyo Neon</h3>
            <img
              src={featuredThumb ?? sampleFriends}
              alt=""
              className="rounded-[14px] aspect-video object-cover w-full mb-4"
              style={
                featuredThumb
                  ? undefined
                  : { filter: 'saturate(1.35) contrast(1.2) hue-rotate(-10deg) brightness(0.96)' }
              }
            />
            <Link to="/studio?style=tokyo-neon" className="btn w-full bg-white text-paper hover:bg-white/90">
              Shoot it
            </Link>
          </section>
        </div>
      </div>
    </main>
  )
}
