/**
 * Ponto de entrada. Dono: frontend-1.
 * QueryClientProvider + BrowserRouter + ProvedorDeAvisos + ProvedorDeSessao + <App />.
 */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClientProvider } from '@tanstack/react-query'
import '@fontsource-variable/fraunces/wght.css'
import '@fontsource-variable/fraunces/wght-italic.css'
import '@fontsource-variable/manrope/wght.css'
import '@fontsource-variable/jetbrains-mono/wght.css'
import './estilos.css'
import { App } from './App'
import { ProvedorDeAvisos } from './componentes/avisos'
import { criarClienteConsultas } from './lib/consultas'
import { ProvedorDeSessao } from './lib/sessao'

const raiz = document.getElementById('raiz')
if (!raiz) throw new Error('Elemento #raiz não encontrado')

const clienteConsultas = criarClienteConsultas()

createRoot(raiz).render(
  <StrictMode>
    <QueryClientProvider client={clienteConsultas}>
      <BrowserRouter>
        <ProvedorDeAvisos>
          <ProvedorDeSessao>
            <App />
          </ProvedorDeSessao>
        </ProvedorDeAvisos>
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
