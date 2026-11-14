import { describe, expect, it } from 'vitest'
import {
  calcularComissao,
  csvComissao,
  datasDoPeriodo,
  diasDoPeriodo,
  numeroCsv,
  tituloPadraoFechamento,
  validarPeriodoFechamento,
  type EntradaComissao,
  type ParticipanteComissao,
} from './comissao'

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

// ------------------------------------------------------------ adendo E.3 — rateio diário (vetores V1–V6)
const ANA = 'a0000000-0000-4000-8000-000000000301'
const BRUNO = 'a0000000-0000-4000-8000-000000000302'
const CARLA = 'a0000000-0000-4000-8000-000000000303'
const MARCOS = 'b0000000-0000-4000-8000-000000000401'
const DIAS3 = ['2026-09-01', '2026-09-02', '2026-09-03']

/** Funcionário com pontos vigentes fixos e presença nos dias dados. */
const F = (nome: string, pontos: number, id: string, presentes: string[]): ParticipanteComissao => ({
  tipo: 'funcionario',
  funcionarioId: id,
  nome,
  pontos,
  incluido: true,
  diasTrabalhados: presentes.length,
  entrada: DIAS3.map((data) => ({ data, presente: presentes.includes(data), pontos })),
})
/** Extra com lançamentos {data: pontos}. */
const X = (nome: string, id: string, lancamentos: Record<string, number>): ParticipanteComissao => ({
  tipo: 'extra',
  funcionarioId: null,
  extraId: id,
  nome,
  pontos: 0,
  incluido: true,
  diasTrabalhados: Object.keys(lancamentos).length,
  entrada: Object.entries(lancamentos).map(([data, pontos]) => ({ data, presente: true, pontos })),
})

const V1 = (ajuste: number, servico = [100_000, 50_001, 30_000], pct = 20): EntradaComissao => ({
  modoRateio: 'diario',
  servicoZigCentavos: 0,
  servicoAjusteCentavos: ajuste,
  percentualRetencao: pct,
  proporcionalDias: false,
  dataInicio: '2026-09-01',
  dataFim: '2026-09-03',
  servicoDias: DIAS3.map((data, k) => ({ data, servicoZigCentavos: servico[k]! })),
  participantes: [
    F('Ana Souza', 10, ANA, ['2026-09-01', '2026-09-02']),
    F('Bruno Lima', 10, BRUNO, ['2026-09-01']),
    F('Carla Dias', 6, CARLA, ['2026-09-01', '2026-09-02']),
    X('Marcos Freitas', MARCOS, { '2026-09-01': 5, '2026-09-02': 7.5 }),
  ],
})

const valoresDia = (r: ReturnType<typeof calcularComissao>, k: number) =>
  Object.fromEntries(r.dias[k]!.rateio.map((x) => [r.itens[x.indice]!.nome.split(' ')[0], x.valorCentavos]))

