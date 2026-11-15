/**
 * Query keys do react-query (contrato §14.8) + cliente e invalidações compartilhadas. Dono: frontend-1.
 * Use SEMPRE `chaves.x(...)` — nunca monte o array à mão.
 */
import { MutationCache, QueryCache, QueryClient } from '@tanstack/react-query'
import { supabase } from './supabase'

type Id = string | null | undefined

export const chaves = {
  painel: (empresaId: Id) => ['painel', empresaId ?? null] as const,
  funcionarios: (empresaId: Id) => ['funcionarios', empresaId ?? null] as const,
  funcionario: (id: Id) => ['funcionario', id ?? null] as const,
  jornadas: (empresaId: Id) => ['jornadas', empresaId ?? null] as const,
  controlidUsuarios: (empresaId: Id) => ['controlid-usuarios', empresaId ?? null] as const,
  pontoDia: (empresaId: Id, data: string) => ['ponto-dia', empresaId ?? null, data] as const,
  espelho: (funcionarioId: Id, inicio: string, fim: string) => ['espelho', funcionarioId ?? null, inicio, fim] as const,
  alarmes: (empresaId: Id, filtros: Record<string, unknown> = {}) => ['alarmes', empresaId ?? null, filtros] as const,
  bancoHoras: (empresaId: Id, ate: string | null) => ['banco-horas', empresaId ?? null, ate] as const,
  extrato: (funcionarioId: Id, inicio: string, fim: string) => ['extrato', funcionarioId ?? null, inicio, fim] as const,
  vendas: (empresaId: Id, tipo: string, inicio: string, fim: string, loja: string | null) =>
    ['vendas', empresaId ?? null, tipo, inicio, fim, loja] as const,
  comissoes: (empresaId: Id) => ['comissoes', empresaId ?? null] as const,
  fechamento: (id: Id) => ['fechamento', id ?? null] as const,
  comissaoDetalhe: (id: Id) => ['fechamento', id ?? null, 'detalhe'] as const,
  tarefas: (empresaId: Id, data: string) => ['tarefas', empresaId ?? null, data] as const,
  rotinas: (empresaId: Id) => ['rotinas', empresaId ?? null] as const,
  integracoes: (empresaId: Id) => ['integracoes', empresaId ?? null] as const,
  sync: (empresaId: Id) => ['sync', empresaId ?? null] as const,
  usuarios: (empresaId: Id) => ['usuarios', empresaId ?? null] as const,
  empresas: () => ['empresas'] as const,
  // adendo extras / ocorrências / reservas
  ocorrencias: (funcionarioId: Id) => ['ocorrencias', funcionarioId ?? null] as const,
  ocorrenciasContagem: (empresaId: Id) => ['ocorrencias-contagem', empresaId ?? null] as const,
  extras: (empresaId: Id, incluirInativos: boolean) => ['extras', empresaId ?? null, incluirInativos] as const,
  diarias: (empresaId: Id, inicio: string, fim: string, tipo: string | null = null) => ['diarias', empresaId ?? null, inicio, fim, tipo] as const,
  valoresDiaria: (empresaId: Id) => ['valores-diaria', empresaId ?? null] as const,
  gastos: (empresaId: Id, inicio: string, fim: string) => ['gastos', empresaId ?? null, inicio, fim] as const,
  reservas: (empresaId: Id, inicio: string, fim: string) => ['reservas', empresaId ?? null, inicio, fim] as const,
  // adendo escala
  escalaMes: (empresaId: Id, anoMes: string) => ['escala-mes', empresaId ?? null, anoMes] as const,
  escalaSemana: (empresaId: Id, data: string | null) => ['escala-semana', empresaId ?? null, data] as const,
  // adendo extras v3 (§E.7)
  faltas: (empresaId: Id, inicio: string, fim: string, funcionarioId: string | null = null) =>
    ['faltas', empresaId ?? null, inicio, fim, funcionarioId] as const,
} as const

/** Prefixos (1º elemento) para invalidar todas as variações de uma família. */
export type FamiliaConsulta =
  | 'painel'
  | 'funcionarios'
  | 'funcionario'
  | 'jornadas'
  | 'controlid-usuarios'
  | 'ponto-dia'
  | 'espelho'
  | 'alarmes'
  | 'banco-horas'
  | 'extrato'
  | 'vendas'
  | 'comissoes'
  | 'fechamento'
  | 'tarefas'
  | 'rotinas'
  | 'integracoes'
  | 'sync'
  | 'usuarios'
  | 'empresas'
  | 'ocorrencias'
  | 'ocorrencias-contagem'
  | 'extras'
  | 'diarias'
  | 'valores-diaria'
  | 'gastos'
  | 'reservas'
  | 'escala-mes'
  | 'escala-semana'
  | 'faltas'

/** Invalida famílias inteiras (qualquer empresa/parâmetro). */
export function invalidar(qc: QueryClient, ...familias: FamiliaConsulta[]): Promise<void> {
  return Promise.all(familias.map((f) => qc.invalidateQueries({ queryKey: [f] }))).then(() => undefined)
}

/** §14.8: toda mutação de ponto invalida painel, ponto-dia, espelho, alarmes, banco-horas (e extrato). */
export function invalidarPonto(qc: QueryClient): Promise<void> {
  return invalidar(qc, 'painel', 'ponto-dia', 'espelho', 'alarmes', 'banco-horas', 'extrato')
}

/** §14.8: toda mutação de tarefas invalida painel e tarefas. */
export function invalidarTarefas(qc: QueryClient): Promise<void> {
  return invalidar(qc, 'painel', 'tarefas', 'rotinas')
}

/** Mensagem que `mensagemDeErro` (lib/supabase) devolve para JWT expirado/inválido. */
export const MENSAGEM_SESSAO_EXPIRADA = 'Sua sessão expirou. Entre novamente.'

function ehSessaoExpirada(erro: unknown): boolean {
  return erro instanceof Error && erro.message === MENSAGEM_SESSAO_EXPIRADA
}

/**
 * Sessão expirada (ex.: aba aberta muito tempo, sem renovação automática): tenta renovar o token uma vez e
 * repetir as consultas; se não der, encerra a sessão — o `onAuthStateChange` leva o usuário para o login
 * em vez de deixar a tela presa em "Sua sessão expirou".
 */
let renovacao: Promise<void> | null = null
function tratarSessaoExpirada(qc: QueryClient): void {
  if (renovacao) return
  renovacao = supabase.auth
    .refreshSession()
    .then(async ({ error }) => {
      if (error) await supabase.auth.signOut()
      else await qc.invalidateQueries()
    })
    .catch(() => supabase.auth.signOut().then(() => undefined))
    .finally(() => {
      renovacao = null
    })
}

/** Cliente único do app (montado em main.tsx). */
export function criarClienteConsultas(): QueryClient {
  const qc: QueryClient = new QueryClient({
    queryCache: new QueryCache({ onError: (erro) => ehSessaoExpirada(erro) && tratarSessaoExpirada(qc) }),
    mutationCache: new MutationCache({ onError: (erro) => ehSessaoExpirada(erro) && tratarSessaoExpirada(qc) }),
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        refetchOnWindowFocus: true,
        retry: (tentativas, erro) => {
          const codigo = (erro as { codigo?: string | null } | null)?.codigo
          if (codigo === '42501' || codigo === 'P0002' || codigo === '22023') return false
          if (ehSessaoExpirada(erro)) return false
          return tentativas < 2
        },
      },
      mutations: { retry: false },
    },
  })
  return qc
}
