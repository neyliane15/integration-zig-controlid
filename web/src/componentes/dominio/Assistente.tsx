/**
 * Assistente de IA: botão flutuante + painel de conversa. A pergunta vai para o workflow "MDG · Assistente" (n8n), que
 * usa o Claude e consulta o banco COM O LOGIN DE QUEM PERGUNTA — só vê o que a pessoa já pode ver no site.
 * Visível para gerente, administrador e master. A conversa fica só nesta aba (sessionStorage), por empresa.
 */
import { useEffect, useId, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import clsx from 'clsx'
import { ArrowUp, Bot, RotateCcw, Sparkles, X } from 'lucide-react'
import { FOCO } from '@/componentes/ui'
import { configuracao } from '@/lib/configuracao'
import { supabase } from '@/lib/supabase'
import { useEmpresaAtual, usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { useContextoEmpresa } from '@/consultas/funcionarios'

interface Mensagem {
  papel: 'usuario' | 'assistente'
  texto: string
  erro?: boolean
}

const SUGESTOES = [
  'Qual funcionário teve menos atrasos este mês?',
  'Qual foi o dia que mais vendeu no mês passado?',
  'Quem faltou na semana passada?',
  'Quem está de folga hoje?',
]

const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado']

const chaveConversa = (empresaId: string) => `mdg:assistente:${empresaId}`
function lerConversa(empresaId: string): Mensagem[] {
  try {
    const v = JSON.parse(window.sessionStorage.getItem(chaveConversa(empresaId)) ?? '[]')
    return Array.isArray(v) ? (v as Mensagem[]).filter((m) => m && typeof m.texto === 'string').slice(-30) : []
  } catch {
    return []
  }
}
function gravarConversa(empresaId: string, m: Mensagem[]) {
  try {
    window.sessionStorage.setItem(chaveConversa(empresaId), JSON.stringify(m.slice(-30)))
  } catch {
    /* armazenamento bloqueado: a conversa só não sobrevive ao recarregar */
  }
}

async function perguntar(corpo: unknown): Promise<string> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('Sua sessão expirou: entre de novo.')
  let r: Response
  try {
    r = await fetch(configuracao.assistenteUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, apikey: configuracao.supabaseAnonKey },
      body: JSON.stringify(corpo),
    })
  } catch {
    throw new Error('Não consegui falar com o assistente. Confira a internet e tente de novo.')
  }
  const json = (await r.json().catch(() => null)) as { resposta?: string; erro?: string } | null
  if (!r.ok || !json?.resposta) throw new Error(json?.erro || `O assistente não respondeu (erro ${r.status}).`)
  return json.resposta
}

