/**
 * Importação do AFD pelo site (RHiD → Relatórios → Relatório de AFDs). O arquivo é lido NO NAVEGADOR com a mesma lib do N8N
 * (`n8n/controlid/lib/afd.mjs`, fonte única: layouts 671/1510, marcações tipo 3/7, empregados tipo 5) e as marcações vão para
 * `ponto_importar_afd` em lotes.
 */
import { lerAfd, type EmpregadoAfd, type LeituraAfd, type MarcacaoAfd } from '../../../n8n/controlid/lib/afd.mjs'

export type { EmpregadoAfd, LeituraAfd, MarcacaoAfd }
export { lerAfd }

/** Marcações por chamada (o banco aceita até 5000). */
export const LOTE_AFD = 2000
/** Tamanho máximo do arquivo aceito pela tela. */
export const LIMITE_ARQUIVO_AFD = 20 * 1024 * 1024

/** AFD é Latin-1 (o RHiD grava "Júnior" em ISO-8859-1): lê como Windows-1252; só com BOM UTF-8 lê como UTF-8. */
export function decodificarAfd(bytes: ArrayBuffer): string {
  const u8 = new Uint8Array(bytes)
  if (u8[0] === 0xef && u8[1] === 0xbb && u8[2] === 0xbf) return new TextDecoder('utf-8').decode(u8.subarray(3))
  return new TextDecoder('windows-1252').decode(u8)
}

export interface PessoaAfd {
  /** CPF ou PIS (11 dígitos) — é o `user_id_externo` do usuário do relógio. */
  documento: string
  tipo: 'cpf' | 'pis'
  nome: string | null
  marcacoes: number
}

export interface PreviaAfd {
  leitura: LeituraAfd
  /** Datas (do relógio) da primeira e da última marcação. */
  inicio: string | null
  fim: string | null
  pessoas: PessoaAfd[]
}

/** Data AAAA-MM-DD da marcação (hora de parede do relógio). */
export function dataDaMarcacao(m: MarcacaoAfd): string {
  return (m.instante ?? m.instante_local ?? '').slice(0, 10)
}

export function documentoDaMarcacao(m: { cpf?: string; pis?: string }): string | null {
  return m.cpf ?? m.pis ?? null
}

/** Lê o texto do AFD e resume para a prévia: período, pessoas (CPF/PIS + nome do registro tipo 5) e contagens. */
export function previaAfd(texto: string): PreviaAfd {
  const leitura = lerAfd(texto)
  const nomes = new Map<string, string | null>()
  for (const e of leitura.empregados) nomes.set((e.cpf ?? e.pis)!, e.nome)
  const pessoas = new Map<string, PessoaAfd>()
  let inicio: string | null = null
  let fim: string | null = null
  for (const m of leitura.marcacoes) {
    const d = dataDaMarcacao(m)
    if (d && (inicio == null || d < inicio)) inicio = d
    if (d && (fim == null || d > fim)) fim = d
    const doc = documentoDaMarcacao(m)
    if (!doc) continue
    const p = pessoas.get(doc) ?? { documento: doc, tipo: m.cpf ? 'cpf' : 'pis', nome: nomes.get(doc) ?? null, marcacoes: 0 }
    p.marcacoes += 1
    pessoas.set(doc, p)
  }
  // empregados do tipo 5 sem marcação no período também entram (aparecem na tela de vínculo)
  for (const e of leitura.empregados) {
    const doc = (e.cpf ?? e.pis)!
    if (!pessoas.has(doc)) pessoas.set(doc, { documento: doc, tipo: e.cpf ? 'cpf' : 'pis', nome: e.nome, marcacoes: 0 })
  }
  const lista = [...pessoas.values()].sort((a, b) => b.marcacoes - a.marcacoes || (a.nome ?? '').localeCompare(b.nome ?? '', 'pt-BR'))
  return { leitura, inicio, fim, pessoas: lista }
}

/** Itens de `ponto_importar_afd`: marcações em lotes; os empregados vão só no primeiro lote. */
export function lotesAfd(leitura: LeituraAfd, tamanho = LOTE_AFD) {
  const empregados = leitura.empregados.map((e) => (e.cpf ? { cpf: e.cpf, nome: e.nome } : { pis: e.pis, nome: e.nome }))
  const lotes: { marcacoes: MarcacaoAfd[]; empregados: typeof empregados }[] = []
  for (let i = 0; i < leitura.marcacoes.length; i += tamanho) {
    lotes.push({ marcacoes: leitura.marcacoes.slice(i, i + tamanho), empregados: i === 0 ? empregados : [] })
  }
  if (lotes.length === 0 && empregados.length > 0) lotes.push({ marcacoes: [], empregados })
  return lotes
}

