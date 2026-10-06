import { useMemo, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { ArrowLeft, Clock, Plus, Trash2 } from 'lucide-react'
import type { LinhaExtratoBancoHoras } from '@/tipos/banco'
import { Botao, CabecalhoPagina, ErroCarga, FiltroPeriodo, Indicador, Selo, Tabela, Vazio, type Coluna, type Tom } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { TextoSaldo } from '@/componentes/dominio/Selos'
import { useContextoEmpresa, useFuncionario } from '@/consultas/funcionarios'
import { useExcluirLancamento, useExtrato } from '@/consultas/bancoHoras'
import { usePerfil } from '@/lib/sessao'
import { podeAdministrar, podeOperar } from '@/lib/permissoes'
import { diaSemanaCurto, formatarData, somarDias } from '@/lib/formato'
import { rotuloTipoLancamento } from '@/lib/rotulos'
import { dataValida } from '@/lib/ponto'
import { ModalLancamento } from './ModalLancamento'

const TOM_TIPO: Record<LinhaExtratoBancoHoras['tipo'], Tom> = {
  saldo_anterior: 'neutro',
  dia: 'neutro',
  saldo_inicial: 'ouro',
  ajuste: 'info',
  compensacao: 'alerta',
  pagamento: 'alerta',
}

function rotuloTipo(t: LinhaExtratoBancoHoras['tipo']): string {
  if (t === 'saldo_anterior') return 'Saldo anterior'
  if (t === 'dia') return 'Dia'
  return rotuloTipoLancamento[t]
}

export function PaginaExtratoBancoHoras() {
  const { id = '' } = useParams()
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const administrar = podeAdministrar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { hoje } = useContextoEmpresa()
  const ontem = somarDias(hoje, -1)
  const [params, setParams] = useSearchParams()
  const inicio = dataValida(params.get('de')) ? (params.get('de') as string) : `${ontem.slice(0, 7)}-01`
  const fim = dataValida(params.get('ate')) ? (params.get('ate') as string) : ontem
  const [lancar, setLancar] = useState(false)

  const funcionario = useFuncionario(id)
  const extrato = useExtrato(id, inicio, fim)
  const excluir = useExcluirLancamento()

  const linhas = extrato.data ?? []
  const saldoFinal = linhas.length ? (linhas[linhas.length - 1] as LinhaExtratoBancoHoras).saldo_acumulado : 0
  const saldoAnterior = linhas.find((l) => l.tipo === 'saldo_anterior')?.saldo_acumulado ?? 0
  const movimentos = useMemo(() => {
    const m = { dias: 0, lancamentos: 0 }
    for (const l of linhas) {
      if (l.tipo === 'dia') m.dias += l.minutos
      else if (l.tipo !== 'saldo_anterior') m.lancamentos += l.minutos
    }
    return m
  }, [linhas])

  const colunas: Coluna<LinhaExtratoBancoHoras>[] = [
    {
      id: 'data',
      titulo: 'Data',
      render: (l) => (
        <span className="numero">
          {formatarData(l.data)} <span className="font-sans text-xs text-lavanda">{diaSemanaCurto(l.data)}</span>
        </span>
      ),
    },
    { id: 'tipo', titulo: 'Tipo', render: (l) => <Selo tom={TOM_TIPO[l.tipo]}>{rotuloTipo(l.tipo)}</Selo> },
    { id: 'descricao', titulo: 'Descrição', render: (l) => <span className="text-creme">{l.descricao}</span> },
    { id: 'minutos', titulo: 'Horas', alinhar: 'direita', render: (l) => (l.tipo === 'saldo_anterior' ? <span className="text-lavanda-escuro">—</span> : <TextoSaldo minutos={l.minutos} />) },
    { id: 'saldo', titulo: 'Saldo', alinhar: 'direita', render: (l) => <TextoSaldo minutos={l.saldo_acumulado} className="font-semibold" /> },
    ...(administrar
      ? [
          {
            id: 'acoes',
            titulo: '',
            alinhar: 'direita' as const,
            render: (l: LinhaExtratoBancoHoras) =>
              l.tipo !== 'dia' && l.tipo !== 'saldo_anterior' && l.referencia_id ? (
                <Botao
                  variante="fantasma"
                  tamanho="p"
                  aria-label={`Excluir lançamento de ${formatarData(l.data)}`}
                  icone={<Trash2 aria-hidden className="size-4" />}
                  onClick={async (e) => {
                    e.stopPropagation()
                    if (!(await avisos.confirmar({ titulo: 'Excluir este lançamento?', mensagem: l.descricao, perigo: true, textoConfirmar: 'Excluir' }))) return
                    try {
                      await excluir.mutateAsync(l.referencia_id as string)
                      avisos.sucesso('Lançamento excluído')
                    } catch (erro) {
                      avisos.erro(erro)
                    }
                  }}
                />
              ) : null,
          },
        ]
      : []),
  ]

  return (
    <div className="mx-auto w-full max-w-6xl">
      <BotaoLink to="/banco-de-horas" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Banco de horas
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Extrato do banco de horas"
        titulo={funcionario.data?.nome ?? 'Funcionário'}
        subtitulo={funcionario.data?.cargo ?? undefined}
        acoes={
          <>
            <BotaoLink to={`/ponto/funcionario/${id}?mes=${fim.slice(0, 7)}`} icone={<Clock aria-hidden />}>
              Espelho de ponto
            </BotaoLink>
            {operar && (
              <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setLancar(true)}>
                Lançamento
              </Botao>
            )}
          </>
        }
      />

      <div className="mb-5 flex flex-wrap items-end justify-between gap-4">
        <FiltroPeriodo
          inicio={inicio}
          fim={fim}
          aoMudar={(de, ate) => {
            const p = new URLSearchParams(params)
            p.set('de', de)
            p.set('ate', ate)
            setParams(p, { replace: true })
          }}
        />
        <div className="w-full sm:w-72">
          <SeletorFuncionario valor={id} aoMudar={(f) => f && navegar(`/banco-de-horas/${f}?${params.toString()}`)} rotuloAcessivel="Trocar funcionário" />
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Indicador rotulo="Saldo anterior" valor={<TextoSaldo minutos={saldoAnterior} />} detalhe={`em ${formatarData(somarDias(inicio, -1))}`} />
        <Indicador rotulo="Dias do período" valor={<TextoSaldo minutos={movimentos.dias} />} />
        <Indicador rotulo="Lançamentos" valor={<TextoSaldo minutos={movimentos.lancamentos} />} />
        <Indicador rotulo="Saldo final" valor={<TextoSaldo minutos={saldoFinal} />} detalhe={`em ${formatarData(fim)}`} tom="ouro" />
      </div>

      {extrato.error ? (
        <ErroCarga erro={extrato.error} aoTentar={() => extrato.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={linhas}
          chave={(l) => `${l.data}-${l.tipo}-${l.referencia_id ?? ''}-${l.descricao}`}
          carregando={extrato.isLoading}
          vazio={<Vazio titulo="Sem movimentos no período" />}
        />
      )}

      {lancar && <ModalLancamento aberto aoFechar={() => setLancar(false)} funcionarioId={id} dataPadrao={fim} permitirSaldoInicial={administrar} />}
    </div>
  )
}