export function Assistente() {
  const perfil = usePerfil()
  const { empresaId, empresa } = useEmpresaAtual()
  const { hoje } = useContextoEmpresa()
  const [aberto, setAberto] = useState(false)
  const [mensagens, setMensagens] = useState<Mensagem[]>([])
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const lista = useRef<HTMLDivElement>(null)
  const campo = useRef<HTMLTextAreaElement>(null)
  const id = useId()

  useEffect(() => {
    if (empresaId) setMensagens(lerConversa(empresaId))
  }, [empresaId])
  useEffect(() => {
    if (empresaId) gravarConversa(empresaId, mensagens)
    lista.current?.scrollTo({ top: lista.current.scrollHeight, behavior: 'smooth' })
  }, [mensagens, empresaId])
  useEffect(() => {
    if (!aberto) return
    window.setTimeout(() => campo.current?.focus(), 50)
    const tecla = (e: globalThis.KeyboardEvent) => e.key === 'Escape' && setAberto(false)
    document.addEventListener('keydown', tecla)
    return () => document.removeEventListener('keydown', tecla)
  }, [aberto])

  if (!podeOperar(perfil.papel) || !empresaId) return null

  async function enviar(pergunta: string) {
    const p = pergunta.trim()
    if (!p || enviando || !empresaId) return
    const historico = mensagens.filter((m) => !m.erro)
    setMensagens((m) => [...m, { papel: 'usuario', texto: p }])
    setTexto('')
    setEnviando(true)
    try {
      const resposta = await perguntar({
        pergunta: p,
        empresa_id: empresaId,
        historico: historico.slice(-12).map(({ papel, texto: t }) => ({ papel, texto: t })),
        contexto: { empresa_nome: empresa?.nome ?? '', hoje, dia_semana: DIAS[new Date(`${hoje}T12:00:00Z`).getUTCDay()] },
      })
      setMensagens((m) => [...m, { papel: 'assistente', texto: resposta }])
    } catch (e) {
      setMensagens((m) => [...m, { papel: 'assistente', texto: e instanceof Error ? e.message : 'Erro ao perguntar.', erro: true }])
    } finally {
      setEnviando(false)
    }
  }

  const submeter = (e: FormEvent) => {
    e.preventDefault()
    void enviar(texto)
  }
  const teclaCampo = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      void enviar(texto)
    }
  }

  return (
    <>
      {!aberto && (
        <button
          type="button"
          onClick={() => setAberto(true)}
          data-teste="abrir-assistente"
          className={clsx(
            'fixed right-4 bottom-[calc(env(safe-area-inset-bottom)+84px)] z-40 flex items-center gap-2 rounded-pilula bg-ouro px-4 py-3 text-sm font-bold text-tinta-ouro shadow-cartao transition-transform hover:-translate-y-0.5 lg:right-6 lg:bottom-6',
            FOCO,
          )}
        >
          <Sparkles aria-hidden className="size-4" />
          Assistente
        </button>
      )}
      {aberto && (
        <div className="fixed inset-0 z-50 flex justify-end">
          <div aria-hidden className="modal-fundo absolute inset-0 bg-veu/40" onClick={() => setAberto(false)} />
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby={`${id}-t`}
            className="gaveta relative flex h-dvh w-full flex-col border-l border-borda bg-cartao shadow-cartao sm:w-[440px]"
          >
            <header className="flex items-center justify-between gap-3 border-b border-borda px-5 pt-[calc(env(safe-area-inset-top)+14px)] pb-3.5">
              <div className="flex items-center gap-2.5">
                <span className="grid size-9 place-items-center rounded-full bg-ouro/15 text-ouro">
                  <Bot aria-hidden className="size-5" />
                </span>
                <div>
                  <h2 id={`${id}-t`} className="font-display text-lg leading-tight text-creme">
                    Assistente
                  </h2>
                  <p className="text-xs text-lavanda">Pergunte sobre vendas, ponto, escala e equipe</p>
                </div>
              </div>
              <div className="flex items-center gap-1">
                {mensagens.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setMensagens([])}
                    aria-label="Nova conversa"
                    title="Nova conversa"
                    className={clsx('rounded-lg p-2 text-lavanda hover:bg-cartao-2 hover:text-creme', FOCO)}
                  >
                    <RotateCcw aria-hidden className="size-4" />
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setAberto(false)}
                  aria-label="Fechar assistente"
                  className={clsx('rounded-lg p-2 text-lavanda hover:bg-cartao-2 hover:text-creme', FOCO)}
                >
                  <X aria-hidden className="size-5" />
                </button>
              </div>
            </header>

            <div ref={lista} className="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain px-5 py-4" aria-live="polite">
              {mensagens.length === 0 && (
                <div className="flex flex-col gap-3">
                  <p className="text-sm leading-relaxed text-lavanda">
                    Faça uma pergunta sobre a loja. Eu consulto os dados do sistema e respondo. Por exemplo:
                  </p>
                  {SUGESTOES.map((s) => (
                    <button
                      key={s}
                      type="button"
                      onClick={() => void enviar(s)}
                      className={clsx(
                        'rounded-entrada border border-borda bg-cartao-2/60 px-3.5 py-2.5 text-left text-sm text-creme transition-colors hover:border-ouro/50',
                        FOCO,
                      )}
                    >
                      {s}
                    </button>
                  ))}
                </div>
              )}
              {mensagens.map((m, i) => (
                <div key={i} className={clsx('flex', m.papel === 'usuario' ? 'justify-end' : 'justify-start')}>
                  <p
                    className={clsx(
                      'max-w-[88%] rounded-cartao px-3.5 py-2.5 text-sm leading-relaxed break-words whitespace-pre-line',
                      m.papel === 'usuario'
                        ? 'rounded-br-md bg-ouro text-tinta-ouro'
                        : m.erro
                          ? 'rounded-bl-md border border-perigo/40 bg-perigo/10 text-creme'
                          : 'rounded-bl-md border border-borda bg-cartao-2/60 text-creme',
                    )}
                    data-teste={m.papel === 'assistente' ? 'resposta-assistente' : undefined}
                  >
                    {m.texto}
                  </p>
                </div>
              ))}
              {enviando && (
                <div className="flex items-center gap-2 text-sm text-lavanda" role="status">
                  <span className="flex gap-1" aria-hidden>
                    {[0, 1, 2].map((k) => (
                      <span key={k} className="size-1.5 animate-pulse rounded-full bg-ouro" style={{ animationDelay: `${k * 150}ms` }} />
                    ))}
                  </span>
                  Consultando os dados…
                </div>
              )}
            </div>

            <form onSubmit={submeter} className="border-t border-borda px-4 pt-3 pb-[calc(env(safe-area-inset-bottom)+12px)]">
              <label htmlFor={`${id}-p`} className="sr-only">
                Sua pergunta
              </label>
              <div className="flex items-end gap-2 rounded-entrada border border-borda bg-entrada p-1.5 focus-within:border-ouro">
                <textarea
                  id={`${id}-p`}
                  ref={campo}
                  rows={1}
                  maxLength={2000}
                  value={texto}
                  onChange={(e) => setTexto(e.target.value)}
                  onKeyDown={teclaCampo}
                  placeholder="Ex.: quem menos atrasou em novembro?"
                  className="max-h-32 min-h-9 flex-1 resize-none bg-transparent px-2 py-1.5 text-sm text-creme outline-none placeholder:text-lavanda-escuro"
                />
                <button
                  type="submit"
                  disabled={!texto.trim() || enviando}
                  aria-label="Enviar pergunta"
                  className={clsx('grid size-9 shrink-0 place-items-center rounded-lg bg-ouro text-tinta-ouro disabled:opacity-40', FOCO)}
                >
                  <ArrowUp aria-hidden className="size-4" />
                </button>
              </div>
              <p className="mt-1.5 text-[11px] text-lavanda-escuro">
                Respostas geradas por IA a partir dos dados do sistema. Confira números importantes.
              </p>
            </form>
          </section>
        </div>
      )}
    </>
  )
}
