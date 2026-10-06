/** Tela cheia para estados da sessão (carregando, desativado, erro). Dono: frontend-1. */
import type { ReactNode } from 'react'
import { Monograma } from './Marca'

export function TelaCarregandoSessao() {
  return (
    <div className="fundo-noite grid min-h-dvh place-items-center" role="status" aria-label="Carregando">
      <div className="flex flex-col items-center gap-5">
        <Monograma className="size-14 animate-pulse" />
        <span className="sobrancelha">Preparando seu dia…</span>
      </div>
    </div>
  )
}

export function TelaEstado({
  sobrancelha = 'Meu dia de gerente',
  titulo,
  italico,
  children,
  acoes,
}: {
  sobrancelha?: string
  titulo: string
  italico?: string
  children?: ReactNode
  acoes?: ReactNode
}) {
  return (
    <main className="fundo-noite grid min-h-dvh place-items-center px-4 py-10">
      <div className="fio-ouro w-full max-w-[460px] rounded-cartao border border-borda bg-cartao p-7 shadow-cartao sm:p-9">
        <p className="sobrancelha">{sobrancelha}</p>
        <h1 className="titulo-display mt-4 !text-[34px]">
          {titulo}
          {italico && (
            <>
              <br />
              <span className="titulo-italico">{italico}</span>
            </>
          )}
        </h1>
        {children && <div className="mt-4 text-[15px] leading-relaxed text-lavanda">{children}</div>}
        {acoes && <div className="mt-7 flex flex-col gap-3">{acoes}</div>}
      </div>
    </main>
  )
}
