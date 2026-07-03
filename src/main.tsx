import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, HashRouter } from 'react-router-dom'
import './index.css'
import App from './App'
import { AppProvider } from './lib/store'
import { initNative } from './lib/native'

initNative()

// single-file preview builds can't rely on server-side routing — use the hash
const Router = import.meta.env.VITE_SINGLEFILE ? HashRouter : BrowserRouter

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Router>
      <AppProvider>
        <App />
      </AppProvider>
    </Router>
  </StrictMode>,
)
