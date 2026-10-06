/**
 * Design system — componentes compartilhados (contrato §14.5).
 * Dono: frontend-1. As PROPS são contrato: frontend-2 usa estes componentes em paralelo.
 * Esta é a versão inicial (funcional e simples); o frontend-1 refina o visual sem mudar as assinaturas.
 */
import {
  forwardRef,
  useEffect,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react'
import clsx from 'clsx'

export type Tom = 'neutro' | 'ouro' | 'sucesso' | 'alerta' | 'perigo' | 'info'

// ------------------------------------------------------------------- Botao
export interface BotaoProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variante?: 'primario' | 'secundario' | 'fantasma' | 'perigo'
  tamanho?: 'p' | 'm' | 'g'
  carregando?: boolean
  icone?: ReactNode
}

const VARIANTES: Record<NonNullable<BotaoProps['variante']>, string> = {
  primario: 'bg-ouro text-tinta-ouro hover:bg-ouro-escuro font-bold',
  secundario: 'border border-borda bg-transparent text-creme hover:border-borda-forte',
  fantasma: 'bg-transparent text-lavanda hover:text-creme',
  perigo: 'bg-perigo text-noite hover:opacity-90 font-bold',
}
const TAMANHOS: Record<NonNullable<BotaoProps['tamanho']>, string> = {
  p: 'h-8 px-3 text-sm',
  m: 'h-11 px-4 text-sm',
  g: 'h-12 px-5 text-base',
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
        'inline-flex items-center justify-center gap-2 rounded-entrada transition-colors disabled:cursor-not-allowed disabled:opacity-50',
        VARIANTES[variante],
        TAMANHOS[tamanho],
        className,
      )}
      {...resto}
    >
      {carregando ? <span className="size-4 animate-spin rounded-full border-2 border-current border-t-transparent" /> : icone}
      {children}
    </button>
  )
})

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
    <div className="flex flex-col gap-1.5">
      <label htmlFor={htmlFor} className="text-sm font-semibold text-lavanda">
        {rotulo}
        {obrigatorio && <span className="ml-0.5 text-ouro">*</span>}
      </label>
      {children}
      {erro ? <p className="text-xs text-perigo">{erro}</p> : ajuda ? <p className="text-xs text-lavanda-escuro">{ajuda}</p> : null}
    </div>
  )
}

const CLASSE_ENTRADA =
  'h-11 w-full rounded-entrada border border-borda bg-entrada px-3 text-creme placeholder:text-lavanda-escuro focus:border-borda-forte focus:outline-none disabled:opacity-60'

export const Entrada = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement> & { invalido?: boolean }>(
  function Entrada({ invalido, className, ...resto }, ref) {
    return (
      <input ref={ref} aria-invalid={invalido || undefined} className={clsx(CLASSE_ENTRADA, invalido && 'border-perigo', className)} {...resto} />
    )
  },
)

export const Selecao = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Selecao(
  { className, ...resto },
  ref,
) {
  return <select ref={ref} className={clsx(CLASSE_ENTRADA, className)} {...resto} />
})

export const AreaTexto = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function AreaTexto(
  { className, ...resto },
  ref,
) {
  return <textarea ref={ref} className={clsx(CLASSE_ENTRADA, 'h-auto min-h-24 py-2', className)} {...resto} />
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
    <label className="inline-flex cursor-pointer items-center gap-2 text-sm text-creme">
      <input
        type="checkbox"
        className="size-4 accent-ouro"
        checked={marcado}
        disabled={desabilitado}
        onChange={(e) => aoMudar(e.target.checked)}
      />
      {rotulo}
    </label>
  )
}

