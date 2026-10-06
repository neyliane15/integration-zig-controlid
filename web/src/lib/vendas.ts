/**
 * Agregações e ordenações de vendas (Zig) para gráficos, ranking e CSV. Dono: frontend-2. Funções puras.
 * Dinheiro sempre em centavos (inteiros).
 */
import type { FaturamentoPorDia, FaturamentoPorForma, VendaPorGarcom, VendasResumo } from '@/tipos/banco'

export const ROTULO_SEM_GARCOM = '(sem garçom)'

function somarDiasCivil(iso: string, n: number): string {
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1, (d ?? 1) + n)).toISOString().slice(0, 10)
}

/** Lista de datas de [inicio, fim] (inclusivo). Período invertido → []. */
export function diasDoIntervalo(inicio: string, fim: string): string[] {
  const dias: string[] = []
  for (let d = inicio; d <= fim && dias.length < 1000; d = somarDiasCivil(d, 1)) dias.push(d)
  return dias
}

/** Garante uma linha por dia do período (dias sem dado = 0); soma linhas repetidas do mesmo dia. */
export function preencherDias(inicio: string, fim: string, linhas: FaturamentoPorDia[]): FaturamentoPorDia[] {
  const mapa = new Map<string, number>()
  for (const l of linhas) mapa.set(l.data, (mapa.get(l.data) ?? 0) + Number(l.valor))
  return diasDoIntervalo(inicio, fim).map((data) => ({ data, valor: mapa.get(data) ?? 0 }))
}

export interface Barra<T> {
  item: T
  /** 0..100, relativo ao maior valor (positivo) */
  percentual: number
}

/** Altura das barras (CSS) relativa ao maior valor. Valores ≤ 0 → 0%. */
export function escalaBarras<T extends { valor: number }>(linhas: T[]): { barras: Barra<T>[]; maximo: number } {
  const maximo = linhas.reduce((m, l) => Math.max(m, Number(l.valor)), 0)
  return {
    maximo,
    barras: linhas.map((item) => ({
      item,
      percentual: maximo > 0 && item.valor > 0 ? Math.max(1, Math.round((Number(item.valor) / maximo) * 1000) / 10) : 0,
    })),
  }
}

export interface EstatisticasDias {
  total: number
  diasComMovimento: number
  /** média dos dias com movimento (centavos, arredondada) */
  mediaPorDiaComMovimento: number
  melhor: FaturamentoPorDia | null
  pior: FaturamentoPorDia | null
}

export function estatisticasDias(linhas: FaturamentoPorDia[]): EstatisticasDias {
  const com = linhas.filter((l) => l.valor > 0)
  const total = linhas.reduce((s, l) => s + Number(l.valor), 0)
  let melhor: FaturamentoPorDia | null = null
  let pior: FaturamentoPorDia | null = null
  for (const l of com) {
    if (!melhor || l.valor > melhor.valor) melhor = l
    if (!pior || l.valor < pior.valor) pior = l
  }
  return {
    total,
    diasComMovimento: com.length,
    mediaPorDiaComMovimento: com.length ? Math.round(total / com.length) : 0,
    melhor,
    pior,
  }
}

export interface FormaComParticipacao extends FaturamentoPorForma {
  percentual: number
}

/** Formas de pagamento ordenadas por valor desc (empate: nome) com participação % (1 casa). */
export function participacaoPorForma(formas: FaturamentoPorForma[]): { formas: FormaComParticipacao[]; total: number } {
  const total = formas.reduce((s, f) => s + Number(f.valor), 0)
  const ordenadas = [...formas].sort((a, b) => b.valor - a.valor || a.payment_name.localeCompare(b.payment_name, 'pt-BR'))
  return {
    total,
    formas: ordenadas.map((f) => ({ ...f, percentual: total > 0 ? Math.round((Number(f.valor) / total) * 1000) / 10 : 0 })),
  }
}

