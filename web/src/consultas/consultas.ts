/**
 * Consultas rápidas (perguntas prontas, sem IA): resumo do ponto por funcionário e escala de um dia.
 * As de vendas reaproveitam consultas/vendas.ts.
 */
import { useQuery } from '@tanstack/react-query'
import { chamarRpc } from '@/lib/supabase'
import { chaves } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

const num = (v: unknown) => Number(v) || 0

export function useConsultaPonto(inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.consultaPonto(empresaId, inicio, fim),
    enabled: !!empresaId,
    queryFn: async () =>
      ((await chamarRpc('consultas_ponto_resumo', { p_inicio: inicio, p_fim: fim, p_empresa: empresaId })) ?? []).map((l) => ({
        ...l,
        dias_com_batida: num(l.dias_com_batida),
        faltas: num(l.faltas),
        faltas_justificadas: num(l.faltas_justificadas),
        atrasos: num(l.atrasos),
        minutos_atraso: num(l.minutos_atraso),
        trabalhado_minutos: num(l.trabalhado_minutos),
        saldo_minutos: num(l.saldo_minutos),
      })),
  })
}

export function useConsultaEscala(data: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.consultaEscala(empresaId, data),
    enabled: !!empresaId && !!data,
    queryFn: async () => (await chamarRpc('consultas_escala_dia', { p_data: data, p_empresa: empresaId })) ?? [],
  })
}
