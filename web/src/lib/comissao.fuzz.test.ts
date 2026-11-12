/**
 * Revisão 2 — testes de propriedade (fuzz) da comissão (contrato §9).
 *
 * 1. Sempre: 3.000 casos aleatórios (semente fixa) comparando `calcularComissao` com uma implementação de referência
 *    INDEPENDENTE (frações comparadas por produto cruzado em BigInt, sem div/mod) e conferindo as invariantes:
 *    Σ valores = base, cada valor = piso ou piso + 1, retenção = round(bruto × % / 100), quem não participa recebe 0.
 * 2. Opt-in (`MDG_FUZZ_BANCO=1`, Postgres de `supabase/testes/preparar-postgres.sh` e um banco com as migrações, ex.:
 *    `MDG_PG_BANCO=mdg_local`): 200 casos aleatórios calculados pela função do banco (`comissao_calcular`, dentro de uma
 *    transação desfeita no fim) têm de dar EXATAMENTE os mesmos centavos que a prévia do front.
 */
import { spawnSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'
import { calcularComissao, type EntradaComissao, type ParticipanteComissao } from './comissao'

/** PRNG determinístico (mulberry32). */
function gerador(semente: number) {
  let a = semente >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const NOMES = ['Ana', 'ana', 'Ágata', 'Bruno', 'Bruno', 'Zé', 'Érica', 'carla', 'Davi', 'Eva', 'Ana Souza', 'Ana souza']
const PONTOS = (inteiro: (a: number, b: number) => number) => [1, 2, 3, 0.5, 0.01, 10, 7.77, 0, 9999.99, inteiro(0, 5000) / 100]

const dataDe = (dia: number) => `2026-09-${String(dia).padStart(2, '0')}`

/** Caso aleatório (funcionários + extras) para os dois modos. */
function caso(rnd: () => number, i: number, modo: 'diario' | 'periodo' | 'qualquer' = 'qualquer'): EntradaComissao {
  const inteiro = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1))
  const escolha = <T,>(xs: T[]) => xs[inteiro(0, xs.length - 1)]!
  const diario = modo === 'diario' || (modo === 'qualquer' && rnd() < 0.6)
  const n = inteiro(1, 8)
  const dias = diario ? inteiro(1, 10) : inteiro(1, 30)
  const datas = Array.from({ length: dias }, (_, k) => dataDe(k + 1))
  const participantes: ParticipanteComissao[] = []
  for (let k = 0; k < n; k++) {
    const extra = rnd() < 0.3
    const id = `f${String(i).padStart(7, '0')}-0000-4000-8000-${String(k).padStart(12, '0')}`
    if (extra) {
      const entrada = datas.filter(() => rnd() < 0.4).map((data) => ({ data, presente: true, pontos: escolha(PONTOS(inteiro)) }))
      participantes.push({ tipo: 'extra', funcionarioId: null, extraId: id, nome: escolha(NOMES), incluido: rnd() > 0.1, pontos: 0, diasTrabalhados: entrada.length, entrada })
    } else {
      const snapshot = rnd() < 0.1
      const pontos = escolha(PONTOS(inteiro))
      const muda = rnd() < 0.2 // pontos vigentes mudam no meio do período
      const entrada = snapshot ? [] : datas.map((data, d) => ({ data, presente: rnd() < 0.6, pontos: muda && d >= dias / 2 ? escolha(PONTOS(inteiro)) : pontos }))
      participantes.push({
        tipo: 'funcionario',
        funcionarioId: snapshot ? null : id,
        nome: escolha(NOMES),
        incluido: rnd() > 0.1,
        pontos,
        pontosManual: !snapshot && rnd() < 0.2,
        diasTrabalhados: snapshot ? inteiro(0, dias) : entrada.filter((l) => l.presente).length,
        entrada,
      })
    }
  }
  const escalaBase = [0, 1, 7, 99, 100, 12345, 995000, 99999999][inteiro(0, 7)]!
  const servicoDias = datas.map((data) => ({ data, servicoZigCentavos: rnd() < 0.2 ? 0 : inteiro(0, escalaBase) }))
  const zig = servicoDias.reduce((t, d) => t + d.servicoZigCentavos, 0)
  return {
    modoRateio: diario ? 'diario' : 'periodo',
    servicoZigCentavos: zig,
    servicoAjusteCentavos: rnd() < 0.3 ? -inteiro(0, zig + 10) || 0 : rnd() < 0.5 ? inteiro(0, 5000) : 0,
    percentualRetencao: [0, 20, 12.5, 13.37, 33.33, 50, 100, inteiro(0, 10000) / 100][inteiro(0, 7)]!,
    proporcionalDias: !diario && rnd() < 0.3,
    dataInicio: '2026-09-01',
    dataFim: datas[datas.length - 1]!,
    servicoDias,
    participantes,
  }
}

