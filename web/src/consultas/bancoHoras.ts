/**
 * Banco de horas (contrato §7.5, §10.4). Dono: frontend-2.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { TipoLancamento } from '@/tipos/banco'
import { chamarRpc } from '@/lib/supabase'
import { chaves, invalidarPonto } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

/** Resumo por funcionário até `ate` (null = ontem, padrão do banco). */
export function useBancoHorasResumo(ate: string | null) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.bancoHoras(empresaId, ate),
    enabled: !!empresaId,
    queryFn: async () => {
      const linhas = (await chamarRpc('banco_horas_resumo', { p_ate: ate, p_empresa: empresaId })) ?? []
      // bigint pode vir como string pelo PostgREST
      return linhas.map((l) => ({ ...l, saldo_minutos: Number(l.saldo_minutos), saldo_mes_minutos: Number(l.saldo_mes_minutos) }))
    },
  })
}

export function useExtrato(funcionarioId: string | null | undefined, inicio: string, fim: string) {
  return useQuery({
    queryKey: chaves.extrato(funcionarioId, inicio, fim),
    enabled: !!funcionarioId,
    queryFn: async () => {
      const linhas = (await chamarRpc('banco_horas_extrato', { p_funcionario: funcionarioId as string, p_inicio: inicio, p_fim: fim })) ?? []
      return linhas.map((l) => ({ ...l, minutos: Number(l.minutos), saldo_acumulado: Number(l.saldo_acumulado) }))
    },
  })
}

export function useLancarBancoHoras() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { funcionarioId: string; data: string; tipo: TipoLancamento; minutos: number; motivo: string }) =>
      chamarRpc('banco_horas_lancar', {
        p_funcionario: a.funcionarioId,
        p_data: a.data,
        p_tipo: a.tipo,
        p_minutos: a.minutos,
        p_motivo: a.motivo,
      }),
    onSuccess: () => invalidarPonto(qc),
  })
}

export function useExcluirLancamento() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => chamarRpc('banco_horas_excluir_lancamento', { p_lancamento: id }),
    onSuccess: () => invalidarPonto(qc),
  })
}
