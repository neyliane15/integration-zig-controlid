/**
 * Ocorrências disciplinares (adendo O): lista com anexos, modal de registro/edição com fotos do documento assinado
 * (câmera do celular ou arquivo, comprimidas no navegador) e visualização por URL assinada.
 */
import { useEffect, useId, useRef, useState } from 'react'
import clsx from 'clsx'
import { Camera, ExternalLink, FileText, ImagePlus, Paperclip, Pencil, Plus, ShieldAlert, Trash2, X } from 'lucide-react'
import type { AnexoOcorrencia, Ocorrencia, TipoOcorrencia } from '@/tipos/banco'
import { AreaTexto, Botao, Campo, Carregando, Entrada, EntradaData, ErroCarga, FOCO, Modal, Selecao, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import {
  LIMITE_ANEXOS,
  textoContagem,
  useAdicionarAnexo,
  useExcluirOcorrencia,
  useOcorrencias,
  useRemoverAnexo,
  useSalvarOcorrencia,
  useUrlAnexo,
} from '@/consultas/ocorrencias'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { comprimirImagem, ehImagem } from '@/lib/imagem'
import { formatarData, formatarDataHora, somarDias } from '@/lib/formato'
import { rotuloTipoOcorrencia } from '@/lib/rotulos'
import { mensagemDeErro } from '@/lib/supabase'

const LIMITE_PDF = 5 * 1024 * 1024

/** Arquivo pronto para enviar (imagem já comprimida) com prévia local. */
export interface ArquivoFila {
  chave: string
  blob: Blob
  nome: string
  previa: string | null
  erro?: string | null
}

/** Prepara os arquivos escolhidos: imagem → JPEG comprimido; PDF → como veio (≤ 5 MB). */
export async function prepararArquivos(arquivos: File[]): Promise<{ prontos: ArquivoFila[]; erros: string[] }> {
  const prontos: ArquivoFila[] = []
  const erros: string[] = []
  for (const f of arquivos) {
    const chave = `${f.name}-${f.size}-${Math.random().toString(36).slice(2, 8)}`
    try {
      if (/pdf$/i.test(f.type) || /\.pdf$/i.test(f.name)) {
        if (f.size > LIMITE_PDF) throw new Error('PDF maior que 5 MB')
        prontos.push({ chave, blob: f.slice(0, f.size, 'application/pdf'), nome: f.name, previa: null })
      } else if (ehImagem(f)) {
        const blob = await comprimirImagem(f)
        prontos.push({ chave, blob, nome: f.name.replace(/\.[^.]+$/, '') + '.jpg', previa: URL.createObjectURL(blob) })
      } else throw new Error('Envie foto (JPG/PNG) ou PDF')
    } catch (e) {
      erros.push(`${f.name}: ${mensagemDeErro(e)}`)
    }
  }
  return { prontos, erros }
}

// ------------------------------------------------------------------ seletor
function SeletorArquivos({ aoEscolher, desabilitado, compacto }: { aoEscolher(f: File[]): void; desabilitado?: boolean; compacto?: boolean }) {
  const camera = useRef<HTMLInputElement>(null)
  const arquivo = useRef<HTMLInputElement>(null)
  const id = useId()
  const mudar = (e: React.ChangeEvent<HTMLInputElement>) => {
    const lista = [...(e.target.files ?? [])]
    e.target.value = ''
    if (lista.length) aoEscolher(lista)
  }
  return (
    <div className="flex flex-wrap gap-2">
      <input ref={camera} id={`${id}-cam`} type="file" accept="image/*" capture="environment" className="sr-only" onChange={mudar} tabIndex={-1} aria-label="Tirar foto do documento" />
      <input
        ref={arquivo}
        id={`${id}-arq`}
        type="file"
        accept="image/jpeg,image/png,image/webp,application/pdf"
        multiple
        className="sr-only"
        onChange={mudar}
        tabIndex={-1}
        aria-label="Escolher arquivo do documento"
      />
      <Botao variante="secundario" tamanho="p" icone={<Camera aria-hidden />} onClick={() => camera.current?.click()} disabled={desabilitado}>
        {compacto ? 'Foto' : 'Tirar foto'}
      </Botao>
      <Botao variante="secundario" tamanho="p" icone={<ImagePlus aria-hidden />} onClick={() => arquivo.current?.click()} disabled={desabilitado}>
        {compacto ? 'Arquivo' : 'Escolher arquivo'}
      </Botao>
    </div>
  )
}

// --------------------------------------------------------------------- modal
export function ModalOcorrencia({
  aberto,
  aoFechar,
  funcionarioId,
  funcionarioNome,
  ocorrencia,
}: {
  aberto: boolean
  aoFechar(): void
  /** null: mostra o seletor de funcionário (atalho do painel) */
  funcionarioId: string | null
  funcionarioNome?: string
  ocorrencia?: Ocorrencia | null
}) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const salvar = useSalvarOcorrencia()
  const anexar = useAdicionarAnexo()
  const id = useId()
  const [funcionario, setFuncionario] = useState<string | null>(funcionarioId)
  const [tipo, setTipo] = useState<TipoOcorrencia>(ocorrencia?.tipo ?? 'advertencia')
  const [data, setData] = useState<string | null>(ocorrencia?.data ?? hoje)
  const [motivo, setMotivo] = useState(ocorrencia?.motivo ?? '')
  const [descricao, setDescricao] = useState(ocorrencia?.descricao ?? '')
  const [dias, setDias] = useState(String(ocorrencia?.dias_suspensao ?? 1))
  const [inicio, setInicio] = useState<string | null>(ocorrencia?.suspensao_inicio ?? null)
  const [fila, setFila] = useState<ArquivoFila[]>([])
  const [preparando, setPreparando] = useState(false)
  const [tentou, setTentou] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setFuncionario(funcionarioId)
    setTipo(ocorrencia?.tipo ?? 'advertencia')
    setData(ocorrencia?.data ?? hoje)
    setMotivo(ocorrencia?.motivo ?? '')
    setDescricao(ocorrencia?.descricao ?? '')
    setDias(String(ocorrencia?.dias_suspensao ?? 1))
    setInicio(ocorrencia?.suspensao_inicio ?? null)
    setFila([])
    setTentou(false)
  }, [aberto, funcionarioId, ocorrencia, hoje])

  // libera as prévias locais só ao desmontar (a fila muda a cada arquivo escolhido)
  const filaRef = useRef(fila)
  filaRef.current = fila
  useEffect(() => () => filaRef.current.forEach((f) => f.previa && URL.revokeObjectURL(f.previa)), [])

  const nDias = Number(dias)
  const inicioEfetivo = inicio ?? data
  const fimSuspensao = tipo === 'suspensao' && inicioEfetivo && Number.isInteger(nDias) && nDias >= 1 ? somarDias(inicioEfetivo, nDias - 1) : null
  const erros = {
    funcionario: !funcionario ? 'Escolha o funcionário' : null,
    data: !data ? 'Informe a data' : data > hoje ? 'Data no futuro' : null,
    motivo: !motivo.trim() ? 'Informe o motivo' : null,
    dias: tipo === 'suspensao' && (!Number.isInteger(nDias) || nDias < 1 || nDias > 30) ? 'Dias de suspensão inválidos (1 a 30)' : null,
    inicio:
      tipo === 'suspensao' && data && inicioEfetivo && (inicioEfetivo < data || inicioEfetivo > somarDias(data, 60)) ? 'Início da suspensão inválido' : null,
  }
  const mostrar = (e: string | null) => (tentou ? e : null)
  const jaTem = ocorrencia?.anexos.length ?? 0

  const escolher = async (arquivos: File[]) => {
    if (jaTem + fila.length + arquivos.length > LIMITE_ANEXOS) return avisos.erro(`Limite de ${LIMITE_ANEXOS} anexos por ocorrência`)
    setPreparando(true)
    try {
      const { prontos, erros: problemas } = await prepararArquivos(arquivos)
      setFila((f) => [...f, ...prontos])
      problemas.forEach((p) => avisos.erro(p))
    } finally {
      setPreparando(false)
    }
  }

  const tirar = (chave: string) =>
    setFila((f) => {
      const item = f.find((x) => x.chave === chave)
      if (item?.previa) URL.revokeObjectURL(item.previa)
      return f.filter((x) => x.chave !== chave)
    })

  const enviar = async () => {
    setTentou(true)
    const primeiro = Object.values(erros).find(Boolean)
    if (primeiro) return avisos.erro(primeiro)
    let ocorrenciaId: string
    try {
      ocorrenciaId = await salvar.mutateAsync({
        id: ocorrencia?.id,
        funcionarioId: funcionario!,
        dados: {
          tipo,
          data: data!,
          motivo: motivo.trim(),
          descricao: descricao.trim() || null,
          diasSuspensao: tipo === 'suspensao' ? nDias : null,
          suspensaoInicio: tipo === 'suspensao' ? inicioEfetivo : null,
        },
      })
    } catch (e) {
      return avisos.erro(e)
    }
    // anexos: cada um independente; os que falharem ficam na fila para tentar de novo
    const restantes: ArquivoFila[] = []
    for (const f of fila) {
      try {
        await anexar.mutateAsync({ ocorrenciaId, arquivo: f.blob, nomeArquivo: f.nome })
        if (f.previa) URL.revokeObjectURL(f.previa)
      } catch (e) {
        restantes.push({ ...f, erro: mensagemDeErro(e) })
      }
    }
    if (restantes.length > 0) {
      setFila(restantes)
      avisos.erro(`Ocorrência salva, mas ${restantes.length} foto(s) não foram enviadas. Anexe de novo pela lista de ocorrências.`)
      // a ocorrência já existe: o modal vira "edição" só para não duplicar ao tentar de novo
      aoFechar()
      return
    }
    setFila([])
    avisos.sucesso(ocorrencia ? 'Ocorrência atualizada' : `${rotuloTipoOcorrencia[tipo]} registrada`)
    aoFechar()
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      largura="g"
      titulo={ocorrencia ? 'Editar ocorrência' : funcionarioNome ? `Registrar ocorrência · ${funcionarioNome}` : 'Registrar ocorrência'}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao onClick={enviar} carregando={salvar.isPending || anexar.isPending} disabled={preparando}>
            {ocorrencia ? 'Salvar' : 'Registrar'}
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {funcionarioId == null && (
          <div className="sm:col-span-2">
            <Campo rotulo="Funcionário" htmlFor={`${id}-f`} obrigatorio erro={mostrar(erros.funcionario)}>
              <SeletorFuncionario id={`${id}-f`} valor={funcionario} aoMudar={setFuncionario} somenteAtivos />
            </Campo>
          </div>
        )}
        <Campo rotulo="Tipo" htmlFor={`${id}-t`} obrigatorio>
          <Selecao id={`${id}-t`} value={tipo} onChange={(e) => setTipo(e.target.value as TipoOcorrencia)}>
            <option value="advertencia">{rotuloTipoOcorrencia.advertencia}</option>
            <option value="suspensao">{rotuloTipoOcorrencia.suspensao}</option>
          </Selecao>
        </Campo>
        <Campo rotulo="Data da ocorrência" htmlFor={`${id}-d`} obrigatorio erro={mostrar(erros.data)}>
          <EntradaData id={`${id}-d`} valor={data} max={hoje} aoMudar={setData} />
        </Campo>
        {tipo === 'suspensao' && (
          <>
            <Campo rotulo="Dias de suspensão" htmlFor={`${id}-n`} obrigatorio erro={mostrar(erros.dias)} ajuda="Dias corridos, de 1 a 30.">
              <Entrada
                id={`${id}-n`}
                type="number"
                min={1}
                max={30}
                inputMode="numeric"
                className="numero"
                value={dias}
                onChange={(e) => setDias(e.target.value)}
              />
            </Campo>
            <Campo
              rotulo="Início da suspensão"
              htmlFor={`${id}-i`}
              erro={mostrar(erros.inicio)}
              ajuda={fimSuspensao ? `Volta ao trabalho em ${formatarData(somarDias(fimSuspensao, 1))}. Os dias ficam abonados no ponto (sem falta nem alarme).` : 'Padrão: a data da ocorrência.'}
            >
              <EntradaData id={`${id}-i`} valor={inicioEfetivo} min={data ?? undefined} max={data ? somarDias(data, 60) : undefined} aoMudar={setInicio} />
            </Campo>
          </>
        )}
        <div className="sm:col-span-2">
          <Campo rotulo="Motivo" htmlFor={`${id}-m`} obrigatorio erro={mostrar(erros.motivo)} ajuda="Ex.: Atraso recorrente, falta sem aviso.">
            <Entrada id={`${id}-m`} value={motivo} maxLength={200} onChange={(e) => setMotivo(e.target.value)} />
          </Campo>
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Descrição" htmlFor={`${id}-ds`}>
            <AreaTexto id={`${id}-ds`} value={descricao} onChange={(e) => setDescricao(e.target.value)} placeholder="O que aconteceu, testemunhas, conversa com o funcionário…" />
          </Campo>
        </div>
        <div className="sm:col-span-2">
          <p className="mb-2 text-sm font-bold text-creme">Documento assinado</p>
          <p className="mb-3 text-xs text-lavanda">
            Tire uma foto pelo celular ou escolha o arquivo (foto ou PDF). As fotos são reduzidas e comprimidas antes de enviar. Até {LIMITE_ANEXOS} por
            ocorrência.
          </p>
          <SeletorArquivos aoEscolher={escolher} desabilitado={preparando || jaTem + fila.length >= LIMITE_ANEXOS} />
          {preparando && <p className="mt-2 text-xs text-lavanda">Preparando imagem…</p>}
          {fila.length > 0 && (
            <ul className="mt-3 flex flex-wrap gap-3" aria-label="Arquivos a enviar">
              {fila.map((f) => (
                <li key={f.chave} className="relative">
                  <div
                    className={clsx(
                      'grid size-24 place-items-center overflow-hidden rounded-entrada border bg-entrada',
                      f.erro ? 'border-perigo/60' : 'border-borda',
                    )}
                  >
                    {f.previa ? <img src={f.previa} alt={`Prévia de ${f.nome}`} className="size-full object-cover" /> : <FileText aria-hidden className="size-8 text-lavanda" />}
                  </div>
                  <p className="mt-1 w-24 truncate text-[11px] text-lavanda" title={f.nome}>
                    {f.nome}
                  </p>
                  {f.erro && <p className="w-24 text-[11px] text-perigo">{f.erro}</p>}
                  <button
                    type="button"
                    onClick={() => tirar(f.chave)}
                    aria-label={`Tirar ${f.nome}`}
                    className={clsx('absolute -top-2 -right-2 grid size-6 place-items-center rounded-full border border-borda bg-cartao text-lavanda hover:text-creme', FOCO)}
                  >
                    <X aria-hidden className="size-3.5" />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </Modal>
  )
}

// ---------------------------------------------------------------- anexos
function MiniaturaAnexo({ anexo, aoAbrir }: { anexo: AnexoOcorrencia; aoAbrir(): void }) {
  const pdf = /\.pdf$/i.test(anexo.caminho)
  const url = useUrlAnexo(pdf ? null : anexo.caminho)
  return (
    <button
      type="button"
      onClick={aoAbrir}
      aria-label={`Ver ${anexo.nome_arquivo ?? 'documento'}`}
      className={clsx('grid size-16 shrink-0 place-items-center overflow-hidden rounded-entrada border border-borda bg-entrada hover:border-ouro/60', FOCO)}
    >
      {pdf ? (
        <FileText aria-hidden className="size-6 text-lavanda" />
      ) : url.data ? (
        <img src={url.data} alt="" className="size-full object-cover" />
      ) : (
        <Paperclip aria-hidden className="size-5 text-lavanda-escuro" />
      )}
    </button>
  )
}

function VerAnexo({ anexo, aoFechar, aoRemover, removendo }: { anexo: AnexoOcorrencia | null; aoFechar(): void; aoRemover?(): void; removendo?: boolean }) {
  const pdf = !!anexo && /\.pdf$/i.test(anexo.caminho)
  const url = useUrlAnexo(anexo?.caminho)
  return (
    <Modal
      aberto={!!anexo}
      aoFechar={aoFechar}
      largura="g"
      titulo={anexo?.nome_arquivo ?? 'Documento'}
      rodape={
        <>
          {aoRemover && (
            <Botao variante="perigo" icone={<Trash2 aria-hidden />} onClick={aoRemover} carregando={removendo} className="mr-auto">
              Remover
            </Botao>
          )}
          {url.data && (
            <a
              href={url.data}
              target="_blank"
              rel="noopener noreferrer"
              className={clsx('inline-flex h-11 items-center gap-2 rounded-entrada border border-borda bg-entrada px-4 text-sm font-semibold text-creme hover:bg-cartao-2', FOCO)}
            >
              <ExternalLink aria-hidden className="size-4" /> Abrir em nova aba
            </a>
          )}
          <Botao variante="secundario" onClick={aoFechar}>
            Fechar
          </Botao>
        </>
      }
    >
      {url.isLoading ? (
        <Carregando />
      ) : url.error ? (
        <ErroCarga erro={url.error} aoTentar={() => url.refetch()} />
      ) : pdf ? (
        <p className="text-sm text-lavanda">PDF: use “Abrir em nova aba” para ver.</p>
      ) : url.data ? (
        <img src={url.data} alt={anexo?.nome_arquivo ?? 'Documento da ocorrência'} className="mx-auto max-h-[70dvh] w-auto rounded-entrada" />
      ) : null}
      {anexo && <p className="mt-3 text-xs text-lavanda">Enviado em {formatarDataHora(anexo.criado_em)}. Link temporário (5 min).</p>}
    </Modal>
  )
}

// ------------------------------------------------------------------- lista
function periodoSuspensao(o: Pick<Ocorrencia, 'dias_suspensao' | 'suspensao_inicio' | 'suspensao_fim'>): string {
  if (!o.dias_suspensao || !o.suspensao_inicio || !o.suspensao_fim) return ''
  const d = o.dias_suspensao
  return `${d} ${d === 1 ? 'dia' : 'dias'} · ${formatarData(o.suspensao_inicio)}${o.suspensao_fim !== o.suspensao_inicio ? ` a ${formatarData(o.suspensao_fim)}` : ''}`
}

function ItemOcorrencia({ o, aoEditar }: { o: Ocorrencia; aoEditar(): void }) {
  const avisos = useAvisos()
  const anexar = useAdicionarAnexo()
  const remover = useRemoverAnexo()
  const excluir = useExcluirOcorrencia()
  const [vendo, setVendo] = useState<AnexoOcorrencia | null>(null)
  const [enviando, setEnviando] = useState(false)

  const adicionar = async (arquivos: File[]) => {
    if (o.anexos.length + arquivos.length > LIMITE_ANEXOS) return avisos.erro(`Limite de ${LIMITE_ANEXOS} anexos por ocorrência`)
    setEnviando(true)
    try {
      const { prontos, erros } = await prepararArquivos(arquivos)
      erros.forEach((e) => avisos.erro(e))
      let ok = 0
      for (const f of prontos) {
        try {
          await anexar.mutateAsync({ ocorrenciaId: o.id, arquivo: f.blob, nomeArquivo: f.nome })
          ok += 1
        } catch (e) {
          avisos.erro(e)
        } finally {
          if (f.previa) URL.revokeObjectURL(f.previa)
        }
      }
      if (ok > 0) avisos.sucesso(ok === 1 ? 'Documento anexado' : `${ok} documentos anexados`)
    } finally {
      setEnviando(false)
    }
  }

  const apagar = async () => {
    const ok = await avisos.confirmar({
      titulo: `Excluir ${rotuloTipoOcorrencia[o.tipo].toLowerCase()} de ${formatarData(o.data)}?`,
      mensagem:
        o.tipo === 'suspensao'
          ? 'Os dias de suspensão deixam de ser abonados e o ponto desses dias é recalculado. Os documentos anexados também são apagados.'
          : 'Os documentos anexados também são apagados. Esta ação não pode ser desfeita.',
      textoConfirmar: 'Excluir',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluir.mutateAsync(o.id)
      avisos.sucesso('Ocorrência excluída')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const removerAnexo = async () => {
    if (!vendo) return
    if (!(await avisos.confirmar({ titulo: 'Remover este documento?', textoConfirmar: 'Remover', perigo: true }))) return
    try {
      await remover.mutateAsync(vendo.id)
      setVendo(null)
      avisos.sucesso('Documento removido')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <li className="rounded-cartao border border-borda bg-cartao p-4 sm:p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="flex flex-wrap items-center gap-2">
            <Selo tom={o.tipo === 'suspensao' ? 'perigo' : 'alerta'}>{rotuloTipoOcorrencia[o.tipo]}</Selo>
            <span className="numero text-sm text-creme">{formatarData(o.data)}</span>
          </p>
          <p className="mt-2 font-semibold break-words text-creme">{o.motivo}</p>
          {o.tipo === 'suspensao' && <p className="numero mt-1 text-sm text-perigo">{periodoSuspensao(o)}</p>}
          {o.descricao && <p className="mt-2 text-sm leading-relaxed break-words whitespace-pre-line text-lavanda">{o.descricao}</p>}
          <p className="mt-2 text-xs text-lavanda-escuro">
            Registrado por {o.criado_por_nome} em {formatarDataHora(o.criado_em)}
          </p>
        </div>
        <div className="flex gap-1">
          <Botao variante="fantasma" tamanho="p" aria-label="Editar ocorrência" icone={<Pencil aria-hidden />} onClick={aoEditar} />
          <Botao variante="fantasma" tamanho="p" aria-label="Excluir ocorrência" icone={<Trash2 aria-hidden />} onClick={apagar} carregando={excluir.isPending} />
        </div>
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-borda pt-4">
        {o.anexos.map((a) => (
          <MiniaturaAnexo key={a.id} anexo={a} aoAbrir={() => setVendo(a)} />
        ))}
        {o.anexos.length === 0 && <p className="mr-2 text-xs text-lavanda">Sem documento anexado.</p>}
        {o.anexos.length < LIMITE_ANEXOS && <SeletorArquivos aoEscolher={adicionar} desabilitado={enviando} compacto />}
        {enviando && <span className="text-xs text-lavanda">Enviando…</span>}
      </div>
      <VerAnexo anexo={vendo} aoFechar={() => setVendo(null)} aoRemover={removerAnexo} removendo={remover.isPending} />
    </li>
  )
}

export function ListaOcorrencias({ funcionarioId, funcionarioNome }: { funcionarioId: string; funcionarioNome: string }) {
  const lista = useOcorrencias(funcionarioId)
  const [modal, setModal] = useState<{ ocorrencia: Ocorrencia | null } | null>(null)
  const itens = lista.data ?? []
  const adv = itens.filter((o) => o.tipo === 'advertencia').length
  const sus = itens.filter((o) => o.tipo === 'suspensao').length
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="flex items-center gap-2 text-sm text-lavanda">
          <ShieldAlert aria-hidden className="size-4 text-ouro" />
          {lista.isLoading ? 'Carregando…' : textoContagem(adv, sus) || 'Nenhuma ocorrência registrada'}
        </p>
        <Botao icone={<Plus aria-hidden />} onClick={() => setModal({ ocorrencia: null })}>
          Registrar ocorrência
        </Botao>
      </div>
      {lista.error ? (
        <ErroCarga erro={lista.error} aoTentar={() => lista.refetch()} />
      ) : lista.isLoading ? (
        <Carregando />
      ) : itens.length === 0 ? (
        <Vazio
          icone={<ShieldAlert aria-hidden />}
          titulo="Sem advertências nem suspensões"
          descricao="Registre aqui as advertências e suspensões, com a foto do documento assinado pelo funcionário."
        />
      ) : (
        <ul className="flex flex-col gap-3">
          {itens.map((o) => (
            <ItemOcorrencia key={o.id} o={o} aoEditar={() => setModal({ ocorrencia: o })} />
          ))}
        </ul>
      )}
      <ModalOcorrencia
        aberto={!!modal}
        aoFechar={() => setModal(null)}
        funcionarioId={funcionarioId}
        funcionarioNome={funcionarioNome}
        ocorrencia={modal?.ocorrencia ?? null}
      />
    </div>
  )
}
