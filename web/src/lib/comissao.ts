/**
 * Prévia de comissão — réplica exata do contrato §9 (o banco é a fonte oficial; esta prévia tem de bater centavo a centavo).
 * Dono: frontend-2. Aritmética inteira com BigInt (pontos em escala 10⁶, como numeric(18,6)), sem ponto flutuante.
 */

export interface ParticipanteComissao {
  /** id do funcionário (desempate final); null para snapshot de funcionário excluído */
  funcionarioId: string | null
  nome: string
  cargo?: string | null
  incluido: boolean
  /** numeric(8,2) */
  pontos: number
  diasTrabalhados: number
}

export interface EntradaComissao {
  servicoZigCentavos: number
  servicoAjusteCentavos: number
  /** numeric(5,2), 0..100 */
  percentualRetencao: number
  proporcionalDias: boolean
  /** 'AAAA-MM-DD' */
  dataInicio: string
  dataFim: string
  participantes: ParticipanteComissao[]
}

export interface ItemCalculado extends ParticipanteComissao {
  /** numeric(18,6) */
  pontosEfetivos: number
  /** base × pe / soma, sem arredondar (só para exibir) */
  exatoCentavos: number
  valorCentavos: number
  /** recebeu +1 centavo no rateio do maior resto */
  centavoExtra: boolean
}

export interface ResultadoComissao {
  servicoZigCentavos: number
  servicoAjusteCentavos: number
  servicoBrutoCentavos: number
  percentualRetencao: number
  retencaoCentavos: number
  baseCentavos: number
  diasPeriodo: number
  somaPontosEfetivos: number
  /** base / soma com 6 casas; null se soma = 0 */
  valorPontoCentavos: number | null
  itens: ItemCalculado[]
  totalDistribuidoCentavos: number
  /** soma = 0 → o banco recusa fechar ('Fechamento sem participantes') */
  semParticipantes: boolean
}

const ESCALA = 1_000_000n

/** Divisão inteira com arredondamento "meio para longe do zero" (round() do Postgres em numeric). */
function dividirArredondando(n: bigint, d: bigint): bigint {
  if (d === 0n) throw new Error('divisão por zero')
  const negativo = n < 0n !== d < 0n
  const an = n < 0n ? -n : n
  const ad = d < 0n ? -d : d
  let q = an / ad
  if ((an % ad) * 2n >= ad) q += 1n
  return negativo ? -q : q
}

/** Número decimal → inteiro na escala 10^casas, arredondando meio para longe do zero. */
function escalar(v: number, casas: number): bigint {
  const texto = Math.abs(v).toFixed(casas + 2) // folga para arredondar uma única vez
  const [int = '0', frac = ''] = texto.split('.')
  const bruto = BigInt(int + frac) // escala 10^(casas+2)
  const r = dividirArredondando(bruto, 100n)
  return v < 0 ? -r : r
}

function paraNumero(v: bigint, escala: bigint): number {
  return Number(v) / Number(escala)
}

/** Dias corridos do período, inclusivo: data_fim − data_inicio + 1. */
export function diasDoPeriodo(inicio: string, fim: string): number {
  const ms = Date.parse(`${fim.slice(0, 10)}T00:00:00Z`) - Date.parse(`${inicio.slice(0, 10)}T00:00:00Z`)
  return Math.round(ms / 86_400_000) + 1
}

