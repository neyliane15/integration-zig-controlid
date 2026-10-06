/**
 * Fechamentos de comissão (contrato §9, §10.6). Dono: frontend-2.
 * Leitura direta de comissao_fechamentos/comissao_itens (RLS G A M); escrita só por RPC.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ComissaoFechamento, ComissaoItem } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidar } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

const num = (v: unknown) => Number(v) || 0

function normalizarFechamento(f: ComissaoFechamento): ComissaoFechamento {
  return {
    ...f,
    servico_zig_centavos: num(f.servico_zig_centavos),
    servico_ajuste_centavos: num(f.servico_ajuste_centavos),
    servico_bruto_centavos: num(f.servico_bruto_centavos),
    percentual_retencao: num(f.percentual_retencao),
    retencao_centavos: num(f.retencao_centavos),
    base_distribuivel_centavos: num(f.base_distribuivel_centavos),
    soma_pontos_efetivos: num(f.soma_pontos_efetivos),
    valor_ponto_centavos: f.valor_ponto_centavos == null ? null : num(f.valor_ponto_centavos),
  }
}

function normalizarItem(i: ComissaoItem): ComissaoItem {
  return { ...i, pontos: num(i.pontos), pontos_efetivos: num(i.pontos_efetivos), valor_centavos: num(i.valor_centavos) }
}

export type FechamentoNaLista = ComissaoFechamento & { total_itens_centavos: number; participantes: number }

export function useFechamentos() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.comissoes(empresaId),
    enabled: !!empresaId,
    queryFn: async () => {
      const linhas = exigir(
        await supabase
          .from('comissao_fechamentos')
          .select('*, comissao_itens(valor_centavos, incluido)')
          .eq('empresa_id', empresaId as string)
          .order('data_inicio', { ascending: false })
          .order('criado_em', { ascending: false }),
      ) as (ComissaoFechamento & { comissao_itens: { valor_centavos: number; incluido: boolean }[] })[]
      return linhas.map<FechamentoNaLista>(({ comissao_itens, ...f }) => ({
        ...normalizarFechamento(f),
        total_itens_centavos: comissao_itens.reduce((s, i) => s + num(i.valor_centavos), 0),
        participantes: comissao_itens.filter((i) => i.incluido).length,
      }))
    },
  })
}

export function useFechamento(id: string | null | undefined) {
  return useQuery({
    queryKey: chaves.fechamento(id),
    enabled: !!id,
    queryFn: async () => {
      const f = exigir(await supabase.from('comissao_fechamentos').select('*').eq('id', id as string).maybeSingle()) as ComissaoFechamento | null
      if (!f) throw new Error('Fechamento não encontrado')
      const itens = exigir(
        await supabase
          .from('comissao_itens')
          .select('*')
          .eq('fechamento_id', id as string)
          .order('funcionario_nome'),
      ) as ComissaoItem[]
      return { fechamento: normalizarFechamento(f), itens: itens.map(normalizarItem) }
    },
  })
}

function useMutacaoComissao<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'comissoes', 'fechamento') })
}

export function useCriarFechamento() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoComissao((a: { inicio: string; fim: string; titulo: string | null; loja: string | null; proporcional: boolean }) =>
    chamarRpc('comissao_criar_fechamento', {
      p_data_inicio: a.inicio,
      p_data_fim: a.fim,
      p_titulo: a.titulo,
      p_loja: a.loja,
      p_proporcional_dias: a.proporcional,
      p_empresa: empresaId,
    }),
  )
}

export function useAtualizarFechamento() {
  return useMutacaoComissao(
    (a: { id: string; titulo: string; ajuste: number; percentual: number; proporcional: boolean; observacoes: string | null }) =>
      chamarRpc('comissao_atualizar_fechamento', {
        p_fechamento: a.id,
        p_titulo: a.titulo,
        p_servico_ajuste_centavos: a.ajuste,
        p_percentual_retencao: a.percentual,
        p_proporcional_dias: a.proporcional,
        p_observacoes: a.observacoes,
      }),
  )
}

/** Grava vários itens em sequência (o banco recalcula a cada chamada). */
export function useDefinirItens() {
  return useMutacaoComissao(async (a: { id: string; itens: { funcionarioId: string; pontos: number; incluido: boolean }[] }) => {
    for (const i of a.itens) {
      await chamarRpc('comissao_definir_item', { p_fechamento: a.id, p_funcionario: i.funcionarioId, p_pontos: i.pontos, p_incluido: i.incluido })
    }
  })
}

export function useRemoverItem() {
  return useMutacaoComissao((a: { id: string; funcionarioId: string }) =>
    chamarRpc('comissao_remover_item', { p_fechamento: a.id, p_funcionario: a.funcionarioId }),
  )
}

export function useRecalcularFechamento() {
  return useMutacaoComissao((id: string) => chamarRpc('comissao_recalcular', { p_fechamento: id }))
}

export function useFecharComissao() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => chamarRpc('comissao_fechar', { p_fechamento: id }),
    onSuccess: () => invalidar(qc, 'comissoes', 'fechamento', 'painel'),
  })
}

export function useExcluirRascunho() {
  return useMutacaoComissao((id: string) => chamarRpc('comissao_excluir_rascunho', { p_fechamento: id }))
}

/** "Enviar por e-mail": coloca na fila do N8N (escopo exportar_fechamento). */
export function useEnviarFechamentoPorEmail() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: (id: string) =>
      chamarRpc('sync_solicitar', { p_escopo: 'exportar_fechamento', p_parametros: { fechamento_id: id }, p_empresa: empresaId }),
    onSuccess: () => invalidar(qc, 'sync', 'painel'),
  })
}
