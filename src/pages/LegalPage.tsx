import { Link } from 'react-router-dom'

/**
 * Privacy & Terms — required for the App Store listing and the account
 * flows. Written to match how LensMood actually works: photos never
 * leave the device, and the only stored data is local.
 */

const Section = ({ title, children }: { title: string; children: React.ReactNode }) => (
  <section className="mb-8">
    <h2 className="font-sans font-semibold text-[16px] mb-2">{title}</h2>
    <div className="text-[14px] leading-relaxed text-ink-soft space-y-3">{children}</div>
  </section>
)

export function PrivacyPage() {
  return (
    <main className="max-w-2xl mx-auto px-4 sm:px-6 py-14 pb-28">
      <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3">Privacy</p>
      <h1 className="type-display text-3xl sm:text-4xl mb-2">Your photos stay yours.</h1>
      <p className="text-fog text-[13px] mb-10">Effective July 2026.</p>

      <Section title="Photos and videos">
        <p>
          Everything LensMood does to your photos and clips happens on your device. Files you
          pick are processed in memory, never uploaded, and never seen by us. Exports save
          directly to your library or share sheet.
        </p>
      </Section>
      <Section title="What we store">
        <p>
          Your looks history (including small thumbnails of photos you develop), saved
          presets, streak, and plan live in local storage on your device only. Deleting the
          app — or using “Delete account &amp; data” in the account sheet — removes all of it.
        </p>
      </Section>
      <Section title="What we don't do">
        <p>
          No tracking, no ads, no analytics SDKs, no selling data, no third-party sharing.
          LensMood works offline once installed.
        </p>
      </Section>
      <Section title="Sign in">
        <p>
          Sign in with Apple or Google is used only to identify your account for syncing your
          plan. With Apple you can hide your email; we honor the relay address.
        </p>
      </Section>
      <Section title="Contact">
        <p>
          Questions: <span className="text-ink">privacy@lensmood.app</span>
        </p>
      </Section>
      <Link to="/" className="btn btn-outline">
        Back to LensMood
      </Link>
    </main>
  )
}

export function TermsPage() {
  return (
    <main className="max-w-2xl mx-auto px-4 sm:px-6 py-14 pb-28">
      <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-violet mb-3">Terms</p>
      <h1 className="type-display text-3xl sm:text-4xl mb-2">The short version.</h1>
      <p className="text-fog text-[13px] mb-10">Effective July 2026.</p>

      <Section title="Your content">
        <p>
          Photos in, photos out — they're yours. You keep every right to what you create with
          LensMood, including commercial use on paid plans.
        </p>
      </Section>
      <Section title="Subscriptions">
        <p>
          Plans are month-to-month and renew until cancelled. On iOS, billing runs through your
          Apple ID and is managed in Settings; on the web, from your account. Cancelling keeps
          your plan until the end of the paid period.
        </p>
      </Section>
      <Section title="Fair use">
        <p>
          Don't use LensMood to process content you don't have rights to, or to produce
          unlawful material. Camera look names reference photographic eras and gear culture;
          LensMood is not affiliated with or endorsed by any camera or film brand.
        </p>
      </Section>
      <Section title="The service">
        <p>
          Processing happens on your device; we ship updates that may change or retire looks.
          The service is provided as-is, and our liability is limited to what you paid in the
          last 12 months.
        </p>
      </Section>
      <Link to="/" className="btn btn-outline">
        Back to LensMood
      </Link>
    </main>
  )
}
