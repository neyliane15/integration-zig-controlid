/**
 * Integrações, segredos (somente escrita), sincronização e lojas Zig (contrato §10.2, §11.1, §12.1, §14.4).
 * Dono: frontend-1. O front NUNCA lê valores de segredo — só quais chaves estão preenchidas.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type {
  ChaveSegredo,
  ControlIdEnvio,
  EscopoSync,
  Integracao,
  ParametrosIntegracao,
  SyncExecucao,
  SyncSolicitacao,
  TipoIntegracao,
  ZigLoja,
} from '@/tipos/banco'
import { chaves, invalidar } from '@/lib/consultas'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'

export function useIntegracoes(empresaId: string | null) {
  return useQuery({
    queryKey: chaves.integracoes(empresaId),
    queryFn: async () =>
      exigir(await supabase.from('integracoes').select('*').eq('empresa_id', empresaId!).order('tipo').order('nome')) as Integracao[],
    enabled: empresaId != null,
  })
}

export function useIntegracao(id: string | null | undefined) {
  return useQuery({
    queryKey: [...chaves.integracoes(null), 'detalhe', id ?? null],
    queryFn: async () => exigir(await supabase.from('integracoes').select('*').eq('id', id!).maybeSingle<Integracao>()),
    enabled: !!id,
  })
}

export function useSegredosPreenchidos(integracaoId: string | null | undefined) {
  return useQuery({
    queryKey: ['integracoes', 'segredos', integracaoId ?? null],
    queryFn: () => chamarRpc('integracao_segredos_preenchidos', { p_integracao: integracaoId! }),
    enabled: !!integracaoId,
  })
}

/** Últimas 20 execuções (da empresa ou de uma integração). */
export function useExecucoes(empresaId: string | null, integracaoId?: string | null, limite = 20) {
  return useQuery({
    queryKey: [...chaves.sync(empresaId), 'execucoes', integracaoId ?? null, limite],
    queryFn: async () => {
      let q = supabase.from('sync_execucoes').select('*').eq('empresa_id', empresaId!)
      if (integracaoId) q = q.eq('integracao_id', integracaoId)
      return exigir(await q.order('iniciado_em', { ascending: false }).limit(limite)) as SyncExecucao[]
    },
    enabled: empresaId != null,
    refetchInterval: (q) => (q.state.data?.some((e) => e.status === 'executando') ? 5_000 : 60_000),
  })
}

/** Solicitações abertas (na fila ou sincronizando). Consulta a cada 5 s enquanto houver alguma (§12.1). */
export function useSolicitacoesAbertas(empresaId: string | null) {
  const qc = useQueryClient()
  return useQuery({
    queryKey: [...chaves.sync(empresaId), 'solicitacoes'],
    queryFn: async () => {
      const linhas = exigir(
        await supabase
          .from('sync_solicitacoes')
          .select('*')
          .eq('empresa_id', empresaId!)
          .in('status', ['pendente', 'em_andamento'])
          .order('solicitado_em', { ascending: false })
          .limit(50),
      ) as SyncSolicitacao[]
      return linhas
    },
    enabled: empresaId != null,
    refetchInterval: (q) => {
      const abertas = q.state.data?.length ?? 0
      return abertas > 0 ? 5_000 : false
    },
    // quando a fila esvazia, atualiza o resto (status das integrações, painel, dados importados)
    structuralSharing: (antigo, novo) => {
      const a = (antigo as SyncSolicitacao[] | undefined)?.length ?? 0
      const n = (novo as SyncSolicitacao[]).length
      if (a > 0 && n < a) void invalidar(qc, 'integracoes', 'painel', 'ponto-dia', 'vendas', 'controlid-usuarios', 'funcionarios')
      return novo
    },
  })
}

export function useSincronizarAgora() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: {
      empresaId: string | null
      integracaoId?: string | null
      escopo?: EscopoSync
      dataInicio?: string | null
      dataFim?: string | null
    }) =>
      chamarRpc('sync_solicitar', {
        p_integracao: a.integracaoId ?? null,
        p_escopo: a.escopo ?? 'tudo',
        p_data_inicio: a.dataInicio ?? null,
        p_data_fim: a.dataFim ?? null,
        p_empresa: a.empresaId,
      }),
    onSuccess: () => invalidar(qc, 'sync', 'painel', 'integracoes'),
  })
}

export interface DadosIntegracao {
  nome: string
  ativa: boolean
  parametros: ParametrosIntegracao
  intervalo_minutos: number
}

export function useSalvarIntegracao() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { id?: string; empresaId: string; tipo: TipoIntegracao; dados: DadosIntegracao }) => {
      if (a.id) {
        const linhas = exigir(await supabase.from('integracoes').update(a.dados).eq('id', a.id).select('id')) as { id: string }[]
        if (linhas.length === 0) throw new Error('Sem permissão')
        return a.id
      }
      const nova = exigir(
        await supabase
          .from('integracoes')
          .insert({ ...a.dados, empresa_id: a.empresaId, tipo: a.tipo })
          .select('id')
          .single<{ id: string }>(),
      )
      return nova.id
    },
    onSuccess: () => invalidar(qc, 'integracoes', 'painel'),
  })
}

/** Merge: string não vazia grava; null remove; chave ausente fica como está. */
export function useDefinirSegredos() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { integracaoId: string; segredos: Partial<Record<ChaveSegredo, string | null>> }) =>
      chamarRpc('integracao_definir_segredos', { p_integracao: a.integracaoId, p_segredos: a.segredos }),
    onSuccess: (_r, a) => qc.invalidateQueries({ queryKey: ['integracoes', 'segredos', a.integracaoId] }),
  })
}

