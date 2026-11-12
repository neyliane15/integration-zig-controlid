import { describe, expect, it } from 'vitest'
import {
  MODELO_CSV_RESERVAS,
  converterReservas,
  detectarSeparador,
  lerCsv,
  lerDataReserva,
  lerHoraReserva,
  lerPessoas,
  lerStatusReserva,
  reconhecerColunas,
} from './reservasCsv'

describe('leitura do CSV', () => {
  it('detecta ; , e TAB', () => {
    expect(detectarSeparador('a;b;c\n1;2;3')).toBe(';')
    expect(detectarSeparador('a,b,c\n1,2,3')).toBe(',')
    expect(detectarSeparador('a\tb\tc')).toBe('\t')
    expect(detectarSeparador('"x;y",b,c')).toBe(',')
  })

  it('lê aspas, aspas dobradas, BOM, CRLF e quebra dentro de aspas', () => {
    const t = '﻿Nome;Obs\r\n"Silva; Ana";"diz ""oi"""\r\n"Bia";"linha1\nlinha2"\r\n\r\n'
    expect(lerCsv(t)).toEqual([
      ['Nome', 'Obs'],
      ['Silva; Ana', 'diz "oi"'],
      ['Bia', 'linha1\nlinha2'],
    ])
  })

  it('o modelo para baixar é lido de volta sem erros', () => {
    const [cab, ...dados] = lerCsv(MODELO_CSV_RESERVAS)
    const m = reconhecerColunas(cab!)
    expect(Object.values(m).every((v) => v != null)).toBe(true)
    const r = converterReservas(dados, m)
    expect(r.erros).toEqual([])
    expect(r.reservas).toHaveLength(3)
    expect(r.reservas[2]).toMatchObject({ id_externo: 'T-1003', status: 'cancelada', pessoas: 6, data: '2026-11-21', hora: '19:00' })
  })
})

describe('reconhecimento de colunas', () => {
  it('português com e sem acento', () => {
    const m = reconhecerColunas(['Cliente', 'Data', 'Horário', 'Pessoas', 'Situação', 'Celular', 'Mesa', 'Observações'])
    expect(m).toMatchObject({ nome: 0, data: 1, hora: 2, pessoas: 3, status: 4, telefone: 5, mesa: 6, observacao: 7 })
  })

  it('inglês (Tagme/planilhas exportadas)', () => {
    const m = reconhecerColunas(['Reservation ID', 'Name', 'Date', 'Time', 'Party size', 'Status', 'Phone', 'Email', 'Notes'])
    expect(m).toMatchObject({ id_externo: 0, nome: 1, data: 2, hora: 3, pessoas: 4, status: 5, telefone: 6, email: 7, observacao: 8 })
  })

  it('Pax/Guests e cabeçalhos compostos', () => {
    expect(reconhecerColunas(['Nome completo do cliente', 'Pax']).pessoas).toBe(1)
    expect(reconhecerColunas(['Nome completo do cliente', 'Pax']).nome).toBe(0)
    expect(reconhecerColunas(['Guests', 'Guest name']).pessoas).toBe(0)
    expect(reconhecerColunas(['Guests', 'Guest name']).nome).toBe(1)
  })

  it('coluna desconhecida fica sem campo', () => {
    const m = reconhecerColunas(['Coluna X', 'Data'])
    expect(m.nome).toBeNull()
    expect(m.data).toBe(1)
  })
})

describe('conversão de valores', () => {
  it('datas', () => {
    expect(lerDataReserva('20/11/2026')).toBe('2026-11-20')
    expect(lerDataReserva('5/1/26')).toBe('2026-01-05')
    expect(lerDataReserva('2026-11-20')).toBe('2026-11-20')
    expect(lerDataReserva('2026-11-20T20:30:00-03:00')).toBe('2026-11-20')
    expect(lerDataReserva('20/11/2026 20:30')).toBe('2026-11-20')
    expect(lerDataReserva('31/02/2026')).toBeNull()
    expect(lerDataReserva('amanhã')).toBeNull()
  })

  it('horas', () => {
    expect(lerHoraReserva('20:30')).toBe('20:30')
    expect(lerHoraReserva('20:30:00')).toBe('20:30')
    expect(lerHoraReserva('20h30')).toBe('20:30')
    expect(lerHoraReserva('20h')).toBe('20:00')
    expect(lerHoraReserva('8:05 PM')).toBe('20:05')
    expect(lerHoraReserva('20/11/2026 21:15')).toBe('21:15')
    expect(lerHoraReserva('2026-11-20T19:45:00-03:00')).toBe('19:45')
    expect(lerHoraReserva('25:00')).toBeNull()
    expect(lerHoraReserva('tarde')).toBeNull()
  })

  it('pessoas', () => {
    expect(lerPessoas('4')).toBe(4)
    expect(lerPessoas('4 pessoas')).toBe(4)
    expect(lerPessoas('2+1')).toBe(3)
    expect(lerPessoas('')).toBeNull()
    expect(lerPessoas('muitas')).toBeNaN()
  })

  it('status', () => {
    expect(lerStatusReserva('Confirmada')).toBe('confirmada')
    expect(lerStatusReserva('CANCELADA pelo cliente')).toBe('cancelada')
    expect(lerStatusReserva('Canceled')).toBe('cancelada')
    expect(lerStatusReserva('No-show')).toBe('nao_compareceu')
    expect(lerStatusReserva('Sentado')).toBe('sentada')
    expect(lerStatusReserva('Seated')).toBe('sentada')
    expect(lerStatusReserva('Finalizada')).toBe('concluida')
    expect(lerStatusReserva('Aguardando confirmação')).toBe('pendente')
    expect(lerStatusReserva('')).toBe('confirmada')
    expect(lerStatusReserva('???')).toBe('confirmada')
  })

  it('linhas com erro são listadas com o número da linha do arquivo', () => {
    const [cab, ...dados] = lerCsv('Nome,Data,Hora,Pax\nAna,20/11/2026,20:00,4\n,20/11/2026,20:00,2\nBia,30/02/2026,,2\nCaio,2026-11-21,25h,2\nDu,21/11/2026,,zero\nEd,21/11/2026 19:30,,')
    const r = converterReservas(dados, reconhecerColunas(cab!))
    expect(r.reservas.map((x) => [x.nome, x.hora, x.pessoas])).toEqual([
      ['Ana', '20:00', 4],
      ['Ed', '19:30', 2],
    ])
    expect(r.erros.map((e) => e.linha)).toEqual([3, 4, 5, 6])
  })
})
