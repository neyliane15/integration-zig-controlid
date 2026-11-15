/**
 * Extras (adendo E v2): cadastro de freelas/diaristas, dias trabalhados (de extra, com pontos, ou diária de funcionário, só custo),
 * valor padrão de diária do funcionário e gastos do período. Tudo por RPC (G A M).
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Diaria, Extra, ExtraImportacao, GastosPeriodo, TipoDiaria } from '@/tipos/banco'
import { chamarRpc } from '@/lib/supabase'
import { chaves, invalidar } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

export { lerPontos, totaisDiarias } from '@/lib/extras'

const num = (v: unknown) => Number(v) || 0
const numOuNull = (v: unknown) => (v == null ? null : Number(v))

// ------------------------------------------------------------------ cadastro
export function useExtras(incluirInativos = false) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.extras(empresaId, incluirInativos),
    enabled: !!empresaId,
    queryFn: async () =>
      ((await chamarRpc('extras_listar', { p_incluir_inativos: incluirInativos, p_empresa: empresaId })) ?? []).map<Extra>((x) => ({
        ...x,
        pontos_padrao: num(x.pontos_padrao),
        valor_diaria_centavos: numOuNull(x.valor_diaria_centavos),
        pontos_pendente: !!x.pontos_pendente,
        dias_lancados: num(x.dias_lancados),
        dias_pendentes: num(x.dias_pendentes),
      })),
  })
}

export interface DadosExtra {
  nome: string
  funcao: string | null
  /** null = mantém a pontuação pendente (só extra pendente; §E.7.5) */
  pontosPadrao: number | null
  valorDiariaCentavos: number | null
  telefone: string | null
  documento: string | null
  observacoes: string | null
  ativo: boolean
}

function useMutacaoExtra<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'extras', 'diarias', 'gastos') })
}

/** Cria (sem id) ou substitui o cadastro (com id). Retorna o id. */
export function useSalvarExtra() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoExtra(async (a: { id?: string | null; dados: DadosExtra }): Promise<string> => {
    const d = a.dados
    if (a.id) {
      await chamarRpc('extra_atualizar', {
        p_extra: a.id,
        p_nome: d.nome,
        p_funcao: d.funcao,
        p_pontos_padrao: d.pontosPadrao,
        p_valor_diaria_centavos: d.valorDiariaCentavos,
        p_telefone: d.telefone,
        p_documento: d.documento,
        p_ativo: d.ativo,
        p_observacoes: d.observacoes,
      })
      return a.id
    }
    return chamarRpc('extra_criar', {
      p_nome: d.nome,
      p_funcao: d.funcao,
      p_pontos_padrao: d.pontosPadrao ?? 0,
      p_valor_diaria_centavos: d.valorDiariaCentavos,
      p_telefone: d.telefone,
      p_documento: d.documento,
      p_observacoes: d.observacoes,
      p_empresa: empresaId,
    })
  })
}

/** Liga/desliga o cadastro (substitui tudo com os dados atuais). */
export function useAtivarExtra() {
  return useMutacaoExtra((x: { extra: Extra; ativo: boolean }) =>
    chamarRpc('extra_atualizar', {
      p_extra: x.extra.id,
      p_nome: x.extra.nome,
      p_funcao: x.extra.funcao,
      // pendente: null mantém a pendência (0 definiria a pontuação como zero)
      p_pontos_padrao: x.extra.pontos_pendente ? null : x.extra.pontos_padrao,
      p_valor_diaria_centavos: x.extra.valor_diaria_centavos,
      p_telefone: x.extra.telefone,
      p_documento: x.extra.documento,
      p_ativo: x.ativo,
      p_observacoes: x.extra.observacoes,
    }),
  )
}

/** Preenche a pontuação de um extra pendente: grava no cadastro e nos dias pendentes (fora de fechamento fechado). Retorna nº de dias. */
export function useDefinirPontuacao() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { extraId: string; pontos: number }) => chamarRpc('extra_definir_pontuacao', { p_extra: a.extraId, p_pontos: a.pontos }),
    onSuccess: () => invalidar(qc, 'extras', 'diarias', 'gastos', 'comissoes', 'fechamento'),
  })
}

