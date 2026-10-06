/**
 * Formatação (contrato §14.6). Dono: frontend-1. Funções puras — nomes e assinaturas são contrato.
 * Dinheiro sempre em CENTAVOS; minutos sempre inteiros.
 */

const FUSO_PADRAO = 'America/Sao_Paulo'

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })

/** 123456 → "R$ 1.234,56"; com `sinal`, positivos ganham "+". */
export function formatarCentavos(c: number | null | undefined, opcoes: { sinal?: boolean } = {}): string {
  if (c == null) return '—'
  const texto = moeda.format(c / 100).replace(/ /g, ' ')
  return opcoes.sinal && c > 0 ? `+${texto}` : texto
}

/** 123456 → "1234,56" (sem milhar; usado em CSV e inputs). */
export function centavosParaTexto(c: number): string {
  const negativo = c < 0
  const abs = Math.abs(Math.trunc(c))
  return `${negativo ? '-' : ''}${Math.floor(abs / 100)},${String(abs % 100).padStart(2, '0')}`
}

/** "1.234,56" | "1234.56" | "-50" → centavos; inválido → null. */
export function textoParaCentavos(s: string): number | null {
  const t = s.trim().replace(/^R\$\s*/, '')
  if (t === '') return null
  const normalizado = t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : t
  const n = Number(normalizado)
  return Number.isFinite(n) ? Math.round(n * 100) : null
}

/** 450 → "7h30"; -206 → "-3h26"; com `sinal`, positivos ganham "+". 0 → "0h00". */
export function formatarMinutos(m: number | null | undefined, opcoes: { sinal?: boolean } = {}): string {
  if (m == null) return '—'
  const abs = Math.abs(Math.trunc(m))
  const texto = `${Math.floor(abs / 60)}h${String(abs % 60).padStart(2, '0')}`
  if (m < 0) return `-${texto}`
  return opcoes.sinal && m > 0 ? `+${texto}` : texto
}

/** -206 → "-03:26"; 450 → "07:30" (CSV). */
export function minutosHHMM(m: number): string {
  const abs = Math.abs(Math.trunc(m))
  return `${m < 0 ? '-' : ''}${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`
}

function partesData(iso: string): [string, string, string] {
  const [a = '', m = '', d = ''] = iso.slice(0, 10).split('-')
  return [a, m, d]
}

/** "2026-10-06" → "06/10/2026". */
export function formatarData(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [a, m, d] = partesData(iso)
  return `${d}/${m}/${a}`
}

/** "2026-10-06" → "06/10". */
export function formatarDataCurta(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [, m, d] = partesData(iso)
  return `${d}/${m}`
}

const DIAS_CURTOS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'] as const

/** "2026-10-03" → "sáb" (data civil, sem fuso). */
export function diaSemanaCurto(iso: string): string {
  const [a, m, d] = partesData(iso)
  return DIAS_CURTOS[new Date(Date.UTC(Number(a), Number(m) - 1, Number(d))).getUTCDay()] ?? ''
}

/** Instante ISO → "HH:MM" no fuso. */
export function formatarHora(instante: string | null | undefined, fuso = FUSO_PADRAO): string {
  if (!instante) return '—'
  return new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: fuso }).format(new Date(instante))
}

/** Instante ISO → "dd/mm/aaaa HH:MM" no fuso. */
export function formatarDataHora(instante: string | null | undefined, fuso = FUSO_PADRAO): string {
  if (!instante) return '—'
  const f = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: fuso,
  })
  return f.format(new Date(instante)).replace(',', '')
}

/** Instante ISO → "agora", "há 5 min", "há 3 h", "há 2 dias". */
export function formatarRelativo(instante: string | null | undefined, agora: Date = new Date()): string {
  if (!instante) return 'nunca'
  const seg = Math.round((agora.getTime() - new Date(instante).getTime()) / 1000)
  if (seg < 60) return 'agora'
  if (seg < 3600) return `há ${Math.floor(seg / 60)} min`
  if (seg < 86400) return `há ${Math.floor(seg / 3600)} h`
  const dias = Math.floor(seg / 86400)
  return `há ${dias} ${dias === 1 ? 'dia' : 'dias'}`
}

/** Dia de trabalho atual (contrato §2.4): data local no fuso, menos a virada. */
export function hojeISO(fuso = FUSO_PADRAO, virada = '05:00', agora: Date = new Date()): string {
  const [h = '0', min = '0'] = virada.split(':')
  const deslocado = new Date(agora.getTime() - (Number(h) * 60 + Number(min)) * 60_000)
  return new Intl.DateTimeFormat('en-CA', { timeZone: fuso, year: 'numeric', month: '2-digit', day: '2-digit' }).format(deslocado)
}

/** "2026-10-06" + 1 → "2026-10-07". */
export function somarDias(iso: string, n: number): string {
  const [a, m, d] = partesData(iso)
  const dt = new Date(Date.UTC(Number(a), Number(m) - 1, Number(d) + n))
  return dt.toISOString().slice(0, 10)
}

/** Minúsculas, sem acento e sem espaços nas pontas (busca). */
export function normalizar(s: string): string {
  return s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
}
