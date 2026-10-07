/**
 * Consultas e mutações de ponto (contrato §10.4). Dono: frontend-2.
 * Toda mutação invalida painel, ponto-dia, espelho, alarmes, banco-horas (§14.8).
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { PontoAbono, PontoAjuste, PontoAlarme, StatusAlarme, TipoAbono, TipoAlarme } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidarPonto } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

export function usePontoDia(data: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.pontoDia(empresaId, data),
    enabled: !!empresaId && !!data,
    queryFn: async () => (await chamarRpc('ponto_dia_empresa', { p_data: data, p_empresa: empresaId })) ?? [],
  })
}

export function useEspelho(funcionarioId: string | null | undefined, inicio: string, fim: string) {
  return useQuery({
    queryKey: chaves.espelho(funcionarioId, inicio, fim),
    enabled: !!funcionarioId,
    queryFn: async () => (await chamarRpc('ponto_espelho', { p_funcionario: funcionarioId as string, p_inicio: inicio, p_fim: fim })) ?? [],
  })
}

/** Abonos do funcionário (e da empresa toda) no período — para "remover abono" no espelho. */
export function useAbonos(funcionarioId: string | null | undefined, inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: [...chaves.espelho(funcionarioId, inicio, fim), 'abonos'],
    enabled: !!funcionarioId && !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('ponto_abonos')
          .select('*')
          .eq('empresa_id', empresaId as string)
          .or(`funcionario_id.eq.${funcionarioId},funcionario_id.is.null`)
          .gte('data', inicio)
          .lte('data', fim)
          .order('data'),
      ) as PontoAbono[],
  })
}

/** Ajustes manuais (auditoria) do funcionário no período. */
export function useAjustes(funcionarioId: string | null | undefined, inicio: string, fim: string) {
  return useQuery({
    queryKey: [...chaves.espelho(funcionarioId, inicio, fim), 'ajustes'],
    enabled: !!funcionarioId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('ponto_ajustes')
          .select('*')
          .eq('funcionario_id', funcionarioId as string)
          .gte('feito_em', `${inicio}T00:00:00`)
          .order('feito_em', { ascending: false })
          .limit(200),
      ) as PontoAjuste[],
  })
}

export interface FiltrosAlarmes {
  status: StatusAlarme | 'todos'
  tipo: TipoAlarme | 'todos'
  funcionarioId: string | null
  inicio: string
  fim: string
}

export type AlarmeComFuncionario = PontoAlarme & { funcionarios: { nome: string; cargo: string | null } | null }

export function useAlarmes(filtros: FiltrosAlarmes) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.alarmes(empresaId, { ...filtros }),
    enabled: !!empresaId,
    queryFn: async () => {
      let q = supabase
        .from('ponto_alarmes')
        .select('*, funcionarios(nome, cargo)')
        .eq('empresa_id', empresaId as string)
        .gte('data', filtros.inicio)
        .lte('data', filtros.fim)
      if (filtros.status !== 'todos') q = q.eq('status', filtros.status)
      if (filtros.tipo !== 'todos') q = q.eq('tipo', filtros.tipo)
      if (filtros.funcionarioId) q = q.eq('funcionario_id', filtros.funcionarioId)
      return exigir(await q.order('data', { ascending: false }).order('criado_em', { ascending: false }).limit(1000)) as AlarmeComFuncionario[]
    },
  })
}

function useMutacaoPonto<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidarPonto(qc) })
}

export function useIncluirBatida() {
  return useMutacaoPonto((a: { funcionarioId: string; instante: string; motivo: string }) =>
    chamarRpc('ponto_incluir_batida', { p_funcionario: a.funcionarioId, p_instante: a.instante, p_motivo: a.motivo }),
  )
}

export function useDesconsiderarBatida() {
  return useMutacaoPonto((a: { batidaId: string; motivo: string }) =>
    chamarRpc('ponto_desconsiderar_batida', { p_batida: a.batidaId, p_motivo: a.motivo }),
  )
}

export function useRestaurarBatida() {
  return useMutacaoPonto((a: { batidaId: string; motivo: string }) =>
    chamarRpc('ponto_restaurar_batida', { p_batida: a.batidaId, p_motivo: a.motivo }),
  )
}

/** Editar batida = desconsiderar a antiga + incluir a nova (§7.7). */
export function useEditarBatida() {
  return useMutacaoPonto(async (a: { batidaId: string; funcionarioId: string; instante: string; motivo: string }) => {
    await chamarRpc('ponto_desconsiderar_batida', { p_batida: a.batidaId, p_motivo: a.motivo })
    return chamarRpc('ponto_incluir_batida', { p_funcionario: a.funcionarioId, p_instante: a.instante, p_motivo: a.motivo })
  })
}

/** Justifica um ou vários alarmes (lote = várias chamadas). Retorna quantos deram certo e os erros. */
export function useJustificarAlarmes() {
  return useMutacaoPonto(async (a: { ids: string[]; justificativa: string }) => {
    const resultados = await Promise.allSettled(
      a.ids.map((id) => chamarRpc('ponto_justificar_alarme', { p_alarme: id, p_justificativa: a.justificativa })),
    )
    const erros = resultados.filter((r): r is PromiseRejectedResult => r.status === 'rejected').map((r) => r.reason as unknown)
    const ok = resultados.length - erros.length
    if (ok === 0 && erros.length) throw erros[0]
    return { ok, erros }
  })
}

export function useReabrirAlarme() {
  return useMutacaoPonto((id: string) => chamarRpc('ponto_reabrir_alarme', { p_alarme: id }))
}

export function useAbonar() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoPonto((a: { inicio: string; fim: string; tipo: TipoAbono; motivo: string | null; funcionarioId: string | null }) =>
    chamarRpc('ponto_abonar', {
      p_inicio: a.inicio,
      p_fim: a.fim,
      p_tipo: a.tipo,
      p_motivo: a.motivo,
      p_funcionario: a.funcionarioId,
      p_empresa: empresaId,
    }),
  )
}

export function useRemoverAbono() {
  return useMutacaoPonto((id: string) => chamarRpc('ponto_remover_abono', { p_abono: id }))
}

export function useReapurar() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoPonto((a: { inicio: string; fim: string; funcionarioId?: string | null }) =>
    chamarRpc('ponto_reapurar', { p_inicio: a.inicio, p_fim: a.fim, p_funcionario: a.funcionarioId ?? null, p_empresa: empresaId }),
  )
}
