/**
 * Regras puras de tarefas e rotinas (contrato §5 tarefas, §10.3). Dono: frontend-2.
 */
import type { Prioridade, Recorrencia, StatusTarefa } from '@/tipos/banco'

export interface TarefaBasica {
  data: string
  status: StatusTarefa
  prioridade: Prioridade
  horario_limite: string | null
  titulo: string
}

export interface RotinaBasica {
  recorrencia: Recorrencia
  dias_semana: number[]
  dia_mes: number | null
  ativa?: boolean
}

const DIAS_CURTOS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'] as const

function hhmm(h: string | null | undefined): string | null {
  return h ? h.slice(0, 5) : null
}

/**
 * "Atrasada" (§5, calculado): status pendente/em andamento e (data < hoje ou (data = hoje e horário limite < hora atual)).
 * `horaAtual` = 'HH:MM' local da empresa.
 */
export function estaAtrasada(t: Pick<TarefaBasica, 'data' | 'status' | 'horario_limite'>, hoje: string, horaAtual: string): boolean {
  if (t.status !== 'pendente' && t.status !== 'em_andamento') return false
  if (t.data < hoje) return true
  const limite = hhmm(t.horario_limite)
  return t.data === hoje && limite != null && limite < horaAtual.slice(0, 5)
}

const ORDEM_STATUS: Record<StatusTarefa, number> = { em_andamento: 0, pendente: 1, concluida: 2, cancelada: 3 }
const ORDEM_PRIORIDADE: Record<Prioridade, number> = { alta: 0, normal: 1, baixa: 2 }

/** Abertas primeiro (atrasadas antes), depois prioridade, horário limite (sem horário por último) e título. */
export function ordenarTarefas<T extends TarefaBasica>(tarefas: T[], hoje: string, horaAtual: string): T[] {
  return [...tarefas].sort((a, b) => {
    const abertaA = ORDEM_STATUS[a.status] <= 1 ? 0 : 1
    const abertaB = ORDEM_STATUS[b.status] <= 1 ? 0 : 1
    if (abertaA !== abertaB) return abertaA - abertaB
    const atrA = estaAtrasada(a, hoje, horaAtual) ? 0 : 1
    const atrB = estaAtrasada(b, hoje, horaAtual) ? 0 : 1
    if (atrA !== atrB) return atrA - atrB
    if (ORDEM_STATUS[a.status] !== ORDEM_STATUS[b.status]) return ORDEM_STATUS[a.status] - ORDEM_STATUS[b.status]
    if (ORDEM_PRIORIDADE[a.prioridade] !== ORDEM_PRIORIDADE[b.prioridade]) return ORDEM_PRIORIDADE[a.prioridade] - ORDEM_PRIORIDADE[b.prioridade]
    const ha = hhmm(a.horario_limite) ?? '99:99'
    const hb = hhmm(b.horario_limite) ?? '99:99'
    if (ha !== hb) return ha < hb ? -1 : 1
    return a.titulo.localeCompare(b.titulo, 'pt-BR')
  })
}

export interface ResumoTarefas {
  total: number
  concluidas: number
  pendentes: number
  atrasadas: number
  canceladas: number
  /** concluídas / (total − canceladas), 0..100 inteiro */
  percentual: number
}

export function resumirTarefas(tarefas: TarefaBasica[], hoje: string, horaAtual: string): ResumoTarefas {
  const r: ResumoTarefas = { total: tarefas.length, concluidas: 0, pendentes: 0, atrasadas: 0, canceladas: 0, percentual: 0 }
  for (const t of tarefas) {
    if (t.status === 'concluida') r.concluidas += 1
    else if (t.status === 'cancelada') r.canceladas += 1
    else r.pendentes += 1
    if (estaAtrasada(t, hoje, horaAtual)) r.atrasadas += 1
  }
  const validas = r.total - r.canceladas
  r.percentual = validas > 0 ? Math.round((r.concluidas / validas) * 100) : 0
  return r
}

/** Progresso do checklist. */
export function progressoItens(itens: { feito: boolean }[]): { feitos: number; total: number; percentual: number } {
  const feitos = itens.filter((i) => i.feito).length
  return { feitos, total: itens.length, percentual: itens.length ? Math.round((feitos / itens.length) * 100) : 0 }
}

/** Próximo status ao tocar no botão principal: pendente → em andamento → concluída; concluída → pendente (reabrir). */
export function proximoStatus(s: StatusTarefa): StatusTarefa {
  if (s === 'pendente') return 'em_andamento'
  if (s === 'em_andamento') return 'concluida'
  return 'pendente'
}

function ultimoDiaDoMes(data: string): number {
  const [a, m] = data.split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, m ?? 1, 0)).getUTCDate()
}

function diaSemana(data: string): number {
  const [a, m, d] = data.split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1, d ?? 1)).getUTCDay()
}

/** A rotina gera tarefa na data? (mensal com dia > último dia do mês → último dia). */
export function rotinaCaiNoDia(r: RotinaBasica, data: string): boolean {
  if (r.ativa === false) return false
  if (r.recorrencia === 'diaria') return true
  if (r.recorrencia === 'semanal') return r.dias_semana.includes(diaSemana(data))
  if (r.dia_mes == null) return false
  const dia = Number(data.slice(8, 10))
  return dia === Math.min(r.dia_mes, ultimoDiaDoMes(data))
}

/** Texto curto: 'Todos os dias', 'Ter e Sex', 'Seg, Qua e Sex', 'Todo dia 31 (ou o último do mês)'. */
export function descreverRecorrencia(r: RotinaBasica): string {
  if (r.recorrencia === 'diaria') return 'Todos os dias'
  if (r.recorrencia === 'semanal') {
    const dias = [...new Set(r.dias_semana)].sort((a, b) => a - b)
    if (dias.length === 7) return 'Todos os dias'
    if (dias.length === 0) return 'Semanal (sem dias)'
    const nomes = dias.map((d) => DIAS_CURTOS[d] ?? '?')
    return nomes.length === 1 ? `Toda ${nomes[0]}` : `${nomes.slice(0, -1).join(', ')} e ${nomes[nomes.length - 1]}`
  }
  if (r.dia_mes == null) return 'Mensal'
  return r.dia_mes > 28 ? `Todo dia ${r.dia_mes} (ou o último do mês)` : `Todo dia ${r.dia_mes}`
}

/** Mesmas regras dos checks do banco. Retorna mensagem ou null. */
export function validarRotina(r: RotinaBasica & { titulo: string }): string | null {
  if (!r.titulo.trim()) return 'Informe o título'
  if (r.recorrencia === 'semanal' && r.dias_semana.length === 0) return 'Escolha ao menos um dia da semana'
  if (r.recorrencia === 'semanal' && r.dias_semana.some((d) => d < 0 || d > 6)) return 'Dia da semana inválido'
  if (r.recorrencia === 'mensal' && (r.dia_mes == null || r.dia_mes < 1 || r.dia_mes > 31)) return 'Informe o dia do mês (1 a 31)'
  return null
}

/** 'HH:MM' atual no fuso. */
export function horaLocal(fuso = 'America/Sao_Paulo', agora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone: fuso, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(agora)
}

/** Itens de checklist digitados um por linha → lista limpa (sem vazios). */
export function linhasChecklist(texto: string): string[] {
  return texto
    .split(/\r?\n/)
    .map((l) => l.replace(/^\s*[-*•]\s*/, '').trim())
    .filter(Boolean)
}
