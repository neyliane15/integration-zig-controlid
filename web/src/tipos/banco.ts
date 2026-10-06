/**
 * Tipos do banco — espelho de docs/CONTRATO.md (§5, §6, §10).
 * Dono: frontend-1 (versão inicial escrita pelo coordenador a partir do contrato).
 *
 * Convenções: `date` → 'AAAA-MM-DD'; `time` → 'HH:MM:SS'; `timestamptz` → ISO 8601;
 * dinheiro em CENTAVOS (number inteiro); minutos em number inteiro; `numeric` → number.
 */

// ------------------------------------------------------------------ escalares
export type Uuid = string
export type DataISO = string
export type HoraISO = string
export type InstanteISO = string
export type Centavos = number
export type Minutos = number

// ---------------------------------------------------------------------- enums
export type Papel = 'master' | 'administrador' | 'gerente' | 'leitura'
export type TipoIntegracao = 'zig' | 'controlid_acesso' | 'controlid_rep'
export type StatusUltimaExecucao = 'sucesso' | 'parcial' | 'erro'
export type EscopoSync =
  | 'tudo'
  | 'funcionarios'
  | 'batidas'
  | 'vendas'
  | 'exportar_funcionarios'
  | 'apurar_ponto'
  | 'exportar_fechamento'
export type StatusSolicitacao = 'pendente' | 'em_andamento' | 'concluida' | 'erro' | 'cancelada'
export type TipoExecucao =
  | 'zig_lojas'
  | 'zig_faturamento'
  | 'zig_vendas'
  | 'zig_compradores'
  | 'zig_importar'
  | 'controlid_usuarios'
  | 'controlid_batidas'
  | 'controlid_exportar_usuarios'
  | 'apurar_ponto'
  | 'tarefas_gerar'
  | 'exportar_fechamento'
export type GatilhoExecucao = 'agendado' | 'manual' | 'webhook'
export type StatusExecucao = 'executando' | 'sucesso' | 'parcial' | 'erro'
export type VinculoControlId = 'automatico' | 'manual'
export type Recorrencia = 'diaria' | 'semanal' | 'mensal'
export type Prioridade = 'baixa' | 'normal' | 'alta'
export type StatusTarefa = 'pendente' | 'em_andamento' | 'concluida' | 'cancelada'
export type OrigemBatida = 'controlid_acesso' | 'controlid_rep' | 'manual'
export type SituacaoDia = 'completo' | 'incompleto' | 'ausente' | 'folga' | 'sem_escala' | 'abonado' | 'em_andamento'
export type TipoAlarme = 'batida_faltando' | 'batidas_impares' | 'sem_batida_dia_escalado' | 'atraso'
export type BatidaEsperada = 'entrada' | 'saida_intervalo' | 'volta_intervalo' | 'saida'
export type StatusAlarme = 'aberto' | 'justificado' | 'resolvido'
export type AcaoAjuste = 'incluir' | 'desconsiderar' | 'restaurar'
export type TipoAbono = 'folga' | 'feriado' | 'ferias' | 'atestado' | 'compensacao' | 'outro'
export type TipoLancamento = 'saldo_inicial' | 'ajuste' | 'compensacao' | 'pagamento'
export type TipoZig = 'Normal' | 'Couvert' | 'ZigCard' | 'Entrance' | 'Tip' | 'Outro'
export type StatusFechamento = 'rascunho' | 'fechado'
/** Adendo envio Control iD (A.2). */
export type StatusEnvioControlId = 'pendente' | 'enviando' | 'enviado' | 'erro' | 'aguardando'
export type OperacaoEnvio = 'salvar' | 'remover' | 'bloquear'
export type AlvoEnvio = 'funcionario' | 'horarios'

