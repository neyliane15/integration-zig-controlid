/**
 * Fechamentos de comissão (contrato §9, §10.6). Dono: frontend-2.
 * Leitura direta de comissao_fechamentos/comissao_itens (RLS G A M); escrita só por RPC.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ComissaoDetalhe, ComissaoFechamento, ComissaoItem, ModoRateio } from '@/tipos/banco'
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
    modo_rateio: f.modo_rateio ?? 'periodo',
    dias_sem_presenca: num(f.dias_sem_presenca),
    dias_sem_participantes: num(f.dias_sem_participantes),
  }
}

function normalizarItem(i: ComissaoItem): ComissaoItem {
  return {
    ...i,
    tipo: i.tipo ?? 'funcionario',
    pontos: num(i.pontos),
    pontos_efetivos: num(i.pontos_efetivos),
    valor_centavos: num(i.valor_centavos),
    dias_presentes: num(i.dias_presentes ?? i.dias_trabalhados),
  }
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

/**
 * `comissao_detalhe` (adendo E.3.4): serviço por dia, rateio de cada dia e a entrada da prévia (presença e pontos por dia).
 * Itens na ordem do banco (nome `collate "C"`, tipo, id).
 */
export function useComissaoDetalhe(id: string | null | undefined) {
  return useQuery({
    queryKey: chaves.comissaoDetalhe(id),
    enabled: !!id,
    queryFn: async (): Promise<ComissaoDetalhe> => {
      const d = await chamarRpc('comissao_detalhe', { p_fechamento: id as string })
      return {
        fechamento: normalizarFechamento(d.fechamento),
        servico_dias: (d.servico_dias ?? []).map((x) => ({ data: x.data, servico_zig_centavos: num(x.servico_zig_centavos) })),
        dias: (d.dias ?? []).map((x) => ({
          ...x,
          servico_zig_centavos: num(x.servico_zig_centavos),
          ajuste_centavos: num(x.ajuste_centavos),
          servico_bruto_centavos: num(x.servico_bruto_centavos),
          retencao_centavos: num(x.retencao_centavos),
          base_centavos: num(x.base_centavos),
          soma_pontos: num(x.soma_pontos),
          participantes: num(x.participantes),
          rateio: (x.rateio ?? []).map((r) => ({ ...r, pontos: num(r.pontos), valor_centavos: num(r.valor_centavos) })),
        })),
        itens: (d.itens ?? []).map((i) => ({
          ...i,
          pontos: num(i.pontos),
          dias_presentes: num(i.dias_presentes),
          pontos_efetivos: num(i.pontos_efetivos),
          valor_centavos: num(i.valor_centavos),
          entrada: (i.entrada ?? []).map((l) => ({ data: l.data, presente: !!l.presente, pontos: num(l.pontos) })),
        })),
      }
    },
  })
}

function useMutacaoComissao<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'comissoes', 'fechamento') })
}

export function useCriarFechamento() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoComissao((a: { inicio: string; fim: string; titulo: string | null; loja: string | null; proporcional: boolean; modo: ModoRateio }) =>
    chamarRpc('comissao_criar_fechamento', {
      p_data_inicio: a.inicio,
      p_data_fim: a.fim,
      p_titulo: a.titulo,
      p_loja: a.loja,
      p_proporcional_dias: a.proporcional,
      p_empresa: empresaId,
      p_modo_rateio: a.modo,
    }),
  )
}

export function useAtualizarFechamento() {
  return useMutacaoComissao(
    (a: { id: string; titulo: string; ajuste: number; percentual: number; proporcional: boolean; observacoes: string | null; modo: ModoRateio }) =>
      chamarRpc('comissao_atualizar_fechamento', {
        p_fechamento: a.id,
        p_titulo: a.titulo,
        p_servico_ajuste_centavos: a.ajuste,
        p_percentual_retencao: a.percentual,
        p_proporcional_dias: a.proporcional,
        p_observacoes: a.observacoes,
        p_modo_rateio: a.modo,
      }),
  )
}

/** Grava vários itens em sequência (o banco recalcula a cada chamada). `pontos: null` = automático (vigentes de cada dia). */
export function useDefinirItens() {
  return useMutacaoComissao(async (a: { id: string; itens: { funcionarioId: string; pontos: number | null; incluido: boolean }[] }) => {
    for (const i of a.itens) {
      await chamarRpc('comissao_definir_item', { p_fechamento: a.id, p_funcionario: i.funcionarioId, p_pontos: i.pontos, p_incluido: i.incluido })
    }
  })
}

/** Inclui/tira um extra do fechamento (adendo E.3.4). */
export function useDefinirExtra() {
  return useMutacaoComissao((a: { id: string; extraId: string; incluido: boolean }) =>
    chamarRpc('comissao_definir_extra', { p_fechamento: a.id, p_extra: a.extraId, p_incluido: a.incluido }),
  )
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
  const qc = useQueryClient()
  // não invalida o detalhe do próprio fechamento (a página ainda montada o buscaria de novo → "Fechamento não encontrado")
  return useMutation({
    mutationFn: (id: string) => chamarRpc('comissao_excluir_rascunho', { p_fechamento: id }),
    onSuccess: (_r, id) => {
      qc.removeQueries({ queryKey: chaves.fechamento(id), exact: false, type: 'inactive' })
      return invalidar(qc, 'comissoes', 'gastos')
    },
  })
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
