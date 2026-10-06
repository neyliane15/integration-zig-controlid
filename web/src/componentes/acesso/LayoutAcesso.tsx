/**
 * Moldura das telas de acesso (login, recuperar, criar conta, começar). Dono: frontend-1.
 * Cartão central de 420px no fundo azul-noite; sobrancelha dourada; título serifado em duas linhas.
 */
import { forwardRef, useState, type InputHTMLAttributes, type ReactNode } from 'react'
import clsx from 'clsx'
import { Eye, EyeOff } from 'lucide-react'
import { Entrada, FOCO } from '../ui'

export function LayoutAcesso({
  titulo,
  italico,
  subtitulo,
  children,
  rodape,
  sobrancelha = 'Meu dia de gerente',
}: {
  titulo: string
  italico?: string
  subtitulo?: ReactNode
  children: ReactNode
  rodape?: ReactNode
  sobrancelha?: string
}) {
  return (
    <main className="fundo-noite flex min-h-dvh items-center justify-center px-4 py-10 sm:py-16">
      <div className="surgir w-full max-w-[420px] rounded-cartao border border-borda bg-cartao px-6 pt-9 pb-8 shadow-cartao sm:px-9 sm:pt-10 sm:pb-9">
        <p className="sobrancelha">{sobrancelha}</p>
        <h1 className="mt-5 font-display text-[38px] leading-[1.08] font-normal tracking-[-0.01em] text-creme sm:text-[42px]">
          {titulo}
          {italico && (
            <>
              <br />
              <em className="titulo-italico font-normal">{italico}</em>
            </>
          )}
        </h1>
        {subtitulo && <p className="mt-4 text-[15px] leading-relaxed text-lavanda">{subtitulo}</p>}
        <div className="mt-8">{children}</div>
        {rodape && <div className="mt-7 flex items-center justify-between gap-4 text-sm">{rodape}</div>}
      </div>
    </main>
  )
}

/** Campo de senha com botão mostrar/ocultar. */
export const EntradaSenha = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement> & { invalido?: boolean }>(
  function EntradaSenha({ className, ...resto }, ref) {
    const [visivel, setVisivel] = useState(false)
    return (
      <div className="relative">
        <Entrada ref={ref} type={visivel ? 'text' : 'password'} className={clsx('pr-12', className)} {...resto} />
        <button
          type="button"
          onClick={() => setVisivel((v) => !v)}
          aria-label={visivel ? 'Ocultar senha' : 'Mostrar senha'}
          aria-pressed={visivel}
          className={clsx(
            'absolute top-1/2 right-2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-lavanda-escuro transition-colors hover:text-lavanda',
            FOCO,
          )}
        >
          {visivel ? <EyeOff aria-hidden className="size-[18px]" /> : <Eye aria-hidden className="size-[18px]" />}
        </button>
      </div>
    )
  },
)

/** Ícone "G" do Google (cores oficiais, só no ícone). */
export function IconeGoogle({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 48 48" aria-hidden className={className}>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  )
}

/** Mensagem de erro/aviso dentro do cartão de acesso. */
export function AlertaAcesso({ tom = 'perigo', children }: { tom?: 'perigo' | 'sucesso' | 'info'; children: ReactNode }) {
  return (
    <div
      role={tom === 'perigo' ? 'alert' : 'status'}
      className={clsx(
        'mb-5 rounded-entrada border px-4 py-3 text-sm leading-relaxed',
        tom === 'perigo' && 'border-perigo/40 bg-perigo/10 text-creme',
        tom === 'sucesso' && 'border-sucesso/40 bg-sucesso/10 text-creme',
        tom === 'info' && 'border-info/40 bg-info/10 text-creme',
      )}
    >
      {children}
    </div>
  )
}

/** Classes dos links do rodapé: lavanda sublinhado (secundário) e dourado (ação). */
export const LINK_SECUNDARIO = clsx('rounded text-lavanda underline decoration-lavanda/60 hover:text-creme', FOCO)
export const LINK_OURO = clsx('rounded font-bold text-ouro hover:text-ouro-claro', FOCO)
