/**
 * Escala (rodízio 5x2 mensal) — lógica pura da tela, sem React nem banco. Dono: frontend.
 * Réplica do comportamento do modelo do cliente (docs/referencias/escala-macaw-v3.html):
 * horário digitado (8 → 8h, 11:30 → 11h30), f = folga, fe = férias, vazio = automático;
 * navegação Enter/↓, ↑, ←/→; cópia para o Excel em TSV.
 */

/** Dias da semana com a SEGUNDA no índice 0 (como no modelo). */
export const DIAS_SEMANA = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'] as const
export type DiaSemana = (typeof DIAS_SEMANA)[number]

/** dow do Postgres/JS (0 = domingo) → índice com segunda = 0. */
export function indiceSegunda(dowDomingo: number): number {
  return (((dowDomingo + 6) % 7) + 7) % 7
}
/** índice com segunda = 0 → dow do Postgres/JS (0 = domingo). */
export function dowDomingo(indiceSeg: number): number {
  return (indiceSeg + 1) % 7
}

const HRE = /^(\d{1,2})(?:[:.,h]?(\d{2}))?\s*(?:h|hs|hrs|hr)?$/i

/**
 * Normaliza o que foi digitado numa célula (igual ao `normT` do modelo):
 * '' → '' · 'f'/'folga' → 'F' · 'fe'/'fé'/'ferias'/'férias' → 'FÉ' · '8' → '8h' · '11:30' → '11h30' · '9h00' → '9h'.
 * Texto que não é horário é cortado em 6 caracteres.
 */
export function normT(bruto: unknown): string {
  const s = String(bruto ?? '').trim()
  if (!s) return ''
  const l = s.toLowerCase()
  if (l === 'f' || l === 'folga') return 'F'
  if (['fe', 'fé', 'ferias', 'férias'].includes(l)) return 'FÉ'
  const m = HRE.exec(s)
  if (m && Number(m[1]) <= 23 && (!m[2] || Number(m[2]) <= 59)) return `${Number(m[1])}h${m[2] && m[2] !== '00' ? m[2] : ''}`
  return s.slice(0, 6)
}

/** '8h' → '08:00', '11h30' → '11:30'; qualquer outra coisa → null. */
export function chegadaParaHora(norm: string | null | undefined): string | null {
  const m = /^(\d{1,2})h(\d{2})?$/.exec(norm ?? '')
  if (!m) return null
  return `${m[1]!.padStart(2, '0')}:${m[2] ?? '00'}`
}

/** '08:00' / '08:00:00' → '8h'; '11:30' → '11h30'; null → ''. */
export function horaParaChegada(hora: string | null | undefined): string {
  const m = /^(\d{1,2}):(\d{2})/.exec(hora ?? '')
  if (!m) return ''
  return `${Number(m[1])}h${m[2] !== '00' ? m[2] : ''}`
}

/** Valor válido para "chegada padrão": só horário (F/FÉ/texto livre viram vazio). */
export function chegadaValida(bruto: unknown): string {
  const v = normT(bruto)
  return chegadaParaHora(v) ? v : ''
}

// ------------------------------------------------------------------ estado de um dia

/** Estado efetivo de uma pessoa num dia: trabalha, folga ou férias. */
export type EstadoDia = 'trabalha' | 'folga' | 'ferias'
/** Ajuste manual guardado para o dia (null = automático). */
export type EstadoAjuste = EstadoDia | null

export interface AjusteCelula {
  /** estado forçado (null = segue o automático) */
  estado: EstadoAjuste
  /** chegada só deste dia, 'HH:MM' (null = padrão) */
  chegada: string | null
}

/** Estado efetivo: ajuste vence; senão férias do período; senão folga do rodízio; senão trabalha. */
export function estadoEfetivo(ajuste: EstadoAjuste, folgaAuto: boolean, feriasAuto: boolean): EstadoDia {
  if (ajuste) return ajuste
  if (feriasAuto) return 'ferias'
  if (folgaAuto) return 'folga'
  return 'trabalha'
}

/**
 * Converte o texto digitado numa célula no ajuste a gravar (mesma regra do `commitCell` do modelo):
 * - 'F' → folga (se o automático já é folga e não há férias, vira automático);
 * - 'FÉ' → férias (se o automático já é férias, vira automático);
 * - horário → trabalha com essa chegada (o estado só é forçado se o automático for folga/férias);
 * - vazio → limpa: num dia de trabalho volta ao automático; num dia que mostrava F/FÉ automático, apagar
 *   significa "trabalha" (o modelo faz igual — a célula mostra o estado, apagar o F tira a folga).
 * `chegadaPadrao` ('HH:MM'): digitar a própria chegada padrão não grava chegada do dia.
 */
export function interpretarCelula(
  texto: string,
  automatico: { folga: boolean; ferias: boolean },
  chegadaPadrao: string | null = null,
): AjusteCelula {
  const v = normT(texto)
  const { folga, ferias } = automatico
  if (v === 'F') return { estado: folga && !ferias ? null : 'folga', chegada: null }
  if (v === 'FÉ') return { estado: ferias ? null : 'ferias', chegada: null }
  const hora = chegadaParaHora(v)
  return {
    estado: folga || ferias ? 'trabalha' : null,
    chegada: hora && hora !== chegadaPadrao ? hora : null,
  }
}

