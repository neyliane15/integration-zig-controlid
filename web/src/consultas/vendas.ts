/**
 * Vendas e faturamento da Zig (contrato §8, §10.5). Dono: frontend-2.
 */
import { useQuery } from '@tanstack/react-query'
import type { ZigLoja } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'
import type { RegistroFaturamento } from '@/lib/vendas'

const num = (v: unknown) => Number(v) || 0

function useArgs(inicio: string, fim: string, loja: string | null) {
  const { empresaId } = useEmpresaAtual()
  return { empresaId, args: { p_inicio: inicio, p_fim: fim, p_loja: loja, p_empresa: empresaId } }
}

export function useVendasResumo(inicio: string, fim: string, loja: string | null, habilitado = true) {
  const { empresaId, args } = useArgs(inicio, fim, loja)
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'resumo', inicio, fim, loja),
    enabled: !!empresaId && habilitado,
    queryFn: async () => {
      const [r] = (await chamarRpc('vendas_resumo', args)) ?? []
      return {
        faturamento: num(r?.faturamento),
        vendas: num(r?.vendas),
        servico: num(r?.servico),
        descontos: num(r?.descontos),
        transacoes: num(r?.transacoes),
        servico_compradores: num(r?.servico_compradores),
      }
    },
  })
}

export function useFaturamentoPorDia(inicio: string, fim: string, loja: string | null, habilitado = true) {
  const { empresaId, args } = useArgs(inicio, fim, loja)
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'por-dia', inicio, fim, loja),
    enabled: !!empresaId && habilitado,
    queryFn: async () => ((await chamarRpc('vendas_faturamento_por_dia', args)) ?? []).map((l) => ({ data: l.data, valor: num(l.valor) })),
  })
}

export function useFaturamentoPorForma(inicio: string, fim: string, loja: string | null, habilitado = true) {
  const { empresaId, args } = useArgs(inicio, fim, loja)
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'por-forma', inicio, fim, loja),
    enabled: !!empresaId && habilitado,
    queryFn: async () => ((await chamarRpc('vendas_faturamento_por_forma', args)) ?? []).map((l) => ({ ...l, valor: num(l.valor) })),
  })
}

export function useVendasPorGarcom(inicio: string, fim: string, loja: string | null, habilitado = true) {
  const { empresaId, args } = useArgs(inicio, fim, loja)
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'por-garcom', inicio, fim, loja),
    enabled: !!empresaId && habilitado,
    queryFn: async () =>
      ((await chamarRpc('vendas_por_garcom', args)) ?? []).map((l) => ({
        ...l,
        quantidade: num(l.quantidade),
        valor_vendas: num(l.valor_vendas),
        valor_servico: num(l.valor_servico),
        transacoes: num(l.transacoes),
      })),
  })
}

export function useLojasZig() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'lojas', '', '', null),
    enabled: !!empresaId,
    staleTime: 5 * 60_000,
    queryFn: async () =>
      exigir(
        await supabase
          .from('zig_lojas')
          .select('*')
          .eq('empresa_id', empresaId as string)
          .order('nome'),
      ) as ZigLoja[],
  })
}

/** Linhas cruas de `zig_faturamento` do período (para o CSV dia × forma). Pagina de 1000 em 1000. */
export async function buscarFaturamentoDetalhado(
  empresaId: string,
  inicio: string,
  fim: string,
  loja: string | null,
): Promise<RegistroFaturamento[]> {
  const todos: RegistroFaturamento[] = []
  for (let de = 0; de < 100_000; de += 1000) {
    let q = supabase
      .from('zig_faturamento')
      .select('data_operacao, payment_name, valor')
      .eq('empresa_id', empresaId)
      .gte('data_operacao', inicio)
      .lte('data_operacao', fim)
    if (loja) q = q.eq('loja_id_externo', loja)
    const pagina = exigir(await q.order('data_operacao').order('id').range(de, de + 999)) as RegistroFaturamento[]
    todos.push(...pagina.map((p) => ({ ...p, valor: num(p.valor) })))
    if (pagina.length < 1000) break
  }
  return todos
}
