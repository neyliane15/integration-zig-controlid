/**
 * Aba "Dias trabalhados" (adendo E.2): dia de um extra (pontos e valor vêm do cadastro, editáveis; os pontos entram na comissão
 * daquele dia) ou diária de funcionário (só custo). Filtro por período e tipo, totais, pagamento e CSV.
 */
import { useEffect, useId, useMemo, useState } from 'react'
import { CalendarPlus, Check, Download, Lock, Pencil, Trash2, Undo2, UserPlus, Wallet } from 'lucide-react'
import type { Diaria, Extra, TipoDiaria } from '@/tipos/banco'
import {
  AreaTexto,
  Botao,
  Caixa,
  Campo,
  Cartao,
  Entrada,
  EntradaData,
  EntradaMoeda,
  ErroCarga,
  Indicador,
  Modal,
  Pilulas,
  Selecao,
  Selo,
  Tabela,
  Vazio,
  type Coluna,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { useContextoEmpresa, useFuncionarios } from '@/consultas/funcionarios'
import { useDiarias, useExcluirDiaria, useExtras, useMarcarDiariaPaga, useSalvarDiaria, useValoresDiaria } from '@/consultas/extras'
import { csvDiarias, lerPontos, pontosTexto, totaisDiarias } from '@/lib/extras'
import { baixarCsv } from '@/lib/csv'
import { formatarCentavos, formatarData, somarDias } from '@/lib/formato'
import { ModalExtra } from './AbaExtras'

type Filtro = 'todos' | TipoDiaria

export function AbaDias({
  inicio,
  fim,
  lancarPara,
  aoConsumirLancar,
}: {
  inicio: string
  fim: string
  /** id de extra vindo do cadastro ("Lançar dia") */
  lancarPara?: string | null
  aoConsumirLancar?(): void
}) {
  const avisos = useAvisos()
  const { hoje, empresa } = useContextoEmpresa()
  const [filtro, setFiltro] = useState<Filtro>('todos')
  const lista = useDiarias(inicio, fim)
  const marcar = useMarcarDiariaPaga()
  const excluir = useExcluirDiaria()
  const [modal, setModal] = useState<{ diaria: Diaria | null; extraId?: string | null } | null>(null)
  const todas = lista.data ?? []
  const linhas = filtro === 'todos' ? todas : todas.filter((d) => d.tipo === filtro)
  const t = totaisDiarias(linhas)

  useEffect(() => {
    if (lancarPara) {
      setModal({ diaria: null, extraId: lancarPara })
      aoConsumirLancar?.()
    }
  }, [lancarPara, aoConsumirLancar])

  const alternarPago = async (d: Diaria) => {
    try {
      await marcar.mutateAsync({ id: d.id, pago: !d.pago, pagoEm: d.pago ? null : hoje })
      avisos.sucesso(d.pago ? 'Pagamento desfeito' : `Dia de ${d.pessoa_nome} marcado como pago`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const apagar = async (d: Diaria) => {
    const ok = await avisos.confirmar({
      titulo: `Excluir o dia de ${d.pessoa_nome}?`,
      mensagem: `${formatarData(d.data)} · ${formatarCentavos(d.valor_centavos)}${d.tipo === 'extra' ? ' · os pontos saem da comissão do dia (recalcule o rascunho)' : ''}`,
      textoConfirmar: 'Excluir',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluir.mutateAsync(d.id)
      avisos.sucesso('Lançamento excluído')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const colunas: Coluna<Diaria>[] = [
    {
      id: 'pessoa',
      titulo: 'Pessoa',
      render: (d) => (
        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-2 font-semibold text-creme">
            <span className="truncate">{d.pessoa_nome}</span>
            {d.tipo === 'extra' ? <Selo tom="info">Extra</Selo> : <Selo>Funcionário</Selo>}
          </p>
          {d.funcao && <p className="text-xs text-lavanda">{d.funcao}</p>}
        </div>
      ),
    },
    {
      id: 'data',
      titulo: 'Data',
      render: (d) => (
        <span className="numero inline-flex items-center gap-1.5">
          {formatarData(d.data)}
          {d.fechado && <Lock aria-label="Comissão do dia já fechada" className="size-3.5 text-lavanda" />}
        </span>
      ),
    },
    {
      id: 'pontos',
      titulo: 'Pontos',
      alinhar: 'direita',
      render: (d) => <span className="numero">{d.tipo === 'extra' ? pontosTexto(d.pontos) : <span className="text-lavanda-escuro">—</span>}</span>,
    },
    { id: 'valor', titulo: 'Valor', alinhar: 'direita', render: (d) => <span className="numero font-semibold whitespace-nowrap">{formatarCentavos(d.valor_centavos)}</span> },
    {
      id: 'pago',
      titulo: 'Pagamento',
      ocultarNoCelular: true,
      render: (d) =>
        d.pago ? (
          <Selo tom="sucesso">
            <Check aria-hidden /> Pago{d.pago_em ? ` em ${formatarData(d.pago_em)}` : ''}
          </Selo>
        ) : (
          <Selo tom="alerta">A pagar</Selo>
        ),
    },
    { id: 'obs', titulo: 'Observação', ocultarNoCelular: true, render: (d) => <span className="text-sm break-words text-lavanda">{d.observacao ?? '—'}</span> },
    {
      id: 'acoes',
      titulo: '',
      alinhar: 'direita',
      render: (d) => (
        <div className="flex justify-end gap-1">
          <Botao
            variante={d.pago ? 'fantasma' : 'secundario'}
            tamanho="p"
            icone={d.pago ? <Undo2 aria-hidden /> : <Check aria-hidden />}
            onClick={() => alternarPago(d)}
            disabled={marcar.isPending}
            aria-label={d.pago ? `Desfazer pagamento de ${d.pessoa_nome}` : `Marcar dia de ${d.pessoa_nome} como pago`}
          >
            {d.pago ? '' : 'Pagar'}
          </Botao>
          <Botao variante="fantasma" tamanho="p" icone={<Pencil aria-hidden />} aria-label={`Editar dia de ${d.pessoa_nome}`} onClick={() => setModal({ diaria: d })} />
          {!d.fechado && (
            <Botao variante="fantasma" tamanho="p" icone={<Trash2 aria-hidden />} aria-label={`Excluir dia de ${d.pessoa_nome}`} onClick={() => apagar(d)} />
          )}
        </div>
      ),
    },
  ]

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-4">
        <Indicador rotulo="Total" valor={formatarCentavos(t.total)} tom="ouro" detalhe={`${t.quantidade} lançamento(s)`} />
        <Indicador rotulo="A pagar" valor={formatarCentavos(t.aPagar)} tom={t.aPagar > 0 ? 'alerta' : undefined} detalhe={`${formatarCentavos(t.pagas)} já pago`} />
        <Indicador rotulo="Dias de extras" valor={t.diasExtras} detalhe={`${pontosTexto(t.pontos)} ponto(s) na comissão`} tom="info" />
        <Indicador rotulo="Diárias de funcionários" valor={formatarCentavos(t.funcionarios)} detalhe="só custo, sem pontos" />
      </div>
      <Cartao
        titulo="Dias trabalhados"
        sobrancelha={`${formatarData(inicio)} a ${formatarData(fim)}`}
        acoes={
          <>
            <Botao
              variante="secundario"
              tamanho="p"
              icone={<Download aria-hidden />}
              disabled={linhas.length === 0}
              onClick={() => {
                const { nome, conteudo } = csvDiarias(linhas, empresa?.nome ?? 'empresa', inicio, fim)
                baixarCsv(nome, conteudo)
              }}
            >
              CSV
            </Botao>
            <Botao tamanho="p" icone={<CalendarPlus aria-hidden />} onClick={() => setModal({ diaria: null })}>
              Lançar dia
            </Botao>
          </>
        }
      >
        <div className="mb-4">
          <Pilulas<Filtro>
            rotulo="Mostrar"
            opcoes={[
              { id: 'todos', rotulo: 'Todos' },
              { id: 'extra', rotulo: 'Extras' },
              { id: 'funcionario', rotulo: 'Funcionários' },
            ]}
            valor={filtro}
            aoMudar={setFiltro}
          />
        </div>
        {lista.error ? (
          <ErroCarga erro={lista.error} aoTentar={() => lista.refetch()} />
        ) : (
          <Tabela
            colunas={colunas}
            linhas={linhas}
            chave={(d) => d.id}
            carregando={lista.isLoading}
            vazio={
              <Vazio
                icone={<Wallet aria-hidden />}
                titulo="Nenhum dia lançado no período"
                descricao="Lance os dias trabalhados pelos extras (entram na comissão do dia) e as diárias de funcionários."
                acao={
                  <Botao icone={<CalendarPlus aria-hidden />} onClick={() => setModal({ diaria: null })}>
                    Lançar dia
                  </Botao>
                }
              />
            }
          />
        )}
      </Cartao>
      <ModalDia aberto={!!modal} diaria={modal?.diaria ?? null} extraInicial={modal?.extraId ?? null} aoFechar={() => setModal(null)} />
    </div>
  )
}

export function ModalDia({
  aberto,
  diaria,
  extraInicial,
  aoFechar,
}: {
  aberto: boolean
  diaria: Diaria | null
  extraInicial?: string | null
  aoFechar(): void
}) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const extras = useExtras(false)
  const funcionarios = useFuncionarios()
  const valores = useValoresDiaria()
  const salvar = useSalvarDiaria()
  const id = useId()
  const [tipo, setTipo] = useState<TipoDiaria>('extra')
  const [extraId, setExtraId] = useState<string | null>(null)
  const [funcionario, setFuncionario] = useState<string | null>(null)
  const [funcao, setFuncao] = useState('')
  const [data, setData] = useState<string | null>(hoje)
  const [pontos, setPontos] = useState('')
  const [valor, setValor] = useState<number | null>(null)
  const [observacao, setObservacao] = useState('')
  const [pago, setPago] = useState(false)
  const [pagoEm, setPagoEm] = useState<string | null>(hoje)
  const [tentou, setTentou] = useState(false)
  const [cadastrar, setCadastrar] = useState(false)

  const ativos = useMemo(() => (extras.data ?? []).filter((x) => x.ativo), [extras.data])

  const aplicarExtra = (x: Extra | undefined) => {
    setPontos(x ? pontosTexto(x.pontos_padrao) : '')
    setValor(x?.valor_diaria_centavos ?? null)
    setFuncao(x?.funcao ?? '')
  }

  useEffect(() => {
    if (!aberto) return
    setTipo(diaria?.tipo ?? 'extra')
    setExtraId(diaria?.extra_id ?? extraInicial ?? null)
    setFuncionario(diaria?.funcionario_id ?? null)
    setFuncao(diaria?.funcao ?? '')
    setData(diaria?.data ?? hoje)
    setPontos(diaria?.pontos != null ? pontosTexto(diaria.pontos) : '')
    setValor(diaria?.valor_centavos ?? null)
    setObservacao(diaria?.observacao ?? '')
    setPago(diaria?.pago ?? false)
    setPagoEm(diaria?.pago_em ?? hoje)
    setTentou(false)
    setCadastrar(false)
  }, [aberto, diaria, hoje, extraInicial])

  // extra vindo do cadastro ("Lançar dia"): pré-preenche quando a lista chega
  useEffect(() => {
    if (aberto && !diaria && extraInicial && extras.data) aplicarExtra(extras.data.find((x) => x.id === extraInicial))
  }, [aberto, diaria, extraInicial, extras.data])

  const escolherExtra = (xid: string | null) => {
    setExtraId(xid)
    aplicarExtra(ativos.find((x) => x.id === xid))
  }

  const escolherFuncionario = (fid: string | null) => {
    setFuncionario(fid)
    const f = (funcionarios.data ?? []).find((x) => x.id === fid)
    setFuncao(f?.cargo ?? '')
    setValor(fid ? (valores.data?.get(fid) ?? null) : null)
  }

  const travado = !!diaria?.fechado
  const extraEscolhido = (extras.data ?? []).find((x) => x.id === extraId)
  const pontosLidos = pontos.trim() === '' ? null : lerPontos(pontos)
  const erros = {
    pessoa: tipo === 'extra' ? (!extraId ? 'Escolha o extra' : null) : !funcionario ? 'Escolha o funcionário' : null,
    data: !data ? 'Informe a data' : !travado && (data < somarDias(hoje, -366) || data > somarDias(hoje, 62)) ? 'Data fora do limite' : null,
    pontos: tipo === 'extra' && (pontos.trim() === '' || pontosLidos == null) ? 'Pontos inválidos (0 a 9999,99)' : null,
    valor: valor == null ? 'Informe o valor da diária' : valor < 0 || valor > 100_000_000 ? 'Valor inválido' : null,
  }

  const enviar = async () => {
    setTentou(true)
    const primeiro = Object.values(erros).find(Boolean)
    if (primeiro) return avisos.erro(primeiro)
    try {
      await salvar.mutateAsync({
        id: diaria?.id,
        dados: {
          data: data!,
          extraId: tipo === 'extra' ? extraId : null,
          funcionarioId: tipo === 'funcionario' ? funcionario : null,
          pontos: tipo === 'extra' ? pontosLidos : null,
          valorCentavos: valor,
          funcao: funcao.trim() || null,
          observacao: observacao.trim() || null,
          pago,
          pagoEm: pago ? pagoEm : null,
        },
      })
      avisos.sucesso(diaria ? 'Lançamento atualizado' : tipo === 'extra' ? `Dia de ${extraEscolhido?.nome ?? 'extra'} lançado` : 'Diária lançada')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <>
      <Modal
        aberto={aberto && !cadastrar}
        aoFechar={aoFechar}
        titulo={diaria ? `Editar dia de ${diaria.pessoa_nome}` : 'Lançar dia trabalhado'}
        rodape={
          <>
            <Botao variante="secundario" onClick={aoFechar}>
              Cancelar
            </Botao>
            <Botao onClick={enviar} carregando={salvar.isPending}>
              {diaria ? 'Salvar' : 'Lançar'}
            </Botao>
          </>
        }
      >
        <div className="grid gap-4 sm:grid-cols-2">
          {!diaria && (
            <div className="sm:col-span-2">
              <Pilulas<TipoDiaria>
                rotulo="Quem trabalhou"
                opcoes={[
                  { id: 'extra', rotulo: 'Extra (freela)' },
                  { id: 'funcionario', rotulo: 'Funcionário (só custo)' },
                ]}
                valor={tipo}
                aoMudar={(v) => {
                  setTipo(v)
                  if (v === 'extra') aplicarExtra(extraEscolhido)
                  else escolherFuncionario(funcionario)
                }}
              />
            </div>
          )}
          <div className="sm:col-span-2">
            {diaria ? (
              <p className="flex flex-wrap items-center gap-2 text-sm text-lavanda">
                <span className="font-semibold text-creme">{diaria.pessoa_nome}</span>
                {diaria.tipo === 'extra' ? <Selo tom="info">Extra</Selo> : <Selo>Funcionário</Selo>}
                <span>· para trocar a pessoa, exclua e lance de novo.</span>
              </p>
            ) : tipo === 'extra' ? (
              <div className="flex flex-wrap items-end gap-2">
                <div className="min-w-0 flex-1 basis-56">
                  <Campo rotulo="Extra" htmlFor={`${id}-x`} obrigatorio erro={tentou ? erros.pessoa : null}>
                    <Selecao id={`${id}-x`} value={extraId ?? ''} disabled={extras.isLoading} onChange={(e) => escolherExtra(e.target.value || null)}>
                      <option value="">{extras.isLoading ? 'Carregando…' : ativos.length ? 'Escolha…' : 'Nenhum extra cadastrado'}</option>
                      {ativos.map((x) => (
                        <option key={x.id} value={x.id}>
                          {x.nome}
                          {x.funcao ? ` — ${x.funcao}` : ''}
                        </option>
                      ))}
                    </Selecao>
                  </Campo>
                </div>
                <Botao variante="secundario" icone={<UserPlus aria-hidden className="size-4" />} onClick={() => setCadastrar(true)}>
                  Cadastrar extra
                </Botao>
              </div>
            ) : (
              <Campo rotulo="Funcionário" htmlFor={`${id}-f`} obrigatorio erro={tentou ? erros.pessoa : null} ajuda="Diária de funcionário é só custo: não entra na comissão.">
                <SeletorFuncionario id={`${id}-f`} valor={funcionario} aoMudar={escolherFuncionario} somenteAtivos />
              </Campo>
            )}
          </div>
          <Campo rotulo="Data" htmlFor={`${id}-d`} obrigatorio erro={tentou ? erros.data : null}>
            <EntradaData id={`${id}-d`} valor={data} aoMudar={setData} desabilitado={travado} />
          </Campo>
          <Campo rotulo="Função do dia" htmlFor={`${id}-fn`} ajuda={tipo === 'extra' ? 'Padrão: a função do cadastro.' : 'Padrão: o cargo.'}>
            <Entrada id={`${id}-fn`} value={funcao} maxLength={80} onChange={(e) => setFuncao(e.target.value)} />
          </Campo>
          {tipo === 'extra' && (
            <Campo
              rotulo="Pontos do dia"
              htmlFor={`${id}-p`}
              obrigatorio
              erro={tentou ? erros.pontos : null}
              ajuda={extraEscolhido ? `Padrão do cadastro: ${pontosTexto(extraEscolhido.pontos_padrao)}` : 'Entram no rateio da comissão deste dia.'}
            >
              <Entrada
                id={`${id}-p`}
                className="numero"
                inputMode="decimal"
                value={pontos}
                disabled={travado}
                invalido={tentou && !!erros.pontos}
                onChange={(e) => setPontos(e.target.value.replace(/[^\d,.]/g, ''))}
              />
            </Campo>
          )}
          <Campo
            rotulo="Valor da diária"
            htmlFor={`${id}-v`}
            obrigatorio
            erro={tentou ? erros.valor : null}
            ajuda={
              tipo === 'extra'
                ? extraEscolhido?.valor_diaria_centavos != null
                  ? `Padrão do cadastro: ${formatarCentavos(extraEscolhido.valor_diaria_centavos)}`
                  : undefined
                : funcionario && valores.data?.get(funcionario) != null
                  ? `Padrão do funcionário: ${formatarCentavos(valores.data.get(funcionario)!)}`
                  : undefined
            }
          >
            <EntradaMoeda id={`${id}-v`} centavos={valor} aoMudar={setValor} />
          </Campo>
          {travado && (
            <p className="flex items-start gap-2 text-xs text-lavanda sm:col-span-2">
              <Lock aria-hidden className="mt-0.5 size-3.5 shrink-0" />A comissão deste dia já foi fechada: data e pontos não mudam. Pagamento, valor e
              observação continuam editáveis.
            </p>
          )}
          <div className="flex flex-col justify-end gap-3">
            <Caixa rotulo="Já foi pago" marcado={pago} aoMudar={setPago} />
          </div>
          {pago && (
            <Campo rotulo="Data do pagamento" htmlFor={`${id}-pg`}>
              <EntradaData id={`${id}-pg`} valor={pagoEm} aoMudar={setPagoEm} />
            </Campo>
          )}
          <div className="sm:col-span-2">
            <Campo rotulo="Observação" htmlFor={`${id}-o`}>
              <AreaTexto id={`${id}-o`} className="min-h-16" value={observacao} onChange={(e) => setObservacao(e.target.value)} />
            </Campo>
          </div>
        </div>
      </Modal>
      <ModalExtra
        aberto={aberto && cadastrar}
        extra={null}
        aoFechar={() => setCadastrar(false)}
        aoSalvar={async (novoId) => {
          const r = await extras.refetch()
          setTipo('extra')
          setExtraId(novoId)
          aplicarExtra((r.data ?? []).find((x) => x.id === novoId))
        }}
      />
    </>
  )
}
