import { useId, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { HandCoins, Plus } from 'lucide-react'
import { Botao, CabecalhoPagina, Campo, Entrada, ErroCarga, FiltroPeriodo, Interruptor, Modal, Selecao, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useCriarFechamento, useFechamentos, type FechamentoNaLista } from '@/consultas/comissoes'
import { useLojasZig } from '@/consultas/vendas'
import { formatarCentavos, formatarData, somarDias } from '@/lib/formato'
import { rotuloStatusFechamento } from '@/lib/rotulos'
import { tituloPadraoFechamento, validarPeriodoFechamento } from '@/lib/comissao'

export function PaginaComissoes() {
  const navegar = useNavigate()
  const fechamentos = useFechamentos()
  const lojas = useLojasZig()
  const [novo, setNovo] = useState(false)

  const nomeLoja = (id: string | null) => (id ? ((lojas.data ?? []).find((l) => l.loja_id_externo === id)?.nome ?? id) : null)

  const colunas: Coluna<FechamentoNaLista>[] = [
    {
      id: 'titulo',
      titulo: 'Fechamento',
      render: (f) => (
        <div className="min-w-0">
          <p className="truncate font-semibold text-creme">{f.titulo}</p>
          <p className="numero text-xs text-lavanda">
            {formatarData(f.data_inicio)} a {formatarData(f.data_fim)}
            {f.loja_id_externo && <span className="font-sans"> · {nomeLoja(f.loja_id_externo)}</span>}
          </p>
        </div>
      ),
    },
    {
      id: 'status',
      titulo: 'Situação',
      render: (f) => <Selo tom={f.status === 'fechado' ? 'sucesso' : 'ouro'}>{rotuloStatusFechamento[f.status]}</Selo>,
    },
    { id: 'servico', titulo: 'Serviço bruto', alinhar: 'direita', ocultarNoCelular: true, render: (f) => <span className="numero">{formatarCentavos(f.servico_bruto_centavos)}</span> },
    { id: 'base', titulo: 'Base distribuível', alinhar: 'direita', render: (f) => <span className="numero font-semibold text-ouro-claro">{formatarCentavos(f.base_distribuivel_centavos)}</span> },
    { id: 'participantes', titulo: 'Participantes', alinhar: 'direita', render: (f) => <span className="numero">{f.participantes}</span> },
    {
      id: 'ponto',
      titulo: 'Valor do ponto',
      alinhar: 'direita',
      ocultarNoCelular: true,
      render: (f) => <span className="numero">{f.valor_ponto_centavos == null ? '—' : formatarCentavos(Math.round(f.valor_ponto_centavos))}</span>,
    },
  ]

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Serviço"
        titulo={
          <>
            Comissões <span className="titulo-italico">da equipe</span>
          </>
        }
        subtitulo="Serviço (10%) da Zig menos a retenção, rateado pelos pontos de comissão de cada funcionário."
        acoes={
          <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setNovo(true)}>
            Novo fechamento
          </Botao>
        }
      />
      {fechamentos.error ? (
        <ErroCarga erro={fechamentos.error} aoTentar={() => fechamentos.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={fechamentos.data ?? []}
          chave={(f) => f.id}
          carregando={fechamentos.isLoading}
          aoClicarLinha={(f) => navegar(`/comissoes/${f.id}`)}
          vazio={
            <Vazio
              icone={<HandCoins className="size-8" />}
              titulo="Nenhum fechamento ainda"
              descricao="Crie o primeiro fechamento escolhendo o período. O sistema soma o serviço da Zig e calcula a parte de cada um."
              acao={<Botao onClick={() => setNovo(true)}>Novo fechamento</Botao>}
            />
          }
        />
      )}
      {novo && <ModalNovoFechamento aoFechar={() => setNovo(false)} aoCriar={(id) => navegar(`/comissoes/${id}`)} />}
    </div>
  )
}

function ModalNovoFechamento({ aoFechar, aoCriar }: { aoFechar(): void; aoCriar(id: string): void }) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const criar = useCriarFechamento()
  const lojas = useLojasZig()
  const inicioMes = `${hoje.slice(0, 7)}-01`
  const fimAnterior = somarDias(inicioMes, -1)
  const [inicio, setInicio] = useState(`${fimAnterior.slice(0, 7)}-01`)
  const [fim, setFim] = useState(fimAnterior)
  const [titulo, setTitulo] = useState('')
  const [loja, setLoja] = useState('')
  const [proporcional, setProporcional] = useState(false)
  const id = useId()
  const erro = validarPeriodoFechamento(inicio, fim)

  const salvar = async () => {
    if (erro) return avisos.erro(erro)
    try {
      const novoId = await criar.mutateAsync({ inicio, fim, titulo: titulo.trim() || null, loja: loja || null, proporcional })
      avisos.sucesso('Rascunho criado')
      aoCriar(novoId)
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      titulo="Novo fechamento de comissão"
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={criar.isPending} onClick={salvar} disabled={!!erro}>
            Criar rascunho
          </Botao>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div>
          <p className="mb-1.5 text-sm font-semibold text-lavanda">Período</p>
          <FiltroPeriodo
            hoje={hoje}
            inicio={inicio}
            fim={fim}
            aoMudar={(i, f) => {
              setInicio(i)
              setFim(f)
            }}
          />
          {erro && <p className="mt-1 text-xs text-perigo">{erro}</p>}
        </div>
        <Campo rotulo="Título" htmlFor={`${id}-t`} ajuda="Em branco: usa o padrão.">
          <Entrada id={`${id}-t`} value={titulo} placeholder={tituloPadraoFechamento(inicio, fim)} onChange={(e) => setTitulo(e.target.value)} />
        </Campo>
        {(lojas.data ?? []).length > 1 && (
          <Campo rotulo="Loja" htmlFor={`${id}-l`}>
            <Selecao id={`${id}-l`} value={loja} onChange={(e) => setLoja(e.target.value)}>
              <option value="">Todas as lojas</option>
              {(lojas.data ?? []).map((l) => (
                <option key={l.id} value={l.loja_id_externo}>
                  {l.nome}
                </option>
              ))}
            </Selecao>
          </Campo>
        )}
        <Interruptor rotulo="Proporcional aos dias trabalhados" marcado={proporcional} aoMudar={setProporcional} />
        <p className="text-xs text-lavanda">
          Entram os funcionários ativos, que participam da comissão e com pontos no fim do período. Você ajusta tudo no rascunho antes de fechar.
        </p>
      </div>
    </Modal>
  )
}
