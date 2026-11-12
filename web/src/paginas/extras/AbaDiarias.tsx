import { useEffect, useId, useState } from 'react'
import { Check, Download, Pencil, Plus, Trash2, Undo2, Wallet } from 'lucide-react'
import type { Diaria } from '@/tipos/banco'
import { AreaTexto, Botao, Caixa, Campo, Cartao, Entrada, EntradaData, EntradaMoeda, ErroCarga, Indicador, Modal, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { useContextoEmpresa, useFuncionarios } from '@/consultas/funcionarios'
import { useDiarias, useExcluirDiaria, useMarcarDiariaPaga, useSalvarDiaria, useValoresDiaria } from '@/consultas/extras'
import { csvDiarias, totaisDiarias } from '@/lib/extras'
import { baixarCsv } from '@/lib/csv'
import { formatarCentavos, formatarData, somarDias } from '@/lib/formato'

export function AbaDiarias({ inicio, fim }: { inicio: string; fim: string }) {
  const avisos = useAvisos()
  const { hoje, empresa } = useContextoEmpresa()
  const lista = useDiarias(inicio, fim)
  const marcar = useMarcarDiariaPaga()
  const excluir = useExcluirDiaria()
  const [modal, setModal] = useState<{ diaria: Diaria | null } | null>(null)
  const linhas = lista.data ?? []
  const t = totaisDiarias(linhas)

  const alternarPago = async (d: Diaria) => {
    try {
      await marcar.mutateAsync({ id: d.id, pago: !d.pago, pagoEm: d.pago ? null : hoje })
      avisos.sucesso(d.pago ? 'Pagamento desfeito' : `Diária de ${d.pessoa_nome} marcada como paga`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const apagar = async (d: Diaria) => {
    const ok = await avisos.confirmar({
      titulo: `Excluir a diária de ${d.pessoa_nome}?`,
      mensagem: `${formatarData(d.data)} · ${formatarCentavos(d.valor_centavos)}`,
      textoConfirmar: 'Excluir',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluir.mutateAsync(d.id)
      avisos.sucesso('Diária excluída')
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
            {d.avulso && <Selo tom="info">Avulso</Selo>}
          </p>
          {d.funcao && <p className="text-xs text-lavanda">{d.funcao}</p>}
        </div>
      ),
    },
    { id: 'data', titulo: 'Data', render: (d) => <span className="numero">{formatarData(d.data)}</span> },
    { id: 'valor', titulo: 'Valor', alinhar: 'direita', render: (d) => <span className="numero font-semibold">{formatarCentavos(d.valor_centavos)}</span> },
    {
      id: 'pago',
      titulo: 'Pagamento',
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
        <div className="flex flex-wrap justify-end gap-1">
          <Botao
            variante={d.pago ? 'fantasma' : 'secundario'}
            tamanho="p"
            icone={d.pago ? <Undo2 aria-hidden /> : <Check aria-hidden />}
            onClick={() => alternarPago(d)}
            disabled={marcar.isPending}
            aria-label={d.pago ? `Desfazer pagamento de ${d.pessoa_nome}` : `Marcar diária de ${d.pessoa_nome} como paga`}
          >
            {d.pago ? '' : 'Pagar'}
          </Botao>
          <Botao variante="fantasma" tamanho="p" icone={<Pencil aria-hidden />} aria-label={`Editar diária de ${d.pessoa_nome}`} onClick={() => setModal({ diaria: d })} />
          <Botao variante="fantasma" tamanho="p" icone={<Trash2 aria-hidden />} aria-label={`Excluir diária de ${d.pessoa_nome}`} onClick={() => apagar(d)} />
        </div>
      ),
    },
  ]

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-4">
        <Indicador rotulo="Total" valor={formatarCentavos(t.total)} tom="ouro" detalhe={`${t.quantidade} diária(s)`} />
        <Indicador rotulo="Pagas" valor={formatarCentavos(t.pagas)} tom="sucesso" />
        <Indicador rotulo="A pagar" valor={formatarCentavos(t.aPagar)} tom={t.aPagar > 0 ? 'alerta' : undefined} />
        <Indicador rotulo="Média" valor={t.quantidade ? formatarCentavos(Math.round(t.total / t.quantidade)) : '—'} detalhe="por diária" />
      </div>
      <Cartao
        titulo="Diárias do período"
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
            <Botao tamanho="p" icone={<Plus aria-hidden />} onClick={() => setModal({ diaria: null })}>
              Lançar diária
            </Botao>
          </>
        }
      >
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
                titulo="Nenhuma diária no período"
                descricao="Lance as diárias de freelancers e de funcionários que cobriram turnos extras."
                acao={
                  <Botao icone={<Plus aria-hidden />} onClick={() => setModal({ diaria: null })}>
                    Lançar diária
                  </Botao>
                }
              />
            }
          />
        )}
      </Cartao>
      <ModalDiaria aberto={!!modal} diaria={modal?.diaria ?? null} aoFechar={() => setModal(null)} />
    </div>
  )
}

