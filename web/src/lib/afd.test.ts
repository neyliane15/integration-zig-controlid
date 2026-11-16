import { readFileSync } from 'node:fs'
import { deflateRawSync } from 'node:zlib'
import { describe, expect, it } from 'vitest'
import { lerAfd as lerAfdN8n } from '../../../n8n/controlid/lib/afd.mjs'
import { decodificarAfd, extrairAfdDoZip, formatarDocumento, lerAfd, lerArquivoAfd, lotesAfd, nomeProprio, previaAfd } from './afd'

const dados = (nome: string) => readFileSync(new URL(`../../../n8n/controlid/lib/__dados__/${nome}`, import.meta.url))
const bytes = (nome: string) => new Uint8Array(dados(nome)).buffer

describe('AFD no navegador', () => {
  it('usa a mesma lib do N8N (fonte única)', () => {
    expect(lerAfd).toBe(lerAfdN8n)
  })

  it('prévia do AFD 671: período, pessoas com o nome do registro tipo 5', () => {
    const p = previaAfd(decodificarAfd(bytes('afd-671.txt')))
    expect(p.leitura.marcacoes).toHaveLength(6)
    expect(p.inicio).toBe('2026-10-05')
    expect(p.fim).toBe('2026-10-06')
    expect(p.pessoas.map((x) => [x.documento, x.nome, x.marcacoes])).toEqual([
      ['52998224725', null, 2],
      ['11144477735', null, 2],
      ['15350946056', null, 1],
      ['39053344705', 'CARLA DIAS', 1],
    ])
  })

  it('prévia do AFD 1510: PIS', () => {
    const p = previaAfd(decodificarAfd(bytes('afd-1510.txt')))
    expect(p.pessoas.map((x) => [x.tipo, x.documento, x.nome, x.marcacoes])).toEqual([
      ['pis', '12345678901', 'ANA SOUZA', 2],
      ['pis', '10987654321', null, 1],
    ])
  })

  it('arquivo em Latin-1 (nome com acento) é decodificado como Windows-1252', () => {
    const linha = '0000000015' + '2026-10-01T09:00:00-0300' + 'I' + '052998224725' + 'JOÃO CONCEIÇÃO'.padEnd(52, ' ') + '0000'
    const latin1 = new Uint8Array([...linha].map((c) => c.charCodeAt(0)))
    expect(lerAfd(decodificarAfd(latin1.buffer)).empregados[0]?.nome).toBe('JOÃO CONCEIÇÃO')
    const bom = new Uint8Array([0xef, 0xbb, 0xbf, ...new TextEncoder().encode('ação')])
    expect(decodificarAfd(bom.buffer)).toBe('ação')
  })

  it('lotes: empregados só no primeiro; sem marcações mas com empregados → um lote', () => {
    const leitura = lerAfd(dados('afd-671.txt').toString('latin1'))
    const lotes = lotesAfd(leitura, 4)
    expect(lotes.map((l) => l.marcacoes.length)).toEqual([4, 2])
    expect(lotes[0]!.empregados).toEqual([{ cpf: '39053344705', nome: 'CARLA DIAS' }])
    expect(lotes[1]!.empregados).toEqual([])
    expect(lotesAfd({ ...leitura, marcacoes: [] })).toHaveLength(1)
    expect(lotesAfd({ ...leitura, marcacoes: [], empregados: [] })).toHaveLength(0)
  })

  it('nome próprio (mesma regra do banco) e documento formatado', () => {
    expect(nomeProprio('  MARIA  DA SILVA E SOUZA ')).toBe('Maria da Silva e Souza')
    expect(nomeProprio('ANA-MARIA DE LIMA')).toBe('Ana-Maria de Lima')
    expect(nomeProprio('DE LIMA')).toBe('De Lima')
    expect(nomeProprio('')).toBeNull()
    expect(formatarDocumento('52998224725')).toBe('529.982.247-25')
    expect(formatarDocumento('12345678901', 'pis')).toBe('123.45678.90-1')
    expect(formatarDocumento(null)).toBe('—')
  })

  it('AFD real do RHiD (REP-P): sem marcações, 7 empregados com acento em Latin-1', () => {
    const p = previaAfd(decodificarAfd(bytes('afd-671-rep-p-rhid.txt')))
    expect(p.leitura.marcacoes).toHaveLength(0)
    expect(p.leitura.ignoradas).toHaveLength(0)
    expect(p.pessoas).toHaveLength(7)
    expect(p.pessoas.find((x) => x.documento === '46821497095')?.nome).toBe('Funcionário Sete Acentuado')
    expect(lotesAfd(p.leitura)).toHaveLength(1) // só os empregados
  })
})

