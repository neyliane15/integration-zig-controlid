/**
 * Extras (adendo E): pontos extras de comissão, diárias (com valor padrão por funcionário) e gastos do período.
 * Tudo por RPC (G A M).
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Diaria, GastosPeriodo, PontoExtra } from '@/tipos/banco'
import { chamarRpc } from '@/lib/supabase'
import { chaves, invalidar } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

export { lerPontosExtras, totaisDiarias } from '@/lib/extras'

const num = (v: unknown) => Number(v) || 0

// ------------------------------------------------------------ pontos extras
export function usePontosExtras(inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.pontosExtras(empresaId, inicio, fim),
    enabled: !!empresaId && !!inicio && !!fim && inicio <= fim,
    queryFn: async () =>
      ((await chamarRpc('comissao_extras_listar', { p_inicio: inicio, p_fim: fim, p_empresa: empresaId })) ?? []).map<PontoExtra>((l) => ({
        ...l,
        pontos: num(l.pontos),
      })),
  })
}

function useMutacaoExtras<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  // extras mudam o cálculo dos rascunhos (após recalcular) e os gastos previstos
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'pontos-extras', 'gastos', 'comissoes', 'fechamento') })
}

export function useLancarPontoExtra() {
  return useMutacaoExtras((a: { funcionarioId: string; data: string; pontos: number; motivo: string }) =>
    chamarRpc('comissao_extra_lancar', { p_funcionario: a.funcionarioId, p_data: a.data, p_pontos: a.pontos, p_motivo: a.motivo }),
  )
}

export function useExcluirPontoExtra() {
  return useMutacaoExtras((id: string) => chamarRpc('comissao_extra_excluir', { p_extra: id }))
}

// -------------------------------------------------------------------- diárias
export function useValoresDiaria(habilitado = true) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.valoresDiaria(empresaId),
    enabled: !!empresaId && habilitado,
    queryFn: async () => {
      const linhas = (await chamarRpc('funcionario_valores_diaria_listar', { p_empresa: empresaId })) ?? []
      return new Map(linhas.map((l) => [l.funcionario_id, num(l.valor_diaria_centavos)]))
    },
  })
}

export function useDefinirValorDiaria() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { funcionarioId: string; centavos: number | null }) =>
      chamarRpc('funcionario_definir_valor_diaria', { p_funcionario: a.funcionarioId, p_valor_centavos: a.centavos }),
    onSuccess: () => invalidar(qc, 'valores-diaria'),
  })
}

export function useDiarias(inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.diarias(empresaId, inicio, fim),
    enabled: !!empresaId && !!inicio && !!fim && inicio <= fim,
    queryFn: async () =>
      ((await chamarRpc('diarias_listar', { p_inicio: inicio, p_fim: fim, p_empresa: empresaId })) ?? []).map<Diaria>((d) => ({
        ...d,
        valor_centavos: num(d.valor_centavos),
      })),
  })
}

function useMutacaoDiaria<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'diarias', 'gastos') })
}

export interface DadosDiaria {
  data: string
  funcionarioId: string | null
  pessoaNome: string | null
  funcao: string | null
  valorCentavos: number | null
  observacao: string | null
  pago: boolean
  pagoEm: string | null
}

export function useSalvarDiaria() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoDiaria(async (a: { id?: string | null; dados: DadosDiaria }) => {
    const d = a.dados
    if (a.id) {
      await chamarRpc('diaria_atualizar', {
        p_diaria: a.id,
        p_data: d.data,
        p_funcionario: d.funcionarioId,
        p_pessoa_nome: d.pessoaNome,
        p_funcao: d.funcao,
        p_valor_centavos: d.valorCentavos,
        p_observacao: d.observacao,
        p_pago: d.pago,
        p_pago_em: d.pago ? d.pagoEm : null,
      })
      return a.id
    }
    return chamarRpc('diaria_lancar', {
      p_data: d.data,
      p_funcionario: d.funcionarioId,
      p_pessoa_nome: d.pessoaNome,
      p_funcao: d.funcao,
      p_valor_centavos: d.valorCentavos,
      p_observacao: d.observacao,
      p_pago: d.pago,
      p_pago_em: d.pago ? d.pagoEm : null,
      p_empresa: empresaId,
    })
  })
}

export function useMarcarDiariaPaga() {
  return useMutacaoDiaria((a: { id: string; pago: boolean; pagoEm?: string | null }) =>
    chamarRpc('diaria_marcar_paga', { p_diaria: a.id, p_pago: a.pago, p_pago_em: a.pago ? (a.pagoEm ?? null) : null }),
  )
}

export function useExcluirDiaria() {
  return useMutacaoDiaria((id: string) => chamarRpc('diaria_excluir', { p_diaria: id }))
}

// ---------------------------------------------------------------- gastos
const CAMPOS_DINHEIRO = ['diarias_pagas', 'diarias_a_pagar', 'comissoes_fechadas', 'comissoes_previstas', 'total'] as const

export function useGastosPeriodo(inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.gastos(empresaId, inicio, fim),
    enabled: !!empresaId && !!inicio && !!fim && inicio <= fim,
    queryFn: async (): Promise<GastosPeriodo> => {
      const g = await chamarRpc('gastos_periodo', { p_inicio: inicio, p_fim: fim, p_empresa: empresaId })
      const normal = <T extends object>(o: T): T => {
        const r: Record<string, unknown> = { ...(o as Record<string, unknown>) }
        for (const c of CAMPOS_DINHEIRO) if (c in r) r[c] = num(r[c])
        return r as T
      }
      return {
        ...g,
        totais: {
          diarias_pagas: num(g.totais.diarias_pagas),
          diarias_a_pagar: num(g.totais.diarias_a_pagar),
          diarias: num(g.totais.diarias),
          diarias_qtd: num(g.totais.diarias_qtd),
          comissoes_fechadas: num(g.totais.comissoes_fechadas),
          comissoes_previstas: num(g.totais.comissoes_previstas),
          total: num(g.totais.total),
          total_com_previsto: num(g.totais.total_com_previsto),
        },
        por_pessoa: (g.por_pessoa ?? []).map((p) => ({ ...normal(p), diarias_qtd: num(p.diarias_qtd) })),
        por_dia: (g.por_dia ?? []).map(normal),
        fechamentos: (g.fechamentos ?? []).map((f) => ({ ...f, base_distribuivel_centavos: num(f.base_distribuivel_centavos) })),
      }
    },
  })
}
