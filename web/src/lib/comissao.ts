/**
 * Prévia de comissão — réplica exata do contrato §9 (modo período) e do adendo E.3 (rateio diário) (o banco é a fonte oficial; esta prévia tem de bater centavo a centavo).
 * Dono: frontend-2. Aritmética inteira com BigInt (pontos em escala 10⁶, como numeric(18,6)), sem ponto flutuante.
 */
import { centavosCsv, dataCsv, gerarCsv, nomeArquivoCsv } from './csv'

export type ModoRateio = 'diario' | 'periodo'
export type TipoParticipante = 'funcionario' | 'extra'

/** Linha de `comissao_detalhe.itens[].entrada`: funcionário → um por dia; extra → um por lançamento do período. */
export interface EntradaDiaParticipante {
  /** 'AAAA-MM-DD' */
  data: string
  presente: boolean
  /** funcionário: pontos vigentes na data; extra: pontos do lançamento (numeric(8,2)) */
  pontos: number
}

export interface ParticipanteComissao {
  /** id do item (último critério de desempate do banco) */
  itemId?: string | null
  /** padrão 'funcionario' */
  tipo?: TipoParticipante
  /** id do funcionário (desempate); null para snapshot de funcionário excluído ou para extra */
  funcionarioId: string | null
  /** id do extra (tipo 'extra') */
  extraId?: string | null
  nome: string
  cargo?: string | null
  incluido: boolean
  /** numeric(8,2). Funcionário: vigentes em data_fim ou o manual; extra: média dos lançamentos (só exibição). */
  pontos: number
  /** dias presentes (funcionário: dias com batida válida; extra: dias lançados) */
  diasTrabalhados: number
  /** funcionário: pontos fixados no rascunho (modo diário usa `pontos` em todos os dias) */
  pontosManual?: boolean
  /** E.3.4 — presença/pontos por dia (modo diário) e lançamentos do extra (os dois modos) */
  entrada?: EntradaDiaParticipante[]
}

export interface ServicoDia {
  data: string
  servicoZigCentavos: number
}

export interface EntradaComissao {
  /** padrão 'periodo' (o §9 original); fechamentos novos usam 'diario' (adendo E.3) */
  modoRateio?: ModoRateio
  /** modo período: Tips do período. Modo diário: ignorado (usa Σ `servicoDias`). */
  servicoZigCentavos: number
  servicoAjusteCentavos: number
  /** numeric(5,2), 0..100 */
  percentualRetencao: number
  /** só no modo período */
  proporcionalDias: boolean
  /** 'AAAA-MM-DD' */
  dataInicio: string
  dataFim: string
  /** modo diário: Tips por dia (dias ausentes = 0) */
  servicoDias?: ServicoDia[]
  participantes: ParticipanteComissao[]
}

export interface RateioDiaParticipante {
  /** índice em `participantes` */
  indice: number
  pontos: number
  valorCentavos: number
  fallback: boolean
  centavoExtra: boolean
}

export interface DiaCalculado {
  data: string
  servicoZigCentavos: number
  ajusteCentavos: number
  servicoBrutoCentavos: number
  retencaoCentavos: number
  baseCentavos: number
  somaPontos: number
  participantes: number
  semPresenca: boolean
  semParticipantes: boolean
  rateio: RateioDiaParticipante[]
}

export interface ItemCalculado extends ParticipanteComissao {
  /** modo período: numeric(18,6); modo diário: Σ pontos dos dias em que entrou */
  pontosEfetivos: number
  /** valor exato sem arredondar (só para exibir) */
  exatoCentavos: number
  valorCentavos: number
  /** recebeu +1 centavo no rateio do maior resto (em algum dia, no modo diário) */
  centavoExtra: boolean
  /** modo diário: dias em que entrou no rateio */
  diasNoRateio: number
}

