/**
 * Aba "Equipe e configuração": data-âncora/fase, setores, membros (a partir dos funcionários cadastrados ou cadastrando
 * direto no setor), folgas da semana base, chegada padrão, caminho/posição do rodízio ou folga fixa e férias por período.
 * G A M editam; leitura só vê.
 */
import { useEffect, useMemo, useState } from 'react'
import clsx from 'clsx'
import { Check, LayoutTemplate, Pencil, Plus, Trash2, UserPlus, X } from 'lucide-react'
import { Botao, Campo, Cartao, Entrada, FOCO, Selecao } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import type { EscalaSemana, EscalaSetorSemana } from '@/tipos/banco'
import {
  useAdicionarFuncionarioEscala,
  useAjustarPeriodo,
  useAplicarModeloMacaw,
  useConfigurarEscala,
  useDefinirMembros,
  useExcluirSetor,
  useRemoverMembro,
  useSalvarMembro,
  useSalvarSetor,
} from '@/consultas/escala'
import { useFuncionarios, useSalvarFuncionario } from '@/consultas/funcionarios'
import { invalidar } from '@/lib/consultas'
import { useQueryClient } from '@tanstack/react-query'
import { DIAS_SEMANA, chegadaParaHora, chegadaValida, horaParaChegada, indiceSegunda, textoFolgas } from '@/lib/escala'
import { formatarData, somarDias } from '@/lib/formato'

const ROTULO = 'text-xs font-semibold text-lavanda'

export function AbaEquipe({ semana, editar, hoje }: { semana: EscalaSemana; editar: boolean; hoje: string }) {
  const naEscala = useMemo(() => new Set(semana.setores.flatMap((s) => s.membros.map((m) => m.funcionario_id))), [semana])
  return (
    <div className="grid min-w-0 gap-5">
      {editar && <CartaoConfiguracao semana={semana} hoje={hoje} />}
      {semana.setores.map((s) => (
        <CartaoSetor key={s.id} setor={s} editar={editar} naEscala={naEscala} hoje={hoje} />
      ))}
      {editar && <NovoSetor />}
    </div>
  )
}

// ------------------------------------------------------------------ configuração

