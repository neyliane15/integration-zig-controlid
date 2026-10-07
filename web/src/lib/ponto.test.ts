import { describe, expect, it } from 'vitest'
import type { BatidaEspelho, LinhaEspelho } from '@/tipos/banco'
import {
  batidasEsperadas,
  batidasValidas,
  dataValida,
  diaDeTrabalho,
  horaParaMinutos,
  identificarFaltantes,
  instanteDoHorario,
  instantesEsperados,
  lerDuracao,
  mesValido,
  minutosParaHora,
  minutosPrevistos,
  nomeDoMes,
  paresTrabalhados,
  periodoDoMes,
  resumirBatidas,
  rotuloBatidaEsperada,
  slotsDoDia,
  somarMeses,
  totaisDoEspelho,
  validarHorariosDia,
} from './ponto'

const SALAO = { entrada: '17:00:00', saida_intervalo: '21:00:00', volta_intervalo: '21:30:00', saida: '01:00:00' }
const COZINHA = { entrada: '10:00', saida_intervalo: '14:00', volta_intervalo: '15:00', saida: '18:00' }
const SEM_INTERVALO = { entrada: '08:00', saida_intervalo: null, volta_intervalo: null, saida: '12:00' }

/** Instante local de São Paulo (-03:00) em ISO UTC. */
const sp = (dataHora: string) => new Date(`${dataHora}:00-03:00`).toISOString()

describe('jornada: minutos previstos e batidas esperadas', () => {
  it('replica a coluna gerada do banco (exemplo do contrato: 450)', () => {
    expect(minutosPrevistos(SALAO)).toBe(450)
    expect(minutosPrevistos(COZINHA)).toBe(420)
    expect(minutosPrevistos(SEM_INTERVALO)).toBe(240)
  })
  it('atravessa a meia-noite sem intervalo', () => {
    expect(minutosPrevistos({ entrada: '22:00', saida_intervalo: null, volta_intervalo: null, saida: '06:00' })).toBe(480)
  })
  it('intervalo que atravessa a meia-noite', () => {
    expect(minutosPrevistos({ entrada: '20:00', saida_intervalo: '23:45', volta_intervalo: '00:15', saida: '04:00' })).toBe(480 - 30)
  })
  it('2 ou 4 batidas', () => {
    expect(batidasEsperadas(SALAO)).toBe(4)
    expect(batidasEsperadas(SEM_INTERVALO)).toBe(2)
  })
  it('slots na ordem', () => {
    expect(slotsDoDia(SALAO).map((s) => s.batida)).toEqual(['entrada', 'saida_intervalo', 'volta_intervalo', 'saida'])
    expect(slotsDoDia(SEM_INTERVALO).map((s) => s.batida)).toEqual(['entrada', 'saida'])
  })
})

describe('validarHorariosDia', () => {
  it('aceita ordens válidas (inclusive circulares)', () => {
    expect(validarHorariosDia(SALAO)).toBeNull()
    expect(validarHorariosDia(COZINHA)).toBeNull()
    expect(validarHorariosDia(SEM_INTERVALO)).toBeNull()
  })
  it('recusa fora de ordem', () => {
    expect(validarHorariosDia({ entrada: '17:00', saida_intervalo: '21:30', volta_intervalo: '21:00', saida: '01:00' })).toBe(
      'Horários da jornada fora de ordem',
    )
    expect(validarHorariosDia({ entrada: '17:00', saida_intervalo: '02:00', volta_intervalo: '03:00', saida: '01:00' })).toBe(
      'Horários da jornada fora de ordem',
    )
    expect(validarHorariosDia({ entrada: '17:00', saida_intervalo: null, volta_intervalo: null, saida: '17:00' })).toBe(
      'Horários da jornada fora de ordem',
    )
  })
  it('exige as duas pontas do intervalo', () => {
    expect(validarHorariosDia({ entrada: '10:00', saida_intervalo: '12:00', volta_intervalo: null, saida: '18:00' })).toMatch(/intervalo/)
  })
  it('horário inválido', () => {
    expect(validarHorariosDia({ entrada: '25:00', saida_intervalo: null, volta_intervalo: null, saida: '18:00' })).toBe('Horário inválido')
  })
})

describe('horas', () => {
  it('converte', () => {
    expect(horaParaMinutos('17:30:00')).toBe(1050)
    expect(horaParaMinutos('01:05')).toBe(65)
    expect(minutosParaHora(1050)).toBe('17:30')
    expect(minutosParaHora(-60)).toBe('23:00')
    expect(minutosParaHora(1500)).toBe('01:00')
  })
})

