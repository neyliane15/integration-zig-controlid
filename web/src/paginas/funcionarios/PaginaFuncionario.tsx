import { useEffect, useId, useMemo, useState, type FormEvent, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, CalendarPlus, Clock, Save, Trash2, UserMinus, UserCheck } from 'lucide-react'
import type { Funcionario } from '@/tipos/banco'
import {
  Abas,
  AreaTexto,
  Botao,
  CabecalhoPagina,
  Campo,
  Carregando,
  Cartao,
  Entrada,
  EntradaData,
  ErroCarga,
  Interruptor,
  Selecao,
  Selo,
  Tabela,
  Vazio,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { VinculoControlId } from '@/componentes/dominio/VinculoControlId'
import { CredenciaisControlId, EstadoEnvioControlId } from '@/componentes/dominio/EnvioControlId'
import {
  useContextoEmpresa,
  useDefinirJornadaFuncionario,
  useExcluirFuncionario,
  useFuncionario,
  useFuncionarioHorarios,
  useFuncionarios,
  useHorariosAcesso,
  useJornadas,
  useJornadasDoFuncionario,
  useNomesZig,
  usePontosFuncionario,
  useRemoverJornadaFuncionario,
  useSalvarFuncionario,
  useVincularHorario,
  type DadosFuncionario,
} from '@/consultas/funcionarios'
import { usePerfil } from '@/lib/sessao'
import { podeAdministrar, podeOperar } from '@/lib/permissoes'
import { formatarData, formatarDataHora, normalizar } from '@/lib/formato'
import { descreverFaixasHorario } from './horariosAcesso'

type Aba = 'dados' | 'vinculos' | 'comissao' | 'jornada' | 'controlid'

interface Formulario {
  nome: string
  apelido: string
  matricula: string
  cpf: string
  pis: string
  cargo: string
  telefone: string
  email: string
  zig_employee_name: string
  pontos_comissao: string
  participa_comissao: boolean
  data_admissao: string | null
  data_desligamento: string | null
  ativo: boolean
  observacoes: string
}

const VAZIO: Formulario = {
  nome: '',
  apelido: '',
  matricula: '',
  cpf: '',
  pis: '',
  cargo: '',
  telefone: '',
  email: '',
  zig_employee_name: '',
  pontos_comissao: '0',
  participa_comissao: true,
  data_admissao: null,
  data_desligamento: null,
  ativo: true,
  observacoes: '',
}

function paraFormulario(f: Funcionario): Formulario {
  return {
    nome: f.nome,
    apelido: f.apelido ?? '',
    matricula: f.matricula ?? '',
    cpf: f.cpf ?? '',
    pis: f.pis ?? '',
    cargo: f.cargo ?? '',
    telefone: f.telefone ?? '',
    email: f.email ?? '',
    zig_employee_name: f.zig_employee_name ?? '',
    pontos_comissao: String(f.pontos_comissao ?? 0).replace('.', ','),
    participa_comissao: f.participa_comissao,
    data_admissao: f.data_admissao,
    data_desligamento: f.data_desligamento,
    ativo: f.ativo,
    observacoes: f.observacoes ?? '',
  }
}

const digitos = (s: string) => s.replace(/\D/g, '')
const vazioParaNull = (s: string) => (s.trim() === '' ? null : s.trim())

function lerPontos(s: string): number | null {
  const n = Number(s.replace(',', '.').trim() || '0')
  return Number.isFinite(n) && n >= 0 && n < 1_000_000 ? Math.round(n * 100) / 100 : null
}

function validar(f: Formulario): Partial<Record<keyof Formulario, string>> {
  const e: Partial<Record<keyof Formulario, string>> = {}
  if (!f.nome.trim()) e.nome = 'Informe o nome'
  if (f.cpf && digitos(f.cpf).length !== 11) e.cpf = 'CPF deve ter 11 dígitos'
  if (f.pis && digitos(f.pis).length !== 11) e.pis = 'PIS deve ter 11 dígitos'
  if (f.email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email.trim())) e.email = 'E-mail inválido'
  if (lerPontos(f.pontos_comissao) == null) e.pontos_comissao = 'Pontos inválidos'
  if (f.data_admissao && f.data_desligamento && f.data_desligamento < f.data_admissao) e.data_desligamento = 'Desligamento antes da admissão'
  return e
}

