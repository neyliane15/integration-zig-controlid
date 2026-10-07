/**
 * Revisão 2 — fuzz da apuração de ponto: banco × front (opt-in, `MDG_FUZZ_BANCO=1`; mesmo Postgres de
 * `supabase/testes/preparar-postgres.sh`, banco com as migrações em `MDG_PG_BANCO`, padrão `mdg_local`).
 *
 * Gera, numa transação desfeita no fim, 2 empresas (São Paulo/05:00 e Manaus/04:00), 16 funcionários com escalas
 * aleatórias (2 ou 4 batidas, muitas atravessando a meia-noite, folgas) e ~55 dias de batidas aleatórias (esquecidas,
 * extras, duplicadas a menos de 2 min, desconsideradas). Apura no banco e confere, dia a dia, com as funções do front:
 *   - duplicadas: regra §7.2-3 reimplementada aqui (janela da empresa a partir da última válida);
 *   - trabalhado = `paresTrabalhados(válidas).total` (§7.2-4);
 *   - batida(s) faltante(s) dos alarmes do banco = `identificarFaltantes` (o que a tela mostra como "faltou");
 *   - um alarme `batida_faltando` por slot faltante, `sem_batida_dia_escalado` só com 0 batidas, ímpar só fora do caso
 *     "faltando", nenhum alarme em dia não encerrado (exceto atraso) e situação coerente com n/esperadas;
 *   - reapurar é idempotente (mesmos dias e alarmes).
 */
import { spawnSync } from 'node:child_process'
import { describe, expect, it } from 'vitest'
import { identificarFaltantes, paresTrabalhados } from './ponto'

const ATIVO = process.env.MDG_FUZZ_BANCO === '1'

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

function psql(sql: string): string {
  const base = process.env.MDG_PG_DIR ?? `${process.env.TMPDIR ?? '/tmp'}/mdg-postgres`
  const r = spawnSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', process.env.MDG_PG_BANCO ?? 'mdg_local'], {
    input: sql,
    encoding: 'utf8',
    maxBuffer: 256 * 1024 * 1024,
    env: { ...process.env, PGHOST: process.env.PGHOST ?? `${base}/socket`, PGPORT: process.env.PGPORT ?? '54329', PGUSER: process.env.PGUSER ?? 'postgres' },
  })
  if (r.status !== 0) throw new Error(r.stderr)
  return r.stdout
}

const pad = (n: number) => String(n).padStart(2, '0')
const hhmm = (m: number) => `${pad(Math.floor((((m % 1440) + 1440) % 1440) / 60))}:${pad((((m % 1440) + 1440) % 1440) % 60)}`

interface Batida { instante: string; duplicada: boolean; desconsiderada: boolean }
interface Esperada { batida: 'entrada' | 'saida_intervalo' | 'volta_intervalo' | 'saida'; instante: string }
interface Linha {
  f: string; data: string; situacao: string; encerrado: boolean; trabalhado_minutos: number; previsto_minutos: number
  batidas: Batida[]; esperadas: Esperada[]; alarmes: { tipo: string; batida_esperada: string; status: string }[]
}

