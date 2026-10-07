import { describe, expect, it } from 'vitest'
import { descreverDias, descreverFaixasHorario, expandirFaixa, liberado, rotuloFim, validarFaixas } from './horariosAcesso'

describe('horários de acesso', () => {
  it('descreve dias', () => {
    expect(descreverDias([0, 1, 2, 3, 4, 5, 6])).toBe('Todos os dias')
    expect(descreverDias([2, 3, 4, 5, 6, 0])).toBe('Ter–Dom')
    expect(descreverDias([1, 3])).toBe('Seg, Qua')
    expect(descreverDias([1, 2, 5])).toBe('Seg, Ter, Sex')
    expect(descreverDias([])).toBe('—')
  })
  it('descreve faixas agrupando por horário', () => {
    expect(
      descreverFaixasHorario([
        { dia_semana: 1, inicio: '10:00:00', fim: '12:00:00' },
        { dia_semana: 2, inicio: '16:30:00', fim: '23:59:59' },
        { dia_semana: 3, inicio: '16:30:00', fim: '23:59:59' },
        { dia_semana: 4, inicio: '16:30:00', fim: '23:59:59' },
      ]),
    ).toBe('Seg 10:00–12:00 · Ter–Qui 16:30–24:00')
    expect(descreverFaixasHorario([])).toMatch(/Sem faixas/)
    expect(rotuloFim('23:59:59')).toBe('24:00')
  })
  it('expande faixa que cruza a meia-noite', () => {
    expect(expandirFaixa(6, '18:00', '02:00')).toEqual([
      { dia_semana: 6, inicio: '18:00:00', fim: '23:59:59' },
      { dia_semana: 0, inicio: '00:00:00', fim: '02:00:00' },
    ])
    expect(expandirFaixa(1, '08:00', '12:00')).toEqual([{ dia_semana: 1, inicio: '08:00:00', fim: '12:00:00' }])
    expect(expandirFaixa(1, '18:00', '00:00')).toEqual([{ dia_semana: 1, inicio: '18:00:00', fim: '23:59:59' }])
  })
  it('valida', () => {
    expect(validarFaixas([{ dia_semana: 1, inicio: '08:00:00', fim: '12:00:00' }])).toBeNull()
    expect(validarFaixas([{ dia_semana: 1, inicio: '12:00:00', fim: '08:00:00' }])).toMatch(/termina antes/)
    expect(
      validarFaixas([
        { dia_semana: 1, inicio: '08:00:00', fim: '12:00:00' },
        { dia_semana: 1, inicio: '11:00:00', fim: '13:00:00' },
      ]),
    ).toBe('Faixas sobrepostas em Seg')
    expect(
      validarFaixas([
        { dia_semana: 1, inicio: '08:00:00', fim: '12:00:00' },
        { dia_semana: 1, inicio: '12:00:00', fim: '13:00:00' },
      ]),
    ).toBeNull()
  })
  it('liberado', () => {
    const f = expandirFaixa(6, '18:00', '02:00')
    expect(liberado(f, 6, '23:30')).toBe(true)
    expect(liberado(f, 0, '01:59')).toBe(true)
    expect(liberado(f, 0, '02:01')).toBe(false)
    expect(liberado(f, 6, '17:59')).toBe(false)
  })
})
