/**
 * Importação de reservas por CSV (Tagme ou planilha própria). Funções puras. Dono: frontend.
 *
 * - Aceita separador `;`, `,` ou TAB (detectado pela 1ª linha), aspas duplas (RFC 4180), BOM e `\r\n`.
 * - Reconhece cabeçalhos variados (português/inglês, com/sem acento): Nome/Cliente/Name, Data/Date, Hora/Horário/Time,
 *   Pessoas/Pax/Guests/Party size, Status, Telefone/Phone, E-mail, Mesa/Área, Observação, Código/ID.
 *   O que não for reconhecido o usuário escolhe na prévia (mapeamento manual).
 * - Datas `dd/mm/aaaa`, `dd/mm/aa`, `aaaa-mm-dd` (também com hora junto: `dd/mm/aaaa 20:30`); horas `20:30`, `20h30`, `20h`.
 */

export type CampoReserva =
  | 'nome'
  | 'data'
  | 'hora'
  | 'pessoas'
  | 'status'
  | 'telefone'
  | 'email'
  | 'mesa'
  | 'area'
  | 'observacao'
  | 'id_externo'

export const CAMPOS_RESERVA: { id: CampoReserva; rotulo: string; obrigatorio?: boolean }[] = [
  { id: 'nome', rotulo: 'Nome do cliente', obrigatorio: true },
  { id: 'data', rotulo: 'Data', obrigatorio: true },
  { id: 'hora', rotulo: 'Hora' },
  { id: 'pessoas', rotulo: 'Pessoas' },
  { id: 'status', rotulo: 'Status' },
  { id: 'telefone', rotulo: 'Telefone' },
  { id: 'email', rotulo: 'E-mail' },
  { id: 'mesa', rotulo: 'Mesa' },
  { id: 'area', rotulo: 'Área / ambiente' },
  { id: 'observacao', rotulo: 'Observação' },
  { id: 'id_externo', rotulo: 'Código da reserva' },
]

/** Sinônimos (já normalizados: minúsculas, sem acento, só letras/números/espaço). Ordem importa: o 1º que casar ganha. */
const SINONIMOS: Record<CampoReserva, string[]> = {
  id_externo: ['codigo', 'cod', 'id', 'id reserva', 'codigo reserva', 'codigo da reserva', 'reserva id', 'reservation id', 'booking id', 'localizador', 'code'],
  nome: ['nome', 'cliente', 'nome do cliente', 'nome cliente', 'name', 'customer', 'customer name', 'guest', 'guest name', 'convidado', 'responsavel', 'titular'],
  data: ['data', 'date', 'dia', 'data da reserva', 'data reserva', 'reservation date', 'booking date', 'data hora', 'data e hora', 'datetime', 'date time'],
  hora: ['hora', 'horario', 'time', 'hora da reserva', 'horario da reserva', 'reservation time', 'booking time', 'hour'],
  pessoas: ['pessoas', 'pax', 'guests', 'party size', 'partysize', 'qtd pessoas', 'quantidade de pessoas', 'quantidade', 'qtd', 'qtde', 'n pessoas', 'numero de pessoas', 'lugares', 'people', 'covers', 'tamanho do grupo', 'adultos'],
  status: ['status', 'situacao', 'estado', 'state'],
  telefone: ['telefone', 'celular', 'fone', 'whatsapp', 'phone', 'phone number', 'mobile', 'tel', 'contato'],
  email: ['email', 'e mail', 'mail'],
  mesa: ['mesa', 'mesas', 'table', 'tables', 'n mesa', 'numero da mesa'],
  area: ['area', 'ambiente', 'setor', 'salao', 'local', 'section', 'area preferida'],
  observacao: ['observacao', 'observacoes', 'obs', 'notas', 'nota', 'comentario', 'comentarios', 'notes', 'note', 'comments', 'pedido especial', 'ocasiao', 'occasion'],
}