export function useExcluirIntegracao() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const linhas = exigir(await supabase.from('integracoes').delete().eq('id', id).select('id')) as { id: string }[]
      if (linhas.length === 0) throw new Error('Sem permissão')
    },
    onSuccess: () => invalidar(qc, 'integracoes', 'painel', 'sync'),
  })
}

// ---------------------------------------------------------------- lojas Zig
export function useLojasZig(empresaId: string | null, integracaoId?: string | null) {
  return useQuery({
    queryKey: [...chaves.integracoes(empresaId), 'lojas', integracaoId ?? null],
    queryFn: async () => {
      let q = supabase.from('zig_lojas').select('*').eq('empresa_id', empresaId!)
      if (integracaoId) q = q.eq('integracao_id', integracaoId)
      return exigir(await q.order('nome')) as ZigLoja[]
    },
    enabled: empresaId != null,
  })
}

export function useMarcarLojaZig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { id: string; sincronizar: boolean }) => {
      const linhas = exigir(await supabase.from('zig_lojas').update({ sincronizar: a.sincronizar }).eq('id', a.id).select('id')) as {
        id: string
      }[]
      if (linhas.length === 0) throw new Error('Sem permissão')
    },
    onSuccess: () => invalidar(qc, 'integracoes', 'vendas'),
  })
}

// ------------------------------------------- envio ao Control iD (adendo)
/** Resumo da fila de envio de um equipamento (contagem por status + erros recentes). */
export function useEnviosControlId(empresaId: string | null, integracaoId: string | null | undefined) {
  return useQuery({
    queryKey: [...chaves.integracoes(empresaId), 'envios', integracaoId ?? null],
    queryFn: async () =>
      exigir(
        await supabase
          .from('controlid_envios')
          .select('id, alvo, funcionario_id, funcionario_nome, operacao, status, erro, tentativas, enviado_em, pendente_desde, atualizado_em')
          .eq('integracao_id', integracaoId!)
          .order('atualizado_em', { ascending: false })
          .limit(500),
      ) as Pick<
        ControlIdEnvio,
        | 'id'
        | 'alvo'
        | 'funcionario_id'
        | 'funcionario_nome'
        | 'operacao'
        | 'status'
        | 'erro'
        | 'tentativas'
        | 'enviado_em'
        | 'pendente_desde'
        | 'atualizado_em'
      >[],
    enabled: empresaId != null && !!integracaoId,
    retry: false,
  })
}

export function useReenviarControlId() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { integracaoId: string; empresaId: string | null }) =>
      chamarRpc('controlid_envio_reenviar', { p_integracao: a.integracaoId, p_empresa: a.empresaId }),
    onSuccess: () => invalidar(qc, 'integracoes'),
  })
}

// ----------------------------------------------------------- utilitários
/** Chaves de segredo por tipo (§11.1). */
export const CHAVES_SEGREDO: Record<TipoIntegracao, { chave: ChaveSegredo; rotulo: string; dica: string; tipo: 'text' | 'password' | 'url' }[]> = {
  zig: [{ chave: 'token', rotulo: 'Token da Zig', dica: 'Fornecido pela Zig para a integração ERP.', tipo: 'password' }],
  controlid_acesso: [
    { chave: 'url', rotulo: 'Endereço do equipamento', dica: 'Ex.: http://192.168.0.50 (o N8N precisa alcançar este IP).', tipo: 'url' },
    { chave: 'login', rotulo: 'Usuário', dica: 'Usuário administrador do equipamento.', tipo: 'text' },
    { chave: 'senha', rotulo: 'Senha', dica: 'Senha do usuário administrador.', tipo: 'password' },
  ],
  controlid_rep: [
    { chave: 'url', rotulo: 'Endereço do relógio', dica: 'Ex.: https://192.168.0.60 (o N8N precisa alcançar este IP).', tipo: 'url' },
    { chave: 'login', rotulo: 'Usuário', dica: 'Usuário administrador do REP.', tipo: 'text' },
    { chave: 'senha', rotulo: 'Senha', dica: 'Senha do usuário administrador.', tipo: 'password' },
  ],
}

/** Parâmetros padrão por tipo (§11.1 + adendo A.1). */
export function parametrosPadrao(tipo: TipoIntegracao): ParametrosIntegracao {
  if (tipo === 'zig') return { rede: '', dias_retroativos: 2 }
  if (tipo === 'controlid_acesso')
    return {
      modelo: 'iDFace',
      dias_retroativos: 2,
      eventos_validos: [7],
      relogio_em_hora_local: true,
      envio: { ativo: false, foto: true, cartao: true, senha: true, horarios: true, ao_desligar: 'remover' },
    }
  return {
    modelo: 'iDClass',
    dias_retroativos: 2,
    identificador: 'cpf',
    envio: { ativo: false, foto: false, cartao: true, senha: true, horarios: false, ao_desligar: 'remover' },
  }
}

export const MODELOS_ACESSO = ['iDFace', 'iDFace Max', 'iDFlex', 'iDAccess', 'iDAccess Nano'] as const
export const MODELOS_REP = ['iDClass', 'iDClass Bio'] as const

export function nomePadrao(tipo: TipoIntegracao): string {
  return tipo === 'zig' ? 'Zig' : tipo === 'controlid_acesso' ? 'Controle de acesso' : 'Relógio de ponto'
}
