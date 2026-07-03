import { Link } from 'react-router-dom'
import Logo from './Logo'

export default function Footer() {
  return (
    <footer className="border-t border-hairline mt-24 pb-24 md:pb-10 bg-paper">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-12 grid gap-10 md:grid-cols-[1fr_auto_auto_auto]">
        <div className="max-w-xs">
          <Logo />
          <p className="mt-4 text-[13px] text-ink-soft leading-relaxed">
            The AI aesthetic camera. Recreate the lighting, grain, and mood of iconic cameras —
            from any photo, on your device.
          </p>
        </div>
        {[
          {
            title: 'Product',
            links: [
              { label: 'Studio', to: '/studio' },
              { label: 'Camera moods', to: '/#styles' },
              { label: 'Pricing', to: '/pricing' },
            ],
          },
          {
            title: 'Account',
            links: [
              { label: 'Library', to: '/dashboard' },
              { label: 'Upgrade', to: '/pricing' },
            ],
          },
          {
            title: 'Social',
            links: [
              { label: 'TikTok', to: '#' },
              { label: 'Instagram', to: '#' },
              { label: 'X', to: '#' },
            ],
          },
        ].map((col) => (
          <div key={col.title}>
            <h4 className="label-mono mb-4">{col.title}</h4>
            <ul className="space-y-2.5 text-[13px]">
              {col.links.map((l) => (
                <li key={l.label}>
                  <Link
                    to={l.to}
                    className="text-ink-soft hover:text-ink hover:underline underline-offset-3 transition-colors"
                  >
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 pt-6 border-t border-hairline flex items-center justify-between font-mono text-[11px] tracking-[0.06em] text-fog">
        <span>© 2026 LENSMOOD</span>
        <span className="tabular-nums">f/1.4 · ISO 400 · 1/125</span>
      </div>
    </footer>
  )
}