export function normalizarCabecalho(s: string): string {
  return s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[º°ª#]/g, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

// ----------------------------------------------------------------- leitura
/** Separador mais provável, contando `;` `,` e TAB fora de aspas na 1ª linha não vazia. */
export function detectarSeparador(texto: string): ';' | ',' | '\t' {
  const primeira = texto.replace(/^﻿/, '').split(/\r?\n/).find((l) => l.trim() !== '') ?? ''
  const conta = { ';': 0, ',': 0, '\t': 0 }
  let aspas = false
  for (const ch of primeira) {
    if (ch === '"') aspas = !aspas
    else if (!aspas && (ch === ';' || ch === ',' || ch === '\t')) conta[ch] += 1
  }
  if (conta['\t'] > conta[';'] && conta['\t'] > conta[',']) return '\t'
  return conta[';'] >= conta[','] && conta[';'] > 0 ? ';' : ','
}

/** CSV → matriz de textos (linhas totalmente vazias são descartadas). */
export function lerCsv(texto: string, separador = detectarSeparador(texto)): string[][] {
  const t = texto.replace(/^﻿/, '')
  const linhas: string[][] = []
  let linha: string[] = []
  let campo = ''
  let aspas = false
  for (let i = 0; i < t.length; i++) {
    const ch = t[i]!
    if (aspas) {
      if (ch === '"') {
        if (t[i + 1] === '"') {
          campo += '"'
          i++
        } else aspas = false
      } else campo += ch
      continue
    }
    if (ch === '"' && campo === '') aspas = true
    else if (ch === separador) {
      linha.push(campo)
      campo = ''
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && t[i + 1] === '\n') i++
      linha.push(campo)
      linhas.push(linha)
      linha = []
      campo = ''
    } else campo += ch
  }
  if (campo !== '' || linha.length > 0) {
    linha.push(campo)
    linhas.push(linha)
  }
  return linhas.filter((l) => l.some((c) => c.trim() !== ''))
}

// -------------------------------------------------------------- mapeamento
export type Mapeamento = Record<CampoReserva, number | null>

export function mapeamentoVazio(): Mapeamento {
  return Object.fromEntries(CAMPOS_RESERVA.map((c) => [c.id, null])) as Mapeamento
}

/** Reconhece as colunas pelo nome. Cada coluna vai para no máximo um campo; casamento exato vence casamento parcial. */
export function reconhecerColunas(cabecalho: string[]): Mapeamento {
  const m = mapeamentoVazio()
  const usados = new Set<number>()
  const nomes = cabecalho.map(normalizarCabecalho)
  const ordem: CampoReserva[] = ['id_externo', 'nome', 'data', 'hora', 'pessoas', 'status', 'telefone', 'email', 'mesa', 'area', 'observacao']
  // 1ª passada: igualdade exata
  for (const campo of ordem) {
    const i = nomes.findIndex((n, j) => !usados.has(j) && SINONIMOS[campo].includes(n))
    if (i >= 0) {
      m[campo] = i
      usados.add(i)
    }
  }
  // 2ª passada: contém a palavra (ex.: "Nome completo do cliente", "Horário previsto")
  for (const campo of ordem) {
    if (m[campo] != null) continue
    const i = nomes.findIndex(
      (n, j) => !usados.has(j) && SINONIMOS[campo].some((s) => s.length >= 3 && new RegExp(`(^| )${s}( |$)`).test(n)),
    )
    if (i >= 0) {
      m[campo] = i
      usados.add(i)
    }
  }
  return m
}

// --------------------------------------------------------------- conversão
function doisDigitos(n: number): string {
  return String(n).padStart(2, '0')
}

function dataValida(a: number, m: number, d: number): boolean {
  if (a < 2000 || a > 2100 || m < 1 || m > 12 || d < 1) return false
  return d <= new Date(Date.UTC(a, m, 0)).getUTCDate()
}

/** 'dd/mm/aaaa', 'dd/mm/aa', 'dd-mm-aaaa', 'aaaa-mm-dd' (com ou sem hora depois) → 'AAAA-MM-DD' | null. */
export function lerDataReserva(s: string): string | null {
  const t = s.trim()
  let a: number, m: number, d: number
  let r = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s]|$)/.exec(t)
  if (r) {
    a = Number(r[1])
    m = Number(r[2])
    d = Number(r[3])
  } else {
    r = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})(?:[\s,T]|$)/.exec(t)
    if (!r) return null
    d = Number(r[1])
    m = Number(r[2])
    a = Number(r[3])
    if (a < 100) a += 2000
  }
  return dataValida(a, m, d) ? `${a}-${doisDigitos(m)}-${doisDigitos(d)}` : null
}

/** '20:30', '20:30:00', '20h30', '20h', '8:05 PM' → 'HH:MM' | null. Aceita a hora dentro de um texto de data-hora. */
export function lerHoraReserva(s: string): string | null {
  const t = s
    .trim()
    .toLowerCase()
    .replace(/^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})[\st,]*/, '')
  const r = /^(\d{1,2})(?:\s*(?::|h)\s*(\d{2})?)?(?::\d{2}(?:\.\d+)?)?\s*(am|pm)?\s*(?:h|hs|hrs)?(?:[+-]\d{2}:?\d{2}|z)?$/.exec(t)
  if (!r) return null
  let h = Number(r[1])
  const min = r[2] == null ? 0 : Number(r[2])
  if (r[3] === 'pm' && h < 12) h += 12
  if (r[3] === 'am' && h === 12) h = 0
  if (h > 23 || min > 59) return null
  return `${doisDigitos(h)}:${doisDigitos(min)}`
}

/** '4', '4 pessoas', '4 pax', '2+1' → 4 / 4 / 4 / 3; vazio → null; inválido → NaN. */
export function lerPessoas(s: string): number | null {
  const t = s.trim()
  if (!t) return null
  const partes = t.match(/\d+/g)
  if (!partes) return Number.NaN
  const total = /\+/.test(t) ? partes.reduce((s2, p) => s2 + Number(p), 0) : Number(partes[0])
  return total
}