function paraDados(f: Formulario): DadosFuncionario {
  return {
    nome: f.nome.trim(),
    apelido: vazioParaNull(f.apelido),
    matricula: vazioParaNull(f.matricula),
    cpf: vazioParaNull(digitos(f.cpf)),
    pis: vazioParaNull(digitos(f.pis)),
    cargo: vazioParaNull(f.cargo),
    telefone: vazioParaNull(f.telefone),
    email: vazioParaNull(f.email),
    zig_employee_name: vazioParaNull(f.zig_employee_name),
    pontos_comissao: lerPontos(f.pontos_comissao) ?? 0,
    participa_comissao: f.participa_comissao,
    data_admissao: f.data_admissao,
    data_desligamento: f.data_desligamento,
    ativo: f.ativo,
    observacoes: vazioParaNull(f.observacoes),
  }
}

export function PaginaFuncionario() {
  const { id } = useParams()
  const novo = !id || id === 'novo'
  const consulta = useFuncionario(novo ? null : id)

  if (!novo && consulta.isLoading) return <Carregando texto="Carregando funcionário…" />
  if (!novo && consulta.error)
    return (
      <div className="mx-auto max-w-5xl">
        <BotaoLink to="/funcionarios" variante="fantasma" icone={<ArrowLeft aria-hidden />} className="mb-4">
          Funcionários
        </BotaoLink>
        <ErroCarga erro={consulta.error} aoTentar={() => consulta.refetch()} />
      </div>
    )
  return <Ficha key={id ?? 'novo'} funcionario={novo ? null : (consulta.data ?? null)} />
}

