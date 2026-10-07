import { useId, useState } from 'react'
import { ArrowLeft, Pencil, Plus, Repeat, Trash2, User } from 'lucide-react'
import type { Prioridade, Recorrencia } from '@/tipos/banco'
import { AreaTexto, Botao, CabecalhoPagina, Caixa, Campo, Carregando, Entrada, EntradaHora, ErroCarga, Interruptor, Modal, Selecao, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { useAtivarRotina, useExcluirRotina, useRotinas, useSalvarRotina, type RotinaComItens } from '@/consultas/tarefas'
import { rotuloDiaSemanaCurto, rotuloPrioridade, rotuloRecorrencia } from '@/lib/rotulos'
import { descreverRecorrencia, linhasChecklist, validarRotina } from '@/lib/tarefas'
import { SeletorResponsavel, SeloPrioridade, useNomeResponsavel, type Responsavel } from './comum'

const ORDEM_DIAS = [1, 2, 3, 4, 5, 6, 0]

export function PaginaRotinas() {
  const avisos = useAvisos()
  const rotinas = useRotinas()
  const ativar = useAtivarRotina()
  const excluir = useExcluirRotina()
  const nomeResponsavel = useNomeResponsavel()
  const [editar, setEditar] = useState<RotinaComItens | 'nova' | null>(null)

  return (
    <div className="mx-auto w-full max-w-5xl">
      <BotaoLink to="/tarefas" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Tarefas
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Tarefas que se repetem"
        titulo={
          <>
            Rotinas <span className="titulo-italico">e checklists</span>
          </>
        }
        subtitulo="Cada rotina vira uma tarefa no dia certo (diária, em dias da semana ou num dia do mês), com o checklist pronto."
        acoes={
          <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setEditar('nova')}>
            Nova rotina
          </Botao>
        }
      />

      {rotinas.isLoading ? (
        <Carregando />
      ) : rotinas.error ? (
        <ErroCarga erro={rotinas.error} aoTentar={() => rotinas.refetch()} />
      ) : (rotinas.data ?? []).length === 0 ? (
        <Vazio
          icone={<Repeat className="size-8" />}
          titulo="Nenhuma rotina"
          descricao="Ex.: “Abrir caixa” todo dia até 16:30 com checklist, “Conferir estoque do bar” às terças e sextas."
          acao={<Botao onClick={() => setEditar('nova')}>Criar rotina</Botao>}
        />
      ) : (
        <ul className="flex flex-col gap-2.5">
          {(rotinas.data ?? []).map((r) => {
            const resp = nomeResponsavel(r)
            return (
              <li key={r.id} className={`rounded-cartao border border-borda bg-cartao p-4 shadow-cartao ${r.ativa ? '' : 'opacity-60'}`}>
                <div className="flex flex-wrap items-start gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-semibold text-creme">{r.titulo}</p>
                      <SeloPrioridade prioridade={r.prioridade} />
                      {!r.ativa && <Selo>Pausada</Selo>}
                    </div>
                    <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-lavanda">
                      <span className="inline-flex items-center gap-1">
                        <Repeat aria-hidden className="size-3" />
                        {descreverRecorrencia(r)}
                      </span>
                      {r.horario_limite && <span className="numero">até {r.horario_limite.slice(0, 5)}</span>}
                      {resp && (
                        <span className="inline-flex items-center gap-1">
                          <User aria-hidden className="size-3" />
                          {resp}
                        </span>
                      )}
                      {r.tarefas_rotina_itens.length > 0 && <span>{r.tarefas_rotina_itens.length} item(ns) no checklist</span>}
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <Interruptor
                      rotulo={<span className="sr-only">Rotina ativa</span>}
                      marcado={r.ativa}
                      desabilitado={ativar.isPending}
                      aoMudar={async (v) => {
                        try {
                          await ativar.mutateAsync({ id: r.id, ativa: v })
                        } catch (e) {
                          avisos.erro(e)
                        }
                      }}
                    />
                    <Botao variante="fantasma" tamanho="p" aria-label={`Editar ${r.titulo}`} icone={<Pencil aria-hidden className="size-4" />} onClick={() => setEditar(r)} />
                    <Botao
                      variante="fantasma"
                      tamanho="p"
                      aria-label={`Excluir ${r.titulo}`}
                      icone={<Trash2 aria-hidden className="size-4" />}
                      onClick={async () => {
                        if (!(await avisos.confirmar({ titulo: `Excluir a rotina “${r.titulo}”?`, mensagem: 'As tarefas já geradas continuam.', perigo: true, textoConfirmar: 'Excluir' }))) return
                        try {
                          await excluir.mutateAsync(r.id)
                          avisos.sucesso('Rotina excluída')
                        } catch (e) {
                          avisos.erro(e)
                        }
                      }}
                    />
                  </div>
                </div>
              </li>
            )
          })}
        </ul>
      )}

      {editar && <EditorRotina rotina={editar === 'nova' ? null : editar} aoFechar={() => setEditar(null)} />}
    </div>
  )
}

