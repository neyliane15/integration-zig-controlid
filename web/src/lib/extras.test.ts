import { describe, expect, it } from 'vitest'
import type { Diaria, GastosPeriodo } from '@/tipos/banco'
import { csvDiarias, csvGastos, fechamentoQueCobre, filtrarExtras, formatarTelefone, lerPontos, totaisDiarias } from './extras'

const dia = (d: Partial<Diaria>): Diaria => ({
  id: 'd',
  data: '2026-11-02',
  tipo: 'extra',
  extra_id: 'x',
  funcionario_id: null,
  pessoa_nome: 'Marcos Freitas',
  funcao: 'Garçom',
  pontos: 5,
  valor_centavos: 18000,
  observacao: null,
  pago: false,
  pago_em: null,
  fechado: false,
  criado_por_nome: 'Gerente',
  criado_em: '2026-11-02T20:00:00Z',
  ...d,
})

describe('extras', () => {
  it('lerPontos segue a regra do banco (0..9999,99, 2 casas)', () => {
    expect(lerPontos('1,5')).toBe(1.5)
    expect(lerPontos('0')).toBe(0)
    expect(lerPontos('9999.99')).toBe(9999.99)
    expect(lerPontos('10000')).toBeNull()
    expect(lerPontos('1,555')).toBeNull()
    expect(lerPontos('-1')).toBeNull()
    expect(lerPontos('')).toBeNull()
  })

  it('formata telefone', () => {
    expect(formatarTelefone('11988880001')).toBe('(11) 98888-0001')
    expect(formatarTelefone('1133334444')).toBe('(11) 3333-4444')
    expect(formatarTelefone('+55 11 x')).toBe('+55 11 x')
    expect(formatarTelefone(null)).toBe('')
  })

  it('busca por nome sem acento, função e dígitos do telefone/documento', () => {
    const l = [
      { nome: 'Márcio Lopes', funcao: 'Cozinha', telefone: '(11) 98888-7777', documento: null },
      { nome: 'Júlia Reis', funcao: 'Garçom', telefone: null, documento: '123.456.789-00' },
    ]
    expect(filtrarExtras(l, 'marcio').map((x) => x.nome)).toEqual(['Márcio Lopes'])
    expect(filtrarExtras(l, 'garç').map((x) => x.nome)).toEqual(['Júlia Reis'])
    expect(filtrarExtras(l, '98888').map((x) => x.nome)).toEqual(['Márcio Lopes'])
    expect(filtrarExtras(l, '456789').map((x) => x.nome)).toEqual(['Júlia Reis'])
    expect(filtrarExtras(l, '  ')).toHaveLength(2)
  })

  it('totais: pagos, a pagar, por tipo e pontos dos extras', () => {
    const t = totaisDiarias([
      dia({ pago: true, valor_centavos: 15000, pontos: 5 }),
      dia({ valor_centavos: 12000, pontos: 7.5 }),
      dia({ tipo: 'funcionario', extra_id: null, funcionario_id: 'f', pontos: null, pago: true, valor_centavos: 100 }),
    ])
    expect(t).toEqual({ pagas: 15100, aPagar: 12000, total: 27100, quantidade: 3, extras: 27000, funcionarios: 100, diasExtras: 2, pontos: 12.5 })
  })

  it('fechamento fechado que cobre a data', () => {
    const f = [
      { id: 'r', status: 'rascunho', data_inicio: '2026-11-01', data_fim: '2026-11-30' },
      { id: 'f', status: 'fechado', data_inicio: '2026-10-01', data_fim: '2026-10-31' },
    ]
    expect(fechamentoQueCobre(f, '2026-10-31')?.id).toBe('f')
    expect(fechamentoQueCobre(f, '2026-11-05')).toBeNull()
    expect(fechamentoQueCobre(f, null)).toBeNull()
  })

  it('CSV dos dias trabalhados', () => {
    const { nome, conteudo } = csvDiarias(
      [
        dia({ data: '2026-11-03', pontos: 7.5, pago: true, pago_em: '2026-11-04' }),
        dia({ tipo: 'funcionario', extra_id: null, funcionario_id: 'f', pessoa_nome: 'Ana Souza', pontos: null, valor_centavos: 12000, observacao: 'Cobriu folga' }),
        dia({}),
      ],
      'Bar Bossa Nova',
      '2026-11-01',
      '2026-11-30',
    )
    expect(nome).toBe('dias-trabalhados_bar-bossa-nova_2026-11-01_2026-11-30.csv')
    const l = conteudo.replace(/^﻿/, '').split('\r\n')
    expect(l[0]).toBe('Data;Pessoa;Tipo;Função;Pontos;Valor (R$);Pago;Pago em;Observação')
    expect(l[1]).toBe('02/11/2026;Ana Souza;Funcionário;Garçom;;120,00;Não;;Cobriu folga')
    expect(l[2]).toBe('02/11/2026;Marcos Freitas;Extra;Garçom;5;180,00;Não;;')
    expect(l[3]).toBe('03/11/2026;Marcos Freitas;Extra;Garçom;7,5;180,00;Sim;04/11/2026;')
    expect(l[4]).toBe('Total;;;;12,5;480,00;;;')
  })

  it('CSV de gastos', () => {
    const g: GastosPeriodo = {
      empresa_id: 'e',
      inicio: '2026-11-01',
      fim: '2026-11-30',
      totais: {
        diarias_pagas: 30000,
        diarias_a_pagar: 15000,
        diarias: 45000,
        diarias_qtd: 3,
        diarias_extras: 33000,
        diarias_funcionarios: 12000,
        comissoes_fechadas: 796000,
        comissoes_previstas: 120000,
        total: 841000,
        total_com_previsto: 961000,
      },
      por_pessoa: [
        { chave: 'f:1', tipo: 'funcionario', funcionario_id: '1', extra_id: null, nome: 'Ana Souza', diarias_qtd: 1, diarias_pagas: 15000, diarias_a_pagar: 0, comissoes_fechadas: 209474, comissoes_previstas: 0, total: 224474 },
        { chave: 'x:2', tipo: 'extra', funcionario_id: null, extra_id: '2', nome: '=Xis', diarias_qtd: 2, diarias_pagas: 15000, diarias_a_pagar: 15000, comissoes_fechadas: 0, comissoes_previstas: 0, total: 30000 },
      ],
      por_dia: [],
      fechamentos: [],
    }
    const { nome, conteudo } = csvGastos(g, 'Bar Bossa Nova')
    expect(nome).toBe('gastos_bar-bossa-nova_2026-11-01_2026-11-30.csv')
    const l = conteudo.replace(/^﻿/, '').split('\r\n')
    expect(l[0]).toBe('Período;01/11/2026 a 30/11/2026')
    expect(l[1]).toBe('Diárias de extras (R$);330,00')
    expect(l[7]).toBe('Total (R$);8410,00')
    expect(l[9]).toBe('')
    expect(l[10]).toBe('Pessoa;Tipo;Diárias (qtd);Diárias pagas (R$);Diárias a pagar (R$);Comissões fechadas (R$);Comissões previstas (R$);Total (R$)')
    expect(l[11]).toBe('Ana Souza;Funcionário;1;150,00;0,00;2094,74;0,00;2244,74')
    expect(l[12]).toBe("'=Xis;Extra;2;150,00;150,00;0,00;0,00;300,00")
    expect(l[13]).toBe('Total;;3;300,00;150,00;7960,00;1200,00;8410,00')
  })
})
