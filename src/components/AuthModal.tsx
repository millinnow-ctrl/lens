import { useState } from 'react'
import Modal from './Modal'
import { ApertureMark } from './Logo'
import { IconApple, IconGoogle } from './icons'
import { haptic } from '../lib/native'
import { useApp } from '../lib/store'

export default function AuthModal() {
  const { authOpen, setAuthOpen, signIn } = useApp()
  const [email, setEmail] = useState('')

  const submit = (name: string, mail: string) => {
    haptic('light')
    signIn({ name, email: mail })
    setAuthOpen(false)
  }

  return (
    <Modal open={authOpen} onClose={() => setAuthOpen(false)}>
      <div className="p-8">
        <ApertureMark className="w-9 h-9 mb-5" tile={false} />
        <h3 className="font-sans font-semibold text-[22px] tracking-[-0.01em] mb-1.5">
          Welcome to the darkroom
        </h3>
        <p className="text-[13px] text-fog mb-6">
          Save your shots, presets and favorite moods across devices.
        </p>

        {/* Apple first — HIG requires prominence when offered on iOS */}
        <button
          onClick={() => submit('Alex', 'alex@icloud.com')}
          className="btn w-full mb-2.5 bg-black text-white border border-black hover:bg-[#1a1a1a]"
        >
          <IconApple size={17} className="-mt-0.5" />
          Continue with Apple
        </button>
        <button
          onClick={() => submit('Alex', 'alex@example.com')}
          className="btn btn-outline w-full mb-4"
        >
          <IconGoogle size={16} />
          Continue with Google
        </button>

        <div className="flex items-center gap-3 mb-4">
          <span className="flex-1 h-px bg-hairline" />
          <span className="text-[12px] font-medium text-fog">or</span>
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
            className="h-11 w-full rounded-full border border-hairline bg-surface px-4.5 text-[14px] focus:border-violet focus:outline-none mb-3 transition-colors"
          />
          <button type="submit" className="btn btn-primary w-full">
            Continue with email
          </button>
        </form>

        <p className="mt-5 text-[11px] text-fog">
          Demo sign-in. No emails are sent.
        </p>
      </div>
    </Modal>
  )
}
