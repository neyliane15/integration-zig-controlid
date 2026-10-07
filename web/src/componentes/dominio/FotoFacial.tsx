/**
 * Foto facial do funcionário (adendo envio Control iD, A.4): escolher imagem, recortar (zoom/posição),
 * comprimir no navegador (JPEG, ≤ 1024 px, ≤ 2 MB), prévia, enviar ao Storage. Dono: frontend-2.
 */
import { useEffect, useId, useRef, useState } from 'react'
import { Camera, ImageOff, Trash2, Upload } from 'lucide-react'
import { Botao, Modal } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useDefinirFoto, useRemoverFoto, useUrlFoto } from '@/consultas/funcionarios'

const LADO_MAXIMO = 1024
const PROPORCAO = 3 / 4 // largura / altura (retrato)
const LIMITE_BYTES = 2 * 1024 * 1024

export interface Recorte {
  zoom: number // 1..3
  x: number // -1..1 (deslocamento horizontal relativo à folga)
  y: number // -1..1
}

/** Retângulo de origem (em px da imagem) para o recorte retrato 3:4. */
export function calcularRecorte(largura: number, altura: number, r: Recorte) {
  let h = altura
  let w = h * PROPORCAO
  if (w > largura) {
    w = largura
    h = w / PROPORCAO
  }
  w /= r.zoom
  h /= r.zoom
  const folgaX = (largura - w) / 2
  const folgaY = (altura - h) / 2
  return { sx: folgaX + r.x * folgaX, sy: folgaY + r.y * folgaY, sw: w, sh: h }
}

async function gerarJpeg(img: HTMLImageElement, r: Recorte): Promise<Blob> {
  const { sx, sy, sw, sh } = calcularRecorte(img.naturalWidth, img.naturalHeight, r)
  const escala = Math.min(1, LADO_MAXIMO / Math.max(sw, sh))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(sw * escala))
  canvas.height = Math.max(1, Math.round(sh * escala))
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Seu navegador não conseguiu processar a imagem')
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height)
  for (const qualidade of [0.88, 0.8, 0.7, 0.6, 0.5]) {
    const blob = await new Promise<Blob | null>((ok) => canvas.toBlob(ok, 'image/jpeg', qualidade))
    if (blob && blob.size <= LIMITE_BYTES) return blob
  }
  throw new Error('A imagem ficou grande demais mesmo comprimida. Tente outra foto.')
}

