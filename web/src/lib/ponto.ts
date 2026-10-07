/**
 * Lógica pura de ponto (contrato §5 jornada_dias, §2.4, §7). Dono: frontend-2.
 * Sem React e sem rede: tudo aqui é testado em `ponto.test.ts`.
 */
import type { BatidaEsperada, BatidaEspelho, EsperadaEspelho, LinhaEspelho, SituacaoDia, TipoAlarme } from '@/tipos/banco'

const FUSO_PADRAO = 'America/Sao_Paulo'
const MIN_DIA = 1440

/** Horários de um dia de jornada (as colunas editáveis de `jornada_dias`). */
export interface HorariosDia {
  entrada: string
  saida_intervalo: string | null
  volta_intervalo: string | null
  saida: string
}

export const ROTULO_BATIDA_ESPERADA: Record<BatidaEsperada, string> = {
  entrada: 'Entrada',
  saida_intervalo: 'Saída p/ intervalo',
  volta_intervalo: 'Volta do intervalo',
  saida: 'Saída',
}

/** Rótulo de uma batida esperada; '' (alarme sem slot) → ''. */
export function rotuloBatidaEsperada(b: BatidaEsperada | '' | null | undefined): string {
  return b ? ROTULO_BATIDA_ESPERADA[b] : ''
}

export const DIAS_SEMANA = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'] as const
export const DIAS_SEMANA_CURTOS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'] as const

// ------------------------------------------------------------------ horas
/** 'HH:MM' ou 'HH:MM:SS' → segundos desde 00:00. Inválido → NaN. */
export function horaParaSegundos(h: string): number {
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(h.trim())
  if (!m) return Number.NaN
  const hh = Number(m[1])
  const mm = Number(m[2])
  const ss = Number(m[3] ?? 0)
  if (hh > 23 || mm > 59 || ss > 59) return Number.NaN
  return hh * 3600 + mm * 60 + ss
}

/** 'HH:MM[:SS]' → minutos desde 00:00 (segundos descartados). */
export function horaParaMinutos(h: string): number {
  return Math.floor(horaParaSegundos(h) / 60)
}

/** 1050 → '17:30' (módulo 24 h). */
export function minutosParaHora(m: number): string {
  const v = ((Math.trunc(m) % MIN_DIA) + MIN_DIA) % MIN_DIA
  return `${String(Math.floor(v / 60)).padStart(2, '0')}:${String(v % 60).padStart(2, '0')}`
}

/** Diferença circular b − a em minutos, como o banco: ((epoch(b − a)/60)::int + 1440) % 1440. */
function diferencaCircular(a: string, b: string): number {
  const seg = horaParaSegundos(b) - horaParaSegundos(a)
  const min = arredondarMeioLonge(seg / 60)
  return ((min % MIN_DIA) + MIN_DIA) % MIN_DIA
}

function arredondarMeioLonge(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x)
}

/** Réplica da coluna gerada `jornada_dias.minutos_previstos`. Ex.: 17:00/21:00/21:30/01:00 → 450. */
export function minutosPrevistos(jd: HorariosDia): number {
  const total = diferencaCircular(jd.entrada, jd.saida)
  const intervalo = jd.saida_intervalo && jd.volta_intervalo ? diferencaCircular(jd.saida_intervalo, jd.volta_intervalo) : 0
  return total - intervalo
}

/** Réplica de `jornada_dias.batidas_esperadas`: 2 sem intervalo, 4 com. */
export function batidasEsperadas(jd: Pick<HorariosDia, 'saida_intervalo'>): 2 | 4 {
  return jd.saida_intervalo ? 4 : 2
}

/**
 * Validação igual à do gatilho do banco: intervalo com as duas pontas ou nenhuma; ordem circular a partir da entrada
 * (entrada < saída p/ intervalo < volta < saída, total < 24 h). Retorna a mensagem de erro ou null.
 */
