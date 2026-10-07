import { describe, expect, it } from 'vitest'
import { centavosCsv, dataCsv, gerarCsv, minutosCsv, nomeArquivoCsv, slug } from './csv'

describe('gerarCsv (§13)', () => {
  it('BOM, ponto e vírgula e CRLF em toda linha', () => {
    const csv = gerarCsv(['Data', 'Valor (R$)'], [['06/10/2026', '2094,74']])
    expect(csv).toBe('﻿Data;Valor (R$)\r\n06/10/2026;2094,74\r\n')
  })
  it('aspas quando necessário (;, aspas, quebra de linha)', () => {
    const csv = gerarCsv(['A'], [['a;b'], ['diz "oi"'], ['linha\nnova'], ['simples']])
    expect(csv.split('\r\n').slice(1, 5)).toEqual(['"a;b"', '"diz ""oi"""', '"linha\nnova"', 'simples'])
  })
  it('null/undefined vazios e booleanos Sim/Não', () => {
    expect(gerarCsv(['a', 'b', 'c', 'd'], [[null, undefined, true, false]])).toBe('﻿a;b;c;d\r\n;;Sim;Não\r\n')
  })
  it('preâmbulo seguido de linha em branco', () => {
    const csv = gerarCsv(['Funcionário'], [['Ana']], [['Período', '01/10/2026 a 31/10/2026'], ['Status', 'Fechado']])
    expect(csv).toBe('﻿Período;01/10/2026 a 31/10/2026\r\nStatus;Fechado\r\n\r\nFuncionário\r\nAna\r\n')
  })
  it('(revisão 2) neutraliza fórmula no começo do texto (= + - @ TAB CR), mas não números nossos', () => {
    const csv = gerarCsv(['x'], [['=HYPERLINK("http://x";"Clique")'], ['+1+1'], ['-2+3'], ['@SUM(A1)'], ['\tTAB'], ['-50,00'], ['-03:26'], ['-1'], ['+55'], ['Ana = Bia'], [-5]])
    expect(csv.split('\r\n').slice(1, -1)).toEqual([
      `"'=HYPERLINK(""http://x"";""Clique"")"`,
      "'+1+1",
      "'-2+3",
      "'@SUM(A1)",
      "'\tTAB",
      '-50,00',
      '-03:26',
      '-1',
      '+55',
      'Ana = Bia',
      '-5',
    ])
  })
  it('sem preâmbulo vazio não gera linha em branco', () => {
    expect(gerarCsv(['x'], [], [])).toBe('﻿x\r\n')
  })
})

describe('conversores', () => {
  it('dinheiro, minutos e datas', () => {
    expect(centavosCsv(209474)).toBe('2094,74')
    expect(centavosCsv(-1)).toBe('-0,01')
    expect(centavosCsv(null)).toBe('')
    expect(minutosCsv(-206)).toBe('-03:26')
    expect(minutosCsv(undefined)).toBe('')
    expect(dataCsv('2026-10-06')).toBe('06/10/2026')
    expect(dataCsv(null)).toBe('')
  })
  it('nome do arquivo', () => {
    expect(slug('Bar Bossa Nová & Cia')).toBe('bar-bossa-nova-cia')
    expect(nomeArquivoCsv('comissao', 'Bar Bossa Nova', '2026-10-01', '2026-10-31')).toBe('comissao_bar-bossa-nova_2026-10-01_2026-10-31.csv')
    expect(nomeArquivoCsv('faturamento', 'Cantina Roma', '2026-10-06', '2026-10-06')).toBe('faturamento_cantina-roma_2026-10-06.csv')
  })
})
