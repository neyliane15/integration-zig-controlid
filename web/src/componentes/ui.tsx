/**
 * Design system — componentes compartilhados (contrato §14.5).
 * Dono: frontend-1. As PROPS são contrato: frontend-2 usa estes componentes em paralelo.
 * Estética: azul-noite, cartões marinho com borda sutil, dourado como acento (não enfeite), títulos em Fraunces.
 */
import {
  forwardRef,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type KeyboardEvent as KeyboardEventReact,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react'
import clsx from 'clsx'
import { AlertTriangle, Check, ChevronDown, ChevronRight, Inbox, RotateCcw, X } from 'lucide-react'
import { centavosParaTexto, hojeISO, somarDias, textoParaCentavos } from '@/lib/formato'
import { mensagemDeErro } from '@/lib/supabase'

export type Tom = 'neutro' | 'ouro' | 'sucesso' | 'alerta' | 'perigo' | 'info'

/** Anel de foco padrão (teclado). */
export const FOCO = 'focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ouro'

// ------------------------------------------------------------------- Botao
export interface BotaoProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variante?: 'primario' | 'secundario' | 'fantasma' | 'perigo'
  tamanho?: 'p' | 'm' | 'g'
  carregando?: boolean
  icone?: ReactNode
}

const VARIANTES: Record<NonNullable<BotaoProps['variante']>, string> = {
  primario:
    'bg-ouro text-tinta-ouro font-bold shadow-[0_1px_0_rgb(255_255_255/0.25)_inset,0_8px_24px_-12px_rgb(201_162_61/0.55)] hover:bg-ouro-claro active:bg-ouro-escuro',
  secundario: 'border border-borda bg-entrada text-creme font-semibold hover:border-borda-forte hover:bg-cartao-2',
  fantasma: 'bg-transparent text-lavanda font-semibold hover:bg-cartao-2 hover:text-creme',
  perigo: 'border border-perigo/50 bg-perigo/10 text-perigo font-bold hover:bg-perigo hover:text-noite',
}
const TAMANHOS: Record<NonNullable<BotaoProps['tamanho']>, string> = {
  p: 'h-9 px-3 text-sm',
  m: 'h-11 px-4 text-sm',
  g: 'h-12 px-5 text-[15px]',
}

export const Botao = forwardRef<HTMLButtonElement, BotaoProps>(function Botao(
  { variante = 'primario', tamanho = 'm', carregando = false, icone, className, children, disabled, type = 'button', ...resto },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      disabled={disabled || carregando}
      aria-busy={carregando || undefined}
      className={clsx(
        'inline-flex shrink-0 select-none items-center justify-center gap-2 whitespace-nowrap rounded-entrada transition-[background-color,border-color,color,transform] duration-150 active:translate-y-px disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4 [&_svg]:shrink-0',
        FOCO,
        VARIANTES[variante],
        TAMANHOS[tamanho],
        className,
      )}
      {...resto}
    >
      {carregando ? <Girador /> : icone}
      {children}
    </button>
  )
})

function Girador({ className }: { className?: string }) {
  return (
    <span aria-hidden className={clsx('inline-block size-4 animate-spin rounded-full border-2 border-current border-t-transparent', className)} />
  )
}

// ------------------------------------------------------------------- Campo
export function Campo({
  rotulo,
  htmlFor,
  ajuda,
  erro,
  obrigatorio,
  children,
}: {
  rotulo: string
  htmlFor?: string
  ajuda?: ReactNode
  erro?: string | null
  obrigatorio?: boolean
  children: ReactNode
}) {
  return (
    <div className="flex min-w-0 flex-col gap-2">
      <label htmlFor={htmlFor} className="text-sm font-bold text-creme">
        {rotulo}
        {obrigatorio && (
          <span className="ml-0.5 text-ouro" aria-hidden>
            *
          </span>
        )}
      </label>
      {children}
      {erro ? (
        <p className="flex items-center gap-1.5 text-xs font-medium text-perigo" role="alert">
          <AlertTriangle aria-hidden className="size-3.5" />
          {erro}
        </p>
      ) : ajuda ? (
        <p className="text-xs leading-relaxed text-lavanda">{ajuda}</p>
      ) : null}
    </div>
  )
}

