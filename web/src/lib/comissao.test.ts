import { describe, expect, it } from 'vitest'
import { calcularComissao, csvComissao, diasDoPeriodo, numeroCsv, tituloPadraoFechamento, validarPeriodoFechamento, type ParticipanteComissao } from './comissao'

const P = (nome: string, cargo: string, pontos: number, id: string, dias = 30, incluido = true): ParticipanteComissao => ({
  funcionarioId: id,
  nome,
  cargo,
  pontos,
  diasTrabalhados: dias,
  incluido,
})

const EQUIPE = [
  P('Ana Souza', 'Garçom', 10, 'a0000000-0000-4000-8000-000000000301'),
  P('Bruno Lima', 'Garçom', 10, 'a0000000-0000-4000-8000-000000000302'),
  P('Carla Dias', 'Cumim', 6, 'a0000000-0000-4000-8000-000000000303'),
  P('Davi Rocha', 'Bartender', 8, 'a0000000-0000-4000-8000-000000000304'),
  P('Eva Martins', 'Cozinha', 4, 'a0000000-0000-4000-8000-000000000305', 15),
]

const BASE = {
  servicoZigCentavos: 1_000_000,
  servicoAjusteCentavos: -5_000,
  percentualRetencao: 20,
  dataInicio: '2026-09-01',
  dataFim: '2026-09-30',
}

const valores = (r: ReturnType<typeof calcularComissao>) => Object.fromEntries(r.itens.map((i) => [i.nome, i.valorCentavos]))

describe('calcularComissao — vetor do contrato §9', () => {
  const r = calcularComissao({ ...BASE, proporcionalDias: false, participantes: EQUIPE })

  it('serviço, retenção e base', () => {
    expect(r.servicoBrutoCentavos).toBe(995_000)
    expect(r.retencaoCentavos).toBe(199_000)
    expect(r.baseCentavos).toBe(796_000)
    expect(r.diasPeriodo).toBe(30)
  })
  it('valores centavo a centavo (maior resto)', () => {
    expect(valores(r)).toEqual({
      'Ana Souza': 209_474,
      'Bruno Lima': 209_474,
      'Carla Dias': 125_684,
      'Davi Rocha': 167_579,
      'Eva Martins': 83_789,
    })
    expect(r.totalDistribuidoCentavos).toBe(796_000)
    expect(r.itens.filter((i) => i.centavoExtra).map((i) => i.nome).sort()).toEqual(['Ana Souza', 'Bruno Lima', 'Davi Rocha'])
  })
  it('soma de pontos e valor do ponto (6 casas)', () => {
    expect(r.somaPontosEfetivos).toBe(38)
    expect(r.valorPontoCentavos).toBe(20_947.368421)
    expect(r.semParticipantes).toBe(false)
  })
  it('exato exibido', () => {
    expect(r.itens[0]?.exatoCentavos).toBeCloseTo(209_473.684211, 5)
  })
})

describe('calcularComissao — proporcional aos dias (§9)', () => {
  const r = calcularComissao({ ...BASE, proporcionalDias: true, participantes: EQUIPE })
  it('pontos efetivos e soma', () => {
    expect(r.itens.find((i) => i.nome === 'Eva Martins')?.pontosEfetivos).toBe(2)
    expect(r.somaPontosEfetivos).toBe(36)
    expect(r.valorPontoCentavos).toBe(22_111.111111)
  })
  it('valores', () => {
    expect(valores(r)).toEqual({
      'Ana Souza': 221_111,
      'Bruno Lima': 221_111,
      'Carla Dias': 132_667,
      'Davi Rocha': 176_889,
      'Eva Martins': 44_222,
    })
    expect(r.totalDistribuidoCentavos).toBe(796_000)
  })
})

