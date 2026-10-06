/**
 * Regras puras dos horários de acesso do Control iD (adendo A.2). Dono: frontend-2.
 */
const DIAS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'] as const

export interface FaixaHorario {
  dia_semana: number
  inicio: string
  fim: string
}

export const FIM_DO_DIA = '23:59:59'

function hhmm(h: string): string {
  return h.slice(0, 5)
}

function segundos(h: string): number {
  const [a = '0', b = '0', c = '0'] = h.split(':')
  return Number(a) * 3600 + Number(b) * 60 + Number(c)
}

/** Normaliza 'HH:MM' → 'HH:MM:SS'. */
export function comSegundos(h: string): string {
  return h.length === 5 ? `${h}:00` : h
}

/** Texto do fim: '23:59:59' → '24:00'. */
export function rotuloFim(fim: string): string {
  return fim.startsWith('23:59:59') ? '24:00' : hhmm(fim)
}

/** Dias → 'Ter–Dom', 'Seg, Qua', 'Todos os dias'. Considera a semana começando na segunda. */
export function descreverDias(dias: number[]): string {
  const unicos = [...new Set(dias)].filter((d) => d >= 0 && d <= 6)
  if (unicos.length === 7) return 'Todos os dias'
  if (unicos.length === 0) return '—'
  // ordem seg..dom (dom = 7)
  const ordem = unicos.map((d) => (d === 0 ? 7 : d)).sort((a, b) => a - b)
  const blocos: number[][] = []
  for (const d of ordem) {
    const ultimo = blocos[blocos.length - 1]
    if (ultimo && ultimo[ultimo.length - 1] === d - 1) ultimo.push(d)
    else blocos.push([d])
  }
  const nome = (d: number) => DIAS[d % 7] ?? '?'
  return blocos
    .map((b) => (b.length >= 3 ? `${nome(b[0] as number)}–${nome(b[b.length - 1] as number)}` : b.map(nome).join(', ')))
    .join(', ')
}

/** Resumo das faixas: 'Ter–Dom 16:30–24:00 · Seg 10:00–12:00'. */
export function descreverFaixasHorario(faixas: FaixaHorario[]): string {
  if (faixas.length === 0) return 'Sem faixas (não libera nenhum horário)'
  const grupos = new Map<string, number[]>()
  for (const f of faixas) {
    const chave = `${hhmm(f.inicio)}–${rotuloFim(f.fim)}`
    grupos.set(chave, [...(grupos.get(chave) ?? []), f.dia_semana])
  }
  return [...grupos.entries()]
    .sort((a, b) => Math.min(...a[1].map((d) => (d === 0 ? 7 : d))) - Math.min(...b[1].map((d) => (d === 0 ? 7 : d))))
    .map(([faixa, dias]) => `${descreverDias(dias)} ${faixa}`)
    .join(' · ')
}

/**
 * Uma faixa digitada que cruza a meia-noite (fim ≤ início) vira duas: até o fim do dia e, no dia seguinte, desde 00:00.
 * Ex.: sáb 18:00 → 02:00 = sáb 18:00–23:59:59 + dom 00:00–02:00.
 */
export function expandirFaixa(dia: number, inicio: string, fim: string): FaixaHorario[] {
  const i = comSegundos(inicio)
  const f = comSegundos(fim)
  if (segundos(f) > segundos(i)) return [{ dia_semana: dia, inicio: i, fim: f }]
  const partes: FaixaHorario[] = [{ dia_semana: dia, inicio: i, fim: FIM_DO_DIA }]
  if (segundos(f) > 0) partes.push({ dia_semana: (dia + 1) % 7, inicio: '00:00:00', fim: f })
  return partes
}

/** Erros: faixa vazia/invertida ou sobreposição no mesmo dia. Retorna mensagem ou null. */
export function validarFaixas(faixas: FaixaHorario[]): string | null {
  for (const f of faixas) {
    if (!/^\d{2}:\d{2}(:\d{2})?$/.test(f.inicio) || !/^\d{2}:\d{2}(:\d{2})?$/.test(f.fim)) return 'Horário inválido'
    if (segundos(f.fim) <= segundos(f.inicio)) return `Faixa de ${DIAS[f.dia_semana]} termina antes de começar`
  }
  for (let d = 0; d < 7; d++) {
    const doDia = faixas.filter((f) => f.dia_semana === d).sort((a, b) => segundos(a.inicio) - segundos(b.inicio))
    for (let k = 1; k < doDia.length; k++) {
      if (segundos((doDia[k] as FaixaHorario).inicio) < segundos((doDia[k - 1] as FaixaHorario).fim))
        return `Faixas sobrepostas em ${DIAS[d]}`
    }
  }
  return null
}

/** O instante (dia da semana + 'HH:MM') está liberado por alguma faixa? */
export function liberado(faixas: FaixaHorario[], dia: number, hora: string): boolean {
  const s = segundos(comSegundos(hora))
  return faixas.some((f) => f.dia_semana === dia && s >= segundos(f.inicio) && s <= segundos(f.fim))
}