// ------------------------------------------------------------------ referência independente
const arred = (n: bigint, d: bigint) => {
  const q = n / d
  return (n % d) * 2n >= d ? q + 1n : q
}
const centesimos = (v: number) => BigInt(Math.round(v * 100))
const idDe = (p: ParticipanteComissao) => (p.tipo === 'extra' ? p.extraId : p.funcionarioId) ?? null

/** ordem: fração desc (produto cruzado), peso desc, nome (código), tipo, id nulos por último */
function distribuir(total: bigint, pesos: bigint[], ps: ParticipanteComissao[]): bigint[] {
  const soma = pesos.reduce((s, v) => s + v, 0n)
  const pisos = pesos.map((x) => (total * x) / soma)
  let resto = total - pisos.reduce((s, v) => s + v, 0n)
  const idx = pesos.map((_, i) => i)
  idx.sort((a, b) => {
    const fa = total * pesos[a]! - pisos[a]! * soma
    const fb = total * pesos[b]! - pisos[b]! * soma
    if (fa !== fb) return fa > fb ? -1 : 1
    if (pesos[a] !== pesos[b]) return pesos[a]! > pesos[b]! ? -1 : 1
    const na = ps[a]!.nome
    const nb = ps[b]!.nome
    if (na !== nb) return na < nb ? -1 : 1
    const ta = ps[a]!.tipo === 'extra' ? 1 : 0
    const tb = ps[b]!.tipo === 'extra' ? 1 : 0
    if (ta !== tb) return ta - tb
    const ia = idDe(ps[a]!) ?? '￿'
    const ib = idDe(ps[b]!) ?? '￿'
    return ia < ib ? -1 : ia > ib ? 1 : 0
  })
  const valores = [...pisos]
  for (const i of idx) {
    if (resto <= 0n) break
    valores[i] = valores[i]! + 1n
    resto -= 1n
  }
  return valores
}

function referenciaPeriodo(e: EntradaComissao) {
  const s = BigInt(e.servicoZigCentavos) + BigInt(e.servicoAjusteCentavos)
  const bruto = s > 0n ? s : 0n
  const retencao = arred(bruto * centesimos(e.percentualRetencao), 10_000n)
  const base = bruto - retencao
  const diasPeriodo = BigInt(Number(e.dataFim.slice(8, 10)))
  const pe = e.participantes.map((p) => {
    if (!p.incluido) return 0n
    if (p.tipo === 'extra') return arred((p.entrada ?? []).reduce((t, l) => t + centesimos(l.pontos) * 10_000n, 0n), diasPeriodo)
    const p6 = centesimos(p.pontos) * 10_000n
    return e.proporcionalDias ? arred(p6 * BigInt(p.diasTrabalhados), diasPeriodo) : p6
  })
  const ativos = pe.map((_, i) => i).filter((i) => pe[i]! > 0n)
  const valores = pe.map(() => 0n)
  if (ativos.length) {
    const v = distribuir(base, ativos.map((i) => pe[i]!), ativos.map((i) => e.participantes[i]!))
    ativos.forEach((i, k) => (valores[i] = v[k]!))
  }
  return { retencao, base, valores }
}

function referenciaDiario(e: EntradaComissao) {
  const datas = e.servicoDias!.map((d) => d.data)
  const sd = e.servicoDias!.map((d) => BigInt(d.servicoZigCentavos))
  const A = BigInt(e.servicoAjusteCentavos)
  const absA = A < 0n ? -A : A
  const somaS = sd.reduce((t, v) => t + v, 0n)
  const w = somaS === 0n ? sd.map(() => 1n) : sd
  const sw = w.reduce((t, v) => t + v, 0n)
  // parte do ajuste por dia: maior resto com desempate por data (índice)
  const pisos = w.map((x) => (absA * x) / sw)
  let sobra = absA - pisos.reduce((t, v) => t + v, 0n)
  const ordem = w.map((_, k) => k).sort((a, b) => {
    const ra = (absA * w[a]!) % sw
    const rb = (absA * w[b]!) % sw
    return ra !== rb ? (ra > rb ? -1 : 1) : a - b
  })
  const partes = [...pisos]
  for (const k of ordem) {
    if (sobra <= 0n) break
    partes[k] = partes[k]! + 1n
    sobra -= 1n
  }
  let retencao = 0n
  let base = 0n
  const valores = e.participantes.map(() => 0n)
  datas.forEach((data, k) => {
    const soma = sd[k]! + (A < 0n ? -partes[k]! : partes[k]!)
    const bruto = soma > 0n ? soma : 0n
    const ret = arred(bruto * centesimos(e.percentualRetencao), 10_000n)
    retencao += ret
    base += bruto - ret
    const pontosDia = (p: ParticipanteComissao, fallback: boolean): bigint => {
      if (!p.incluido) return 0n
      const l = (p.entrada ?? []).find((x) => x.data === data)
      if (p.tipo === 'extra') return !fallback && l ? centesimos(l.pontos) : 0n
      if (!fallback && !l?.presente) return 0n
      return p.pontosManual || p.funcionarioId == null ? centesimos(p.pontos) : centesimos(l?.pontos ?? 0)
    }
    let pesos = e.participantes.map((p) => pontosDia(p, false))
    if (pesos.every((x) => x === 0n) && bruto - ret > 0n) pesos = e.participantes.map((p) => pontosDia(p, true))
    const ativos = pesos.map((_, i) => i).filter((i) => pesos[i]! > 0n)
    if (!ativos.length) return
    const v = distribuir(bruto - ret, ativos.map((i) => pesos[i]!), ativos.map((i) => e.participantes[i]!))
    ativos.forEach((i, j) => (valores[i] = valores[i]! + v[j]!))
  })
  return { retencao, base, valores }
}

