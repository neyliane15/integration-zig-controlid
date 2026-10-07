import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { CalendarClock, DoorOpen, Plus, Search, Users } from 'lucide-react'
import type { ControlIdEnvio, Funcionario, StatusEnvioControlId } from '@/tipos/banco'
import { CabecalhoPagina, Campo, Entrada, ErroCarga, Selecao, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { SeloStatusEnvio } from '@/componentes/dominio/Selos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import {
  envioAtivo,
  useControlIdUsuarios,
  useEnviosEmpresa,
  useEquipamentosControlId,
  useFuncionarios,
  useJornadasVigentes,
} from '@/consultas/funcionarios'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { normalizar } from '@/lib/formato'

type FiltroSituacao = 'ativos' | 'inativos' | 'todos'

const PESO_ENVIO: Record<StatusEnvioControlId, number> = { erro: 5, aguardando: 4, enviando: 3, pendente: 2, enviado: 1 }

/** Pior status entre os equipamentos (erro > aguardando > enviando > pendente > enviado). */
function piorEnvio(envios: ControlIdEnvio[]): StatusEnvioControlId | null {
  let pior: StatusEnvioControlId | null = null
  for (const e of envios) if (!pior || PESO_ENVIO[e.status] > PESO_ENVIO[pior]) pior = e.status
  return pior
}

function formatarPontos(p: number): string {
  return Number(p).toLocaleString('pt-BR', { maximumFractionDigits: 2 })
}

