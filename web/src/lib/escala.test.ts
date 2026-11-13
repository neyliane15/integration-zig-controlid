import { describe, expect, it } from 'vitest'
import {
  chegadaParaHora,
  chegadaValida,
  diasDoMes,
  dowDomingo,
  estadoEfetivo,
  horaParaChegada,
  indiceSegunda,
  interpretarCelula,
  montarTsv,
  normT,
  proximaCelula,
  somarMeses,
  textoCelula,
  textoFolgas,
} from './escala'

describe('normT (igual ao modelo)', () => {
  it.each([
    ['', ''],
    ['   ', ''],
    ['f', 'F'],
    ['F', 'F'],
    ['Folga', 'F'],
    ['fe', 'FÉ'],
    ['FÉ', 'FÉ'],
    ['férias', 'FÉ'],
    ['ferias', 'FÉ'],
    ['8', '8h'],
    ['08', '8h'],
    ['8h', '8h'],
    ['8:00', '8h'],
    ['9h00', '9h'],
    ['11:30', '11h30'],
    ['11.30', '11h30'],
    ['1130', '11h30'],
    ['11h30', '11h30'],
    ['7hs', '7h'],
    ['23:59', '23h59'],
    ['24', '24'],
    ['10:75', '10:75'],
    ['qualquer coisa', 'qualqu'],
  ])('%j → %j', (e, s) => expect(normT(e)).toBe(s))
  it('null/undefined', () => {
    expect(normT(null)).toBe('')
    expect(normT(undefined)).toBe('')
  })
})

describe('conversões de horário', () => {
  it('chegada ↔ hora', () => {
    expect(chegadaParaHora('8h')).toBe('08:00')
    expect(chegadaParaHora('11h30')).toBe('11:30')
    expect(chegadaParaHora('F')).toBeNull()
    expect(chegadaParaHora('')).toBeNull()
    expect(horaParaChegada('08:00:00')).toBe('8h')
    expect(horaParaChegada('11:30')).toBe('11h30')
    expect(horaParaChegada(null)).toBe('')
    expect(chegadaValida('f')).toBe('')
    expect(chegadaValida('8')).toBe('8h')
    expect(chegadaValida('abc')).toBe('')
  })
  it('dias da semana', () => {
    expect(indiceSegunda(1)).toBe(0)
    expect(indiceSegunda(0)).toBe(6)
    expect(dowDomingo(6)).toBe(0)
    expect(dowDomingo(0)).toBe(1)
    expect(textoFolgas([3, 2])).toBe('QUA, QUI')
  })
})

describe('estado e célula', () => {
  it('ajuste vence; férias vencem folga', () => {
    expect(estadoEfetivo(null, true, false)).toBe('folga')
    expect(estadoEfetivo(null, true, true)).toBe('ferias')
    expect(estadoEfetivo(null, false, false)).toBe('trabalha')
    expect(estadoEfetivo('trabalha', true, true)).toBe('trabalha')
  })
  it('interpretarCelula segue o commitCell do modelo', () => {
    const trab = { folga: false, ferias: false }
    const folga = { folga: true, ferias: false }
    const ferias = { folga: false, ferias: true }
    expect(interpretarCelula('f', trab)).toEqual({ estado: 'folga', chegada: null })
    expect(interpretarCelula('f', folga)).toEqual({ estado: null, chegada: null })
    expect(interpretarCelula('f', ferias)).toEqual({ estado: 'folga', chegada: null })
    expect(interpretarCelula('fe', ferias)).toEqual({ estado: null, chegada: null })
    expect(interpretarCelula('fe', trab)).toEqual({ estado: 'ferias', chegada: null })
    expect(interpretarCelula('', trab)).toEqual({ estado: null, chegada: null })
    expect(interpretarCelula('', folga)).toEqual({ estado: 'trabalha', chegada: null })
    expect(interpretarCelula('8', trab)).toEqual({ estado: null, chegada: '08:00' })
    expect(interpretarCelula('8', trab, '08:00')).toEqual({ estado: null, chegada: null })
    expect(interpretarCelula('11:30', folga)).toEqual({ estado: 'trabalha', chegada: '11:30' })
  })
  it('textoCelula', () => {
    expect(textoCelula('folga', '08:00')).toBe('F')
    expect(textoCelula('ferias', null)).toBe('FÉ')
    expect(textoCelula('trabalha', '11:30')).toBe('11h30')
    expect(textoCelula('trabalha', null)).toBe('')
  })
})