export function validarHorariosDia(jd: HorariosDia): string | null {
  const campos = [jd.entrada, jd.saida, jd.saida_intervalo, jd.volta_intervalo].filter((h): h is string => !!h)
  if (!jd.entrada || !jd.saida) return 'Informe entrada e saída'
  if (campos.some((h) => Number.isNaN(horaParaSegundos(h)))) return 'Horário inválido'
  if (!!jd.saida_intervalo !== !!jd.volta_intervalo) return 'Informe a saída e a volta do intervalo (ou nenhuma das duas)'
  const sequencia = [jd.entrada, jd.saida_intervalo, jd.volta_intervalo, jd.saida].filter((h): h is string => !!h)
  const deslocamentos = sequencia.map((h) => diferencaCircular(jd.entrada, h))
  for (let i = 1; i < deslocamentos.length; i++) {
    if ((deslocamentos[i] ?? 0) <= (deslocamentos[i - 1] ?? 0)) return 'Horários da jornada fora de ordem'
  }
  return null
}

/** Os slots de batida do dia, na ordem. */
export function slotsDoDia(jd: HorariosDia): { batida: BatidaEsperada; hora: string }[] {
  const slots: { batida: BatidaEsperada; hora: string }[] = [{ batida: 'entrada', hora: jd.entrada }]
  if (jd.saida_intervalo && jd.volta_intervalo) {
    slots.push({ batida: 'saida_intervalo', hora: jd.saida_intervalo }, { batida: 'volta_intervalo', hora: jd.volta_intervalo })
  }
  slots.push({ batida: 'saida', hora: jd.saida })
  return slots
}

// --------------------------------------------------------- fuso e instantes
/** Deslocamento (ms) do fuso no instante: hora de parede − UTC. */
export function deslocamentoFuso(instante: Date, fuso: string = FUSO_PADRAO): number {
  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: fuso,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(instante)
  const v = (t: string) => Number(partes.find((p) => p.type === t)?.value ?? 0)
  const parede = Date.UTC(v('year'), v('month') - 1, v('day'), v('hour') % 24, v('minute'), v('second'))
  return parede - Math.floor(instante.getTime() / 1000) * 1000
}

/** Data civil 'AAAA-MM-DD' + hora 'HH:MM[:SS]' na hora de parede do fuso → Date (instante). */
export function instanteLocal(data: string, hora: string, fuso: string = FUSO_PADRAO): Date {
  const [a, m, d] = data.slice(0, 10).split('-').map(Number)
  const seg = horaParaSegundos(hora)
  const parede = Date.UTC(a ?? 1970, (m ?? 1) - 1, d ?? 1) + seg * 1000
  let palpite = parede - deslocamentoFuso(new Date(parede), fuso)
  // segunda passada cobre a troca de horário de verão
  palpite = parede - deslocamentoFuso(new Date(palpite), fuso)
  return new Date(palpite)
}

function somarDiasCivil(iso: string, n: number): string {
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1, (d ?? 1) + n)).toISOString().slice(0, 10)
}

/**
 * Horário de escala `hora` no dia de trabalho `data` → instante (contrato §2.4): se hora < virada, cai no dia civil seguinte.
 * Ex.: D = sáb 2026-10-03, 01:00, virada 05:00 → dom 2026-10-04 01:00 (-03) = 2026-10-04T04:00:00Z.
 */
export function instanteDoHorario(data: string, hora: string, fuso: string = FUSO_PADRAO, virada = '05:00'): Date {
  const diaSeguinte = horaParaSegundos(hora) < horaParaSegundos(virada)
  return instanteLocal(diaSeguinte ? somarDiasCivil(data, 1) : data, hora, fuso)
}

/** Instantes previstos E1..Ek do dia (mesmo formato de `ponto_espelho.esperadas`). */
export function instantesEsperados(data: string, jd: HorariosDia, fuso: string = FUSO_PADRAO, virada = '05:00'): EsperadaEspelho[] {
  return slotsDoDia(jd).map((s) => ({ batida: s.batida, instante: instanteDoHorario(data, s.hora, fuso, virada).toISOString() }))
}

/** Dia de trabalho de um instante (§2.4): ((i no fuso) − virada)::date. */
export function diaDeTrabalho(instante: Date | string, fuso: string = FUSO_PADRAO, virada = '05:00'): string {
  const t = typeof instante === 'string' ? new Date(instante) : instante
  const deslocado = new Date(t.getTime() + deslocamentoFuso(t, fuso) - horaParaSegundos(virada) * 1000)
  return deslocado.toISOString().slice(0, 10)
}

// ----------------------------------------------------------------- batidas
/** Batidas que contam: não desconsideradas e não duplicadas. */
export function batidasValidas<T extends Pick<BatidaEspelho, 'desconsiderada' | 'duplicada' | 'instante'>>(batidas: T[]): T[] {
  return batidas
    .filter((b) => !b.desconsiderada && !b.duplicada)
    .sort((x, y) => new Date(x.instante).getTime() - new Date(y.instante).getTime())
}

