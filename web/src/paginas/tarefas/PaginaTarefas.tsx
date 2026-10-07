import { useId, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import clsx from 'clsx'
import { AlarmClock, Ban, Check, ChevronLeft, ChevronRight, ListChecks, Pencil, Play, Plus, Repeat, RotateCcw, Trash2, User } from 'lucide-react'
import type { Prioridade } from '@/tipos/banco'
import { AreaTexto, Botao, CabecalhoPagina, Caixa, Campo, Entrada, EntradaData, EntradaHora, ErroCarga, Esqueleto, Modal, Selecao, Selo, Vazio, FOCO } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useAdicionarItemTarefa, useExcluirTarefa, useMarcarItem, useRemoverItemTarefa, useMudarStatusTarefa, useSalvarTarefa, useTarefas, type TarefaComItens } from '@/consultas/tarefas'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { formatarData, somarDias } from '@/lib/formato'
import { rotuloDiaSemana, rotuloPrioridade, rotuloStatusTarefa } from '@/lib/rotulos'
import { dataValida } from '@/lib/ponto'
import { estaAtrasada, horaLocal, linhasChecklist, ordenarTarefas, progressoItens, proximoStatus, resumirTarefas } from '@/lib/tarefas'
import { SeletorResponsavel, SeloPrioridade, useNomeResponsavel, type Responsavel } from './comum'

type Filtro = 'abertas' | 'todas' | 'minhas' | 'concluidas'

function diaSemana(iso: string): number {
  const [a, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(a ?? 1970, (m ?? 1) - 1, d ?? 1)).getUTCDay()
}

