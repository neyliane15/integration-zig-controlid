/**
 * Importação de extras por CSV (adendo extras v3, §E.7.6) — "outro sistema do Macaw" (formato ainda indefinido) ou planilha própria
 * salva como CSV. Funções puras. Dono: frontend. Reaproveita a leitura de CSV das reservas (`;` `,` TAB, aspas, BOM).
 *
 * - Colunas reconhecidas pelo nome (português/inglês, com/sem acento); o resto o usuário escolhe na prévia.
 * - Pontos vazios → `null` = **pontuação pendente** (o extra novo fica pendente e não entra na comissão até preencher).
 * - Dias trabalhados (opcional): uma coluna de data; pode ter várias datas na mesma célula (`03/09/2026, 04/09/2026`) ou uma linha por
 *   dia da mesma pessoa — linhas com o mesmo documento (ou, sem documento, o mesmo nome) viram **um** item com todos os dias.
 */
import type { ExtraImportacao } from '@/tipos/banco'
import { lerDataReserva, normalizarCabecalho } from './reservasCsv'

export { detectarSeparador, lerCsv } from './reservasCsv'

export type CampoExtra = 'nome' | 'funcao' | 'telefone' | 'documento' | 'valor' | 'pontos' | 'dias'

export const CAMPOS_EXTRA: { id: CampoExtra; rotulo: string; obrigatorio?: boolean; ajuda?: string }[] = [
  { id: 'nome', rotulo: 'Nome', obrigatorio: true },
  { id: 'funcao', rotulo: 'Função' },
  { id: 'telefone', rotulo: 'Telefone' },
  { id: 'documento', rotulo: 'Documento (CPF/RG)' },
  { id: 'valor', rotulo: 'Valor da diária' },
  { id: 'pontos', rotulo: 'Pontos', ajuda: 'Vazio = pontuação pendente' },
  { id: 'dias', rotulo: 'Dias trabalhados (data)', ajuda: 'Opcional' },
]

const SINONIMOS: Record<CampoExtra, string[]> = {
  nome: ['nome', 'nome completo', 'extra', 'freela', 'freelancer', 'diarista', 'colaborador', 'pessoa', 'name', 'full name', 'funcionario'],
  funcao: ['funcao', 'cargo', 'posicao', 'setor', 'role', 'position', 'job', 'atividade'],
  telefone: ['telefone', 'celular', 'fone', 'whatsapp', 'phone', 'mobile', 'tel', 'contato'],
  documento: ['documento', 'doc', 'cpf', 'rg', 'cpf rg', 'cpf ou rg', 'document', 'id'],
  valor: ['valor', 'valor da diaria', 'valor diaria', 'diaria', 'cache', 'pagamento', 'valor dia', 'daily rate', 'rate', 'pay'],
  pontos: ['pontos', 'pontuacao', 'pontos comissao', 'pontos de comissao', 'pts', 'points', 'score', 'peso'],
  dias: ['data', 'datas', 'dia', 'dias', 'dias trabalhados', 'data trabalhada', 'datas trabalhadas', 'date', 'dates', 'work date'],
}

const ORDEM: CampoExtra[] = ['nome', 'documento', 'telefone', 'funcao', 'pontos', 'valor', 'dias']

export type MapeamentoExtras = Record<CampoExtra, number | null>

export function mapeamentoExtrasVazio(): MapeamentoExtras {
  return Object.fromEntries(CAMPOS_EXTRA.map((c) => [c.id, null])) as MapeamentoExtras
}

/** Reconhece as colunas pelo nome (igualdade primeiro, depois "contém a palavra"). Cada coluna vai para no máximo um campo. */
export function reconhecerColunasExtras(cabecalho: string[]): MapeamentoExtras {
  const m = mapeamentoExtrasVazio()
  const usados = new Set<number>()
  const nomes = cabecalho.map(normalizarCabecalho)
  for (const campo of ORDEM) {
    const i = nomes.findIndex((n, j) => !usados.has(j) && SINONIMOS[campo].includes(n))
    if (i >= 0) {
      m[campo] = i
      usados.add(i)
    }
  }
  for (const campo of ORDEM) {
    if (m[campo] != null) continue
    const i = nomes.findIndex((n, j) => !usados.has(j) && SINONIMOS[campo].some((s) => s.length >= 3 && new RegExp(`(^| )${s}( |$)`).test(n)))
    if (i >= 0) {
      m[campo] = i
      usados.add(i)
    }
  }
  return m
}

/** '150', '150,00', 'R$ 1.234,56', '1234.56' → centavos; vazio → null; inválido → NaN. */
export function lerValorCentavos(s: string): number | null {
  let t = s.replace(/r\$|\s/gi, '').trim()
  if (!t) return null
  if (!/^\d[\d.,]*$/.test(t)) return Number.NaN
  if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.')
  else if (/^\d{1,3}(\.\d{3})+$/.test(t)) t = t.replace(/\./g, '')
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return Number.NaN
  const [int, frac = ''] = t.split('.')
  return Number(int) * 100 + Number(frac.padEnd(2, '0'))
}

/** Pontos 0..9999,99 com até 2 casas; vazio → null (pendente); inválido → NaN. */
export function lerPontosCsv(s: string): number | null {
  const t = s.replace(',', '.').trim()
  if (!t) return null
  if (!/^\d{1,4}(\.\d{1,2})?$/.test(t)) return Number.NaN
  return Number(t)
}

/** Várias datas numa célula: separadas por vírgula, espaço, `|` ou `e`. Devolve as datas e os textos que não são data. */
export function lerDatas(s: string): { datas: string[]; invalidas: string[] } {
  const partes = s
    .split(/\s*(?:,|\||\s+e\s+|\s+)\s*/i)
    .map((p) => p.trim())
    .filter(Boolean)
  const datas: string[] = []
  const invalidas: string[] = []
  for (const p of partes) {
    const d = lerDataReserva(p)
    if (d) {
      if (!datas.includes(d)) datas.push(d)
    } else invalidas.push(p)
  }
  return { datas, invalidas }
}

