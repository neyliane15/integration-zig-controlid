import { useId, useMemo, useState } from 'react'
import { ArrowLeft, DoorOpen, Pencil, Plus, Trash2, Users, X } from 'lucide-react'
import {
  Botao,
  CabecalhoPagina,
  Caixa,
  Campo,
  Carregando,
  Cartao,
  Entrada,
  EntradaHora,
  ErroCarga,
  Interruptor,
  Modal,
  Selecao,
  Selo,
  Vazio,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { SeloStatusEnvio } from '@/componentes/dominio/Selos'
import {
  envioAtivo,
  useEnviosEmpresa,
  useEquipamentosControlId,
  useExcluirHorarioAcesso,
  useFuncionarioHorarios,
  useFuncionarios,
  useHorariosAcesso,
  useSalvarHorarioAcesso,
  useVincularHorario,
  type HorarioComFaixas,
} from '@/consultas/funcionarios'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { formatarRelativo, normalizar } from '@/lib/formato'
import { rotuloDiaSemana, rotuloDiaSemanaCurto } from '@/lib/rotulos'
import { FIM_DO_DIA, descreverFaixasHorario, expandirFaixa, rotuloFim, validarFaixas, type FaixaHorario } from './horariosAcesso'

const ORDEM_DIAS = [1, 2, 3, 4, 5, 6, 0]

export function PaginaHorariosAcesso() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const horarios = useHorariosAcesso()
  const vinculos = useFuncionarioHorarios()
  const equipamentos = useEquipamentosControlId()
  const envios = useEnviosEmpresa()
  const excluir = useExcluirHorarioAcesso()
  const [editando, setEditando] = useState<HorarioComFaixas | 'novo' | null>(null)
  const [pessoas, setPessoas] = useState<HorarioComFaixas | null>(null)

  const contagem = useMemo(() => {
    const m = new Map<string, number>()
    for (const v of vinculos.data ?? []) m.set(v.horario_id, (m.get(v.horario_id) ?? 0) + 1)
    return m
  }, [vinculos.data])

  const acessoLigados = (equipamentos.data ?? []).filter((e) => e.tipo === 'controlid_acesso')

  return (
    <div className="mx-auto w-full max-w-7xl">
      <BotaoLink to="/funcionarios" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Funcionários
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Control iD"
        titulo={
          <>
            Horários <span className="titulo-italico">de acesso</span>
          </>
        }
        subtitulo="Quando cada funcionário pode passar pelos equipamentos de acesso (iDFace, iDFlex, iDAccess). Funcionário sem horário vinculado segue a regra padrão do equipamento."
        acoes={
          operar && (
            <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setEditando('novo')}>
              Novo horário
            </Botao>
          )
        }
      />

      {acessoLigados.length > 0 && (
        <Cartao sobrancelha="Envio aos equipamentos" titulo="Situação dos horários" className="mb-5">
          <ul className="flex flex-col gap-2">
            {acessoLigados.map((eq) => {
              const envio = (envios.data ?? []).find((x) => x.alvo === 'horarios' && x.integracao_id === eq.id)
              return (
                <li key={eq.id} className="flex flex-wrap items-center justify-between gap-2 rounded-entrada border border-borda bg-entrada/60 px-3 py-2 text-sm">
                  <span className="font-semibold text-creme">{eq.nome}</span>
                  <span className="flex flex-wrap items-center gap-2">
                    {envio?.erro && <span className="text-xs text-perigo">{envio.erro}</span>}
                    {envio?.enviado_em && <span className="text-xs text-lavanda">enviado {formatarRelativo(envio.enviado_em)}</span>}
                    <SeloStatusEnvio status={!envioAtivo(eq) ? 'desligado' : (envio?.status ?? 'sem_envio')} />
                  </span>
                </li>
              )
            })}
          </ul>
          {acessoLigados.some((e) => !envioAtivo(e)) && (
            <p className="mt-3 text-xs text-lavanda">Equipamento com envio desligado não recebe horários. Um administrador ativa o envio em Integrações.</p>
          )}
        </Cartao>
      )}

      {horarios.isLoading ? (
        <Carregando />
      ) : horarios.error ? (
        <ErroCarga erro={horarios.error} aoTentar={() => horarios.refetch()} />
      ) : (horarios.data ?? []).length === 0 ? (
        <Vazio
          icone={<DoorOpen className="size-8" />}
          titulo="Nenhum horário de acesso"
          descricao="Crie um horário (ex.: “Salão noite”: ter a dom, 16:30 às 02:00) e vincule aos funcionários."
          acao={operar && <Botao onClick={() => setEditando('novo')}>Criar horário</Botao>}
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {(horarios.data ?? []).map((h) => (
            <Cartao
              key={h.id}
              sobrancelha={`${contagem.get(h.id) ?? 0} funcionário(s)`}
              titulo={
                <span className="flex flex-wrap items-center gap-2">
                  {h.nome} {!h.ativo && <Selo>Inativo</Selo>}
                </span>
              }
              acoes={
                operar && (
                  <>
                    <Botao variante="fantasma" tamanho="p" icone={<Users aria-hidden className="size-4" />} onClick={() => setPessoas(h)}>
                      Funcionários
                    </Botao>
                    <Botao variante="fantasma" tamanho="p" aria-label={`Editar ${h.nome}`} icone={<Pencil aria-hidden className="size-4" />} onClick={() => setEditando(h)} />
                    <Botao
                      variante="fantasma"
                      tamanho="p"
                      aria-label={`Excluir ${h.nome}`}
                      icone={<Trash2 aria-hidden className="size-4" />}
                      onClick={async () => {
                        if (
                          !(await avisos.confirmar({
                            titulo: `Excluir o horário ${h.nome}?`,
                            mensagem: 'Os funcionários vinculados ficam sem esta restrição; os equipamentos serão atualizados.',
                            perigo: true,
                            textoConfirmar: 'Excluir',
                          }))
                        )
                          return
                        try {
                          await excluir.mutateAsync(h.id)
                          avisos.sucesso('Horário excluído')
                        } catch (e) {
                          avisos.erro(e)
                        }
                      }}
                    />
                  </>
                )
              }
            >
              <p className="mb-3 text-sm text-lavanda">{descreverFaixasHorario(h.controlid_horario_faixas)}</p>
              <GradeSemana faixas={h.controlid_horario_faixas} />
            </Cartao>
          ))}
        </div>
      )}

      {editando && <EditorHorario horario={editando === 'novo' ? null : editando} aoFechar={() => setEditando(null)} />}
      {pessoas && <FuncionariosDoHorario horario={pessoas} aoFechar={() => setPessoas(null)} />}
    </div>
  )
}