export interface ResultadoComissao {
  modoRateio: ModoRateio
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
  /** modo diário: um por dia do período; [] no modo período */
  dias: DiaCalculado[]
  diasSemPresenca: number
  /** > 0 → o banco recusa fechar ('Há dias com serviço sem participantes para ratear') */
  diasSemParticipantes: number
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

/** Datas 'AAAA-MM-DD' do período, em ordem. */
export function datasDoPeriodo(inicio: string, fim: string): string[] {
  const n = diasDoPeriodo(inicio, fim)
  const t0 = Date.parse(`${inicio.slice(0, 10)}T00:00:00Z`)
  const r: string[] = []
  for (let k = 0; k < n; k++) r.push(new Date(t0 + k * 86_400_000).toISOString().slice(0, 10))
  return r
}

function compararTexto(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

const tipoDe = (p: ParticipanteComissao): TipoParticipante => p.tipo ?? 'funcionario'
const idDe = (p: ParticipanteComissao): string | null => (tipoDe(p) === 'extra' ? (p.extraId ?? null) : p.funcionarioId)

/**
 * Desempate depois do resto (E.3.2 passo 6 / §9 passo 9): pontos desc, nome `collate "C"`, tipo (funcionário antes de extra),
 * id do participante asc nulos por último, id do item.
 */
function desempate(pa: bigint, a: ParticipanteComissao, pb: bigint, b: ParticipanteComissao): number {
  if (pa !== pb) return pa > pb ? -1 : 1
  const nome = compararTexto(a.nome, b.nome)
  if (nome !== 0) return nome
  const ta = tipoDe(a) === 'funcionario' ? 0 : 1
  const tb = tipoDe(b) === 'funcionario' ? 0 : 1
  if (ta !== tb) return ta - tb
  const ia = idDe(a)
  const ib = idDe(b)
  if (ia == null || ib == null) {
    if (ia != null) return -1
    if (ib != null) return 1
  } else {
    const c = compararTexto(ia.toLowerCase(), ib.toLowerCase())
    if (c !== 0) return c
  }
  return compararTexto((a.itemId ?? '').toLowerCase(), (b.itemId ?? '').toLowerCase())
}

/** Maior resto exato: reparte `total` pelos pesos; devolve valor e se ganhou o +1. Pesos > 0. */
function maiorResto(total: bigint, pesos: bigint[], comparar: (i: number, j: number) => number) {
  const soma = pesos.reduce((s, v) => s + v, 0n)
  const pisos = pesos.map((w) => (total * w) / soma)
  const restos = pesos.map((w) => (total * w) % soma)
  let sobra = total - pisos.reduce((s, v) => s + v, 0n)
  const ordem = pesos.map((_, i) => i).sort((i, j) => (restos[i] !== restos[j] ? (restos[i]! > restos[j]! ? -1 : 1) : comparar(i, j)))
  const extra = new Set<number>()
  for (const i of ordem) {
    if (sobra <= 0n) break
    extra.add(i)
    sobra -= 1n
  }
  return pisos.map((p, i) => ({ valor: p + (extra.has(i) ? 1n : 0n), extra: extra.has(i) }))
}

export function calcularComissao(e: EntradaComissao): ResultadoComissao {
  return (e.modoRateio ?? 'periodo') === 'diario' ? calcularDiario(e) : calcularPeriodo(e)
}

/** Modo período: §9 (passos 1–9) + extras com pe = round(Σ pontos dos lançamentos / dias_periodo, 6) (adendo E.3.2). */
function calcularPeriodo(e: EntradaComissao): ResultadoComissao {
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
    if (tipoDe(p) === 'extra') {
      const soma6 = (p.entrada ?? []).reduce((s, l) => s + escalar(l.pontos, 2) * 10_000n, 0n)
      return diasPeriodo > 0 ? dividirArredondando(soma6, BigInt(diasPeriodo)) : 0n
    }
    const pontos6 = escalar(p.pontos, 2) * 10_000n
    if (!e.proporcionalDias) return pontos6
    if (diasPeriodo <= 0) return 0n
    return dividirArredondando(pontos6 * BigInt(Math.trunc(p.diasTrabalhados)), BigInt(diasPeriodo))
  })
  // 7. soma
  const soma = efetivos.reduce((s, v) => s + v, 0n)
  const comum = {
    modoRateio: 'periodo' as const,
    servicoZigCentavos: Number(zig),
    servicoAjusteCentavos: Number(ajuste),
    servicoBrutoCentavos: Number(bruto),
    percentualRetencao: e.percentualRetencao,
    retencaoCentavos: Number(retencao),
    baseCentavos: Number(base),
    diasPeriodo,
    dias: [],
    diasSemPresenca: 0,
    diasSemParticipantes: 0,
  }

