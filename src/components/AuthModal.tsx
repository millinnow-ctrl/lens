import { useState } from 'react'
import Modal from './Modal'
import { ApertureMark } from './Logo'
import { IconGoogle } from './icons'
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
      <div className="p-8">
        <ApertureMark className="w-9 h-9 mb-5" />
        <h3 className="font-sans font-semibold text-[22px] tracking-[-0.01em] mb-1.5">
          Welcome to the darkroom
        </h3>
        <p className="text-[13px] text-fog mb-6">
          Save your shots, presets and favorite moods across devices.
        </p>

        <button
          onClick={() => submit('Alex', 'alex@example.com')}
          className="btn btn-outline w-full mb-4"
        >
          <IconGoogle size={16} />
          Continue with Google
        </button>

        <div className="flex items-center gap-3 mb-4">
          <span className="flex-1 h-px bg-hairline" />
          <span className="font-mono text-[11px] tracking-[0.14em] uppercase text-fog">or</span>
          <span className="flex-1 h-px bg-hairline" />
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
            className="h-11 w-full rounded-xs border border-hairline bg-surface px-4 text-[14px] focus:border-ink focus:outline-none mb-3 transition-colors"
          />
          <button type="submit" className="btn btn-primary w-full">
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