export interface Par {
  inicio: string
  fim: string
  minutos: number
}

/**
 * Pares (1ª,2ª), (3ª,4ª)… e total trabalhado = Σ floor((b2 − b1)/60 s) (§7.2 passo 4).
 * Com número ímpar, a última fica em `sobra` e não conta.
 */
export function paresTrabalhados(instantes: (string | Date)[]): { pares: Par[]; sobra: string | null; total: number } {
  const ordenados = instantes
    .map((i) => (typeof i === 'string' ? new Date(i) : i))
    .sort((a, b) => a.getTime() - b.getTime())
  const pares: Par[] = []
  let total = 0
  for (let i = 0; i + 1 < ordenados.length; i += 2) {
    const a = ordenados[i] as Date
    const b = ordenados[i + 1] as Date
    const minutos = Math.floor((b.getTime() - a.getTime()) / 60000)
    total += minutos
    pares.push({ inicio: a.toISOString(), fim: b.toISOString(), minutos })
  }
  const sobra = ordenados.length % 2 === 1 ? (ordenados[ordenados.length - 1] as Date).toISOString() : null
  return { pares, sobra, total }
}

/** Combinações de `n` índices de 0..k−1 em ordem lexicográfica. */
function combinacoes(k: number, n: number): number[][] {
  const saida: number[][] = []
  const atual: number[] = []
  const passo = (inicio: number) => {
    if (atual.length === n) {
      saida.push([...atual])
      return
    }
    for (let i = inicio; i < k; i++) {
      atual.push(i)
      passo(i + 1)
      atual.pop()
    }
  }
  passo(0)
  return saida
}

/**
 * Qual batida faltou (§7.3): com 0 < n < k, escolhe os n slots (ordem preservada) que minimizam Σ |batida_i − slot_i|;
 * empate → a combinação lexicograficamente menor. Retorna os slots NÃO escolhidos (os faltantes), na ordem.
 * Ex.: escala 17:00/21:00/21:30/01:00, batidas 16:58, 21:02, 01:05 → ['volta_intervalo'].
 */
export function identificarFaltantes(batidas: (string | Date)[], esperadas: EsperadaEspelho[]): BatidaEsperada[] {
  const n = batidas.length
  const k = esperadas.length
  if (n === 0) return esperadas.map((e) => e.batida)
  if (n >= k) return []
  const tb = batidas.map((b) => (typeof b === 'string' ? new Date(b) : b).getTime()).sort((a, b) => a - b)
  const ts = esperadas.map((e) => new Date(e.instante).getTime())
  let melhor: number[] | null = null
  let melhorCusto = Number.POSITIVE_INFINITY
  for (const comb of combinacoes(k, n)) {
    let custo = 0
    comb.forEach((slot, i) => {
      custo += Math.abs((tb[i] ?? 0) - (ts[slot] ?? 0))
    })
    if (custo < melhorCusto) {
      melhorCusto = custo
      melhor = comb
    }
  }
  const escolhidos = new Set(melhor ?? [])
  return esperadas.filter((_, i) => !escolhidos.has(i)).map((e) => e.batida)
}

/** Resumo de batidas de um dia para exibir "3 de 4". */
export interface ResumoBatidas {
  validas: number
  esperadas: number
  faltam: number
  impar: boolean
  /** slots que faltam (só quando 0 < validas < esperadas, ou todos quando validas = 0) */
  faltantes: BatidaEsperada[]
}

export function resumirBatidas(linha: Pick<LinhaEspelho, 'batidas' | 'esperadas'>): ResumoBatidas {
  const validas = batidasValidas(linha.batidas)
  const esperadas = linha.esperadas.length
  return {
    validas: validas.length,
    esperadas,
    faltam: Math.max(0, esperadas - validas.length),
    impar: validas.length % 2 === 1,
    faltantes: esperadas > 0 ? identificarFaltantes(validas.map((b) => b.instante), linha.esperadas) : [],
  }
}

// ----------------------------------------------------------- situação/alarme
/** Situações que pedem atenção do gerente. */
export function situacaoProblematica(s: SituacaoDia): boolean {
  return s === 'incompleto' || s === 'ausente'
}