function compararTexto(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

export function calcularComissao(e: EntradaComissao): ResultadoComissao {
  const zig = BigInt(Math.trunc(e.servicoZigCentavos))
  const ajuste = BigInt(Math.trunc(e.servicoAjusteCentavos))
  // 2. bruto = max(0, zig + ajuste)
  const somaBruta = zig + ajuste
  const bruto = somaBruta > 0n ? somaBruta : 0n
  // 3. retenção = round(bruto × % / 100); base = bruto − retenção
  const pct100 = escalar(e.percentualRetencao, 2) // % × 100
  const retencao = dividirArredondando(bruto * pct100, 10_000n)
  const base = bruto - retencao
  // 5. dias do período
  const diasPeriodo = diasDoPeriodo(e.dataInicio, e.dataFim)
  // 6. pontos efetivos (escala 10⁶)
  const efetivos = e.participantes.map((p) => {
    if (!p.incluido) return 0n
    const pontos6 = escalar(p.pontos, 2) * 10_000n
    if (!e.proporcionalDias) return pontos6
    if (diasPeriodo <= 0) return 0n
    return dividirArredondando(pontos6 * BigInt(Math.trunc(p.diasTrabalhados)), BigInt(diasPeriodo))
  })
  // 7. soma
  const soma = efetivos.reduce((s, v) => s + v, 0n)

  if (soma === 0n) {
    const itens = e.participantes.map<ItemCalculado>((p, i) => ({
      ...p,
      pontosEfetivos: paraNumero(efetivos[i] ?? 0n, ESCALA),
      exatoCentavos: 0,
      valorCentavos: 0,
      centavoExtra: false,
    }))
    return {
      servicoZigCentavos: Number(zig),
      servicoAjusteCentavos: Number(ajuste),
      servicoBrutoCentavos: Number(bruto),
      percentualRetencao: e.percentualRetencao,
      retencaoCentavos: Number(retencao),
      baseCentavos: Number(base),
      diasPeriodo,
      somaPontosEfetivos: 0,
      valorPontoCentavos: null,
      itens,
      totalDistribuidoCentavos: 0,
      semParticipantes: true,
    }
  }

  // 9. maior resto: exato_i = base × pe_i / soma → piso + resto (mesmo denominador: compara restos inteiros)
  const parciais = e.participantes.map((p, i) => {
    const pe = efetivos[i] ?? 0n
    const numerador = base * pe
    return { indice: i, p, pe, piso: numerador / soma, resto: numerador % soma }
  })
  const somaPisos = parciais.reduce((s, v) => s + v.piso, 0n)
  let sobra = Number(base - somaPisos)
  const ordem = parciais
    .filter((x) => x.p.incluido && x.pe > 0n)
    .sort((a, b) => {
      if (a.resto !== b.resto) return a.resto > b.resto ? -1 : 1
      if (a.pe !== b.pe) return a.pe > b.pe ? -1 : 1
      const nome = compararTexto(a.p.nome, b.p.nome)
      if (nome !== 0) return nome
      return compararTexto(a.p.funcionarioId ?? '', b.p.funcionarioId ?? '')
    })
  const extra = new Set<number>()
  for (const x of ordem) {
    if (sobra <= 0) break
    extra.add(x.indice)
    sobra -= 1
  }

  const itens = parciais.map<ItemCalculado>((x) => ({
    ...x.p,
    pontosEfetivos: paraNumero(x.pe, ESCALA),
    exatoCentavos: Number(base * x.pe) / Number(soma),
    valorCentavos: Number(x.piso) + (extra.has(x.indice) ? 1 : 0),
    centavoExtra: extra.has(x.indice),
  }))

  return {
    servicoZigCentavos: Number(zig),
    servicoAjusteCentavos: Number(ajuste),
    servicoBrutoCentavos: Number(bruto),
    percentualRetencao: e.percentualRetencao,
    retencaoCentavos: Number(retencao),
    baseCentavos: Number(base),
    diasPeriodo,
    somaPontosEfetivos: paraNumero(soma, ESCALA),
    // 8. valor do ponto (6 casas)
    valorPontoCentavos: paraNumero(dividirArredondando(base * ESCALA * ESCALA, soma), ESCALA),
    itens,
    totalDistribuidoCentavos: itens.reduce((s, i) => s + i.valorCentavos, 0),
    semParticipantes: false,
  }
}

/** Título padrão de um fechamento: 'Comissão dd/mm a dd/mm/aaaa'. */
export function tituloPadraoFechamento(inicio: string, fim: string): string {
  const [ai, mi, di] = inicio.slice(0, 10).split('-')
  const [af, mf, df] = fim.slice(0, 10).split('-')
  const inicioTexto = ai === af ? `${di}/${mi}` : `${di}/${mi}/${ai}`
  return `Comissão ${inicioTexto} a ${df}/${mf}/${af}`
}

/** Valida o período do fechamento como o banco (check comissao_periodo). Retorna mensagem ou null. */
export function validarPeriodoFechamento(inicio: string | null, fim: string | null): string | null {
  if (!inicio || !fim) return 'Informe o período'
  const dias = diasDoPeriodo(inicio, fim)
  if (dias < 1) return 'Período inválido'
  if (dias - 1 > 92) return 'Período máximo de 93 dias'
  return null
}