describe('calcularComissao — rateio diário (adendo E.3.3)', () => {
  it('V1: 3 dias, extra e fallback', () => {
    const r = calcularComissao(V1(0))
    expect(r.dias.map((d) => [d.servicoBrutoCentavos, d.retencaoCentavos, d.baseCentavos])).toEqual([
      [100_000, 20_000, 80_000],
      [50_001, 10_000, 40_001],
      [30_000, 6_000, 24_000],
    ])
    expect(valoresDia(r, 0)).toEqual({ Ana: 25_807, Bruno: 25_806, Carla: 15_484, Marcos: 12_903 })
    expect(valoresDia(r, 1)).toEqual({ Ana: 17_022, Carla: 10_213, Marcos: 12_766 })
    expect(valoresDia(r, 2)).toEqual({ Ana: 9_231, Bruno: 9_231, Carla: 5_538 })
    expect(r.dias.map((d) => d.somaPontos)).toEqual([31, 23.5, 26])
    expect(r.dias.map((d) => d.semPresenca)).toEqual([false, false, true])
    expect(r.dias[2]!.rateio.every((x) => x.fallback)).toBe(true)
    expect(valores(r)).toEqual({ 'Ana Souza': 52_060, 'Bruno Lima': 35_037, 'Carla Dias': 31_235, 'Marcos Freitas': 25_669 })
    expect(r.baseCentavos).toBe(144_001)
    expect(r.totalDistribuidoCentavos).toBe(144_001)
    expect(r.retencaoCentavos).toBe(36_000)
    expect(r.servicoZigCentavos).toBe(180_001)
    expect(r.diasSemPresenca).toBe(1)
    expect(r.diasSemParticipantes).toBe(0)
    const marcos = r.itens.find((i) => i.nome === 'Marcos Freitas')!
    expect(marcos.pontosEfetivos).toBe(12.5)
    expect(r.itens.find((i) => i.nome === 'Ana Souza')!.pontosEfetivos).toBe(30)
    expect(r.somaPontosEfetivos).toBe(80.5)
    expect(r.valorPontoCentavos).toBe(1_788.832298)
    // Carla (fração 0,871) e Ana (empata com Bruno, ganha pelo nome) levam o centavo no 01/09
    expect(r.dias[0]!.rateio.filter((x) => x.centavoExtra).map((x) => r.itens[x.indice]!.nome)).toEqual(['Ana Souza', 'Carla Dias'])
  })

  it('V2: ajuste +1000 repartido pelo serviço do dia', () => {
    const r = calcularComissao(V1(1_000))
    expect(r.dias.map((d) => d.ajusteCentavos)).toEqual([555, 278, 167])
    expect(r.dias.map((d) => d.baseCentavos)).toEqual([80_444, 40_223, 24_134])
    expect(r.dias.map((d) => d.retencaoCentavos)).toEqual([20_111, 10_056, 6_033])
    expect(valoresDia(r, 0)).toEqual({ Ana: 25_950, Bruno: 25_949, Carla: 15_570, Marcos: 12_975 })
    expect(valoresDia(r, 1)).toEqual({ Ana: 17_116, Carla: 10_270, Marcos: 12_837 })
    expect(valoresDia(r, 2)).toEqual({ Ana: 9_282, Bruno: 9_282, Carla: 5_570 })
    expect(valores(r)).toEqual({ 'Ana Souza': 52_348, 'Bruno Lima': 35_231, 'Carla Dias': 31_410, 'Marcos Freitas': 25_812 })
    expect(r.totalDistribuidoCentavos).toBe(144_801)
    expect(r.retencaoCentavos).toBe(36_200)
  })

  it('V3: ajuste −500', () => {
    const r = calcularComissao(V1(-500))
    expect(r.dias.map((d) => d.ajusteCentavos)).toEqual([-278, -139, -83])
    expect(r.dias.map((d) => d.servicoBrutoCentavos)).toEqual([99_722, 49_862, 29_917])
    expect(r.dias.map((d) => d.retencaoCentavos)).toEqual([19_944, 9_972, 5_983])
    expect(r.dias.map((d) => d.baseCentavos)).toEqual([79_778, 39_890, 23_934])
    expect(valores(r)).toEqual({ 'Ana Souza': 51_915, 'Bruno Lima': 34_940, 'Carla Dias': 31_149, 'Marcos Freitas': 25_598 })
    expect(r.totalDistribuidoCentavos).toBe(143_602)
  })

  it('V4: sem serviço, ajuste +100, retenção 0% (peso igual, sobra para o 1º dia)', () => {
    const r = calcularComissao(V1(100, [0, 0, 0], 0))
    expect(r.dias.map((d) => d.ajusteCentavos)).toEqual([34, 33, 33])
    expect(valoresDia(r, 0)).toEqual({ Ana: 11, Bruno: 11, Carla: 7, Marcos: 5 })
    expect(valoresDia(r, 1)).toEqual({ Ana: 14, Carla: 8, Marcos: 11 })
    expect(valoresDia(r, 2)).toEqual({ Ana: 13, Bruno: 13, Carla: 7 })
    expect(valores(r)).toEqual({ 'Ana Souza': 38, 'Bruno Lima': 24, 'Carla Dias': 22, 'Marcos Freitas': 16 })
  })

  it('V5: ajuste ≤ −serviço → tudo zero (presentes gravados com valor 0, sem fallback)', () => {
    const r = calcularComissao(V1(-180_501))
    expect(r.dias.every((d) => d.servicoBrutoCentavos === 0 && d.baseCentavos === 0)).toBe(true)
    expect(r.itens.every((i) => i.valorCentavos === 0)).toBe(true)
    expect(r.dias.map((d) => d.participantes)).toEqual([4, 3, 0])
    expect(r.diasSemPresenca).toBe(0)
    expect(r.diasSemParticipantes).toBe(0)
  })

  it('V6: modo período + extra (3 lançamentos de 5 pontos em 30 dias → pe 0,5)', () => {
    const marcos: ParticipanteComissao = {
      ...X('Marcos Freitas', MARCOS, { '2026-09-05': 5, '2026-09-12': 5, '2026-09-19': 5 }),
      pontos: 5,
    }
    const r = calcularComissao({ ...BASE, modoRateio: 'periodo', proporcionalDias: false, participantes: [...EQUIPE, marcos] })
    expect(r.itens.find((i) => i.nome === 'Marcos Freitas')!.pontosEfetivos).toBe(0.5)
    expect(r.somaPontosEfetivos).toBe(38.5)
    expect(valores(r)).toEqual({
      'Ana Souza': 206_753,
      'Bruno Lima': 206_753,
      'Carla Dias': 124_052,
      'Davi Rocha': 165_403,
      'Eva Martins': 82_701,
      'Marcos Freitas': 10_338,
    })
    expect(r.dias).toEqual([])
  })

  it('extra não entra pelo fallback; sem funcionários → dia sem participantes', () => {
    const e = V1(0)
    e.participantes = [X('Marcos Freitas', MARCOS, { '2026-09-01': 5 })]
    const r = calcularComissao(e)
    expect(r.dias.map((d) => [d.semPresenca, d.semParticipantes])).toEqual([
      [false, false],
      [false, true],
      [false, true],
    ])
    expect(r.diasSemParticipantes).toBe(2)
    expect(r.totalDistribuidoCentavos).toBe(80_000)
  })

  it('pontos manuais valem em todos os dias; não incluído fica de fora (inclusive do fallback)', () => {
    const e = V1(0)
    e.participantes = e.participantes.map((p) =>
      p.nome === 'Ana Souza' ? { ...p, pontos: 20, pontosManual: true } : p.nome === 'Bruno Lima' ? { ...p, incluido: false } : p,
    )
    const r = calcularComissao(e)
    expect(r.dias[0]!.somaPontos).toBe(31) // Ana 20 + Carla 6 + Marcos 5
    expect(r.dias[2]!.somaPontos).toBe(26) // fallback: Ana 20 + Carla 6
    expect(r.itens.find((i) => i.nome === 'Bruno Lima')!.valorCentavos).toBe(0)
    expect(r.totalDistribuidoCentavos).toBe(144_001)
  })

  it('pontos vigentes por dia (mudança de pontos no meio do período)', () => {
    const e = V1(0)
    const ana = e.participantes[0]!
    ana.entrada = ana.entrada!.map((l) => (l.data === '2026-09-02' ? { ...l, pontos: 12 } : l))
    const r = calcularComissao(e)
    expect(r.dias[1]!.somaPontos).toBe(25.5)
    expect(r.dias[2]!.somaPontos).toBe(26) // 03/09 volta a 10
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

describe('CSV do fechamento (adendo E.4) — idêntico ao do N8N', () => {
  const r = calcularComissao(V1(0))
  const fechamento = {
    data_inicio: '2026-09-01',
    data_fim: '2026-09-03',
    status: 'fechado' as const,
    modo_rateio: 'diario' as const,
    servico_zig_centavos: r.servicoZigCentavos,
    servico_ajuste_centavos: r.servicoAjusteCentavos,
    servico_bruto_centavos: r.servicoBrutoCentavos,
    percentual_retencao: 20,
    retencao_centavos: r.retencaoCentavos,
    base_distribuivel_centavos: r.baseCentavos,
    valor_ponto_centavos: r.valorPontoCentavos,
    dias_sem_presenca: r.diasSemPresenca,
  }
  const itens = [
    ...r.itens.map((i) => ({
      funcionario_nome: i.nome,
      tipo: i.tipo ?? 'funcionario',
      cargo: i.cargo ?? null,
      incluido: i.incluido,
      pontos: i.tipo === 'extra' ? 6.25 : i.pontos,
      dias_presentes: i.diasTrabalhados,
      valor_centavos: i.valorCentavos,
    })),
    { funcionario_nome: 'Zé; "Fora"', tipo: 'funcionario' as const, cargo: null, incluido: false, pontos: 2.5, dias_presentes: 3, valor_centavos: 0 },
  ]

  const n8n = async () => {
    const caminho = new URL('../../../n8n/comum/lib/csv.mjs', import.meta.url).href
    return (await import(/* @vite-ignore */ caminho)) as { csvComissao(d: unknown): { nome: string; conteudo: string } }
  }

  it('bate byte a byte com csvComissao (n8n/comum/lib/csv.mjs) — diário e período', async () => {
    const m = await n8n()
    for (const f of [fechamento, { ...fechamento, modo_rateio: 'periodo' as const, status: 'rascunho' as const, valor_ponto_centavos: null }]) {
      const esperado = m.csvComissao({ fechamento: { ...f, empresa_nome: 'Bar Bossa Nova' }, itens })
      const nosso = csvComissao(f, itens, 'Bar Bossa Nova')
      expect(nosso.nome).toBe(esperado.nome)
      expect(nosso.conteudo).toBe(esperado.conteudo)
    }
  })

  it('conteúdo esperado (modo diário)', () => {
    const { nome, conteudo } = csvComissao(fechamento, itens, 'Bar Bossa Nova')
    expect(nome).toBe('comissao_bar-bossa-nova_2026-09-01_2026-09-03.csv')
    const linhas = conteudo.replace(/^\uFEFF/, '').split('\r\n')
    expect(linhas.slice(0, 12)).toEqual([
      'Período;01/09/2026 a 03/09/2026',
      'Modo de rateio;Diário',
      'Serviço Zig (R$);1800,01',
      'Ajuste (R$);0,00',
      'Serviço bruto (R$);1800,01',
      'Retenção (%);20',
      'Retenção (R$);360,00',
      'Base distribuível (R$);1440,01',
      'Valor do ponto (R$);17,89',
      'Status;Fechado',
      'Dias sem presença registrada;1',
      '',
    ])
    expect(linhas[12]).toBe('Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)')
    expect(linhas[13]).toBe('Ana Souza;Funcionário;;Sim;10;2;520,60')
    expect(linhas[16]).toBe('Marcos Freitas;Extra;;Sim;6,25;2;256,69')
    expect(linhas[17]).toBe('"Zé; ""Fora""";Funcionário;;Não;2,5;3;0,00')
    expect(linhas[18]).toBe('Total;;;;32,25;7;1440,01')
    expect(linhas[19]).toBe('')
  })

  it('modo período: sem a linha de dias sem presença', () => {
    const linhas = csvComissao({ ...fechamento, modo_rateio: 'periodo' }, itens, 'Bar').conteudo.split('\r\n')
    expect(linhas[1]).toBe('Modo de rateio;Por período')
    expect(linhas[10]).toBe('')
    expect(linhas[11]).toBe('Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)')
  })

  it('numeroCsv', () => {
    expect(numeroCsv(10)).toBe('10')
    expect(numeroCsv(2.5, 2)).toBe('2,5')
    expect(numeroCsv(7.333333)).toBe('7,333333')
    expect(numeroCsv(null)).toBe('')
    expect(numeroCsv(-0.0000001)).toBe('0')
  })
})

describe('datasDoPeriodo', () => {
  it('inclusivo e atravessa mês', () => {
    expect(datasDoPeriodo('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'])
  })
})

// Revisão 1: mesmo vetor de supabase/testes/56_comissao_desempate.sql (o banco usa collate "C" no desempate por nome).
describe('calcularComissao — desempate igual ao banco', () => {
  const base = { servicoZigCentavos: 0, servicoAjusteCentavos: 100, percentualRetencao: 0, proporcionalDias: false, dataInicio: '2026-09-01', dataFim: '2026-09-30' }
  it('desempate por nome em ordem de código de caractere (B < a < Á), não alfabética', () => {
    const r = calcularComissao({
      ...base,
      participantes: [
        P('ana', '', 1, 'e5600000-0000-4000-8000-000000000302'),
        P('Ágata', '', 1, 'e5600000-0000-4000-8000-000000000303'),
        P('Bruno', '', 1, 'e5600000-0000-4000-8000-000000000301'),
      ],
    })
    expect(valores(r)).toEqual({ Bruno: 34, ana: 33, 'Ágata': 33 })
  })
  it('nomes iguais: menor funcionario_id leva o centavo; snapshot sem id (null) fica por último', () => {
    const r = calcularComissao({
      ...base,
      participantes: [
        { ...P('Mesmo Nome', '', 1, 'x'), funcionarioId: null },
        P('Mesmo Nome', '', 1, 'e5600000-0000-4000-8000-000000000303'),
        P('Mesmo Nome', '', 1, 'e5600000-0000-4000-8000-000000000302'),
      ],
    })
    expect(r.itens.map((i) => [i.funcionarioId, i.valorCentavos])).toEqual([
      [null, 33],
      ['e5600000-0000-4000-8000-000000000303', 33],
      ['e5600000-0000-4000-8000-000000000302', 34],
    ])
  })
})

// ------------------------------------------------------------- adendo extras v3 (§E.7.8): presença, faltas, pendentes
describe('calcularComissao — presença v3 (vetores V7, V7b, V8, V8b)', () => {
  type L = NonNullable<ParticipanteComissao['entrada']>[number]
  const DIAS = ['2026-09-01', '2026-09-02', '2026-09-03', '2026-09-04']
  const ponto = (pontos: number): Partial<L> => ({ presente: true, origem: 'ponto', pontos })
  const escala = (pontos: number): Partial<L> => ({ presente: true, origem: 'escala', pontos })
  const bloq = (motivo: L['motivo']): Partial<L> => ({ presente: false, bloqueado: true, motivo })
  const fb = (): Partial<L> => ({ presente: false, fallback: true, motivo: 'sem_registro' })
  const nada = (motivo: L['motivo']): Partial<L> => ({ presente: false, motivo })
  const func = (nome: string, n: number, pontos: number, dias: Partial<L>[]): ParticipanteComissao => ({
    itemId: `b0000000-0000-4000-8000-00000000000${n}`,
    tipo: 'funcionario',
    funcionarioId: `a0000000-0000-4000-8000-00000000030${n}`,
    nome,
    incluido: true,
    pontos,
    pontosManual: false,
    diasTrabalhados: 0,
    entrada: dias.map((d, k) => ({ data: DIAS[k]!, presente: false, fallback: false, bloqueado: false, motivo: null, origem: null, pontos, ...d })),
  })
  const extra = (nome: string, n: number, pontos: number, pendente: boolean): ParticipanteComissao => ({
    itemId: `b0000000-0000-4000-8000-00000000001${n}`,
    tipo: 'extra',
    funcionarioId: null,
    extraId: `c0000000-0000-4000-8000-00000000000${n}`,
    nome,
    incluido: true,
    pontos,
    diasTrabalhados: 1,
    entrada: [{ data: '2026-09-03', presente: true, pontos: pendente ? 0 : pontos, pendente }],
  })
  const equipe = (zePontos: number | null): ParticipanteComissao[] => [
    func('Ana Souza', 1, 10, [ponto(10), escala(10), bloq('ferias'), escala(10)]),
    func('Bruno Lima', 2, 10, [ponto(10), nada('folga_escala'), escala(10), escala(10)]),
    func('Carla Dias', 3, 6, [ponto(6), bloq('falta_justificada'), escala(6), bloq('atestado')]),
    func('Davi Rocha', 4, 8, [bloq('falta_injustificada'), bloq('suspensao'), bloq('fora_vinculo'), bloq('fora_vinculo')]),
    func('Eva Martins', 5, 4, [nada('sem_batida'), fb(), fb(), fb()]),
    extra('Marcos Freitas', 1, 5, false),
    extra('Zé Pereira', 2, zePontos ?? 0, zePontos == null),
  ]
  const entrada = (modo: 'diario' | 'periodo', zePontos: number | null, proporcional = false): EntradaComissao => ({
    modoRateio: modo,
    servicoZigCentavos: 200_001,
    servicoAjusteCentavos: 0,
    percentualRetencao: 20,
    proporcionalDias: proporcional,
    dataInicio: '2026-09-01',
    dataFim: '2026-09-04',
    servicoDias: [100_000, 50_000, 30_000, 20_001].map((v, k) => ({ data: DIAS[k]!, servicoZigCentavos: v })),
    participantes: equipe(zePontos),
  })

  it('V7 — diário: faltas, suspensão, férias, atestado e desligado ficam de fora; escala e fallback individual', () => {
    const r = calcularComissao(entrada('diario', null))
    expect(r.dias.map((d) => d.baseCentavos)).toEqual([80_000, 40_000, 24_000, 16_001])
    expect(r.dias.map((d) => d.rateio.map((x) => [r.itens[x.indice]!.nome.split(' ')[0], x.valorCentavos]))).toEqual([
      [['Ana', 30_769], ['Bruno', 30_769], ['Carla', 18_462]],
      [['Ana', 28_571], ['Eva', 11_429]],
      [['Bruno', 9_600], ['Carla', 5_760], ['Eva', 3_840], ['Marcos', 4_800]],
      [['Ana', 6_667], ['Bruno', 6_667], ['Eva', 2_667]],
    ])
    expect(valores(r)).toEqual({
      'Ana Souza': 66_007,
      'Bruno Lima': 47_036,
      'Carla Dias': 24_222,
      'Davi Rocha': 0,
      'Eva Martins': 17_936,
      'Marcos Freitas': 4_800,
      'Zé Pereira': 0,
    })
    expect(r.totalDistribuidoCentavos).toBe(160_001)
    expect(r.diasSemPresenca).toBe(3)
    expect(r.diasSemParticipantes).toBe(0)
    expect(r.extrasSemPontuacao).toBe(1)
    expect(r.itens.map((i) => i.diasPresentes)).toEqual([3, 3, 2, 0, 0, 1, 1])
    expect(r.itens.find((i) => i.nome === 'Zé Pereira')!.pontosPendente).toBe(true)
    // detalhe: origem e ausentes com motivo
    expect(r.dias[0]!.rateio.map((x) => x.origem)).toEqual(['ponto', 'ponto', 'ponto'])
    expect(r.dias[1]!.rateio.map((x) => [x.origem, x.fallback])).toEqual([['escala', false], ['fallback', true]])
    expect(r.dias[0]!.ausentes.map((a) => [r.itens[a.indice]!.nome, a.motivo])).toEqual([
      ['Davi Rocha', 'falta_injustificada'],
      ['Eva Martins', 'sem_batida'],
    ])
    expect(r.dias[2]!.ausentes.map((a) => a.motivo)).toEqual(['ferias', 'fora_vinculo'])
  })

  it('V7b — Zé com 3 pontos entra em 03/09 e o fechamento é liberado', () => {
    const r = calcularComissao(entrada('diario', 3))
    expect(r.dias[2]!.rateio.map((x) => x.valorCentavos)).toEqual([8_571, 5_143, 3_429, 4_286, 2_571])
    expect(valores(r)).toEqual({
      'Ana Souza': 66_007,
      'Bruno Lima': 46_007,
      'Carla Dias': 23_605,
      'Davi Rocha': 0,
      'Eva Martins': 17_525,
      'Marcos Freitas': 4_286,
      'Zé Pereira': 2_571,
    })
    expect(r.extrasSemPontuacao).toBe(0)
  })

  it('V8 — período proporcional: dias = presente ou fallback; Davi (todos bloqueados) 0', () => {
    const r = calcularComissao(entrada('periodo', 3, true))
    expect(r.baseCentavos).toBe(160_001)
    expect(r.itens.map((i) => i.diasPresentes)).toEqual([3, 3, 2, 0, 3, 1, 1])
    expect(valores(r)).toEqual({
      'Ana Souza': 52_174,
      'Bruno Lima': 52_174,
      'Carla Dias': 20_870,
      'Davi Rocha': 0,
      'Eva Martins': 20_870,
      'Marcos Freitas': 8_696,
      'Zé Pereira': 5_217,
    })
  })

  it('V8b — período não proporcional', () => {
    const r = calcularComissao(entrada('periodo', 3))
    expect(valores(r)).toEqual({
      'Ana Souza': 50_001,
      'Bruno Lima': 50_000,
      'Carla Dias': 30_000,
      'Davi Rocha': 0,
      'Eva Martins': 20_000,
      'Marcos Freitas': 6_250,
      'Zé Pereira': 3_750,
    })
  })

  it('último recurso: sem ninguém, entram os incluídos não bloqueados', () => {
    const e = entrada('diario', 3)
    e.servicoDias = [{ data: '2026-09-02', servicoZigCentavos: 1_000 }]
    // 02/09 sem Ana (tirada) e sem Eva (tirada): sobra Bruno (folga na escala, não bloqueado) pelo último recurso
    e.participantes = e.participantes.map((p) => (p.nome === 'Ana Souza' || p.nome === 'Eva Martins' ? { ...p, incluido: false } : p))
    const r = calcularComissao(e)
    expect(r.dias[1]!.rateio.map((x) => [r.itens[x.indice]!.nome, x.valorCentavos, x.origem])).toEqual([['Bruno Lima', 800, 'ultimo_recurso']])
    expect(r.dias[1]!.semPresenca).toBe(true)
    expect(r.diasSemParticipantes).toBe(0)
  })
})