const CLASSE_ENTRADA = clsx(
  'h-12 w-full min-w-0 rounded-entrada border border-borda bg-entrada px-4 text-[15px] text-creme transition-colors',
  'placeholder:text-lavanda-escuro hover:border-borda-forte',
  'focus:border-ouro/70 focus:outline-none focus:ring-3 focus:ring-ouro/15',
  'disabled:cursor-not-allowed disabled:opacity-55 aria-[invalid=true]:border-perigo/70',
)

export const Entrada = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement> & { invalido?: boolean }>(
  function Entrada({ invalido, className, ...resto }, ref) {
    return <input ref={ref} aria-invalid={invalido || resto['aria-invalid'] || undefined} className={clsx(CLASSE_ENTRADA, className)} {...resto} />
  },
)

export const Selecao = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Selecao(
  { className, ...resto },
  ref,
) {
  return (
    <div className="relative min-w-0">
      <select ref={ref} className={clsx(CLASSE_ENTRADA, 'cursor-pointer appearance-none pr-10', className)} {...resto} />
      <ChevronDown aria-hidden className="pointer-events-none absolute top-1/2 right-3.5 size-4 -translate-y-1/2 text-lavanda" />
    </div>
  )
})

export const AreaTexto = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function AreaTexto(
  { className, ...resto },
  ref,
) {
  return <textarea ref={ref} className={clsx(CLASSE_ENTRADA, 'h-auto min-h-28 py-3 leading-relaxed', className)} {...resto} />
})

// ------------------------------------------------------- Caixa / Interruptor
interface PropsMarcavel {
  rotulo: ReactNode
  marcado: boolean
  aoMudar(v: boolean): void
  desabilitado?: boolean
}

export function Caixa({ rotulo, marcado, aoMudar, desabilitado }: PropsMarcavel) {
  return (
    <label
      className={clsx(
        'group inline-flex items-center gap-2.5 text-sm text-creme',
        desabilitado ? 'cursor-not-allowed opacity-55' : 'cursor-pointer',
      )}
    >
      <span className="relative inline-grid size-[18px] shrink-0 place-items-center">
        <input
          type="checkbox"
          className={clsx(
            'peer size-[18px] cursor-[inherit] appearance-none rounded-[5px] border border-borda-forte bg-entrada transition-colors',
            'checked:border-ouro checked:bg-ouro group-hover:border-ouro/70',
            FOCO,
          )}
          checked={marcado}
          disabled={desabilitado}
          onChange={(e) => aoMudar(e.target.checked)}
        />
        <Check aria-hidden strokeWidth={3.2} className="pointer-events-none absolute size-3 text-tinta-ouro opacity-0 peer-checked:opacity-100" />
      </span>
      <span>{rotulo}</span>
    </label>
  )
}

export function Interruptor({ rotulo, marcado, aoMudar, desabilitado }: PropsMarcavel) {
  const id = useId()
  return (
    <div className={clsx('inline-flex items-center gap-3 text-sm text-creme', desabilitado && 'opacity-55')}>
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={marcado}
        disabled={desabilitado}
        onClick={() => aoMudar(!marcado)}
        className={clsx(
          'relative h-6 w-11 shrink-0 rounded-pilula border transition-colors disabled:cursor-not-allowed',
          marcado ? 'border-ouro bg-ouro' : 'border-borda-forte bg-entrada',
          FOCO,
        )}
      >
        <span
          className={clsx(
            'absolute top-1/2 size-[18px] -translate-y-1/2 rounded-full shadow transition-all',
            marcado ? 'left-[22px] bg-tinta-ouro' : 'left-[2px] bg-lavanda',
          )}
        />
      </button>
      <label htmlFor={id} className={desabilitado ? 'cursor-not-allowed' : 'cursor-pointer'}>
        {rotulo}
      </label>
    </div>
  )
}

