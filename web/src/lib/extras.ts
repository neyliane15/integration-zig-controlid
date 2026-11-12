/**
 * Funções puras dos Extras (adendo E): validação de pontos extras, totais de diárias e CSVs.
 */
import type { Diaria, GastosPeriodo } from '@/tipos/banco'
import { centavosCsv, dataCsv, gerarCsv, nomeArquivoCsv } from './csv'

/** Pontos com até 2 casas, 0 < x ≤ 9999,99 (mesma regra do banco: `Pontos extras inválidos`). Aceita vírgula. */
export function lerPontosExtras(s: string): number | null {
  const t = s.replace(',', '.').trim()
  if (!/^\d{1,4}(\.\d{1,2})?$/.test(t)) return null
  const n = Number(t)
  return n > 0 && n <= 9999.99 ? n : null
}

/** Totais da lista de diárias (centavos). */
export function totaisDiarias(lista: Pick<Diaria, 'pago' | 'valor_centavos'>[]) {
  let pagas = 0
  let aPagar = 0
  for (const d of lista) {
    if (d.pago) pagas += d.valor_centavos
    else aPagar += d.valor_centavos
  }
  return { pagas, aPagar, total: pagas + aPagar, quantidade: lista.length }
}

/** Fechamentos fechados que cobrem a data (o banco recusa lançar/excluir extra nelas). */
export function fechamentoQueCobre<T extends { status: string; data_inicio: string; data_fim: string }>(fechamentos: T[], data: string | null): T | null {
  if (!data) return null
  return fechamentos.find((f) => f.status === 'fechado' && f.data_inicio <= data && data <= f.data_fim) ?? null
}

export const COLUNAS_CSV_GASTOS = ['Pessoa', 'Avulso', 'Diárias (qtd)', 'Diárias pagas (R$)', 'Diárias a pagar (R$)', 'Comissões fechadas (R$)', 'Comissões previstas (R$)', 'Total (R$)']

/** CSV dos gastos do período (§13): preâmbulo com os totais + uma linha por pessoa + Total. */
export function csvGastos(g: GastosPeriodo, empresaNome: string): { nome: string; conteudo: string } {
  const t = g.totais
  const preambulo = [
    ['Período', `${dataCsv(g.inicio)} a ${dataCsv(g.fim)}`],
    ['Diárias pagas (R$)', centavosCsv(t.diarias_pagas)],
    ['Diárias a pagar (R$)', centavosCsv(t.diarias_a_pagar)],
    ['Comissões fechadas (R$)', centavosCsv(t.comissoes_fechadas)],
    ['Comissões previstas (R$)', centavosCsv(t.comissoes_previstas)],
    ['Total (R$)', centavosCsv(t.total)],
    ['Total com previsto (R$)', centavosCsv(t.total_com_previsto)],
  ]
  const linhas: unknown[][] = g.por_pessoa.map((p) => [
    p.nome,
    p.avulso,
    p.diarias_qtd,
    centavosCsv(p.diarias_pagas),
    centavosCsv(p.diarias_a_pagar),
    centavosCsv(p.comissoes_fechadas),
    centavosCsv(p.comissoes_previstas),
    centavosCsv(p.total),
  ])
  linhas.push([
    'Total',
    '',
    t.diarias_qtd,
    centavosCsv(t.diarias_pagas),
    centavosCsv(t.diarias_a_pagar),
    centavosCsv(t.comissoes_fechadas),
    centavosCsv(t.comissoes_previstas),
    centavosCsv(t.total),
  ])
  return { nome: nomeArquivoCsv('gastos', empresaNome || 'empresa', g.inicio, g.fim), conteudo: gerarCsv(COLUNAS_CSV_GASTOS, linhas, preambulo) }
}

export const COLUNAS_CSV_DIARIAS = ['Data', 'Pessoa', 'Avulso', 'Função', 'Valor (R$)', 'Pago', 'Pago em', 'Observação']

export function csvDiarias(lista: Diaria[], empresaNome: string, inicio: string, fim: string): { nome: string; conteudo: string } {
  const linhas = [...lista]
    .sort((a, b) => a.data.localeCompare(b.data) || a.pessoa_nome.localeCompare(b.pessoa_nome, 'pt-BR'))
    .map((d) => [dataCsv(d.data), d.pessoa_nome, d.avulso, d.funcao ?? '', centavosCsv(d.valor_centavos), d.pago, dataCsv(d.pago_em), d.observacao ?? ''])
  return { nome: nomeArquivoCsv('diarias', empresaNome || 'empresa', inicio, fim), conteudo: gerarCsv(COLUNAS_CSV_DIARIAS, linhas) }
}