function ModalDiaria({ aberto, diaria, aoFechar }: { aberto: boolean; diaria: Diaria | null; aoFechar(): void }) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const funcionarios = useFuncionarios()
  const valores = useValoresDiaria()
  const salvar = useSalvarDiaria()
  const id = useId()
  const [avulso, setAvulso] = useState(false)
  const [funcionario, setFuncionario] = useState<string | null>(null)
  const [nome, setNome] = useState('')
  const [funcao, setFuncao] = useState('')
  const [data, setData] = useState<string | null>(hoje)
  const [valor, setValor] = useState<number | null>(null)
  const [observacao, setObservacao] = useState('')
  const [pago, setPago] = useState(false)
  const [pagoEm, setPagoEm] = useState<string | null>(hoje)
  const [tentou, setTentou] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setAvulso(diaria ? diaria.avulso : false)
    setFuncionario(diaria?.funcionario_id ?? null)
    setNome(diaria?.avulso ? diaria.pessoa_nome : '')
    setFuncao(diaria?.funcao ?? '')
    setData(diaria?.data ?? hoje)
    setValor(diaria?.valor_centavos ?? null)
    setObservacao(diaria?.observacao ?? '')
    setPago(diaria?.pago ?? false)
    setPagoEm(diaria?.pago_em ?? hoje)
    setTentou(false)
  }, [aberto, diaria, hoje])

  const escolherFuncionario = (fid: string | null) => {
    setFuncionario(fid)
    const f = (funcionarios.data ?? []).find((x) => x.id === fid)
    if (f?.cargo) setFuncao(f.cargo)
    const padrao = fid ? valores.data?.get(fid) : undefined
    if (padrao != null) setValor(padrao)
  }

  const padraoDoFuncionario = !avulso && funcionario ? valores.data?.get(funcionario) : undefined
  const erros = {
    pessoa: avulso ? (!nome.trim() ? 'Informe o nome' : null) : !funcionario ? 'Escolha o funcionário' : null,
    data: !data ? 'Informe a data' : data < somarDias(hoje, -366) || data > somarDias(hoje, 62) ? 'Data fora do limite' : null,
    valor: valor == null && padraoDoFuncionario == null ? 'Informe o valor da diária' : valor != null && (valor < 0 || valor > 100_000_000) ? 'Valor inválido' : null,
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
          funcionarioId: avulso ? null : funcionario,
          pessoaNome: avulso ? nome.trim() : null,
          funcao: funcao.trim() || null,
          valorCentavos: valor,
          observacao: observacao.trim() || null,
          pago,
          pagoEm: pago ? pagoEm : null,
        },
      })
      avisos.sucesso(diaria ? 'Diária atualizada' : 'Diária lançada')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto={aberto}
      aoFechar={aoFechar}
      titulo={diaria ? 'Editar diária' : 'Lançar diária'}
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
        <div className="flex flex-wrap gap-1.5 sm:col-span-2" role="radiogroup" aria-label="Quem recebe">
          {[
            { v: false, r: 'Funcionário cadastrado' },
            { v: true, r: 'Avulso (freelancer)' },
          ].map((o) => (
            <button
              key={String(o.v)}
              type="button"
              role="radio"
              aria-checked={avulso === o.v}
              onClick={() => setAvulso(o.v)}
              className={`h-9 rounded-pilula border px-3.5 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ouro ${
                avulso === o.v ? 'border-ouro/60 bg-ouro/10 text-ouro-claro' : 'border-borda text-lavanda hover:text-creme'
              }`}
            >
              {o.r}
            </button>
          ))}
        </div>
        <div className="sm:col-span-2">
          {avulso ? (
            <Campo rotulo="Nome" htmlFor={`${id}-n`} obrigatorio erro={tentou ? erros.pessoa : null}>
              <Entrada id={`${id}-n`} value={nome} maxLength={120} onChange={(e) => setNome(e.target.value)} autoComplete="off" />
            </Campo>
          ) : (
            <Campo rotulo="Funcionário" htmlFor={`${id}-f`} obrigatorio erro={tentou ? erros.pessoa : null}>
              <SeletorFuncionario id={`${id}-f`} valor={funcionario} aoMudar={escolherFuncionario} somenteAtivos />
            </Campo>
          )}
        </div>
        <Campo rotulo="Função" htmlFor={`${id}-fn`} ajuda={avulso ? 'Ex.: Garçom, Cozinha, Bar' : 'Padrão: o cargo do funcionário.'}>
          <Entrada id={`${id}-fn`} value={funcao} maxLength={80} onChange={(e) => setFuncao(e.target.value)} />
        </Campo>
        <Campo rotulo="Data" htmlFor={`${id}-d`} obrigatorio erro={tentou ? erros.data : null}>
          <EntradaData id={`${id}-d`} valor={data} aoMudar={setData} />
        </Campo>
        <Campo
          rotulo="Valor"
          htmlFor={`${id}-v`}
          obrigatorio
          erro={tentou ? erros.valor : null}
          ajuda={padraoDoFuncionario != null ? `Padrão do funcionário: ${formatarCentavos(padraoDoFuncionario)}` : !avulso && funcionario ? 'Sem valor padrão no cadastro.' : undefined}
        >
          <EntradaMoeda id={`${id}-v`} centavos={valor} aoMudar={setValor} />
        </Campo>
        <div className="flex flex-col justify-end gap-3">
          <Caixa rotulo="Já foi paga" marcado={pago} aoMudar={setPago} />
        </div>
        {pago && (
          <Campo rotulo="Data do pagamento" htmlFor={`${id}-pg`}>
            <EntradaData id={`${id}-pg`} valor={pagoEm} aoMudar={setPagoEm} />
          </Campo>
        )}
        <div className="sm:col-span-2">
          <Campo rotulo="Observação" htmlFor={`${id}-o`}>
            <AreaTexto id={`${id}-o`} className="min-h-20" value={observacao} onChange={(e) => setObservacao(e.target.value)} />
          </Campo>
        </div>
      </div>
    </Modal>
  )
}