/** Barras de 24 h por dia (seg..dom). */
function GradeSemana({ faixas }: { faixas: FaixaHorario[] }) {
  const pct = (h: string) => {
    const [a = '0', b = '0', c = '0'] = h.split(':')
    return ((Number(a) * 3600 + Number(b) * 60 + Number(c)) / 86400) * 100
  }
  return (
    <div className="flex flex-col gap-1" aria-hidden>
      {ORDEM_DIAS.map((d) => (
        <div key={d} className="grid grid-cols-[2.5rem_1fr] items-center gap-2 text-xs">
          <span className="text-lavanda">{rotuloDiaSemanaCurto[d]}</span>
          <div className="relative h-3 overflow-hidden rounded-pilula bg-entrada">
            {faixas
              .filter((f) => f.dia_semana === d)
              .map((f, i) => (
                <span key={i} className="absolute inset-y-0 rounded-pilula bg-ouro/70" style={{ left: `${pct(f.inicio)}%`, width: `${Math.max(1, pct(f.fim) - pct(f.inicio))}%` }} />
              ))}
          </div>
        </div>
      ))}
      <div className="grid grid-cols-[2.5rem_1fr] text-[10px] text-lavanda-escuro">
        <span />
        <span className="flex justify-between">
          <span>0h</span>
          <span>6h</span>
          <span>12h</span>
          <span>18h</span>
          <span>24h</span>
        </span>
      </div>
    </div>
  )
}

