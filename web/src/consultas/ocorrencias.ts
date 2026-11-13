/**
 * Ocorrências disciplinares (adendo O): advertências e suspensões, com fotos do documento assinado no bucket privado
 * `funcionarios-documentos`. Leitura sempre por RPC; Storage: upload → `ocorrencia_adicionar_anexo`; remover → RPC → storage.remove.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { TipoOcorrencia } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidar, invalidarPonto } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'

export const BUCKET_DOCUMENTOS = 'funcionarios-documentos'
export const LIMITE_ANEXOS = 10

const num = (v: unknown) => Number(v) || 0

export function useOcorrencias(funcionarioId: string | null | undefined) {
  return useQuery({
    queryKey: chaves.ocorrencias(funcionarioId),
    enabled: !!funcionarioId,
    queryFn: async () => (await chamarRpc('ocorrencias_listar', { p_funcionario: funcionarioId as string })) ?? [],
  })
}

/** Contagem por funcionário (lista de funcionários e ficha). */
export function useContagemOcorrencias(habilitado = true) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.ocorrenciasContagem(empresaId),
    enabled: !!empresaId && habilitado,
    queryFn: async () => {
      const linhas = (await chamarRpc('ocorrencias_contagem', { p_empresa: empresaId })) ?? []
      return new Map(
        linhas.map((l) => [
          l.funcionario_id,
          { ...l, advertencias: num(l.advertencias), suspensoes: num(l.suspensoes), dias_suspensao: num(l.dias_suspensao) },
        ]),
      )
    },
  })
}

/** "2 advertências · 1 suspensão" (vazio se nenhuma). */
export function textoContagem(advertencias: number, suspensoes: number): string {
  const partes: string[] = []
  if (advertencias > 0) partes.push(`${advertencias} ${advertencias === 1 ? 'advertência' : 'advertências'}`)
  if (suspensoes > 0) partes.push(`${suspensoes} ${suspensoes === 1 ? 'suspensão' : 'suspensões'}`)
  return partes.join(' · ')
}

function invalidarOcorrencias(qc: ReturnType<typeof useQueryClient>) {
  // suspensão gera abonos e reapura o ponto
  return Promise.all([invalidar(qc, 'ocorrencias', 'ocorrencias-contagem', 'painel', 'comissoes', 'fechamento'), invalidarPonto(qc)])
}

export interface DadosOcorrencia {
  tipo: TipoOcorrencia
  data: string
  motivo: string
  descricao: string | null
  diasSuspensao: number | null
  suspensaoInicio: string | null
}

function argsSuspensao(d: DadosOcorrencia) {
  return d.tipo === 'suspensao'
    ? { p_dias_suspensao: d.diasSuspensao, p_suspensao_inicio: d.suspensaoInicio ?? d.data }
    : { p_dias_suspensao: null, p_suspensao_inicio: null }
}

export function useSalvarOcorrencia() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { id?: string | null; funcionarioId: string; dados: DadosOcorrencia }): Promise<string> => {
      const d = a.dados
      if (a.id) {
        await chamarRpc('ocorrencia_atualizar', {
          p_ocorrencia: a.id,
          p_tipo: d.tipo,
          p_data: d.data,
          p_motivo: d.motivo,
          p_descricao: d.descricao,
          ...argsSuspensao(d),
        })
        return a.id
      }
      return chamarRpc('ocorrencia_criar', {
        p_funcionario: a.funcionarioId,
        p_tipo: d.tipo,
        p_data: d.data,
        p_motivo: d.motivo,
        p_descricao: d.descricao,
        ...argsSuspensao(d),
      })
    },
    onSuccess: () => invalidarOcorrencias(qc),
  })
}

export function useExcluirOcorrencia() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const caminhos = (await chamarRpc('ocorrencia_excluir', { p_ocorrencia: id })) ?? []
      // o banco não apaga objetos do Storage (O.2); falha aqui não desfaz a exclusão
      if (caminhos.length > 0) await supabase.storage.from(BUCKET_DOCUMENTOS).remove(caminhos)
    },
    onSuccess: () => invalidarOcorrencias(qc),
  })
}

function extensao(tipo: string): string {
  if (/png/i.test(tipo)) return 'png'
  if (/webp/i.test(tipo)) return 'webp'
  if (/pdf/i.test(tipo)) return 'pdf'
  return 'jpg'
}

/** Caminho do anexo: `<empresa_id>/ocorrencias/<ocorrencia_id>/<uuid>.<ext>` (O.2). */
export function caminhoAnexo(empresaId: string, ocorrenciaId: string, tipo: string, nome?: string): string {
  const id = nome ?? (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : String(Date.now()))
  return `${empresaId}/ocorrencias/${ocorrenciaId}/${id}.${extensao(tipo)}`
}

/** Envia um arquivo (já comprimido) e registra o anexo; desfaz o upload se o registro falhar. */
export function useAdicionarAnexo() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async (a: { ocorrenciaId: string; arquivo: Blob; nomeArquivo: string | null; empresaId?: string | null }) => {
      const empresa = a.empresaId ?? empresaId
      if (!empresa) throw new Error('Informe a empresa')
      const tipo = a.arquivo.type || 'image/jpeg'
      const caminho = caminhoAnexo(empresa, a.ocorrenciaId, tipo)
      exigir(await supabase.storage.from(BUCKET_DOCUMENTOS).upload(caminho, a.arquivo, { contentType: tipo, upsert: false }))
      try {
        return await chamarRpc('ocorrencia_adicionar_anexo', { p_ocorrencia: a.ocorrenciaId, p_caminho: caminho, p_nome_arquivo: a.nomeArquivo })
      } catch (e) {
        await supabase.storage.from(BUCKET_DOCUMENTOS).remove([caminho])
        throw e
      }
    },
    onSuccess: () => invalidar(qc, 'ocorrencias'),
  })
}

export function useRemoverAnexo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (anexoId: string) => {
      const caminho = await chamarRpc('ocorrencia_remover_anexo', { p_anexo: anexoId })
      if (caminho) await supabase.storage.from(BUCKET_DOCUMENTOS).remove([caminho])
    },
    onSuccess: () => invalidar(qc, 'ocorrencias'),
  })
}

/** URL assinada (5 min) para ver o documento. */
export function useUrlAnexo(caminho: string | null | undefined) {
  return useQuery({
    queryKey: ['ocorrencias', 'anexo-url', caminho ?? null],
    enabled: !!caminho,
    staleTime: 4 * 60_000,
    retry: false,
    queryFn: async () => {
      const r = exigir(await supabase.storage.from(BUCKET_DOCUMENTOS).createSignedUrl(caminho as string, 300)) as { signedUrl: string }
      return r.signedUrl
    },
  })
}

export function useResumoOcorrencias(dias = 30, habilitado = true) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: [...chaves.ocorrenciasContagem(empresaId), 'resumo', dias],
    enabled: !!empresaId && habilitado,
    queryFn: () => chamarRpc('ocorrencias_resumo', { p_dias: dias, p_empresa: empresaId }),
  })
}
