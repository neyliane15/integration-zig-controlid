/**
 * Rótulos exibidos para cada enum de tipos/banco.ts (contrato §14.7). Dono: frontend-1.
 * Convenção de nome: `rotulo<NomeDoTipo>` → Record<Tipo, string>.
 */
import type {
  AcaoAjuste,
  BatidaEsperada,
  EscopoSync,
  GatilhoExecucao,
  OperacaoEnvio,
  OrigemBatida,
  Papel,
  Prioridade,
  Recorrencia,
  SituacaoDia,
  StatusAlarme,
  StatusEnvioControlId,
  StatusExecucao,
  StatusFechamento,
  StatusSolicitacao,
  StatusTarefa,
  StatusUltimaExecucao,
  TipoAbono,
  TipoAlarme,
  TipoExecucao,
  TipoIntegracao,
  TipoLancamento,
  TipoZig,
  VinculoControlId,
} from '@/tipos/banco'

export const rotuloPapel: Record<Papel, string> = {
  master: 'Master',
  administrador: 'Administrador',
  gerente: 'Gerente',
  leitura: 'Somente leitura',
}

export const rotuloTipoAlarme: Record<TipoAlarme, string> = {
  batida_faltando: 'Batida faltando',
  batidas_impares: 'Batidas ímpares',
  sem_batida_dia_escalado: 'Sem batidas no dia escalado',
  atraso: 'Atraso',
}

export const rotuloBatidaEsperada: Record<BatidaEsperada, string> = {
  entrada: 'Entrada',
  saida_intervalo: 'Saída p/ intervalo',
  volta_intervalo: 'Volta do intervalo',
  saida: 'Saída',
}

export const rotuloStatusAlarme: Record<StatusAlarme, string> = {
  aberto: 'Aberto',
  justificado: 'Justificado',
  resolvido: 'Resolvido',
}

export const rotuloSituacaoDia: Record<SituacaoDia, string> = {
  completo: 'Completo',
  incompleto: 'Incompleto',
  ausente: 'Ausente',
  folga: 'Folga',
  sem_escala: 'Sem escala',
  abonado: 'Abonado',
  em_andamento: 'Em andamento',
}

export const rotuloOrigemBatida: Record<OrigemBatida, string> = {
  controlid_acesso: 'Control iD (acesso)',
  controlid_rep: 'Control iD (REP)',
  manual: 'Manual',
}

export const rotuloTipoAbono: Record<TipoAbono, string> = {
  folga: 'Folga',
  feriado: 'Feriado',
  ferias: 'Férias',
  atestado: 'Atestado',
  compensacao: 'Compensação',
  outro: 'Outro',
}

export const rotuloTipoLancamento: Record<TipoLancamento, string> = {
  saldo_inicial: 'Saldo inicial',
  ajuste: 'Ajuste',
  compensacao: 'Compensação',
  pagamento: 'Pagamento em folha',
}

export const rotuloTipoIntegracao: Record<TipoIntegracao, string> = {
  zig: 'Zig',
  controlid_acesso: 'Control iD — controle de acesso',
  controlid_rep: 'Control iD — relógio de ponto (REP)',
}

export const rotuloStatusExecucao: Record<StatusExecucao, string> = {
  executando: 'Executando',
  sucesso: 'Sucesso',
  parcial: 'Parcial',
  erro: 'Erro',
}

export const rotuloStatusUltimaExecucao: Record<StatusUltimaExecucao, string> = {
  sucesso: 'Sucesso',
  parcial: 'Parcial',
  erro: 'Erro',
}

export const rotuloStatusSolicitacao: Record<StatusSolicitacao, string> = {
  pendente: 'Na fila',
  em_andamento: 'Sincronizando',
  concluida: 'Concluída',
  erro: 'Erro',
  cancelada: 'Cancelada',
}

export const rotuloStatusTarefa: Record<StatusTarefa, string> = {
  pendente: 'Pendente',
  em_andamento: 'Em andamento',
  concluida: 'Concluída',
  cancelada: 'Cancelada',
}

export const rotuloPrioridade: Record<Prioridade, string> = {
  baixa: 'Baixa',
  normal: 'Normal',
  alta: 'Alta',
}

export const rotuloStatusFechamento: Record<StatusFechamento, string> = {
  rascunho: 'Rascunho',
  fechado: 'Fechado',
}

export const rotuloEscopoSync: Record<EscopoSync, string> = {
  tudo: 'Tudo',
  funcionarios: 'Usuários do equipamento',
  batidas: 'Batidas',
  vendas: 'Vendas',
  exportar_funcionarios: 'Enviar funcionários ao equipamento',
  apurar_ponto: 'Recalcular ponto',
  exportar_fechamento: 'Enviar fechamento por e-mail',
}

export const rotuloTipoExecucao: Record<TipoExecucao, string> = {
  zig_lojas: 'Zig · lojas',
  zig_faturamento: 'Zig · faturamento',
  zig_vendas: 'Zig · vendas',
  zig_compradores: 'Zig · compradores',
  zig_importar: 'Zig · importação',
  controlid_usuarios: 'Control iD · usuários',
  controlid_batidas: 'Control iD · batidas',
  controlid_exportar_usuarios: 'Control iD · envio de funcionários',
  apurar_ponto: 'Apuração do ponto',
  tarefas_gerar: 'Geração de tarefas',
  exportar_fechamento: 'Envio de fechamento',
}

export const rotuloGatilhoExecucao: Record<GatilhoExecucao, string> = {
  agendado: 'Agendado',
  manual: 'Manual',
  webhook: 'Webhook',
}

export const rotuloRecorrencia: Record<Recorrencia, string> = {
  diaria: 'Diária',
  semanal: 'Semanal',
  mensal: 'Mensal',
}

export const rotuloVinculoControlId: Record<VinculoControlId, string> = {
  automatico: 'Automático',
  manual: 'Manual',
}

export const rotuloAcaoAjuste: Record<AcaoAjuste, string> = {
  incluir: 'Inclusão',
  desconsiderar: 'Desconsiderada',
  restaurar: 'Restaurada',
}

export const rotuloTipoZig: Record<TipoZig, string> = {
  Normal: 'Produto',
  Couvert: 'Couvert',
  ZigCard: 'ZigCard',
  Entrance: 'Entrada',
  Tip: 'Serviço',
  Outro: 'Outro',
}

/** 0 = domingo … 6 = sábado. */
export const rotuloDiaSemana = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'] as const
export const rotuloDiaSemanaCurto = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'] as const

export const rotuloStatusEnvio: Record<StatusEnvioControlId, string> = {
  pendente: 'Pendente',
  enviando: 'Enviando',
  enviado: 'Enviado',
  erro: 'Erro',
  aguardando: 'Aguardando',
}

export const rotuloOperacaoEnvio: Record<OperacaoEnvio, string> = {
  salvar: 'Cadastrar/atualizar',
  remover: 'Remover',
  bloquear: 'Bloquear',
}

export const rotuloAoDesligar: Record<'remover' | 'bloquear', string> = {
  remover: 'Remover do equipamento',
  bloquear: 'Bloquear (manter cadastro)',
}
