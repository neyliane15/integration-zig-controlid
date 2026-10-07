/** Histórico das últimas execuções de sincronização (`sync_execucoes`). Dono: frontend-1. */
import { History } from 'lucide-react'
import type { StatusExecucao, SyncExecucao } from '@/tipos/banco'
import { useExecucoes } from '@/consultas/integracoes'
import { formatarDataHora, formatarRelativo } from '@/lib/formato'
import { rotuloGatilhoExecucao, rotuloStatusExecucao, rotuloTipoExecucao } from '@/lib/rotulos'
import { ErroCarga, Selo, Tabela, Vazio, type Coluna, type Tom } from '../ui'

const TOM: Record<StatusExecucao, Tom> = { executando: 'info', sucesso: 'sucesso', parcial: 'alerta', erro: 'perigo' }

function duracao(e: SyncExecucao): string {
  if (!e.finalizado_em) return '—'
  const s = Math.max(0, Math.round((new Date(e.finalizado_em).getTime() - new Date(e.iniciado_em).getTime()) / 1000))
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}min ${s % 60}s`
}

export function HistoricoExecucoes({
  empresaId,
  integracaoId,
  nomes,
}: {
  empresaId: string | null
  integracaoId?: string | null
  nomes?: Record<string, string>
}) {
  const consulta = useExecucoes(empresaId, integracaoId)
  if (consulta.isError) return <ErroCarga erro={consulta.error} aoTentar={() => void consulta.refetch()} />

  const colunas: Coluna<SyncExecucao>[] = [
    {
      id: 'quando',
      titulo: 'Quando',
      render: (e) => (
        <span className="flex flex-col">
          <span className="text-creme">{formatarRelativo(e.iniciado_em)}</span>
          <span className="numero text-xs text-lavanda">{formatarDataHora(e.iniciado_em)}</span>
        </span>
      ),
    },
    {
      id: 'tipo',
      titulo: 'Execução',
      render: (e) => (
        <span className="flex flex-col">
          <span>{rotuloTipoExecucao[e.tipo] ?? e.tipo}</span>
          <span className="text-xs text-lavanda">
            {!integracaoId && e.integracao_id && nomes?.[e.integracao_id] ? `${nomes[e.integracao_id]} · ` : ''}
            {rotuloGatilhoExecucao[e.gatilho] ?? e.gatilho}
          </span>
        </span>
      ),
    },
    {
      id: 'status',
      titulo: 'Status',
      render: (e) => <Selo tom={TOM[e.status]}>{rotuloStatusExecucao[e.status]}</Selo>,
    },
    {
      id: 'registros',
      titulo: 'Lidos / gravados',
      alinhar: 'direita',
      render: (e) => (
        <span className="numero text-sm">
          {e.registros_lidos} / {e.registros_gravados}
          {e.registros_ignorados > 0 && <span className="text-lavanda"> ({e.registros_ignorados} ign.)</span>}
        </span>
      ),
    },
    { id: 'duracao', titulo: 'Duração', alinhar: 'direita', ocultarNoCelular: true, render: (e) => <span className="numero text-sm text-lavanda">{duracao(e)}</span> },
    {
      id: 'erro',
      titulo: 'Detalhe',
      ocultarNoCelular: false,
      render: (e) => (e.erro ? <span className="line-clamp-2 text-sm text-perigo" title={e.erro}>{e.erro}</span> : <span className="text-lavanda-escuro">—</span>),
    },
  ]

  return (
    <Tabela
      colunas={colunas}
      linhas={consulta.data ?? []}
      chave={(e) => e.id}
      carregando={consulta.isPending}
      vazio={<Vazio icone={<History aria-hidden />} titulo="Nenhuma execução ainda" descricao="Quando o N8N sincronizar, o histórico aparece aqui." />}
    />
  )
}