describe('calcularComissao — regras de borda', () => {
  it('ajuste negativo maior que o serviço → bruto 0, tudo zero', () => {
    const r = calcularComissao({ ...BASE, servicoAjusteCentavos: -2_000_000, proporcionalDias: false, participantes: EQUIPE })
    expect(r.servicoBrutoCentavos).toBe(0)
    expect(r.baseCentavos).toBe(0)
    expect(r.itens.every((i) => i.valorCentavos === 0)).toBe(true)
    expect(r.valorPontoCentavos).toBe(0)
  })
  it('sem participantes → valor do ponto null e todos zero', () => {
    const r = calcularComissao({ ...BASE, proporcionalDias: false, participantes: EQUIPE.map((p) => ({ ...p, incluido: false })) })
    expect(r.semParticipantes).toBe(true)
    expect(r.valorPontoCentavos).toBeNull()
    expect(r.totalDistribuidoCentavos).toBe(0)
    expect(r.itens.every((i) => i.pontosEfetivos === 0)).toBe(true)
  })
  it('lista vazia', () => {
    const r = calcularComissao({ ...BASE, proporcionalDias: false, participantes: [] })
    expect(r.semParticipantes).toBe(true)
    expect(r.baseCentavos).toBe(796_000)
  })
  it('não incluído recebe 0 e não entra na soma', () => {
    const r = calcularComissao({
      ...BASE,
      proporcionalDias: false,
      participantes: [P('Ana Souza', 'Garçom', 10, '1'), P('Bruno Lima', 'Garçom', 10, '2', 30, false)],
    })
    expect(valores(r)).toEqual({ 'Ana Souza': 796_000, 'Bruno Lima': 0 })
  })
  it('participante com 0 pontos fica de fora do rateio', () => {
    const r = calcularComissao({ ...BASE, proporcionalDias: false, participantes: [P('A', '', 1, '1'), P('B', '', 0, '2')] })
    expect(valores(r)).toEqual({ A: 796_000, B: 0 })
  })
  it('retenção arredonda meio para longe do zero', () => {
    // 1 centavo × 50% = 0,5 → 1
    const r = calcularComissao({ ...BASE, servicoZigCentavos: 1, servicoAjusteCentavos: 0, percentualRetencao: 50, proporcionalDias: false, participantes: [P('A', '', 1, '1')] })
    expect(r.retencaoCentavos).toBe(1)
    expect(r.baseCentavos).toBe(0)
  })
  it('retenção com decimais (12,5%)', () => {
    const r = calcularComissao({ ...BASE, servicoZigCentavos: 1_001, servicoAjusteCentavos: 0, percentualRetencao: 12.5, proporcionalDias: false, participantes: [] })
    expect(r.retencaoCentavos).toBe(125) // 125,125 → 125
  })
  it('retenção 0 e 100', () => {
    expect(calcularComissao({ ...BASE, percentualRetencao: 0, proporcionalDias: false, participantes: [] }).baseCentavos).toBe(995_000)
    expect(calcularComissao({ ...BASE, percentualRetencao: 100, proporcionalDias: false, participantes: [] }).baseCentavos).toBe(0)
  })
  it('desempate por pontos efetivos, depois nome, depois id', () => {
    // base 100, 3 participantes com 1 ponto: 33,33 cada → resto 1 → vai para o menor nome
    const r = calcularComissao({
      ...BASE,
      servicoZigCentavos: 125,
      servicoAjusteCentavos: 0,
      percentualRetencao: 20,
      proporcionalDias: false,
      participantes: [P('Caio', '', 1, '3'), P('Ana', '', 1, '9'), P('Ana', '', 1, '1')],
    })
    expect(r.baseCentavos).toBe(100)
    expect(r.itens.map((i) => [i.nome, i.funcionarioId, i.valorCentavos])).toEqual([
      ['Caio', '3', 33],
      ['Ana', '9', 33],
      ['Ana', '1', 34],
    ])
  })
  it('pontos fracionários (numeric(8,2))', () => {
    const r = calcularComissao({
      ...BASE,
      servicoZigCentavos: 1_000,
      servicoAjusteCentavos: 0,
      percentualRetencao: 0,
      proporcionalDias: false,
      participantes: [P('A', '', 1.5, '1'), P('B', '', 0.75, '2'), P('C', '', 0.75, '3')],
    })
    expect(valores(r)).toEqual({ A: 500, B: 250, C: 250 })
    expect(r.somaPontosEfetivos).toBe(3)
  })
  it('proporcional arredonda pontos efetivos em 6 casas', () => {
    const r = calcularComissao({
      ...BASE,
      dataInicio: '2026-10-01',
      dataFim: '2026-10-03',
      proporcionalDias: true,
      participantes: [P('A', '', 1, '1', 1), P('B', '', 1, '2', 2)],
    })
    expect(r.itens.map((i) => i.pontosEfetivos)).toEqual([0.333333, 0.666667])
    expect(r.totalDistribuidoCentavos).toBe(r.baseCentavos)
  })
  it('Σ valores = base sempre (varredura aleatória determinística)', () => {
    let semente = 42
    const aleatorio = () => {
      semente = (semente * 1_103_515_245 + 12_345) % 2 ** 31
      return semente / 2 ** 31
    }
    for (let caso = 0; caso < 300; caso++) {
      const n = 1 + Math.floor(aleatorio() * 9)
      const participantes = Array.from({ length: n }, (_, i) =>
        P(`F${i}`, '', Math.round(aleatorio() * 2000) / 100, String(i), Math.floor(aleatorio() * 31), aleatorio() > 0.15),
      )
      const r = calcularComissao({
        servicoZigCentavos: Math.floor(aleatorio() * 10_000_000),
        servicoAjusteCentavos: Math.floor(aleatorio() * 20_000) - 10_000,
        percentualRetencao: Math.round(aleatorio() * 10_000) / 100,
        proporcionalDias: aleatorio() > 0.5,
        dataInicio: '2026-09-01',
        dataFim: '2026-09-30',
        participantes,
      })
      if (!r.semParticipantes) expect(r.totalDistribuidoCentavos).toBe(r.baseCentavos)
      for (const i of r.itens) {
        expect(Number.isInteger(i.valorCentavos)).toBe(true)
        expect(Math.abs(i.valorCentavos - i.exatoCentavos)).toBeLessThan(1)
      }
    }
  })
})

