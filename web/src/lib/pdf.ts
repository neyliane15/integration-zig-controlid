/**
 * PDF a partir de um pedaço da tela, mantendo o visual do app (cores, fontes, selos): o elemento é desenhado numa imagem
 * (html-to-image) e cada fatia vira uma página A4 deitada de um PDF montado aqui mesmo (só imagens JPEG, sem dependência
 * de biblioteca de PDF).
 */
import { toCanvas } from 'html-to-image'

const A4_DEITADO = { largura: 842, altura: 595 } // pontos (1/72")
const MARGEM = 24

const texto = (s: string) => new TextEncoder().encode(s)

function base64ParaBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

/** Monta um PDF com uma imagem JPEG por página (ajustada à página, centralizada no topo). */
export function pdfDeJpegs(paginas: { jpeg: Uint8Array; largura: number; altura: number }[], titulo = 'Documento'): Blob {
  const { largura: W, altura: H } = A4_DEITADO
  const partes: Uint8Array[] = []
  const offsets: number[] = []
  let pos = 0
  const add = (b: Uint8Array) => {
    partes.push(b)
    pos += b.length
  }
  const obj = (n: number, corpo: Uint8Array[] | string) => {
    offsets[n] = pos
    add(texto(`${n} 0 obj\n`))
    if (typeof corpo === 'string') add(texto(corpo))
    else corpo.forEach(add)
    add(texto('\nendobj\n'))
  }
  add(texto('%PDF-1.4\n%âãÏÓ\n'))
  const n = paginas.length
  // 1 catálogo, 2 páginas, 3 info; por página k: página 4+3k, conteúdo 5+3k, imagem 6+3k
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>')
  obj(2, `<< /Type /Pages /Count ${n} /Kids [${paginas.map((_, k) => `${4 + 3 * k} 0 R`).join(' ')}] >>`)
  const tituloPdf = titulo.replace(/[()\\]/g, ' ').replace(/[^\x20-\x7e]/g, (c) => c.normalize('NFD').replace(/[^\x20-\x7e]/g, ''))
  obj(3, `<< /Title (${tituloPdf}) /Producer (Meu Dia de Gerente) >>`)
  paginas.forEach((p, k) => {
    const escala = Math.min((W - 2 * MARGEM) / p.largura, (H - 2 * MARGEM) / p.altura)
    const w = p.largura * escala
    const h = p.altura * escala
    const x = (W - w) / 2
    const y = H - MARGEM - h
    const conteudo = `q ${w.toFixed(2)} 0 0 ${h.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)} cm /Im${k} Do Q`
    obj(4 + 3 * k, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /XObject << /Im${k} ${6 + 3 * k} 0 R >> >> /Contents ${5 + 3 * k} 0 R >>`)
    obj(5 + 3 * k, `<< /Length ${conteudo.length} >>\nstream\n${conteudo}\nendstream`)
    obj(6 + 3 * k, [
      texto(`<< /Type /XObject /Subtype /Image /Width ${p.largura} /Height ${p.altura} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n`),
      p.jpeg,
      texto('\nendstream'),
    ])
  })
  const total = 4 + 3 * n
  const inicioXref = pos
  let xref = `xref\n0 ${total}\n0000000000 65535 f \n`
  for (let i = 1; i < total; i++) xref += `${String(offsets[i] ?? 0).padStart(10, '0')} 00000 n \n`
  add(texto(xref))
  add(texto(`trailer\n<< /Size ${total} /Root 1 0 R /Info 3 0 R >>\nstartxref\n${inicioXref}\n%%EOF\n`))
  return new Blob(partes as BlobPart[], { type: 'application/pdf' })
}

/**
 * Desenha `elemento` (já no documento, para herdar o tema) e baixa como PDF A4 deitado. Conteúdo mais alto que uma
 * página é fatiado em várias páginas.
 */
export async function baixarElementoComoPdf(elemento: HTMLElement, nomeArquivo: string, titulo: string): Promise<void> {
  const fundo = getComputedStyle(document.body).backgroundColor || '#ffffff'
  // o elemento pode estar fora da tela (cópia montada para o PDF): a imagem é desenhada como se estivesse no lugar
  const canvas = await toCanvas(elemento, {
    pixelRatio: 2,
    backgroundColor: fundo,
    cacheBust: true,
    width: elemento.scrollWidth,
    height: elemento.scrollHeight,
    style: { position: 'static', left: '0', top: '0', margin: '0' },
  })
  const proporcaoPagina = (A4_DEITADO.altura - 2 * MARGEM) / (A4_DEITADO.largura - 2 * MARGEM)
  const alturaFatia = Math.max(1, Math.floor(canvas.width * proporcaoPagina))
  const paginas: { jpeg: Uint8Array; largura: number; altura: number }[] = []
  for (let y = 0; y < canvas.height; y += alturaFatia) {
    const h = Math.min(alturaFatia, canvas.height - y)
    const fatia = document.createElement('canvas')
    fatia.width = canvas.width
    fatia.height = h
    const ctx = fatia.getContext('2d')
    if (!ctx) throw new Error('Não foi possível gerar o PDF neste navegador')
    ctx.fillStyle = fundo
    ctx.fillRect(0, 0, fatia.width, fatia.height)
    ctx.drawImage(canvas, 0, y, canvas.width, h, 0, 0, canvas.width, h)
    const url = fatia.toDataURL('image/jpeg', 0.92)
    paginas.push({ jpeg: base64ParaBytes(url.slice(url.indexOf(',') + 1)), largura: fatia.width, altura: fatia.height })
  }
  const blob = pdfDeJpegs(paginas, titulo)
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = nomeArquivo
  document.body.appendChild(a)
  a.click()
  a.remove()
  window.setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
}
