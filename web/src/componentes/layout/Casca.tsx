/**
 * Casca do app logado: barra lateral fixa (≥1024px), barra superior + menu inferior + gaveta (celular).
 * Dono: frontend-1.
 */
import { Suspense, useEffect, useState } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import clsx from 'clsx'
import { Building2, LogOut, Menu as IconeMenu, MoreHorizontal, X } from 'lucide-react'
import { useSessao, useEmpresaAtual, usePerfil } from '@/lib/sessao'
import { rotuloPapel } from '@/lib/rotulos'
import { ehMaster } from '@/lib/permissoes'
import { Carregando, FOCO, Vazio } from '../ui'
import { Marca } from './Marca'
import { MenuLateral, itensDoPapel } from './Menu'
import { SeletorEmpresa } from './SeletorEmpresa'

function iniciais(nome: string): string {
  const partes = nome.trim().split(/\s+/)
  return ((partes[0]?.[0] ?? '') + (partes.length > 1 ? (partes[partes.length - 1]?.[0] ?? '') : '')).toUpperCase() || '?'
}

function BlocoUsuario() {
  const perfil = usePerfil()
  const { sair } = useSessao()
  return (
    <div className="flex items-center gap-3 rounded-entrada border border-borda bg-cartao/60 p-2.5">
      <span
        aria-hidden
        className="grid size-9 shrink-0 place-items-center rounded-full border border-ouro/35 bg-ouro/10 text-xs font-bold text-ouro-claro"
      >
        {iniciais(perfil.nome)}
      </span>
      <div className="min-w-0 flex-1 leading-tight">
        <p className="truncate text-sm font-semibold text-creme">{perfil.nome}</p>
        <p className="truncate text-xs text-lavanda">{rotuloPapel[perfil.papel]}</p>
      </div>
      <button
        type="button"
        onClick={() => void sair()}
        aria-label="Sair"
        title="Sair"
        className={clsx('rounded-lg p-2 text-lavanda transition-colors hover:bg-cartao-2 hover:text-creme', FOCO)}
      >
        <LogOut aria-hidden className="size-4" />
      </button>
    </div>
  )
}

function NomeEmpresa() {
  const { empresa } = useEmpresaAtual()
  if (!empresa) return null
  return (
    <div className="flex min-w-0 items-center gap-2 rounded-entrada border border-borda bg-cartao/50 px-3 py-2">
      <Building2 aria-hidden className="size-4 shrink-0 text-ouro" />
      <span className="truncate text-sm font-semibold text-creme">{empresa.nome}</span>
    </div>
  )
}

function ConteudoLateral({ aoNavegar }: { aoNavegar?(): void }) {
  const perfil = usePerfil()
  return (
    <div className="flex h-full flex-col gap-6">
      {ehMaster(perfil.papel) ? <SeletorEmpresa aoTrocar={aoNavegar} /> : <NomeEmpresa />}
      <div className="min-h-0 flex-1 overflow-y-auto pr-1 [scrollbar-width:thin]">
        <MenuLateral papel={perfil.papel} aoNavegar={aoNavegar} />
      </div>
      <BlocoUsuario />
    </div>
  )
}

