/**
 * Consultas e mutações de funcionários, jornadas e vínculos Control iD/Zig. Dono: frontend-2.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type {
  ControlIdUsuario,
  Funcionario,
  FuncionarioJornada,
  FuncionarioPontos,
  Integracao,
  Jornada,
  JornadaDia,
  Perfil,
} from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidar, invalidarPonto } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'
import { hojeISO, somarDias } from '@/lib/formato'

// --------------------------------------------------------------- contexto
/** Empresa em que a tela opera + fuso/virada/dia de trabalho atual. */
export function useContextoEmpresa() {
  const { empresaId, empresa } = useEmpresaAtual()
  const fuso = empresa?.fuso ?? 'America/Sao_Paulo'
  const virada = (empresa?.virada_dia ?? '05:00').slice(0, 5)
  return { empresaId, empresa, fuso, virada, hoje: hojeISO(fuso, virada) }
}

// ------------------------------------------------------------ funcionários
export type DadosFuncionario = Partial<
  Pick<
    Funcionario,
    | 'nome'
    | 'apelido'
    | 'matricula'
    | 'cpf'
    | 'pis'
    | 'cargo'
    | 'telefone'
    | 'email'
    | 'zig_employee_name'
    | 'pontos_comissao'
    | 'participa_comissao'
    | 'data_admissao'
    | 'data_desligamento'
    | 'ativo'
    | 'observacoes'
  >
>

export function useFuncionarios() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.funcionarios(empresaId),
    enabled: !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('funcionarios')
          .select('*')
          .eq('empresa_id', empresaId as string)
          .order('nome'),
      ) as Funcionario[],
  })
}

export function useFuncionario(id: string | null | undefined) {
  return useQuery({
    queryKey: chaves.funcionario(id),
    enabled: !!id,
    queryFn: async () => {
      const f = exigir(await supabase.from('funcionarios').select('*').eq('id', id as string).maybeSingle()) as Funcionario | null
      if (!f) throw new Error('Funcionário não encontrado')
      return f
    },
  })
}

export function useSalvarFuncionario() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async ({ id, dados }: { id?: string | null; dados: DadosFuncionario }): Promise<string> => {
      if (id) {
        exigir(await supabase.from('funcionarios').update(dados).eq('id', id).select('id').single())
        return id
      }
      const r = exigir(
        await supabase
          .from('funcionarios')
          .insert({ ...dados, empresa_id: empresaId })
          .select('id')
          .single(),
      ) as { id: string }
      return r.id
    },
    onSuccess: async (id) => {
      await invalidar(qc, 'funcionarios', 'funcionario', 'comissoes')
      await qc.invalidateQueries({ queryKey: ['funcionario-pontos', id] })
      await invalidarPonto(qc)
    },
  })
}

export function useExcluirFuncionario() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const r = exigir(await supabase.from('funcionarios').delete().eq('id', id).select('id')) as { id: string }[]
      if (r.length === 0) throw new Error('Sem permissão')
    },
    onSuccess: async () => {
      await invalidar(qc, 'funcionarios', 'funcionario')
      await invalidarPonto(qc)
    },
  })
}

/** Histórico de pontos de comissão (G A M; leitura recebe lista vazia pela RLS). */
export function usePontosFuncionario(funcionarioId: string | null | undefined) {
  return useQuery({
    queryKey: ['funcionario-pontos', funcionarioId ?? null],
    enabled: !!funcionarioId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('funcionario_pontos')
          .select('*')
          .eq('funcionario_id', funcionarioId as string)
          .order('vigente_desde', { ascending: false }),
      ) as FuncionarioPontos[],
  })
}

// --------------------------------------------------------------- jornadas
export type JornadaComDias = Jornada & { jornada_dias: JornadaDia[] }

export function useJornadas() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.jornadas(empresaId),
    enabled: !!empresaId,
    queryFn: async () => {
      const lista = exigir(
        await supabase
          .from('jornadas')
          .select('*, jornada_dias(*)')
          .eq('empresa_id', empresaId as string)
          .order('nome'),
      ) as JornadaComDias[]
      for (const j of lista) j.jornada_dias.sort((a, b) => a.dia_semana - b.dia_semana)
      return lista
    },
  })
}

export interface DiaJornadaEntrada {
  dia_semana: number
  entrada: string
  saida_intervalo: string | null
  volta_intervalo: string | null
  saida: string
}

export interface DadosJornada {
  id?: string | null
  nome: string
  tolerancia_batida_minutos: number
  tolerancia_diaria_minutos: number
  ativa: boolean
  dias: DiaJornadaEntrada[]
}

export function useSalvarJornada() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async (d: DadosJornada): Promise<string> => {
      const campos = {
        nome: d.nome.trim(),
        tolerancia_batida_minutos: d.tolerancia_batida_minutos,
        tolerancia_diaria_minutos: d.tolerancia_diaria_minutos,
        ativa: d.ativa,
      }
      let id = d.id ?? null
      if (id) {
        exigir(await supabase.from('jornadas').update(campos).eq('id', id).select('id').single())
      } else {
        const r = exigir(
          await supabase
            .from('jornadas')
            .insert({ ...campos, empresa_id: empresaId })
            .select('id')
            .single(),
        ) as { id: string }
        id = r.id
      }
      const diasMantidos = d.dias.map((x) => x.dia_semana)
      // remove os dias que viraram folga
      let remover = supabase.from('jornada_dias').delete().eq('jornada_id', id)
      if (diasMantidos.length) remover = remover.not('dia_semana', 'in', `(${diasMantidos.join(',')})`)
      exigir(await remover)
      if (d.dias.length) {
        exigir(
          await supabase.from('jornada_dias').upsert(
            d.dias.map((x) => ({
              jornada_id: id,
              empresa_id: empresaId,
              dia_semana: x.dia_semana,
              entrada: x.entrada,
              saida_intervalo: x.saida_intervalo,
              volta_intervalo: x.volta_intervalo,
              saida: x.saida,
            })),
            { onConflict: 'jornada_id,dia_semana' },
          ),
        )
      }
      return id as string
    },
    onSuccess: async () => {
      await invalidar(qc, 'jornadas')
      await invalidarPonto(qc)
    },
  })
}

