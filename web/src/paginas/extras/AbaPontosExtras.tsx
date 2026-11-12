import { useId, useMemo, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { Lock, Plus, Sparkles, Trash2 } from 'lucide-react'
import type { PontoExtra } from '@/tipos/banco'
import { Botao, Campo, Cartao, Entrada, EntradaData, ErroCarga, FOCO, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useFechamentos } from '@/consultas/comissoes'
import { useExcluirPontoExtra, useLancarPontoExtra, usePontosExtras } from '@/consultas/extras'
import { fechamentoQueCobre, lerPontosExtras } from '@/lib/extras'
import { formatarData, formatarDataHora } from '@/lib/formato'

const fmt = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })

export function AbaPontosExtras({ inicio, fim }: { inicio: string; fim: string }) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const lista = usePontosExtras(inicio, fim)
  const fechamentos = useFechamentos()
  const lancar = useLancarPontoExtra()
  const excluir = useExcluirPontoExtra()
  const id = useId()
  const [funcionario, setFuncionario] = useState<string | null>(null)
  const [data, setData] = useState<string | null>(hoje)
  const [pontos, setPontos] = useState('')
  const [motivo, setMotivo] = useState('')
  const [tentou, setTentou] = useState(false)

  const fechado = fechamentoQueCobre(fechamentos.data ?? [], data)
  const rascunhos = (fechamentos.data ?? []).filter((f) => f.status === 'rascunho' && data && f.data_inicio <= data && data <= f.data_fim)
  const valorPontos = lerPontosExtras(pontos)
  const erros = {
    funcionario: !funcionario ? 'Escolha o funcionário' : null,
    data: !data ? 'Informe a data' : null,
    pontos: valorPontos == null ? 'Pontos extras inválidos (de 0,01 a 9999,99)' : null,
    motivo: !motivo.trim() ? 'Informe o motivo' : null,
  }
  const linhas = lista.data ?? []
  const total = useMemo(() => linhas.reduce((s, l) => s + l.pontos, 0), [linhas])

  const enviar = async (e: FormEvent) => {
    e.preventDefault()
    setTentou(true)
    const primeiro = Object.values(erros).find(Boolean)
    if (primeiro) return avisos.erro(primeiro)
    try {
      await lancar.mutateAsync({ funcionarioId: funcionario!, data: data!, pontos: valorPontos!, motivo: motivo.trim() })
      avisos.sucesso(
        rascunhos.length > 0 ? 'Pontos lançados. Abra o rascunho e clique em “Reler serviço e presença” para incluir os extras.' : 'Pontos extras lançados',
      )
      setPontos('')
      setMotivo('')
      setTentou(false)
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const apagar = async (l: PontoExtra) => {
    const ok = await avisos.confirmar({
      titulo: `Excluir ${fmt(l.pontos)} ponto(s) de ${l.funcionario_nome}?`,
      mensagem: `Lançamento de ${formatarData(l.data)}: ${l.motivo}`,
      textoConfirmar: 'Excluir',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluir.mutateAsync(l.id)
      avisos.sucesso('Lançamento excluído')
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const colunas: Coluna<PontoExtra>[] = [
    {
      id: 'func',
      titulo: 'Funcionário',
      render: (l) => (
        <div className="min-w-0">
          <p className="truncate font-semibold text-creme">{l.funcionario_nome}</p>
          {l.cargo && <p className="text-xs text-lavanda">{l.cargo}</p>}
        </div>
      ),
    },
    { id: 'data', titulo: 'Data', render: (l) => <span className="numero">{formatarData(l.data)}</span> },
    { id: 'pontos', titulo: 'Pontos', alinhar: 'direita', render: (l) => <span className="numero font-semibold text-ouro-claro">+{fmt(l.pontos)}</span> },
    { id: 'motivo', titulo: 'Motivo', render: (l) => <span className="break-words">{l.motivo}</span> },
    {
      id: 'quem',
      titulo: 'Lançado por',
      ocultarNoCelular: true,
      render: (l) => (
        <span className="text-xs text-lavanda">
          {l.criado_por_nome}
          <br />
          {formatarDataHora(l.criado_em)}
        </span>
      ),
    },
    {
      id: 'acoes',
      titulo: '',
      alinhar: 'direita',
      render: (l) =>
        l.fechado ? (
          <Selo>
            <Lock aria-hidden /> Fechado
          </Selo>
        ) : (
          <Botao
            variante="fantasma"
            tamanho="p"
            aria-label={`Excluir pontos extras de ${l.funcionario_nome} em ${formatarData(l.data)}`}
            icone={<Trash2 aria-hidden />}
            onClick={() => apagar(l)}
          />
        ),
    },
  ]

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-[minmax(0,360px)_minmax(0,1fr)]">
      <Cartao titulo="Lançar pontos extras" sobrancelha="Comissão">
        <form onSubmit={enviar} noValidate className="flex flex-col gap-4">
          <Campo rotulo="Funcionário" htmlFor={`${id}-f`} obrigatorio erro={tentou ? erros.funcionario : null}>
            <SeletorFuncionario id={`${id}-f`} valor={funcionario} aoMudar={setFuncionario} somenteAtivos />
          </Campo>
          <Campo rotulo="Data" htmlFor={`${id}-d`} obrigatorio erro={tentou ? erros.data : null}>
            <EntradaData id={`${id}-d`} valor={data} aoMudar={setData} />
          </Campo>
          <Campo rotulo="Pontos extras" htmlFor={`${id}-p`} obrigatorio erro={tentou ? erros.pontos : null} ajuda="Somados aos pontos do funcionário no fechamento que cobre a data.">
            <Entrada
              id={`${id}-p`}
              className="numero"
              inputMode="decimal"
              placeholder="Ex.: 1,5"
              value={pontos}
              onChange={(e) => setPontos(e.target.value.replace(/[^\d,.]/g, ''))}
            />
          </Campo>
          <Campo rotulo="Motivo" htmlFor={`${id}-m`} obrigatorio erro={tentou ? erros.motivo : null}>
            <Entrada id={`${id}-m`} value={motivo} maxLength={200} placeholder="Ex.: Cobriu folga, meta batida" onChange={(e) => setMotivo(e.target.value)} />
          </Campo>
          {fechado && (
            <p role="alert" className="flex items-start gap-2 rounded-entrada border border-alerta/40 bg-alerta/10 px-3 py-2.5 text-sm text-creme">
              <Lock aria-hidden className="mt-0.5 size-4 shrink-0 text-alerta" />
              <span>
                {formatarData(data)} está no fechamento <strong>{fechado.titulo}</strong>, que já foi fechado. O sistema não aceita pontos extras nessa
                data.
              </span>
            </p>
          )}
          {!fechado && rascunhos.length > 0 && (
            <p className="text-xs text-lavanda">
              Esta data está no rascunho{' '}
              {rascunhos.map((r, i) => (
                <span key={r.id}>
                  {i > 0 && ', '}
                  <Link to={`/comissoes/${r.id}`} className={`font-semibold text-ouro hover:underline ${FOCO}`}>
                    {r.titulo}
                  </Link>
                </span>
              ))}
              . Depois de lançar, abra o fechamento e clique em “Reler serviço e presença”.
            </p>
          )}
          <Botao type="submit" icone={<Plus aria-hidden />} carregando={lancar.isPending} disabled={!!fechado}>
            Lançar pontos
          </Botao>
        </form>
      </Cartao>

      <Cartao
        titulo="Lançamentos do período"
        sobrancelha={`${formatarData(inicio)} a ${formatarData(fim)}`}
        acoes={linhas.length > 0 ? <Selo tom="ouro">+{fmt(total)} pontos</Selo> : undefined}
      >
        {lista.error ? (
          <ErroCarga erro={lista.error} aoTentar={() => lista.refetch()} />
        ) : (
          <Tabela
            colunas={colunas}
            linhas={linhas}
            chave={(l) => l.id}
            carregando={lista.isLoading}
            vazio={
              <Vazio
                icone={<Sparkles aria-hidden />}
                titulo="Nenhum ponto extra no período"
                descricao="Pontos extras entram na comissão do fechamento que cobre a data, sem proporcionalidade."
              />
            }
          />
        )}
      </Cartao>
    </div>
  )
}
