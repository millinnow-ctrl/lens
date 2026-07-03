import { useState } from 'react'
import Modal from './Modal'
import { ApertureMark } from './Logo'
import { useApp } from '../lib/store'

export default function AuthModal() {
  const { authOpen, setAuthOpen, signIn } = useApp()
  const [email, setEmail] = useState('')

  const submit = (name: string, mail: string) => {
    signIn({ name, email: mail })
    setAuthOpen(false)
  }

  return (
    <Modal open={authOpen} onClose={() => setAuthOpen(false)}>
      <div className="p-8 text-center">
        <div className="mx-auto w-14 h-14 mb-4 flex items-center justify-center">
          <ApertureMark className="w-12 h-12" />
        </div>
        <h3 className="font-display text-2xl font-semibold mb-1.5">Welcome to the darkroom</h3>
        <p className="text-sm text-fog mb-6">
          Save your shots, presets and favorite moods across devices.
        </p>

        <button
          onClick={() => submit('Alex', 'alex@example.com')}
          className="w-full pill-base pill-ghost px-5 py-3 text-sm mb-3"
        >
          <svg viewBox="0 0 24 24" className="w-4.5 h-4.5" aria-hidden>
            <path fill="#4285F4" d="M23.5 12.3c0-.9-.1-1.5-.3-2.2H12v4.1h6.5c-.1 1.1-.8 2.7-2.4 3.8l3.7 2.9c2.2-2 3.7-5 3.7-8.6z" />
            <path fill="#34A853" d="M12 24c3.2 0 5.9-1.1 7.9-2.9l-3.7-2.9c-1 .7-2.4 1.2-4.2 1.2-3.2 0-5.9-2.1-6.8-5l-3.9 3C3.2 21.3 7.3 24 12 24z" />
            <path fill="#FBBC05" d="M5.2 14.4c-.2-.7-.4-1.5-.4-2.4s.1-1.7.4-2.4l-3.9-3C.5 8.2 0 10 0 12s.5 3.8 1.3 5.4l3.9-3z" />
            <path fill="#EA4335" d="M12 4.7c1.8 0 3 .8 3.7 1.4l3.3-3.2C17.9 1.1 15.2 0 12 0 7.3 0 3.2 2.7 1.3 6.6l3.9 3c.9-2.9 3.6-4.9 6.8-4.9z" />
          </svg>
          Continue with Google
        </button>

        <div className="flex items-center gap-3 my-4 text-[11px] uppercase tracking-widest text-fog">
          <span className="flex-1 h-px bg-cloud" />
          or
          <span className="flex-1 h-px bg-cloud" />
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (email.includes('@')) submit(email.split('@')[0], email)
          }}
        >
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            className="w-full rounded-full bg-mist border border-transparent focus:border-violet focus:bg-paper outline-none px-5 py-3 text-sm mb-3 transition-colors"
          />
          <button type="submit" className="w-full pill-base pill-primary px-5 py-3 text-sm">
            Continue with email
          </button>
        </form>

        <p className="mt-5 text-[11px] text-fog">
          Demo sign-in — no emails are sent. By continuing you agree to make better photos.
        </p>
      </div>
    </Modal>
  )
}