/** Importação em lote (§E.7.6): cada linha é atômica; o retorno traz os erros por linha (índice do item, 1-based). */
export function useImportarExtras() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async (itens: ExtraImportacao[]) => {
      const r = await chamarRpc('extras_importar', { p_itens: itens, p_empresa: empresaId })
      return {
        lidos: num(r.lidos),
        criados: num(r.criados),
        atualizados: num(r.atualizados),
        dias_lancados: num(r.dias_lancados),
        pendentes_pontuacao: num(r.pendentes_pontuacao),
        erros: (r.erros ?? []).map((e) => ({ linha: num(e.linha), mensagem: String(e.mensagem) })),
      }
    },
    onSuccess: () => invalidar(qc, 'extras', 'diarias', 'gastos'),
  })
}

export function useExcluirExtra() {
  return useMutacaoExtra((id: string) => chamarRpc('extra_excluir', { p_extra: id }))
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

export function useDiarias(inicio: string, fim: string, tipo: TipoDiaria | null = null) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.diarias(empresaId, inicio, fim, tipo),
    enabled: !!empresaId && !!inicio && !!fim && inicio <= fim,
    queryFn: async () =>
      ((await chamarRpc('diarias_listar', { p_inicio: inicio, p_fim: fim, p_tipo: tipo, p_empresa: empresaId })) ?? []).map<Diaria>((d) => ({
        ...d,
        pontos: numOuNull(d.pontos),
        pontos_pendente: !!d.pontos_pendente,
        valor_centavos: num(d.valor_centavos),
      })),
  })
}

function useMutacaoDiaria<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  // dias de extra mudam o rateio dos rascunhos (após recalcular) e os gastos
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'diarias', 'extras', 'gastos', 'comissoes', 'fechamento') })
}

export interface DadosDiaria {
  data: string
  /** exatamente um dos dois (só no lançamento: a pessoa não muda depois) */
  extraId: string | null
  funcionarioId: string | null
  /** só extra; null = padrão do cadastro */
  pontos: number | null
  /** null = padrão do cadastro */
  valorCentavos: number | null
  funcao: string | null
  observacao: string | null
  pago: boolean
  pagoEm: string | null
}

export function useSalvarDiaria() {
  return useMutacaoDiaria(async (a: { id?: string | null; dados: DadosDiaria }) => {
    const d = a.dados
    if (a.id) {
      await chamarRpc('diaria_atualizar', {
        p_diaria: a.id,
        p_data: d.data,
        p_pontos: d.extraId ? d.pontos : null,
        p_valor_centavos: d.valorCentavos,
        p_funcao: d.funcao,
        p_observacao: d.observacao,
        p_pago: d.pago,
        p_pago_em: d.pago ? d.pagoEm : null,
      })
      return a.id
    }
    return chamarRpc('diaria_lancar', {
      p_data: d.data,
      p_extra: d.extraId,
      p_funcionario: d.extraId ? null : d.funcionarioId,
      p_pontos: d.extraId ? d.pontos : null,
      p_valor_centavos: d.valorCentavos,
      p_funcao: d.funcao,
      p_observacao: d.observacao,
      p_pago: d.pago,
      p_pago_em: d.pago ? d.pagoEm : null,
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
const CAMPOS_DINHEIRO = ['diarias_pagas', 'diarias_a_pagar', 'comissoes_fechadas', 'comissoes_previstas', 'total', 'diarias_qtd'] as const

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
          diarias_extras: num(g.totais.diarias_extras),
          diarias_funcionarios: num(g.totais.diarias_funcionarios),
          comissoes_fechadas: num(g.totais.comissoes_fechadas),
          comissoes_previstas: num(g.totais.comissoes_previstas),
          total: num(g.totais.total),
          total_com_previsto: num(g.totais.total_com_previsto),
        },
        por_pessoa: (g.por_pessoa ?? []).map(normal),
        por_dia: (g.por_dia ?? []).map(normal),
        fechamentos: (g.fechamentos ?? []).map((f) => ({
          ...f,
          base_distribuivel_centavos: num(f.base_distribuivel_centavos),
          valor_no_periodo_centavos: num(f.valor_no_periodo_centavos),
        })),
      }
    },
  })
}
