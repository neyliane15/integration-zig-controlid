/**
 * Selos e textos de domínio (ponto, banco de horas, envio Control iD). Dono: frontend-2.
 */
import clsx from 'clsx'
import { AlertTriangle, Check, Clock, CloudOff, Loader2, Send, XCircle } from 'lucide-react'
import type { BatidaEsperada, SituacaoDia, StatusAlarme, StatusEnvioControlId, TipoAlarme } from '@/tipos/banco'
import { Selo, type Tom } from '@/componentes/ui'
import { formatarMinutos } from '@/lib/formato'
import { rotuloBatidaEsperada, rotuloSituacaoDia, rotuloStatusAlarme, rotuloStatusEnvio, rotuloTipoAlarme } from '@/lib/rotulos'

export const TOM_SITUACAO: Record<SituacaoDia, Tom> = {
  completo: 'sucesso',
  incompleto: 'alerta',
  ausente: 'perigo',
  folga: 'neutro',
  sem_escala: 'neutro',
  abonado: 'info',
  em_andamento: 'ouro',
}

export function SeloSituacaoDia({ situacao }: { situacao: SituacaoDia }) {
  return <Selo tom={TOM_SITUACAO[situacao]}>{rotuloSituacaoDia[situacao]}</Selo>
}

export const TOM_ALARME: Record<TipoAlarme, Tom> = {
  sem_batida_dia_escalado: 'perigo',
  batida_faltando: 'alerta',
  batidas_impares: 'alerta',
  atraso: 'info',
}

const TOM_STATUS_ALARME: Record<StatusAlarme, Tom> = { aberto: 'alerta', justificado: 'info', resolvido: 'sucesso' }

/** Selo do tipo de alarme; com `batidaEsperada`, diz qual batida (ex.: "Batida faltando · Volta do intervalo"). */
export function SeloAlarme({
  tipo,
  batidaEsperada,
  status,
}: {
  tipo: TipoAlarme
  batidaEsperada?: BatidaEsperada | '' | null
  status?: StatusAlarme
}) {
  const fechado = status && status !== 'aberto'
  return (
    <Selo tom={fechado ? 'neutro' : TOM_ALARME[tipo]}>
      <AlertTriangle aria-hidden />
      {rotuloTipoAlarme[tipo]}
      {batidaEsperada ? ` · ${rotuloBatidaEsperada[batidaEsperada]}` : ''}
    </Selo>
  )
}

export function SeloStatusAlarme({ status }: { status: StatusAlarme }) {
  return <Selo tom={TOM_STATUS_ALARME[status]}>{rotuloStatusAlarme[status]}</Selo>
}

const TOM_ENVIO: Record<StatusEnvioControlId, Tom> = {
  pendente: 'ouro',
  enviando: 'info',
  enviado: 'sucesso',
  erro: 'perigo',
  aguardando: 'alerta',
}

export function SeloStatusEnvio({ status }: { status: StatusEnvioControlId | 'desligado' | 'sem_envio' }) {
  if (status === 'desligado')
    return (
      <Selo tom="neutro">
        <CloudOff aria-hidden />
        Envio desligado
      </Selo>
    )
  if (status === 'sem_envio') return <Selo tom="neutro">Nada a enviar</Selo>
  const Icone = { pendente: Clock, enviando: Loader2, enviado: Check, erro: XCircle, aguardando: Send }[status]
  return (
    <Selo tom={TOM_ENVIO[status]}>
      <Icone aria-hidden className={status === 'enviando' ? 'animate-spin' : undefined} />
      {rotuloStatusEnvio[status]}
    </Selo>
  )
}

/** Saldo em minutos com cor: positivo verde, negativo vermelho, zero neutro. */
export function TextoSaldo({ minutos, className, provisorio }: { minutos: number; className?: string; provisorio?: boolean }) {
  return (
    <span
      className={clsx(
        'numero whitespace-nowrap',
        provisorio ? 'text-lavanda' : minutos > 0 ? 'text-sucesso' : minutos < 0 ? 'text-perigo' : 'text-creme',
        className,
      )}
      title={provisorio ? 'Provisório: o dia ainda não foi encerrado' : undefined}
    >
      {formatarMinutos(minutos, { sinal: true })}
    </span>
  )
}

/** "3/4" batidas, em alerta quando faltam ou é ímpar. */
export function ContagemBatidas({ validas, esperadas, encerrado = true }: { validas: number; esperadas: number; encerrado?: boolean }) {
  const problema = encerrado && ((esperadas > 0 && validas < esperadas) || validas % 2 === 1)
  return (
    <span
      className={clsx('numero inline-flex items-baseline gap-0.5 whitespace-nowrap font-semibold', problema ? 'text-alerta' : 'text-creme')}
      aria-label={`${validas} de ${esperadas} batidas`}
      title={`${validas} batida(s) válida(s) de ${esperadas} esperada(s)`}
    >
      {validas}
      <span className="text-lavanda">/{esperadas}</span>
    </span>
  )
}