export function useExcluirJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      exigir(await supabase.from('jornadas').delete().eq('id', id))
    },
    onSuccess: () => invalidar(qc, 'jornadas'),
  })
}

export type FuncionarioJornadaComNome = FuncionarioJornada & { jornadas: { nome: string } | null }

/** Histórico de jornadas do funcionário (mais recente primeiro). */
export function useJornadasDoFuncionario(funcionarioId: string | null | undefined) {
  return useQuery({
    queryKey: ['jornadas', 'funcionario', funcionarioId ?? null],
    enabled: !!funcionarioId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('funcionario_jornadas')
          .select('*, jornadas(nome)')
          .eq('funcionario_id', funcionarioId as string)
          .order('vigente_desde', { ascending: false }),
      ) as FuncionarioJornadaComNome[],
  })
}

/** Jornada vigente em cada funcionário hoje (para a lista). */
export function useJornadasVigentes() {
  const { empresaId, hoje } = useContextoEmpresa()
  return useQuery({
    queryKey: ['jornadas', empresaId ?? null, 'vigentes', hoje],
    enabled: !!empresaId,
    queryFn: async () => {
      const linhas = exigir(
        await supabase
          .from('funcionario_jornadas')
          .select('funcionario_id, vigente_desde, jornadas(nome)')
          .eq('empresa_id', empresaId as string)
          .lte('vigente_desde', hoje)
          .order('vigente_desde', { ascending: false }),
      ) as unknown as { funcionario_id: string; vigente_desde: string; jornadas: { nome: string } | null }[]
      const mapa = new Map<string, string>()
      for (const l of linhas) if (!mapa.has(l.funcionario_id)) mapa.set(l.funcionario_id, l.jornadas?.nome ?? '—')
      return mapa
    },
  })
}

export function useDefinirJornadaFuncionario() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: { funcionarioId: string; jornadaId: string; vigenteDesde: string }) => {
      exigir(
        await supabase
          .from('funcionario_jornadas')
          .upsert(
            { funcionario_id: d.funcionarioId, jornada_id: d.jornadaId, vigente_desde: d.vigenteDesde },
            { onConflict: 'funcionario_id,vigente_desde' },
          ),
      )
    },
    onSuccess: async () => {
      await invalidar(qc, 'jornadas')
      await invalidarPonto(qc)
    },
  })
}

export function useRemoverJornadaFuncionario() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      exigir(await supabase.from('funcionario_jornadas').delete().eq('id', id))
    },
    onSuccess: async () => {
      await invalidar(qc, 'jornadas')
      await invalidarPonto(qc)
    },
  })
}

// ------------------------------------------------------------ Control iD
export type EquipamentoControlId = Pick<Integracao, 'id' | 'nome' | 'tipo' | 'ativa'>

/** Equipamentos Control iD da empresa (G A M). */
export function useEquipamentosControlId() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: ['integracoes', empresaId ?? null, 'controlid-equipamentos'],
    enabled: !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('integracoes')
          .select('id, nome, tipo, ativa')
          .eq('empresa_id', empresaId as string)
          .in('tipo', ['controlid_acesso', 'controlid_rep'])
          .order('nome'),
      ) as EquipamentoControlId[],
  })
}

/** Usuários importados de todos os equipamentos Control iD da empresa (G A M). */
export function useControlIdUsuarios() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.controlidUsuarios(empresaId),
    enabled: !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('controlid_usuarios')
          .select('*')
          .eq('empresa_id', empresaId as string)
          .order('nome'),
      ) as ControlIdUsuario[],
  })
}

export function useVincularControlId() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (d: { controlidUsuarioId: string; funcionarioId: string | null }) =>
      chamarRpc('funcionario_vincular_controlid', { p_controlid_usuario: d.controlidUsuarioId, p_funcionario: d.funcionarioId }),
    onSuccess: async () => {
      await invalidar(qc, 'controlid-usuarios', 'funcionarios', 'painel')
      await invalidarPonto(qc)
    },
  })
}

/** Nomes de garçom (employeeName) vistos na Zig nos últimos 60 dias — sugestões do vínculo. */
export function useNomesZig() {
  const { empresaId, hoje } = useContextoEmpresa()
  const inicio = somarDias(hoje, -60)
  return useQuery({
    queryKey: chaves.vendas(empresaId, 'nomes-zig', inicio, hoje, null),
    enabled: !!empresaId,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const linhas = await chamarRpc('vendas_por_garcom', { p_inicio: inicio, p_fim: hoje, p_empresa: empresaId })
      return (linhas ?? [])
        .filter((l) => l.employee_name?.trim())
        .map((l) => ({ nome: l.employee_name as string, funcionarioId: l.funcionario_id, valor: l.valor_vendas }))
    },
  })
}

// --------------------------------------------------------------- perfis
export type PerfilResumo = Pick<Perfil, 'id' | 'nome' | 'email' | 'papel' | 'funcionario_id' | 'ativo'>

/** Usuários da empresa (para atribuir tarefas). */
export function usePerfisEmpresa() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: ['usuarios', empresaId ?? null, 'resumo'],
    enabled: !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('perfis')
          .select('id, nome, email, papel, funcionario_id, ativo')
          .eq('empresa_id', empresaId as string)
          .order('nome'),
      ) as PerfilResumo[],
  })
}