// ------------------------------------------------- entradas especializadas
export function EntradaMoeda({
  centavos,
  aoMudar,
  permitirNegativo,
  id,
  desabilitado,
}: {
  centavos: number | null
  aoMudar(c: number | null): void
  permitirNegativo?: boolean
  id?: string
  desabilitado?: boolean
}) {
  const formatado = centavos == null ? '' : centavosParaTexto(centavos)
  const [texto, setTexto] = useState(formatado)
  const [focado, setFocado] = useState(false)
  useEffect(() => {
    if (!focado) setTexto(formatado)
  }, [formatado, focado])
  return (
    <div className="relative min-w-0">
      <span aria-hidden className="pointer-events-none absolute top-1/2 left-4 -translate-y-1/2 text-sm text-lavanda">
        R$
      </span>
      <Entrada
        id={id}
        inputMode="decimal"
        autoComplete="off"
        disabled={desabilitado}
        value={texto}
        className="numero pl-11 text-right"
        onFocus={() => setFocado(true)}
        onChange={(e) => setTexto(e.target.value.replace(permitirNegativo ? /[^\d.,-]/g : /[^\d.,]/g, ''))}
        onBlur={() => {
          setFocado(false)
          const c = textoParaCentavos(texto)
          if (texto.trim() === '' || c == null) {
            aoMudar(texto.trim() === '' ? null : centavos)
            setTexto(texto.trim() === '' ? '' : formatado)
            return
          }
          const final = permitirNegativo ? c : Math.abs(c)
          aoMudar(final)
          setTexto(centavosParaTexto(final))
        }}
      />
    </div>
  )
}

export function EntradaData({
  valor,
  aoMudar,
  min,
  max,
  id,
}: {
  valor: string | null
  aoMudar(v: string | null): void
  min?: string
  max?: string
  id?: string
}) {
  return (
    <Entrada
      id={id}
      type="date"
      className="numero [color-scheme:dark]"
      value={valor ?? ''}
      min={min}
      max={max}
      onChange={(e) => aoMudar(e.target.value || null)}
    />
  )
}

export function EntradaHora({ valor, aoMudar, id }: { valor: string | null; aoMudar(v: string | null): void; id?: string }) {
  return (
    <Entrada
      id={id}
      type="time"
      className="numero [color-scheme:dark]"
      value={valor?.slice(0, 5) ?? ''}
      onChange={(e) => aoMudar(e.target.value || null)}
    />
  )
}

function primeiroDoMes(iso: string): string {
  return `${iso.slice(0, 7)}-01`
}

/** Atalhos de período (dia de trabalho no fuso de São Paulo, virada 05:00). Exportado para testes/telas. */
export function atalhosPeriodo(hoje: string = hojeISO()): { id: string; rotulo: string; inicio: string; fim: string }[] {
  const inicioMes = primeiroDoMes(hoje)
  const fimMesAnterior = somarDias(inicioMes, -1)
  return [
    { id: 'hoje', rotulo: 'Hoje', inicio: hoje, fim: hoje },
    { id: 'ontem', rotulo: 'Ontem', inicio: somarDias(hoje, -1), fim: somarDias(hoje, -1) },
    { id: '7dias', rotulo: '7 dias', inicio: somarDias(hoje, -6), fim: hoje },
    { id: 'mes', rotulo: 'Este mês', inicio: inicioMes, fim: hoje },
    { id: 'mes-anterior', rotulo: 'Mês anterior', inicio: primeiroDoMes(fimMesAnterior), fim: fimMesAnterior },
  ]
}