describe('auxiliares', () => {
  it('dias do período', () => {
    expect(diasDoPeriodo('2026-09-01', '2026-09-30')).toBe(30)
    expect(diasDoPeriodo('2026-10-06', '2026-10-06')).toBe(1)
    expect(diasDoPeriodo('2026-02-01', '2026-03-01')).toBe(29)
  })
  it('título padrão', () => {
    expect(tituloPadraoFechamento('2026-09-01', '2026-09-30')).toBe('Comissão 01/09 a 30/09/2026')
    expect(tituloPadraoFechamento('2025-12-15', '2026-01-14')).toBe('Comissão 15/12/2025 a 14/01/2026')
  })
  it('valida período', () => {
    expect(validarPeriodoFechamento('2026-09-01', '2026-09-30')).toBeNull()
    expect(validarPeriodoFechamento('2026-09-30', '2026-09-01')).toBe('Período inválido')
    expect(validarPeriodoFechamento('2026-01-01', '2026-04-03')).toBeNull() // 92 dias de diferença
    expect(validarPeriodoFechamento('2026-01-01', '2026-04-04')).toBe('Período máximo de 93 dias')
    expect(validarPeriodoFechamento(null, '2026-01-01')).toBe('Informe o período')
  })
})

describe('CSV do fechamento — idêntico ao do N8N', () => {
  const r = calcularComissao({ ...BASE, proporcionalDias: false, participantes: EQUIPE })
  const fechamento = {
    data_inicio: '2026-09-01',
    data_fim: '2026-09-30',
    status: 'fechado' as const,
    servico_zig_centavos: r.servicoZigCentavos,
    servico_ajuste_centavos: r.servicoAjusteCentavos,
    servico_bruto_centavos: r.servicoBrutoCentavos,
    percentual_retencao: 20,
    retencao_centavos: r.retencaoCentavos,
    base_distribuivel_centavos: r.baseCentavos,
    valor_ponto_centavos: r.valorPontoCentavos,
  }
  const itens = [
    ...r.itens.map((i) => ({
      funcionario_nome: i.nome,
      cargo: i.cargo ?? null,
      incluido: i.incluido,
      pontos: i.pontos,
      dias_trabalhados: i.diasTrabalhados,
      pontos_efetivos: i.pontosEfetivos,
      valor_centavos: i.valorCentavos,
    })),
    { funcionario_nome: 'Zé; "Fora"', cargo: null, incluido: false, pontos: 2.5, dias_trabalhados: 0, pontos_efetivos: 0, valor_centavos: 0 },
  ]

  it('bate byte a byte com csvComissao (n8n/comum/lib/csv.mjs)', async () => {
    const caminho = new URL('../../../n8n/comum/lib/csv.mjs', import.meta.url).href
    const n8n = (await import(/* @vite-ignore */ caminho)) as {
      csvComissao(d: unknown): { nome: string; conteudo: string }
    }
    const esperado = n8n.csvComissao({ fechamento: { ...fechamento, empresa_nome: 'Bar Bossa Nova' }, itens })
    const nosso = csvComissao(fechamento, itens, 'Bar Bossa Nova')
    expect(nosso.nome).toBe(esperado.nome)
    expect(nosso.conteudo).toBe(esperado.conteudo)
  })

  it('conteúdo esperado', () => {
    const { nome, conteudo } = csvComissao(fechamento, itens, 'Bar Bossa Nova')
    expect(nome).toBe('comissao_bar-bossa-nova_2026-09-01_2026-09-30.csv')
    const linhas = conteudo.replace(/^﻿/, '').split('\r\n')
    expect(linhas.slice(0, 10)).toEqual([
      'Período;01/09/2026 a 30/09/2026',
      'Serviço Zig (R$);10000,00',
      'Ajuste (R$);-50,00',
      'Serviço bruto (R$);9950,00',
      'Retenção (%);20',
      'Retenção (R$);1990,00',
      'Base distribuível (R$);7960,00',
      'Valor do ponto (R$);209,47',
      'Status;Fechado',
      '',
    ])
    expect(linhas[10]).toBe('Funcionário;Cargo;Incluído;Pontos;Dias trabalhados;Pontos efetivos;Valor (R$)')
    expect(linhas[11]).toBe('Ana Souza;Garçom;Sim;10;30;10;2094,74')
    expect(linhas[16]).toBe('"Zé; ""Fora""";;Não;2,5;0;0;0,00')
    expect(linhas[17]).toBe('Total;;;38;;38;7960,00')
  })

  it('numeroCsv', () => {
    expect(numeroCsv(10)).toBe('10')
    expect(numeroCsv(2.5, 2)).toBe('2,5')
    expect(numeroCsv(7.333333)).toBe('7,333333')
    expect(numeroCsv(null)).toBe('')
    expect(numeroCsv(-0.0000001)).toBe('0')
  })
})