const referencia = (e: EntradaComissao) => (e.modoRateio === 'diario' ? referenciaDiario(e) : referenciaPeriodo(e))

describe('comissão — propriedades (fuzz, 3.000 casos, modos diário e período)', () => {
  it('prévia do front = referência independente; Σ = base (sem dias sem participantes); cada valor ≥ 0', () => {
    const rnd = gerador(20261007)
    for (let i = 0; i < 3000; i++) {
      const e = caso(rnd, i)
      const r = calcularComissao(e)
      const ref = referencia(e)
      const contexto = JSON.stringify(e)
      expect(r.retencaoCentavos, contexto).toBe(Number(ref.retencao))
      expect(r.baseCentavos, contexto).toBe(Number(ref.base))
      expect(r.itens.map((x) => x.valorCentavos), contexto).toEqual(ref.valores.map(Number))
      if (!r.semParticipantes && r.diasSemParticipantes === 0) expect(r.totalDistribuidoCentavos, contexto).toBe(r.baseCentavos)
      if (e.modoRateio === 'diario') {
        expect(r.dias.reduce((t, d) => t + d.ajusteCentavos, 0), contexto).toBe(e.servicoAjusteCentavos)
        for (const d of r.dias) if (d.participantes > 0) expect(d.rateio.reduce((t, x) => t + x.valorCentavos, 0), contexto).toBe(d.baseCentavos)
      }
      r.itens.forEach((x, k) => {
        if (!e.participantes[k]!.incluido) expect(x.valorCentavos, contexto).toBe(0)
        expect(x.valorCentavos, contexto).toBeGreaterThanOrEqual(0)
      })
    }
  })

  it('no mesmo dia, mais pontos nunca recebe menos', () => {
    const rnd = gerador(7)
    for (let i = 0; i < 500; i++) {
      const r = calcularComissao(caso(rnd, i, 'diario'))
      for (const d of r.dias)
        for (const a of d.rateio) for (const b of d.rateio) if (a.pontos > b.pontos) expect(a.valorCentavos).toBeGreaterThanOrEqual(b.valorCentavos)
    }
  })

  it('extra só recebe nos dias em que foi lançado', () => {
    const rnd = gerador(99)
    for (let i = 0; i < 500; i++) {
      const e = caso(rnd, i, 'diario')
      const r = calcularComissao(e)
      for (const d of r.dias)
        for (const x of d.rateio) {
          const p = e.participantes[x.indice]!
          if (p.tipo === 'extra') {
            expect(x.fallback).toBe(false)
            expect(p.entrada!.some((l) => l.data === d.data)).toBe(true)
          }
        }
    }
  })
})

// --------------------------------------------------------------- front × banco (opt-in)
const BANCO_ATIVO = process.env.MDG_FUZZ_BANCO === '1'
const sqlTexto = (s: string) => `'${s.replace(/'/g, "''")}'`