describe.skipIf(!ATIVO)('ponto — banco × front (fuzz; MDG_FUZZ_BANCO=1)', () => {
  it('apuração, duplicadas, trabalhado e batida faltante batem com o front em ~880 dias aleatórios', { timeout: 300_000 }, () => {
    const rnd = gerador(Number(process.env.MDG_FUZZ_SEMENTE ?? 31337))
    const inteiro = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1))
    const EMP = [
      { id: 'e9800000-0000-4000-8000-00000000000a', fuso: 'America/Sao_Paulo', virada: '05:00', off: -3, janela: 2 },
      { id: 'e9800000-0000-4000-8000-00000000000b', fuso: 'America/Manaus', virada: '04:00', off: -4, janela: 3 },
    ]
    let sql = `begin;\nset local app.agora = '2026-10-06 12:00:00-03';\nset local client_min_messages = warning;\n`
    for (const e of EMP) {
      sql += `insert into public.empresas (id, nome, fuso, virada_dia, ponto_janela_duplicada_minutos) values ('${e.id}', 'Fuzz ponto ${e.fuso}', '${e.fuso}', '${e.virada}', ${e.janela});\n`
    }
    const funcionarios: { id: string; emp: (typeof EMP)[number] }[] = []
    for (let k = 0; k < 16; k++) {
      const emp = EMP[k % 2]!
      const fid = `e9800000-0000-4000-8000-0000000003${pad(k)}`
      const jid = `e9800000-0000-4000-8000-0000000002${pad(k)}`
      funcionarios.push({ id: fid, emp })
      sql += `insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values ('${jid}', '${emp.id}', 'J${k}', ${inteiro(0, 15)}, ${inteiro(0, 20)});\n`
      const viradaMin = Number(emp.virada.slice(0, 2)) * 60
      for (let d = 0; d < 7; d++) {
        if (rnd() < 0.2) continue // folga
        // entrada entre virada+1h e 22:00; jornada total até 10h (pode atravessar a meia-noite, sempre antes da virada)
        const ent = inteiro(viradaMin + 60, 22 * 60)
        const fimMax = viradaMin + 1440 - 1
        const sai = Math.min(ent + inteiro(120, 600), fimMax)
        if (rnd() < 0.4 || sai - ent < 90) {
          sql += `insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) values ('${jid}', ${d}, '${hhmm(ent)}', '${hhmm(sai)}');\n`
        } else {
          const si = inteiro(ent + 30, sai - 60)
          const vi = Math.min(si + inteiro(15, 60), sai - 15)
          sql += `insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values ('${jid}', ${d}, '${hhmm(ent)}', '${hhmm(si)}', '${hhmm(vi)}', '${hhmm(sai)}');\n`
        }
      }
      sql += `insert into public.funcionarios (id, empresa_id, nome, data_admissao) values ('${fid}', '${emp.id}', 'F${k}', '2026-08-10');\n`
      sql += `insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde) values ('${fid}', '${jid}', '2026-08-10');\n`
      // batidas aleatórias: por dia de calendário, 0..6 batidas espalhadas de 06:00 a 05:59 do dia seguinte
      const valores: string[] = []
      for (let dia = Date.UTC(2026, 7, 10); dia <= Date.UTC(2026, 9, 6); dia += 86400000) {
        const n = [0, 1, 2, 3, 3, 4, 4, 4, 5, 6][inteiro(0, 9)]!
        const minutos = Array.from({ length: n }, () => inteiro(viradaMin, viradaMin + 1439)).sort((a, b) => a - b)
        for (const m of minutos) {
          const inst = new Date(dia + (m - emp.off * 60) * 60000 + inteiro(0, 59) * 1000)
          if (inst.getTime() > Date.parse('2026-10-06T15:00:00Z')) continue
          valores.push(`('${emp.id}', '${fid}', 'manual', '${inst.toISOString()}', 'fuzz', ${rnd() < 0.05})`)
          if (rnd() < 0.12) {
            const dup = new Date(inst.getTime() + inteiro(1, emp.janela * 60 + 30) * 1000)
            if (dup.getTime() <= Date.parse('2026-10-06T15:00:00Z')) valores.push(`('${emp.id}', '${fid}', 'manual', '${dup.toISOString()}', 'fuzz', false)`)
          }
        }
      }
      if (valores.length) sql += `insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo, desconsiderada) values ${valores.join(',\n')};\n`
    }
    const consulta = (rotulo: string) =>
      `select '${rotulo}' || jsonb_agg(x)::text from (select f.id as f, e.data, e.situacao, e.encerrado, e.trabalhado_minutos, e.previsto_minutos, e.batidas, e.esperadas,
         (select coalesce(json_agg(json_build_object('tipo', a.tipo, 'batida_esperada', a.batida_esperada, 'status', a.status)), '[]') from public.ponto_alarmes a where a.funcionario_id = f.id and a.data = e.data and a.status <> 'resolvido') as alarmes
        from public.funcionarios f cross join lateral (select * from public.ponto_espelho(f.id, '2026-08-10', '2026-10-06') ) e
       where f.empresa_id in ('${EMP[0]!.id}', '${EMP[1]!.id}')) x;\n`
    // ponto_espelho aceita até 62 dias: 2026-08-10..2026-10-06 = 58 dias
    sql += `select count(*) from (select public.ponto_apurar(f.id, '2026-08-10', '2026-10-06') from public.funcionarios f where f.empresa_id in ('${EMP[0]!.id}', '${EMP[1]!.id}')) a;\n`
    sql += consulta('A:')
    sql += `select count(*) from (select public.ponto_apurar(f.id, '2026-08-10', '2026-10-06') from public.funcionarios f where f.empresa_id in ('${EMP[0]!.id}', '${EMP[1]!.id}')) a;\n`
    sql += consulta('B:')
    sql += `rollback;\n`
    const saida = psql(sql)
    const a = JSON.parse(saida.split('\n').find((l) => l.startsWith('A:'))!.slice(2)) as Linha[]
    const b = JSON.parse(saida.split('\n').find((l) => l.startsWith('B:'))!.slice(2)) as Linha[]
    expect(b, 'reapurar é idempotente').toEqual(a)
    expect(a.length).toBeGreaterThan(800)

    const janela = new Map(funcionarios.map((f) => [f.id, f.emp.janela]))
    let comFaltante = 0
    for (const l of a) {
      const ctx = JSON.stringify(l)
      // duplicadas (§7.2-3): ordem por instante; dentro da janela da ÚLTIMA válida
      const naoDesc = l.batidas.filter((x) => !x.desconsiderada).sort((x, y) => Date.parse(x.instante) - Date.parse(y.instante))
      let ultima: number | null = null
      for (const x of naoDesc) {
        const t = Date.parse(x.instante)
        const dup = ultima != null && t - ultima < janela.get(l.f)! * 60000
        expect(x.duplicada, ctx).toBe(dup)
        if (!dup) ultima = t
      }
      const validas = naoDesc.filter((x) => !x.duplicada).map((x) => x.instante)
      expect(l.trabalhado_minutos, ctx).toBe(paresTrabalhados(validas).total)
      const n = validas.length
      const k = l.esperadas.length
      const abertos = l.alarmes.filter((x) => x.tipo !== 'atraso')
      if (!l.encerrado) {
        expect(abertos, ctx).toEqual([])
        expect(l.situacao, ctx).toBe('em_andamento')
        continue
      }
      const faltando = abertos.filter((x) => x.tipo === 'batida_faltando').map((x) => x.batida_esperada).sort()
      if (k > 0 && n > 0 && n < k) {
        comFaltante++
        expect(faltando, ctx).toEqual([...identificarFaltantes(validas, l.esperadas)].sort())
        expect(l.situacao, ctx).toBe('incompleto')
      } else {
        expect(faltando, ctx).toEqual([])
      }
      expect(abertos.some((x) => x.tipo === 'sem_batida_dia_escalado'), ctx).toBe(k > 0 && n === 0)
      expect(abertos.some((x) => x.tipo === 'batidas_impares'), ctx).toBe(n % 2 === 1 && !(k > 0 && n > 0 && n < k))
      if (k === 0 && n === 0) expect(['folga', 'sem_escala'], ctx).toContain(l.situacao)
      if (k > 0 && n === 0) expect(l.situacao, ctx).toBe('ausente')
      if (n > 0 && n >= k && n % 2 === 0) expect(l.situacao, ctx).toBe('completo')
    }
    expect(comFaltante, 'o fuzz exercita o caso "batida faltando"').toBeGreaterThan(50)
  })
})
