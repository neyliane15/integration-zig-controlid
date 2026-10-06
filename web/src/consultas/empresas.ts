/**
 * Consultas de empresas (master e configurações). Dono: frontend-1.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Empresa } from '@/tipos/banco'
import { chaves, invalidar } from '@/lib/consultas'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'

/** Lista (master: todas; demais: a própria, pela RLS). */
export function useEmpresas(habilitado = true) {
  return useQuery({
    queryKey: chaves.empresas(),
    queryFn: async () => exigir(await supabase.from('empresas').select('*').order('nome')) as Empresa[],
    enabled: habilitado,
  })
}

export function useEmpresa(id: string | null | undefined) {
  return useQuery({
    queryKey: ['empresa', id ?? null],
    queryFn: async () => exigir(await supabase.from('empresas').select('*').eq('id', id!).maybeSingle<Empresa>()),
    enabled: !!id,
  })
}

export type DadosEmpresa = Partial<
  Pick<
    Empresa,
    | 'nome'
    | 'cnpj'
    | 'telefone'
    | 'cidade'
    | 'uf'
    | 'fuso'
    | 'virada_dia'
    | 'comissao_percentual_retencao'
    | 'ponto_alarme_atraso'
    | 'ponto_janela_duplicada_minutos'
    | 'ativa'
  >
>

function useInvalidarEmpresas() {
  const qc = useQueryClient()
  return () =>
    Promise.all([invalidar(qc, 'empresas', 'painel'), qc.invalidateQueries({ queryKey: ['empresa'] })]).then(() => undefined)
}

export function useAtualizarEmpresa() {
  const depois = useInvalidarEmpresas()
  return useMutation({
    mutationFn: async ({ id, dados }: { id: string; dados: DadosEmpresa }) => {
      const r = await supabase.from('empresas').update(dados).eq('id', id).select('id')
      const linhas = exigir(r) as { id: string }[]
      if (linhas.length === 0) throw new Error('Sem permissão')
    },
    onSuccess: depois,
  })
}

export function useCriarEmpresaMaster() {
  const depois = useInvalidarEmpresas()
  return useMutation({
    mutationFn: (a: { nome: string; cnpj: string | null; adminEmail: string; adminSenha: string; adminNome: string }) =>
      chamarRpc('master_criar_empresa', {
        p_nome: a.nome,
        p_cnpj: a.cnpj,
        p_admin_email: a.adminEmail,
        p_admin_senha: a.adminSenha,
        p_admin_nome: a.adminNome,
      }),
    onSuccess: depois,
  })
}

export function useExcluirEmpresa() {
  const depois = useInvalidarEmpresas()
  return useMutation({
    mutationFn: async (id: string) => {
      const linhas = exigir(await supabase.from('empresas').delete().eq('id', id).select('id')) as { id: string }[]
      if (linhas.length === 0) throw new Error('Sem permissão')
    },
    onSuccess: depois,
  })
}

/** Só dígitos; '' → null. */
export function limparCnpj(s: string): string | null {
  const d = s.replace(/\D/g, '')
  return d === '' ? null : d
}

/** "12345678000190" → "12.345.678/0001-90". */
export function formatarCnpj(c: string | null | undefined): string {
  if (!c) return '—'
  const d = c.replace(/\D/g, '')
  if (d.length !== 14) return c
  return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`
}
