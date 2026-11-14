import { useEffect, useId, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import clsx from 'clsx'
import { AlertTriangle, ArrowLeft, CalendarPlus, Check, Download, Lock, Mail, RefreshCw, Trash2, UserPlus, X } from 'lucide-react'
import type { ComissaoDetalhe, ComissaoDetalheItem, ComissaoFechamento, ModoRateio } from '@/tipos/banco'
import {
  AreaTexto,
  Botao,
  CabecalhoPagina,
  Caixa,
  Campo,
  Carregando,
  Cartao,
  Entrada,
  EntradaMoeda,
  ErroCarga,
  Interruptor,
  Pilulas,
  Selecao,
  useMidia,
  Selo,
  Vazio,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { useContextoEmpresa, useFuncionarios } from '@/consultas/funcionarios'
import {
  useAtualizarFechamento,
  useComissaoDetalhe,
  useDefinirExtra,
  useDefinirItens,
  useEnviarFechamentoPorEmail,
  useExcluirRascunho,
  useFecharComissao,
  useRecalcularFechamento,
  useRemoverItem,
} from '@/consultas/comissoes'
import { usePerfil } from '@/lib/sessao'
import { podeAdministrar } from '@/lib/permissoes'
import { formatarCentavos, formatarData, formatarDataHora } from '@/lib/formato'
import { baixarCsv } from '@/lib/csv'
import { descricaoModoRateio, rotuloModoRateio, rotuloStatusFechamento } from '@/lib/rotulos'
import { calcularComissao, csvComissao, type ParticipanteComissao, type ResultadoComissao } from '@/lib/comissao'
import { RateioDiario } from './RateioDiario'

interface Parametros {
  titulo: string
  ajuste: number
  percentual: string
  proporcional: boolean
  observacoes: string
  modo: ModoRateio
}

/** pontos: texto do campo; vazio = automático (vigentes de cada dia) */
type EdicaoItem = { pontos: string; incluido: boolean }

function paramsDe(f: ComissaoFechamento): Parametros {
  return {
    titulo: f.titulo,
    ajuste: f.servico_ajuste_centavos,
    percentual: String(f.percentual_retencao).replace('.', ','),
    proporcional: f.proporcional_dias,
    observacoes: f.observacoes ?? '',
    modo: f.modo_rateio,
  }
}

function lerNumero(s: string): number | null {
  const n = Number(s.replace(',', '.').trim())
  return s.trim() !== '' && Number.isFinite(n) ? n : null
}

const fmtPontos = (n: number, casas = 2) => n.toLocaleString('pt-BR', { maximumFractionDigits: casas })
const textoPontos = (n: number) => String(n).replace('.', ',')

/** Funcionário com cadastro: pontos editáveis (manual) ou automáticos. Snapshot de excluído e extra: não. */
const editaPontos = (i: ComissaoDetalheItem) => i.tipo === 'funcionario' && !!i.funcionario_id
const editaIncluido = (i: ComissaoDetalheItem) => (i.tipo === 'funcionario' ? !!i.funcionario_id : !!i.extra_id)
const edicaoOriginal = (i: ComissaoDetalheItem): EdicaoItem => ({ pontos: i.pontos_manual ? textoPontos(i.pontos) : '', incluido: i.incluido })
const mudou = (i: ComissaoDetalheItem, e: EdicaoItem | undefined) => {
  if (!e) return false
  const o = edicaoOriginal(i)
  return e.incluido !== o.incluido || lerNumero(e.pontos) !== lerNumero(o.pontos)
}

export function PaginaFechamento() {
  const { id = '' } = useParams()
  const consulta = useComissaoDetalhe(id)
  if (consulta.isLoading) return <Carregando texto="Carregando fechamento…" />
  if (consulta.error || !consulta.data)
    return (
      <div className="mx-auto max-w-5xl">
        <BotaoLink to="/comissoes" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
          Comissões
        </BotaoLink>
        <ErroCarga erro={consulta.error ?? 'Fechamento não encontrado'} aoTentar={() => consulta.refetch()} />
      </div>
    )
  return <Fechamento detalhe={consulta.data} />
}

function Fechamento({ detalhe }: { detalhe: ComissaoDetalhe }) {
  const { fechamento: f, itens } = detalhe
  const perfil = usePerfil()
  const administrar = podeAdministrar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { empresa } = useContextoEmpresa()
  const funcionarios = useFuncionarios()
  const atualizar = useAtualizarFechamento()
  const definirItens = useDefinirItens()
  const definirExtra = useDefinirExtra()
  const removerItem = useRemoverItem()
  const recalcular = useRecalcularFechamento()
  const fechar = useFecharComissao()
  const excluir = useExcluirRascunho()
  const enviarEmail = useEnviarFechamentoPorEmail()
  const id = useId()

  const rascunho = f.status === 'rascunho'
  const [params, setParams] = useState<Parametros>(() => paramsDe(f))
  const [edicoes, setEdicoes] = useState<Record<string, EdicaoItem>>({})
  const [adicionar, setAdicionar] = useState('')

  useEffect(() => {
    setParams(paramsDe(f))
  }, [f])
  useEffect(() => {
    setEdicoes({})
  }, [itens])

  const percentual = lerNumero(params.percentual)
  const erroPercentual = percentual == null || percentual < 0 || percentual > 100 ? 'Entre 0 e 100' : null
  const paramsAlterados = JSON.stringify(params) !== JSON.stringify(paramsDe(f))
  const itensAlterados = itens.filter((i) => mudou(i, edicoes[i.id]))
  const sujo = paramsAlterados || itensAlterados.length > 0
  const diario = params.modo === 'diario'

  const editar = (i: ComissaoDetalheItem, parcial: Partial<EdicaoItem>) =>
    setEdicoes((x) => ({ ...x, [i.id]: { ...(x[i.id] ?? edicaoOriginal(i)), ...parcial } }))

  /** participante da prévia com as edições locais aplicadas */
  const participante = (i: ComissaoDetalheItem): ParticipanteComissao => {
    const e = edicoes[i.id]
    const manualTexto = e ? lerNumero(e.pontos) : i.pontos_manual ? i.pontos : null
    const manual = editaPontos(i) ? manualTexto != null : i.pontos_manual
    const vigenteNoFim = i.entrada.find((l) => l.data === f.data_fim)?.pontos
    return {
      itemId: i.id,
      tipo: i.tipo,
      funcionarioId: i.funcionario_id,
      extraId: i.extra_id,
      nome: i.nome,
      cargo: i.cargo,
      incluido: e ? e.incluido : i.incluido,
      pontos: editaPontos(i) ? (manualTexto ?? (i.pontos_manual ? (vigenteNoFim ?? i.pontos) : i.pontos)) : i.pontos,
      pontosManual: manual,
      diasTrabalhados: i.dias_presentes,
      entrada: i.entrada,
    }
  }

  // prévia instantânea — mesma regra do banco (§9 / adendo E.3)
  const previa: ResultadoComissao = useMemo(
    () =>
      calcularComissao({
        modoRateio: params.modo,
        servicoZigCentavos: f.servico_zig_centavos,
        servicoAjusteCentavos: params.ajuste,
        percentualRetencao: percentual ?? f.percentual_retencao,
        proporcionalDias: params.proporcional,
        dataInicio: f.data_inicio,
        dataFim: f.data_fim,
        servicoDias: detalhe.servico_dias.map((d) => ({ data: d.data, servicoZigCentavos: d.servico_zig_centavos })),
        participantes: itens.map(participante),
      }),
    [detalhe, params, edicoes, percentual],
  )

  // conferência: sem alterações, a prévia tem de bater com o banco
  const confere =
    !sujo && previa.itens.every((p, k) => p.valorCentavos === itens[k]?.valor_centavos) && previa.baseCentavos === f.base_distribuivel_centavos

  const disponiveis = (funcionarios.data ?? []).filter((x) => x.ativo && !itens.some((i) => i.funcionario_id === x.id))
  const diasSemParticipantes = sujo ? previa.diasSemParticipantes : f.dias_sem_participantes
  const diasSemPresenca = sujo ? previa.diasSemPresenca : f.dias_sem_presenca
  const extrasPendentes = sujo ? previa.extrasSemPontuacao : f.extras_sem_pontuacao
  const nomesPendentes = previa.itens.filter((i) => i.pontosPendente).map((i) => i.nome)

  const salvar = async () => {
    if (erroPercentual) return avisos.erro('Percentual de retenção inválido')
    if (!params.titulo.trim()) return avisos.erro('Informe o título')
    try {
      if (paramsAlterados)
        await atualizar.mutateAsync({
          id: f.id,
          titulo: params.titulo.trim(),
          ajuste: params.ajuste,
          percentual: percentual as number,
          proporcional: params.proporcional,
          observacoes: params.observacoes.trim() || null,
          modo: params.modo,
        })
      const funcs = itensAlterados.filter((i) => i.tipo === 'funcionario' && i.funcionario_id)
      if (funcs.length)
        await definirItens.mutateAsync({
          id: f.id,
          itens: funcs.map((i) => ({ funcionarioId: i.funcionario_id!, pontos: lerNumero(edicoes[i.id]!.pontos), incluido: edicoes[i.id]!.incluido })),
        })
      for (const i of itensAlterados.filter((x) => x.tipo === 'extra' && x.extra_id))
        await definirExtra.mutateAsync({ id: f.id, extraId: i.extra_id!, incluido: edicoes[i.id]!.incluido })
      avisos.sucesso('Rascunho salvo e recalculado')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const incluirParticipante = async () => {
    if (!adicionar) return
    try {
      await definirItens.mutateAsync({ id: f.id, itens: [{ funcionarioId: adicionar, pontos: null, incluido: true }] })
      setAdicionar('')
      avisos.sucesso('Participante incluído')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const exportar = () => {
    if (sujo) avisos.info('Exportando os valores salvos (as alterações não salvas não entram).')
    const { nome, conteudo } = csvComissao(
      f,
      itens.map((i) => ({
        funcionario_nome: i.nome,
        tipo: i.tipo,
        cargo: i.cargo,
        incluido: i.incluido,
        pontos: i.pontos,
        dias_presentes: i.dias_presentes,
        valor_centavos: i.valor_centavos,
      })),
      empresa?.nome ?? 'empresa',
    )
    baixarCsv(nome, conteudo)
  }

  const acaoFechar = async () => {
    const ok = await avisos.confirmar({
      titulo: 'Fechar a comissão?',
      mensagem: (
        <>
          Base distribuível <strong>{formatarCentavos(f.base_distribuivel_centavos)}</strong> para{' '}
          {itens.filter((i) => i.incluido && i.valor_centavos > 0).length} participante(s).
          {f.dias_sem_presenca > 0 && <> {f.dias_sem_presenca} dia(s) tiveram gente sem registro de presença (entrou pelo fallback).</>} Depois de
          fechado, o fechamento não pode mais ser alterado nem excluído.
        </>
      ),
      textoConfirmar: 'Fechar comissão',
    })
    if (!ok) return
    try {
      await fechar.mutateAsync(f.id)
      avisos.sucesso('Comissão fechada')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const telaLarga = useMidia('(min-width: 768px)')
  const ocupado = atualizar.isPending || definirItens.isPending || definirExtra.isPending || removerItem.isPending || recalcular.isPending
  const somaIncluidos = previa.itens.reduce((s, i) => s + (i.incluido ? i.pontos : 0), 0)
  const diasIncluidos = previa.itens.reduce((s, i) => s + (i.incluido ? i.diasPresentes : 0), 0)
  const participantes = previa.itens.filter((i) => i.incluido && i.valorCentavos > 0).length
  const extras = itens.filter((i) => i.tipo === 'extra').length

  return (
    <div className="mx-auto w-full max-w-7xl">
      <BotaoLink to="/comissoes" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Comissões
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha={`${formatarData(f.data_inicio)} a ${formatarData(f.data_fim)} · ${f.dias_periodo} dias`}
        titulo={f.titulo}
        subtitulo={
          <span className="flex flex-wrap items-center gap-2">
            <Selo tom={rascunho ? 'ouro' : 'sucesso'}>
              {!rascunho && <Lock aria-hidden />}
              {rotuloStatusFechamento[f.status]}
            </Selo>
            <Selo tom="info">Rateio {rotuloModoRateio[f.modo_rateio].toLowerCase()}</Selo>
            {f.fechado_em && <span>fechado em {formatarDataHora(f.fechado_em)}</span>}
            {rascunho && f.calculado_em && <span>calculado {formatarDataHora(f.calculado_em)}</span>}
          </span>
        }
        acoes={
          <>
            <Botao variante="secundario" icone={<Download aria-hidden className="size-4" />} onClick={exportar}>
              Exportar CSV
            </Botao>
            <Botao
              variante="secundario"
              icone={<Mail aria-hidden className="size-4" />}
              carregando={enviarEmail.isPending}
              onClick={async () => {
                try {
                  const n = await enviarEmail.mutateAsync(f.id)
                  avisos.sucesso(Number(n) > 0 ? 'Envio por e-mail colocado na fila' : 'Já existe um envio na fila')
                } catch (e) {
                  avisos.erro(e)
                }
              }}
            >
              Enviar por e-mail
            </Botao>
            {rascunho && administrar && (
              <Botao
                icone={<Lock aria-hidden className="size-4" />}
                onClick={acaoFechar}
                carregando={fechar.isPending}
                disabled={sujo || ocupado || f.valor_ponto_centavos == null || f.dias_sem_participantes > 0 || f.extras_sem_pontuacao > 0}
                title={
                  f.extras_sem_pontuacao > 0
                    ? 'Há extras sem pontuação: preencha antes de fechar'
                    : f.dias_sem_participantes > 0
                      ? 'Há dias com serviço sem participantes para ratear'
                      : undefined
                }
              >
                Fechar comissão
              </Botao>
            )}
          </>
        }
      />

      {rascunho && sujo && (
        <div role="status" className="mb-5 flex flex-wrap items-center gap-3 rounded-cartao border border-ouro/50 bg-ouro/10 p-4 text-sm">
          <span className="flex-1 text-ouro-claro">Prévia com alterações não salvas. Os valores abaixo já mostram o resultado; salve para valer.</span>
          <Botao
            variante="fantasma"
            tamanho="p"
            onClick={() => {
              setParams(paramsDe(f))
              setEdicoes({})
            }}
          >
            Descartar
          </Botao>
          <Botao tamanho="p" icone={<Check aria-hidden className="size-4" />} carregando={ocupado} onClick={salvar}>
            Salvar
          </Botao>
        </div>
      )}
      {diario && diasSemParticipantes > 0 && (
        <p role="alert" className="mb-4 flex items-start gap-2 rounded-cartao border border-perigo/40 bg-perigo/10 p-4 text-sm text-perigo">
          <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
          {diasSemParticipantes} dia(s) com serviço sem ninguém para ratear. Inclua funcionários com pontos para poder fechar.
        </p>
      )}
      {extrasPendentes > 0 && (
        <div role="alert" data-teste="aviso-extras-pendentes" className="mb-4 flex flex-wrap items-start gap-3 rounded-cartao border border-alerta/50 bg-alerta/10 p-4 text-sm text-alerta">
          <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
          <span className="min-w-0 flex-1">
            <strong>
              {extrasPendentes} extra(s) com pontuação pendente
            </strong>
            {nomesPendentes.length > 0 && <> ({nomesPendentes.join(', ')})</>}: os dias sem pontuação não entram no rateio e o fechamento fica bloqueado.
            Preencha a pontuação em Extras (ou tire o extra do fechamento) e recalcule.
          </span>
          <BotaoLink to="/extras?pendentes=1" variante="secundario" tamanho="p">
            Preencher pontuação
          </BotaoLink>
        </div>
      )}
      {diario && diasSemPresenca > 0 && (
        <p role="status" className="mb-4 flex items-start gap-2 rounded-cartao border border-alerta/40 bg-alerta/10 p-4 text-sm text-alerta">
          <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
          {diasSemPresenca} dia(s) com gente sem registro de presença (sem ponto e fora da escala) — essas pessoas entraram pelo fallback. Confira o
          ponto ou a escala desses dias.
        </p>
      )}
      {rascunho && !administrar && <p className="mb-4 text-sm text-lavanda">Somente o administrador fecha a comissão. Você pode preparar o rascunho.</p>}

      <div className="grid grid-cols-[minmax(0,1fr)] gap-5 2xl:grid-cols-[minmax(0,380px)_minmax(0,1fr)]">
        <Cartao sobrancelha="Cálculo" titulo={<span className="numero">{formatarCentavos(previa.baseCentavos)}</span>}>
          <p className="-mt-3 mb-4 text-sm text-lavanda">base distribuível</p>
          <dl className="flex flex-col gap-2.5 text-sm">
            <Linha rotulo="Serviço da Zig (Tips)" valor={formatarCentavos(previa.servicoZigCentavos)} />
            <div className="flex flex-col gap-1.5">
              <label htmlFor={`${id}-aj`} className="text-lavanda">
                Ajuste manual (±)
              </label>
              {rascunho ? (
                <EntradaMoeda id={`${id}-aj`} centavos={params.ajuste} permitirNegativo aoMudar={(c) => setParams((p) => ({ ...p, ajuste: c ?? 0 }))} />
              ) : (
                <span className="numero text-creme">{formatarCentavos(f.servico_ajuste_centavos, { sinal: true })}</span>
              )}
              {diario && params.ajuste !== 0 && <span className="text-xs text-lavanda">Repartido entre os dias pelo serviço de cada dia.</span>}
            </div>
            <Linha rotulo="Serviço bruto" valor={formatarCentavos(previa.servicoBrutoCentavos)} forte />
            <div className="grid grid-cols-[1fr_auto] items-end gap-3">
              <Campo rotulo="Retenção (%)" htmlFor={`${id}-pct`} erro={rascunho ? erroPercentual : null}>
                {rascunho ? (
                  <Entrada
                    id={`${id}-pct`}
                    className="numero"
                    inputMode="decimal"
                    value={params.percentual}
                    invalido={!!erroPercentual}
                    onChange={(e) => setParams((p) => ({ ...p, percentual: e.target.value.replace(/[^\d,.]/g, '') }))}
                  />
                ) : (
                  <span id={`${id}-pct`} className="numero text-creme">
                    {fmtPontos(f.percentual_retencao)}%
                  </span>
                )}
              </Campo>
              <span className="numero pb-3 text-perigo">−{formatarCentavos(previa.retencaoCentavos)}</span>
            </div>
            {diario && <p className="-mt-1 text-xs text-lavanda">No rateio diário a retenção é arredondada dia a dia.</p>}
            <Linha rotulo="Base distribuível" valor={formatarCentavos(previa.baseCentavos)} forte ouro />
            <Linha rotulo={diario ? 'Pontos somados nos dias' : 'Soma dos pontos'} valor={fmtPontos(previa.somaPontosEfetivos, 6)} />
            <Linha
              rotulo={diario ? 'Valor médio do ponto' : 'Valor do ponto'}
              valor={previa.valorPontoCentavos == null ? '—' : formatarCentavos(Math.round(previa.valorPontoCentavos))}
              detalhe={previa.valorPontoCentavos == null ? undefined : `${previa.valorPontoCentavos.toLocaleString('pt-BR', { maximumFractionDigits: 6 })} centavos`}
            />
            <div className="flex flex-col gap-1.5 pt-2">
              <span className="text-lavanda">Modo de rateio</span>
              <Pilulas<ModoRateio>
                rotulo="Modo de rateio"
                opcoes={[
                  { id: 'diario', rotulo: 'Diário' },
                  { id: 'periodo', rotulo: 'Por período' },
                ]}
                valor={params.modo}
                desabilitado={!rascunho}
                aoMudar={(v) => setParams((p) => ({ ...p, modo: v }))}
              />
              <span className="text-xs text-lavanda">{descricaoModoRateio[params.modo]}</span>
            </div>
            {!diario && (
              <div className="pt-1">
                <Interruptor
                  rotulo="Proporcional aos dias trabalhados"
                  marcado={params.proporcional}
                  desabilitado={!rascunho}
                  aoMudar={(v) => setParams((p) => ({ ...p, proporcional: v }))}
                />
              </div>
            )}
            {rascunho && (
              <>
                <Campo rotulo="Título" htmlFor={`${id}-tit`}>
                  <Entrada id={`${id}-tit`} value={params.titulo} onChange={(e) => setParams((p) => ({ ...p, titulo: e.target.value }))} />
                </Campo>
                <Campo rotulo="Observações" htmlFor={`${id}-obs`}>
                  <AreaTexto id={`${id}-obs`} className="min-h-16" value={params.observacoes} onChange={(e) => setParams((p) => ({ ...p, observacoes: e.target.value }))} />
                </Campo>
              </>
            )}
            {!rascunho && f.observacoes && <p className="text-sm text-lavanda">{f.observacoes}</p>}
          </dl>
          {rascunho && (
            <div className="mt-5 flex flex-col gap-3 border-t border-borda pt-4">
              <p className="text-xs text-lavanda">Lançou dias de extras ou ajustou o ponto? Recalcule para o rascunho ler tudo de novo.</p>
              <div className="flex flex-wrap gap-2">
                <Botao
                  variante="secundario"
                  tamanho="p"
                  icone={<RefreshCw aria-hidden className="size-4" />}
                  carregando={recalcular.isPending}
                  disabled={sujo}
                  title={sujo ? 'Salve ou descarte as alterações antes' : 'Relê o serviço da Zig, a presença e os dias dos extras'}
                  onClick={async () => {
                    try {
                      await recalcular.mutateAsync(f.id)
                      avisos.sucesso('Recalculado com o serviço, a presença e os extras atuais')
                    } catch (e) {
                      avisos.erro(e)
                    }
                  }}
                >
                  Recalcular
                </Botao>
                <Botao
                  variante="perigo"
                  tamanho="p"
                  icone={<Trash2 aria-hidden className="size-4" />}
                  carregando={excluir.isPending}
                  onClick={async () => {
                    if (!(await avisos.confirmar({ titulo: 'Excluir este rascunho?', perigo: true, textoConfirmar: 'Excluir' }))) return
                    try {
                      await excluir.mutateAsync(f.id)
                      avisos.sucesso('Rascunho excluído')
                      navegar('/comissoes', { replace: true })
                    } catch (e) {
                      avisos.erro(e)
                    }
                  }}
                >
                  Excluir rascunho
                </Botao>
              </div>
            </div>
          )}
        </Cartao>

        <div className="flex min-w-0 flex-col gap-5">
          <Cartao
            sobrancelha={`${participantes} participante(s)${extras ? ` · ${extras} extra(s)` : ''}`}
            titulo="Rateio por participante"
            acoes={
              <>
                {confere ? <Selo tom="sucesso">Prévia confere com o banco</Selo> : sujo ? <Selo tom="ouro">Prévia</Selo> : null}
                {rascunho && (
                  <BotaoLink to={`/extras?aba=dias&de=${f.data_inicio}&ate=${f.data_fim}`} variante="fantasma" tamanho="p" icone={<CalendarPlus aria-hidden className="size-4" />}>
                    Dias dos extras
                  </BotaoLink>
                )}
              </>
            }
            semPreenchimento
          >
            {itens.length === 0 ? (
              <div className="p-5">
                <Vazio titulo="Sem participantes" descricao="Inclua funcionários abaixo ou lance dias de extras no período e recalcule." />
              </div>
            ) : (
              <ListaParticipantes
                larga={telaLarga}
                itens={itens}
                previa={previa}
                rascunho={rascunho}
                diario={diario}
                diasPeriodo={f.dias_periodo}
                edicoes={edicoes}
                editar={editar}
                ocupado={ocupado}
                somaIncluidos={somaIncluidos}
                diasIncluidos={diasIncluidos}
                aoRemover={async (i) => {
                  if (!(await avisos.confirmar({ titulo: `Remover ${i.nome} do fechamento?`, textoConfirmar: 'Remover', perigo: true }))) return
                  try {
                    await removerItem.mutateAsync({ id: f.id, funcionarioId: i.funcionario_id! })
                  } catch (err) {
                    avisos.erro(err)
                  }
                }}
              />
            )}
            {rascunho && (
              <div className="flex flex-wrap items-end gap-2 border-t border-borda p-5">
                <div className="min-w-0 flex-1">
                  <Campo rotulo="Incluir funcionário" htmlFor={`${id}-add`}>
                    <Selecao id={`${id}-add`} value={adicionar} onChange={(e) => setAdicionar(e.target.value)}>
                      <option value="">{disponiveis.length ? 'Escolha um funcionário…' : 'Todos os ativos já estão no fechamento'}</option>
                      {disponiveis.map((x) => (
                        <option key={x.id} value={x.id}>
                          {x.nome}
                          {x.cargo ? ` — ${x.cargo}` : ''}
                        </option>
                      ))}
                    </Selecao>
                  </Campo>
                </div>
                <Botao
                  variante="secundario"
                  icone={<UserPlus aria-hidden className="size-4" />}
                  disabled={!adicionar || ocupado}
                  carregando={definirItens.isPending && !!adicionar}
                  onClick={incluirParticipante}
                >
                  Incluir
                </Botao>
                <p className="basis-full text-xs text-lavanda">Extras entram sozinhos quando têm dia lançado no período (em Extras → Dias trabalhados).</p>
              </div>
            )}
          </Cartao>

          {diario && <RateioDiario dias={previa.dias} itens={previa.itens} previa={sujo} />}
        </div>
      </div>
    </div>
  )
}

interface PropsLista {
  larga: boolean
  itens: ComissaoDetalheItem[]
  previa: ResultadoComissao
  rascunho: boolean
  diario: boolean
  diasPeriodo: number
  edicoes: Record<string, EdicaoItem>
  editar(i: ComissaoDetalheItem, parcial: Partial<EdicaoItem>): void
  ocupado: boolean
  somaIncluidos: number
  diasIncluidos: number
  aoRemover(i: ComissaoDetalheItem): void
}

/** Participantes: tabela (≥ 768 px) ou cartões (celular). Um só é montado, para não duplicar rótulos acessíveis. */
function ListaParticipantes(props: PropsLista) {
  const { larga, itens, previa, rascunho, diario, diasPeriodo, edicoes, editar, ocupado } = props

  const incluidoDe = (i: ComissaoDetalheItem) => (edicoes[i.id] ? edicoes[i.id]!.incluido : i.incluido)
  const ctrlIncluido = (i: ComissaoDetalheItem, comTexto = false) =>
    rascunho && editaIncluido(i) ? (
      <Caixa rotulo={
          comTexto ? (
            <>
              <span aria-hidden>Incluído</span>
              <span className="sr-only">Incluir {i.nome}</span>
            </>
          ) : (
            <span className="sr-only">Incluir {i.nome}</span>
          )
        } marcado={incluidoDe(i)} aoMudar={(v) => editar(i, { incluido: v })} />
    ) : (
      <span className="text-lavanda">{comTexto ? (incluidoDe(i) ? 'Incluído' : 'Não incluído') : incluidoDe(i) ? 'Sim' : 'Não'}</span>
    )
  const ctrlPontos = (i: ComissaoDetalheItem) =>
    rascunho && editaPontos(i) ? (
      <Entrada
        aria-label={`Pontos de ${i.nome}`}
        className="numero ml-auto h-9 w-24! min-w-20! shrink-0 px-3! text-right"
        inputMode="decimal"
        placeholder={diario ? 'auto' : fmtPontos(i.pontos)}
        title={diario ? 'Vazio = automático (pontos vigentes de cada dia)' : 'Vazio = pontos vigentes no fim do período'}
        value={edicoes[i.id]?.pontos ?? edicaoOriginal(i).pontos}
        onChange={(ev) => editar(i, { pontos: ev.target.value.replace(/[^\d,.]/g, '') })}
      />
    ) : (
      <span className="numero" title={i.tipo === 'extra' ? 'Média dos pontos dos dias lançados' : undefined}>
        {fmtPontos(i.pontos)}
      </span>
    )
  const ctrlRemover = (i: ComissaoDetalheItem) =>
    rascunho && i.tipo === 'funcionario' && i.funcionario_id ? (
      <Botao variante="fantasma" tamanho="p" aria-label={`Remover ${i.nome}`} icone={<X aria-hidden className="size-4" />} disabled={ocupado} onClick={() => props.aoRemover(i)} />
    ) : null
  const diasDe = (i: ComissaoDetalheItem, k: number) => previa.itens[k]?.diasPresentes ?? i.dias_presentes
  const dias = (i: ComissaoDetalheItem, k: number) => (i.tipo === 'extra' ? `${diasDe(i, k)} dia(s)` : `${diasDe(i, k)}/${diasPeriodo}`)
  const valor = (k: number) => {
    const p = previa.itens[k]
    return (
      <>
        {formatarCentavos(p?.valorCentavos ?? 0)}
        {p?.centavoExtra && (
          <span className="ml-1 text-[10px] text-lavanda" title="Recebeu +1 centavo no arredondamento pelo maior resto">
            +1¢
          </span>
        )}
      </>
    )
  }
  const nome = (i: ComissaoDetalheItem) => (
    <p className="flex flex-wrap items-center gap-1.5 font-semibold text-creme">
      <span>{i.nome}</span>
      {i.tipo === 'extra' && <Selo tom="info">Extra</Selo>}
      {i.tipo === 'extra' && i.pontos_pendente && <Selo tom="alerta">Pontuação pendente</Selo>}
    </p>
  )
  const classeLinha = (i: ComissaoDetalheItem) => clsx('border-t border-borda', !incluidoDe(i) && 'opacity-60', mudou(i, edicoes[i.id]) && 'bg-ouro/5')

  if (!larga)
    return (
      <ul aria-label="Participantes">
        {itens.map((i, k) => (
          <li key={i.id} className={clsx(classeLinha(i), 'px-5 py-3.5')}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                {nome(i)}
                <p className="text-xs text-lavanda">
                  {[
                    i.cargo,
                    i.tipo === 'extra' ? `${diasDe(i, k)} dia(s) trabalhado(s)` : `presente ${diasDe(i, k)} de ${diasPeriodo} dias`,
                    `${fmtPontos(previa.itens[k]?.pontosEfetivos ?? 0)} pts ${diario ? 'nos dias' : 'efetivos'}`,
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
              </div>
              <span className="numero shrink-0 text-right font-semibold whitespace-nowrap text-ouro-claro">{valor(k)}</span>
            </div>
            <div className="mt-2 flex items-center justify-between gap-3">
              {ctrlIncluido(i, true)}
              <span className="flex items-center gap-2 text-sm text-lavanda">
                Pontos {ctrlPontos(i)}
                {ctrlRemover(i)}
              </span>
            </div>
          </li>
        ))}
        <li className="flex items-center justify-between gap-3 border-t-2 border-borda-forte px-5 py-3 font-semibold">
          <span className="text-creme">Total · {fmtPontos(props.somaIncluidos)} pts</span>
          <span className="numero text-ouro-claro">{formatarCentavos(previa.totalDistribuidoCentavos)}</span>
        </li>
      </ul>
    )

  return (
    <div className="relative overflow-x-auto">
      <table className="w-full min-w-[620px] text-sm">
        <thead>
          <tr className="bg-cartao-2/70 text-[11px] font-bold tracking-[0.14em] whitespace-nowrap text-lavanda uppercase">
            <th scope="col" className="px-5 py-3 text-left">Participante</th>
            <th scope="col" className="px-3 py-3 text-center">Incluído</th>
            <th scope="col" className="px-3 py-3 text-right" title={diario ? 'Vazio = automático: pontos vigentes de cada dia' : undefined}>
              Pontos
            </th>
            <th scope="col" className="px-3 py-3 text-right">Dias presentes</th>
            <th scope="col" className="px-3 py-3 text-right">{diario ? 'Pts nos dias' : 'Pts efetivos'}</th>
            <th scope="col" className="px-3 py-3 text-right">Valor</th>
            {rascunho && (
              <th scope="col" className="px-3 py-3">
                <span className="sr-only">Ações</span>
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {itens.map((i, k) => (
            <tr key={i.id} className={classeLinha(i)}>
              <td className="px-5 py-3">
                {nome(i)}
                {i.cargo && <p className="text-xs text-lavanda">{i.cargo}</p>}
              </td>
              <td className="px-3 py-3 text-center">{ctrlIncluido(i)}</td>
              <td className="px-3 py-3 text-right">{ctrlPontos(i)}</td>
              <td className="numero px-3 py-3 text-right text-lavanda">{dias(i, k)}</td>
              <td className="numero px-3 py-3 text-right">{fmtPontos(previa.itens[k]?.pontosEfetivos ?? 0, 6)}</td>
              <td className="numero px-3 py-3 text-right font-semibold whitespace-nowrap text-ouro-claro">{valor(k)}</td>
              {rascunho && <td className="px-3 py-3 text-right">{ctrlRemover(i)}</td>}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-borda-forte font-semibold">
            <td className="px-5 py-3 text-creme">Total</td>
            <td />
            <td className="numero px-3 py-3 text-right">{fmtPontos(props.somaIncluidos)}</td>
            <td className="numero px-3 py-3 text-right text-lavanda">{props.diasIncluidos}</td>
            <td className="numero px-3 py-3 text-right">{fmtPontos(previa.somaPontosEfetivos, 6)}</td>
            <td className="numero px-3 py-3 text-right text-ouro-claro">{formatarCentavos(previa.totalDistribuidoCentavos)}</td>
            {rascunho && <td />}
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

function Linha({ rotulo, valor, detalhe, forte, ouro }: { rotulo: string; valor: string; detalhe?: string; forte?: boolean; ouro?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="text-lavanda">{rotulo}</dt>
      <dd className={clsx('numero text-right', forte ? 'font-semibold' : '', ouro ? 'text-ouro-claro' : 'text-creme')}>
        {valor}
        {detalhe && <span className="block text-[11px] font-normal text-lavanda">{detalhe}</span>}
      </dd>
    </div>
  )
}
