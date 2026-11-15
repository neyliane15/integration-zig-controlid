import { describe, expect, it } from 'vitest'
import {
  MODELO_CSV_EXTRAS,
  chaveExtra,
  converterExtras,
  lerCsv,
  lerDatas,
  lerPontosCsv,
  lerValorCentavos,
  linhasDoItem,
  paraImportacao,
  reconhecerColunasExtras,
} from './extrasCsv'

describe('importação de extras (CSV)', () => {
  it('reconhece colunas variadas', () => {
    const m = reconhecerColunasExtras(['Nome completo', 'Cargo', 'Celular', 'CPF', 'Diária', 'Pontuação', 'Datas trabalhadas', 'Outra'])
    expect(m).toEqual({ nome: 0, funcao: 1, telefone: 2, documento: 3, valor: 4, pontos: 5, dias: 6 })
    const en = reconhecerColunasExtras(['Name', 'Role', 'Phone', 'Document', 'Daily rate', 'Points', 'Date'])
    expect(en).toEqual({ nome: 0, funcao: 1, telefone: 2, documento: 3, valor: 4, pontos: 5, dias: 6 })
  })
  it('valores, pontos e datas', () => {
    expect(lerValorCentavos('150')).toBe(15000)
    expect(lerValorCentavos('150,5')).toBe(15050)
    expect(lerValorCentavos('R$ 1.234,56')).toBe(123456)
    expect(lerValorCentavos('1.500')).toBe(150000)
    expect(lerValorCentavos('12.34')).toBe(1234)
    expect(lerValorCentavos('')).toBeNull()
    expect(lerValorCentavos('abc')).toBeNaN()
    expect(lerPontosCsv('7,5')).toBe(7.5)
    expect(lerPontosCsv('')).toBeNull()
    expect(lerPontosCsv('-1')).toBeNaN()
    expect(lerPontosCsv('1,234')).toBeNaN()
    expect(lerDatas('03/09/2026, 04/09/2026 | 2026-09-05')).toEqual({ datas: ['2026-09-03', '2026-09-04', '2026-09-05'], invalidas: [] })
    expect(lerDatas('ontem').invalidas).toEqual(['ontem'])
    expect(lerDatas('')).toEqual({ datas: [], invalidas: [] })
  })
  it('agrupa a mesma pessoa (documento normalizado, senão nome), marca sem pontos e erros por linha', () => {
    const m = lerCsv(
      [
        'Nome;Função;Documento;Diária;Pontos;Data',
        'Zé Pereira;Cumim;123.456.789-00;150;;03/09/2026',
        'Ze Pereira (outro jeito);;12345678900;;;04/09/2026',
        '  marina   costa ;Garçom;;180;6;03/09/2026',
        'Marina Costa;;;;;05/09/2026',
        ';;;;;',
        'Sem Nome Válido;;;abc;;',
        'Rafael;Bar;;160;99999;',
        'Bia;;;;;31/02/2026',
      ].join('\n'),
      ';',
      true,
    )
    const r = converterExtras(m.slice(1), reconhecerColunasExtras(m[0]!))
    expect(r.extras.map((x) => [x.nome, x.linhas, x.pontos, x.dias_trabalhados.map((d) => d.data)])).toEqual([
      ['Zé Pereira', [2, 3], null, ['2026-09-03', '2026-09-04']],
      ['marina costa', [4, 5], 6, ['2026-09-03', '2026-09-05']],
    ])
    expect(r.semPontos).toBe(1)
    expect(r.erros).toEqual([
      { linha: 7, mensagem: 'Valor inválido: “abc”' },
      { linha: 8, mensagem: 'Pontos inválidos: “99999”' },
      { linha: 9, mensagem: 'Data inválida: “31/02/2026”' },
    ])
    const payload = paraImportacao(r.extras)
    expect(payload[0]).toEqual({
      nome: 'Zé Pereira',
      funcao: 'Cumim',
      telefone: null,
      documento: '123.456.789-00',
      valor_diaria_centavos: 15000,
      pontos: null,
      dias_trabalhados: [
        { data: '2026-09-03', valor_centavos: 15000, pontos: null },
        { data: '2026-09-04', valor_centavos: null, pontos: null },
      ],
    })
    expect(linhasDoItem(r.extras, 2)).toEqual([4, 5])
    expect(chaveExtra('A', ' 12.3-a ')).toBe('d:123a')
    expect(chaveExtra('  Ana   Souza ', null)).toBe('n:ana souza')
  })
  it('modelo lê sem erros e tem um extra sem pontuação', () => {
    const m = lerCsv(MODELO_CSV_EXTRAS)
    const r = converterExtras(m.slice(1), reconhecerColunasExtras(m[0]!))
    expect(r.erros).toEqual([])
    expect(r.extras).toHaveLength(3)
    expect(r.semPontos).toBe(1)
    expect(MODELO_CSV_EXTRAS.startsWith('﻿')).toBe(true)
    expect(MODELO_CSV_EXTRAS.endsWith('\r\n')).toBe(true)
  })
})