export function PaginaTarefas() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const { hoje, fuso } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const data = dataValida(params.get('data')) ? (params.get('data') as string) : hoje
  const [filtro, setFiltro] = useState<Filtro>('abertas')
  const [editar, setEditar] = useState<string | null>(null)
  const agora = horaLocal(fuso)

  const tarefas = useTarefas(data, hoje)
  const tarefaEditada = (tarefas.data ?? []).find((t) => t.id === editar)
  const nomeResponsavel = useNomeResponsavel()

  const ehMinha = (t: Responsavel) => t.responsavel_perfil_id === perfil.id || (!!perfil.funcionario_id && t.responsavel_funcionario_id === perfil.funcionario_id)
  const podeMexer = (t: TarefaComItens) => operar || ehMinha(t)

  const resumo = useMemo(() => resumirTarefas(tarefas.data ?? [], hoje, agora), [tarefas.data, hoje, agora])
  const lista = useMemo(() => {
    const todas = ordenarTarefas(tarefas.data ?? [], hoje, agora)
    if (filtro === 'abertas') return todas.filter((t) => t.status === 'pendente' || t.status === 'em_andamento')
    if (filtro === 'concluidas') return todas.filter((t) => t.status === 'concluida' || t.status === 'cancelada')
    if (filtro === 'minhas') return todas.filter(ehMinha)
    return todas
  }, [tarefas.data, filtro, hoje, agora])

  const irPara = (d: string | null) => {
    const p = new URLSearchParams(params)
    if (!d || d === hoje) p.delete('data')
    else p.set('data', d)
    setParams(p, { replace: true })
  }

  return (
    <div className="mx-auto w-full max-w-5xl">
      <CabecalhoPagina
        sobrancelha="Rotina da casa"
        titulo={
          <>
            Tarefas <span className="titulo-italico">{data === hoje ? 'de hoje' : formatarData(data)}</span>
          </>
        }
        subtitulo={`${rotuloDiaSemana[diaSemana(data)]} · ${resumo.concluidas} de ${resumo.total - resumo.canceladas} concluída(s)`}
        acoes={
          operar && (
            <>
              <BotaoLink to="/tarefas/rotinas" icone={<Repeat aria-hidden />}>
                Rotinas
              </BotaoLink>
              <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setEditar('nova')}>
                Nova tarefa
              </Botao>
            </>
          )
        }
      />

      <div className="mb-5 flex flex-wrap items-center gap-2">
        <Botao variante="secundario" aria-label="Dia anterior" icone={<ChevronLeft aria-hidden className="size-4" />} onClick={() => irPara(somarDias(data, -1))} />
        <div className="w-44">
          <EntradaData id="data-tarefas" valor={data} aoMudar={(v) => irPara(v)} />
        </div>
        <Botao variante="secundario" aria-label="Próximo dia" icone={<ChevronRight aria-hidden className="size-4" />} onClick={() => irPara(somarDias(data, 1))} />
        {data !== hoje && (
          <Botao variante="fantasma" onClick={() => irPara(null)}>
            Hoje
          </Botao>
        )}
      </div>

      <div className="mb-5 rounded-cartao border border-borda bg-cartao p-5 shadow-cartao">
        <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
          <p className="font-display text-2xl text-creme">
            <span className="numero">{resumo.percentual}%</span> <span className="text-base text-lavanda">concluído</span>
          </p>
          <div className="flex flex-wrap gap-1.5">
            <Selo tom="ouro">{resumo.pendentes} aberta(s)</Selo>
            {resumo.atrasadas > 0 && (
              <Selo tom="perigo">
                <AlarmClock aria-hidden />
                {resumo.atrasadas} atrasada(s)
              </Selo>
            )}
            <Selo tom="sucesso">{resumo.concluidas} concluída(s)</Selo>
          </div>
        </div>
        <div className="h-2 overflow-hidden rounded-pilula bg-entrada" role="progressbar" aria-valuenow={resumo.percentual} aria-valuemin={0} aria-valuemax={100} aria-label="Progresso das tarefas">
          <div className="h-full rounded-pilula bg-ouro transition-all" style={{ width: `${resumo.percentual}%` }} />
        </div>
      </div>

      <div role="tablist" aria-label="Filtrar tarefas" className="mb-4 flex flex-wrap gap-1.5">
        {(['abertas', 'minhas', 'concluidas', 'todas'] as Filtro[]).map((f) => (
          <button
            key={f}
            type="button"
            role="tab"
            aria-selected={filtro === f}
            onClick={() => setFiltro(f)}
            className={clsx(
              'h-9 rounded-pilula border px-3.5 text-sm font-semibold transition-colors',
              filtro === f ? 'border-ouro/60 bg-ouro/10 text-ouro-claro' : 'border-borda text-lavanda hover:text-creme',
              FOCO,
            )}
          >
            {{ abertas: 'Abertas', minhas: 'Minhas', concluidas: 'Concluídas', todas: 'Todas' }[f]}
          </button>
        ))}
      </div>

      {tarefas.isLoading ? (
        <div className="flex flex-col gap-2">
          {[0, 1, 2].map((i) => (
            <Esqueleto key={i} className="h-20 w-full" />
          ))}
        </div>
      ) : tarefas.error ? (
        <ErroCarga erro={tarefas.error} aoTentar={() => tarefas.refetch()} />
      ) : lista.length === 0 ? (
        <Vazio
          icone={<ListChecks className="size-8" />}
          titulo={(tarefas.data ?? []).length === 0 ? 'Nenhuma tarefa neste dia' : filtro === 'abertas' ? 'Tudo feito!' : 'Nada neste filtro'}
          descricao={(tarefas.data ?? []).length === 0 && operar ? 'Crie uma tarefa avulsa ou cadastre rotinas que se repetem.' : undefined}
          acao={operar && (tarefas.data ?? []).length === 0 && <Botao onClick={() => setEditar('nova')}>Nova tarefa</Botao>}
        />
      ) : (
        <ul className="flex flex-col gap-2.5">
          {lista.map((t) => (
            <CartaoTarefa
              key={t.id}
              tarefa={t}
              atrasada={estaAtrasada(t, hoje, agora)}
              responsavel={nomeResponsavel(t)}
              podeMexer={podeMexer(t)}
              operar={operar}
              aoEditar={() => setEditar(t.id)}
            />
          ))}
        </ul>
      )}

      {editar && (editar === 'nova' || tarefaEditada) && (
        <EditorTarefa key={editar} tarefa={editar === 'nova' ? null : (tarefaEditada ?? null)} data={data} aoFechar={() => setEditar(null)} />
      )}
    </div>
  )
}

