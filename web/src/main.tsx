/**
 * Ponto de entrada (esqueleto). Dono: frontend-1 — substituir pela montagem real:
 * QueryClientProvider + BrowserRouter + ProvedorDeAvisos + ProvedorDeSessao + <App />.
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/fraunces/wght.css'
import '@fontsource-variable/fraunces/wght-italic.css'
import '@fontsource-variable/manrope/wght.css'
import '@fontsource-variable/jetbrains-mono/wght.css'
import './estilos.css'

const raiz = document.getElementById('raiz')
if (!raiz) throw new Error('Elemento #raiz não encontrado')

createRoot(raiz).render(
  <StrictMode>
    <main className="grid min-h-dvh place-items-center p-4">
      <div className="w-full max-w-[420px] rounded-cartao border border-borda bg-cartao p-8 shadow-cartao">
        <p className="sobrancelha">Meu dia de gerente</p>
        <h1 className="titulo-display mt-3">
          Em construção
          <br />
          <span className="titulo-italico">em breve.</span>
        </h1>
      </div>
    </main>
  </StrictMode>,
)
