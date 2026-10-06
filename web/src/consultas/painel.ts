/**
 * Painel do dia (contrato §10.7 e §14.4). Dono: frontend-1.
 * Ao abrir, chama `tarefas_gerar_do_dia` (idempotente) e depois `painel_do_dia`.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { StatusTarefa, Tarefa } from '@/tipos/banco'
import { chaves, invalidarTarefas } from '@/lib/consultas'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'

export function usePainel(empresaId: string | null) {
  return useQuery({
    queryKey: chaves.painel(empresaId),
    queryFn: async () => {
      try {
        await chamarRpc('tarefas_gerar_do_dia', { p_empresa: empresaId })
      } catch {
        /* gerar tarefas não pode impedir o painel de abrir */
      }
      return chamarRpc('painel_do_dia', { p_empresa: empresaId })
    },
    enabled: empresaId != null,
    // enquanto alguma integração estiver sincronizando, acompanha a cada 5 s (§12.1); senão a cada 1 min
    refetchInterval: (q) => (q.state.data?.sincronizacao.some((s) => s.executando) ? 5_000 : 60_000),
  })
}

export type TarefaPainel = Pick<Tarefa, 'id' | 'titulo' | 'status' | 'prioridade' | 'horario_limite' | 'data'>

const PESO_STATUS: Record<StatusTarefa, number> = { em_andamento: 0, pendente: 1, concluida: 2, cancelada: 3 }
const PESO_PRIORIDADE = { alta: 0, normal: 1, baixa: 2 } as const

/** Lista curta das tarefas do dia para o cartão do painel (chave sob 'painel' para invalidar junto). */
export function useTarefasDoPainel(empresaId: string | null, data: string | null | undefined) {
  return useQuery({
    queryKey: [...chaves.painel(empresaId), 'tarefas', data ?? null],
    queryFn: async () => {
      const linhas = exigir(
        await supabase
          .from('tarefas')
          .select('id, titulo, status, prioridade, horario_limite, data')
          .eq('empresa_id', empresaId!)
          .eq('data', data!)
          .neq('status', 'cancelada'),
      ) as TarefaPainel[]
      return linhas.sort(
        (a, b) =>
          PESO_STATUS[a.status] - PESO_STATUS[b.status] ||
          PESO_PRIORIDADE[a.prioridade] - PESO_PRIORIDADE[b.prioridade] ||
          (a.horario_limite ?? '99').localeCompare(b.horario_limite ?? '99') ||
          a.titulo.localeCompare(b.titulo, 'pt-BR'),
      )
    },
    enabled: empresaId != null && !!data,
  })
}

export function useMudarStatusTarefa() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { tarefa: string; status: StatusTarefa }) => chamarRpc('tarefa_mudar_status', { p_tarefa: a.tarefa, p_status: a.status }),
    onSettled: () => invalidarTarefas(qc),
  })
}
