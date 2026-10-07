import { describe, expect, it } from 'vitest'
import {
  centavosParaTexto,
  diaSemanaCurto,
  formatarCentavos,
  formatarData,
  formatarDataCurta,
  formatarDataHora,
  formatarHora,
  formatarMinutos,
  formatarRelativo,
  hojeISO,
  minutosHHMM,
  normalizar,
  somarDias,
  textoParaCentavos,
} from './formato'

const nbsp = (s: string) => s.replace(/\s/g, ' ')

describe('dinheiro', () => {
  it('formata centavos em reais', () => {
    expect(nbsp(formatarCentavos(123456))).toBe('R$ 1.234,56')
    expect(nbsp(formatarCentavos(0))).toBe('R$ 0,00')
    expect(nbsp(formatarCentavos(-5))).toMatch(/^-R\$ 0,05$/)
    expect(nbsp(formatarCentavos(100, { sinal: true }))).toBe('+R$ 1,00')
    expect(formatarCentavos(null)).toBe('—')
  })
  it('centavos ↔ texto', () => {
    expect(centavosParaTexto(209474)).toBe('2094,74')
    expect(centavosParaTexto(-5)).toBe('-0,05')
    expect(centavosParaTexto(100000000)).toBe('1000000,00')
    expect(textoParaCentavos('1.234,56')).toBe(123456)
    expect(textoParaCentavos('R$ 10')).toBe(1000)
    expect(textoParaCentavos('1234.5')).toBe(123450)
    expect(textoParaCentavos('-50')).toBe(-5000)
    expect(textoParaCentavos('0,1')).toBe(10)
    expect(textoParaCentavos('')).toBeNull()
    expect(textoParaCentavos('abc')).toBeNull()
  })
})

describe('minutos', () => {
  it('formatarMinutos', () => {
    expect(formatarMinutos(450)).toBe('7h30')
    expect(formatarMinutos(-206)).toBe('-3h26')
    expect(formatarMinutos(0)).toBe('0h00')
    expect(formatarMinutos(5, { sinal: true })).toBe('+0h05')
    expect(formatarMinutos(undefined)).toBe('—')
  })
  it('minutosHHMM', () => {
    expect(minutosHHMM(-206)).toBe('-03:26')
    expect(minutosHHMM(450)).toBe('07:30')
    expect(minutosHHMM(0)).toBe('00:00')
    expect(minutosHHMM(6000)).toBe('100:00')
  })
})

describe('datas', () => {
  it('formata datas civis', () => {
    expect(formatarData('2026-10-06')).toBe('06/10/2026')
    expect(formatarData(null)).toBe('—')
    expect(formatarDataCurta('2026-10-06')).toBe('06/10')
    expect(diaSemanaCurto('2026-10-03')).toBe('sáb')
    expect(diaSemanaCurto('2026-10-04')).toBe('dom')
  })
  it('horas no fuso', () => {
    expect(formatarHora('2026-10-05T20:02:11Z')).toBe('17:02')
    expect(formatarHora('2026-10-05T20:02:11Z', 'America/Manaus')).toBe('16:02')
    expect(formatarDataHora('2026-10-05T03:30:00Z')).toBe('05/10/2026 00:30')
  })
  it('relativo', () => {
    const agora = new Date('2026-10-06T12:00:00Z')
    expect(formatarRelativo('2026-10-06T11:59:30Z', agora)).toBe('agora')
    expect(formatarRelativo('2026-10-06T11:55:00Z', agora)).toBe('há 5 min')
    expect(formatarRelativo('2026-10-06T09:00:00Z', agora)).toBe('há 3 h')
    expect(formatarRelativo('2026-10-05T11:00:00Z', agora)).toBe('há 1 dia')
    expect(formatarRelativo('2026-10-03T11:00:00Z', agora)).toBe('há 3 dias')
    expect(formatarRelativo(null)).toBe('nunca')
  })
  it('hojeISO respeita a virada do dia (§2.4)', () => {
    // 2026-10-04 01:30 em SP (04:30Z) → dia de trabalho 2026-10-03
    expect(hojeISO('America/Sao_Paulo', '05:00', new Date('2026-10-04T04:30:00Z'))).toBe('2026-10-03')
    // 05:00 em SP (08:00Z) → 2026-10-04
    expect(hojeISO('America/Sao_Paulo', '05:00', new Date('2026-10-04T08:00:00Z'))).toBe('2026-10-04')
    expect(hojeISO('America/Sao_Paulo', '00:00', new Date('2026-10-04T04:30:00Z'))).toBe('2026-10-04')
  })
  it('somarDias atravessa mês e ano', () => {
    expect(somarDias('2026-10-06', 1)).toBe('2026-10-07')
    expect(somarDias('2026-10-01', -1)).toBe('2026-09-30')
    expect(somarDias('2026-12-31', 1)).toBe('2027-01-01')
    expect(somarDias('2028-02-28', 1)).toBe('2028-02-29')
  })
})

it('normalizar remove acentos e caixa', () => {
  expect(normalizar('  Ação É Ótima ')).toBe('acao e otima')
})