function CartaoConfiguracao({ semana, hoje }: { semana: EscalaSemana; hoje: string }) {
  const avisos = useAvisos()
  const configurar = useConfigurarEscala()
  const modelo = useAplicarModeloMacaw()
  const [ancora, setAncora] = useState(semana.ancora ?? '')
  const [fase, setFase] = useState(String(semana.fase ?? 0))
  useEffect(() => {
    setAncora(semana.ancora ?? '')
    setFase(String(semana.fase ?? 0))
  }, [semana.ancora, semana.fase])

  const segunda = ancora ? new Date(`${ancora}T12:00:00Z`).getUTCDay() === 1 : false
  const mudou = ancora !== (semana.ancora ?? '') || Number(fase) !== (semana.fase ?? 0)

  async function salvar() {
    if (!segunda) return avisos.erro(new Error('A data-âncora deve ser uma segunda-feira'))
    if (semana.ancora && ancora > semana.ancora) {
      const ok = await avisos.confirmar({
        titulo: 'Mudar a data-âncora?',
        mensagem: `Ajustes da escala antes de ${formatarData(ancora)} (inclusive férias) serão apagados.`,
        textoConfirmar: 'Mudar',
        perigo: true,
      })
      if (!ok) return
    }
    try {
      await configurar.mutateAsync({ ancora, fase: Math.trunc(Number(fase) || 0) })
      avisos.sucesso('Rodízio atualizado.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  async function aplicarModelo() {
    const ok = await avisos.confirmar({
      titulo: 'Completar com o modelo Macaw?',
      mensagem:
        'Cria os setores e as posições do modelo que ainda faltam (Salão, Maître, Areia, Bar, ASG e Cozinha). O que você já editou não muda.',
      textoConfirmar: 'Completar',
    })
    if (!ok) return
    try {
      const r = await modelo.mutateAsync({ ancora: null })
      avisos.sucesso(
        r.membros || r.setores
          ? `Modelo aplicado: ${r.setores} setor(es), ${r.membros} posição(ões), ${r.funcionarios_criados} funcionário(s) provisório(s).`
          : 'A escala já tem todas as posições do modelo.',
      )
    } catch (e) {
      avisos.erro(e)
    }
  }

  // segunda-feira da semana de hoje (atalho)
  const segHoje = somarDias(hoje, -indiceSegunda(new Date(`${hoje}T12:00:00Z`).getUTCDay()))

  return (
    <Cartao
      sobrancelha="Configuração"
      titulo="Rodízio contínuo"
      acoes={
        <Botao variante="secundario" tamanho="p" icone={<LayoutTemplate aria-hidden />} carregando={modelo.isPending} onClick={() => void aplicarModelo()}>
          Completar com o modelo Macaw
        </Botao>
      }
    >
      <div className="flex flex-wrap items-end gap-3">
        <Campo
          rotulo="Data-âncora (segunda-feira)"
          htmlFor="escala-ancora"
          erro={ancora && !segunda ? 'Escolha uma segunda-feira' : null}
        >
          <Entrada id="escala-ancora" type="date" value={ancora} onChange={(e) => setAncora(e.target.value)} className="w-[180px]!" />
        </Campo>
        <Campo rotulo="Fase" htmlFor="escala-fase">
          <Entrada id="escala-fase" type="number" min={-1000} max={1000} value={fase} onChange={(e) => setFase(e.target.value)} className="w-[100px]!" />
        </Campo>
        <div className="flex gap-2 pb-0.5">
          <Botao tamanho="m" disabled={!mudou} carregando={configurar.isPending} onClick={() => void salvar()}>
            Salvar
          </Botao>
          {ancora !== segHoje && (
            <Botao variante="fantasma" tamanho="m" onClick={() => setAncora(segHoje)}>
              Usar esta semana
            </Botao>
          )}
        </div>
      </div>
      <p className="mt-3 text-xs leading-relaxed text-lavanda">
        A semana que começa na data-âncora é a semana 0 do rodízio; a cada semana cada pessoa assume as folgas da próxima posição do seu
        caminho, sem recomeçar no mês. A fase adianta o rodízio em semanas sem mudar a âncora (o setor também tem a sua).
        {semana.semana != null && ` Esta semana é a ${semana.semana}.`}
      </p>
    </Cartao>
  )
}

function NovoSetor() {
  const avisos = useAvisos()
  const salvar = useSalvarSetor()
  const [nome, setNome] = useState('')
  async function criar() {
    try {
      await salvar.mutateAsync({ nome: nome.trim() })
      setNome('')
      avisos.sucesso('Setor criado.')
    } catch (e) {
      avisos.erro(e)
    }
  }
  return (
    <Cartao sobrancelha="Novo setor">
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          if (nome.trim()) void criar()
        }}
      >
        <Campo rotulo="Nome do setor" htmlFor="escala-novo-setor">
          <Entrada id="escala-novo-setor" value={nome} maxLength={40} placeholder="ex.: Delivery" onChange={(e) => setNome(e.target.value)} />
        </Campo>
        <Botao type="submit" variante="secundario" icone={<Plus aria-hidden />} disabled={!nome.trim()} carregando={salvar.isPending}>
          Criar setor
        </Botao>
      </form>
    </Cartao>
  )
}

// ------------------------------------------------------------------ setor

interface Rascunho {
  funcionario_id: string
  nome: string
  cargo: string | null
  folgas: number[]
  chegada: string
  caminho: number | null
  posicao: string
}

function rascunhoDe(setor: EscalaSetorSemana): Rascunho[] {
  return setor.membros.map((m) => ({
    funcionario_id: m.funcionario_id,
    nome: m.nome,
    cargo: m.cargo,
    folgas: [...m.folgas_base].sort((a, b) => a - b),
    chegada: horaParaChegada(m.chegada_padrao),
    caminho: m.caminho,
    posicao: m.posicao == null ? '' : String(m.posicao),
  }))
}

const assinatura = (r: Rascunho[]) =>
  JSON.stringify(r.map((x) => [x.funcionario_id, x.folgas, chegadaValida(x.chegada), x.caminho, x.caminho == null ? '' : x.posicao]))