describe('instantes (fuso e virada do dia, §2.4)', () => {
  it('saída depois da meia-noite cai no dia civil seguinte', () => {
    expect(instanteDoHorario('2026-10-03', '01:00', 'America/Sao_Paulo', '05:00').toISOString()).toBe('2026-10-04T04:00:00.000Z')
    expect(instanteDoHorario('2026-10-03', '17:00', 'America/Sao_Paulo', '05:00').toISOString()).toBe('2026-10-03T20:00:00.000Z')
    expect(instanteDoHorario('2026-10-03', '05:00', 'America/Sao_Paulo', '05:00').toISOString()).toBe('2026-10-03T08:00:00.000Z')
  })
  it('instantes esperados do dia', () => {
    expect(instantesEsperados('2026-10-03', SALAO, 'America/Sao_Paulo', '05:00')).toEqual([
      { batida: 'entrada', instante: '2026-10-03T20:00:00.000Z' },
      { batida: 'saida_intervalo', instante: '2026-10-04T00:00:00.000Z' },
      { batida: 'volta_intervalo', instante: '2026-10-04T00:30:00.000Z' },
      { batida: 'saida', instante: '2026-10-04T04:00:00.000Z' },
    ])
  })
  it('outro fuso', () => {
    expect(instanteDoHorario('2026-07-01', '12:00', 'Europe/Lisbon', '05:00').toISOString()).toBe('2026-07-01T11:00:00.000Z')
    expect(instanteDoHorario('2026-01-15', '12:00', 'America/Manaus', '05:00').toISOString()).toBe('2026-01-15T16:00:00.000Z')
  })
  it('dia de trabalho de um instante', () => {
    expect(diaDeTrabalho(sp('2026-10-04T01:30'))).toBe('2026-10-03')
    expect(diaDeTrabalho(sp('2026-10-04T05:00'))).toBe('2026-10-04')
    expect(diaDeTrabalho(sp('2026-10-04T04:59'))).toBe('2026-10-03')
  })
})

describe('pares trabalhados (§7.2 passo 4, vetor §7.6)', () => {
  it('sáb 03/10: 16:58, 21:02, 21:29, 01:04 → 459', () => {
    const r = paresTrabalhados([sp('2026-10-03T16:58'), sp('2026-10-03T21:02'), sp('2026-10-03T21:29'), sp('2026-10-04T01:04')])
    expect(r.pares.map((p) => p.minutos)).toEqual([244, 215])
    expect(r.total).toBe(459)
    expect(r.sobra).toBeNull()
  })
  it('ímpar: a última fica sem par', () => {
    const r = paresTrabalhados([sp('2026-09-19T21:02'), sp('2026-09-19T16:58'), sp('2026-09-20T01:05')])
    expect(r.total).toBe(244)
    expect(r.sobra).toBe(sp('2026-09-20T01:05'))
  })
  it('trunca segundos (floor)', () => {
    expect(paresTrabalhados(['2026-10-03T20:00:00Z', '2026-10-03T20:01:59Z']).total).toBe(1)
  })
  it('vazio', () => {
    expect(paresTrabalhados([])).toEqual({ pares: [], sobra: null, total: 0 })
  })
})

describe('qual batida faltou (§7.3)', () => {
  const esperadas = instantesEsperados('2026-09-19', SALAO)
  it('exemplo do contrato: falta a volta do intervalo', () => {
    expect(identificarFaltantes([sp('2026-09-19T16:58'), sp('2026-09-19T21:02'), sp('2026-09-20T01:05')], esperadas)).toEqual([
      'volta_intervalo',
    ])
  })
  it('só entrada → faltam as 3 seguintes', () => {
    expect(identificarFaltantes([sp('2026-09-19T17:01')], esperadas)).toEqual(['saida_intervalo', 'volta_intervalo', 'saida'])
  })
  it('só saída', () => {
    expect(identificarFaltantes([sp('2026-09-20T01:10')], esperadas)).toEqual(['entrada', 'saida_intervalo', 'volta_intervalo'])
  })
  it('empate → combinação lexicograficamente menor (slots mais cedo)', () => {
    // batida exatamente no meio entre 21:00 e 21:30 → empate entre slot 2 e 3; vence o 2 (saida_intervalo)
    expect(identificarFaltantes([sp('2026-09-19T17:00'), sp('2026-09-19T21:15'), sp('2026-09-20T01:00')], esperadas)).toEqual([
      'volta_intervalo',
    ])
  })
  it('sem batidas → todas; completas → nenhuma', () => {
    expect(identificarFaltantes([], esperadas)).toHaveLength(4)
    expect(
      identificarFaltantes([sp('2026-09-19T17:00'), sp('2026-09-19T21:00'), sp('2026-09-19T21:30'), sp('2026-09-20T01:00')], esperadas),
    ).toEqual([])
  })
})

function batida(instante: string, extra: Partial<BatidaEspelho> = {}): BatidaEspelho {
  return { id: instante, instante, origem: 'controlid_acesso', desconsiderada: false, duplicada: false, motivo: null, ...extra }
}

