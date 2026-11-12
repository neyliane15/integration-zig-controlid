import { describe, expect, it } from 'vitest'
import type { GastosPeriodo } from '@/tipos/banco'
import { csvGastos, fechamentoQueCobre, lerPontosExtras, totaisDiarias } from './extras'

describe('extras', () => {
  it('lerPontosExtras segue a regra do banco', () => {
    expect(lerPontosExtras('1,5')).toBe(1.5)
    expect(lerPontosExtras('3')).toBe(3)
    expect(lerPontosExtras('9999.99')).toBe(9999.99)
    expect(lerPontosExtras('0')).toBeNull()
    expect(lerPontosExtras('10000')).toBeNull()
    expect(lerPontosExtras('1,555')).toBeNull()
    expect(lerPontosExtras('-1')).toBeNull()
    expect(lerPontosExtras('')).toBeNull()
  })

  it('totais das diárias', () => {
    expect(totaisDiarias([{ pago: true, valor_centavos: 15000 }, { pago: false, valor_centavos: 12000 }, { pago: true, valor_centavos: 100 }])).toEqual({
      pagas: 15100,
      aPagar: 12000,
      total: 27100,
      quantidade: 3,
    })
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

  it('CSV de gastos', () => {
    const g: GastosPeriodo = {
      empresa_id: 'e',
      inicio: '2026-11-01',
      fim: '2026-11-30',
      totais: { diarias_pagas: 30000, diarias_a_pagar: 15000, diarias: 45000, diarias_qtd: 3, comissoes_fechadas: 796000, comissoes_previstas: 120000, total: 841000, total_com_previsto: 961000 },
      por_pessoa: [
        { chave: 'f:1', funcionario_id: '1', nome: 'Ana Souza', avulso: false, diarias_qtd: 1, diarias_pagas: 15000, diarias_a_pagar: 0, comissoes_fechadas: 209474, comissoes_previstas: 0, total: 224474 },
        { chave: 'a:=x', funcionario_id: null, nome: '=Xis', avulso: true, diarias_qtd: 2, diarias_pagas: 15000, diarias_a_pagar: 15000, comissoes_fechadas: 0, comissoes_previstas: 0, total: 30000 },
      ],
      por_dia: [],
      fechamentos: [],
    }
    const { nome, conteudo } = csvGastos(g, 'Bar Bossa Nova')
    expect(nome).toBe('gastos_bar-bossa-nova_2026-11-01_2026-11-30.csv')
    const l = conteudo.replace(/^﻿/, '').split('\r\n')
    expect(l[0]).toBe('Período;01/11/2026 a 30/11/2026')
    expect(l[5]).toBe('Total (R$);8410,00')
    expect(l[7]).toBe('')
    expect(l[8]).toBe('Pessoa;Avulso;Diárias (qtd);Diárias pagas (R$);Diárias a pagar (R$);Comissões fechadas (R$);Comissões previstas (R$);Total (R$)')
    expect(l[9]).toBe('Ana Souza;Não;1;150,00;0,00;2094,74;0,00;2244,74')
    expect(l[10]).toBe("'=Xis;Sim;2;150,00;150,00;0,00;0,00;300,00")
    expect(l[11]).toBe('Total;;3;300,00;150,00;7960,00;1200,00;8410,00')
  })
})