/** Chave de agrupamento (igual ao casamento do banco): documento só com letras/dígitos; sem documento, o nome normalizado. */
export function chaveExtra(nome: string, documento: string | null): string {
  const doc = (documento ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
  if (doc) return `d:${doc}`
  return `n:${nome.toLowerCase().replace(/\s+/g, ' ').trim()}`
}

export interface ExtraLido extends ExtraImportacao {
  /** linhas do arquivo (1 = cabeçalho) que formaram o item */
  linhas: number[]
  pontos: number | null
  dias_trabalhados: { data: string; valor_centavos: number | null; pontos: number | null }[]
}

export interface ErroLinhaExtra {
  linha: number
  mensagem: string
}

export interface ResultadoExtrasCsv {
  extras: ExtraLido[]
  erros: ErroLinhaExtra[]
  /** itens sem pontuação (ficarão pendentes se forem novos) */
  semPontos: number
}

export const LIMITE_EXTRAS_IMPORTACAO = 1000

const v = (l: string[], i: number | null) => (i == null ? '' : (l[i] ?? '').trim())
const ouNull = (s: string) => (s === '' ? null : s)

/** Linhas de dados (sem cabeçalho) → itens de `extras_importar`, agrupando a mesma pessoa. */
export function converterExtras(dados: string[][], m: MapeamentoExtras): ResultadoExtrasCsv {
  const erros: ErroLinhaExtra[] = []
  const porChave = new Map<string, ExtraLido>()
  dados.forEach((l, k) => {
    const linha = k + 2
    if (l.every((c) => c.trim() === '')) return // linha em branco (lerCsv com manterVazias): ignora sem erro
    const nome = v(l, m.nome).replace(/\s+/g, ' ')
    if (!nome) return void erros.push({ linha, mensagem: 'Informe o nome' })
    const textoValor = v(l, m.valor)
    const valor = lerValorCentavos(textoValor)
    if (valor != null && (!Number.isFinite(valor) || valor > 100_000_000)) return void erros.push({ linha, mensagem: `Valor inválido: “${textoValor}”` })
    const textoPontos = v(l, m.pontos)
    const pontos = lerPontosCsv(textoPontos)
    if (pontos != null && (!Number.isFinite(pontos) || pontos > 9999.99)) return void erros.push({ linha, mensagem: `Pontos inválidos: “${textoPontos}”` })
    const { datas, invalidas } = lerDatas(v(l, m.dias))
    if (invalidas.length) return void erros.push({ linha, mensagem: `Data inválida: “${invalidas[0]}”` })
    const documento = ouNull(v(l, m.documento))
    const chave = chaveExtra(nome, documento)
    let item = porChave.get(chave)
    if (!item) {
      item = {
        nome: nome.slice(0, 120),
        funcao: ouNull(v(l, m.funcao)),
        telefone: ouNull(v(l, m.telefone)),
        documento,
        valor_diaria_centavos: valor,
        pontos,
        dias_trabalhados: [],
        linhas: [],
      }
      porChave.set(chave, item)
    } else {
      item.funcao ??= ouNull(v(l, m.funcao))
      item.telefone ??= ouNull(v(l, m.telefone))
      item.valor_diaria_centavos ??= valor
      item.pontos ??= pontos
    }
    item.linhas.push(linha)
    for (const data of datas) {
      const dia = { data, valor_centavos: valor, pontos }
      const j = item.dias_trabalhados.findIndex((d) => d.data === data)
      if (j >= 0) item.dias_trabalhados[j] = dia
      else item.dias_trabalhados.push(dia)
    }
  })
  const extras = [...porChave.values()]
  for (const x of extras) x.dias_trabalhados.sort((a, b) => (a.data < b.data ? -1 : a.data > b.data ? 1 : 0))
  return { extras, erros, semPontos: extras.filter((x) => x.pontos == null).length }
}

/** Payload de `extras_importar` (sem os campos só da prévia). */
export function paraImportacao(extras: ExtraLido[]): ExtraImportacao[] {
  return extras.map((x) => ({
    nome: x.nome,
    funcao: x.funcao ?? null,
    telefone: x.telefone ?? null,
    documento: x.documento ?? null,
    valor_diaria_centavos: x.valor_diaria_centavos ?? null,
    pontos: x.pontos,
    ...(x.dias_trabalhados.length
      ? { dias_trabalhados: x.dias_trabalhados.map((d) => ({ data: d.data, valor_centavos: d.valor_centavos, pontos: d.pontos })) }
      : {}),
  }))
}

/** Erros do banco vêm pelo índice do item (1-based): traduz para as linhas do arquivo. */
export function linhasDoItem(extras: ExtraLido[], linhaItem: number): number[] {
  return extras[linhaItem - 1]?.linhas ?? []
}

/** Modelo para baixar (§13: BOM, `;`, `\r\n`). Pontos em branco = pontuação pendente. */
export const MODELO_CSV_EXTRAS =
  '﻿' +
  [
    'Nome;Função;Telefone;Documento;Valor da diária;Pontos;Dias trabalhados',
    'Zé Pereira;Cumim;(21) 99999-0000;123.456.789-00;150,00;;03/09/2026',
    'Marina Costa;Garçom;(21) 98888-1111;987.654.321-00;180,00;6;03/09/2026, 04/09/2026',
    'Rafael Lima;Bar;;;160,00;5;',
  ]
    .map((l) => l + '\r\n')
    .join('')