function Ficha({ funcionario }: { funcionario: Funcionario | null }) {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const administrar = podeAdministrar(perfil.papel)
  const navegar = useNavigate()
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const salvar = useSalvarFuncionario()
  const excluir = useExcluirFuncionario()
  const todos = useFuncionarios()
  const [aba, setAba] = useState<Aba>('dados')
  const [form, setForm] = useState<Formulario>(() => (funcionario ? paraFormulario(funcionario) : VAZIO))
  const [tentou, setTentou] = useState(false)
  const idForm = useId()

  useEffect(() => {
    if (funcionario) setForm(paraFormulario(funcionario))
  }, [funcionario])

  const erros = tentou ? validar(form) : {}
  const alterado = useMemo(
    () => JSON.stringify(paraDados(form)) !== JSON.stringify(funcionario ? paraDados(paraFormulario(funcionario)) : paraDados(VAZIO)),
    [form, funcionario],
  )
  const cargos = useMemo(
    () => [...new Set((todos.data ?? []).map((f) => f.cargo?.trim()).filter((c): c is string => !!c))].sort(),
    [todos.data],
  )

  const mudar = <K extends keyof Formulario>(k: K, v: Formulario[K]) => setForm((f) => ({ ...f, [k]: v }))

  const enviar = async (e?: FormEvent) => {
    e?.preventDefault()
    setTentou(true)
    const problemas = validar(form)
    if (Object.keys(problemas).length) {
      const primeiro = Object.keys(problemas)[0]
      if (primeiro === 'pontos_comissao') setAba('comissao')
      else if (primeiro === 'zig_employee_name') setAba('vinculos')
      else setAba('dados')
      avisos.erro(Object.values(problemas)[0])
      return
    }
    try {
      const novoId = await salvar.mutateAsync({ id: funcionario?.id, dados: paraDados(form) })
      avisos.sucesso(funcionario ? 'Funcionário salvo' : 'Funcionário cadastrado')
      setTentou(false)
      if (!funcionario) navegar(`/funcionarios/${novoId}`, { replace: true })
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const desligar = async () => {
    if (!funcionario) return
    const ok = await avisos.confirmar({
      titulo: `Desligar ${funcionario.nome}?`,
      mensagem: (
        <>
          A data de desligamento será <strong>{formatarData(hoje)}</strong> e o cadastro ficará inativo. Nos equipamentos Control iD com envio
          ligado, o usuário será removido (ou bloqueado, conforme a configuração do equipamento). O histórico de ponto é mantido.
        </>
      ),
      textoConfirmar: 'Desligar',
      perigo: true,
    })
    if (!ok) return
    try {
      await salvar.mutateAsync({ id: funcionario.id, dados: { ativo: false, data_desligamento: hoje } })
      avisos.sucesso('Funcionário desligado')
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const reativar = async () => {
    if (!funcionario) return
    try {
      await salvar.mutateAsync({ id: funcionario.id, dados: { ativo: true, data_desligamento: null } })
      avisos.sucesso('Funcionário reativado')
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const apagar = async () => {
    if (!funcionario) return
    const ok = await avisos.confirmar({
      titulo: `Excluir ${funcionario.nome}?`,
      mensagem: 'Apaga o cadastro e TODO o histórico de ponto e banco de horas. Prefira “Desligar”. Esta ação não pode ser desfeita.',
      textoConfirmar: 'Excluir definitivamente',
      perigo: true,
    })
    if (!ok) return
    try {
      await excluir.mutateAsync(funcionario.id)
      avisos.sucesso('Funcionário excluído')
      navegar('/funcionarios', { replace: true })
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  const abas: { id: Aba; rotulo: ReactNode }[] = funcionario
    ? [
        { id: 'dados', rotulo: 'Dados' },
        { id: 'vinculos', rotulo: 'Vínculos' },
        { id: 'comissao', rotulo: 'Comissão' },
        { id: 'jornada', rotulo: 'Jornada' },
        ...(operar ? [{ id: 'controlid' as const, rotulo: 'Control iD' }] : []),
      ]
    : [
        { id: 'dados', rotulo: 'Dados' },
        { id: 'vinculos', rotulo: 'Nome na Zig' },
        { id: 'comissao', rotulo: 'Comissão' },
      ]

  const abaComForm = aba === 'dados' || aba === 'comissao' || aba === 'vinculos'

  return (
    <div className="mx-auto w-full max-w-5xl">
      <BotaoLink to="/funcionarios" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Funcionários
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha={funcionario ? (funcionario.cargo ?? 'Funcionário') : 'Novo cadastro'}
        titulo={funcionario ? funcionario.nome : 'Novo funcionário'}
        subtitulo={
          funcionario ? (
            <span className="flex flex-wrap items-center gap-2">
              {funcionario.ativo ? <Selo tom="sucesso">Ativo</Selo> : <Selo>Inativo</Selo>}
              {funcionario.matricula && <span className="numero">matrícula {funcionario.matricula}</span>}
              {funcionario.data_desligamento && <span>desligado em {formatarData(funcionario.data_desligamento)}</span>}
            </span>
          ) : (
            'A matrícula em branco é gerada automaticamente (é o “registration” no Control iD).'
          )
        }
        acoes={
          funcionario && (
            <>
              <BotaoLink to={`/ponto/funcionario/${funcionario.id}`} icone={<Clock aria-hidden />}>
                Espelho de ponto
              </BotaoLink>
              {operar &&
                (funcionario.ativo ? (
                  <Botao variante="secundario" icone={<UserMinus aria-hidden className="size-4" />} onClick={desligar} disabled={salvar.isPending}>
                    Desligar
                  </Botao>
                ) : (
                  <Botao variante="secundario" icone={<UserCheck aria-hidden className="size-4" />} onClick={reativar} disabled={salvar.isPending}>
                    Reativar
                  </Botao>
                ))}
              {administrar && (
                <Botao variante="perigo" icone={<Trash2 aria-hidden className="size-4" />} onClick={apagar} carregando={excluir.isPending}>
                  Excluir
                </Botao>
              )}
            </>
          )
        }
      />

      <Abas<Aba> abas={abas} ativa={aba} aoMudar={setAba} />

      <div className="mt-5">
        {abaComForm && (
          <form id={idForm} onSubmit={enviar} noValidate>
            <fieldset disabled={!operar} className="min-w-0">
              {aba === 'dados' && <AbaDados form={form} mudar={mudar} erros={erros} cargos={cargos} />}
              {aba === 'vinculos' && (
                <div className="flex flex-col gap-5">
                  <NomeZig form={form} mudar={mudar} funcionarioId={funcionario?.id ?? null} />
                  {funcionario && operar && (
                    <Cartao titulo="Control iD" sobrancelha="Usuários dos equipamentos">
                      <VinculoControlId funcionarioId={funcionario.id} />
                    </Cartao>
                  )}
                </div>
              )}
              {aba === 'comissao' && <AbaComissao form={form} mudar={mudar} erros={erros} funcionarioId={funcionario?.id ?? null} operar={operar} />}
            </fieldset>
            {operar && (
              <div className="sticky bottom-0 z-10 -mx-4 mt-6 flex flex-wrap items-center justify-end gap-3 border-t border-borda bg-noite/90 px-4 py-3 backdrop-blur sm:mx-0 sm:rounded-entrada sm:border">
                {alterado && <span className="mr-auto text-sm text-ouro-claro">Alterações não salvas</span>}
                <Botao type="submit" carregando={salvar.isPending} icone={<Save aria-hidden className="size-4" />} disabled={!alterado && !!funcionario}>
                  {funcionario ? 'Salvar' : 'Cadastrar'}
                </Botao>
              </div>
            )}
          </form>
        )}
        {aba === 'jornada' && funcionario && <AbaJornada funcionario={funcionario} operar={operar} />}
        {aba === 'controlid' && funcionario && operar && <AbaControlId funcionario={funcionario} />}
      </div>
    </div>
  )
}

type Mudar = <K extends keyof Formulario>(k: K, v: Formulario[K]) => void

function AbaDados({
  form,
  mudar,
  erros,
  cargos,
}: {
  form: Formulario
  mudar: Mudar
  erros: Partial<Record<keyof Formulario, string>>
  cargos: string[]
}) {
  const id = useId()
  return (
    <Cartao>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <Campo rotulo="Nome completo" htmlFor={`${id}-nome`} obrigatorio erro={erros.nome}>
            <Entrada id={`${id}-nome`} value={form.nome} invalido={!!erros.nome} onChange={(e) => mudar('nome', e.target.value)} autoComplete="off" />
          </Campo>
        </div>
        <Campo rotulo="Apelido" htmlFor={`${id}-apelido`}>
          <Entrada id={`${id}-apelido`} value={form.apelido} onChange={(e) => mudar('apelido', e.target.value)} />
        </Campo>
        <Campo rotulo="Cargo" htmlFor={`${id}-cargo`} ajuda="Ex.: Garçom, Cumim, Bartender, Cozinha">
          <Entrada id={`${id}-cargo`} list={`${id}-cargos`} value={form.cargo} onChange={(e) => mudar('cargo', e.target.value)} />
          <datalist id={`${id}-cargos`}>
            {cargos.map((c) => (
              <option key={c} value={c} />
            ))}
          </datalist>
        </Campo>
        <Campo rotulo="Matrícula" htmlFor={`${id}-matricula`} ajuda="Em branco: gerada automaticamente.">
          <Entrada id={`${id}-matricula`} className="numero" value={form.matricula} onChange={(e) => mudar('matricula', e.target.value)} />
        </Campo>
        <Campo rotulo="CPF" htmlFor={`${id}-cpf`} erro={erros.cpf} ajuda="Obrigatório para o relógio de ponto (REP).">
          <Entrada
            id={`${id}-cpf`}
            className="numero"
            inputMode="numeric"
            maxLength={14}
            value={form.cpf}
            invalido={!!erros.cpf}
            onChange={(e) => mudar('cpf', e.target.value.replace(/[^\d.-]/g, ''))}
          />
        </Campo>
        <Campo rotulo="PIS" htmlFor={`${id}-pis`} erro={erros.pis}>
          <Entrada
            id={`${id}-pis`}
            className="numero"
            inputMode="numeric"
            maxLength={14}
            value={form.pis}
            invalido={!!erros.pis}
            onChange={(e) => mudar('pis', e.target.value.replace(/[^\d.-]/g, ''))}
          />
        </Campo>
        <Campo rotulo="Telefone" htmlFor={`${id}-tel`}>
          <Entrada id={`${id}-tel`} type="tel" value={form.telefone} onChange={(e) => mudar('telefone', e.target.value)} />
        </Campo>
        <Campo rotulo="E-mail" htmlFor={`${id}-email`} erro={erros.email}>
          <Entrada id={`${id}-email`} type="email" value={form.email} invalido={!!erros.email} onChange={(e) => mudar('email', e.target.value)} />
        </Campo>
        <Campo rotulo="Admissão" htmlFor={`${id}-adm`}>
          <EntradaData id={`${id}-adm`} valor={form.data_admissao} aoMudar={(v) => mudar('data_admissao', v)} />
        </Campo>
        <Campo rotulo="Desligamento" htmlFor={`${id}-desl`} erro={erros.data_desligamento}>
          <EntradaData id={`${id}-desl`} valor={form.data_desligamento} min={form.data_admissao ?? undefined} aoMudar={(v) => mudar('data_desligamento', v)} />
        </Campo>
        <div className="sm:col-span-2">
          <Interruptor rotulo="Ativo (aparece nas listas e no ponto do dia)" marcado={form.ativo} aoMudar={(v) => mudar('ativo', v)} />
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Observações" htmlFor={`${id}-obs`}>
            <AreaTexto id={`${id}-obs`} value={form.observacoes} onChange={(e) => mudar('observacoes', e.target.value)} />
          </Campo>
        </div>
      </div>
    </Cartao>
  )
}

function NomeZig({ form, mudar, funcionarioId }: { form: Formulario; mudar: Mudar; funcionarioId: string | null }) {
  const id = useId()
  const nomes = useNomesZig()
  const termo = normalizar(form.zig_employee_name)
  const sugestoes = (nomes.data ?? []).filter((n) => !n.funcionarioId || n.funcionarioId === funcionarioId)
  const exato = (nomes.data ?? []).find((n) => normalizar(n.nome) === termo)
  return (
    <Cartao titulo="Zig" sobrancelha="Nome do garçom nas vendas">
      <Campo
        rotulo="Nome na Zig (employeeName)"
        htmlFor={id}
        ajuda="Exatamente como aparece nas vendas da Zig. Liga as vendas do garçom a este funcionário (vale também para o histórico)."
      >
        <Entrada id={id} list={`${id}-lista`} value={form.zig_employee_name} onChange={(e) => mudar('zig_employee_name', e.target.value)} autoComplete="off" />
        <datalist id={`${id}-lista`}>
          {sugestoes.map((n) => (
            <option key={n.nome} value={n.nome} />
          ))}
        </datalist>
      </Campo>
      {form.zig_employee_name.trim() && (
        <p className="mt-2 text-xs">
          {exato ? (
            exato.funcionarioId && exato.funcionarioId !== funcionarioId ? (
              <span className="text-alerta">Este nome já está ligado a outro funcionário.</span>
            ) : (
              <span className="text-sucesso">Nome encontrado nas vendas dos últimos 60 dias.</span>
            )
          ) : (
            <span className="text-lavanda">Nome ainda não visto nas vendas dos últimos 60 dias.</span>
          )}
        </p>
      )}
      {sugestoes.length > 0 && (
        <div className="mt-4">
          <p className="mb-2 text-xs font-bold tracking-[0.14em] text-lavanda uppercase">Sem vínculo nos últimos 60 dias</p>
          <div className="flex flex-wrap gap-1.5">
            {sugestoes
              .filter((n) => !n.funcionarioId)
              .slice(0, 12)
              .map((n) => (
                <button
                  key={n.nome}
                  type="button"
                  className="rounded-pilula border border-borda px-2.5 py-1 text-xs text-creme hover:border-ouro/60 focus-visible:outline-2 focus-visible:outline-ouro"
                  onClick={() => mudar('zig_employee_name', n.nome)}
                >
                  {n.nome}
                </button>
              ))}
          </div>
        </div>
      )}
    </Cartao>
  )
}

function AbaComissao({
  form,
  mudar,
  erros,
  funcionarioId,
  operar,
}: {
  form: Formulario
  mudar: Mudar
  erros: Partial<Record<keyof Formulario, string>>
  funcionarioId: string | null
  operar: boolean
}) {
  const id = useId()
  const historico = usePontosFuncionario(operar ? funcionarioId : null)
  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Cartao titulo="Pontos de comissão" sobrancelha="Rateio do serviço">
        <div className="flex flex-col gap-4">
          <Campo
            rotulo="Pontos"
            htmlFor={`${id}-pontos`}
            erro={erros.pontos_comissao}
            ajuda="Mudou? Vale a partir do dia de trabalho de hoje; o histórico fica guardado."
          >
            <Entrada
              id={`${id}-pontos`}
              className="numero"
              inputMode="decimal"
              value={form.pontos_comissao}
              invalido={!!erros.pontos_comissao}
              onChange={(e) => mudar('pontos_comissao', e.target.value.replace(/[^\d,.]/g, ''))}
            />
          </Campo>
          <Interruptor rotulo="Participa da comissão" marcado={form.participa_comissao} aoMudar={(v) => mudar('participa_comissao', v)} />
        </div>
      </Cartao>
      {funcionarioId && operar && (
        <Cartao titulo="Histórico de pontos" sobrancelha="Vigências">
          {historico.error ? (
            <ErroCarga erro={historico.error} aoTentar={() => historico.refetch()} />
          ) : (
            <Tabela
              colunas={[
                { id: 'desde', titulo: 'Vigente desde', render: (p) => <span className="numero">{formatarData(p.vigente_desde)}</span> },
                { id: 'pontos', titulo: 'Pontos', alinhar: 'direita', render: (p) => <span className="numero">{Number(p.pontos).toLocaleString('pt-BR')}</span> },
                { id: 'em', titulo: 'Registrado', ocultarNoCelular: true, render: (p) => <span className="text-lavanda">{formatarDataHora(p.criado_em)}</span> },
              ]}
              linhas={historico.data ?? []}
              chave={(p) => p.id}
              carregando={historico.isLoading}
              vazio={<Vazio titulo="Sem histórico" />}
            />
          )}
        </Cartao>
      )}
    </div>
  )
}

function AbaJornada({ funcionario, operar }: { funcionario: Funcionario; operar: boolean }) {
  const avisos = useAvisos()
  const { hoje } = useContextoEmpresa()
  const jornadas = useJornadas()
  const historico = useJornadasDoFuncionario(funcionario.id)
  const definir = useDefinirJornadaFuncionario()
  const remover = useRemoverJornadaFuncionario()
  const [jornadaId, setJornadaId] = useState('')
  const [desde, setDesde] = useState<string | null>(hoje)
  const id = useId()

  const vigente = (historico.data ?? []).find((h) => h.vigente_desde <= hoje)

  const salvarVigencia = async () => {
    if (!jornadaId || !desde) return avisos.erro('Escolha a jornada e a data')
    try {
      await definir.mutateAsync({ funcionarioId: funcionario.id, jornadaId, vigenteDesde: desde })
      avisos.sucesso('Jornada definida. O ponto será recalculado.')
      setJornadaId('')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
      <Cartao titulo="Jornada vigente" sobrancelha="Escala">
        {historico.isLoading ? (
          <Carregando />
        ) : vigente ? (
          <p className="font-display text-2xl text-creme">
            {vigente.jornadas?.nome ?? '—'} <span className="block text-sm font-sans text-lavanda">desde {formatarData(vigente.vigente_desde)}</span>
          </p>
        ) : (
          <p className="text-sm text-alerta">Sem jornada: o ponto não gera faltas nem alarmes de batida faltando.</p>
        )}
        {operar && (
          <div className="mt-5 flex flex-col gap-3 border-t border-borda pt-5">
            <p className="text-sm font-semibold text-creme">Nova vigência</p>
            <Campo rotulo="Jornada" htmlFor={`${id}-j`}>
              <Selecao id={`${id}-j`} value={jornadaId} onChange={(e) => setJornadaId(e.target.value)}>
                <option value="">Escolha…</option>
                {(jornadas.data ?? [])
                  .filter((j) => j.ativa)
                  .map((j) => (
                    <option key={j.id} value={j.id}>
                      {j.nome}
                    </option>
                  ))}
              </Selecao>
            </Campo>
            <Campo rotulo="A partir de" htmlFor={`${id}-d`}>
              <EntradaData id={`${id}-d`} valor={desde} aoMudar={setDesde} />
            </Campo>
            <div className="flex flex-wrap gap-2">
              <Botao icone={<CalendarPlus aria-hidden className="size-4" />} carregando={definir.isPending} onClick={salvarVigencia} disabled={!jornadaId || !desde}>
                Definir jornada
              </Botao>
              <BotaoLink to="/funcionarios/jornadas" variante="fantasma">
                Gerenciar jornadas
              </BotaoLink>
            </div>
          </div>
        )}
      </Cartao>
      <Cartao titulo="Histórico" sobrancelha="Vigências">
        {historico.error ? (
          <ErroCarga erro={historico.error} aoTentar={() => historico.refetch()} />
        ) : (
          <Tabela
            colunas={[
              { id: 'jornada', titulo: 'Jornada', render: (h) => h.jornadas?.nome ?? '—' },
              {
                id: 'desde',
                titulo: 'Desde',
                render: (h) => (
                  <span className="numero">
                    {formatarData(h.vigente_desde)}
                    {h.id === vigente?.id && (
                      <span className="ml-2">
                        <Selo tom="ouro">vigente</Selo>
                      </span>
                    )}
                    {h.vigente_desde > hoje && (
                      <span className="ml-2">
                        <Selo tom="info">futura</Selo>
                      </span>
                    )}
                  </span>
                ),
              },
              ...(operar
                ? [
                    {
                      id: 'acoes',
                      titulo: '',
                      alinhar: 'direita' as const,
                      render: (h: (typeof historico.data & object)[number]) => (
                        <Botao
                          variante="fantasma"
                          tamanho="p"
                          aria-label={`Remover vigência de ${formatarData(h.vigente_desde)}`}
                          icone={<Trash2 aria-hidden className="size-4" />}
                          onClick={async () => {
                            if (!(await avisos.confirmar({ titulo: 'Remover esta vigência?', mensagem: 'O ponto será recalculado.', perigo: true, textoConfirmar: 'Remover' }))) return
                            try {
                              await remover.mutateAsync(h.id)
                              avisos.sucesso('Vigência removida')
                            } catch (e) {
                              avisos.erro(e)
                            }
                          }}
                        />
                      ),
                    },
                  ]
                : []),
            ]}
            linhas={historico.data ?? []}
            chave={(h) => h.id}
            carregando={historico.isLoading}
            vazio={<Vazio titulo="Nenhuma jornada definida" />}
          />
        )}
      </Cartao>
    </div>
  )
}

function AbaControlId({ funcionario }: { funcionario: Funcionario }) {
  const avisos = useAvisos()
  const horarios = useHorariosAcesso()
  const vinculos = useFuncionarioHorarios()
  const vincular = useVincularHorario()
  const meus = new Set((vinculos.data ?? []).filter((v) => v.funcionario_id === funcionario.id).map((v) => v.horario_id))

  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Cartao titulo="Estado do envio" sobrancelha="Por equipamento" className="lg:col-span-2">
        <EstadoEnvioControlId funcionarioId={funcionario.id} editavel />
      </Cartao>
      <Cartao titulo="Credenciais" sobrancelha="Foto, cartão e senha">
        <CredenciaisControlId funcionarioId={funcionario.id} nome={funcionario.nome} editavel />
      </Cartao>
      <Cartao
        titulo="Horários de acesso"
        sobrancelha="Quando pode passar"
        acoes={
          <BotaoLink to="/funcionarios/horarios-acesso" variante="fantasma" tamanho="p">
            Gerenciar
          </BotaoLink>
        }
      >
        {horarios.isLoading || vinculos.isLoading ? (
          <Carregando />
        ) : horarios.error ? (
          <ErroCarga erro={horarios.error} aoTentar={() => horarios.refetch()} />
        ) : (horarios.data ?? []).length === 0 ? (
          <Vazio titulo="Nenhum horário de acesso" descricao="Sem horário vinculado vale a regra padrão do equipamento." />
        ) : (
          <>
            <p className="mb-3 text-sm text-lavanda">
              Sem nenhum marcado: sem restrição (regra padrão do equipamento). Com um ou mais: pode passar em qualquer faixa deles. Só equipamentos de
              acesso (não o REP).
            </p>
            <ul className="flex flex-col gap-2">
              {(horarios.data ?? []).map((h) => (
                <li key={h.id} className="rounded-entrada border border-borda bg-entrada/60 p-3">
                  <Interruptor
                    rotulo={
                      <span>
                        <span className="font-semibold">{h.nome}</span>
                        {!h.ativo && <span className="ml-2 text-xs text-lavanda">(inativo)</span>}
                        <span className="block text-xs text-lavanda">{descreverFaixasHorario(h.controlid_horario_faixas)}</span>
                      </span>
                    }
                    marcado={meus.has(h.id)}
                    desabilitado={vincular.isPending}
                    aoMudar={async (v) => {
                      try {
                        await vincular.mutateAsync({ funcionarioId: funcionario.id, horarioId: h.id, vincular: v })
                      } catch (e) {
                        avisos.erro(e)
                      }
                    }}
                  />
                </li>
              ))}
            </ul>
          </>
        )}
      </Cartao>
    </div>
  )
}