/** Gravidade para ordenar alarmes (maior = mais grave). */
export const GRAVIDADE_ALARME: Record<TipoAlarme, number> = {
  sem_batida_dia_escalado: 4,
  batida_faltando: 3,
  batidas_impares: 2,
  atraso: 1,
}

// ----------------------------------------------------------------- períodos
/** '2026-10' → { inicio: '2026-10-01', fim: '2026-10-31' }. */
export function periodoDoMes(mes: string): { inicio: string; fim: string } {
  const [a, m] = mes.split('-').map(Number)
  const ano = a ?? 1970
  const mm = m ?? 1
  const ultimo = new Date(Date.UTC(ano, mm, 0)).getUTCDate()
  const p = `${ano}-${String(mm).padStart(2, '0')}`
  return { inicio: `${p}-01`, fim: `${p}-${String(ultimo).padStart(2, '0')}` }
}

/** '2026-10' + (−1) → '2026-09'. */
export function somarMeses(mes: string, n: number): string {
  const [a, m] = mes.split('-').map(Number)
  const d = new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1 + n, 1))
  return d.toISOString().slice(0, 7)
}

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']

/** '2026-10' → 'outubro de 2026'. */
export function nomeDoMes(mes: string): string {
  const [a, m] = mes.split('-').map(Number)
  return `${MESES[(m ?? 1) - 1] ?? ''} de ${a ?? ''}`
}

/** Valida 'AAAA-MM'. */
export function mesValido(mes: string | null | undefined): mes is string {
  return !!mes && /^\d{4}-(0[1-9]|1[0-2])$/.test(mes)
}

/** Valida 'AAAA-MM-DD' (data real). */
export function dataValida(iso: string | null | undefined): iso is string {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false
  const d = new Date(`${iso}T00:00:00Z`)
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso
}

// ------------------------------------------------------------- resumo mês
export interface TotaisEspelho {
  previsto: number
  trabalhado: number
  /** só dias encerrados (os que entram no banco de horas) */
  saldo: number
  atraso: number
  diasTrabalhados: number
  faltas: number
  incompletos: number
  alarmesAbertos: number
}

export function totaisDoEspelho(linhas: LinhaEspelho[]): TotaisEspelho {
  const t: TotaisEspelho = { previsto: 0, trabalhado: 0, saldo: 0, atraso: 0, diasTrabalhados: 0, faltas: 0, incompletos: 0, alarmesAbertos: 0 }
  for (const l of linhas) {
    t.previsto += l.previsto_minutos
    t.trabalhado += l.trabalhado_minutos
    if (l.encerrado) t.saldo += l.saldo_minutos
    t.atraso += l.atraso_minutos
    if (batidasValidas(l.batidas).length > 0) t.diasTrabalhados += 1
    if (l.situacao === 'ausente') t.faltas += 1
    if (l.situacao === 'incompleto') t.incompletos += 1
    t.alarmesAbertos += l.alarmes.filter((a) => a.status === 'aberto').length
  }
  return t
}

// ------------------------------------------------------------- durações
/**
 * Lê uma duração digitada pelo gerente → minutos com sinal.
 * Aceita '2h30', '-1h', '+0h45', '02:30', '-03:26', '90' (minutos), '1,5h' (decimal de horas). Inválido → null.
 */
export function lerDuracao(texto: string): number | null {
  const t = texto.trim().toLowerCase().replace(/\s+/g, '')
  if (t === '') return null
  const sinal = t.startsWith('-') ? -1 : 1
  const corpo = t.replace(/^[+-]/, '')
  let m: RegExpExecArray | null
  if ((m = /^(\d+)h(\d{1,2})?(?:m(?:in)?)?$/.exec(corpo))) {
    const min = Number(m[2] ?? 0)
    if (min > 59) return null
    return sinal * (Number(m[1]) * 60 + min)
  }
  if ((m = /^(\d+)[,.](\d+)h$/.exec(corpo))) return sinal * Math.round(Number(`${m[1]}.${m[2]}`) * 60)
  if ((m = /^(\d+):(\d{2})$/.exec(corpo))) {
    const min = Number(m[2])
    if (min > 59) return null
    return sinal * (Number(m[1]) * 60 + min)
  }
  if ((m = /^(\d+)(?:m|min)?$/.exec(corpo))) return sinal * Number(m[1])
  return null
}