/** Status canônico da reserva (o banco guarda exatamente estes valores). */
export type StatusReservaCsv = 'confirmada' | 'pendente' | 'cancelada' | 'sentada' | 'concluida' | 'nao_compareceu'

const STATUS: [RegExp, StatusReservaCsv][] = [
  [/cancel|desist|recus|rejeit|declin|estorn/, 'cancelada'],
  [/no ?show|nao (veio|compareceu)|ausente|faltou|nao apareceu/, 'nao_compareceu'],
  [/sentad|seated|chegou|arrived|check ?in|na mesa|em atendimento/, 'sentada'],
  [/finaliz|conclu|complet|encerr|finished|done|saiu|left/, 'concluida'],
  [/pend|aguard|espera|waiting|wait|solicit|request|nova|novo|new|lista/, 'pendente'],
  [/confirm|aprov|aceit|accept|reservad|booked|agendad|ativa|ok/, 'confirmada'],
]

/** Texto livre de status (Tagme/planilha) → status canônico; vazio → 'confirmada'. */
export function lerStatusReserva(s: string | null | undefined): StatusReservaCsv {
  const t = normalizarCabecalho(s ?? '')
  if (!t) return 'confirmada'
  for (const [re, st] of STATUS) if (re.test(t)) return st
  return 'confirmada'
}

export interface ReservaLida {
  /** número da linha no arquivo (1 = cabeçalho) */
  linha: number
  id_externo: string | null
  nome: string
  data: string
  hora: string | null
  pessoas: number
  status: StatusReservaCsv
  telefone: string | null
  email: string | null
  mesa: string | null
  area: string | null
  observacao: string | null
}

export interface ErroLinha {
  linha: number
  mensagem: string
}

export interface ResultadoConversao {
  reservas: ReservaLida[]
  erros: ErroLinha[]
}

function valor(l: string[], i: number | null): string {
  return i == null ? '' : (l[i] ?? '').trim()
}
const ouNull = (s: string) => (s === '' ? null : s)

/** Converte as linhas de dados (sem o cabeçalho) usando o mapeamento. `pessoas` vazio → 2. */
export function converterReservas(dados: string[][], m: Mapeamento): ResultadoConversao {
  const reservas: ReservaLida[] = []
  const erros: ErroLinha[] = []
  dados.forEach((l, k) => {
    const linha = k + 2
    const nome = valor(l, m.nome)
    const textoData = valor(l, m.data)
    if (!nome) return void erros.push({ linha, mensagem: 'Sem nome do cliente' })
    const data = lerDataReserva(textoData)
    if (!data) return void erros.push({ linha, mensagem: textoData ? `Data inválida: “${textoData}”` : 'Sem data' })
    const textoHora = valor(l, m.hora)
    const hora = textoHora ? lerHoraReserva(textoHora) : /\d{1,2}[:h]\d{2}/.test(textoData) ? lerHoraReserva(textoData) : null
    if (textoHora && !hora) return void erros.push({ linha, mensagem: `Hora inválida: “${textoHora}”` })
    const pessoasLidas = lerPessoas(valor(l, m.pessoas))
    if (pessoasLidas != null && (!Number.isFinite(pessoasLidas) || pessoasLidas < 1 || pessoasLidas > 500))
      return void erros.push({ linha, mensagem: `Quantidade de pessoas inválida: “${valor(l, m.pessoas)}”` })
    reservas.push({
      linha,
      id_externo: ouNull(valor(l, m.id_externo)),
      nome: nome.slice(0, 200),
      data,
      hora,
      pessoas: pessoasLidas ?? 2,
      status: lerStatusReserva(valor(l, m.status)),
      telefone: ouNull(valor(l, m.telefone)),
      email: ouNull(valor(l, m.email)),
      mesa: ouNull(valor(l, m.mesa)),
      area: ouNull(valor(l, m.area)),
      observacao: ouNull(valor(l, m.observacao)),
    })
  })
  return { reservas, erros }
}

/** Modelo para baixar (mesmo formato do §13: BOM, `;`, `\r\n`). */
export const MODELO_CSV_RESERVAS =
  '﻿' +
  [
    'Código;Nome;Data;Hora;Pessoas;Status;Telefone;E-mail;Mesa;Área;Observação',
    'T-1001;Maria Oliveira;20/11/2026;20:00;4;Confirmada;(11) 98888-7777;maria@exemplo.com;12;Varanda;Aniversário',
    'T-1002;João Pereira;20/11/2026;21:30;2;Pendente;(11) 97777-6666;;;Salão;',
    'T-1003;Ana Costa;21/11/2026;19:00;6;Cancelada;;;;;Cancelou por telefone',
  ]
    .map((l) => l + '\r\n')
    .join('')
