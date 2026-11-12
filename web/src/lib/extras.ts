/**
 * Funções puras dos Extras (adendo E v2 — freelas/diaristas): validação de pontos, busca, totais dos dias trabalhados e CSVs.
 */
import type { Diaria, Extra, GastosPeriodo } from '@/tipos/banco'
import { centavosCsv, dataCsv, gerarCsv, nomeArquivoCsv } from './csv'
import { numeroCsv } from './comissao'

/** Pontos com até 2 casas em 0..9999,99 (regra do banco: `Pontos inválidos`). Aceita vírgula. Vazio → null. */
export function lerPontos(s: string): number | null {
  const t = s.replace(',', '.').trim()
  if (!/^\d{1,4}(\.\d{1,2})?$/.test(t)) return null
  const n = Number(t)
  return n >= 0 && n <= 9999.99 ? n : null
}

/** Pontos para exibir/editar: 7.5 → "7,5". */
export const pontosTexto = (n: number | null | undefined) => (n == null ? '' : n.toLocaleString('pt-BR', { maximumFractionDigits: 2 }))

const normalizar = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()

/** Busca por nome, função, telefone ou documento (sem acento/maiúsculas). */
export function filtrarExtras<T extends Pick<Extra, 'nome' | 'funcao' | 'telefone' | 'documento'>>(lista: T[], busca: string): T[] {
  const termo = normalizar(busca.trim())
  if (!termo) return lista
  const digitos = termo.replace(/\D/g, '')
  return lista.filter((e) => {
    if (normalizar(`${e.nome} ${e.funcao ?? ''}`).includes(termo)) return true
    if (!digitos) return false
    return `${e.telefone ?? ''} ${e.documento ?? ''}`.replace(/\D/g, '').includes(digitos)
  })
}

/** Totais da lista de dias trabalhados / diárias (centavos e pontos). */
export function totaisDiarias(lista: Pick<Diaria, 'pago' | 'valor_centavos' | 'tipo' | 'pontos'>[]) {
  let pagas = 0
  let aPagar = 0
  let extras = 0
  let funcionarios = 0
  let diasExtras = 0
  let pontos = 0
  for (const d of lista) {
    if (d.pago) pagas += d.valor_centavos
    else aPagar += d.valor_centavos
    if (d.tipo === 'extra') {
      extras += d.valor_centavos
      diasExtras += 1
      pontos += Number(d.pontos) || 0
    } else funcionarios += d.valor_centavos
  }
  return { pagas, aPagar, total: pagas + aPagar, quantidade: lista.length, extras, funcionarios, diasExtras, pontos: Math.round(pontos * 100) / 100 }
}

/** Fechamento fechado que cobre a data (o banco trava data/pontos de dias de extra nele). */
export function fechamentoQueCobre<T extends { status: string; data_inicio: string; data_fim: string }>(fechamentos: T[], data: string | null): T | null {
  if (!data) return null
  return fechamentos.find((f) => f.status === 'fechado' && f.data_inicio <= data && data <= f.data_fim) ?? null
}

const rotuloTipo = (t: string) => (t === 'extra' ? 'Extra' : 'Funcionário')

export const COLUNAS_CSV_GASTOS = ['Pessoa', 'Tipo', 'Diárias (qtd)', 'Diárias pagas (R$)', 'Diárias a pagar (R$)', 'Comissões fechadas (R$)', 'Comissões previstas (R$)', 'Total (R$)']

/** CSV dos gastos do período (§13): preâmbulo com os totais + uma linha por pessoa + Total. */
export function csvGastos(g: GastosPeriodo, empresaNome: string): { nome: string; conteudo: string } {
  const t = g.totais
  const preambulo = [
    ['Período', `${dataCsv(g.inicio)} a ${dataCsv(g.fim)}`],
    ['Diárias de extras (R$)', centavosCsv(t.diarias_extras)],
    ['Diárias de funcionários (R$)', centavosCsv(t.diarias_funcionarios)],
    ['Diárias pagas (R$)', centavosCsv(t.diarias_pagas)],
    ['Diárias a pagar (R$)', centavosCsv(t.diarias_a_pagar)],
    ['Comissões fechadas (R$)', centavosCsv(t.comissoes_fechadas)],
    ['Comissões previstas (R$)', centavosCsv(t.comissoes_previstas)],
    ['Total (R$)', centavosCsv(t.total)],
    ['Total com previsto (R$)', centavosCsv(t.total_com_previsto)],
  ]
  const linhas: unknown[][] = g.por_pessoa.map((p) => [
    p.nome,
    rotuloTipo(p.tipo),
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

export const COLUNAS_CSV_DIARIAS = ['Data', 'Pessoa', 'Tipo', 'Função', 'Pontos', 'Valor (R$)', 'Pago', 'Pago em', 'Observação']

/** CSV dos dias trabalhados: em ordem de data e nome + linha Total (Σ pontos dos extras, Σ valor). */
export function csvDiarias(lista: Diaria[], empresaNome: string, inicio: string, fim: string): { nome: string; conteudo: string } {
  const linhas: unknown[][] = [...lista]
    .sort((a, b) => a.data.localeCompare(b.data) || a.pessoa_nome.localeCompare(b.pessoa_nome, 'pt-BR'))
    .map((d) => [
      dataCsv(d.data),
      d.pessoa_nome,
      rotuloTipo(d.tipo),
      d.funcao ?? '',
      d.tipo === 'extra' ? numeroCsv(d.pontos ?? 0, 2) : '',
      centavosCsv(d.valor_centavos),
      d.pago,
      dataCsv(d.pago_em),
      d.observacao ?? '',
    ])
  const t = totaisDiarias(lista)
  linhas.push(['Total', '', '', '', numeroCsv(t.pontos, 2), centavosCsv(t.total), '', '', ''])
  return { nome: nomeArquivoCsv('dias-trabalhados', empresaNome || 'empresa', inicio, fim), conteudo: gerarCsv(COLUNAS_CSV_DIARIAS, linhas) }
}
