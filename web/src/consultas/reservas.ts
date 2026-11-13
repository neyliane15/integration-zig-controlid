/**
 * Reservas (adendo R): leitura SEMPRE por `reservas_listar` (leitura recebe telefone/e-mail nulos), escrita por RPC.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { LinhaImportacaoReserva, Reserva, StatusReserva } from '@/tipos/banco'
import { chamarRpc } from '@/lib/supabase'
import { chaves, invalidar } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'
import type { ReservaLida } from '@/lib/reservasCsv'

export function useReservas(inicio: string, fim: string) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.reservas(empresaId, inicio, fim),
    enabled: !!empresaId && !!inicio && !!fim && inicio <= fim,
    queryFn: async () =>
      ((await chamarRpc('reservas_listar', { p_inicio: inicio, p_fim: fim, p_empresa: empresaId })) ?? []).map<Reserva>((r) => ({
        ...r,
        pessoas: Number(r.pessoas) || 0,
      })),
  })
}

function useMutacaoReserva<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => invalidar(qc, 'reservas', 'painel') })
}

export interface DadosReserva {
  data: string
  horario: string | null
  nomeCliente: string
  pessoas: number
  telefone: string | null
  email: string | null
  area: string | null
  mesa: string | null
  observacao: string | null
  status: StatusReserva
}

export function useSalvarReserva() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoReserva(async (a: { id?: string | null; dados: DadosReserva }) => {
    const d = a.dados
    if (a.id) {
      await chamarRpc('reserva_atualizar', {
        p_reserva: a.id,
        p_data: d.data,
        p_horario: d.horario,
        p_nome_cliente: d.nomeCliente,
        p_pessoas: d.pessoas,
        p_telefone: d.telefone,
        p_area: d.area,
        p_mesa: d.mesa,
        p_observacao: d.observacao,
        p_status: d.status,
        p_email: d.email,
      })
      return a.id
    }
    return chamarRpc('reserva_criar', {
      p_data: d.data,
      p_horario: d.horario,
      p_nome_cliente: d.nomeCliente,
      p_pessoas: d.pessoas,
      p_telefone: d.telefone,
      p_area: d.area,
      p_mesa: d.mesa,
      p_observacao: d.observacao,
      p_status: d.status,
      p_email: d.email,
      p_empresa: empresaId,
    })
  })
}

export function useMudarStatusReserva() {
  return useMutacaoReserva((a: { id: string; status: StatusReserva }) => chamarRpc('reserva_mudar_status', { p_reserva: a.id, p_status: a.status }))
}

export function useCancelarReserva() {
  return useMutacaoReserva((id: string) => chamarRpc('reserva_cancelar', { p_reserva: id }))
}

export function useExcluirReserva() {
  return useMutacaoReserva((id: string) => chamarRpc('reserva_excluir', { p_reserva: id }))
}

/** Converte as linhas lidas do CSV para o formato de `reservas_importar` (R.3). */
export function paraImportacao(r: ReservaLida): LinhaImportacaoReserva {
  return {
    id_externo: r.id_externo,
    data: r.data,
    horario: r.hora,
    nome: r.nome,
    pessoas: r.pessoas,
    telefone: r.telefone,
    email: r.email,
    status: r.status,
    area: r.area,
    mesa: r.mesa,
    observacao: r.observacao,
  }
}

export function useImportarReservas() {
  const { empresaId } = useEmpresaAtual()
  return useMutacaoReserva((linhas: ReservaLida[]) => chamarRpc('reservas_importar', { p_linhas: linhas.map(paraImportacao), p_empresa: empresaId }))
}