export function Casca() {
  const perfil = usePerfil()
  const { empresaId, empresa } = useEmpresaAtual()
  const [gaveta, setGaveta] = useState(false)
  const local = useLocation()

  useEffect(() => setGaveta(false), [local.pathname])
  useEffect(() => {
    if (!gaveta) return
    const tecla = (e: KeyboardEvent) => e.key === 'Escape' && setGaveta(false)
    document.addEventListener('keydown', tecla)
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', tecla)
      document.body.style.overflow = overflow
    }
  }, [gaveta])

  const atalhos = itensDoPapel(perfil.papel).filter((i) => i.atalho).slice(0, 4)
  const masterSemEmpresa = ehMaster(perfil.papel) && !empresaId && !local.pathname.startsWith('/master')

  return (
    <div className="min-h-dvh bg-noite">
      <a
        href="#conteudo"
        className="sr-only z-[70] rounded-entrada bg-ouro px-4 py-2 font-bold text-tinta-ouro focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
      >
        Pular para o conteúdo
      </a>

      {/* barra lateral — desktop */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-[260px] flex-col gap-7 border-r border-borda bg-noite-2 px-4 pt-6 pb-4 lg:flex">
        <Link to="/" className={clsx('self-start rounded-lg px-1', FOCO)} aria-label="Ir para o painel">
          <Marca />
        </Link>
        <div className="min-h-0 flex-1">
          <ConteudoLateral />
        </div>
      </aside>

      {/* barra superior — celular/tablet */}
      <header className="sticky top-0 z-30 flex h-16 items-center justify-between gap-3 border-b border-borda bg-noite-2/95 px-4 pt-[env(safe-area-inset-top)] backdrop-blur lg:hidden">
        <Link to="/" className={clsx('rounded-lg', FOCO)} aria-label="Ir para o painel">
          <Marca />
        </Link>
        <div className="flex min-w-0 items-center gap-2">
          {empresa && <span className="hidden max-w-[40vw] truncate text-xs font-semibold text-lavanda sm:block">{empresa.nome}</span>}
          <button
            type="button"
            onClick={() => setGaveta(true)}
            aria-label="Abrir menu"
            aria-expanded={gaveta}
            aria-controls="gaveta-menu"
            className={clsx('grid size-10 place-items-center rounded-entrada border border-borda bg-cartao text-creme', FOCO)}
          >
            <IconeMenu aria-hidden className="size-5" />
          </button>
        </div>
      </header>

      {/* gaveta — celular */}
      {gaveta && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div aria-hidden className="modal-fundo absolute inset-0 bg-[#02040b]/75" onClick={() => setGaveta(false)} />
          <div
            id="gaveta-menu"
            role="dialog"
            aria-modal="true"
            aria-label="Menu"
            className="gaveta absolute inset-y-0 left-0 flex w-[min(320px,86vw)] flex-col gap-6 border-r border-borda bg-noite-2 px-4 pt-[calc(env(safe-area-inset-top)+16px)] pb-[calc(env(safe-area-inset-bottom)+16px)]"
          >
            <div className="flex items-center justify-between">
              <Marca />
              <button
                type="button"
                onClick={() => setGaveta(false)}
                aria-label="Fechar menu"
                className={clsx('grid size-10 place-items-center rounded-entrada text-lavanda hover:text-creme', FOCO)}
                autoFocus
              >
                <X aria-hidden className="size-5" />
              </button>
            </div>
            <div className="min-h-0 flex-1">
              <ConteudoLateral aoNavegar={() => setGaveta(false)} />
            </div>
          </div>
        </div>
      )}

      <main id="conteudo" tabIndex={-1} className="min-w-0 focus:outline-none lg:pl-[260px]">
        <div className="mx-auto w-full max-w-[1180px] px-4 pt-6 pb-[calc(env(safe-area-inset-bottom)+96px)] sm:px-6 lg:px-10 lg:pt-10 lg:pb-16">
          {masterSemEmpresa ? (
            <div className="mx-auto max-w-lg pt-8">
              <Vazio
                icone={<Building2 aria-hidden />}
                titulo="Escolha uma empresa"
                descricao="Como master, você opera em uma empresa por vez. Selecione no menu ou cadastre a primeira."
                acao={
                  <div className="flex flex-col items-stretch gap-3">
                    <div className="w-64 text-left">
                      <SeletorEmpresa />
                    </div>
                    <Link to="/master/empresas" className="text-sm font-semibold text-ouro hover:underline">
                      Gerenciar empresas
                    </Link>
                  </div>
                }
              />
            </div>
          ) : (
            <Suspense fallback={<Carregando />}>
              <Outlet />
            </Suspense>
          )}
        </div>
      </main>

      {/* menu inferior — celular */}
      <nav
        aria-label="Atalhos"
        className="fixed inset-x-0 bottom-0 z-30 border-t border-borda bg-noite-2/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
      >
        <ul className="mx-auto flex max-w-lg items-stretch justify-around">
          {atalhos.map((i) => (
            <li key={i.para} className="flex-1">
              <NavLink
                to={i.para}
                end={i.para === '/'}
                className={({ isActive }) =>
                  clsx(
                    'flex h-16 flex-col items-center justify-center gap-1 text-[11px] font-semibold transition-colors',
                    'focus-visible:outline-2 focus-visible:-outline-offset-4 focus-visible:outline-ouro',
                    isActive ? 'text-ouro-claro' : 'text-lavanda hover:text-creme',
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    <i.icone aria-hidden className={clsx('size-5', isActive ? 'text-ouro' : '')} />
                    {i.rotulo}
                  </>
                )}
              </NavLink>
            </li>
          ))}
          <li className="flex-1">
            <button
              type="button"
              onClick={() => setGaveta(true)}
              className="flex h-16 w-full flex-col items-center justify-center gap-1 text-[11px] font-semibold text-lavanda hover:text-creme focus-visible:outline-2 focus-visible:-outline-offset-4 focus-visible:outline-ouro"
            >
              <MoreHorizontal aria-hidden className="size-5" />
              Mais
            </button>
          </li>
        </ul>
      </nav>
    </div>
  )
}