function CartaoTarefa({
  tarefa: t,
  atrasada,
  responsavel,
  podeMexer,
  operar,
  aoEditar,
}: {
  tarefa: TarefaComItens
  atrasada: boolean
  responsavel: string | null
  podeMexer: boolean
  operar: boolean
  aoEditar(): void
}) {
  const avisos = useAvisos()
  const mudar = useMudarStatusTarefa()
  const marcar = useMarcarItem()
  const excluir = useExcluirTarefa()
  const [aberto, setAberto] = useState(t.tarefa_itens.length > 0 && t.status !== 'concluida' && t.status !== 'cancelada')
  const prog = progressoItens(t.tarefa_itens)
  const fechada = t.status === 'concluida' || t.status === 'cancelada'

  const definirStatus = async (s: typeof t.status) => {
    try {
      await mudar.mutateAsync({ id: t.id, status: s })
      if (s === 'concluida') avisos.sucesso(`“${t.titulo}” concluída`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const prox = proximoStatus(t.status === 'cancelada' ? 'concluida' : t.status)
  const IconeAcao = t.status === 'pendente' ? Play : t.status === 'em_andamento' ? Check : RotateCcw
  const rotuloAcao = t.status === 'pendente' ? 'Começar' : t.status === 'em_andamento' ? 'Concluir' : 'Reabrir'

  return (
    <li
      className={clsx(
        'rounded-cartao border bg-cartao p-4 shadow-cartao',
        atrasada ? 'border-perigo/50 border-l-4 border-l-perigo' : t.status === 'em_andamento' ? 'border-ouro/40' : 'border-borda',
        fechada && 'opacity-70',
      )}
    >
      <div className="flex items-start gap-3">
        <button
          type="button"
          disabled={!podeMexer || mudar.isPending}
          onClick={() => definirStatus(t.status === 'concluida' ? 'pendente' : 'concluida')}
          aria-label={t.status === 'concluida' ? `Reabrir ${t.titulo}` : `Marcar ${t.titulo} como concluída`}
          aria-pressed={t.status === 'concluida'}
          className={clsx(
            'mt-0.5 grid size-7 shrink-0 place-items-center rounded-full border-2 transition-colors disabled:cursor-not-allowed disabled:opacity-50',
            t.status === 'concluida' ? 'border-sucesso bg-sucesso text-noite' : 'border-borda-forte hover:border-ouro',
            FOCO,
          )}
        >
          {t.status === 'concluida' && <Check aria-hidden className="size-4" strokeWidth={3} />}
        </button>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className={clsx('font-semibold text-creme', t.status === 'concluida' && 'line-through decoration-lavanda')}>{t.titulo}</p>
            <SeloPrioridade prioridade={t.prioridade} />
            {t.status === 'em_andamento' && <Selo tom="ouro">{rotuloStatusTarefa.em_andamento}</Selo>}
            {t.status === 'cancelada' && <Selo>{rotuloStatusTarefa.cancelada}</Selo>}
            {atrasada && (
              <Selo tom="perigo">
                <AlarmClock aria-hidden />
                Atrasada
              </Selo>
            )}
            {t.rotina_id && (
              <span className="text-lavanda" title="Gerada por rotina">
                <Repeat aria-label="Rotina" className="size-3.5" />
              </span>
            )}
          </div>
          <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-lavanda">
            {t.horario_limite && <span className="numero">até {t.horario_limite.slice(0, 5)}</span>}
            {responsavel && (
              <span className="inline-flex items-center gap-1">
                <User aria-hidden className="size-3" />
                {responsavel}
              </span>
            )}
            {prog.total > 0 && (
              <button type="button" className={clsx('underline-offset-4 hover:text-creme hover:underline', FOCO)} onClick={() => setAberto((v) => !v)} aria-expanded={aberto}>
                checklist {prog.feitos}/{prog.total}
              </button>
            )}
          </div>
          {t.descricao && <p className="mt-2 text-sm whitespace-pre-line text-lavanda">{t.descricao}</p>}
          {aberto && prog.total > 0 && (
            <ul className="mt-3 flex flex-col gap-1.5 border-l-2 border-borda pl-3">
              {t.tarefa_itens.map((i) => (
                <li key={i.id}>
                  <Caixa
                    rotulo={<span className={i.feito ? 'text-lavanda line-through' : undefined}>{i.texto}</span>}
                    marcado={i.feito}
                    desabilitado={!podeMexer || marcar.isPending}
                    aoMudar={async (v) => {
                      try {
                        await marcar.mutateAsync({ id: i.id, feito: v })
                      } catch (e) {
                        avisos.erro(e)
                      }
                    }}
                  />
                </li>
              ))}
            </ul>
          )}
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1 sm:flex-row sm:items-center">
          {podeMexer && t.status !== 'cancelada' && (
            <Botao variante={t.status === 'em_andamento' ? 'primario' : 'secundario'} tamanho="p" icone={<IconeAcao aria-hidden className="size-4" />} carregando={mudar.isPending} onClick={() => definirStatus(prox)}>
              <span className="hidden sm:inline">{rotuloAcao}</span>
            </Botao>
          )}
          {operar && (
            <div className="flex">
              <Botao variante="fantasma" tamanho="p" aria-label={`Editar ${t.titulo}`} icone={<Pencil aria-hidden className="size-4" />} onClick={aoEditar} />
              {!fechada && (
                <Botao variante="fantasma" tamanho="p" aria-label={`Cancelar ${t.titulo}`} icone={<Ban aria-hidden className="size-4" />} onClick={() => definirStatus('cancelada')} />
              )}
              {t.status === 'cancelada' && (
                <Botao variante="fantasma" tamanho="p" aria-label={`Reabrir ${t.titulo}`} icone={<RotateCcw aria-hidden className="size-4" />} onClick={() => definirStatus('pendente')} />
              )}
              <Botao
                variante="fantasma"
                tamanho="p"
                aria-label={`Excluir ${t.titulo}`}
                icone={<Trash2 aria-hidden className="size-4" />}
                onClick={async () => {
                  if (!(await avisos.confirmar({ titulo: `Excluir “${t.titulo}”?`, mensagem: t.rotina_id ? 'Ela não volta a ser gerada hoje (a rotina continua para os próximos dias).' : undefined, perigo: true, textoConfirmar: 'Excluir' }))) return
                  try {
                    await excluir.mutateAsync(t.id)
                  } catch (e) {
                    avisos.erro(e)
                  }
                }}
              />
            </div>
          )}
        </div>
      </div>
    </li>
  )
}

function EditorTarefa({ tarefa, data, aoFechar }: { tarefa: TarefaComItens | null; data: string; aoFechar(): void }) {
  const avisos = useAvisos()
  const salvar = useSalvarTarefa()
  const id = useId()
  const [titulo, setTitulo] = useState(tarefa?.titulo ?? '')
  const [descricao, setDescricao] = useState(tarefa?.descricao ?? '')
  const [dia, setDia] = useState<string | null>(tarefa?.data ?? data)
  const [horario, setHorario] = useState<string | null>(tarefa?.horario_limite?.slice(0, 5) ?? null)
  const [prioridade, setPrioridade] = useState<Prioridade>(tarefa?.prioridade ?? 'normal')
  const [responsavel, setResponsavel] = useState<Responsavel>({
    responsavel_funcionario_id: tarefa?.responsavel_funcionario_id ?? null,
    responsavel_perfil_id: tarefa?.responsavel_perfil_id ?? null,
  })
  const [checklist, setChecklist] = useState('')

  const enviar = async () => {
    if (!titulo.trim()) return avisos.erro('Informe o título')
    if (!dia) return avisos.erro('Informe o dia')
    try {
      await salvar.mutateAsync({
        id: tarefa?.id,
        data: dia,
        titulo: titulo.trim(),
        descricao: descricao.trim() || null,
        horario_limite: horario,
        prioridade,
        ...responsavel,
        itens: tarefa ? undefined : linhasChecklist(checklist),
      })
      avisos.sucesso(tarefa ? 'Tarefa salva' : 'Tarefa criada')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      titulo={tarefa ? 'Editar tarefa' : 'Nova tarefa'}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={salvar.isPending} onClick={enviar}>
            Salvar
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Campo rotulo="Título" htmlFor={`${id}-t`} obrigatorio>
            <Entrada id={`${id}-t`} value={titulo} onChange={(e) => setTitulo(e.target.value)} placeholder="Ex.: Conferir estoque do bar" />
          </Campo>
        </div>
        <Campo rotulo="Dia" htmlFor={`${id}-d`}>
          <EntradaData id={`${id}-d`} valor={dia} aoMudar={setDia} />
        </Campo>
        <Campo rotulo="Até que horas" htmlFor={`${id}-h`}>
          <EntradaHora id={`${id}-h`} valor={horario} aoMudar={setHorario} />
        </Campo>
        <Campo rotulo="Prioridade" htmlFor={`${id}-p`}>
          <Selecao id={`${id}-p`} value={prioridade} onChange={(e) => setPrioridade(e.target.value as Prioridade)}>
            {(['alta', 'normal', 'baixa'] as Prioridade[]).map((p) => (
              <option key={p} value={p}>
                {rotuloPrioridade[p]}
              </option>
            ))}
          </Selecao>
        </Campo>
        <Campo rotulo="Responsável" htmlFor={`${id}-r`}>
          <SeletorResponsavel id={`${id}-r`} valor={responsavel} aoMudar={setResponsavel} />
        </Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Descrição" htmlFor={`${id}-desc`}>
            <AreaTexto id={`${id}-desc`} className="min-h-16" value={descricao} onChange={(e) => setDescricao(e.target.value)} />
          </Campo>
        </div>
        {tarefa && <ChecklistExistente tarefa={tarefa} />}
        {!tarefa && (
          <div className="sm:col-span-2">
            <Campo rotulo="Checklist (um item por linha)" htmlFor={`${id}-c`} ajuda={`${linhasChecklist(checklist).length} item(ns)`}>
              <AreaTexto id={`${id}-c`} value={checklist} onChange={(e) => setChecklist(e.target.value)} placeholder={'Contar troco\nLigar máquinas de cartão'} />
            </Campo>
          </div>
        )}
      </div>
    </Modal>
  )
}

function ChecklistExistente({ tarefa }: { tarefa: TarefaComItens }) {
  const avisos = useAvisos()
  const adicionar = useAdicionarItemTarefa()
  const remover = useRemoverItemTarefa()
  const [texto, setTexto] = useState('')
  const id = useId()
  return (
    <div className="sm:col-span-2">
      <p className="mb-1.5 text-sm font-semibold text-lavanda">Checklist</p>
      <ul className="mb-2 flex flex-col gap-1">
        {tarefa.tarefa_itens.map((i) => (
          <li key={i.id} className="flex items-center justify-between gap-2 rounded-entrada bg-entrada/60 px-3 py-1.5 text-sm">
            <span className={i.feito ? 'text-lavanda line-through' : 'text-creme'}>{i.texto}</span>
            <Botao
              variante="fantasma"
              tamanho="p"
              aria-label={`Remover item ${i.texto}`}
              icone={<Trash2 aria-hidden className="size-4" />}
              onClick={async () => {
                try {
                  await remover.mutateAsync(i.id)
                } catch (e) {
                  avisos.erro(e)
                }
              }}
            />
          </li>
        ))}
      </ul>
      <div className="flex gap-2">
        <label htmlFor={id} className="sr-only">
          Novo item do checklist
        </label>
        <Entrada id={id} value={texto} placeholder="Novo item" onChange={(e) => setTexto(e.target.value)} />
        <Botao
          variante="secundario"
          disabled={!texto.trim()}
          carregando={adicionar.isPending}
          onClick={async () => {
            try {
              await adicionar.mutateAsync({ tarefaId: tarefa.id, texto: texto.trim(), ordem: tarefa.tarefa_itens.length })
              setTexto('')
            } catch (e) {
              avisos.erro(e)
            }
          }}
        >
          Adicionar
        </Botao>
      </div>
    </div>
  )
}