describe('mês', () => {
  it('novembro de 2026 começa num domingo e tem 30 dias', () => {
    const d = diasDoMes('2026-11')
    expect(d).toHaveLength(30)
    expect(d[0]).toEqual({ dia: 1, data: '2026-11-01', semana: 6, rotulo: 'DOM' })
    expect(d[1]!.rotulo).toBe('SEG')
  })
  it('fevereiro bissexto e mês inválido', () => {
    expect(diasDoMes('2028-02')).toHaveLength(29)
    expect(diasDoMes('2026-2')).toEqual([])
  })
  it('somarMeses atravessa o ano', () => {
    expect(somarMeses('2026-12', 1)).toBe('2027-01')
    expect(somarMeses('2026-01', -1)).toBe('2025-12')
  })
})

describe('navegação', () => {
  const lim = { linhas: 3, colunas: 5 }
  it('Enter/↓ descem, ↑ sobe, bordas seguram', () => {
    expect(proximaCelula({ linha: 0, coluna: 2 }, 'Enter', lim)).toEqual({ linha: 1, coluna: 2 })
    expect(proximaCelula({ linha: 0, coluna: 2 }, 'ArrowDown', lim)).toEqual({ linha: 1, coluna: 2 })
    expect(proximaCelula({ linha: 0, coluna: 2 }, 'ArrowUp', lim)).toEqual({ linha: 0, coluna: 2 })
    expect(proximaCelula({ linha: 2, coluna: 2 }, 'Enter', lim)).toEqual({ linha: 2, coluna: 2 })
    expect(proximaCelula({ linha: 0, coluna: 0 }, 'a', lim)).toBeNull()
  })
  it('←/→ só no começo/fim do texto', () => {
    expect(proximaCelula({ linha: 1, coluna: 1 }, 'ArrowRight', lim, { inicio: 0, fim: 1, tamanho: 2 })).toBeNull()
    expect(proximaCelula({ linha: 1, coluna: 1 }, 'ArrowRight', lim, { inicio: 2, fim: 2, tamanho: 2 })).toEqual({ linha: 1, coluna: 2 })
    expect(proximaCelula({ linha: 1, coluna: 1 }, 'ArrowLeft', lim, { inicio: 1, fim: 1, tamanho: 2 })).toBeNull()
    expect(proximaCelula({ linha: 1, coluna: 1 }, 'ArrowLeft', lim)).toEqual({ linha: 1, coluna: 0 })
  })
})

describe('montarTsv', () => {
  it('cabeçalho, setor, pessoas com chegada padrão e +FÉ, linha Na escala', () => {
    const dias = diasDoMes('2026-11').slice(0, 3)
    const tsv = montarTsv(
      dias,
      [
        {
          nome: 'Salão',
          linhas: [
            { nome: 'Ana\tSouza', celulas: ['F', '', '11h30'], chegadaPadrao: '8h', folgas: 1, ferias: 0 },
            { nome: 'Bruno', celulas: ['FÉ', 'FÉ', ''], chegadaPadrao: '', folgas: 0, ferias: 2 },
          ],
        },
      ],
      [0, 1, 2],
    )
    expect(tsv.split('\n')).toEqual([
      'Nome\t1 DOM\t2 SEG\t3 TER\tFolgas',
      'Salão',
      'Ana Souza\tF\t8h\t11h30\t1',
      'Bruno\tFÉ\tFÉ\t\t0 +2FÉ',
      'Na escala\t0\t1\t2\t',
    ])
  })
})
