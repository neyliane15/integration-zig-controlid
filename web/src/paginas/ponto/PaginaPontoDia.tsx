import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { AlertTriangle, CalendarRange, ChevronLeft, ChevronRight, RefreshCw, Search } from 'lucide-react'
import type { EsperadaEspelho, LinhaPontoDiaEmpresa } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Campo, Entrada, EntradaData, ErroCarga, Indicador, Interruptor, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BatidasDia } from '@/componentes/dominio/BatidasDia'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { ContagemBatidas, SeloSituacaoDia, TextoSaldo } from '@/componentes/dominio/Selos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useEsperadasDoDia, usePontoDia, useReapurar } from '@/consultas/ponto'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { formatarData, formatarMinutos, normalizar, somarDias } from '@/lib/formato'
import { rotuloDiaSemana } from '@/lib/rotulos'
import { batidasValidas, dataValida, identificarFaltantes } from '@/lib/ponto'
import { ModalIncluirBatida } from './ModaisPonto'

interface LinhaTela extends LinhaPontoDiaEmpresa {
  esperadasLista: EsperadaEspelho[]
  validas: number
  faltantes: ReturnType<typeof identificarFaltantes>
  problema: boolean
}

function diaSemana(iso: string): number {
  const [a, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1, d ?? 1)).getUTCDay()
}