export function FiltroPeriodo({
  inicio,
  fim,
  aoMudar,
  atalhos = true,
}: {
  inicio: string
  fim: string
  aoMudar(inicio: string, fim: string): void
  atalhos?: boolean
}) {
  const id = useId()
  const lista = atalhos ? atalhosPeriodo() : []
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 sm:flex sm:flex-wrap">
        <label htmlFor={`${id}-i`} className="sr-only">
          Data inicial
        </label>
        <div className="min-w-0 sm:w-44">
          <EntradaData id={`${id}-i`} valor={inicio} aoMudar={(v) => v && aoMudar(v, v > fim ? v : fim)} />
        </div>
        <span className="text-sm text-lavanda">a</span>
        <label htmlFor={`${id}-f`} className="sr-only">
          Data final
        </label>
        <div className="min-w-0 sm:w-44">
          <EntradaData id={`${id}-f`} valor={fim} aoMudar={(v) => v && aoMudar(v < inicio ? v : inicio, v)} />
        </div>
      </div>
      {lista.length > 0 && (
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Atalhos de período">
          {lista.map((a) => {
            const ativo = a.inicio === inicio && a.fim === fim
            return (
              <button
                key={a.id}
                type="button"
                aria-pressed={ativo}
                onClick={() => aoMudar(a.inicio, a.fim)}
                className={clsx(
                  'h-8 rounded-pilula border px-3 text-xs font-semibold transition-colors',
                  ativo ? 'border-ouro/60 bg-ouro/10 text-ouro-claro' : 'border-borda text-lavanda hover:border-borda-forte hover:text-creme',
                  FOCO,
                )}
              >
                {a.rotulo}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- estrutura
export function Cartao({
  titulo,
  sobrancelha,
  acoes,
  className,
  semPreenchimento,
  children,
}: {
  titulo?: ReactNode
  sobrancelha?: string
  acoes?: ReactNode
  className?: string
  semPreenchimento?: boolean
  children?: ReactNode
}) {
  return (
    <section className={clsx('min-w-0 rounded-cartao border border-borda bg-cartao shadow-cartao', !semPreenchimento && 'p-5 sm:p-6', className)}>
      {(titulo || sobrancelha || acoes) && (
        <header className={clsx('mb-4 flex flex-wrap items-start justify-between gap-3', semPreenchimento && 'px-5 pt-5 sm:px-6 sm:pt-6')}>
          <div className="min-w-0">
            {sobrancelha && <p className="sobrancelha mb-1.5">{sobrancelha}</p>}
            {titulo && <h2 className="font-display text-xl leading-tight text-creme">{titulo}</h2>}
          </div>
          {acoes && <div className="flex flex-wrap items-center gap-2">{acoes}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

export function CabecalhoPagina({
  sobrancelha,
  titulo,
  subtitulo,
  acoes,
}: {
  sobrancelha?: string
  titulo: ReactNode
  subtitulo?: ReactNode
  acoes?: ReactNode
}) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4 sm:mb-8">
      <div className="min-w-0">
        {sobrancelha && <p className="sobrancelha mb-2">{sobrancelha}</p>}
        <h1 className="font-display text-[28px] leading-[1.1] text-creme sm:text-4xl">{titulo}</h1>
        {subtitulo && <p className="mt-2 text-[15px] text-lavanda">{subtitulo}</p>}
      </div>
      {acoes && <div className="flex flex-wrap gap-2">{acoes}</div>}
    </header>
  )
}

const TONS_SELO: Record<Tom, string> = {
  neutro: 'border-borda-forte/70 bg-cartao-2 text-lavanda',
  ouro: 'border-ouro/40 bg-ouro/10 text-ouro-claro',
  sucesso: 'border-sucesso/35 bg-sucesso/10 text-sucesso',
  alerta: 'border-alerta/35 bg-alerta/10 text-alerta',
  perigo: 'border-perigo/40 bg-perigo/10 text-perigo',
  info: 'border-info/35 bg-info/10 text-info',
}
const TONS_TEXTO: Record<Tom, string> = {
  neutro: 'text-creme',
  ouro: 'text-ouro-claro',
  sucesso: 'text-sucesso',
  alerta: 'text-alerta',
  perigo: 'text-perigo',
  info: 'text-info',
}

export function Selo({ tom = 'neutro', children }: { tom?: Tom; children: ReactNode }) {
  return (
    <span
      className={clsx(
        'inline-flex max-w-full items-center gap-1 truncate rounded-pilula border px-2.5 py-0.5 font-sans text-xs font-semibold tracking-normal not-italic leading-5 [&_svg]:size-3',
        TONS_SELO[tom],
      )}
    >
      {children}
    </span>
  )
}

export function Indicador({ rotulo, valor, detalhe, tom }: { rotulo: string; valor: ReactNode; detalhe?: ReactNode; tom?: Tom }) {
  return (
    <div className="relative min-w-0 overflow-hidden rounded-cartao border border-borda bg-cartao p-4 shadow-cartao sm:p-5">
      <p className="text-[11px] font-bold tracking-[0.14em] text-lavanda uppercase sm:text-xs">{rotulo}</p>
      <p
        className={clsx(
          'numero mt-3 text-[17px] leading-tight font-medium tracking-tight break-words min-[420px]:text-xl sm:text-[22px] xl:text-[26px]',
          TONS_TEXTO[tom ?? 'neutro'],
        )}
      >
        {valor}
      </p>
      {detalhe && <p className="mt-2 text-xs text-lavanda">{detalhe}</p>}
    </div>
  )
}

// ------------------------------------------------------------------- Tabela
export interface Coluna<T> {
  id: string
  titulo: ReactNode
  render(l: T): ReactNode
  alinhar?: 'esquerda' | 'direita' | 'centro'
  ocultarNoCelular?: boolean
}

const ALINHAR = { esquerda: 'text-left', direita: 'text-right', centro: 'text-center' } as const

function teclaAtivar(fn?: () => void) {
  return fn
    ? (e: KeyboardEventReact) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          fn()
        }
      }
    : undefined
}

export function Tabela<T>({
  colunas,
  linhas,
  chave,
  vazio,
  carregando,
  aoClicarLinha,
}: {
  colunas: Coluna<T>[]
  linhas: T[]
  chave(l: T): string
  vazio?: ReactNode
  carregando?: boolean
  aoClicarLinha?(l: T): void
}) {
  if (carregando)
    return (
      <div className="flex flex-col gap-2" aria-busy="true">
        <span className="sr-only">Carregando…</span>
        {[0, 1, 2, 3].map((i) => (
          <Esqueleto key={i} className="h-12 w-full" />
        ))}
      </div>
    )
  if (linhas.length === 0) return <>{vazio ?? <Vazio titulo="Nada por aqui" />}</>
  const [principal, ...demais] = colunas
  const noCelular = demais.filter((c) => !c.ocultarNoCelular)
  return (
    <>
      {/* desktop / tablet */}
      <div className="hidden overflow-x-auto rounded-cartao border border-borda bg-cartao md:block">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="bg-cartao-2/70">
              {colunas.map((c) => (
                <th
                  key={c.id}
                  scope="col"
                  className={clsx(
                    'px-4 py-3 text-[11px] font-bold tracking-[0.14em] whitespace-nowrap text-lavanda uppercase first:pl-5 last:pr-5',
                    ALINHAR[c.alinhar ?? 'esquerda'],
                  )}
                >
                  {c.titulo}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => {
              const clicar = aoClicarLinha ? () => aoClicarLinha(l) : undefined
              return (
                <tr
                  key={chave(l)}
                  onClick={clicar}
                  onKeyDown={teclaAtivar(clicar)}
                  tabIndex={clicar ? 0 : undefined}
                  className={clsx(
                    'border-t border-borda transition-colors',
                    clicar && 'cursor-pointer hover:bg-cartao-2 focus-visible:bg-cartao-2 focus-visible:outline-none',
                  )}
                >
                  {colunas.map((c) => (
                    <td key={c.id} className={clsx('px-4 py-3.5 text-creme first:pl-5 last:pr-5', ALINHAR[c.alinhar ?? 'esquerda'])}>
                      {c.render(l)}
                    </td>
                  ))}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      {/* celular: lista de cartões */}
      <ul className="flex flex-col gap-2.5 md:hidden">
        {linhas.map((l) => {
          const clicar = aoClicarLinha ? () => aoClicarLinha(l) : undefined
          return (
            <li
              key={chave(l)}
              onClick={clicar}
              onKeyDown={teclaAtivar(clicar)}
              tabIndex={clicar ? 0 : undefined}
              role={clicar ? 'button' : undefined}
              className={clsx(
                'rounded-entrada border border-borda bg-cartao p-4 text-sm',
                clicar && 'cursor-pointer active:bg-cartao-2',
                clicar && FOCO,
              )}
            >
              {principal && (
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1 font-semibold text-creme">{principal.render(l)}</div>
                  {clicar && <ChevronRight aria-hidden className="mt-0.5 size-4 shrink-0 text-lavanda" />}
                </div>
              )}
              {noCelular.length > 0 && (
                <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2.5">
                  {noCelular.map((c) => (
                    <div key={c.id} className="min-w-0">
                      <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">{c.titulo}</dt>
                      <dd className="mt-0.5 min-w-0 break-words text-creme">{c.render(l)}</dd>
                    </div>
                  ))}
                </dl>
              )}
            </li>
          )
        })}
      </ul>
    </>
  )
}

// --------------------------------------------------------------------- Abas
export function Abas<T extends string>({
  abas,
  ativa,
  aoMudar,
}: {
  abas: { id: NoInfer<T>; rotulo: ReactNode; contador?: number }[]
  ativa: T
  aoMudar(id: T): void
}) {
  const refs = useRef<(HTMLButtonElement | null)[]>([])
  function teclado(e: KeyboardEventReact, i: number) {
    const delta = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!delta) return
    e.preventDefault()
    const j = (i + delta + abas.length) % abas.length
    const alvo = abas[j]
    if (alvo) {
      aoMudar(alvo.id)
      refs.current[j]?.focus()
    }
  }
  return (
    <div role="tablist" className="-mx-1 flex gap-1 overflow-x-auto border-b border-borda px-1 [scrollbar-width:none]">
      {abas.map((a, i) => {
        const sel = a.id === ativa
        return (
          <button
            key={a.id}
            ref={(el) => {
              refs.current[i] = el
            }}
            role="tab"
            type="button"
            aria-selected={sel}
            tabIndex={sel ? 0 : -1}
            onClick={() => aoMudar(a.id)}
            onKeyDown={(e) => teclado(e, i)}
            className={clsx(
              '-mb-px inline-flex items-center gap-2 border-b-2 px-3.5 py-3 text-sm font-semibold whitespace-nowrap transition-colors',
              sel ? 'border-ouro text-creme' : 'border-transparent text-lavanda hover:text-creme',
              'focus-visible:rounded-t-md focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ouro',
            )}
          >
            {a.rotulo}
            {a.contador != null && (
              <span
                className={clsx(
                  'numero rounded-pilula px-1.5 text-[11px] leading-5',
                  sel ? 'bg-ouro/15 text-ouro-claro' : 'bg-cartao-2 text-lavanda',
                )}
              >
                {a.contador}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}

// -------------------------------------------------------------------- Modal
export function Modal({
  aberto,
  aoFechar,
  titulo,
  rodape,
  largura = 'm',
  children,
}: {
  aberto: boolean
  aoFechar(): void
  titulo: ReactNode
  rodape?: ReactNode
  largura?: 'p' | 'm' | 'g'
  children?: ReactNode
}) {
  const idTitulo = useId()
  const caixa = useRef<HTMLDivElement>(null)
  const fecharRef = useRef(aoFechar)
  fecharRef.current = aoFechar

  useEffect(() => {
    if (!aberto) return
    const anterior = document.activeElement as HTMLElement | null
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    // foca o primeiro campo (ou o próprio diálogo)
    const t = window.setTimeout(() => {
      const el = caixa.current
      if (!el || el.contains(document.activeElement)) return
      const alvo = el.querySelector<HTMLElement>('[autofocus],input:not([type=hidden]),select,textarea')
      ;(alvo ?? el).focus()
    }, 0)
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        fecharRef.current()
      }
      if (e.key === 'Tab' && caixa.current) {
        const focaveis = caixa.current.querySelectorAll<HTMLElement>(
          'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])',
        )
        const primeiro = focaveis[0]
        const ultimo = focaveis[focaveis.length - 1]
        if (!primeiro || !ultimo) return
        if (e.shiftKey && document.activeElement === primeiro) {
          e.preventDefault()
          ultimo.focus()
        } else if (!e.shiftKey && document.activeElement === ultimo) {
          e.preventDefault()
          primeiro.focus()
        }
      }
    }
    document.addEventListener('keydown', tecla)
    return () => {
      window.clearTimeout(t)
      document.removeEventListener('keydown', tecla)
      document.body.style.overflow = overflow
      anterior?.focus?.()
    }
  }, [aberto])

  if (!aberto) return null
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6">
      <div aria-hidden className="modal-fundo absolute inset-0 bg-[#02040b]/75 backdrop-blur-[2px]" onClick={aoFechar} />
      <div
        ref={caixa}
        role="dialog"
        aria-modal="true"
        aria-labelledby={idTitulo}
        tabIndex={-1}
        className={clsx(
          'modal-caixa relative flex max-h-[92dvh] w-full flex-col overflow-hidden rounded-t-cartao border border-borda bg-cartao shadow-cartao focus:outline-none sm:rounded-cartao',
          { p: 'sm:max-w-md', m: 'sm:max-w-lg', g: 'sm:max-w-3xl' }[largura],
        )}
      >
        <header className="flex items-start justify-between gap-4 border-b border-borda px-5 py-4 sm:px-6">
          <h2 id={idTitulo} className="font-display text-xl leading-snug text-creme">
            {titulo}
          </h2>
          <button
            type="button"
            onClick={aoFechar}
            aria-label="Fechar"
            className={clsx('-mr-1.5 rounded-lg p-1.5 text-lavanda transition-colors hover:bg-cartao-2 hover:text-creme', FOCO)}
          >
            <X aria-hidden className="size-5" />
          </button>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5 sm:px-6">{children}</div>
        {rodape && (
          <footer className="flex flex-wrap justify-end gap-2 border-t border-borda bg-noite-2/60 px-5 py-4 pb-[calc(env(safe-area-inset-bottom)+16px)] sm:px-6 sm:pb-4">
            {rodape}
          </footer>
        )}
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ estados
export function Vazio({ titulo, descricao, acao, icone }: { titulo: string; descricao?: ReactNode; acao?: ReactNode; icone?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-cartao border border-dashed border-borda-forte/70 px-6 py-12 text-center">
      <div className="mb-2 grid size-12 place-items-center rounded-full border border-borda bg-cartao-2 text-ouro [&_svg]:size-5">
        {icone ?? <Inbox aria-hidden />}
      </div>
      <p className="font-display text-xl text-creme">{titulo}</p>
      {descricao && <p className="max-w-md text-sm leading-relaxed text-lavanda">{descricao}</p>}
      {acao && <div className="mt-3">{acao}</div>}
    </div>
  )
}

export function Carregando({ texto = 'Carregando…' }: { texto?: string }) {
  return (
    <div role="status" className="flex items-center justify-center gap-3 p-10 text-sm text-lavanda">
      <Girador className="text-ouro" />
      {texto}
    </div>
  )
}

export function Esqueleto({ className }: { className?: string }) {
  return <div aria-hidden className={clsx('esqueleto rounded-entrada', className)} />
}

export function ErroCarga({ erro, aoTentar }: { erro: unknown; aoTentar?(): void }) {
  return (
    <div role="alert" className="flex flex-col items-start gap-3 rounded-cartao border border-perigo/35 bg-perigo/5 p-5 text-sm sm:flex-row sm:items-center">
      <AlertTriangle aria-hidden className="size-5 shrink-0 text-perigo" />
      <div className="min-w-0 flex-1">
        <p className="font-semibold text-creme">Não foi possível carregar.</p>
        <p className="mt-0.5 text-lavanda">{mensagemDeErro(erro)}</p>
      </div>
      {aoTentar && (
        <Botao variante="secundario" tamanho="p" onClick={aoTentar} icone={<RotateCcw aria-hidden />}>
          Tentar de novo
        </Botao>
      )}
    </div>
  )
}
