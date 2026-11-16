/**
 * Importação do AFD (RHiD/arquivo) e "Ligar funcionários" — RPCs da migração …0300_importar_afd.sql.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Integracao, ResultadoImportacaoAfd } from '@/tipos/banco'
import { chamarRpc, exigir, supabase } from '@/lib/supabase'
import { chaves, invalidar, invalidarPonto } from '@/lib/consultas'
import { lotesAfd, type LeituraAfd } from '@/lib/afd'
import { useEmpresaAtual } from '@/lib/sessao'

/** Relógios de ponto (REP) da empresa — destino da importação. */
export function useRelogiosPonto() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: [...chaves.integracoes(empresaId), 'relogios-ponto'],
    enabled: !!empresaId,
    queryFn: async () =>
      exigir(
        await supabase
          .from('integracoes')
          .select('*')
          .eq('empresa_id', empresaId as string)
          .eq('tipo', 'controlid_rep')
          .order('ativa', { ascending: false })
          .order('nome'),
      ) as Integracao[],
  })
}

export function ehRelogioPorArquivo(i: Pick<Integracao, 'tipo' | 'parametros'> | null | undefined): boolean {
  return i?.tipo === 'controlid_rep' && (i.parametros as { fonte?: string }).fonte === 'arquivo'
}

/** Cria (ou devolve) o "Relógio de ponto (RHiD/arquivo)" — sem URL nem login. */
export function useCriarRelogioArquivo() {
  const qc = useQueryClient()
  const { empresaId } = useEmpresaAtual()
  return useMutation({
    mutationFn: () => chamarRpc('ponto_integracao_arquivo', { p_empresa: empresaId }),
    onSuccess: () => invalidar(qc, 'integracoes', 'painel'),
  })
}

/** Soma dos lotes de uma importação. */
export function somarResultados(a: ResultadoImportacaoAfd | null, b: ResultadoImportacaoAfd, deslocamento: number): ResultadoImportacaoAfd {
  const erros = (b.erros ?? []).map((e) => ({ ...e, indice: e.indice + deslocamento }))
  if (!a) return { ...b, erros }
  const min = (x: string | null, y: string | null) => (x == null ? y : y == null ? x : x < y ? x : y)
  const max = (x: string | null, y: string | null) => (x == null ? y : y == null ? x : x > y ? x : y)
  return {
    lidas: a.lidas + b.lidas,
    gravadas: a.gravadas + b.gravadas,
    duplicadas: a.duplicadas + b.duplicadas,
    ignoradas: a.ignoradas + b.ignoradas,
    dias_reapurados: a.dias_reapurados + b.dias_reapurados,
    periodo: { inicio: min(a.periodo.inicio, b.periodo.inicio), fim: max(a.periodo.fim, b.periodo.fim) },
    empregados: {
      lidos: a.empregados.lidos + b.empregados.lidos,
      novos: a.empregados.novos + b.empregados.novos,
      atualizados: a.empregados.atualizados + b.empregados.atualizados,
      vinculados_automaticamente: a.empregados.vinculados_automaticamente + b.empregados.vinculados_automaticamente,
    },
    execucao_id: b.execucao_id,
    erros: [...(a.erros ?? []), ...erros].slice(0, 20),
    sem_funcionario: b.sem_funcionario, // calculado no fim de cada lote; o último é o que vale…
  }
}

/** Envia o AFD lido em lotes; `aoProgresso(enviadas, total)`. */
export function useImportarAfd() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (a: { integracaoId: string; leitura: LeituraAfd; arquivo: string; aoProgresso?(enviadas: number, total: number): void }) => {
      const lotes = lotesAfd(a.leitura)
      const total = a.leitura.marcacoes.length
      let r: ResultadoImportacaoAfd | null = null
      const pendentes = new Map<string, ResultadoImportacaoAfd['sem_funcionario'][number]>()
      let enviadas = 0
      for (const [i, lote] of lotes.entries()) {
        const parte = await chamarRpc('ponto_importar_afd', {
          p_integracao: a.integracaoId,
          p_marcacoes: lote.marcacoes,
          p_empregados: lote.empregados,
          p_arquivo_nome: lotes.length > 1 ? `${a.arquivo} (lote ${i + 1}/${lotes.length})` : a.arquivo,
        })
        r = somarResultados(r, parte, enviadas)
        // …mas cada lote só conhece os CPFs dele: junta todos (a contagem mais recente de cada CPF vale)
        for (const p of parte.sem_funcionario) pendentes.set(p.cpf ?? p.pis ?? '', p)
        enviadas += lote.marcacoes.length
        a.aoProgresso?.(enviadas, total)
      }
      if (!r) throw new Error('O arquivo não tem marcações')
      return { ...r, sem_funcionario: [...pendentes.values()].sort((x, y) => y.quantidade - x.quantidade) }
    },
    onSettled: async () => {
      await invalidar(qc, 'integracoes', 'sync', 'controlid-usuarios', 'funcionarios')
      await invalidarPonto(qc)
    },
  })
}

/** CPF/PIS do relógio com batidas ainda sem funcionário. */
export function usePendentesRelogio(integracaoId: string | null | undefined) {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: [...chaves.controlidUsuarios(empresaId), 'pendentes-afd', integracaoId ?? null],
    enabled: !!integracaoId,
    queryFn: () => chamarRpc('ponto_afd_pendentes', { p_integracao: integracaoId! }),
  })
}

/** Funcionários provisórios da escala (posição do modelo, ex.: "Salão|Garçom 1", ainda com o nome da posição). */
export function useProvisoriosEscala() {
  const { empresaId } = useEmpresaAtual()
  return useQuery({
    queryKey: [...chaves.funcionarios(empresaId), 'provisorios-escala'],
    enabled: !!empresaId,
    queryFn: async () => {
      const linhas = exigir(
        await supabase
          .from('escala_membros')
          .select('funcionario_id, modelo_posicao')
          .eq('empresa_id', empresaId as string)
          .not('modelo_posicao', 'is', null),
      ) as { funcionario_id: string; modelo_posicao: string }[]
      return new Map(linhas.map((l) => [l.funcionario_id, l.modelo_posicao.split('|').pop() ?? '']))
    },
  })
}

export function useLigarFuncionarioAfd() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (a: { controlidUsuarioId: string; funcionarioId: string; renomear: boolean; cadastrarDocumento: boolean }) =>
      chamarRpc('ponto_afd_ligar', {
        p_controlid_usuario: a.controlidUsuarioId,
        p_funcionario: a.funcionarioId,
        p_renomear: a.renomear,
        p_cadastrar_documento: a.cadastrarDocumento,
      }),
    onSuccess: async () => {
      await invalidar(qc, 'controlid-usuarios', 'funcionarios', 'funcionario', 'escala-mes', 'escala-semana')
      await invalidarPonto(qc)
    },
  })
}