export function FotoFacial({
  funcionarioId,
  caminho,
  editavel,
  nome,
}: {
  funcionarioId: string
  caminho: string | null
  editavel: boolean
  nome: string
}) {
  const avisos = useAvisos()
  const url = useUrlFoto(caminho)
  const definir = useDefinirFoto()
  const remover = useRemoverFoto()
  const entrada = useRef<HTMLInputElement>(null)
  const [origem, setOrigem] = useState<{ img: HTMLImageElement; url: string } | null>(null)
  const [recorte, setRecorte] = useState<Recorte>({ zoom: 1, x: 0, y: 0 })
  const previa = useRef<HTMLCanvasElement>(null)
  const id = useId()

  // desenha a prévia do recorte
  useEffect(() => {
    const c = previa.current
    if (!origem || !c) return
    const ctx = c.getContext('2d')
    if (!ctx) return
    const { sx, sy, sw, sh } = calcularRecorte(origem.img.naturalWidth, origem.img.naturalHeight, recorte)
    ctx.clearRect(0, 0, c.width, c.height)
    ctx.drawImage(origem.img, sx, sy, sw, sh, 0, 0, c.width, c.height)
    // guia oval do rosto
    ctx.strokeStyle = 'rgba(232,200,120,0.8)'
    ctx.setLineDash([6, 6])
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.ellipse(c.width / 2, c.height * 0.45, c.width * 0.3, c.height * 0.3, 0, 0, Math.PI * 2)
    ctx.stroke()
  }, [origem, recorte])

  useEffect(() => () => {
    if (origem) URL.revokeObjectURL(origem.url)
  }, [origem])

  const escolher = (arquivo: File | undefined) => {
    if (!arquivo) return
    if (!/^image\/(jpeg|png|webp|heic|heif)$/i.test(arquivo.type) && !/\.(jpe?g|png|webp)$/i.test(arquivo.name)) {
      avisos.erro('Escolha uma imagem JPG ou PNG')
      return
    }
    const u = URL.createObjectURL(arquivo)
    const img = new Image()
    img.onload = () => {
      setRecorte({ zoom: 1, x: 0, y: 0 })
      setOrigem({ img, url: u })
    }
    img.onerror = () => {
      URL.revokeObjectURL(u)
      avisos.erro('Não consegui abrir esta imagem')
    }
    img.src = u
  }

  const salvar = async () => {
    if (!origem) return
    try {
      const blob = await gerarJpeg(origem.img, recorte)
      await definir.mutateAsync({ funcionarioId, arquivo: blob, anterior: caminho })
      avisos.sucesso('Foto salva. Ela vai para os equipamentos com envio de foto ligado.')
      setOrigem(null)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const apagar = async () => {
    const ok = await avisos.confirmar({
      titulo: 'Remover a foto?',
      mensagem: 'A foto também será apagada dos equipamentos com envio de foto ligado.',
      textoConfirmar: 'Remover',
      perigo: true,
    })
    if (!ok) return
    try {
      await remover.mutateAsync({ funcionarioId, caminho })
      avisos.sucesso('Foto removida')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="flex flex-wrap items-start gap-4">
      <div className="grid aspect-[3/4] w-28 shrink-0 place-items-center overflow-hidden rounded-entrada border border-borda bg-entrada">
        {caminho && url.data ? (
          <img src={url.data} alt={`Foto facial de ${nome}`} className="size-full object-cover" />
        ) : (
          <ImageOff aria-hidden className="size-8 text-lavanda-escuro" />
        )}
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <p className="text-sm text-lavanda">
          {caminho ? 'Foto cadastrada.' : 'Sem foto.'} Rosto de frente, bem iluminado, sem óculos escuros nem boné.
        </p>
        {editavel && (
          <div className="flex flex-wrap gap-2">
            <input
              ref={entrada}
              id={id}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              capture="user"
              className="sr-only"
              onChange={(e) => {
                escolher(e.target.files?.[0])
                e.target.value = ''
              }}
            />
            <Botao variante="secundario" tamanho="p" icone={caminho ? <Camera aria-hidden className="size-4" /> : <Upload aria-hidden className="size-4" />} onClick={() => entrada.current?.click()}>
              {caminho ? 'Trocar foto' : 'Enviar foto'}
            </Botao>
            {caminho && (
              <Botao variante="fantasma" tamanho="p" icone={<Trash2 aria-hidden className="size-4" />} carregando={remover.isPending} onClick={apagar}>
                Remover
              </Botao>
            )}
          </div>
        )}
      </div>

      <Modal
        aberto={!!origem}
        aoFechar={() => setOrigem(null)}
        titulo="Ajustar a foto"
        rodape={
          <>
            <Botao variante="secundario" onClick={() => setOrigem(null)}>
              Cancelar
            </Botao>
            <Botao carregando={definir.isPending} onClick={salvar}>
              Salvar foto
            </Botao>
          </>
        }
      >
        <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-start">
          <canvas ref={previa} width={240} height={320} className="w-48 shrink-0 rounded-entrada border border-borda bg-entrada" aria-label="Prévia do recorte" role="img" />
          <div className="flex w-full flex-col gap-3 text-sm">
            <ControleFaixa rotulo="Zoom" min={1} max={3} passo={0.05} valor={recorte.zoom} aoMudar={(zoom) => setRecorte((r) => ({ ...r, zoom }))} />
            <ControleFaixa rotulo="Horizontal" min={-1} max={1} passo={0.02} valor={recorte.x} aoMudar={(x) => setRecorte((r) => ({ ...r, x }))} />
            <ControleFaixa rotulo="Vertical" min={-1} max={1} passo={0.02} valor={recorte.y} aoMudar={(y) => setRecorte((r) => ({ ...r, y }))} />
            <p className="text-xs text-lavanda">Centralize o rosto dentro da guia. A imagem é reduzida para no máximo 1024 px e comprimida em JPEG antes de enviar.</p>
          </div>
        </div>
      </Modal>
    </div>
  )
}

function ControleFaixa({
  rotulo,
  min,
  max,
  passo,
  valor,
  aoMudar,
}: {
  rotulo: string
  min: number
  max: number
  passo: number
  valor: number
  aoMudar(v: number): void
}) {
  const id = useId()
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="font-semibold text-lavanda">
        {rotulo}
      </label>
      <input id={id} type="range" min={min} max={max} step={passo} value={valor} onChange={(e) => aoMudar(Number(e.target.value))} className="accent-ouro" />
    </div>
  )
}
