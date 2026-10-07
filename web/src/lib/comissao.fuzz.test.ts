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

function caso(rnd: () => number, i: number, proporcionalPermitido = true): EntradaComissao {
  const inteiro = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1))
  const n = inteiro(1, 9)
  const dias = inteiro(1, 30)
  const dataFim = new Date(Date.UTC(2026, 8, dias)).toISOString().slice(0, 10)
  // pontos com 2 casas, com repetições frequentes (empates de fração e de pontos)
  const pontosPossiveis = [1, 2, 3, 0.5, 0.01, 10, 7.77, 999999.99, inteiro(0, 5000) / 100]
  const participantes: ParticipanteComissao[] = []
  for (let k = 0; k < n; k++) {
    participantes.push({
      funcionarioId: rnd() < 0.1 ? null : `f${String(i).padStart(7, '0')}-0000-4000-8000-${String(k).padStart(12, '0')}`,
      nome: NOMES[inteiro(0, NOMES.length - 1)]!,
      incluido: rnd() > 0.1,
      pontos: pontosPossiveis[inteiro(0, pontosPossiveis.length - 1)]!,
      diasTrabalhados: inteiro(0, dias),
    })
  }
  const escalaBase = [0, 1, 7, 99, 100, 12345, 995000, 99999999, 999999999999][inteiro(0, 8)]!
  return {
    servicoZigCentavos: inteiro(0, escalaBase),
    servicoAjusteCentavos: rnd() < 0.3 ? -inteiro(0, escalaBase) : rnd() < 0.5 ? inteiro(0, 5000) : 0,
    percentualRetencao: [0, 20, 12.5, 13.37, 33.33, 50, 100, inteiro(0, 10000) / 100][inteiro(0, 7)]!,
    proporcionalDias: proporcionalPermitido && rnd() < 0.3,
    dataInicio: '2026-09-01',
    dataFim,
    participantes,
  }
}

// ------------------------------------------------------------------ referência independente
const arred = (n: bigint, d: bigint) => {
  const q = n / d
  return (n % d) * 2n >= d ? q + 1n : q
}
const centesimos = (v: number) => BigInt(Math.round(v * 100))

function referencia(e: EntradaComissao) {
  const bruto = (() => {
    const s = BigInt(e.servicoZigCentavos) + BigInt(e.servicoAjusteCentavos)
    return s > 0n ? s : 0n
  })()
  const retencao = arred(bruto * centesimos(e.percentualRetencao), 10_000n)
  const base = bruto - retencao
  const diasPeriodo = BigInt(Number(e.dataFim.slice(8, 10))) // período sempre começa em 01/09 e termina em setembro
  // pontos efetivos na escala 10^6
  const pe = e.participantes.map((p) => {
    if (!p.incluido) return 0n
    const p6 = centesimos(p.pontos) * 10_000n
    return e.proporcionalDias ? arred(p6 * BigInt(p.diasTrabalhados), diasPeriodo) : p6
  })
  const soma = pe.reduce((s, v) => s + v, 0n)
  if (soma === 0n) return { retencao, base, valores: pe.map(() => 0n) }
  // piso exato por subtração repetida evitada: floor(base × pe / soma) com BigInt
  const pisos = pe.map((x) => (base * x) / soma)
  let resto = base - pisos.reduce((s, v) => s + v, 0n)
  // ordem: fração desc (comparada por produto cruzado das frações (base×pe − piso×soma)/soma), pe desc, nome (código), id
  const idx = pe.map((_, i) => i).filter((i) => pe[i]! > 0n)
  idx.sort((a, b) => {
    const fa = base * pe[a]! - pisos[a]! * soma
    const fb = base * pe[b]! - pisos[b]! * soma
    if (fa !== fb) return fa > fb ? -1 : 1
    if (pe[a] !== pe[b]) return pe[a]! > pe[b]! ? -1 : 1
    const na = e.participantes[a]!.nome
    const nb = e.participantes[b]!.nome
    if (na !== nb) return na < nb ? -1 : 1
    const ia = e.participantes[a]!.funcionarioId ?? '￿'
    const ib = e.participantes[b]!.funcionarioId ?? '￿'
    return ia < ib ? -1 : ia > ib ? 1 : 0
  })
  const valores = [...pisos]
  for (const i of idx) {
    if (resto <= 0n) break
    valores[i] = valores[i]! + 1n
    resto -= 1n
  }
  return { retencao, base, valores }
}

describe('comissão — propriedades (fuzz, 3.000 casos)', () => {
  it('prévia do front = referência independente, Σ = base e cada valor = piso ou piso + 1', () => {
    const rnd = gerador(20261007)
    for (let i = 0; i < 3000; i++) {
      const e = caso(rnd, i)
      const r = calcularComissao(e)
      const ref = referencia(e)
      const contexto = JSON.stringify(e)
      expect(r.retencaoCentavos, contexto).toBe(Number(ref.retencao))
      expect(r.baseCentavos, contexto).toBe(Number(ref.base))
      expect(r.itens.map((x) => x.valorCentavos), contexto).toEqual(ref.valores.map(Number))
      if (!r.semParticipantes) expect(r.totalDistribuidoCentavos, contexto).toBe(r.baseCentavos)
      r.itens.forEach((x, k) => {
        if (!e.participantes[k]!.incluido) expect(x.valorCentavos, contexto).toBe(0)
        expect(x.valorCentavos, contexto).toBeGreaterThanOrEqual(0)
      })
    }
  })

  it('mais pontos nunca recebe menos (mesmo caso, só um participante com pontos maiores)', () => {
    const rnd = gerador(7)
    for (let i = 0; i < 500; i++) {
      const e = { ...caso(rnd, i, false), proporcionalDias: false }
      const r = calcularComissao(e)
      e.participantes.forEach((a, ia) =>
        e.participantes.forEach((b, ib) => {
          if (a.incluido && b.incluido && a.pontos > b.pontos) {
            expect(r.itens[ia]!.valorCentavos, JSON.stringify(e)).toBeGreaterThanOrEqual(r.itens[ib]!.valorCentavos)
          }
        }),
      )
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
    const empresa = 'e9900000-0000-4000-8000-00000000000a'
    let sql = `begin;\nset local client_min_messages = warning;\n`
    sql += `insert into public.empresas (id, nome) values ('${empresa}', 'Fuzz comissão');\n`
    casos.forEach((e, i) => {
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
        sql += `insert into public.comissao_itens (empresa_id, fechamento_id, funcionario_id, funcionario_nome, incluido, pontos, dias_trabalhados)
          values ('${empresa}', '${fid}', ${fun}, ${sqlTexto(p.nome)}, ${p.incluido}, ${p.pontos}, ${p.diasTrabalhados});\n`
      })
      // o ajuste já contém o "serviço da Zig" do caso (não há vendas nesta empresa)
      e.servicoAjusteCentavos += e.servicoZigCentavos
      e.servicoZigCentavos = 0
      sql += `select public.comissao_calcular('${fid}');\n`
    })
    sql += `select json_agg(json_build_object('f', f.titulo, 'base', f.base_distribuivel_centavos, 'ret', f.retencao_centavos,
              'itens', (select json_agg(json_build_object('id', i.funcionario_id, 'nome', i.funcionario_nome, 'v', i.valor_centavos)) from public.comissao_itens i where i.fechamento_id = f.id)))
            from public.comissao_fechamentos f where f.empresa_id = '${empresa}';\nrollback;\n`
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
