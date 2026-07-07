import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, HashRouter } from 'react-router-dom'
import './index.css'
import App from './App'
import ErrorBoundary from './components/ErrorBoundary'
import { AppProvider } from './lib/store'
import { initNative } from './lib/native'

initNative()

// single-file preview builds can't rely on server-side routing — use the hash
const Router = import.meta.env.VITE_SINGLEFILE ? HashRouter : BrowserRouter

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <Router>
        <AppProvider>
          <App />
        </AppProvider>
      </Router>
    </ErrorBoundary>
  </StrictMode>,
)

/* dismiss the launch splash once the app has painted — a short native-style
   hold, then a fade; the node is removed so it can't intercept taps */
const splash = document.getElementById('lm-splash')
if (splash) {
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  const hold = reduce ? 0 : 350
  requestAnimationFrame(() => {
    setTimeout(() => {
      splash.classList.add('gone')
      const drop = () => splash.remove()
      splash.addEventListener('transitionend', drop, { once: true })
      setTimeout(drop, 700) // fallback if transitionend never fires
    }, hold)
  })
}
