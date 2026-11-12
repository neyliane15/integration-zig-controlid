/**
 * Gráfico de barras simples por dia (CSS puro, sem dependência), empilhando até 3 séries.
 * Mesmo visual do gráfico de faturamento de Vendas.
 */
import clsx from 'clsx'
import { diaSemanaCurto, formatarCentavos, formatarData, formatarDataCurta } from '@/lib/formato'

export interface SerieBarras {
  id: string
  rotulo: string
  /** classe Tailwind de fundo (tokens do tema) */
  cor: string
}

export interface PontoBarras {
  data: string
  valores: Record<string, number>
}

export function GraficoBarrasDias({ pontos, series, titulo }: { pontos: PontoBarras[]; series: SerieBarras[]; titulo: string }) {
  const totais = pontos.map((p) => series.reduce((s, x) => s + Math.max(0, p.valores[x.id] ?? 0), 0))
  const maximo = totais.reduce((m, v) => Math.max(m, v), 0)
  const muitos = pontos.length > 31
  const passoRotulo = pontos.length <= 14 ? 1 : pontos.length <= 31 ? 3 : Math.ceil(pontos.length / 10)
  return (
    <figure className="min-w-0">
      <figcaption className="sr-only">
        {titulo}, máximo de {formatarCentavos(maximo)} em um dia
      </figcaption>
      <div className="flex h-44 items-end gap-px sm:gap-1" role="list">
        {pontos.map((p, i) => {
          const total = totais[i] ?? 0
          const descricao = `${formatarData(p.data)} (${diaSemanaCurto(p.data)}): ${formatarCentavos(total)}${series
            .filter((s) => (p.valores[s.id] ?? 0) > 0)
            .map((s) => ` · ${s.rotulo} ${formatarCentavos(p.valores[s.id] ?? 0)}`)
            .join('')}`
          return (
            <div key={p.data} role="listitem" className="group flex h-full min-w-0 flex-1 flex-col justify-end" title={descricao} aria-label={descricao}>
              {total > 0 ? (
                <div
                  className={clsx('flex w-full flex-col-reverse overflow-hidden transition-opacity group-hover:opacity-85', muitos ? 'rounded-t-[2px]' : 'rounded-t-[4px]')}
                  style={{ height: `${Math.max(1, (total / maximo) * 100)}%` }}
                >
                  {series.map((s) => {
                    const v = Math.max(0, p.valores[s.id] ?? 0)
                    return v > 0 ? <div key={s.id} className={s.cor} style={{ height: `${(v / total) * 100}%` }} /> : null
                  })}
                </div>
              ) : (
                <div className="h-[2px] w-full bg-borda" />
              )}
            </div>
          )
        })}
      </div>
      <div className="mt-1 flex gap-px overflow-hidden sm:gap-1" aria-hidden>
        {pontos.map((p, i) => (
          <span key={p.data} className="numero min-w-0 flex-1 overflow-visible text-center text-[10px] whitespace-nowrap text-lavanda">
            {i % passoRotulo === 0 ? formatarDataCurta(p.data) : ''}
          </span>
        ))}
      </div>
      {series.length > 1 && (
        <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-lavanda" aria-hidden>
          {series.map((s) => (
            <li key={s.id} className="inline-flex items-center gap-1.5">
              <span className={clsx('size-2.5 rounded-sm', s.cor)} />
              {s.rotulo}
            </li>
          ))}
        </ul>
      )}
    </figure>
  )
}