function EditorRotina({ rotina, aoFechar }: { rotina: RotinaComItens | null; aoFechar(): void }) {
  const avisos = useAvisos()
  const salvar = useSalvarRotina()
  const id = useId()
  const [titulo, setTitulo] = useState(rotina?.titulo ?? '')
  const [descricao, setDescricao] = useState(rotina?.descricao ?? '')
  const [recorrencia, setRecorrencia] = useState<Recorrencia>(rotina?.recorrencia ?? 'diaria')
  const [dias, setDias] = useState<number[]>(rotina?.dias_semana ?? [])
  const [diaMes, setDiaMes] = useState(rotina?.dia_mes ? String(rotina.dia_mes) : '1')
  const [horario, setHorario] = useState<string | null>(rotina?.horario_limite?.slice(0, 5) ?? null)
  const [prioridade, setPrioridade] = useState<Prioridade>(rotina?.prioridade ?? 'normal')
  const [responsavel, setResponsavel] = useState<Responsavel>({
    responsavel_funcionario_id: rotina?.responsavel_funcionario_id ?? null,
    responsavel_perfil_id: rotina?.responsavel_perfil_id ?? null,
  })
  const [ativa, setAtiva] = useState(rotina?.ativa ?? true)
  const [checklist, setChecklist] = useState((rotina?.tarefas_rotina_itens ?? []).map((i) => i.texto).join('\n'))

  const dados = { titulo, recorrencia, dias_semana: dias, dia_mes: recorrencia === 'mensal' ? Number(diaMes) || null : null }
  const erro = validarRotina(dados)

  const enviar = async () => {
    if (erro) return avisos.erro(erro)
    try {
      await salvar.mutateAsync({
        id: rotina?.id,
        titulo: titulo.trim(),
        descricao: descricao.trim() || null,
        recorrencia,
        dias_semana: [...dias].sort((a, b) => a - b),
        dia_mes: dados.dia_mes,
        horario_limite: horario,
        prioridade,
        ...responsavel,
        ativa,
        itens: linhasChecklist(checklist),
      })
      avisos.sucesso('Rotina salva. Vale a partir da próxima geração (hoje, se ainda não gerada).')
      aoFechar()
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      largura="g"
      titulo={rotina ? 'Editar rotina' : 'Nova rotina'}
      rodape={
        <>
          <span className="mr-auto self-center text-sm text-lavanda">{erro ?? descreverRecorrencia(dados)}</span>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={salvar.isPending} onClick={enviar} disabled={!!erro}>
            Salvar
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Campo rotulo="Título" htmlFor={`${id}-t`} obrigatorio>
            <Entrada id={`${id}-t`} value={titulo} onChange={(e) => setTitulo(e.target.value)} placeholder="Ex.: Abrir caixa" />
          </Campo>
        </div>
        <Campo rotulo="Repete" htmlFor={`${id}-r`}>
          <Selecao id={`${id}-r`} value={recorrencia} onChange={(e) => setRecorrencia(e.target.value as Recorrencia)}>
            {(['diaria', 'semanal', 'mensal'] as Recorrencia[]).map((r) => (
              <option key={r} value={r}>
                {rotuloRecorrencia[r]}
              </option>
            ))}
          </Selecao>
        </Campo>
        {recorrencia === 'mensal' ? (
          <Campo rotulo="Dia do mês" htmlFor={`${id}-dm`} ajuda="Mês mais curto: cai no último dia.">
            <Entrada id={`${id}-dm`} className="numero" inputMode="numeric" value={diaMes} onChange={(e) => setDiaMes(e.target.value.replace(/\D/g, '').slice(0, 2))} />
          </Campo>
        ) : recorrencia === 'semanal' ? (
          <fieldset className="flex flex-col gap-1.5">
            <legend className="mb-1.5 text-sm font-semibold text-lavanda">Dias da semana</legend>
            <div className="flex flex-wrap gap-x-3 gap-y-2">
              {ORDEM_DIAS.map((d) => (
                <Caixa key={d} rotulo={rotuloDiaSemanaCurto[d]} marcado={dias.includes(d)} aoMudar={(v) => setDias((l) => (v ? [...l, d] : l.filter((x) => x !== d)))} />
              ))}
            </div>
          </fieldset>
        ) : (
          <div />
        )}
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
        <Campo rotulo="Responsável" htmlFor={`${id}-resp`}>
          <SeletorResponsavel id={`${id}-resp`} valor={responsavel} aoMudar={setResponsavel} />
        </Campo>
        <div className="self-end pb-2.5">
          <Interruptor rotulo="Rotina ativa" marcado={ativa} aoMudar={setAtiva} />
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Descrição" htmlFor={`${id}-d`}>
            <AreaTexto id={`${id}-d`} className="min-h-16" value={descricao} onChange={(e) => setDescricao(e.target.value)} />
          </Campo>
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Checklist (um item por linha)" htmlFor={`${id}-c`} ajuda={`${linhasChecklist(checklist).length} item(ns). Alterações valem para as próximas tarefas geradas.`}>
            <AreaTexto id={`${id}-c`} value={checklist} onChange={(e) => setChecklist(e.target.value)} placeholder={'Contar troco\nLigar máquinas de cartão\nConferir sangria'} />
          </Campo>
        </div>
      </div>
    </Modal>
  )
}
