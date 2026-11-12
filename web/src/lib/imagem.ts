/**
 * Compressão de imagem no navegador (sem dependência): mantém a proporção, reduz o maior lado e gera JPEG,
 * baixando a qualidade até caber no limite. Usada nas fotos de documentos (ocorrências disciplinares).
 * Mesma técnica da foto facial (componentes/dominio/FotoFacial.tsx), sem o recorte.
 */

export const TIPOS_IMAGEM_ACEITOS = 'image/jpeg,image/png,image/webp,image/heic,image/heif'

export function ehImagem(arquivo: Pick<File, 'type' | 'name'>): boolean {
  return /^image\/(jpeg|png|webp|heic|heif)$/i.test(arquivo.type) || /\.(jpe?g|png|webp|heic|heif)$/i.test(arquivo.name)
}

/** Dimensões finais mantendo a proporção, com o maior lado ≤ ladoMaximo (nunca amplia). */
export function dimensoesReduzidas(largura: number, altura: number, ladoMaximo: number): { largura: number; altura: number } {
  const escala = Math.min(1, ladoMaximo / Math.max(largura, altura, 1))
  return { largura: Math.max(1, Math.round(largura * escala)), altura: Math.max(1, Math.round(altura * escala)) }
}

export function carregarImagem(arquivo: Blob): Promise<HTMLImageElement> {
  return new Promise((ok, falha) => {
    const url = URL.createObjectURL(arquivo)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      ok(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      falha(new Error('Não consegui abrir esta imagem. Tente JPG ou PNG.'))
    }
    img.src = url
  })
}

export async function comprimirImagem(
  arquivo: Blob,
  { ladoMaximo = 1800, limiteBytes = 1_500_000 }: { ladoMaximo?: number; limiteBytes?: number } = {},
): Promise<Blob> {
  const img = await carregarImagem(arquivo)
  const { largura, altura } = dimensoesReduzidas(img.naturalWidth, img.naturalHeight, ladoMaximo)
  const canvas = document.createElement('canvas')
  canvas.width = largura
  canvas.height = altura
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Seu navegador não conseguiu processar a imagem')
  ctx.fillStyle = '#ffffff' // PNG com transparência vira fundo branco (documento)
  ctx.fillRect(0, 0, largura, altura)
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(img, 0, 0, largura, altura)
  for (const qualidade of [0.85, 0.75, 0.65, 0.55, 0.45]) {
    const blob = await new Promise<Blob | null>((ok) => canvas.toBlob(ok, 'image/jpeg', qualidade))
    if (blob && blob.size <= limiteBytes) return blob
  }
  throw new Error('A imagem ficou grande demais mesmo comprimida. Tente outra foto.')
}