/** Zip mínimo (local + central + fim) com as entradas dadas; método 8 = deflate, 0 = store. */
function zip(entradas: { nome: string; dados: Uint8Array; metodo: 0 | 8 }[]): ArrayBuffer {
  const partes: Uint8Array[] = []
  const central: Uint8Array[] = []
  let deslocamento = 0
  for (const e of entradas) {
    const corpo = e.metodo === 8 ? new Uint8Array(deflateRawSync(e.dados)) : e.dados
    const nome = new TextEncoder().encode(e.nome)
    const local = new DataView(new ArrayBuffer(30))
    local.setUint32(0, 0x04034b50, true)
    local.setUint16(8, e.metodo, true)
    local.setUint32(18, 0, true) // tamanho zerado (como no descritor de dados): o leitor usa o diretório central
    local.setUint16(26, nome.length, true)
    partes.push(new Uint8Array(local.buffer), nome, corpo)
    const c = new DataView(new ArrayBuffer(46))
    c.setUint32(0, 0x02014b50, true)
    c.setUint16(10, e.metodo, true)
    c.setUint32(20, corpo.length, true)
    c.setUint32(24, e.dados.length, true)
    c.setUint16(28, nome.length, true)
    c.setUint32(42, deslocamento, true)
    central.push(new Uint8Array(c.buffer), nome)
    deslocamento += 30 + nome.length + corpo.length
  }
  const tamanhoCentral = central.reduce((s, x) => s + x.length, 0)
  const fim = new DataView(new ArrayBuffer(22))
  fim.setUint32(0, 0x06054b50, true)
  fim.setUint16(8, entradas.length, true)
  fim.setUint16(10, entradas.length, true)
  fim.setUint32(12, tamanhoCentral, true)
  fim.setUint32(16, deslocamento, true)
  const tudo = [...partes, ...central, new Uint8Array(fim.buffer)]
  const saida = new Uint8Array(tudo.reduce((s, x) => s + x.length, 0))
  let i = 0
  for (const x of tudo) {
    saida.set(x, i)
    i += x.length
  }
  return saida.buffer
}

describe('AFD em .zip (RHiD entrega o .txt + a assinatura .p7s)', () => {
  const txt = new Uint8Array(dados('afd-671-rep-p-rhid.txt'))
  it('extrai o .txt (deflate) e ignora o .p7s', async () => {
    const z = zip([
      { nome: 'AFD_assinatura.p7s', dados: new Uint8Array([1, 2, 3]), metodo: 0 },
      { nome: 'pasta/AFD00001.txt', dados: txt, metodo: 8 },
    ])
    const r = await extrairAfdDoZip(z)
    expect(r.nome).toBe('AFD00001.txt')
    expect(new Uint8Array(r.bytes)).toEqual(txt)
    const lido = await lerArquivoAfd('afd.zip', z)
    expect(lido.nome).toBe('afd.zip → AFD00001.txt')
    expect(lerAfd(lido.texto).empregados).toHaveLength(7)
  })
  it('store, .zip sem .txt e arquivo que não é zip', async () => {
    expect((await extrairAfdDoZip(zip([{ nome: 'a.txt', dados: txt, metodo: 0 }]))).bytes.byteLength).toBe(txt.length)
    await expect(extrairAfdDoZip(zip([{ nome: 'a.p7s', dados: txt, metodo: 0 }]))).rejects.toThrow('O .zip não tem o arquivo .txt do AFD')
    await expect(extrairAfdDoZip(new Uint8Array(30).buffer)).rejects.toThrow('Arquivo .zip inválido')
    expect((await lerArquivoAfd('afd.txt', txt.buffer)).texto.startsWith('0000000001')).toBe(true)
  })
})
