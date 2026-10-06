/**
 * Query keys do react-query (contrato §14.8) + cliente e invalidações compartilhadas. Dono: frontend-1.
 * Use SEMPRE `chaves.x(...)` — nunca monte o array à mão.
 */
import { QueryClient } from '@tanstack/react-query'

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
  tarefas: (empresaId: Id, data: string) => ['tarefas', empresaId ?? null, data] as const,
  rotinas: (empresaId: Id) => ['rotinas', empresaId ?? null] as const,
  integracoes: (empresaId: Id) => ['integracoes', empresaId ?? null] as const,
  sync: (empresaId: Id) => ['sync', empresaId ?? null] as const,
  usuarios: (empresaId: Id) => ['usuarios', empresaId ?? null] as const,
  empresas: () => ['empresas'] as const,
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

/** Cliente único do app (montado em main.tsx). */
export function criarClienteConsultas(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        refetchOnWindowFocus: true,
        retry: (tentativas, erro) => {
          const codigo = (erro as { codigo?: string | null } | null)?.codigo
          if (codigo === '42501' || codigo === 'P0002' || codigo === '22023') return false
          return tentativas < 2
        },
      },
      mutations: { retry: false },
    },
  })
}