/** "52998224725" → "529.982.247-25"; PIS → "123.45678.90-1". */
export function formatarDocumento(doc: string | null | undefined, tipo: 'cpf' | 'pis' = 'cpf'): string {
  if (!doc || !/^\d{11}$/.test(doc)) return doc ?? '—'
  return tipo === 'cpf'
    ? `${doc.slice(0, 3)}.${doc.slice(3, 6)}.${doc.slice(6, 9)}-${doc.slice(9)}`
    : `${doc.slice(0, 3)}.${doc.slice(3, 8)}.${doc.slice(8, 10)}-${doc.slice(10)}`
}

/** Mesma regra de `nome_proprio` do banco: "CARLA DE SOUZA" → "Carla de Souza". */
export function nomeProprio(nome: string | null | undefined): string | null {
  const partes = (nome ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return null
  return partes
    .map((p, i) => {
      const min = p.toLocaleLowerCase('pt-BR')
      if (i > 0 && ['da', 'de', 'do', 'das', 'dos', 'e'].includes(min)) return min
      // como o initcap do Postgres: maiúscula no início de cada trecho alfanumérico ("ANA-MARIA" → "Ana-Maria")
      return min.replace(/(^|[^\p{L}\p{N}])(\p{L})/gu, (_t, antes: string, letra: string) => antes + letra.toLocaleUpperCase('pt-BR'))
    })
    .join(' ')
}

// ------------------------------------------------------------------------- .zip do RHiD
/**
 * O RHiD pode entregar o AFD num .zip (o .txt + a assinatura .p7s). Leitor mínimo de zip (diretório central; entradas
 * "store" ou "deflate" via DecompressionStream do navegador): devolve o .txt do AFD (o maior .txt, se houver mais de um).
 */
export async function extrairAfdDoZip(zip: ArrayBuffer): Promise<{ nome: string; bytes: ArrayBuffer }> {
  const v = new DataView(zip)
  const u8 = new Uint8Array(zip)
  // fim do diretório central (assinatura 0x06054b50), procurado de trás para frente (comentário de até 64 KB)
  let fim = -1
  for (let i = u8.length - 22; i >= Math.max(0, u8.length - 22 - 0xffff); i--) {
    if (v.getUint32(i, true) === 0x06054b50) {
      fim = i
      break
    }
  }
  if (fim < 0) throw new Error('Arquivo .zip inválido')
  const total = v.getUint16(fim + 10, true)
  let p = v.getUint32(fim + 16, true)
  const entradas: { nome: string; metodo: number; comprimido: number; local: number }[] = []
  for (let k = 0; k < total; k++) {
    if (v.getUint32(p, true) !== 0x02014b50) throw new Error('Arquivo .zip inválido')
    const metodo = v.getUint16(p + 10, true)
    const comprimido = v.getUint32(p + 20, true)
    const n = v.getUint16(p + 28, true)
    const extra = v.getUint16(p + 30, true)
    const coment = v.getUint16(p + 32, true)
    const local = v.getUint32(p + 42, true)
    const nome = new TextDecoder('windows-1252').decode(u8.subarray(p + 46, p + 46 + n))
    entradas.push({ nome, metodo, comprimido, local })
    p += 46 + n + extra + coment
  }
  const txt = entradas.filter((e) => /\.txt$/i.test(e.nome) && !e.nome.endsWith('/')).sort((a, b) => b.comprimido - a.comprimido)[0]
  if (!txt) throw new Error('O .zip não tem o arquivo .txt do AFD')
  // tamanho comprimido do diretório central (o do cabeçalho local pode vir zerado quando o zip usa descritor de dados)
  const inicio = txt.local + 30 + v.getUint16(txt.local + 26, true) + v.getUint16(txt.local + 28, true)
  const dados = u8.slice(inicio, inicio + txt.comprimido)
  const nomeCurto = txt.nome.split('/').pop() ?? txt.nome
  if (txt.metodo === 0) return { nome: nomeCurto, bytes: dados.buffer }
  if (txt.metodo !== 8) throw new Error('Compactação do .zip não suportada: descompacte e escolha o .txt')
  if (typeof DecompressionStream === 'undefined') throw new Error('Este navegador não abre .zip: descompacte e escolha o .txt')
  const fluxo = new Blob([dados]).stream().pipeThrough(new DecompressionStream('deflate-raw'))
  return { nome: nomeCurto, bytes: await new Response(fluxo).arrayBuffer() }
}

/** Lê o arquivo escolhido (.txt ou .zip do RHiD) e devolve o texto do AFD. */
export async function lerArquivoAfd(nome: string, bytes: ArrayBuffer): Promise<{ nome: string; texto: string }> {
  const u8 = new Uint8Array(bytes)
  const ehZip = /\.zip$/i.test(nome) || (u8[0] === 0x50 && u8[1] === 0x4b && u8[2] === 0x03 && u8[3] === 0x04)
  if (!ehZip) return { nome, texto: decodificarAfd(bytes) }
  const txt = await extrairAfdDoZip(bytes)
  return { nome: `${nome} → ${txt.nome}`, texto: decodificarAfd(txt.bytes) }
}
