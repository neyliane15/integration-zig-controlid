/**
 * Peças reutilizadas de integração: ícone por tipo, selo de status, botão "Sincronizar agora".
 * Dono: frontend-1 (usadas no painel e nas telas de integrações).
 */
import clsx from 'clsx'
import { Fingerprint, RefreshCw, ScanFace, Store } from 'lucide-react'
import type { EscopoSync, StatusUltimaExecucao, TipoIntegracao } from '@/tipos/banco'
import { useAvisos } from '../avisos'
import { Botao, Selo, type Tom } from '../ui'
import { useSincronizarAgora } from '@/consultas/integracoes'
import { rotuloStatusUltimaExecucao } from '@/lib/rotulos'

export function IconeIntegracao({ tipo, className }: { tipo: TipoIntegracao; className?: string }) {
  const Icone = tipo === 'zig' ? Store : tipo === 'controlid_acesso' ? ScanFace : Fingerprint
  return (
    <span className={clsx('grid size-10 shrink-0 place-items-center rounded-entrada border border-borda bg-cartao-2 text-ouro', className)}>
      <Icone aria-hidden className="size-[18px]" />
    </span>
  )
}

const TOM_STATUS: Record<StatusUltimaExecucao, Tom> = { sucesso: 'sucesso', parcial: 'alerta', erro: 'perigo' }

export function SeloStatusIntegracao({
  ativa,
  status,
  executando,
}: {
  ativa: boolean
  status: StatusUltimaExecucao | null
  executando?: boolean
}) {
  if (!ativa) return <Selo>Desativada</Selo>
  if (executando)
    return (
      <Selo tom="info">
        <RefreshCw aria-hidden className="animate-spin" /> Sincronizando
      </Selo>
    )
  if (!status) return <Selo>Nunca sincronizou</Selo>
  return <Selo tom={TOM_STATUS[status]}>{rotuloStatusUltimaExecucao[status]}</Selo>
}

export function BotaoSincronizar({
  empresaId,
  integracaoId,
  escopo = 'tudo',
  rotulo = 'Sincronizar agora',
  tamanho = 'p',
  variante = 'secundario',
  desabilitado,
}: {
  empresaId: string | null
  integracaoId?: string | null
  escopo?: EscopoSync
  rotulo?: string
  tamanho?: 'p' | 'm' | 'g'
  variante?: 'primario' | 'secundario' | 'fantasma'
  desabilitado?: boolean
}) {
  const avisos = useAvisos()
  const sincronizar = useSincronizarAgora()
  return (
    <Botao
      variante={variante}
      tamanho={tamanho}
      icone={<RefreshCw aria-hidden />}
      carregando={sincronizar.isPending}
      disabled={desabilitado}
      onClick={() =>
        sincronizar.mutate(
          { empresaId, integracaoId, escopo },
          {
            onSuccess: (n) =>
              n > 0
                ? avisos.sucesso(n === 1 ? 'Pedido enviado. A sincronização começa em até 1 minuto.' : `${n} pedidos enviados. Começam em até 1 minuto.`)
                : avisos.info('Já existe uma sincronização na fila para esta integração.'),
            onError: avisos.erro,
          },
        )
      }
    >
      {rotulo}
    </Botao>
  )
}