describe.skipIf(!BANCO_ATIVO)('comissão — front × banco (fuzz, 200 casos; MDG_FUZZ_BANCO=1)', () => {
  it('comissao_calcular dá os mesmos centavos que calcularComissao', { timeout: 120_000 }, () => {
    const rnd = gerador(Number(process.env.MDG_FUZZ_SEMENTE ?? 424242))
    const casos: EntradaComissao[] = []
    for (let i = 0; i < 200; i++) {
      const e = caso(rnd, i)
      // Banco: dias trabalhados só são guardados (snapshot) para item sem funcionário; no proporcional usa snapshots
      // com nomes únicos (sem id, o desempate final do banco é o id interno do item — não reproduzível no front).
      // colunas numeric(18,6) do banco: valor do ponto até 10¹² centavos — limita o serviço a R$ 1 milhão (realista)
      e.servicoZigCentavos %= 100_000_000
      e.servicoAjusteCentavos %= 100_000_000
      if (e.proporcionalDias) e.participantes.forEach((p) => Object.assign(p, { funcionarioId: null }))
      e.participantes.forEach((p, k) => {
        if (p.funcionarioId == null) p.nome = `${p.nome} #${k}`
      })
      casos.push(e)
    }
    // uma empresa por caso: os pontos extras entram em qualquer fechamento da empresa que cubra a data (adendo E.1)
    const empresaDe = (i: number) => `e99${String(i).padStart(5, '0')}-0000-4000-8000-00000000eeee`
    let sql = `begin;\nset local client_min_messages = warning;\n`
    casos.forEach((e, i) => {
      const empresa = empresaDe(i)
      sql += `insert into public.empresas (id, nome) values ('${empresa}', 'Fuzz comissão ${i}');\n`
      const fid = `e99${String(i).padStart(5, '0')}-0000-4000-8000-000000000000`
      sql += `insert into public.comissao_fechamentos (id, empresa_id, titulo, data_inicio, data_fim, percentual_retencao, servico_ajuste_centavos, proporcional_dias)
        values ('${fid}', '${empresa}', 'f${i}', '${e.dataInicio}', '${e.dataFim}', ${e.percentualRetencao}, ${e.servicoZigCentavos + e.servicoAjusteCentavos}, ${e.proporcionalDias});\n`
      e.participantes.forEach((p, k) => {
        let fun = 'null'
        if (p.funcionarioId) {
          const id = `e99${String(i).padStart(5, '0')}-0000-4000-8000-${String(k).padStart(12, '0')}`
          p.funcionarioId = id
          fun = `'${id}'`
          sql += `insert into public.funcionarios (id, empresa_id, nome) values (${fun}, '${empresa}', ${sqlTexto(p.nome)});\n`
        }
        sql += `insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, incluido, pontos, dias_trabalhados, pontos_extras)
          values ('${empresa}', '${fid}', ${fun}, ${sqlTexto(p.nome)}, ${p.incluido}, ${p.pontos}, ${p.diasTrabalhados}, ${p.funcionarioId ? 0 : (p.pontosExtras ?? 0)});\n`
        // com funcionário o banco relê os extras de comissao_pontos_extras; sem funcionário (snapshot) mantém a coluna
        if (p.funcionarioId && (p.pontosExtras ?? 0) > 0)
          sql += `insert into public.comissao_pontos_extras (empresa_id, funcionario_id, data, pontos, motivo, criado_por_nome)
            values ('${empresa}', ${fun}, '${e.dataInicio}', ${p.pontosExtras}, 'fuzz', 'Fuzz');\n`
      })
      // o ajuste já contém o "serviço da Zig" do caso (não há vendas nesta empresa)
      e.servicoAjusteCentavos += e.servicoZigCentavos
      e.servicoZigCentavos = 0
      sql += `select public.comissao_calcular('${fid}');\n`
    })
    sql += `select json_agg(json_build_object('f', f.titulo, 'base', f.base_distribuivel_centavos, 'ret', f.retencao_centavos,
              'itens', (select json_agg(json_build_object('id', i.funcionario_id, 'nome', i.funcionario_nome, 'v', i.valor_centavos)) from public.comissao_itens i where i.fechamento_id = f.id)))
            from public.comissao_fechamentos f where f.empresa_id::text like 'e99%-0000-4000-8000-00000000eeee';\nrollback;\n`
    const base = process.env.MDG_PG_DIR ?? `${process.env.TMPDIR ?? '/tmp'}/mdg-postgres`
    const r = spawnSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', process.env.MDG_PG_BANCO ?? 'mdg_local'], {
      input: sql,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, PGHOST: process.env.PGHOST ?? `${base}/socket`, PGPORT: process.env.PGPORT ?? '54329', PGUSER: process.env.PGUSER ?? 'postgres' },
    })
    expect(r.status, r.stderr).toBe(0)
    const saida = r.stdout
    const linhaJson = saida.split('\n').find((l) => l.startsWith('['))!
    const banco = new Map((JSON.parse(linhaJson) as { f: string; base: number; ret: number; itens: { id: string | null; nome: string; v: number }[] }[]).map((x) => [x.f, x]))
    casos.forEach((e, i) => {
      const r = calcularComissao(e)
      const b = banco.get(`f${i}`)!
      const contexto = JSON.stringify(e)
      expect(b.base, contexto).toBe(r.baseCentavos)
      expect(b.ret, contexto).toBe(r.retencaoCentavos)
      const doBanco = new Map(b.itens.map((x) => [`${x.id ?? ''}|${x.nome}`, x.v]))
      for (const it of r.itens) expect(doBanco.get(`${it.funcionarioId ?? ''}|${it.nome}`), contexto).toBe(it.valorCentavos)
    })
  })
})
