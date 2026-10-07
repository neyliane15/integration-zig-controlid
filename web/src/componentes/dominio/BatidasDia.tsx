/**
 * Batidas de um dia como "fichas" (horário + marcações), com as que faltam em destaque. Dono: frontend-2.
 */
import clsx from 'clsx'
import { PenLine, Plus } from 'lucide-react'
import type { BatidaEsperada, BatidaEspelho, EsperadaEspelho } from '@/tipos/banco'
import { FOCO } from '@/componentes/ui'
import { formatarHora } from '@/lib/formato'
import { rotuloBatidaEsperada, rotuloOrigemBatida } from '@/lib/rotulos'

export function BatidasDia({
  batidas,
  fuso,
  faltantes = [],
  esperadas = [],
  aoClicarBatida,
  aoClicarFaltante,
}: {
  batidas: BatidaEspelho[]
  fuso?: string
  /** slots que faltam (ver `identificarFaltantes`) */
  faltantes?: BatidaEsperada[]
  esperadas?: EsperadaEspelho[]
  aoClicarBatida?(b: BatidaEspelho): void
  /** clique numa batida faltante (ex.: abrir "Incluir batida" já com o horário previsto) */
  aoClicarFaltante?(e: EsperadaEspelho): void
}) {
  const ordenadas = [...batidas].sort((a, b) => a.instante.localeCompare(b.instante))
  const faltando = esperadas.filter((e) => faltantes.includes(e.batida))
  if (ordenadas.length === 0 && faltando.length === 0) return <span className="text-sm text-lavanda-escuro">—</span>

  // intercala as faltantes na ordem do horário previsto
  type Ficha = { tipo: 'b'; b: BatidaEspelho; t: string } | { tipo: 'f'; e: EsperadaEspelho; t: string }
  const fichas: Ficha[] = [
    ...ordenadas.map<Ficha>((b) => ({ tipo: 'b', b, t: b.instante })),
    ...faltando.map<Ficha>((e) => ({ tipo: 'f', e, t: e.instante })),
  ].sort((x, y) => new Date(x.t).getTime() - new Date(y.t).getTime())

  return (
    <ul className="flex flex-wrap gap-1.5" aria-label="Batidas do dia">
      {fichas.map((f) => {
        if (f.tipo === 'f') {
          const rotulo = `Faltou: ${rotuloBatidaEsperada[f.e.batida]} (prevista ${formatarHora(f.e.instante, fuso)})`
          const conteudo = (
            <>
              {aoClicarFaltante ? <Plus aria-hidden className="size-3" /> : null}
              <span className="numero">{formatarHora(f.e.instante, fuso)}</span>
              <span className="text-[10px] font-bold uppercase tracking-wider">falta</span>
            </>
          )
          const classe = 'inline-flex h-7 items-center gap-1 rounded-pilula border border-dashed border-alerta/70 bg-alerta/10 px-2 text-xs text-alerta'
          return (
            <li key={`f-${f.e.batida}`}>
              {aoClicarFaltante ? (
                <button type="button" className={clsx(classe, 'hover:bg-alerta/20', FOCO)} title={rotulo} aria-label={`${rotulo}. Incluir batida`} onClick={(ev) => { ev.stopPropagation(); aoClicarFaltante(f.e) }}>
                  {conteudo}
                </button>
              ) : (
                <span className={classe} title={rotulo} aria-label={rotulo}>
                  {conteudo}
                </span>
              )}
            </li>
          )
        }
        const b = f.b
        const estado = b.desconsiderada ? 'desconsiderada' : b.duplicada ? 'duplicada (ignorada)' : 'válida'
        const titulo = `${formatarHora(b.instante, fuso)} · ${rotuloOrigemBatida[b.origem]} · ${estado}${b.motivo ? ` · ${b.motivo}` : ''}`
        const classe = clsx(
          'inline-flex h-7 items-center gap-1 rounded-pilula border px-2 text-xs',
          b.desconsiderada
            ? 'border-borda text-lavanda-escuro line-through'
            : b.duplicada
              ? 'border-borda text-lavanda'
              : b.origem === 'manual'
                ? 'border-info/40 bg-info/10 text-info'
                : 'border-borda-forte bg-cartao-2 text-creme',
        )
        const conteudo = (
          <>
            {b.origem === 'manual' && <PenLine aria-hidden className="size-3" />}
            <span className="numero">{formatarHora(b.instante, fuso)}</span>
            {b.duplicada && !b.desconsiderada && <span className="text-[10px] uppercase">dup.</span>}
          </>
        )
        return (
          <li key={b.id}>
            {aoClicarBatida ? (
              <button
                type="button"
                className={clsx(classe, 'hover:border-ouro/60', FOCO)}
                title={titulo}
                aria-label={`Batida ${titulo}. Abrir ações`}
                onClick={(ev) => {
                  ev.stopPropagation()
                  aoClicarBatida(b)
                }}
              >
                {conteudo}
              </button>
            ) : (
              <span className={classe} title={titulo} aria-label={`Batida ${titulo}`}>
                {conteudo}
              </span>
            )}
          </li>
        )
      })}
    </ul>
  )
}
