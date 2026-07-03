import { Link } from 'react-router-dom'
import Logo from './Logo'

export default function Footer() {
  return (
    <footer className="border-t border-cloud mt-24 pb-24 md:pb-10">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-12 grid gap-10 md:grid-cols-[1fr_auto_auto_auto]">
        <div className="max-w-xs">
          <Logo />
          <p className="mt-3 text-sm text-fog leading-relaxed">
            The AI aesthetic camera. Recreate the lighting, grain, and mood of iconic cameras — from
            any photo.
          </p>
        </div>
        {[
          {
            title: 'Product',
            links: [
              { label: 'Studio', to: '/studio' },
              { label: 'Camera styles', to: '/#styles' },
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
            <h4 className="text-xs font-bold uppercase tracking-widest text-fog mb-3">{col.title}</h4>
            <ul className="space-y-2 text-sm">
              {col.links.map((l) => (
                <li key={l.label}>
                  <Link to={l.to} className="text-ink-soft hover:text-violet transition-colors">
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 text-xs text-fog flex items-center justify-between">
        <span>© 2026 LensMood. Every photo deserves a better camera.</span>
        <span className="font-mono">f/1.4 · ISO 400</span>
      </div>
    </footer>
  )
}