export function Interruptor({ rotulo, marcado, aoMudar, desabilitado }: PropsMarcavel) {
  return (
    <label className="inline-flex cursor-pointer items-center gap-3 text-sm text-creme">
      <button
        type="button"
        role="switch"
        aria-checked={marcado}
        disabled={desabilitado}
        onClick={() => aoMudar(!marcado)}
        className={clsx('relative h-6 w-11 rounded-pilula transition-colors', marcado ? 'bg-ouro' : 'bg-borda')}
      >
        <span className={clsx('absolute top-0.5 size-5 rounded-full bg-creme transition-all', marcado ? 'left-5.5' : 'left-0.5')} />
      </button>
      {rotulo}
    </label>
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
  const texto = centavos == null ? '' : (centavos / 100).toFixed(2).replace('.', ',')
  return (
    <Entrada
      id={id}
      inputMode="decimal"
      disabled={desabilitado}
      defaultValue={texto}
      key={texto}
      onBlur={(e) => {
        const limpo = e.target.value.replace(/\./g, '').replace(',', '.').trim()
        if (limpo === '') return aoMudar(null)
        const n = Math.round(Number(limpo) * 100)
        if (Number.isNaN(n)) return aoMudar(centavos)
        aoMudar(permitirNegativo ? n : Math.abs(n))
      }}
    />
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
  return <Entrada id={id} type="date" value={valor ?? ''} min={min} max={max} onChange={(e) => aoMudar(e.target.value || null)} />
}

export function EntradaHora({ valor, aoMudar, id }: { valor: string | null; aoMudar(v: string | null): void; id?: string }) {
  return <Entrada id={id} type="time" value={valor?.slice(0, 5) ?? ''} onChange={(e) => aoMudar(e.target.value || null)} />
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
  void atalhos // atalhos (Hoje, Ontem, 7 dias, Este mês, Mês anterior): frontend-1 implementa
  return (
    <div className="flex flex-wrap items-end gap-2">
      <EntradaData valor={inicio} aoMudar={(v) => v && aoMudar(v, fim)} max={fim} />
      <span className="pb-3 text-lavanda">a</span>
      <EntradaData valor={fim} aoMudar={(v) => v && aoMudar(inicio, v)} min={inicio} />
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
    <section className={clsx('rounded-cartao border border-borda bg-cartao shadow-cartao', !semPreenchimento && 'p-5', className)}>
      {(titulo || sobrancelha || acoes) && (
        <header className={clsx('mb-4 flex items-start justify-between gap-3', semPreenchimento && 'px-5 pt-5')}>
          <div>
            {sobrancelha && <p className="sobrancelha">{sobrancelha}</p>}
            {titulo && <h2 className="font-display text-xl text-creme">{titulo}</h2>}
          </div>
          {acoes}
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
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        {sobrancelha && <p className="sobrancelha">{sobrancelha}</p>}
        <h1 className="mt-1 font-display text-3xl text-creme">{titulo}</h1>
        {subtitulo && <p className="mt-1 text-sm text-lavanda">{subtitulo}</p>}
      </div>
      {acoes && <div className="flex flex-wrap gap-2">{acoes}</div>}
    </header>
  )
}

const TONS: Record<Tom, string> = {
  neutro: 'border-borda text-lavanda',
  ouro: 'border-ouro/40 text-ouro-claro',
  sucesso: 'border-sucesso/40 text-sucesso',
  alerta: 'border-alerta/40 text-alerta',
  perigo: 'border-perigo/40 text-perigo',
  info: 'border-info/40 text-info',
}

export function Selo({ tom = 'neutro', children }: { tom?: Tom; children: ReactNode }) {
  return (
    <span className={clsx('inline-flex items-center gap-1 rounded-pilula border px-2.5 py-0.5 text-xs font-semibold', TONS[tom])}>
      {children}
    </span>
  )
}

export function Indicador({ rotulo, valor, detalhe, tom }: { rotulo: string; valor: ReactNode; detalhe?: ReactNode; tom?: Tom }) {
  return (
    <div className="rounded-cartao border border-borda bg-cartao p-5">
      <p className="text-sm text-lavanda">{rotulo}</p>
      <p className={clsx('numero mt-2 text-2xl font-semibold', tom ? TONS[tom].split(' ')[1] : 'text-creme')}>{valor}</p>
      {detalhe && <p className="mt-1 text-xs text-lavanda-escuro">{detalhe}</p>}
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
  if (carregando) return <Carregando />
  if (linhas.length === 0) return <>{vazio ?? <Vazio titulo="Nada por aqui" />}</>
  return (
    <div className="overflow-x-auto rounded-cartao border border-borda">
      <table className="w-full text-sm">
        <thead className="bg-cartao-2 text-xs uppercase tracking-wider text-lavanda">
          <tr>
            {colunas.map((c) => (
              <th key={c.id} className={clsx('px-4 py-3 font-semibold', ALINHAR[c.alinhar ?? 'esquerda'], c.ocultarNoCelular && 'hidden md:table-cell')}>
                {c.titulo}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {linhas.map((l) => (
            <tr
              key={chave(l)}
              onClick={aoClicarLinha ? () => aoClicarLinha(l) : undefined}
              className={clsx('border-t border-borda', aoClicarLinha && 'cursor-pointer hover:bg-cartao-2')}
            >
              {colunas.map((c) => (
                <td key={c.id} className={clsx('px-4 py-3', ALINHAR[c.alinhar ?? 'esquerda'], c.ocultarNoCelular && 'hidden md:table-cell')}>
                  {c.render(l)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// --------------------------------------------------------------------- Abas
export function Abas<T extends string>({
  abas,
  ativa,
  aoMudar,
}: {
  abas: { id: T; rotulo: ReactNode; contador?: number }[]
  ativa: T
  aoMudar(id: T): void
}) {
  return (
    <div role="tablist" className="flex gap-1 overflow-x-auto border-b border-borda">
      {abas.map((a) => (
        <button
          key={a.id}
          role="tab"
          type="button"
          aria-selected={a.id === ativa}
          onClick={() => aoMudar(a.id)}
          className={clsx(
            '-mb-px whitespace-nowrap border-b-2 px-4 py-2.5 text-sm font-semibold',
            a.id === ativa ? 'border-ouro text-creme' : 'border-transparent text-lavanda hover:text-creme',
          )}
        >
          {a.rotulo}
          {a.contador != null && <span className="ml-2 text-xs text-lavanda">{a.contador}</span>}
        </button>
      ))}
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
  useEffect(() => {
    if (!aberto) return
    const tecla = (e: KeyboardEvent) => e.key === 'Escape' && aoFechar()
    window.addEventListener('keydown', tecla)
    return () => window.removeEventListener('keydown', tecla)
  }, [aberto, aoFechar])
  if (!aberto) return null
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-noite/80 p-4" onClick={aoFechar}>
      <div
        role="dialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
        className={clsx(
          'max-h-[90dvh] w-full overflow-y-auto rounded-cartao border border-borda bg-cartao p-6 shadow-cartao',
          { p: 'max-w-sm', m: 'max-w-lg', g: 'max-w-3xl' }[largura],
        )}
      >
        <h2 className="mb-4 font-display text-xl text-creme">{titulo}</h2>
        {children}
        {rodape && <div className="mt-6 flex flex-wrap justify-end gap-2">{rodape}</div>}
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ estados
export function Vazio({ titulo, descricao, acao, icone }: { titulo: string; descricao?: ReactNode; acao?: ReactNode; icone?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-cartao border border-dashed border-borda p-10 text-center">
      {icone && <div className="text-lavanda">{icone}</div>}
      <p className="font-display text-lg text-creme">{titulo}</p>
      {descricao && <p className="text-sm text-lavanda">{descricao}</p>}
      {acao && <div className="mt-2">{acao}</div>}
    </div>
  )
}

export function Carregando({ texto = 'Carregando…' }: { texto?: string }) {
  return (
    <div role="status" className="flex items-center justify-center gap-3 p-10 text-sm text-lavanda">
      <span className="size-4 animate-spin rounded-full border-2 border-ouro border-t-transparent" />
      {texto}
    </div>
  )
}

export function Esqueleto({ className }: { className?: string }) {
  return <div className={clsx('animate-pulse rounded-entrada bg-cartao-2', className)} />
}

export function ErroCarga({ erro, aoTentar }: { erro: unknown; aoTentar?(): void }) {
  const mensagem = erro instanceof Error ? erro.message : typeof erro === 'object' && erro && 'message' in erro ? String(erro.message) : String(erro)
  return (
    <div role="alert" className="rounded-cartao border border-perigo/40 bg-cartao p-5 text-sm">
      <p className="text-perigo">{mensagem}</p>
      {aoTentar && (
        <Botao variante="secundario" tamanho="p" className="mt-3" onClick={aoTentar}>
          Tentar de novo
        </Botao>
      )}
    </div>
  )
}