export interface LinhaRanking extends VendaPorGarcom {
  posicao: number
  nomeExibido: string
  /** participação nas vendas do período (%) */
  percentual: number
  /** valor_vendas / transacoes (centavos) */
  ticketMedio: number
}

/** Ranking por vendas desc (empate: serviço desc, nome asc). "(sem garçom)" vai sempre para o fim, sem posição. */
export function rankingGarcons(linhas: VendaPorGarcom[]): LinhaRanking[] {
  const total = linhas.reduce((s, l) => s + Number(l.valor_vendas), 0)
  const nome = (l: VendaPorGarcom) => l.employee_name?.trim() || ROTULO_SEM_GARCOM
  const ordenadas = [...linhas].sort((a, b) => {
    const semA = !a.employee_name?.trim()
    const semB = !b.employee_name?.trim()
    if (semA !== semB) return semA ? 1 : -1
    return b.valor_vendas - a.valor_vendas || b.valor_servico - a.valor_servico || nome(a).localeCompare(nome(b), 'pt-BR')
  })
  let posicao = 0
  return ordenadas.map((l) => {
    const sem = !l.employee_name?.trim()
    if (!sem) posicao += 1
    return {
      ...l,
      posicao: sem ? 0 : posicao,
      nomeExibido: nome(l),
      percentual: total > 0 ? Math.round((Number(l.valor_vendas) / total) * 1000) / 10 : 0,
      ticketMedio: l.transacoes > 0 ? Math.round(Number(l.valor_vendas) / Number(l.transacoes)) : 0,
    }
  })
}

export interface Indicadores {
  faturamento: number
  vendas: number
  servico: number
  descontos: number
  transacoes: number
  ticketMedio: number
  /** serviço / vendas (%) com 1 casa */
  percentualServico: number
  /** diferença entre o serviço dos itens Tip e o tip_value dos compradores (conferência) */
  divergenciaServico: number
}

export function indicadores(r: VendasResumo | null | undefined): Indicadores {
  const v = r ?? { faturamento: 0, vendas: 0, servico: 0, descontos: 0, transacoes: 0, servico_compradores: 0 }
  const n = (x: number | string) => Number(x) || 0
  return {
    faturamento: n(v.faturamento),
    vendas: n(v.vendas),
    servico: n(v.servico),
    descontos: n(v.descontos),
    transacoes: n(v.transacoes),
    ticketMedio: n(v.transacoes) > 0 ? Math.round(n(v.faturamento) / n(v.transacoes)) : 0,
    percentualServico: n(v.vendas) > 0 ? Math.round((n(v.servico) / n(v.vendas)) * 1000) / 10 : 0,
    divergenciaServico: n(v.servico) - n(v.servico_compradores),
  }
}

export interface RegistroFaturamento {
  data_operacao: string
  payment_name: string
  valor: number
}

/** Agrupa linhas de `zig_faturamento` por (dia, forma) para o CSV `faturamento_…`, ordenado por data e valor desc. */
export function faturamentoDiaForma(registros: RegistroFaturamento[]): { data: string; forma: string; valor: number }[] {
  const mapa = new Map<string, { data: string; forma: string; valor: number }>()
  for (const r of registros) {
    const chave = `${r.data_operacao}\u0000${r.payment_name}`
    const atual = mapa.get(chave) ?? { data: r.data_operacao, forma: r.payment_name, valor: 0 }
    atual.valor += Number(r.valor)
    mapa.set(chave, atual)
  }
  return [...mapa.values()].sort((a, b) => a.data.localeCompare(b.data) || b.valor - a.valor || a.forma.localeCompare(b.forma, 'pt-BR'))
}

/** Valida o período de consulta de vendas (máx. 366 dias). */
export function validarPeriodoVendas(inicio: string, fim: string): string | null {
  if (!inicio || !fim || fim < inicio) return 'Período inválido'
  if (diasDoIntervalo(inicio, fim).length > 366) return 'Período máximo de 366 dias'
  return null
}