export function PaginaPontoDia() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { hoje, fuso, virada } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const dataParam = params.get('data')
  const data = dataValida(dataParam) ? dataParam : hoje
  const [busca, setBusca] = useState('')
  const [soProblemas, setSoProblemas] = useState(false)
  const [incluir, setIncluir] = useState<{ linha: LinhaTela; hora: string | null } | null>(null)

  const dia = usePontoDia(data)
  const esperadas = useEsperadasDoDia(data, fuso, virada)
  const reapurar = useReapurar()

  const irPara = (d: string | null) => {
    const p = new URLSearchParams(params)
    if (!d || d === hoje) p.delete('data')
    else p.set('data', d)
    setParams(p, { replace: true })
  }

  const linhas = useMemo<LinhaTela[]>(() => {
    return (dia.data ?? []).map((l) => {
      const semPrevisao = l.situacao === 'abonado' || l.situacao === 'folga' || l.situacao === 'sem_escala'
      const lista = semPrevisao ? [] : (esperadas.data?.get(l.funcionario_id) ?? [])
      const validas = batidasValidas(l.batidas)
      const agora = Date.now()
      // dia em andamento: só aponta como faltante o que já deveria ter sido batido
      const faltantes = (lista.length && validas.length < lista.length ? identificarFaltantes(validas.map((b) => b.instante), lista) : []).filter(
        (f) => l.encerrado || new Date(lista.find((e) => e.batida === f)?.instante ?? 0).getTime() < agora,
      )
      const problema = l.alarmes_abertos > 0 || l.situacao === 'ausente' || l.situacao === 'incompleto' || (l.encerrado && validas.length % 2 === 1)
      return { ...l, esperadasLista: lista, validas: validas.length, faltantes, problema }
    })
  }, [dia.data, esperadas.data])

  const filtradas = useMemo(() => {
    const termo = normalizar(busca)
    return linhas
      .filter((l) => (!soProblemas || l.problema) && (!termo || normalizar(`${l.funcionario_nome} ${l.cargo ?? ''}`).includes(termo)))
      .sort((a, b) => Number(b.problema) - Number(a.problema) || b.alarmes_abertos - a.alarmes_abertos || a.funcionario_nome.localeCompare(b.funcionario_nome, 'pt-BR'))
  }, [linhas, busca, soProblemas])

  const resumo = useMemo(() => {
    const escalados = linhas.filter((l) => l.previsto_minutos > 0 || l.esperadasLista.length > 0)
    return {
      escalados: escalados.length,
      presentes: linhas.filter((l) => l.validas % 2 === 1).length,
      comBatida: linhas.filter((l) => l.validas > 0).length,
      ausentes: linhas.filter((l) => l.situacao === 'ausente').length,
      alarmes: linhas.reduce((s, l) => s + l.alarmes_abertos, 0),
      trabalhado: linhas.reduce((s, l) => s + l.trabalhado_minutos, 0),
    }
  }, [linhas])

  const mes = data.slice(0, 7)
  const ehHoje = data === hoje

  const colunas: Coluna<LinhaTela>[] = [
    {
      id: 'nome',
      titulo: 'Funcionário',
      render: (l) => (
        <div className="flex min-w-0 items-center gap-2">
          {l.problema && <AlertTriangle aria-label="Precisa de atenção" className="size-4 shrink-0 text-alerta" />}
          <div className="min-w-0">
            <p className="truncate font-semibold text-creme">{l.funcionario_nome}</p>
            {l.cargo && <p className="text-xs text-lavanda">{l.cargo}</p>}
          </div>
        </div>
      ),
    },
    {
      id: 'batidas',
      titulo: 'Batidas',
      render: (l) => (
        <div className="flex flex-col gap-1.5">
          <ContagemBatidas validas={l.validas} esperadas={l.esperadasLista.length} encerrado={l.encerrado} />
          <BatidasDia
            batidas={l.batidas}
            fuso={fuso}
            esperadas={l.esperadasLista}
            faltantes={l.faltantes}
            aoClicarFaltante={operar ? (e) => setIncluir({ linha: l, hora: e.instante ? horaLocal(e.instante, fuso) : null }) : undefined}
          />
        </div>
      ),
    },
    { id: 'trabalhado', titulo: 'Trabalhado', alinhar: 'direita', render: (l) => <span className="numero">{formatarMinutos(l.trabalhado_minutos)}</span> },
    {
      id: 'saldo',
      titulo: 'Saldo',
      alinhar: 'direita',
      render: (l) => <TextoSaldo minutos={l.saldo_minutos} provisorio={!l.encerrado} />,
    },
    {
      id: 'situacao',
      titulo: 'Situação',
      render: (l) => (
        <div className="flex flex-wrap gap-1">
          <SeloSituacaoDia situacao={l.situacao} />
          {l.atraso_minutos > 0 && <Selo tom="info">{l.atraso_minutos} min atraso</Selo>}
        </div>
      ),
    },
    {
      id: 'alarmes',
      titulo: 'Alarmes',
      alinhar: 'centro',
      render: (l) =>
        l.alarmes_abertos > 0 ? (
          <Selo tom="alerta">
            <AlertTriangle aria-hidden />
            {l.alarmes_abertos}
          </Selo>
        ) : (
          <span className="text-lavanda-escuro">—</span>
        ),
    },
  ]

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Ponto"
        titulo={
          <>
            {ehHoje ? 'Ponto de hoje' : 'Ponto do dia'} <span className="titulo-italico">{formatarData(data)}</span>
          </>
        }
        subtitulo={`${rotuloDiaSemana[diaSemana(data)]} · dia de trabalho começa às ${virada}${ehHoje ? ' · em andamento (saldo provisório)' : ''}`}
        acoes={
          <>
            <BotaoLink to="/ponto/alarmes" icone={<AlertTriangle aria-hidden />}>
              Alarmes
            </BotaoLink>
            {operar && (
              <Botao
                variante="secundario"
                icone={<RefreshCw aria-hidden className="size-4" />}
                carregando={reapurar.isPending}
                onClick={async () => {
                  try {
                    await reapurar.mutateAsync({ inicio: data, fim: data })
                    avisos.sucesso('Dia recalculado')
                  } catch (e) {
                    avisos.erro(e)
                  }
                }}
              >
                Recalcular
              </Botao>
            )}
          </>
        }
      />

      <nav aria-label="Escolher dia" className="mb-5 flex flex-wrap items-end gap-2">
        <Botao variante="secundario" aria-label="Dia anterior" icone={<ChevronLeft aria-hidden className="size-4" />} onClick={() => irPara(somarDias(data, -1))} />
        <div className="w-44">
          <EntradaData valor={data} max={hoje} aoMudar={(v) => irPara(v)} id="data-ponto" />
        </div>
        <Botao variante="secundario" aria-label="Próximo dia" icone={<ChevronRight aria-hidden className="size-4" />} disabled={data >= hoje} onClick={() => irPara(somarDias(data, 1))} />
        {!ehHoje && (
          <Botao variante="fantasma" onClick={() => irPara(null)}>
            Hoje
          </Botao>
        )}
      </nav>

      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Indicador rotulo={ehHoje ? 'Presentes agora' : 'Com batida'} valor={`${ehHoje ? resumo.presentes : resumo.comBatida} / ${resumo.escalados}`} detalhe="escalados no dia" tom="ouro" />
        <Indicador rotulo="Ausentes" valor={resumo.ausentes} tom={resumo.ausentes ? 'perigo' : undefined} detalhe={ehHoje ? 'só após o fim do dia' : 'escalados sem batida'} />
        <Indicador rotulo="Alarmes abertos" valor={resumo.alarmes} tom={resumo.alarmes ? 'alerta' : 'sucesso'} />
        <Indicador rotulo="Horas trabalhadas" valor={formatarMinutos(resumo.trabalhado)} detalhe="soma da equipe" />
      </div>

      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:gap-4">
        <div className="w-full min-w-0 sm:max-w-sm">
          <Campo rotulo="Buscar" htmlFor="busca-ponto">
            <div className="relative">
              <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-lavanda" />
              <Entrada id="busca-ponto" type="search" className="pl-9" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou cargo" />
            </div>
          </Campo>
        </div>
        <div className="sm:pb-2.5">
          <Interruptor rotulo="Só quem precisa de atenção" marcado={soProblemas} aoMudar={setSoProblemas} />
        </div>
      </div>

      {dia.error ? (
        <ErroCarga erro={dia.error} aoTentar={() => dia.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={filtradas}
          chave={(l) => l.funcionario_id}
          carregando={dia.isLoading}
          aoClicarLinha={(l) => navegar(`/ponto/funcionario/${l.funcionario_id}?mes=${mes}`)}
          vazio={
            linhas.length === 0 ? (
              <Vazio icone={<CalendarRange className="size-8" />} titulo="Ninguém no vínculo neste dia" descricao="Cadastre funcionários com data de admissão até este dia." />
            ) : (
              <Vazio titulo={soProblemas ? 'Tudo certo por aqui' : 'Ninguém encontrado'} descricao={soProblemas ? 'Nenhum funcionário com pendência neste dia.' : undefined} />
            )
          }
        />
      )}

      {incluir && (
        <ModalIncluirBatida
          key={`${incluir.linha.funcionario_id}-${incluir.hora}`}
          aberto
          aoFechar={() => setIncluir(null)}
          funcionarioId={incluir.linha.funcionario_id}
          funcionarioNome={incluir.linha.funcionario_nome}
          data={data}
          horaSugerida={incluir.hora}
          fuso={fuso}
          virada={virada}
        />
      )}
    </div>
  )
}

function horaLocal(instante: string, fuso: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone: fuso, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(instante))
}
