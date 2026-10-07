/**
 * Tarefas do dia e rotinas (contrato §5, §10.3). Dono: frontend-2.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Prioridade, Recorrencia, StatusTarefa, Tarefa, TarefaItem, TarefaRotina, TarefaRotinaItem } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidarTarefas } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

export type TarefaComItens = Tarefa & { tarefa_itens: TarefaItem[] }
export type RotinaComItens = TarefaRotina & { tarefas_rotina_itens: TarefaRotinaItem[] }

/** Tarefas do dia. Para o dia de trabalho atual (ou futuro), materializa as rotinas antes (`tarefas_gerar_do_dia`). */
export function useTarefas(data: string, hoje: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.tarefas(empresaId, data),
    enabled: !!empresaId && !!data,
    queryFn: async () => {
      if (data >= hoje) {
        try {
          await chamarRpc('tarefas_gerar_do_dia', { p_data: data, p_empresa: empresaId })
        } catch {
          /* gerar é conveniência: a lista continua mesmo se falhar */
        }
      }
      const lista = exigir(
        await supabase
          .from('tarefas')
          .select('*, tarefa_itens(*)')
          .eq('empresa_id', empresaId as string)
          .eq('data', data),
      ) as TarefaComItens[]
      for (const t of lista) t.tarefa_itens.sort((a, b) => a.ordem - b.ordem)
      return lista
    },
  })
}

export function useMudarStatusTarefa() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { id: string; status: StatusTarefa }) => chamarRpc('tarefa_mudar_status', { p_tarefa: a.id, p_status: a.status }),
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useMarcarItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { id: string; feito: boolean }) => chamarRpc('tarefa_marcar_item', { p_item: a.id, p_feito: a.feito }),
    onSuccess: () => invalidarTarefas(qc),
  })
}

export interface DadosTarefa {
  id?: string | null
  data: string
  titulo: string
  descricao: string | null
  horario_limite: string | null
  prioridade: Prioridade
  responsavel_funcionario_id: string | null
  responsavel_perfil_id: string | null
  /** só na criação */
  itens?: string[]
}

export function useSalvarTarefa() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async ({ id, itens, ...campos }: DadosTarefa) => {
      if (id) {
        exigir(await supabase.from('tarefas').update(campos).eq('id', id).select('id').single())
        return id
      }
      const r = exigir(
        await supabase
          .from('tarefas')
          .insert({ ...campos, empresa_id: empresaId })
          .select('id')
          .single(),
      ) as { id: string }
      if (itens?.length) {
        exigir(await supabase.from('tarefa_itens').insert(itens.map((texto, ordem) => ({ tarefa_id: r.id, empresa_id: empresaId, ordem, texto }))))
      }
      return r.id
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useAdicionarItemTarefa() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async (a: { tarefaId: string; texto: string; ordem: number }) => {
      exigir(await supabase.from('tarefa_itens').insert({ tarefa_id: a.tarefaId, empresa_id: empresaId, ordem: a.ordem, texto: a.texto }))
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useRemoverItemTarefa() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      exigir(await supabase.from('tarefa_itens').delete().eq('id', id))
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useExcluirTarefa() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      exigir(await supabase.from('tarefas').delete().eq('id', id))
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

// ---------------------------------------------------------------- rotinas
export function useRotinas() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.rotinas(empresaId),
    enabled: !!empresaId,
    queryFn: async () => {
      const lista = exigir(
        await supabase
          .from('tarefas_rotinas')
          .select('*, tarefas_rotina_itens(*)')
          .eq('empresa_id', empresaId as string)
          .order('titulo'),
      ) as RotinaComItens[]
      for (const r of lista) r.tarefas_rotina_itens.sort((a, b) => a.ordem - b.ordem)
      return lista
    },
  })
}

export interface DadosRotina {
  id?: string | null
  titulo: string
  descricao: string | null
  recorrencia: Recorrencia
  dias_semana: number[]
  dia_mes: number | null
  horario_limite: string | null
  prioridade: Prioridade
  responsavel_funcionario_id: string | null
  responsavel_perfil_id: string | null
  ativa: boolean
  itens: string[]
}

export function useSalvarRotina() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async ({ id, itens, ...campos }: DadosRotina) => {
      const dados = {
        ...campos,
        dias_semana: campos.recorrencia === 'semanal' ? campos.dias_semana : [],
        dia_mes: campos.recorrencia === 'mensal' ? campos.dia_mes : null,
      }
      let rotinaId = id ?? null
      if (rotinaId) {
        exigir(await supabase.from('tarefas_rotinas').update(dados).eq('id', rotinaId).select('id').single())
        exigir(await supabase.from('tarefas_rotina_itens').delete().eq('rotina_id', rotinaId))
      } else {
        const r = exigir(
          await supabase
            .from('tarefas_rotinas')
            .insert({ ...dados, empresa_id: empresaId })
            .select('id')
            .single(),
        ) as { id: string }
        rotinaId = r.id
      }
      if (itens.length) {
        exigir(
          await supabase
            .from('tarefas_rotina_itens')
            .insert(itens.map((texto, ordem) => ({ rotina_id: rotinaId, empresa_id: empresaId, ordem, texto }))),
        )
      }
      return rotinaId as string
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useAtivarRotina() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { id: string; ativa: boolean }) => {
      exigir(await supabase.from('tarefas_rotinas').update({ ativa: a.ativa }).eq('id', a.id))
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}

export function useExcluirRotina() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      exigir(await supabase.from('tarefas_rotinas').delete().eq('id', id))
    },
    onSuccess: () => invalidarTarefas(qc),
  })
}