  if (soma === 0n) {
    const itens = e.participantes.map<ItemCalculado>((p, i) => ({
      ...p,
      pontosEfetivos: paraNumero(efetivos[i] ?? 0n, ESCALA),
      exatoCentavos: 0,
      valorCentavos: 0,
      centavoExtra: false,
      diasNoRateio: 0,
    }))
    return { ...comum, somaPontosEfetivos: 0, valorPontoCentavos: null, itens, totalDistribuidoCentavos: 0, semParticipantes: true }
  }

  // 9. maior resto entre quem tem pe > 0
  const ativos = e.participantes.map((_, i) => i).filter((i) => (efetivos[i] ?? 0n) > 0n)
  const rateio = maiorResto(
    base,
    ativos.map((i) => efetivos[i]!),
    (x, y) => desempate(efetivos[ativos[x]!]!, e.participantes[ativos[x]!]!, efetivos[ativos[y]!]!, e.participantes[ativos[y]!]!),
  )
  const porIndice = new Map(ativos.map((i, k) => [i, rateio[k]!]))

  const itens = e.participantes.map<ItemCalculado>((p, i) => {
    const r = porIndice.get(i)
    const pe = efetivos[i] ?? 0n
    return {
      ...p,
      pontosEfetivos: paraNumero(pe, ESCALA),
      exatoCentavos: Number(base * pe) / Number(soma),
      valorCentavos: r ? Number(r.valor) : 0,
      centavoExtra: r?.extra ?? false,
      diasNoRateio: 0,
    }
  })

  return {
    ...comum,
    somaPontosEfetivos: paraNumero(soma, ESCALA),
    // 8. valor do ponto (6 casas)
    valorPontoCentavos: paraNumero(dividirArredondando(base * ESCALA * ESCALA, soma), ESCALA),
    itens,
    totalDistribuidoCentavos: itens.reduce((s, i) => s + i.valorCentavos, 0),
    semParticipantes: false,
  }
}

