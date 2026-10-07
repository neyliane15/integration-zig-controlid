/**
 * Avisos (toasts) e confirmação (contrato §14.5). Dono: frontend-1.
 * `useAvisos(): { sucesso, erro, info, confirmar }`.
 */
import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react'
import clsx from 'clsx'
import { AlertTriangle, CheckCircle2, Info, X } from 'lucide-react'
import { mensagemDeErro } from '@/lib/supabase'
import { Botao, Modal } from './ui'

type TipoAviso = 'sucesso' | 'erro' | 'info'
interface Aviso {
  id: number
  tipo: TipoAviso
  mensagem: string
}
export interface OpcoesConfirmar {
  titulo: string
  mensagem?: ReactNode
  textoConfirmar?: string
  perigo?: boolean
}
export interface Avisos {
  sucesso(m: string): void
  erro(e: unknown): void
  info(m: string): void
  confirmar(o: OpcoesConfirmar): Promise<boolean>
}

const ContextoAvisos = createContext<Avisos | null>(null)

const DURACAO: Record<TipoAviso, number> = { sucesso: 4000, info: 5000, erro: 7000 }

export function ProvedorDeAvisos({ children }: { children: ReactNode }) {
  const [avisos, setAvisos] = useState<Aviso[]>([])
  const [pergunta, setPergunta] = useState<(OpcoesConfirmar & { resolver(v: boolean): void }) | null>(null)
  const proximo = useRef(1)

  const fechar = useCallback((id: number) => setAvisos((l) => l.filter((a) => a.id !== id)), [])

  const empilhar = useCallback(
    (tipo: TipoAviso, mensagem: string) => {
      const id = proximo.current++
      setAvisos((l) => [...l.filter((a) => a.mensagem !== mensagem).slice(-3), { id, tipo, mensagem }])
      window.setTimeout(() => fechar(id), DURACAO[tipo])
    },
    [fechar],
  )

  const responder = useCallback(
    (v: boolean) => {
      setPergunta((p) => {
        p?.resolver(v)
        return null
      })
    },
    [],
  )

  const valor = useMemo<Avisos>(
    () => ({
      sucesso: (m) => empilhar('sucesso', m),
      info: (m) => empilhar('info', m),
      erro: (e) => empilhar('erro', mensagemDeErro(e)),
      confirmar: (o) =>
        new Promise<boolean>((resolver) => {
          setPergunta((anterior) => {
            anterior?.resolver(false)
            return { ...o, resolver }
          })
        }),
    }),
    [empilhar],
  )

  return (
    <ContextoAvisos.Provider value={valor}>
      {children}
      <div
        aria-live="polite"
        className="pointer-events-none fixed inset-x-0 bottom-[calc(env(safe-area-inset-bottom)+80px)] z-[60] flex flex-col items-center gap-2 px-4 lg:bottom-6 lg:items-end lg:px-6"
      >
        {avisos.map((a) => (
          <div
            key={a.id}
            role={a.tipo === 'erro' ? 'alert' : 'status'}
            className={clsx(
              'aviso-entrando pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-entrada border bg-cartao-2 px-4 py-3 text-sm text-creme shadow-cartao',
              a.tipo === 'sucesso' && 'border-sucesso/40',
              a.tipo === 'erro' && 'border-perigo/50',
              a.tipo === 'info' && 'border-info/40',
            )}
          >
            {a.tipo === 'sucesso' && <CheckCircle2 aria-hidden className="mt-0.5 size-4 shrink-0 text-sucesso" />}
            {a.tipo === 'erro' && <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0 text-perigo" />}
            {a.tipo === 'info' && <Info aria-hidden className="mt-0.5 size-4 shrink-0 text-info" />}
            <p className="flex-1 leading-snug">{a.mensagem}</p>
            <button
              type="button"
              onClick={() => fechar(a.id)}
              className="-m-1 rounded-md p-1 text-lavanda hover:text-creme"
              aria-label="Fechar aviso"
            >
              <X aria-hidden className="size-4" />
            </button>
          </div>
        ))}
      </div>
      <Modal
        aberto={pergunta != null}
        aoFechar={() => responder(false)}
        titulo={pergunta?.titulo ?? ''}
        largura="p"
        rodape={
          <>
            <Botao variante="secundario" onClick={() => responder(false)}>
              Cancelar
            </Botao>
            <Botao variante={pergunta?.perigo ? 'perigo' : 'primario'} onClick={() => responder(true)} autoFocus>
              {pergunta?.textoConfirmar ?? 'Confirmar'}
            </Botao>
          </>
        }
      >
        {pergunta?.mensagem && <div className="text-sm leading-relaxed text-lavanda">{pergunta.mensagem}</div>}
      </Modal>
    </ContextoAvisos.Provider>
  )
}

export function useAvisos(): Avisos {
  const c = useContext(ContextoAvisos)
  if (!c) throw new Error('useAvisos fora de <ProvedorDeAvisos>')
  return c
}
