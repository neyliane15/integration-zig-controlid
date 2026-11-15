/**
 * Faltas (adendo extras v3, §E.7.2): justificada (motivo obrigatório, anexo opcional) ou injustificada. Tiram a comissão do dia.
 * Anexo no bucket privado `funcionarios-documentos` em `<empresa>/faltas/<funcionario>/<uuid>.<ext>`: upload → `falta_definir_anexo`.
 * Toda escrita reapura o ponto do dia e recalcula os rascunhos de comissão (no banco) — aqui só invalidamos as telas.
 */
import { useMutation, useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query'
import type { TipoFalta } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidar, invalidarPonto } from '@/lib/consultas'
import { useEmpresaAtual } from '@/lib/sessao'
import { BUCKET_DOCUMENTOS } from './ocorrencias'

function extensao(tipo: string, nome?: string | null): string {
  if (tipo === 'application/pdf') return 'pdf'
  if (tipo === 'image/png') return 'png'
  if (tipo === 'image/webp') return 'webp'
  const m = /\.(jpe?g|png|webp|pdf)$/i.exec(nome ?? '')
  return m ? m[1]!.toLowerCase() : 'jpg'
}

/** `<empresa_id>/faltas/<funcionario_id>/<uuid>.<ext>` (§E.7.2). */
export function caminhoAnexoFalta(empresaId: string, funcionarioId: string, tipo: string, nome?: string | null): string {
  const id = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : String(Date.now())
  return `${empresaId}/faltas/${funcionarioId}/${id}.${extensao(tipo, nome)}`
}

export function useFaltas(inicio: string, fim: string, funcionarioId: string | null = null, habilitado = true) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: chaves.faltas(empresaId, inicio, fim, funcionarioId),
    enabled: !!empresaId && habilitado && !!inicio && !!fim,
    queryFn: async () =>
      (await chamarRpc('faltas_listar', { p_inicio: inicio, p_fim: fim, p_funcionario: funcionarioId, p_empresa: funcionarioId ? null : empresaId })) ?? [],
  })
}

async function aposFalta(qc: QueryClient) {
  await invalidar(qc, 'escala-mes', 'faltas', 'comissoes', 'fechamento', 'funcionario')
  void invalidarPonto(qc)
}

export interface ArgsFalta {
  funcionarioId: string
  data: string
  tipo: TipoFalta
  motivo: string | null
  /** anexo opcional (só justificada; imagem já comprimida ou PDF) */
  arquivo?: Blob | null
  nomeArquivo?: string | null
}

/**
 * Registra (ou troca) a falta do dia. O anexo vai depois do registro: se o upload falhar a falta fica salva e o erro do anexo
 * volta em `anexoErro` (o Storage não existe no ambiente local).
 */
export function useRegistrarFalta() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: async (a: ArgsFalta) => {
      const falta = await chamarRpc('falta_registrar', {
        p_funcionario: a.funcionarioId,
        p_data: a.data,
        p_tipo: a.tipo,
        p_motivo: a.motivo?.trim() || null,
      })
      if (falta?.anexo_anterior) await supabase.storage.from(BUCKET_DOCUMENTOS).remove([falta.anexo_anterior]).catch(() => undefined)
      let anexoErro: unknown = null
      if (a.arquivo && empresaId) {
        const tipo = a.arquivo.type || 'image/jpeg'
        const caminho = caminhoAnexoFalta(empresaId, a.funcionarioId, tipo, a.nomeArquivo)
        try {
          exigir(await supabase.storage.from(BUCKET_DOCUMENTOS).upload(caminho, a.arquivo, { contentType: tipo, upsert: false }))
          const antigo = await chamarRpc('falta_definir_anexo', {
            p_funcionario: a.funcionarioId,
            p_data: a.data,
            p_caminho: caminho,
            p_nome_arquivo: a.nomeArquivo ?? null,
          })
          if (antigo) await supabase.storage.from(BUCKET_DOCUMENTOS).remove([antigo]).catch(() => undefined)
        } catch (e) {
          anexoErro = e
        }
      }
      return { falta, anexoErro }
    },
    onSuccess: () => aposFalta(qc),
  })
}

export function useRemoverFalta() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { funcionarioId: string; data: string }) => {
      const caminho = await chamarRpc('falta_remover', { p_funcionario: a.funcionarioId, p_data: a.data })
      if (caminho) await supabase.storage.from(BUCKET_DOCUMENTOS).remove([caminho]).catch(() => undefined)
    },
    onSuccess: () => aposFalta(qc),
  })
}