/** Modo diário (adendo E.3.2): o serviço de cada dia (− retenção) é rateado entre quem trabalhou no dia, pelos pontos. */
function calcularDiario(e: EntradaComissao): ResultadoComissao {
  const datas = datasDoPeriodo(e.dataInicio, e.dataFim)
  const diasPeriodo = datas.length
  const servicoPorData = new Map((e.servicoDias ?? []).map((s) => [s.data.slice(0, 10), BigInt(Math.trunc(s.servicoZigCentavos))]))
  const s = datas.map((d) => servicoPorData.get(d) ?? 0n)
  const zig = s.reduce((a, v) => a + v, 0n)
  const A = BigInt(Math.trunc(e.servicoAjusteCentavos))
  const pct100 = escalar(e.percentualRetencao, 2)

  // 2. ajuste do dia: |A| repartido pelo peso max(s_d, 0) (ou 1 para todos se a soma for 0); sobra por resto desc, data asc
  const absA = A < 0n ? -A : A
  const sinal = A < 0n ? -1n : 1n
  const positivos = s.map((v) => (v > 0n ? v : 0n))
  const pesos = positivos.some((v) => v > 0n) ? positivos : s.map(() => 1n)
  const somaPesos = pesos.reduce((a, v) => a + v, 0n)
  const partes = s.map(() => 0n)
  if (absA > 0n && somaPesos !== 0n) {
    const pisos = pesos.map((w) => (absA * w) / somaPesos)
    const restos = pesos.map((w) => (absA * w) % somaPesos)
    let sobra = absA - pisos.reduce((a, v) => a + v, 0n)
    const ordem = pesos.map((_, i) => i).sort((i, j) => (restos[i] !== restos[j] ? (restos[i]! > restos[j]! ? -1 : 1) : i - j))
    pisos.forEach((p, i) => (partes[i] = p))
    for (const i of ordem) {
      if (sobra <= 0n) break
      partes[i] = partes[i]! + 1n
      sobra -= 1n
    }
  }

  // pontos por dia de cada participante (escala 10²)
  const porData = e.participantes.map((p) => new Map((p.entrada ?? []).map((l) => [l.data.slice(0, 10), l])))
  const pontosFixos = e.participantes.map((p) => escalar(p.pontos, 2))

  const acumulado = e.participantes.map(() => ({ valor: 0n, pontos: 0n, dias: 0, extra: false, exato: 0 }))
  let somaTotal = 0n
  let diasSemPresenca = 0
  let diasSemParticipantes = 0
  let bruto = 0n
  let retencao = 0n
  let base = 0n

  const dias = datas.map<DiaCalculado>((data, k) => {
    const sd = s[k]!
    const ad = sinal * partes[k]!
    const somaDia = sd + ad
    const brutoD = somaDia > 0n ? somaDia : 0n
    const retencaoD = dividirArredondando(brutoD * pct100, 10_000n)
    const baseD = brutoD - retencaoD
    bruto += brutoD
    retencao += retencaoD
    base += baseD

    // 4. presentes do dia
    let presentes: { i: number; p: bigint; fallback: boolean }[] = []
    e.participantes.forEach((p, i) => {
      if (!p.incluido) return
      const l = porData[i]!.get(data)
      if (!l || !l.presente) return
      const pts = tipoDe(p) === 'extra' ? escalar(l.pontos, 2) : p.pontosManual || p.funcionarioId == null ? pontosFixos[i]! : escalar(l.pontos, 2)
      if (pts > 0n) presentes.push({ i, p: pts, fallback: false })
    })
    // 5. fallback: dia com base > 0 e ninguém presente → todos os funcionários incluídos
    let semPresenca = false
    let semParticipantes = false
    if (presentes.length === 0 && baseD > 0n) {
      e.participantes.forEach((p, i) => {
        if (!p.incluido || tipoDe(p) !== 'funcionario') return
        const pts = p.pontosManual || p.funcionarioId == null ? pontosFixos[i]! : escalar(porData[i]!.get(data)?.pontos ?? 0, 2)
        if (pts > 0n) presentes.push({ i, p: pts, fallback: true })
      })
      if (presentes.length > 0) {
        semPresenca = true
        diasSemPresenca += 1
      } else {
        semParticipantes = true
        diasSemParticipantes += 1
      }
    }
    // 6. rateio do dia
    const somaP = presentes.reduce((a, x) => a + x.p, 0n)
    somaTotal += somaP
    let rateio: RateioDiaParticipante[] = []
    if (presentes.length > 0) {
      const r = maiorResto(
        baseD,
        presentes.map((x) => x.p),
        (x, y) => desempate(presentes[x]!.p, e.participantes[presentes[x]!.i]!, presentes[y]!.p, e.participantes[presentes[y]!.i]!),
      )
      rateio = presentes.map((x, j) => {
        const a = acumulado[x.i]!
        a.valor += r[j]!.valor
        a.pontos += x.p
        a.dias += 1
        a.extra ||= r[j]!.extra
        a.exato += Number(baseD * x.p) / Number(somaP)
        return { indice: x.i, pontos: paraNumero(x.p, 100n), valorCentavos: Number(r[j]!.valor), fallback: x.fallback, centavoExtra: r[j]!.extra }
      })
      // ordem de exibição do banco: nome collate "C", tipo, id
      rateio.sort((a, b) => desempate(0n, e.participantes[a.indice]!, 0n, e.participantes[b.indice]!))
    }
    presentes = []
    return {
      data,
      servicoZigCentavos: Number(sd),
      ajusteCentavos: Number(ad),
      servicoBrutoCentavos: Number(brutoD),
      retencaoCentavos: Number(retencaoD),
      baseCentavos: Number(baseD),
      somaPontos: paraNumero(somaP, 100n),
      participantes: rateio.length,
      semPresenca,
      semParticipantes,
      rateio,
    }
  })

  const itens = e.participantes.map<ItemCalculado>((p, i) => {
    const a = acumulado[i]!
    return {
      ...p,
      pontosEfetivos: paraNumero(a.pontos, 100n),
      exatoCentavos: a.exato,
      valorCentavos: Number(a.valor),
      centavoExtra: a.extra,
      diasNoRateio: a.dias,
    }
  })

  return {
    modoRateio: 'diario',
    servicoZigCentavos: Number(zig),
    servicoAjusteCentavos: Number(A),
    servicoBrutoCentavos: Number(bruto),
    percentualRetencao: e.percentualRetencao,
    retencaoCentavos: Number(retencao),
    baseCentavos: Number(base),
    diasPeriodo,
    somaPontosEfetivos: paraNumero(somaTotal, 100n),
    // round(base / soma, 6) com soma em escala 10²
    valorPontoCentavos: somaTotal === 0n ? null : paraNumero(dividirArredondando(base * ESCALA * 100n, somaTotal), ESCALA),
    itens,
    totalDistribuidoCentavos: itens.reduce((t, x) => t + x.valorCentavos, 0),
    semParticipantes: somaTotal === 0n,
    dias,
    diasSemPresenca,
    diasSemParticipantes,
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

// ------------------------------------------------------------------- CSV
/** Número decimal com vírgula e sem zeros à direita (10 → "10"; 2.5 → "2,5"; 7.333333 → "7,333333"). Igual a numeroCsv do N8N. */
export function numeroCsv(v: number | string | null | undefined, casas = 6): string {
  if (v === null || v === undefined || v === '') return ''
  const n = Number(v)
  if (!Number.isFinite(n)) return ''
  return n
    .toFixed(casas)
    .replace(/\.?0+$/, '')
    .replace('.', ',')
    .replace(/^-0$/, '0')
}

export interface FechamentoCsv {
  data_inicio: string
  data_fim: string
  status: 'rascunho' | 'fechado'
  /** adendo E.3 — ausente = 'periodo' */
  modo_rateio?: ModoRateio | null
  servico_zig_centavos: number
  servico_ajuste_centavos: number
  servico_bruto_centavos: number
  percentual_retencao: number
  retencao_centavos: number
  base_distribuivel_centavos: number
  valor_ponto_centavos: number | null
  dias_sem_presenca?: number | null
}

export interface ItemCsv {
  funcionario_nome: string
  tipo?: TipoParticipante | null
  cargo: string | null
  incluido: boolean
  pontos: number
  dias_presentes: number
  valor_centavos: number
}

export const COLUNAS_CSV_COMISSAO = ['Participante', 'Tipo', 'Cargo', 'Incluído', 'Pontos', 'Dias presentes', 'Valor (R$)']

/**
 * CSV do fechamento (adendo E.4) — mesma saída, byte a byte, de `csvComissao` em n8n/comum/lib/csv.mjs.
 * Itens na ordem recebida (o banco ordena por nome, tipo, id).
 */
export function csvComissao(f: FechamentoCsv, itens: ItemCsv[], empresaNome: string): { nome: string; conteudo: string } {
  const valorPonto = f.valor_ponto_centavos == null ? null : Math.round(Number(f.valor_ponto_centavos))
  const diario = f.modo_rateio === 'diario'
  const preambulo = [
    ['Período', `${dataCsv(f.data_inicio)} a ${dataCsv(f.data_fim)}`],
    ['Modo de rateio', diario ? 'Diário' : 'Por período'],
    ['Serviço Zig (R$)', centavosCsv(f.servico_zig_centavos ?? 0)],
    ['Ajuste (R$)', centavosCsv(f.servico_ajuste_centavos ?? 0)],
    ['Serviço bruto (R$)', centavosCsv(f.servico_bruto_centavos ?? 0)],
    ['Retenção (%)', numeroCsv(f.percentual_retencao ?? 0, 2)],
    ['Retenção (R$)', centavosCsv(f.retencao_centavos ?? 0)],
    ['Base distribuível (R$)', centavosCsv(f.base_distribuivel_centavos ?? 0)],
    ['Valor do ponto (R$)', centavosCsv(valorPonto)],
    ['Status', f.status === 'fechado' ? 'Fechado' : 'Rascunho'],
  ]
  if (diario) preambulo.push(['Dias sem presença registrada', String(Math.trunc(Number(f.dias_sem_presenca) || 0))])
  let somaPontos = 0
  let somaDias = 0
  let somaValor = 0
  const linhas: unknown[][] = itens.map((i) => {
    const incluido = i.incluido !== false
    const dias = Math.trunc(Number(i.dias_presentes) || 0)
    if (incluido) somaPontos += Number(i.pontos) || 0
    if (incluido) somaDias += dias
    somaValor += Number(i.valor_centavos) || 0
    return [
      i.funcionario_nome ?? '',
      i.tipo === 'extra' ? 'Extra' : 'Funcionário',
      i.cargo ?? '',
      incluido,
      numeroCsv(i.pontos, 2),
      dias,
      centavosCsv(Number(i.valor_centavos) || 0),
    ]
  })
  linhas.push(['Total', '', '', '', numeroCsv(somaPontos, 2), somaDias, centavosCsv(somaValor)])
  return {
    nome: nomeArquivoCsv('comissao', empresaNome || 'empresa', f.data_inicio, f.data_fim),
    conteudo: gerarCsv(COLUNAS_CSV_COMISSAO, linhas, preambulo),
  }
}