// ---------------------------------------------------------- tabelas (backend-1)
export interface Empresa {
  id: Uuid
  nome: string
  cnpj: string | null
  telefone: string | null
  cidade: string | null
  uf: string | null
  fuso: string
  virada_dia: HoraISO
  comissao_percentual_retencao: number
  ponto_alarme_atraso: boolean
  ponto_janela_duplicada_minutos: number
  ativa: boolean
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface Perfil {
  id: Uuid
  nome: string
  email: string
  papel: Papel
  empresa_id: Uuid | null
  funcionario_id: Uuid | null
  ativo: boolean
  criado_em: InstanteISO
}

export interface Configuracao {
  id: 1
  master_email: string | null
  cadastro_aberto: boolean
}

export interface Funcionario {
  id: Uuid
  empresa_id: Uuid
  nome: string
  apelido: string | null
  matricula: string | null
  cpf: string | null
  pis: string | null
  cargo: string | null
  telefone: string | null
  email: string | null
  zig_employee_name: string | null
  pontos_comissao: number
  participa_comissao: boolean
  data_admissao: DataISO | null
  data_desligamento: DataISO | null
  ativo: boolean
  observacoes: string | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface FuncionarioPontos {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  pontos: number
  vigente_desde: DataISO
  criado_por: Uuid | null
  criado_em: InstanteISO
}

export interface Jornada {
  id: Uuid
  empresa_id: Uuid
  nome: string
  tolerancia_batida_minutos: number
  tolerancia_diaria_minutos: number
  ativa: boolean
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface JornadaDia {
  id: Uuid
  empresa_id: Uuid
  jornada_id: Uuid
  /** 0 = domingo … 6 = sábado */
  dia_semana: number
  entrada: HoraISO
  saida_intervalo: HoraISO | null
  volta_intervalo: HoraISO | null
  saida: HoraISO
  /** gerada pelo banco (2 ou 4) — não enviar no insert/update */
  batidas_esperadas: 2 | 4
  /** gerada pelo banco — não enviar no insert/update */
  minutos_previstos: Minutos
}

export interface FuncionarioJornada {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  jornada_id: Uuid
  vigente_desde: DataISO
  criado_em: InstanteISO
}

/** Parâmetros visíveis por tipo de integração (§11.1). */
export interface ParametrosZig {
  rede?: string
  dias_retroativos?: number
}
/** Envio sistema → equipamento (adendo A.1). Padrão: desligado (opt-in por equipamento). */
export interface ParametrosEnvioControlId {
  ativo?: boolean
  foto?: boolean
  cartao?: boolean
  senha?: boolean
  horarios?: boolean
  ao_desligar?: 'remover' | 'bloquear'
}
export interface ParametrosControlIdAcesso {
  envio?: ParametrosEnvioControlId
  modelo?: string
  dias_retroativos?: number
  eventos_validos?: number[]
  relogio_em_hora_local?: boolean
}
export interface ParametrosControlIdRep {
  envio?: ParametrosEnvioControlId
  modelo?: string
  dias_retroativos?: number
  identificador?: 'cpf' | 'pis'
}
export type ParametrosIntegracao = ParametrosZig | ParametrosControlIdAcesso | ParametrosControlIdRep

/** Chaves de segredo permitidas por tipo (§11.1). Valores nunca voltam ao front. */
export type ChaveSegredoZig = 'token'
export type ChaveSegredoControlId = 'url' | 'login' | 'senha'
export type ChaveSegredo = ChaveSegredoZig | ChaveSegredoControlId

export interface Integracao {
  id: Uuid
  empresa_id: Uuid
  tipo: TipoIntegracao
  nome: string
  ativa: boolean
  parametros: ParametrosIntegracao
  intervalo_minutos: number
  cursor: Record<string, unknown>
  ultimo_sucesso_em: InstanteISO | null
  ultima_execucao_em: InstanteISO | null
  ultimo_status: StatusUltimaExecucao | null
  ultimo_erro: string | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface ControlIdUsuario {
  id: Uuid
  empresa_id: Uuid
  integracao_id: Uuid
  user_id_externo: string
  registration: string | null
  nome: string | null
  cpf: string | null
  pis: string | null
  funcionario_id: Uuid | null
  vinculo: VinculoControlId | null
  removido_no_equipamento: boolean
  visto_em: InstanteISO
  criado_em: InstanteISO
}

export interface SyncSolicitacao {
  id: Uuid
  empresa_id: Uuid
  integracao_id: Uuid | null
  escopo: EscopoSync
  data_inicio: DataISO | null
  data_fim: DataISO | null
  parametros: Record<string, unknown>
  status: StatusSolicitacao
  solicitado_por: Uuid | null
  solicitado_em: InstanteISO
  pego_em: InstanteISO | null
  concluido_em: InstanteISO | null
  execucao_id: Uuid | null
  mensagem: string | null
}

export interface SyncExecucao {
  id: Uuid
  empresa_id: Uuid | null
  integracao_id: Uuid | null
  solicitacao_id: Uuid | null
  tipo: TipoExecucao
  gatilho: GatilhoExecucao
  workflow: string
  n8n_execution_id: string | null
  status: StatusExecucao
  iniciado_em: InstanteISO
  finalizado_em: InstanteISO | null
  periodo_inicio: DataISO | null
  periodo_fim: DataISO | null
  registros_lidos: number
  registros_gravados: number
  registros_ignorados: number
  tentativas: number
  erro: string | null
  detalhes: Record<string, unknown>
}

export interface TarefaRotina {
  id: Uuid
  empresa_id: Uuid
  titulo: string
  descricao: string | null
  recorrencia: Recorrencia
  dias_semana: number[]
  dia_mes: number | null
  horario_limite: HoraISO | null
  prioridade: Prioridade
  responsavel_funcionario_id: Uuid | null
  responsavel_perfil_id: Uuid | null
  ativa: boolean
  criado_por: Uuid | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface TarefaRotinaItem {
  id: Uuid
  empresa_id: Uuid
  rotina_id: Uuid
  ordem: number
  texto: string
}

export interface Tarefa {
  id: Uuid
  empresa_id: Uuid
  rotina_id: Uuid | null
  data: DataISO
  titulo: string
  descricao: string | null
  horario_limite: HoraISO | null
  prioridade: Prioridade
  status: StatusTarefa
  responsavel_funcionario_id: Uuid | null
  responsavel_perfil_id: Uuid | null
  concluida_por: Uuid | null
  concluida_em: InstanteISO | null
  criado_por: Uuid | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface TarefaItem {
  id: Uuid
  empresa_id: Uuid
  tarefa_id: Uuid
  ordem: number
  texto: string
  feito: boolean
  feito_por: Uuid | null
  feito_em: InstanteISO | null
}

// ------------------------------------------- envio ao Control iD (adendo, b1)
export interface ControlIdEnvio {
  id: Uuid
  empresa_id: Uuid
  integracao_id: Uuid
  alvo: AlvoEnvio
  funcionario_id: Uuid | null
  funcionario_nome: string | null
  operacao: OperacaoEnvio
  status: StatusEnvioControlId
  versao: number
  assinatura: string
  assinatura_enviada: string | null
  id_remoto: string | null
  mapa_remoto: Record<string, { time_zone_id: number; access_rule_id: number }>
  tentativas: number
  erro: string | null
  pendente_desde: InstanteISO | null
  pego_em: InstanteISO | null
  enviado_em: InstanteISO | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface ControlIdHorario {
  id: Uuid
  empresa_id: Uuid
  nome: string
  ativo: boolean
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface ControlIdHorarioFaixa {
  id: Uuid
  empresa_id: Uuid
  horario_id: Uuid
  /** 0 = domingo … 6 = sábado */
  dia_semana: number
  inicio: HoraISO
  /** '23:59:59' = até o fim do dia */
  fim: HoraISO
}

export interface FuncionarioHorario {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  horario_id: Uuid
  criado_em: InstanteISO
}

export interface FuncionarioFoto {
  funcionario_id: Uuid
  empresa_id: Uuid
  bucket: string
  caminho: string
  atualizado_por: Uuid | null
  atualizado_em: InstanteISO
}

/** Retorno de `funcionario_credenciais` — nunca a senha nem o número completo do cartão. */
export interface CredenciaisFuncionario {
  senha_definida: boolean
  cartoes: { id: Uuid; final: string; criado_em: InstanteISO }[]
  foto: { caminho: string; atualizado_em: InstanteISO } | null
}

// ---------------------------------------------------------- tabelas (backend-2)
export interface PontoBatida {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid | null
  integracao_id: Uuid | null
  origem: OrigemBatida
  id_externo: string | null
  pessoa_externa: string | null
  instante: InstanteISO
  data_trabalho: DataISO
  desconsiderada: boolean
  motivo: string | null
  criado_por: Uuid | null
  criado_em: InstanteISO
}

export interface PontoDia {
  funcionario_id: Uuid
  data: DataISO
  empresa_id: Uuid
  jornada_id: Uuid | null
  abono_tipo: TipoAbono | null
  batidas_esperadas: number
  batidas_validas: number
  batidas_duplicadas: number
  previsto_minutos: Minutos
  trabalhado_minutos: Minutos
  saldo_minutos: Minutos
  atraso_minutos: Minutos
  primeira_batida: InstanteISO | null
  ultima_batida: InstanteISO | null
  situacao: SituacaoDia
  encerrado: boolean
  alarmes_abertos: number
  apurado_em: InstanteISO
}

export interface PontoAlarme {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  data: DataISO
  tipo: TipoAlarme
  batida_esperada: BatidaEsperada | ''
  horario_previsto: InstanteISO | null
  minutos: number | null
  detalhe: string
  status: StatusAlarme
  justificativa: string | null
  justificado_por: Uuid | null
  justificado_em: InstanteISO | null
  resolvido_em: InstanteISO | null
  resolvido_automaticamente: boolean
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

export interface PontoAjuste {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  batida_id: Uuid | null
  acao: AcaoAjuste
  instante: InstanteISO
  motivo: string
  feito_por: Uuid | null
  feito_por_nome: string
  feito_em: InstanteISO
}

export interface PontoAbono {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid | null
  data: DataISO
  tipo: TipoAbono
  motivo: string | null
  criado_por: Uuid | null
  criado_em: InstanteISO
}

export interface BancoHorasLancamento {
  id: Uuid
  empresa_id: Uuid
  funcionario_id: Uuid
  data: DataISO
  tipo: TipoLancamento
  minutos: Minutos
  motivo: string
  criado_por: Uuid | null
  criado_por_nome: string
  criado_em: InstanteISO
}

export interface ZigLoja {
  id: Uuid
  empresa_id: Uuid
  integracao_id: Uuid
  loja_id_externo: string
  nome: string
  sincronizar: boolean
  visto_em: InstanteISO
  criado_em: InstanteISO
}

export interface ZigVendaItem {
  id: number
  empresa_id: Uuid
  loja_id_externo: string
  data_operacao: DataISO
  transaction_id: string
  transaction_date: InstanteISO | null
  event_id: string | null
  event_date: DataISO | null
  invoice_id: string | null
  product_id: string | null
  product_sku: string | null
  product_name: string | null
  product_category: string | null
  tipo: TipoZig
  tipo_original: string | null
  unit_value: Centavos
  quantidade: number
  fractional_amount: number | null
  fraction_unit: string | null
  discount_value: Centavos
  valor_total: Centavos
  employee_name: string | null
  additions: unknown[]
  importado_em: InstanteISO
}

export interface ZigFaturamento {
  id: number
  empresa_id: Uuid
  loja_id_externo: string
  data_operacao: DataISO
  event_id: string | null
  event_date: DataISO | null
  payment_id: number
  payment_name: string
  valor: Centavos
  importado_em: InstanteISO
}

export interface ComissaoFechamento {
  id: Uuid
  empresa_id: Uuid
  titulo: string
  data_inicio: DataISO
  data_fim: DataISO
  loja_id_externo: string | null
  status: StatusFechamento
  servico_zig_centavos: Centavos
  servico_ajuste_centavos: Centavos
  servico_bruto_centavos: Centavos
  percentual_retencao: number
  retencao_centavos: Centavos
  base_distribuivel_centavos: Centavos
  proporcional_dias: boolean
  dias_periodo: number
  soma_pontos_efetivos: number
  valor_ponto_centavos: number | null
  observacoes: string | null
  criado_por: Uuid | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
  calculado_em: InstanteISO | null
  fechado_por: Uuid | null
  fechado_em: InstanteISO | null
}

export interface ComissaoItem {
  id: Uuid
  empresa_id: Uuid
  fechamento_id: Uuid
  funcionario_id: Uuid | null
  funcionario_nome: string
  cargo: string | null
  incluido: boolean
  pontos: number
  dias_trabalhados: number
  pontos_efetivos: number
  valor_centavos: Centavos
  criado_em: InstanteISO
}

// ------------------------------------------------------- retornos de RPC (b2)
export interface BatidaEspelho {
  id: Uuid
  instante: InstanteISO
  origem: OrigemBatida
  desconsiderada: boolean
  duplicada: boolean
  motivo: string | null
}

export interface AlarmeEspelho {
  id: Uuid
  tipo: TipoAlarme
  batida_esperada: BatidaEsperada | ''
  status: StatusAlarme
  detalhe: string
  justificativa: string | null
}

export interface EsperadaEspelho {
  batida: BatidaEsperada
  instante: InstanteISO
}

export interface LinhaEspelho {
  data: DataISO
  dia_semana: number
  situacao: SituacaoDia
  encerrado: boolean
  abono_tipo: TipoAbono | null
  jornada_nome: string | null
  previsto_minutos: Minutos
  trabalhado_minutos: Minutos
  saldo_minutos: Minutos
  atraso_minutos: Minutos
  batidas: BatidaEspelho[]
  alarmes: AlarmeEspelho[]
  esperadas: EsperadaEspelho[]
}

export interface LinhaPontoDiaEmpresa {
  funcionario_id: Uuid
  funcionario_nome: string
  cargo: string | null
  situacao: SituacaoDia
  encerrado: boolean
  previsto_minutos: Minutos
  trabalhado_minutos: Minutos
  saldo_minutos: Minutos
  atraso_minutos: Minutos
  batidas: BatidaEspelho[]
  alarmes_abertos: number
}

export interface LinhaBancoHorasResumo {
  funcionario_id: Uuid
  funcionario_nome: string
  cargo: string | null
  saldo_minutos: Minutos
  saldo_mes_minutos: Minutos
  ultimo_dia_apurado: DataISO | null
}

export interface LinhaExtratoBancoHoras {
  data: DataISO
  tipo: 'saldo_anterior' | 'dia' | TipoLancamento
  descricao: string
  minutos: Minutos
  saldo_acumulado: Minutos
  referencia_id: Uuid | null
}

export interface VendasResumo {
  faturamento: Centavos
  vendas: Centavos
  servico: Centavos
  descontos: Centavos
  transacoes: number
  servico_compradores: Centavos
}

export interface FaturamentoPorDia {
  data: DataISO
  valor: Centavos
}

export interface FaturamentoPorForma {
  payment_id: number
  payment_name: string
  valor: Centavos
}

export interface VendaPorGarcom {
  employee_name: string | null
  funcionario_id: Uuid | null
  funcionario_nome: string | null
  quantidade: number
  valor_vendas: Centavos
  valor_servico: Centavos
  transacoes: number
}

export interface PainelDoDia {
  empresa_id: Uuid
  dia_trabalho: DataISO
  ontem: DataISO
  faturamento: { hoje: Centavos; ontem: Centavos; mes: Centavos; tem_zig: boolean }
  servico: { ontem: Centavos; mes: Centavos }
  ponto: {
    alarmes_abertos: number
    alarmes: {
      id: Uuid
      funcionario_id: Uuid
      funcionario_nome: string
      data: DataISO
      tipo: TipoAlarme
      batida_esperada: BatidaEsperada | ''
      detalhe: string
    }[]
    presentes_agora: number
    escalados_hoje: number
    batidas_sem_funcionario: number
  }
  tarefas: { total: number; concluidas: number; pendentes: number; atrasadas: number }
  sincronizacao: {
    integracao_id: Uuid
    tipo: TipoIntegracao
    nome: string
    ativa: boolean
    ultimo_sucesso_em: InstanteISO | null
    ultimo_status: StatusUltimaExecucao | null
    ultimo_erro: string | null
    executando: boolean
  }[]
}

// --------------------------------------------------------- mapa das RPCs [api]
type ArgsPeriodoVendas = { p_inicio: DataISO; p_fim: DataISO; p_loja?: string | null; p_empresa?: Uuid | null }

/** Nome → { args, retorno }. Só RPCs `[api]` (as `[servico]` são do N8N). */
export interface Rpcs {
  // usuários e empresas (b1)
  admin_criar_usuario: {
    args: { p_email: string; p_senha: string; p_nome: string; p_papel: Papel; p_empresa_id: Uuid | null; p_funcionario_id?: Uuid | null }
    retorno: Uuid
  }
  admin_atualizar_usuario: {
    args: { p_usuario: Uuid; p_nome: string; p_papel: Papel; p_ativo: boolean; p_funcionario_id?: Uuid | null }
    retorno: null
  }
  admin_redefinir_senha: { args: { p_usuario: Uuid; p_senha: string }; retorno: null }
  admin_excluir_usuario: { args: { p_usuario: Uuid }; retorno: null }
  atualizar_meu_perfil: { args: { p_nome: string }; retorno: null }
  criar_minha_empresa: { args: { p_nome: string; p_cnpj?: string | null }; retorno: Uuid }
  master_criar_empresa: {
    args: { p_nome: string; p_cnpj: string | null; p_admin_email: string; p_admin_senha: string; p_admin_nome: string }
    retorno: Uuid
  }
  // cadastros, integrações, sync (b1)
  dia_de_trabalho: { args: { p_instante: InstanteISO; p_empresa: Uuid }; retorno: DataISO }
  dia_de_trabalho_atual: { args: { p_empresa?: Uuid | null }; retorno: DataISO }
  pontos_vigentes: { args: { p_funcionario: Uuid; p_data: DataISO }; retorno: number }
  funcionario_vincular_controlid: { args: { p_controlid_usuario: Uuid; p_funcionario: Uuid | null }; retorno: null }
  integracao_definir_segredos: { args: { p_integracao: Uuid; p_segredos: Partial<Record<ChaveSegredo, string | null>> }; retorno: null }
  integracao_segredos_preenchidos: { args: { p_integracao: Uuid }; retorno: ChaveSegredo[] }
  sync_solicitar: {
    args: {
      p_integracao?: Uuid | null
      p_escopo?: EscopoSync
      p_data_inicio?: DataISO | null
      p_data_fim?: DataISO | null
      p_parametros?: Record<string, unknown>
      p_empresa?: Uuid | null
    }
    retorno: number
  }
  // envio ao Control iD (adendo, b1)
  funcionario_definir_senha: { args: { p_funcionario: Uuid; p_senha: string | null }; retorno: null }
  funcionario_adicionar_cartao: { args: { p_funcionario: Uuid; p_numero: string }; retorno: Uuid }
  funcionario_remover_cartao: { args: { p_cartao: Uuid }; retorno: null }
  funcionario_definir_foto: { args: { p_funcionario: Uuid; p_caminho: string | null }; retorno: null }
  funcionario_credenciais: { args: { p_funcionario: Uuid }; retorno: CredenciaisFuncionario }
  controlid_envio_reenviar: {
    args: { p_integracao?: Uuid | null; p_funcionario?: Uuid | null; p_empresa?: Uuid | null }
    retorno: number
  }
  // tarefas (b1)
  tarefas_gerar_do_dia: { args: { p_data?: DataISO | null; p_empresa?: Uuid | null }; retorno: number }
  tarefa_mudar_status: { args: { p_tarefa: Uuid; p_status: StatusTarefa }; retorno: null }
  tarefa_marcar_item: { args: { p_item: Uuid; p_feito: boolean }; retorno: null }
  // ponto e banco de horas (b2)
  ponto_espelho: { args: { p_funcionario: Uuid; p_inicio: DataISO; p_fim: DataISO }; retorno: LinhaEspelho[] }
  ponto_dia_empresa: { args: { p_data?: DataISO | null; p_empresa?: Uuid | null }; retorno: LinhaPontoDiaEmpresa[] }
  ponto_reapurar: {
    args: { p_inicio: DataISO; p_fim: DataISO; p_funcionario?: Uuid | null; p_empresa?: Uuid | null }
    retorno: number
  }
  ponto_incluir_batida: { args: { p_funcionario: Uuid; p_instante: InstanteISO; p_motivo: string }; retorno: Uuid }
  ponto_desconsiderar_batida: { args: { p_batida: Uuid; p_motivo: string }; retorno: null }
  ponto_restaurar_batida: { args: { p_batida: Uuid; p_motivo: string }; retorno: null }
  ponto_justificar_alarme: { args: { p_alarme: Uuid; p_justificativa: string }; retorno: null }
  ponto_reabrir_alarme: { args: { p_alarme: Uuid }; retorno: null }
  ponto_abonar: {
    args: {
      p_inicio: DataISO
      p_fim: DataISO
      p_tipo: TipoAbono
      p_motivo?: string | null
      p_funcionario?: Uuid | null
      p_empresa?: Uuid | null
    }
    retorno: number
  }
  ponto_remover_abono: { args: { p_abono: Uuid }; retorno: null }
  banco_horas_saldo: { args: { p_funcionario: Uuid; p_ate?: DataISO | null }; retorno: number }
  banco_horas_resumo: { args: { p_ate?: DataISO | null; p_empresa?: Uuid | null }; retorno: LinhaBancoHorasResumo[] }
  banco_horas_extrato: {
    args: { p_funcionario: Uuid; p_inicio: DataISO; p_fim: DataISO }
    retorno: LinhaExtratoBancoHoras[]
  }
  banco_horas_lancar: {
    args: { p_funcionario: Uuid; p_data: DataISO; p_tipo: TipoLancamento; p_minutos: number; p_motivo: string }
    retorno: Uuid
  }
  banco_horas_excluir_lancamento: { args: { p_lancamento: Uuid }; retorno: null }
  // vendas (b2)
  vendas_resumo: { args: ArgsPeriodoVendas; retorno: VendasResumo[] }
  vendas_faturamento_por_dia: { args: ArgsPeriodoVendas; retorno: FaturamentoPorDia[] }
  vendas_faturamento_por_forma: { args: ArgsPeriodoVendas; retorno: FaturamentoPorForma[] }
  vendas_por_garcom: { args: ArgsPeriodoVendas; retorno: VendaPorGarcom[] }
  // comissões (b2)
  comissao_criar_fechamento: {
    args: {
      p_data_inicio: DataISO
      p_data_fim: DataISO
      p_titulo?: string | null
      p_loja?: string | null
      p_proporcional_dias?: boolean
      p_empresa?: Uuid | null
    }
    retorno: Uuid
  }
  comissao_atualizar_fechamento: {
    args: {
      p_fechamento: Uuid
      p_titulo: string
      p_servico_ajuste_centavos: Centavos
      p_percentual_retencao: number
      p_proporcional_dias: boolean
      p_observacoes: string | null
    }
    retorno: null
  }
  comissao_definir_item: {
    args: { p_fechamento: Uuid; p_funcionario: Uuid; p_pontos: number; p_incluido?: boolean }
    retorno: null
  }
  comissao_remover_item: { args: { p_fechamento: Uuid; p_funcionario: Uuid }; retorno: null }
  comissao_recalcular: { args: { p_fechamento: Uuid }; retorno: null }
  comissao_fechar: { args: { p_fechamento: Uuid }; retorno: null }
  comissao_excluir_rascunho: { args: { p_fechamento: Uuid }; retorno: null }
  // painel (b2)
  painel_do_dia: { args: { p_empresa?: Uuid | null }; retorno: PainelDoDia }
}

export type NomeRpc = keyof Rpcs