/** Texto mostrado na célula. */
export function textoCelula(estado: EstadoDia, chegadaDia: string | null): string {
  if (estado === 'ferias') return 'FÉ'
  if (estado === 'folga') return 'F'
  return horaParaChegada(chegadaDia)
}

// ------------------------------------------------------------------ mês

export interface DiaDoMes {
  dia: number
  /** AAAA-MM-DD */
  data: string
  /** 0 = segunda … 6 = domingo */
  semana: number
  rotulo: DiaSemana
}

/** 'AAAA-MM' → dias do mês (sem fuso: aritmética de calendário em UTC). */
export function diasDoMes(mes: string): DiaDoMes[] {
  const m = /^(\d{4})-(\d{2})$/.exec(mes)
  if (!m) return []
  const ano = Number(m[1])
  const mm = Number(m[2])
  const n = new Date(Date.UTC(ano, mm, 0)).getUTCDate()
  const dias: DiaDoMes[] = []
  for (let d = 1; d <= n; d++) {
    const semana = indiceSegunda(new Date(Date.UTC(ano, mm - 1, d)).getUTCDay())
    dias.push({ dia: d, data: `${m[1]}-${m[2]}-${String(d).padStart(2, '0')}`, semana, rotulo: DIAS_SEMANA[semana]! })
  }
  return dias
}

/** 'AAAA-MM' do mês de uma data ISO. */
export function mesDe(dataIso: string): string {
  return dataIso.slice(0, 7)
}

/** Mês anterior/seguinte. */
export function somarMeses(mes: string, n: number): string {
  const [a, m] = mes.split('-').map(Number) as [number, number]
  const d = new Date(Date.UTC(a, m - 1 + n, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

/** 'novembro de 2026'. */
export function nomeDoMes(mes: string): string {
  const [a, m] = mes.split('-').map(Number) as [number, number]
  return new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(a, m - 1, 15)))
}

/** Folgas da semana base em texto: [0, 1] → 'SEG, TER'. */
export function textoFolgas(indices: number[]): string {
  return [...indices]
    .sort((a, b) => a - b)
    .map((i) => DIAS_SEMANA[i])
    .join(', ')
}

// ------------------------------------------------------------------ navegação na grade

export interface Posicao {
  linha: number
  coluna: number
}

/**
 * Próxima célula ao apertar uma tecla (null = a tecla não navega).
 * ←/→ só andam quando o cursor está no começo/fim do texto (como no modelo). Fora da grade → null.
 */
export function proximaCelula(
  p: Posicao,
  tecla: string,
  limites: { linhas: number; colunas: number },
  cursor: { inicio: number; fim: number; tamanho: number } = { inicio: 0, fim: 0, tamanho: 0 },
): Posicao | null {
  let dl = 0
  let dc = 0
  if (tecla === 'Enter' || tecla === 'ArrowDown') dl = 1
  else if (tecla === 'ArrowUp') dl = -1
  else if (tecla === 'ArrowRight' && cursor.fim >= cursor.tamanho) dc = 1
  else if (tecla === 'ArrowLeft' && cursor.inicio === 0) dc = -1
  else return null
  const n = { linha: p.linha + dl, coluna: p.coluna + dc }
  if (n.linha < 0 || n.coluna < 0 || n.linha >= limites.linhas || n.coluna >= limites.colunas) return { ...p }
  return n
}

/** A tecla é de navegação (o componente deve gravar a célula e mover o foco). */
export function teclaNavega(tecla: string): boolean {
  return ['Enter', 'ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight'].includes(tecla)
}

// ------------------------------------------------------------------ TSV (Copiar para Excel)

export interface LinhaTsv {
  nome: string
  /** texto de cada dia; célula de trabalho vazia → cai na chegada padrão */
  celulas: string[]
  chegadaPadrao: string
  folgas: number
  ferias: number
}
export interface SecaoTsv {
  nome: string
  linhas: LinhaTsv[]
}

/** Remove tabulação/quebra de linha (quebrariam as colunas). */
function limpo(s: string): string {
  return s.replace(/[\t\r\n]+/g, ' ').trim()
}

/**
 * Monta o TSV igual ao do modelo: cabeçalho "Nome · 1 SEG · … · Folgas", uma linha com o nome de cada setor,
 * as pessoas (célula vazia de trabalho = chegada padrão; total de folgas com "+nFÉ") e a linha "Na escala".
 */
export function montarTsv(dias: DiaDoMes[], secoes: SecaoTsv[], naEscala: number[]): string {
  const linhas: string[] = []
  linhas.push(['Nome', ...dias.map((d) => `${d.dia} ${d.rotulo}`), 'Folgas'].join('\t'))
  for (const s of secoes) {
    linhas.push(limpo(s.nome))
    for (const l of s.linhas) {
      const total = `${l.folgas}${l.ferias ? ` +${l.ferias}FÉ` : ''}`
      linhas.push([limpo(l.nome), ...dias.map((_, j) => limpo(l.celulas[j] || l.chegadaPadrao || '')), total].join('\t'))
    }
  }
  linhas.push(['Na escala', ...dias.map((_, j) => String(naEscala[j] ?? 0)), ''].join('\t'))
  return linhas.join('\n')
}