function linha(extra: Partial<LinhaEspelho>): LinhaEspelho {
  return {
    data: '2026-09-19',
    dia_semana: 6,
    situacao: 'completo',
    encerrado: true,
    abono_tipo: null,
    jornada_nome: 'Salão noite',
    previsto_minutos: 450,
    trabalhado_minutos: 0,
    saldo_minutos: 0,
    atraso_minutos: 0,
    batidas: [],
    alarmes: [],
    esperadas: instantesEsperados('2026-09-19', SALAO),
    ...extra,
  }
}

describe('batidas válidas e resumo', () => {
  it('ignora desconsideradas e duplicadas e ordena', () => {
    const v = batidasValidas([
      batida(sp('2026-09-26T21:00')),
      batida(sp('2026-09-26T17:21'), { duplicada: true }),
      batida(sp('2026-09-26T17:20')),
      batida(sp('2026-09-26T18:00'), { desconsiderada: true }),
    ])
    expect(v.map((b) => b.instante)).toEqual([sp('2026-09-26T17:20'), sp('2026-09-26T21:00')])
  })
  it('resumo 3 de 4 com a batida faltante identificada', () => {
    const r = resumirBatidas(
      linha({ batidas: [batida(sp('2026-09-19T16:58')), batida(sp('2026-09-19T21:02')), batida(sp('2026-09-20T01:05'))] }),
    )
    expect(r).toEqual({ validas: 3, esperadas: 4, faltam: 1, impar: true, faltantes: ['volta_intervalo'] })
  })
  it('folga com batidas ímpares (sem esperadas)', () => {
    const r = resumirBatidas(linha({ esperadas: [], batidas: [batida(sp('2026-09-13T10:00'))] }))
    expect(r).toEqual({ validas: 1, esperadas: 0, faltam: 0, impar: true, faltantes: [] })
  })
})

describe('totais do espelho', () => {
  it('soma e conta', () => {
    const t = totaisDoEspelho([
      linha({ trabalhado_minutos: 459, saldo_minutos: 0, batidas: [batida(sp('2026-10-03T16:58'))] }),
      linha({ situacao: 'ausente', saldo_minutos: -450, alarmes: [{ id: 'a', tipo: 'sem_batida_dia_escalado', batida_esperada: '', status: 'aberto', detalhe: '', justificativa: null }] }),
      linha({ situacao: 'incompleto', trabalhado_minutos: 244, saldo_minutos: -206, atraso_minutos: 3, batidas: [batida(sp('2026-09-19T16:58'))], alarmes: [{ id: 'b', tipo: 'batida_faltando', batida_esperada: 'volta_intervalo', status: 'justificado', detalhe: '', justificativa: 'x' }] }),
      linha({ situacao: 'em_andamento', encerrado: false, saldo_minutos: 99 }),
    ])
    expect(t).toEqual({ previsto: 1800, trabalhado: 703, saldo: -656, atraso: 3, diasTrabalhados: 2, faltas: 1, incompletos: 1, alarmesAbertos: 1 })
  })
})

describe('períodos e validações', () => {
  it('mês', () => {
    expect(periodoDoMes('2026-02')).toEqual({ inicio: '2026-02-01', fim: '2026-02-28' })
    expect(periodoDoMes('2028-02')).toEqual({ inicio: '2028-02-01', fim: '2028-02-29' })
    expect(periodoDoMes('2026-10')).toEqual({ inicio: '2026-10-01', fim: '2026-10-31' })
    expect(somarMeses('2026-01', -1)).toBe('2025-12')
    expect(somarMeses('2026-12', 1)).toBe('2027-01')
    expect(nomeDoMes('2026-10')).toBe('outubro de 2026')
  })
  it('valida', () => {
    expect(mesValido('2026-10')).toBe(true)
    expect(mesValido('2026-13')).toBe(false)
    expect(mesValido(null)).toBe(false)
    expect(dataValida('2026-02-29')).toBe(false)
    expect(dataValida('2028-02-29')).toBe(true)
    expect(dataValida('ontem')).toBe(false)
  })
  it('rótulos', () => {
    expect(rotuloBatidaEsperada('volta_intervalo')).toBe('Volta do intervalo')
    expect(rotuloBatidaEsperada('')).toBe('')
  })
})

describe('lerDuracao', () => {
  it.each([
    ['2h30', 150],
    ['-1h', -60],
    ['+0h45', 45],
    ['02:30', 150],
    ['-03:26', -206],
    ['90', 90],
    ['90min', 90],
    ['1,5h', 90],
    ['-2.25h', -135],
    [' - 1h 15 ', -75],
  ])('%s → %i', (t, m) => expect(lerDuracao(t)).toBe(m))
  it.each(['', 'abc', '1h75', '1:7', '10:99'])('%s → null', (t) => expect(lerDuracao(t)).toBeNull())
})