function CartaoSetor({ setor, editar, naEscala, hoje }: { setor: EscalaSetorSemana; editar: boolean; naEscala: Set<string>; hoje: string }) {
  const avisos = useAvisos()
  const definir = useDefinirMembros()
  const salvarSetor = useSalvarSetor()
  const excluirSetor = useExcluirSetor()
  const original = useMemo(() => rascunhoDe(setor), [setor])
  const [linhas, setLinhas] = useState(original)
  const [nomeSetor, setNomeSetor] = useState(setor.nome)
  const [faseSetor, setFaseSetor] = useState(String(setor.fase))
  useEffect(() => setLinhas(original), [original])
  useEffect(() => {
    setNomeSetor(setor.nome)
    setFaseSetor(String(setor.fase))
  }, [setor.nome, setor.fase])

  const sujo = assinatura(linhas) !== assinatura(original)
  const maxCaminho = Math.max(0, ...linhas.map((l) => l.caminho ?? 0))
  const mudar = (i: number, p: Partial<Rascunho>) => setLinhas((ls) => ls.map((l, j) => (j === i ? { ...l, ...p } : l)))

  async function salvarMembros() {
    const vistos = new Set<string>()
    for (const l of linhas) {
      if (l.caminho == null || !l.posicao) continue
      const k = `${l.caminho}|${Number(l.posicao)}`
      if (vistos.has(k)) return avisos.erro(new Error(`Posição já ocupada no caminho (caminho ${l.caminho}, posição ${l.posicao})`))
      vistos.add(k)
    }
    try {
      await definir.mutateAsync({
        setorId: setor.id,
        membros: linhas.map((l) => ({
          funcionario_id: l.funcionario_id,
          folgas_base: l.folgas,
          chegada_padrao: chegadaParaHora(chegadaValida(l.chegada)),
          caminho: l.caminho,
          posicao: l.caminho == null || !l.posicao ? null : Number(l.posicao),
        })),
      })
      avisos.sucesso(`${setor.nome}: escala salva.`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  async function salvarDadosSetor() {
    try {
      await salvarSetor.mutateAsync({ id: setor.id, nome: nomeSetor.trim(), fase: Math.trunc(Number(faseSetor) || 0) })
      avisos.sucesso('Setor atualizado.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  async function apagarSetor() {
    const ok = await avisos.confirmar({
      titulo: `Excluir o setor ${setor.nome}?`,
      mensagem: 'As pessoas saem da escala (os ajustes e férias delas são apagados). Os funcionários continuam cadastrados.',
      textoConfirmar: 'Excluir setor',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluirSetor.mutateAsync(setor.id)
      avisos.sucesso('Setor excluído.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const dadosSetorMudou = nomeSetor.trim() !== setor.nome || Number(faseSetor) !== setor.fase

  return (
    <Cartao
      sobrancelha={`Setor · ${setor.membros.length} pessoa(s)`}
      titulo={setor.nome}
      acoes={
        editar && (
          <Botao variante="fantasma" tamanho="p" icone={<Trash2 aria-hidden />} onClick={() => void apagarSetor()} aria-label={`Excluir setor ${setor.nome}`}>
            Excluir
          </Botao>
        )
      }
    >
      {editar && (
        <div className="mb-4 flex flex-wrap items-end gap-2">
          <Campo rotulo="Nome do setor" htmlFor={`setor-nome-${setor.id}`}>
            <Entrada id={`setor-nome-${setor.id}`} value={nomeSetor} maxLength={40} onChange={(e) => setNomeSetor(e.target.value)} />
          </Campo>
          <Campo rotulo="Fase do setor" htmlFor={`setor-fase-${setor.id}`}>
            <Entrada
              id={`setor-fase-${setor.id}`}
              type="number"
              min={-1000}
              max={1000}
              value={faseSetor}
              onChange={(e) => setFaseSetor(e.target.value)}
              className="w-[100px]!"
            />
          </Campo>
          {dadosSetorMudou && (
            <Botao variante="secundario" disabled={!nomeSetor.trim()} carregando={salvarSetor.isPending} onClick={() => void salvarDadosSetor()}>
              Salvar setor
            </Botao>
          )}
        </div>
      )}

      {linhas.length === 0 && <p className="text-sm text-lavanda">Ninguém neste setor ainda.</p>}
      <div className="grid gap-3 md:grid-cols-2">
        {linhas.map((l, i) => (
          <Membro
            key={l.funcionario_id}
            l={l}
            editar={editar}
            maxCaminho={maxCaminho}
            hoje={hoje}
            aoMudar={(p) => mudar(i, p)}
          />
        ))}
      </div>

      {editar && sujo && (
        <div className="sticky bottom-20 z-10 mt-4 flex flex-wrap items-center justify-end gap-2 rounded-entrada border border-ouro/40 bg-cartao p-3 shadow-cartao lg:bottom-4">
          <span className="mr-auto text-sm text-lavanda">Alterações não salvas em {setor.nome}.</span>
          <Botao variante="fantasma" onClick={() => setLinhas(original)}>
            Descartar
          </Botao>
          <Botao carregando={definir.isPending} onClick={() => void salvarMembros()}>
            Salvar {setor.nome}
          </Botao>
        </div>
      )}

      {editar && <AdicionarAoSetor setorId={setor.id} naEscala={naEscala} proximoCaminho={maxCaminho || 1} />}
    </Cartao>
  )
}

function Membro({
  l,
  editar,
  maxCaminho,
  hoje,
  aoMudar,
}: {
  l: Rascunho
  editar: boolean
  maxCaminho: number
  hoje: string
  aoMudar(p: Partial<Rascunho>): void
}) {
  const avisos = useAvisos()
  const qc = useQueryClient()
  const salvarFunc = useSalvarFuncionario()
  const remover = useRemoverMembro()
  const periodo = useAjustarPeriodo()
  const [editandoNome, setEditandoNome] = useState(false)
  const [nome, setNome] = useState(l.nome)
  const [cargo, setCargo] = useState(l.cargo ?? '')
  const [feriasDe, setFeriasDe] = useState('')
  const [feriasAte, setFeriasAte] = useState('')
  const id = l.funcionario_id

  async function salvarNome() {
    try {
      await salvarFunc.mutateAsync({ id, dados: { nome: nome.trim(), cargo: cargo.trim() || null } })
      await invalidar(qc, 'escala-mes', 'escala-semana')
      setEditandoNome(false)
      avisos.sucesso('Nome atualizado.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  async function tirarDaEscala() {
    const ok = await avisos.confirmar({
      titulo: `Tirar ${l.nome} da escala?`,
      mensagem: 'Os ajustes e férias dessa pessoa na escala são apagados. O cadastro do funcionário continua.',
      textoConfirmar: 'Tirar da escala',
      perigo: true,
    })
    if (!ok) return
    try {
      await remover.mutateAsync(id)
      avisos.sucesso('Pessoa retirada da escala.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  async function ferias(status: 'ferias' | null) {
    if (!feriasDe) return avisos.erro(new Error('Informe a data'))
    const fim = feriasAte || feriasDe
    try {
      const n = await periodo.mutateAsync({ funcionarioId: id, inicio: feriasDe, fim, status })
      avisos.sucesso(status ? `Férias marcadas em ${n} dia(s).` : `Férias retiradas de ${n} dia(s).`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  const alternarFolga = (d: number) =>
    aoMudar({ folgas: l.folgas.includes(d) ? l.folgas.filter((x) => x !== d) : [...l.folgas, d].sort((a, b) => a - b) })

  if (!editar) {
    return (
      <div className="rounded-entrada border border-borda bg-noite p-3 text-sm">
        <p className="font-semibold text-creme">
          {l.nome} {l.cargo && <span className="font-normal text-lavanda">· {l.cargo}</span>}
        </p>
        <p className="mt-1 text-xs text-lavanda">
          Folgas na semana base: {textoFolgas(l.folgas) || '—'}
          {l.chegada && ` · chegada ${l.chegada}`} · {l.caminho == null ? 'folga fixa' : `caminho ${l.caminho}, posição ${l.posicao}`}
        </p>
      </div>
    )
  }

  return (
    <div className="flex min-w-0 flex-col gap-2.5 rounded-entrada border border-borda bg-noite p-3" data-teste="membro" data-nome={l.nome}>
      {editandoNome ? (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex min-w-0 flex-1 flex-col gap-1">
            <span className={ROTULO}>Nome</span>
            <Entrada value={nome} maxLength={80} onChange={(e) => setNome(e.target.value)} aria-label="Nome do funcionário" />
          </label>
          <label className="flex w-32 flex-col gap-1">
            <span className={ROTULO}>Cargo</span>
            <Entrada value={cargo} maxLength={40} onChange={(e) => setCargo(e.target.value)} aria-label="Cargo do funcionário" />
          </label>
          <Botao tamanho="p" aria-label="Salvar nome" icone={<Check aria-hidden />} disabled={!nome.trim()} carregando={salvarFunc.isPending} onClick={() => void salvarNome()}>
            Salvar
          </Botao>
          <Botao variante="fantasma" tamanho="p" aria-label="Cancelar edição do nome" icone={<X aria-hidden />} onClick={() => setEditandoNome(false)} />
        </div>
      ) : (
        <div className="flex items-start justify-between gap-2">
          <p className="min-w-0 truncate font-semibold text-creme">
            {l.nome} {l.cargo && <span className="font-normal text-lavanda">· {l.cargo}</span>}
          </p>
          <div className="flex shrink-0 gap-1">
            <button
              type="button"
              aria-label={`Editar nome de ${l.nome}`}
              title="Editar nome e cargo"
              onClick={() => {
                setNome(l.nome)
                setCargo(l.cargo ?? '')
                setEditandoNome(true)
              }}
              className={clsx('rounded-lg p-1.5 text-lavanda hover:bg-cartao-2 hover:text-creme', FOCO)}
            >
              <Pencil aria-hidden className="size-4" />
            </button>
            <button
              type="button"
              aria-label={`Tirar ${l.nome} da escala`}
              title="Tirar da escala"
              onClick={() => void tirarDaEscala()}
              className={clsx('rounded-lg p-1.5 text-lavanda hover:bg-perigo/10 hover:text-perigo', FOCO)}
            >
              <Trash2 aria-hidden className="size-4" />
            </button>
          </div>
        </div>
      )}

      <div>
        <p className={ROTULO}>Folgas na semana base</p>
        <div className="mt-1 flex flex-wrap gap-1" role="group" aria-label={`Folgas de ${l.nome}`}>
          {DIAS_SEMANA.map((d, i) => {
            const on = l.folgas.includes(i)
            return (
              <button
                key={d}
                type="button"
                aria-pressed={on}
                onClick={() => alternarFolga(i)}
                className={clsx(
                  'h-8 min-w-11 rounded-lg border px-1.5 text-xs font-semibold transition-colors',
                  FOCO,
                  on ? 'border-folga/50 bg-folga-suave text-perigo' : 'border-borda bg-cartao text-lavanda hover:text-creme',
                )}
              >
                {d}
              </button>
            )
          })}
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1">
          <span className={ROTULO}>Chegada padrão</span>
          <Entrada
            value={l.chegada}
            maxLength={6}
            placeholder="ex.: 8"
            aria-label={`Chegada padrão de ${l.nome}`}
            onChange={(e) => aoMudar({ chegada: e.target.value })}
            onBlur={(e) => aoMudar({ chegada: chegadaValida(e.target.value) })}
            className="h-9! w-[84px]!"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className={ROTULO}>Rodízio</span>
          <Selecao
            value={l.caminho == null ? '' : String(l.caminho)}
            aria-label={`Rodízio de ${l.nome}`}
            onChange={(e) => aoMudar({ caminho: e.target.value ? Number(e.target.value) : null, posicao: '' })}
            className="h-9! w-[140px]!"
          >
            <option value="">Folga fixa</option>
            {Array.from({ length: Math.min(20, maxCaminho + 1) }, (_, k) => k + 1).map((c) => (
              <option key={c} value={c}>
                Caminho {c}
              </option>
            ))}
          </Selecao>
        </label>
        {l.caminho != null && (
          <label className="flex flex-col gap-1">
            <span className={ROTULO}>Posição</span>
            <Entrada
              type="number"
              min={1}
              max={99}
              value={l.posicao}
              placeholder="próx."
              aria-label={`Posição de ${l.nome} no caminho`}
              onChange={(e) => aoMudar({ posicao: e.target.value })}
              className="h-9! w-[72px]!"
            />
          </label>
        )}
      </div>

      <details className="group">
        <summary className={clsx('cursor-pointer text-xs font-semibold text-ouro-claro', FOCO)}>Férias</summary>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1">
            <span className={ROTULO}>De</span>
            <Entrada type="date" value={feriasDe} min={somarDias(hoje, -62)} onChange={(e) => setFeriasDe(e.target.value)} className="h-9! w-[150px]!" aria-label="Início das férias" />
          </label>
          <label className="flex flex-col gap-1">
            <span className={ROTULO}>Até</span>
            <Entrada type="date" value={feriasAte} min={feriasDe || undefined} onChange={(e) => setFeriasAte(e.target.value)} className="h-9! w-[150px]!" aria-label="Fim das férias" />
          </label>
          <Botao tamanho="p" variante="secundario" carregando={periodo.isPending} onClick={() => void ferias('ferias')}>
            Marcar férias
          </Botao>
          <Botao tamanho="p" variante="fantasma" disabled={periodo.isPending} onClick={() => void ferias(null)}>
            Tirar férias
          </Botao>
        </div>
        <p className="mt-1 text-xs text-lavanda">Até 62 dias por vez. Os dias aparecem como FÉ na escala do mês e viram abono de férias no ponto.</p>
      </details>
    </div>
  )
}

function AdicionarAoSetor({ setorId, naEscala, proximoCaminho }: { setorId: string; naEscala: Set<string>; proximoCaminho: number }) {
  const avisos = useAvisos()
  const funcionarios = useFuncionarios()
  const salvarMembro = useSalvarMembro()
  const adicionar = useAdicionarFuncionarioEscala()
  const [escolhido, setEscolhido] = useState('')
  const [nome, setNome] = useState('')
  const [cargo, setCargo] = useState('')
  const livres = (funcionarios.data ?? []).filter((f) => f.ativo && !naEscala.has(f.id))
  const dados = { folgasBase: [] as number[], chegadaPadrao: null, caminho: proximoCaminho, posicao: null }

  async function incluir() {
    try {
      await salvarMembro.mutateAsync({ setorId, funcionarioId: escolhido, dados })
      setEscolhido('')
      avisos.sucesso('Pessoa adicionada. Marque as folgas da semana base.')
    } catch (e) {
      avisos.erro(e)
    }
  }
  async function cadastrar() {
    try {
      await adicionar.mutateAsync({ setorId, nome, cargo: cargo || null, dados })
      setNome('')
      setCargo('')
      avisos.sucesso('Funcionário cadastrado e incluído na escala.')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="mt-4 grid gap-3 border-t border-borda pt-4 lg:grid-cols-2">
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          if (escolhido) void incluir()
        }}
      >
        <label className="flex min-w-0 flex-1 flex-col gap-1">
          <span className={ROTULO}>Adicionar funcionário cadastrado</span>
          <Selecao value={escolhido} onChange={(e) => setEscolhido(e.target.value)} aria-label="Funcionário cadastrado" className="h-9!">
            <option value="">{livres.length ? 'Escolha…' : 'Todos já estão na escala'}</option>
            {livres.map((f) => (
              <option key={f.id} value={f.id}>
                {f.nome}
                {f.cargo ? ` · ${f.cargo}` : ''}
              </option>
            ))}
          </Selecao>
        </label>
        <Botao type="submit" tamanho="p" variante="secundario" icone={<Plus aria-hidden />} disabled={!escolhido} carregando={salvarMembro.isPending}>
          Adicionar
        </Botao>
      </form>
      <form
        className="flex flex-wrap items-end gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          if (nome.trim()) void cadastrar()
        }}
      >
        <label className="flex min-w-0 flex-1 flex-col gap-1">
          <span className={ROTULO}>Novo funcionário neste setor</span>
          <Entrada value={nome} maxLength={80} placeholder="Nome" aria-label="Nome do novo funcionário" onChange={(e) => setNome(e.target.value)} className="h-9!" />
        </label>
        <Entrada value={cargo} maxLength={40} placeholder="Cargo" aria-label="Cargo do novo funcionário" onChange={(e) => setCargo(e.target.value)} className="h-9! w-28!" />
        <Botao type="submit" tamanho="p" icone={<UserPlus aria-hidden />} disabled={!nome.trim()} carregando={adicionar.isPending}>
          Cadastrar
        </Botao>
      </form>
    </div>
  )
}
