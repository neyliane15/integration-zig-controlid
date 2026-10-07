/**
 * Usuários (perfis) da empresa e RPCs administrativas (contrato §10.1). Dono: frontend-1.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Papel, Perfil } from '@/tipos/banco'
import { chaves, invalidar } from '@/lib/consultas'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'

export function useUsuarios(empresaId: string | null) {
  return useQuery({
    queryKey: chaves.usuarios(empresaId),
    queryFn: async () => exigir(await supabase.from('perfis').select('*').eq('empresa_id', empresaId!).order('nome')) as Perfil[],
    enabled: empresaId != null,
  })
}

/** Funcionários ativos (id, nome) para vincular ao usuário. */
export function useFuncionariosParaVinculo(empresaId: string | null) {
  return useQuery({
    queryKey: [...chaves.usuarios(empresaId), 'funcionarios'],
    queryFn: async () =>
      exigir(await supabase.from('funcionarios').select('id, nome, cargo').eq('empresa_id', empresaId!).eq('ativo', true).order('nome')) as {
        id: string
        nome: string
        cargo: string | null
      }[],
    enabled: empresaId != null,
  })
}

function useDepois() {
  const qc = useQueryClient()
  return () => invalidar(qc, 'usuarios')
}

export function useCriarUsuario() {
  const depois = useDepois()
  return useMutation({
    mutationFn: (a: { email: string; senha: string; nome: string; papel: Papel; empresaId: string; funcionarioId: string | null }) =>
      chamarRpc('admin_criar_usuario', {
        p_email: a.email,
        p_senha: a.senha,
        p_nome: a.nome,
        p_papel: a.papel,
        p_empresa_id: a.empresaId,
        p_funcionario_id: a.funcionarioId,
      }),
    onSuccess: depois,
  })
}

export function useAtualizarUsuario() {
  const depois = useDepois()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { id: string; nome: string; papel: Papel; ativo: boolean; funcionarioId: string | null }) =>
      chamarRpc('admin_atualizar_usuario', {
        p_usuario: a.id,
        p_nome: a.nome,
        p_papel: a.papel,
        p_ativo: a.ativo,
        p_funcionario_id: a.funcionarioId,
      }),
    onSuccess: () => Promise.all([depois(), qc.invalidateQueries({ queryKey: ['perfil'] })]),
  })
}

export function useRedefinirSenha() {
  return useMutation({
    mutationFn: (a: { id: string; senha: string }) => chamarRpc('admin_redefinir_senha', { p_usuario: a.id, p_senha: a.senha }),
  })
}

export function useExcluirUsuario() {
  const depois = useDepois()
  return useMutation({
    mutationFn: (id: string) => chamarRpc('admin_excluir_usuario', { p_usuario: id }),
    onSuccess: depois,
  })
}

export function useAtualizarMeuPerfil() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (nome: string) => chamarRpc('atualizar_meu_perfil', { p_nome: nome }),
    onSuccess: () => Promise.all([qc.invalidateQueries({ queryKey: ['perfil'] }), invalidar(qc, 'usuarios')]),
  })
}