export function PaginaFuncionarios() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const navegar = useNavigate()
  const [params, setParams] = useSearchParams()
  const [busca, setBusca] = useState(params.get('busca') ?? '')
  const situacao = (params.get('situacao') as FiltroSituacao | null) ?? 'ativos'
  const cargo = params.get('cargo') ?? ''

  const funcionarios = useFuncionarios()
  const jornadas = useJornadasVigentes()
  const usuarios = useControlIdUsuarios()
  const equipamentos = useEquipamentosControlId()
  const envios = useEnviosEmpresa()

  const definir = (chave: string, valor: string | null) => {
    const p = new URLSearchParams(params)
    if (valor) p.set(chave, valor)
    else p.delete(chave)
    setParams(p, { replace: true })
  }

  const cargos = useMemo(
    () => [...new Set((funcionarios.data ?? []).map((f) => f.cargo?.trim()).filter((c): c is string => !!c))].sort((a, b) => a.localeCompare(b, 'pt-BR')),
    [funcionarios.data],
  )

  const vinculos = useMemo(() => {
    const m = new Map<string, number>()
    for (const u of usuarios.data ?? []) if (u.funcionario_id && !u.removido_no_equipamento) m.set(u.funcionario_id, (m.get(u.funcionario_id) ?? 0) + 1)
    return m
  }, [usuarios.data])

  const enviosPorFuncionario = useMemo(() => {
    const ligados = new Set((equipamentos.data ?? []).filter(envioAtivo).map((e) => e.id))
    const m = new Map<string, ControlIdEnvio[]>()
    for (const e of envios.data ?? []) {
      if (!e.funcionario_id || e.alvo !== 'funcionario' || !ligados.has(e.integracao_id)) continue
      m.set(e.funcionario_id, [...(m.get(e.funcionario_id) ?? []), e])
    }
    return m
  }, [envios.data, equipamentos.data])

  const totalEquipamentos = equipamentos.data?.length ?? 0
  const algumEnvioLigado = (equipamentos.data ?? []).some(envioAtivo)

  const linhas = useMemo(() => {
    const termo = normalizar(busca)
    return (funcionarios.data ?? []).filter((f) => {
      if (situacao === 'ativos' && !f.ativo) return false
      if (situacao === 'inativos' && f.ativo) return false
      if (cargo && (f.cargo ?? '').trim() !== cargo) return false
      if (!termo) return true
      return [f.nome, f.apelido, f.matricula, f.cpf, f.cargo, f.zig_employee_name].some((v) => v && normalizar(v).includes(termo))
    })
  }, [funcionarios.data, busca, situacao, cargo])

  const colunas: Coluna<Funcionario>[] = [
    {
      id: 'nome',
      titulo: 'Funcionário',
      render: (f) => (
        <div className="min-w-0">
          <p className="truncate font-semibold text-creme">{f.nome}</p>
          <p className="text-xs text-lavanda">
            {f.apelido ? `${f.apelido} · ` : ''}
            {f.matricula ? `matrícula ${f.matricula}` : 'sem matrícula'}
          </p>
        </div>
      ),
    },
    { id: 'cargo', titulo: 'Cargo', render: (f) => f.cargo || <span className="text-lavanda-escuro">—</span> },
    {
      id: 'pontos',
      titulo: 'Pontos',
      alinhar: 'direita',
      render: (f) => (
        <span className={f.participa_comissao ? 'numero' : 'numero text-lavanda-escuro'} title={f.participa_comissao ? undefined : 'Não participa da comissão'}>
          {formatarPontos(f.pontos_comissao)}
        </span>
      ),
    },
    {
      id: 'jornada',
      titulo: 'Jornada',
      ocultarNoCelular: true,
      render: (f) => jornadas.data?.get(f.id) ?? <span className="text-lavanda-escuro">sem jornada</span>,
    },
    {
      id: 'vinculos',
      titulo: 'Vínculos',
      render: (f) => {
        const n = vinculos.get(f.id) ?? 0
        return (
          <div className="flex flex-wrap gap-1">
            {operar && totalEquipamentos > 0 && (
              <Selo tom={n > 0 ? 'sucesso' : 'alerta'}>
                Control iD {n}/{totalEquipamentos}
              </Selo>
            )}
            <Selo tom={f.zig_employee_name ? 'sucesso' : 'neutro'}>{f.zig_employee_name ? 'Zig' : 'Sem Zig'}</Selo>
          </div>
        )
      },
    },
    ...(operar && algumEnvioLigado
      ? [
          {
            id: 'envio',
            titulo: 'Envio',
            ocultarNoCelular: true,
            render: (f: Funcionario) => {
              const s = piorEnvio(enviosPorFuncionario.get(f.id) ?? [])
              return s ? <SeloStatusEnvio status={s} /> : <span className="text-lavanda-escuro">—</span>
            },
          } satisfies Coluna<Funcionario>,
        ]
      : []),
    {
      id: 'situacao',
      titulo: 'Situação',
      render: (f) => (f.ativo ? <Selo tom="sucesso">Ativo</Selo> : <Selo>Inativo</Selo>),
    },
  ]

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Equipe"
        titulo={
          <>
            Funcionários <span className="titulo-italico">da casa</span>
          </>
        }
        subtitulo="Cadastro, vínculos com o Control iD e a Zig, pontos de comissão e jornada."
        acoes={
          <>
            <BotaoLink to="/funcionarios/jornadas" icone={<CalendarClock aria-hidden />}>
              Jornadas
            </BotaoLink>
            <BotaoLink to="/funcionarios/horarios-acesso" icone={<DoorOpen aria-hidden />}>
              Horários de acesso
            </BotaoLink>
            {operar && (
              <BotaoLink to="/funcionarios/novo" variante="primario" icone={<Plus aria-hidden />}>
                Novo funcionário
              </BotaoLink>
            )}
          </>
        }
      />

      <div className="mb-5 grid gap-3 sm:grid-cols-[minmax(0,1fr)_180px_200px]">
        <Campo rotulo="Buscar" htmlFor="busca-funcionario">
          <div className="relative">
            <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-lavanda" />
            <Entrada
              id="busca-funcionario"
              type="search"
              placeholder="Nome, matrícula, CPF, cargo…"
              className="pl-9"
              value={busca}
              onChange={(e) => {
                setBusca(e.target.value)
                definir('busca', e.target.value || null)
              }}
            />
          </div>
        </Campo>
        <Campo rotulo="Situação" htmlFor="filtro-situacao">
          <Selecao id="filtro-situacao" value={situacao} onChange={(e) => definir('situacao', e.target.value === 'ativos' ? null : e.target.value)}>
            <option value="ativos">Ativos</option>
            <option value="inativos">Inativos</option>
            <option value="todos">Todos</option>
          </Selecao>
        </Campo>
        <Campo rotulo="Cargo" htmlFor="filtro-cargo">
          <Selecao id="filtro-cargo" value={cargo} onChange={(e) => definir('cargo', e.target.value || null)}>
            <option value="">Todos os cargos</option>
            {cargos.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </Selecao>
        </Campo>
      </div>

      {funcionarios.error ? (
        <ErroCarga erro={funcionarios.error} aoTentar={() => funcionarios.refetch()} />
      ) : (
        <>
          {!funcionarios.isLoading && (
            <p className="mb-3 text-sm text-lavanda" aria-live="polite">
              {linhas.length} de {funcionarios.data?.length ?? 0} funcionário(s)
            </p>
          )}
          <Tabela
            colunas={colunas}
            linhas={linhas}
            chave={(f) => f.id}
            carregando={funcionarios.isLoading}
            aoClicarLinha={(f) => navegar(`/funcionarios/${f.id}`)}
            vazio={
              (funcionarios.data?.length ?? 0) === 0 ? (
                <Vazio
                  icone={<Users className="size-8" />}
                  titulo="Nenhum funcionário ainda"
                  descricao="Cadastre a equipe para acompanhar ponto, comissão e tarefas."
                  acao={
                    operar && (
                      <BotaoLink to="/funcionarios/novo" variante="primario">
                        Cadastrar o primeiro
                      </BotaoLink>
                    )
                  }
                />
              ) : (
                <Vazio titulo="Ninguém encontrado" descricao="Ajuste a busca ou os filtros." />
              )
            }
          />
        </>
      )}
    </div>
  )
}
