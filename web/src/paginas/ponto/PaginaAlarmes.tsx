import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { ArrowLeft, BellRing, CheckCheck, RotateCcw } from 'lucide-react'
import type { StatusAlarme, TipoAlarme } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Caixa, Campo, ErroCarga, FiltroPeriodo, Selecao, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { SeloAlarme, SeloStatusAlarme } from '@/componentes/dominio/Selos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useAlarmes, useReabrirAlarme, type AlarmeComFuncionario } from '@/consultas/ponto'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { diaSemanaCurto, formatarData, somarDias } from '@/lib/formato'
import { rotuloStatusAlarme, rotuloTipoAlarme } from '@/lib/rotulos'
import { dataValida, GRAVIDADE_ALARME } from '@/lib/ponto'
import { ModalJustificar } from './ModaisPonto'

const STATUS: (StatusAlarme | 'todos')[] = ['aberto', 'justificado', 'resolvido', 'todos']
const TIPOS: TipoAlarme[] = ['sem_batida_dia_escalado', 'batida_faltando', 'batidas_impares', 'atraso']

export function PaginaAlarmes() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { hoje } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()

  const statusParam = params.get('status') as StatusAlarme | 'todos' | null
  const status = statusParam && STATUS.includes(statusParam) ? statusParam : 'aberto'
  const tipoParam = params.get('tipo') as TipoAlarme | null
  const tipo = tipoParam && TIPOS.includes(tipoParam) ? tipoParam : 'todos'
  const funcionarioId = params.get('funcionario')
  const inicio = dataValida(params.get('de')) ? (params.get('de') as string) : somarDias(hoje, -30)
  const fim = dataValida(params.get('ate')) ? (params.get('ate') as string) : hoje

  const definir = (mudancas: Record<string, string | null>) => {
    const p = new URLSearchParams(params)
    for (const [k, v] of Object.entries(mudancas)) {
      if (v) p.set(k, v)
      else p.delete(k)
    }
    setParams(p, { replace: true })
  }

  const alarmes = useAlarmes({ status, tipo, funcionarioId, inicio, fim })
  const reabrir = useReabrirAlarme()
  const [selecionados, setSelecionados] = useState<Set<string>>(new Set())
  const [justificar, setJustificar] = useState<string[]>([])

  const linhas = useMemo(
    () =>
      [...(alarmes.data ?? [])].sort(
        (a, b) =>
          Number(b.status === 'aberto') - Number(a.status === 'aberto') ||
          b.data.localeCompare(a.data) ||
          GRAVIDADE_ALARME[b.tipo] - GRAVIDADE_ALARME[a.tipo] ||
          (a.funcionarios?.nome ?? '').localeCompare(b.funcionarios?.nome ?? '', 'pt-BR'),
      ),
    [alarmes.data],
  )
  const abertosVisiveis = linhas.filter((a) => a.status === 'aberto')
  const marcados = abertosVisiveis.filter((a) => selecionados.has(a.id))
  const todosMarcados = abertosVisiveis.length > 0 && marcados.length === abertosVisiveis.length

  const alternar = (id: string, v: boolean) =>
    setSelecionados((s) => {
      const n = new Set(s)
      if (v) n.add(id)
      else n.delete(id)
      return n
    })

  const colunas: Coluna<AlarmeComFuncionario>[] = [
    {
      id: 'funcionario',
      titulo: 'Funcionário',
      render: (a) => (
        <div className="flex min-w-0 items-center gap-3">
          {operar && a.status === 'aberto' && (
            <div onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()}>
              <Caixa rotulo={<span className="sr-only">Selecionar</span>} marcado={selecionados.has(a.id)} aoMudar={(v) => alternar(a.id, v)} />
            </div>
          )}
          <div className="min-w-0">
            <p className="truncate font-semibold text-creme">{a.funcionarios?.nome ?? '—'}</p>
            <p className="numero text-xs text-lavanda">
              {formatarData(a.data)} · {diaSemanaCurto(a.data)}
            </p>
          </div>
        </div>
      ),
    },
    { id: 'tipo', titulo: 'Alarme', render: (a) => <SeloAlarme tipo={a.tipo} batidaEsperada={a.batida_esperada} status={a.status} /> },
    { id: 'detalhe', titulo: 'Detalhe', render: (a) => <span className={a.status === 'aberto' ? 'text-creme' : 'text-lavanda'}>{a.detalhe}</span> },
    {
      id: 'status',
      titulo: 'Situação',
      render: (a) => (
        <div className="flex flex-col gap-1">
          <SeloStatusAlarme status={a.status} />
          {a.justificativa && <span className="text-xs italic text-lavanda">“{a.justificativa}”</span>}
          {a.resolvido_automaticamente && <span className="text-xs text-lavanda">resolvido pela batida</span>}
        </div>
      ),
    },
    ...(operar
      ? [
          {
            id: 'acoes',
            titulo: '',
            alinhar: 'direita' as const,
            render: (a: AlarmeComFuncionario) =>
              a.status === 'aberto' ? (
                <Botao
                  variante="secundario"
                  tamanho="p"
                  onClick={(e) => {
                    e.stopPropagation()
                    setJustificar([a.id])
                  }}
                >
                  Justificar
                </Botao>
              ) : a.status === 'justificado' ? (
                <Botao
                  variante="fantasma"
                  tamanho="p"
                  icone={<RotateCcw aria-hidden className="size-3.5" />}
                  onClick={async (e) => {
                    e.stopPropagation()
                    try {
                      await reabrir.mutateAsync(a.id)
                      avisos.sucesso('Alarme reaberto')
                    } catch (erro) {
                      avisos.erro(erro)
                    }
                  }}
                >
                  Reabrir
                </Botao>
              ) : null,
          },
        ]
      : []),
  ]

  return (
    <div className="mx-auto w-full max-w-7xl">
      <BotaoLink to="/ponto" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Ponto do dia
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Ponto"
        titulo={
          <>
            Alarmes <span className="titulo-italico">de ponto</span>
          </>
        }
        subtitulo="Batida faltando, batidas ímpares, dia escalado sem batida e atrasos. Inclua a batida que faltou no espelho ou justifique."
        acoes={
          operar &&
          marcados.length > 0 && (
            <Botao icone={<CheckCheck aria-hidden className="size-4" />} onClick={() => setJustificar(marcados.map((a) => a.id))}>
              Justificar {marcados.length} selecionado(s)
            </Botao>
          )
        }
      />

      <div className="mb-5 grid gap-3 md:grid-cols-3 lg:grid-cols-[180px_220px_minmax(0,1fr)]">
        <Campo rotulo="Situação" htmlFor="f-status">
          <Selecao id="f-status" value={status} onChange={(e) => definir({ status: e.target.value === 'aberto' ? null : e.target.value })}>
            {STATUS.map((s) => (
              <option key={s} value={s}>
                {s === 'todos' ? 'Todas' : rotuloStatusAlarme[s]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <Campo rotulo="Tipo" htmlFor="f-tipo">
          <Selecao id="f-tipo" value={tipo} onChange={(e) => definir({ tipo: e.target.value === 'todos' ? null : e.target.value })}>
            <option value="todos">Todos os tipos</option>
            {TIPOS.map((t) => (
              <option key={t} value={t}>
                {rotuloTipoAlarme[t]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <Campo rotulo="Funcionário" htmlFor="f-func">
          <SeletorFuncionario id="f-func" valor={funcionarioId} aoMudar={(v) => definir({ funcionario: v })} permitirTodos />
        </Campo>
      </div>
      <div className="mb-5">
        <FiltroPeriodo inicio={inicio} fim={fim} aoMudar={(de, ate) => definir({ de, ate })} />
      </div>

      {operar && abertosVisiveis.length > 1 && (
        <div className="mb-3">
          <Caixa
            rotulo={`Selecionar todos os ${abertosVisiveis.length} abertos`}
            marcado={todosMarcados}
            aoMudar={(v) => setSelecionados(v ? new Set(abertosVisiveis.map((a) => a.id)) : new Set())}
          />
        </div>
      )}

      {alarmes.error ? (
        <ErroCarga erro={alarmes.error} aoTentar={() => alarmes.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={linhas}
          chave={(a) => a.id}
          carregando={alarmes.isLoading}
          aoClicarLinha={(a) => navegar(`/ponto/funcionario/${a.funcionario_id}?mes=${a.data.slice(0, 7)}`)}
          vazio={
            <Vazio
              icone={<BellRing className="size-8" />}
              titulo={status === 'aberto' ? 'Nenhum alarme aberto' : 'Nenhum alarme encontrado'}
              descricao={status === 'aberto' ? 'Tudo em ordem no período escolhido.' : 'Ajuste os filtros.'}
            />
          }
        />
      )}

      {justificar.length > 0 && (
        <ModalJustificar
          ids={justificar}
          aoFechar={() => {
            setJustificar([])
            setSelecionados(new Set())
          }}
        />
      )}
    </div>
  )
}
