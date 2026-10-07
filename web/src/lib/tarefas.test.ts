import { describe, expect, it } from 'vitest'
import type { Prioridade, StatusTarefa } from '@/tipos/banco'
import {
  descreverRecorrencia,
  estaAtrasada,
  horaLocal,
  linhasChecklist,
  ordenarTarefas,
  progressoItens,
  proximoStatus,
  resumirTarefas,
  rotinaCaiNoDia,
  validarRotina,
} from './tarefas'

const T = (titulo: string, status: StatusTarefa = 'pendente', prioridade: Prioridade = 'normal', horario_limite: string | null = null, data = '2026-10-06') => ({
  titulo,
  status,
  prioridade,
  horario_limite,
  data,
})

describe('atrasada', () => {
  it('regras do contrato', () => {
    expect(estaAtrasada(T('a', 'pendente', 'normal', '16:30:00'), '2026-10-06', '16:31')).toBe(true)
    expect(estaAtrasada(T('a', 'pendente', 'normal', '16:30:00'), '2026-10-06', '16:30')).toBe(false)
    expect(estaAtrasada(T('a', 'em_andamento', 'normal', null, '2026-10-05'), '2026-10-06', '00:00')).toBe(true)
    expect(estaAtrasada(T('a', 'pendente', 'normal', null), '2026-10-06', '23:59')).toBe(false)
    expect(estaAtrasada(T('a', 'concluida', 'normal', '01:00'), '2026-10-06', '23:00')).toBe(false)
    expect(estaAtrasada(T('a', 'cancelada', 'normal', null, '2026-01-01'), '2026-10-06', '23:00')).toBe(false)
    expect(estaAtrasada(T('a', 'pendente', 'normal', '10:00', '2026-10-07'), '2026-10-06', '23:00')).toBe(false)
  })
})

describe('ordenação', () => {
  it('abertas atrasadas, abertas por prioridade/horário, depois fechadas', () => {
    const r = ordenarTarefas(
      [
        T('Concluída', 'concluida', 'alta'),
        T('Baixa', 'pendente', 'baixa'),
        T('Alta 18h', 'pendente', 'alta', '18:00'),
        T('Alta 17h', 'pendente', 'alta', '17:00'),
        T('Atrasada', 'pendente', 'baixa', '09:00'),
        T('Cancelada', 'cancelada', 'alta'),
        T('Andando', 'em_andamento', 'baixa'),
      ],
      '2026-10-06',
      '12:00',
    )
    expect(r.map((t) => t.titulo)).toEqual(['Atrasada', 'Andando', 'Alta 17h', 'Alta 18h', 'Baixa', 'Concluída', 'Cancelada'])
  })
})

describe('resumo e progresso', () => {
  it('resume', () => {
    expect(
      resumirTarefas([T('a', 'concluida'), T('b', 'pendente', 'normal', '09:00'), T('c', 'cancelada'), T('d', 'em_andamento')], '2026-10-06', '12:00'),
    ).toEqual({ total: 4, concluidas: 1, pendentes: 2, atrasadas: 1, canceladas: 1, percentual: 33 })
    expect(resumirTarefas([], '2026-10-06', '12:00').percentual).toBe(0)
  })
  it('progresso do checklist', () => {
    expect(progressoItens([{ feito: true }, { feito: false }, { feito: true }])).toEqual({ feitos: 2, total: 3, percentual: 67 })
    expect(progressoItens([])).toEqual({ feitos: 0, total: 0, percentual: 0 })
  })
  it('próximo status', () => {
    expect(proximoStatus('pendente')).toBe('em_andamento')
    expect(proximoStatus('em_andamento')).toBe('concluida')
    expect(proximoStatus('concluida')).toBe('pendente')
  })
})

describe('recorrência', () => {
  it('diária e semanal (ter/sex)', () => {
    expect(rotinaCaiNoDia({ recorrencia: 'diaria', dias_semana: [], dia_mes: null }, '2026-10-06')).toBe(true)
    const tersex = { recorrencia: 'semanal' as const, dias_semana: [2, 5], dia_mes: null }
    expect(rotinaCaiNoDia(tersex, '2026-10-06')).toBe(true) // terça
    expect(rotinaCaiNoDia(tersex, '2026-10-07')).toBe(false)
    expect(rotinaCaiNoDia(tersex, '2026-10-09')).toBe(true) // sexta
    expect(rotinaCaiNoDia({ ...tersex, ativa: false }, '2026-10-06')).toBe(false)
  })
  it('mensal: mês curto cai no último dia', () => {
    const d31 = { recorrencia: 'mensal' as const, dias_semana: [], dia_mes: 31 }
    expect(rotinaCaiNoDia(d31, '2026-02-28')).toBe(true)
    expect(rotinaCaiNoDia(d31, '2026-02-27')).toBe(false)
    expect(rotinaCaiNoDia(d31, '2026-04-30')).toBe(true)
    expect(rotinaCaiNoDia(d31, '2026-10-31')).toBe(true)
    expect(rotinaCaiNoDia(d31, '2026-10-30')).toBe(false)
    expect(rotinaCaiNoDia({ recorrencia: 'mensal', dias_semana: [], dia_mes: 5 }, '2026-10-05')).toBe(true)
  })
  it('descreve', () => {
    expect(descreverRecorrencia({ recorrencia: 'diaria', dias_semana: [], dia_mes: null })).toBe('Todos os dias')
    expect(descreverRecorrencia({ recorrencia: 'semanal', dias_semana: [5, 2], dia_mes: null })).toBe('Ter e Sex')
    expect(descreverRecorrencia({ recorrencia: 'semanal', dias_semana: [1, 3, 5], dia_mes: null })).toBe('Seg, Qua e Sex')
    expect(descreverRecorrencia({ recorrencia: 'semanal', dias_semana: [0], dia_mes: null })).toBe('Toda Dom')
    expect(descreverRecorrencia({ recorrencia: 'semanal', dias_semana: [0, 1, 2, 3, 4, 5, 6], dia_mes: null })).toBe('Todos os dias')
    expect(descreverRecorrencia({ recorrencia: 'mensal', dias_semana: [], dia_mes: 31 })).toBe('Todo dia 31 (ou o último do mês)')
    expect(descreverRecorrencia({ recorrencia: 'mensal', dias_semana: [], dia_mes: 10 })).toBe('Todo dia 10')
  })
  it('valida', () => {
    expect(validarRotina({ titulo: ' ', recorrencia: 'diaria', dias_semana: [], dia_mes: null })).toBe('Informe o título')
    expect(validarRotina({ titulo: 'x', recorrencia: 'semanal', dias_semana: [], dia_mes: null })).toMatch(/dia da semana/)
    expect(validarRotina({ titulo: 'x', recorrencia: 'mensal', dias_semana: [], dia_mes: null })).toMatch(/dia do mês/)
    expect(validarRotina({ titulo: 'x', recorrencia: 'mensal', dias_semana: [], dia_mes: 31 })).toBeNull()
  })
})

describe('auxiliares', () => {
  it('hora local no fuso', () => {
    expect(horaLocal('America/Sao_Paulo', new Date('2026-10-06T15:05:00Z'))).toBe('12:05')
    expect(horaLocal('America/Sao_Paulo', new Date('2026-10-06T03:00:00Z'))).toBe('00:00')
  })
  it('checklist por linhas', () => {
    expect(linhasChecklist('- Contar troco\n\n* Ligar máquinas \r\n• Conferir sangria\n   ')).toEqual(['Contar troco', 'Ligar máquinas', 'Conferir sangria'])
  })
})