function EditorHorario({ horario, aoFechar }: { horario: HorarioComFaixas | null; aoFechar(): void }) {
  const avisos = useAvisos()
  const salvar = useSalvarHorarioAcesso()
  const id = useId()
  const [nome, setNome] = useState(horario?.nome ?? '')
  const [ativo, setAtivo] = useState(horario?.ativo ?? true)
  const [faixas, setFaixas] = useState<FaixaHorario[]>(
    () => horario?.controlid_horario_faixas.map((f) => ({ dia_semana: f.dia_semana, inicio: f.inicio, fim: f.fim })) ?? [],
  )
  // atalho: mesma faixa em vários dias
  const [dias, setDias] = useState<number[]>([2, 3, 4, 5, 6, 0])
  const [inicio, setInicio] = useState<string | null>('16:30')
  const [fim, setFim] = useState<string | null>('02:00')

  const erro = validarFaixas(faixas)

  const adicionar = () => {
    if (!inicio || !fim || dias.length === 0) return avisos.erro('Escolha os dias e os horários')
    const novas = dias.flatMap((d) => expandirFaixa(d, inicio, fim))
    setFaixas((l) => [...l, ...novas].sort((a, b) => (a.dia_semana || 7) - (b.dia_semana || 7) || a.inicio.localeCompare(b.inicio)))
  }

  const enviar = async () => {
    if (!nome.trim()) return avisos.erro('Informe o nome')
    if (erro) return avisos.erro(erro)
    try {
      await salvar.mutateAsync({ id: horario?.id, nome, ativo, faixas })
      avisos.sucesso('Horário salvo. Os equipamentos de acesso com envio ligado serão atualizados.')
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
      titulo={horario ? 'Editar horário de acesso' : 'Novo horário de acesso'}
      rodape={
        <>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={salvar.isPending} onClick={enviar} disabled={!!erro}>
            Salvar
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
        <Campo rotulo="Nome" htmlFor={`${id}-nome`} obrigatorio>
          <Entrada id={`${id}-nome`} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Ex.: Salão noite" />
        </Campo>
        <div className="pb-2.5">
          <Interruptor rotulo="Ativo" marcado={ativo} aoMudar={setAtivo} />
        </div>
      </div>

      <fieldset className="mt-5 rounded-entrada border border-borda p-4">
        <legend className="px-1 text-sm font-semibold text-creme">Adicionar faixa</legend>
        <div className="flex flex-wrap gap-x-4 gap-y-2" role="group" aria-label="Dias da semana">
          {ORDEM_DIAS.map((d) => (
            <Caixa key={d} rotulo={rotuloDiaSemanaCurto[d]} marcado={dias.includes(d)} aoMudar={(v) => setDias((l) => (v ? [...l, d] : l.filter((x) => x !== d)))} />
          ))}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
          <Campo rotulo="Das" htmlFor={`${id}-i`}>
            <EntradaHora id={`${id}-i`} valor={inicio} aoMudar={setInicio} />
          </Campo>
          <Campo rotulo="Até" htmlFor={`${id}-f`} ajuda="00:00 = até o fim do dia">
            <EntradaHora id={`${id}-f`} valor={fim} aoMudar={setFim} />
          </Campo>
          <Botao variante="secundario" className="col-span-2 sm:col-span-1" icone={<Plus aria-hidden className="size-4" />} onClick={adicionar}>
            Adicionar
          </Botao>
        </div>
        <p className="mt-2 text-xs text-lavanda">Faixa que passa da meia-noite é dividida em duas (até 24:00 e, no dia seguinte, desde 00:00).</p>
      </fieldset>

      <div className="mt-5">
        <p className="mb-2 text-sm font-semibold text-creme">Faixas ({faixas.length})</p>
        {faixas.length === 0 ? (
          <p className="text-sm text-alerta">Sem faixas, quem tiver só este horário não passa em nenhum momento.</p>
        ) : (
          <ul className="flex flex-col gap-1.5">
            {faixas.map((f, i) => (
              <li key={`${f.dia_semana}-${f.inicio}-${i}`} className="grid grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-2 rounded-entrada border border-borda bg-entrada/60 px-3 py-1.5 text-sm">
                <Selecao
                  aria-label="Dia"
                  className="h-9"
                  value={f.dia_semana}
                  onChange={(e) => setFaixas((l) => l.map((x, j) => (j === i ? { ...x, dia_semana: Number(e.target.value) } : x)))}
                >
                  {ORDEM_DIAS.map((d) => (
                    <option key={d} value={d}>
                      {rotuloDiaSemana[d]}
                    </option>
                  ))}
                </Selecao>
                <span className="numero text-creme">{f.inicio.slice(0, 5)}</span>
                <span className="numero text-creme">→ {rotuloFim(f.fim)}</span>
                <Botao variante="fantasma" tamanho="p" aria-label="Remover faixa" icone={<X aria-hidden className="size-4" />} onClick={() => setFaixas((l) => l.filter((_, j) => j !== i))} />
              </li>
            ))}
          </ul>
        )}
        {erro && (
          <p role="alert" className="mt-2 text-sm text-perigo">
            {erro}
          </p>
        )}
        {faixas.length > 0 && !erro && <p className="mt-3 text-xs text-lavanda">{descreverFaixasHorario(faixas)}</p>}
        <p className="sr-only">Fim do dia é {FIM_DO_DIA}.</p>
      </div>
    </Modal>
  )
}

function FuncionariosDoHorario({ horario, aoFechar }: { horario: HorarioComFaixas; aoFechar(): void }) {
  const avisos = useAvisos()
  const funcionarios = useFuncionarios()
  const vinculos = useFuncionarioHorarios()
  const vincular = useVincularHorario()
  const [busca, setBusca] = useState('')
  const id = useId()
  const marcados = new Set((vinculos.data ?? []).filter((v) => v.horario_id === horario.id).map((v) => v.funcionario_id))
  const lista = (funcionarios.data ?? []).filter((f) => (f.ativo || marcados.has(f.id)) && (!busca || normalizar(f.nome).includes(normalizar(busca))))

  return (
    <Modal aberto aoFechar={aoFechar} titulo={`Funcionários — ${horario.nome}`} rodape={<Botao onClick={aoFechar}>Pronto</Botao>}>
      <Campo rotulo="Buscar" htmlFor={id}>
        <Entrada id={id} type="search" value={busca} onChange={(e) => setBusca(e.target.value)} />
      </Campo>
      {funcionarios.isLoading || vinculos.isLoading ? (
        <Carregando />
      ) : (
        <ul className="mt-3 flex max-h-[50dvh] flex-col gap-1 overflow-y-auto">
          {lista.map((f) => (
            <li key={f.id} className="rounded-entrada px-2 py-1.5 hover:bg-cartao-2">
              <Caixa
                rotulo={
                  <span>
                    {f.nome}
                    {f.cargo && <span className="ml-2 text-xs text-lavanda">{f.cargo}</span>}
                  </span>
                }
                marcado={marcados.has(f.id)}
                desabilitado={vincular.isPending}
                aoMudar={async (v) => {
                  try {
                    await vincular.mutateAsync({ funcionarioId: f.id, horarioId: horario.id, vincular: v })
                  } catch (e) {
                    avisos.erro(e)
                  }
                }}
              />
            </li>
          ))}
          {lista.length === 0 && <li className="p-3 text-sm text-lavanda">Ninguém encontrado.</li>}
        </ul>
      )}
    </Modal>
  )
}
