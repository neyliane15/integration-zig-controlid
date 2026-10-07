import { useEffect, useId, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import clsx from 'clsx'
import { ArrowLeft, Check, Download, Lock, Mail, RefreshCw, Trash2, UserPlus, X } from 'lucide-react'
import type { ComissaoFechamento, ComissaoItem } from '@/tipos/banco'
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
  Selecao,
  Selo,
  Vazio,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { useContextoEmpresa, useFuncionarios } from '@/consultas/funcionarios'
import {
  useAtualizarFechamento,
  useDefinirItens,
  useEnviarFechamentoPorEmail,
  useExcluirRascunho,
  useFecharComissao,
  useFechamento,
  useRecalcularFechamento,
  useRemoverItem,
} from '@/consultas/comissoes'
import { chamarRpc } from '@/lib/supabase'
import { usePerfil } from '@/lib/sessao'
import { podeAdministrar } from '@/lib/permissoes'
import { formatarCentavos, formatarData, formatarDataHora } from '@/lib/formato'
import { baixarCsv } from '@/lib/csv'
import { rotuloStatusFechamento } from '@/lib/rotulos'
import { calcularComissao, csvComissao, type ResultadoComissao } from '@/lib/comissao'

interface Parametros {
  titulo: string
  ajuste: number
  percentual: string
  proporcional: boolean
  observacoes: string
}

type EdicaoItem = { pontos: string; incluido: boolean }

function paramsDe(f: ComissaoFechamento): Parametros {
  return {
    titulo: f.titulo,
    ajuste: f.servico_ajuste_centavos,
    percentual: String(f.percentual_retencao).replace('.', ','),
    proporcional: f.proporcional_dias,
    observacoes: f.observacoes ?? '',
  }
}

function lerNumero(s: string): number | null {
  const n = Number(s.replace(',', '.').trim())
  return s.trim() !== '' && Number.isFinite(n) ? n : null
}

const fmtPontos = (n: number, casas = 2) => n.toLocaleString('pt-BR', { maximumFractionDigits: casas })

export function PaginaFechamento() {
  const { id = '' } = useParams()
  const consulta = useFechamento(id)
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
  return <Fechamento fechamento={consulta.data.fechamento} itens={consulta.data.itens} />
}

function Fechamento({ fechamento: f, itens }: { fechamento: ComissaoFechamento; itens: ComissaoItem[] }) {
  const perfil = usePerfil()
  const administrar = podeAdministrar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { empresa } = useContextoEmpresa()
  const funcionarios = useFuncionarios()
  const atualizar = useAtualizarFechamento()
  const definirItens = useDefinirItens()
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
  const itensAlterados = Object.entries(edicoes).filter(([fid, e]) => {
    const original = itens.find((i) => i.funcionario_id === fid)
    return original && (lerNumero(e.pontos) !== original.pontos || e.incluido !== original.incluido)
  })
  const sujo = paramsAlterados || itensAlterados.length > 0

  const itemEfetivo = (i: ComissaoItem) => {
    const e = i.funcionario_id ? edicoes[i.funcionario_id] : undefined
    return { pontos: e ? (lerNumero(e.pontos) ?? 0) : i.pontos, incluido: e ? e.incluido : i.incluido }
  }

  // prévia instantânea (§9) — mesma regra do banco
  const previa: ResultadoComissao = useMemo(
    () =>
      calcularComissao({
        servicoZigCentavos: f.servico_zig_centavos,
        servicoAjusteCentavos: params.ajuste,
        percentualRetencao: percentual ?? f.percentual_retencao,
        proporcionalDias: params.proporcional,
        dataInicio: f.data_inicio,
        dataFim: f.data_fim,
        participantes: itens.map((i) => ({
          funcionarioId: i.funcionario_id,
          nome: i.funcionario_nome,
          cargo: i.cargo,
          diasTrabalhados: i.dias_trabalhados,
          ...itemEfetivo(i),
        })),
      }),
    [f, itens, params, edicoes, percentual],
  )

  // conferência: sem alterações, a prévia tem de bater com o banco
  const confere = !sujo && previa.itens.every((p, k) => p.valorCentavos === itens[k]?.valor_centavos) && previa.baseCentavos === f.base_distribuivel_centavos

  const disponiveis = (funcionarios.data ?? []).filter((x) => x.ativo && !itens.some((i) => i.funcionario_id === x.id))

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
        })
      if (itensAlterados.length)
        await definirItens.mutateAsync({
          id: f.id,
          itens: itensAlterados.map(([fid, e]) => ({ funcionarioId: fid, pontos: lerNumero(e.pontos) ?? 0, incluido: e.incluido })),
        })
      avisos.sucesso('Rascunho salvo e recalculado')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const incluirParticipante = async () => {
    if (!adicionar) return
    try {
      const pontos = Number(await chamarRpc('pontos_vigentes', { p_funcionario: adicionar, p_data: f.data_fim })) || 0
      await definirItens.mutateAsync({ id: f.id, itens: [{ funcionarioId: adicionar, pontos, incluido: true }] })
      setAdicionar('')
      avisos.sucesso('Participante incluído')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const exportar = () => {
    if (sujo) avisos.info('Exportando os valores salvos (as alterações não salvas não entram).')
    const { nome, conteudo } = csvComissao(f, itens, empresa?.nome ?? 'empresa')
    baixarCsv(nome, conteudo)
  }

  const acaoFechar = async () => {
    const ok = await avisos.confirmar({
      titulo: 'Fechar a comissão?',
      mensagem: (
        <>
          Base distribuível <strong>{formatarCentavos(f.base_distribuivel_centavos)}</strong> para {itens.filter((i) => i.incluido && Number(i.pontos_efetivos) > 0).length} participante(s) com pontos.
          Depois de fechado, o fechamento não pode mais ser alterado nem excluído.
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

  const ocupado = atualizar.isPending || definirItens.isPending || removerItem.isPending || recalcular.isPending

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
              <Botao icone={<Lock aria-hidden className="size-4" />} onClick={acaoFechar} carregando={fechar.isPending} disabled={sujo || ocupado || f.valor_ponto_centavos == null}>
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
          <Botao tamanho="p" icone={<Check aria-hidden className="size-4" />} carregando={atualizar.isPending || definirItens.isPending} onClick={salvar}>
            Salvar
          </Botao>
        </div>
      )}
      {rascunho && !administrar && <p className="mb-4 text-sm text-lavanda">Somente o administrador fecha a comissão. Você pode preparar o rascunho.</p>}

      <div className="grid grid-cols-[minmax(0,1fr)] gap-5 xl:grid-cols-[minmax(0,380px)_minmax(0,1fr)]">
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
            <Linha rotulo="Base distribuível" valor={formatarCentavos(previa.baseCentavos)} forte ouro />
            <Linha rotulo="Soma dos pontos" valor={fmtPontos(previa.somaPontosEfetivos, 6)} />
            <Linha
              rotulo="Valor do ponto"
              valor={previa.valorPontoCentavos == null ? '—' : formatarCentavos(Math.round(previa.valorPontoCentavos))}
              detalhe={previa.valorPontoCentavos == null ? undefined : `${previa.valorPontoCentavos.toLocaleString('pt-BR', { maximumFractionDigits: 6 })} centavos`}
            />
            <div className="pt-2">
              <Interruptor
                rotulo="Proporcional aos dias trabalhados"
                marcado={params.proporcional}
                desabilitado={!rascunho}
                aoMudar={(v) => setParams((p) => ({ ...p, proporcional: v }))}
              />
            </div>
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
            <div className="mt-5 flex flex-wrap gap-2 border-t border-borda pt-4">
              <Botao
                variante="secundario"
                tamanho="p"
                icone={<RefreshCw aria-hidden className="size-4" />}
                carregando={recalcular.isPending}
                disabled={sujo}
                title={sujo ? 'Salve ou descarte as alterações antes' : 'Relê o serviço da Zig e os dias trabalhados'}
                onClick={async () => {
                  try {
                    await recalcular.mutateAsync(f.id)
                    avisos.sucesso('Recalculado com o serviço e a presença atuais')
                  } catch (e) {
                    avisos.erro(e)
                  }
                }}
              >
                Reler serviço e presença
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
          )}
        </Cartao>

        <Cartao
          sobrancelha={`${previa.itens.filter((i) => i.incluido && i.pontosEfetivos > 0).length} participante(s)`}
          titulo="Rateio por funcionário"
          acoes={confere ? <Selo tom="sucesso">Prévia confere com o banco</Selo> : sujo ? <Selo tom="ouro">Prévia</Selo> : null}
          semPreenchimento
        >
          {itens.length === 0 ? (
            <div className="p-5">
              <Vazio titulo="Sem participantes" descricao="Inclua funcionários abaixo para ratear o serviço." />
            </div>
          ) : (
            <div className="relative overflow-x-auto">
              <table className="w-full min-w-[640px] text-sm">
                <thead>
                  <tr className="bg-cartao-2/70 text-[11px] font-bold tracking-[0.14em] text-lavanda uppercase">
                    <th scope="col" className="px-5 py-3 text-left">Funcionário</th>
                    <th scope="col" className="px-3 py-3 text-center">Incluído</th>
                    <th scope="col" className="px-3 py-3 text-right">Pontos</th>
                    <th scope="col" className="px-3 py-3 text-right">Dias</th>
                    <th scope="col" className="px-3 py-3 text-right">Pts efetivos</th>
                    <th scope="col" className="px-3 py-3 text-right">Valor</th>
                    {rascunho && <th scope="col" className="px-3 py-3"><span className="sr-only">Ações</span></th>}
                  </tr>
                </thead>
                <tbody>
                  {itens.map((i, k) => {
                    const p = previa.itens[k]
                    const efetivo = itemEfetivo(i)
                    const fid = i.funcionario_id
                    const edicao = fid ? edicoes[fid] : undefined
                    const mudou = edicao && (lerNumero(edicao.pontos) !== i.pontos || edicao.incluido !== i.incluido)
                    return (
                      <tr key={i.id} className={clsx('border-t border-borda', !efetivo.incluido && 'opacity-60', mudou && 'bg-ouro/5')}>
                        <td className="px-5 py-3">
                          <p className="font-semibold text-creme">{i.funcionario_nome}</p>
                          {i.cargo && <p className="text-xs text-lavanda">{i.cargo}</p>}
                        </td>
                        <td className="px-3 py-3 text-center">
                          {rascunho && fid ? (
                            <Caixa
                              rotulo={<span className="sr-only">Incluir {i.funcionario_nome}</span>}
                              marcado={efetivo.incluido}
                              aoMudar={(v) => setEdicoes((e) => ({ ...e, [fid]: { pontos: e[fid]?.pontos ?? String(i.pontos).replace('.', ','), incluido: v } }))}
                            />
                          ) : efetivo.incluido ? (
                            'Sim'
                          ) : (
                            'Não'
                          )}
                        </td>
                        <td className="px-3 py-3 text-right">
                          {rascunho && fid ? (
                            <Entrada
                              aria-label={`Pontos de ${i.funcionario_nome}`}
                              className="numero ml-auto h-9 w-20 text-right"
                              inputMode="decimal"
                              value={edicao?.pontos ?? String(i.pontos).replace('.', ',')}
                              onChange={(e) => {
                                const v = e.target.value.replace(/[^\d,.]/g, '')
                                setEdicoes((x) => ({ ...x, [fid]: { pontos: v, incluido: x[fid]?.incluido ?? i.incluido } }))
                              }}
                            />
                          ) : (
                            <span className="numero">{fmtPontos(i.pontos)}</span>
                          )}
                        </td>
                        <td className="numero px-3 py-3 text-right text-lavanda">
                          {i.dias_trabalhados}/{f.dias_periodo}
                        </td>
                        <td className="numero px-3 py-3 text-right">{fmtPontos(p?.pontosEfetivos ?? 0, 6)}</td>
                        <td className="numero px-3 py-3 text-right font-semibold whitespace-nowrap text-ouro-claro">
                          {formatarCentavos(p?.valorCentavos ?? 0)}
                          {p?.centavoExtra && (
                            <span className="ml-1 text-[10px] text-lavanda" title="Recebeu +1 centavo no arredondamento pelo maior resto">
                              +1¢
                            </span>
                          )}
                        </td>
                        {rascunho && (
                          <td className="px-3 py-3 text-right">
                            {fid && (
                              <Botao
                                variante="fantasma"
                                tamanho="p"
                                aria-label={`Remover ${i.funcionario_nome}`}
                                icone={<X aria-hidden className="size-4" />}
                                disabled={ocupado}
                                onClick={async () => {
                                  if (!(await avisos.confirmar({ titulo: `Remover ${i.funcionario_nome} do fechamento?`, textoConfirmar: 'Remover', perigo: true }))) return
                                  try {
                                    await removerItem.mutateAsync({ id: f.id, funcionarioId: fid })
                                  } catch (e) {
                                    avisos.erro(e)
                                  }
                                }}
                              />
                            )}
                          </td>
                        )}
                      </tr>
                    )
                  })}
                </tbody>
                <tfoot>
                  <tr className="border-t-2 border-borda-forte font-semibold">
                    <td className="px-5 py-3 text-creme">Total</td>
                    <td />
                    <td className="numero px-3 py-3 text-right">
                      {fmtPontos(itens.reduce((s, i) => s + (itemEfetivo(i).incluido ? itemEfetivo(i).pontos : 0), 0))}
                    </td>
                    <td />
                    <td className="numero px-3 py-3 text-right">{fmtPontos(previa.somaPontosEfetivos, 6)}</td>
                    <td className="numero px-3 py-3 text-right text-ouro-claro">{formatarCentavos(previa.totalDistribuidoCentavos)}</td>
                    {rascunho && <td />}
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
          {rascunho && (
            <div className="flex flex-wrap items-end gap-2 border-t border-borda p-5">
              <div className="min-w-0 flex-1">
                <Campo rotulo="Incluir participante" htmlFor={`${id}-add`}>
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
              <Botao variante="secundario" icone={<UserPlus aria-hidden className="size-4" />} disabled={!adicionar || ocupado} carregando={definirItens.isPending && !!adicionar} onClick={incluirParticipante}>
                Incluir
              </Botao>
            </div>
          )}
        </Cartao>
      </div>
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
