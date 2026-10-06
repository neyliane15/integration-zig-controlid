import { describe, expect, it } from 'vitest'
import type { VendaPorGarcom } from '@/tipos/banco'
import {
  diasDoIntervalo,
  escalaBarras,
  estatisticasDias,
  faturamentoDiaForma,
  indicadores,
  participacaoPorForma,
  preencherDias,
  rankingGarcons,
  validarPeriodoVendas,
} from './vendas'

const G = (employee_name: string | null, valor_vendas: number, valor_servico = 0, transacoes = 1): VendaPorGarcom => ({
  employee_name,
  funcionario_id: null,
  funcionario_nome: null,
  quantidade: 1,
  valor_vendas,
  valor_servico,
  transacoes,
})

describe('dias', () => {
  it('intervalo inclusivo, atravessando mês', () => {
    expect(diasDoIntervalo('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'])
    expect(diasDoIntervalo('2026-10-02', '2026-10-01')).toEqual([])
  })
  it('preenche dias vazios e soma repetidos', () => {
    expect(
      preencherDias('2026-10-01', '2026-10-03', [
        { data: '2026-10-03', valor: 100 },
        { data: '2026-10-01', valor: 50 },
        { data: '2026-10-01', valor: 25 },
      ]),
    ).toEqual([
      { data: '2026-10-01', valor: 75 },
      { data: '2026-10-02', valor: 0 },
      { data: '2026-10-03', valor: 100 },
    ])
  })
})

describe('barras', () => {
  it('relativas ao máximo, mínimo visível 1%', () => {
    const { barras, maximo } = escalaBarras([{ valor: 200 }, { valor: 100 }, { valor: 0 }, { valor: 1 }, { valor: -5 }])
    expect(maximo).toBe(200)
    expect(barras.map((b) => b.percentual)).toEqual([100, 50, 0, 1, 0])
  })
  it('tudo zero', () => {
    expect(escalaBarras([{ valor: 0 }]).barras[0]?.percentual).toBe(0)
  })
})

describe('estatísticas', () => {
  it('total, média dos dias com movimento, melhor e pior', () => {
    const e = estatisticasDias([
      { data: 'a', valor: 100 },
      { data: 'b', valor: 0 },
      { data: 'c', valor: 301 },
    ])
    expect(e.total).toBe(401)
    expect(e.diasComMovimento).toBe(2)
    expect(e.mediaPorDiaComMovimento).toBe(201) // 200,5 → 201
    expect(e.melhor?.data).toBe('c')
    expect(e.pior?.data).toBe('a')
  })
  it('vazio', () => {
    expect(estatisticasDias([])).toEqual({ total: 0, diasComMovimento: 0, mediaPorDiaComMovimento: 0, melhor: null, pior: null })
  })
})

describe('formas de pagamento', () => {
  it('ordena e calcula participação', () => {
    const r = participacaoPorForma([
      { payment_id: 1, payment_name: 'Pix', valor: 250 },
      { payment_id: 2, payment_name: 'Crédito', valor: 500 },
      { payment_id: 3, payment_name: 'Débito', valor: 250 },
    ])
    expect(r.total).toBe(1000)
    expect(r.formas.map((f) => [f.payment_name, f.percentual])).toEqual([
      ['Crédito', 50],
      ['Débito', 25],
      ['Pix', 25],
    ])
  })
})

describe('ranking de garçons', () => {
  it('ordena por vendas, sem garçom no fim e sem posição', () => {
    const r = rankingGarcons([G(null, 9_999), G('Bruno Lima', 5_000, 500, 4), G('Ana Souza', 5_000, 600, 0), G('Davi Rocha', 10_000, 0, 3)])
    expect(r.map((l) => [l.posicao, l.nomeExibido])).toEqual([
      [1, 'Davi Rocha'],
      [2, 'Ana Souza'],
      [3, 'Bruno Lima'],
      [0, '(sem garçom)'],
    ])
    expect(r[0]?.ticketMedio).toBe(3_333)
    expect(r[1]?.ticketMedio).toBe(0)
    expect(r[0]?.percentual).toBe(33.3)
  })
  it('nome em branco conta como sem garçom', () => {
    expect(rankingGarcons([G('  ', 10)])[0]?.nomeExibido).toBe('(sem garçom)')
  })
})

describe('indicadores', () => {
  it('ticket médio, % de serviço e conferência', () => {
    const i = indicadores({ faturamento: 110_000, vendas: 100_000, servico: 10_000, descontos: 500, transacoes: 3, servico_compradores: 9_900 })
    expect(i.ticketMedio).toBe(36_667)
    expect(i.percentualServico).toBe(10)
    expect(i.divergenciaServico).toBe(100)
  })
  it('nulo → zeros', () => {
    expect(indicadores(null).ticketMedio).toBe(0)
  })
})

describe('faturamento por dia e forma (CSV)', () => {
  it('agrupa e ordena', () => {
    expect(
      faturamentoDiaForma([
        { data_operacao: '2026-10-02', payment_name: 'Pix', valor: 10 },
        { data_operacao: '2026-10-01', payment_name: 'Pix', valor: 5 },
        { data_operacao: '2026-10-01', payment_name: 'Crédito', valor: 30 },
        { data_operacao: '2026-10-01', payment_name: 'Pix', valor: 40 },
      ]),
    ).toEqual([
      { data: '2026-10-01', forma: 'Pix', valor: 45 },
      { data: '2026-10-01', forma: 'Crédito', valor: 30 },
      { data: '2026-10-02', forma: 'Pix', valor: 10 },
    ])
  })
})

describe('período', () => {
  it('valida', () => {
    expect(validarPeriodoVendas('2026-01-01', '2026-12-31')).toBeNull()
    expect(validarPeriodoVendas('2026-01-01', '2027-01-02')).toBe('Período máximo de 366 dias')
    expect(validarPeriodoVendas('2026-02-01', '2026-01-01')).toBe('Período inválido')
  })
})
