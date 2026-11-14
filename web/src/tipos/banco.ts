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
export type TipoIntegracao = 'zig' | 'controlid_acesso' | 'controlid_rep' | 'tagme'
export type StatusUltimaExecucao = 'sucesso' | 'parcial' | 'erro'
export type EscopoSync =
  | 'tudo'
  | 'funcionarios'
  | 'batidas'
  | 'vendas'
  | 'exportar_funcionarios'
  | 'apurar_ponto'
  | 'exportar_fechamento'
  | 'reservas'
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
  | 'tagme_importar'
export type GatilhoExecucao = 'agendado' | 'manual' | 'webhook'
export type StatusExecucao = 'executando' | 'sucesso' | 'parcial' | 'erro'
export type VinculoControlId = 'automatico' | 'manual'
export type Recorrencia = 'diaria' | 'semanal' | 'mensal'
export type Prioridade = 'baixa' | 'normal' | 'alta'
export type StatusTarefa = 'pendente' | 'em_andamento' | 'concluida' | 'cancelada'
export type OrigemBatida = 'controlid_acesso' | 'controlid_rep' | 'manual'
export type SituacaoDia = 'completo' | 'incompleto' | 'ausente' | 'folga' | 'sem_escala' | 'abonado' | 'em_andamento' | 'suspenso'
export type TipoAlarme = 'batida_faltando' | 'batidas_impares' | 'sem_batida_dia_escalado' | 'atraso'
export type BatidaEsperada = 'entrada' | 'saida_intervalo' | 'volta_intervalo' | 'saida'
export type StatusAlarme = 'aberto' | 'justificado' | 'resolvido'
export type AcaoAjuste = 'incluir' | 'desconsiderar' | 'restaurar'
export type TipoAbono = 'folga' | 'feriado' | 'ferias' | 'atestado' | 'compensacao' | 'outro' | 'suspensao'
export type TipoLancamento = 'saldo_inicial' | 'ajuste' | 'compensacao' | 'pagamento'
export type TipoZig = 'Normal' | 'Couvert' | 'ZigCard' | 'Entrance' | 'Tip' | 'Outro'
export type StatusFechamento = 'rascunho' | 'fechado'
export type ModoRateio = 'diario' | 'periodo'
export type TipoParticipanteComissao = 'funcionario' | 'extra'
export type TipoDiaria = 'extra' | 'funcionario'
/** Adendo envio Control iD (A.2). */
export type StatusEnvioControlId = 'pendente' | 'enviando' | 'enviado' | 'erro' | 'aguardando'
export type OperacaoEnvio = 'salvar' | 'remover' | 'bloquear'
export type AlvoEnvio = 'funcionario' | 'horarios'
/** Adendo extras/ocorrências/reservas. */
export type TipoOcorrencia = 'advertencia' | 'suspensao'
export type StatusReserva = 'confirmada' | 'pendente' | 'cancelada' | 'sentada' | 'concluida' | 'nao_compareceu'
export type OrigemReserva = 'tagme' | 'manual' | 'importacao'

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
/** Adendo R.1 — o N8N pode acrescentar chaves (ex.: `mapeamento`); o front preserva as desconhecidas. */
export interface ParametrosTagme {
  url_base?: string
  restaurante_id?: string
  dias_retroativos?: number
  dias_a_frente?: number
  [chave: string]: unknown
}
export type ParametrosIntegracao = ParametrosZig | ParametrosControlIdAcesso | ParametrosControlIdRep | ParametrosTagme

/** Chaves de segredo permitidas por tipo (§11.1). Valores nunca voltam ao front. */
export type ChaveSegredoZig = 'token'
export type ChaveSegredoControlId = 'url' | 'login' | 'senha'
export type ChaveSegredoTagme = 'token' | 'cliente_id' | 'cliente_segredo'
export type ChaveSegredo = ChaveSegredoZig | ChaveSegredoControlId | ChaveSegredoTagme

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
  /** adendo E.3 — 'diario' (padrão dos novos) ou 'periodo' (§9) */
  modo_rateio: ModoRateio
  /** modo diário: dias com base > 0 rateados pelo fallback (sem presença registrada) */
  dias_sem_presenca: number
  /** modo diário: dias com base > 0 sem ninguém para ratear (fechar é recusado) */
  dias_sem_participantes: number
}

export interface ComissaoItem {
  id: Uuid
  empresa_id: Uuid
  fechamento_id: Uuid
  /** adendo E.3: participante = funcionário OU extra */
  tipo: TipoParticipanteComissao
  funcionario_id: Uuid | null
  extra_id: Uuid | null
  /** snapshot do nome (funcionário ou extra) */
  funcionario_nome: string
  cargo: string | null
  incluido: boolean
  pontos: number
  /** funcionário: pontos fixados no rascunho (senão: vigentes de cada dia) */
  pontos_manual: boolean
  /** = dias_presentes (compatibilidade) */
  dias_trabalhados: number
  /** funcionário: dias com batida válida no período; extra: dias lançados */
  dias_presentes: number
  pontos_efetivos: number
  valor_centavos: Centavos
  criado_em: InstanteISO
}

// ---------------------------------------- adendo extras / ocorrências / reservas
export interface AnexoOcorrencia {
  id: Uuid
  caminho: string
  nome_arquivo: string | null
  criado_em: InstanteISO
}

/** Item de `ocorrencias_listar` (O.4). */
export interface Ocorrencia {
  id: Uuid
  funcionario_id: Uuid
  tipo: TipoOcorrencia
  data: DataISO
  motivo: string
  descricao: string | null
  dias_suspensao: number | null
  suspensao_inicio: DataISO | null
  suspensao_fim: DataISO | null
  criado_por_nome: string
  criado_em: InstanteISO
  atualizado_em: InstanteISO
  anexos: AnexoOcorrencia[]
}

export interface ContagemOcorrencias {
  funcionario_id: Uuid
  advertencias: number
  suspensoes: number
  dias_suspensao: number
  ultima_data: DataISO | null
}

export interface OcorrenciaRecente {
  id: Uuid
  funcionario_id: Uuid
  funcionario_nome: string
  tipo: TipoOcorrencia
  data: DataISO
  motivo: string
  dias_suspensao: number | null
  suspensao_inicio: DataISO | null
  suspensao_fim: DataISO | null
}

/** `ocorrencias_resumo` e bloco `ocorrencias` do painel. */
export interface ResumoOcorrencias {
  desde: DataISO
  ate: DataISO
  advertencias: number
  suspensoes: number
  suspensos_hoje: number
  recentes: OcorrenciaRecente[]
}

/** `comissao_detalhe` (adendo E.3.4). */
export interface ComissaoDetalheRateio {
  item_id: Uuid
  pontos: number
  valor_centavos: Centavos
  fallback: boolean
}
export interface ComissaoDetalheDia {
  data: DataISO
  servico_zig_centavos: Centavos
  ajuste_centavos: Centavos
  servico_bruto_centavos: Centavos
  retencao_centavos: Centavos
  base_centavos: Centavos
  soma_pontos: number
  participantes: number
  sem_presenca: boolean
  sem_participantes: boolean
  rateio: ComissaoDetalheRateio[]
}
export interface ComissaoDetalheItem {
  id: Uuid
  tipo: TipoParticipanteComissao
  funcionario_id: Uuid | null
  extra_id: Uuid | null
  nome: string
  cargo: string | null
  incluido: boolean
  pontos: number
  pontos_manual: boolean
  dias_presentes: number
  pontos_efetivos: number
  valor_centavos: Centavos
  entrada: { data: DataISO; presente: boolean; pontos: number }[]
}
export interface ComissaoDetalhe {
  fechamento: ComissaoFechamento
  servico_dias: { data: DataISO; servico_zig_centavos: Centavos }[]
  dias: ComissaoDetalheDia[]
  itens: ComissaoDetalheItem[]
}

/** Linha de `extras_listar` (E.1) — freela/diarista. */
export interface Extra {
  id: Uuid
  nome: string
  funcao: string | null
  telefone: string | null
  documento: string | null
  pontos_padrao: number
  valor_diaria_centavos: Centavos | null
  ativo: boolean
  observacoes: string | null
  dias_lancados: number
  ultimo_dia: DataISO | null
  criado_em: InstanteISO
}

/** Linha de `diarias_listar` (E.2): dia trabalhado de um extra (com pontos) ou diária de funcionário (só custo). */
export interface Diaria {
  id: Uuid
  data: DataISO
  tipo: TipoDiaria
  extra_id: Uuid | null
  funcionario_id: Uuid | null
  pessoa_nome: string
  funcao: string | null
  /** só extra */
  pontos: number | null
  valor_centavos: Centavos
  observacao: string | null
  pago: boolean
  pago_em: DataISO | null
  /** extra com data dentro de fechamento fechado: data e pontos travados */
  fechado: boolean
  criado_por_nome: string
  criado_em: InstanteISO
}

export interface ValorDiaria {
  funcionario_id: Uuid
  valor_diaria_centavos: Centavos
}

export interface GastosTotais {
  diarias_pagas: Centavos
  diarias_a_pagar: Centavos
  diarias: Centavos
  diarias_qtd: number
  diarias_extras: Centavos
  diarias_funcionarios: Centavos
  comissoes_fechadas: Centavos
  comissoes_previstas: Centavos
  total: Centavos
  total_com_previsto: Centavos
}

export interface GastosPessoa {
  chave: string
  tipo: TipoParticipanteComissao
  funcionario_id: Uuid | null
  extra_id: Uuid | null
  nome: string
  diarias_qtd: number
  diarias_pagas: Centavos
  diarias_a_pagar: Centavos
  comissoes_fechadas: Centavos
  comissoes_previstas: Centavos
  total: Centavos
}

export interface GastosDia {
  data: DataISO
  diarias_pagas: Centavos
  diarias_a_pagar: Centavos
  comissoes_fechadas: Centavos
  comissoes_previstas: Centavos
  total: Centavos
}

/** `gastos_periodo` (E.3). */
export interface GastosPeriodo {
  empresa_id: Uuid
  inicio: DataISO
  fim: DataISO
  totais: GastosTotais
  por_pessoa: GastosPessoa[]
  por_dia: GastosDia[]
  fechamentos: {
    id: Uuid
    titulo: string
    status: StatusFechamento
    modo_rateio: ModoRateio
    data_inicio: DataISO
    data_fim: DataISO
    base_distribuivel_centavos: Centavos
    valor_no_periodo_centavos: Centavos
  }[]
}

/** Linha de `reservas_listar` (R.3). `telefone`/`email` = null para leitura. */
export interface Reserva {
  id: Uuid
  origem: OrigemReserva
  data: DataISO
  horario: HoraISO | null
  nome_cliente: string
  pessoas: number
  status: StatusReserva
  area: string | null
  mesa: string | null
  observacao: string | null
  telefone: string | null
  email: string | null
  criado_em: InstanteISO
  atualizado_em: InstanteISO
}

/** Linha enviada a `reservas_importar`. */
export interface LinhaImportacaoReserva {
  id_externo: string | null
  data: DataISO
  horario: string | null
  nome: string
  pessoas: number | null
  telefone: string | null
  email: string | null
  status: StatusReserva | null
  area: string | null
  mesa: string | null
  observacao: string | null
}

export interface RetornoImportacaoReservas {
  lidos: number
  gravados: number
  ignorados: number
  inseridos: number
  atualizados: number
  erros: { indice: number; motivo: string }[]
}

export interface ReservaPainel {
  id: Uuid
  horario: HoraISO | null
  nome_cliente: string
  pessoas: number
  status: StatusReserva
  area: string | null
  mesa: string | null
  observacao: string | null
  origem: OrigemReserva
  telefone: string | null
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
  /** horários previstos do dia (vazio em folga, abono ou sem escala) — revisão 1 */
  esperadas: EsperadaEspelho[]
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
  /** adendo R.4 */
  reservas?: {
    total: number
    pessoas: number
    canceladas: number
    nao_compareceu: number
    sentadas: number
    tem_tagme: boolean
    proximas: ReservaPainel[]
  }
  /** adendo R.4: null para leitura */
  ocorrencias?: ResumoOcorrencias | null
}

// --------------------------------------------------------- mapa das RPCs [api]
type ArgsPeriodoVendas = { p_inicio: DataISO; p_fim: DataISO; p_loja?: string | null; p_empresa?: Uuid | null }

/** Nome → { args, retorno }. Só RPCs `[api]` (as `[servico]` são do N8N). */
// ------------------------------------------------------------ escala (adendo escala v2)
/** Dia da semana da escala: 0 = SEG … 6 = DOM (diferente do dow do Postgres). */
export type DiaSemanaEscala = 0 | 1 | 2 | 3 | 4 | 5 | 6
export type StatusEscala = 'trabalha' | 'folga' | 'ferias' | 'fora'
export type StatusAjusteEscala = 'trabalha' | 'folga' | 'ferias'

export interface EscalaDiaMembro {
  data: DataISO
  status: StatusEscala
  origem: 'auto' | 'ajuste'
  /** 'HH:MM' só quando trabalha */
  chegada: string | null
  ajustado: boolean
  motivo: string | null
}
export interface EscalaDiaFuncionario extends EscalaDiaMembro {
  funcionario_id: Uuid
}
export interface EscalaCaminho {
  caminho: number
  funcionarios: Uuid[]
}
export interface EscalaMembroMes {
  membro_id: Uuid
  funcionario_id: Uuid
  nome: string
  cargo: string | null
  chegada_padrao: string | null
  folgas_base: number[]
  caminho: number | null
  posicao: number | null
  folga_fixa: boolean
  trabalha: number
  folgas: number
  ferias: number
  dias: EscalaDiaMembro[]
}
export interface EscalaSetorMes {
  id: Uuid
  nome: string
  ordem: number
  fase: number
  caminhos: EscalaCaminho[]
  membros: EscalaMembroMes[]
  na_escala: number[]
}
export interface EscalaMes {
  empresa_id: Uuid
  ano_mes: string
  inicio: DataISO
  fim: DataISO
  configurada: boolean
  ancora: DataISO | null
  fase: number | null
  pode_editar: boolean
  hoje: DataISO
  dias: { data: DataISO; dia_semana: number; semana: number | null }[]
  setores: EscalaSetorMes[]
  na_escala: number[]
}
export interface EscalaMembroSemana {
  funcionario_id: Uuid
  nome: string
  cargo: string | null
  chegada_padrao: string | null
  caminho: number | null
  posicao: number | null
  folga_fixa: boolean
  folgas_base: number[]
  folgas_semana: number[]
}
export interface EscalaSetorSemana {
  id: Uuid
  nome: string
  ordem: number
  fase: number
  total: number
  caminhos: (EscalaCaminho & { nomes: string[] })[]
  membros: EscalaMembroSemana[]
  na_escala_base: number[]
  na_escala_semana: number[]
}
export interface EscalaSemana {
  empresa_id: Uuid
  configurada: boolean
  ancora: DataISO | null
  fase: number | null
  semana_inicio: DataISO
  semana: number | null
  setores: EscalaSetorSemana[]
  na_escala_base: number[]
  na_escala_semana: number[]
}
export interface EscalaMembroEntrada {
  funcionario_id: Uuid
  folgas_base: number[]
  chegada_padrao: string | null
  caminho: number | null
  posicao: number | null
}

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
      p_modo_rateio?: ModoRateio
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
      p_modo_rateio?: ModoRateio | null
    }
    retorno: null
  }
  comissao_definir_item: {
    /** p_pontos null = automático (pontos vigentes de cada dia) */
    args: { p_fechamento: Uuid; p_funcionario: Uuid; p_pontos: number | null; p_incluido?: boolean }
    retorno: null
  }
  comissao_definir_extra: { args: { p_fechamento: Uuid; p_extra: Uuid; p_incluido: boolean }; retorno: null }
  comissao_detalhe: { args: { p_fechamento: Uuid }; retorno: ComissaoDetalhe }
  comissao_remover_item: { args: { p_fechamento: Uuid; p_funcionario: Uuid }; retorno: null }
  comissao_recalcular: { args: { p_fechamento: Uuid }; retorno: null }
  comissao_fechar: { args: { p_fechamento: Uuid }; retorno: null }
  comissao_excluir_rascunho: { args: { p_fechamento: Uuid }; retorno: null }
  // painel (b2)
  painel_do_dia: { args: { p_empresa?: Uuid | null }; retorno: PainelDoDia }
  // ocorrências (adendo O.4)
  ocorrencia_criar: {
    args: {
      p_funcionario: Uuid
      p_tipo: TipoOcorrencia
      p_data: DataISO
      p_motivo: string
      p_descricao?: string | null
      p_dias_suspensao?: number | null
      p_suspensao_inicio?: DataISO | null
    }
    retorno: Uuid
  }
  ocorrencia_atualizar: {
    args: {
      p_ocorrencia: Uuid
      p_tipo: TipoOcorrencia
      p_data: DataISO
      p_motivo: string
      p_descricao: string | null
      p_dias_suspensao?: number | null
      p_suspensao_inicio?: DataISO | null
    }
    retorno: null
  }
  ocorrencia_excluir: { args: { p_ocorrencia: Uuid }; retorno: string[] | null }
  ocorrencia_adicionar_anexo: { args: { p_ocorrencia: Uuid; p_caminho: string; p_nome_arquivo?: string | null }; retorno: Uuid }
  ocorrencia_remover_anexo: { args: { p_anexo: Uuid }; retorno: string }
  ocorrencias_listar: { args: { p_funcionario: Uuid }; retorno: Ocorrencia[] }
  ocorrencias_contagem: { args: { p_funcionario?: Uuid | null; p_empresa?: Uuid | null }; retorno: ContagemOcorrencias[] }
  ocorrencias_resumo: { args: { p_dias?: number; p_empresa?: Uuid | null }; retorno: ResumoOcorrencias }
  // extras (adendo E)
  extra_criar: {
    args: {
      p_nome: string
      p_funcao?: string | null
      p_pontos_padrao?: number | null
      p_valor_diaria_centavos?: Centavos | null
      p_telefone?: string | null
      p_documento?: string | null
      p_observacoes?: string | null
      p_empresa?: Uuid | null
    }
    retorno: Uuid
  }
  extra_atualizar: {
    args: {
      p_extra: Uuid
      p_nome: string
      p_funcao: string | null
      p_pontos_padrao: number | null
      p_valor_diaria_centavos: Centavos | null
      p_telefone: string | null
      p_documento: string | null
      p_ativo: boolean | null
      p_observacoes: string | null
    }
    retorno: null
  }
  extra_excluir: { args: { p_extra: Uuid }; retorno: null }
  extras_listar: { args: { p_incluir_inativos?: boolean; p_empresa?: Uuid | null }; retorno: Extra[] }
  funcionario_definir_valor_diaria: { args: { p_funcionario: Uuid; p_valor_centavos: Centavos | null }; retorno: null }
  funcionario_valores_diaria_listar: { args: { p_empresa?: Uuid | null }; retorno: ValorDiaria[] }
  diaria_lancar: {
    args: {
      p_data: DataISO
      p_extra?: Uuid | null
      p_funcionario?: Uuid | null
      p_pontos?: number | null
      p_valor_centavos?: Centavos | null
      p_funcao?: string | null
      p_observacao?: string | null
      p_pago?: boolean
      p_pago_em?: DataISO | null
    }
    retorno: Uuid
  }
  diaria_atualizar: {
    args: {
      p_diaria: Uuid
      p_data: DataISO | null
      p_pontos: number | null
      p_valor_centavos: Centavos | null
      p_funcao: string | null
      p_observacao: string | null
      p_pago: boolean | null
      p_pago_em: DataISO | null
    }
    retorno: null
  }
  diaria_marcar_paga: { args: { p_diaria: Uuid; p_pago: boolean; p_pago_em?: DataISO | null }; retorno: null }
  diaria_excluir: { args: { p_diaria: Uuid }; retorno: null }
  diarias_listar: {
    args: {
      p_inicio: DataISO
      p_fim: DataISO
      p_tipo?: TipoDiaria | null
      p_extra?: Uuid | null
      p_funcionario?: Uuid | null
      p_pago?: boolean | null
      p_empresa?: Uuid | null
    }
    retorno: Diaria[]
  }
  gastos_periodo: { args: { p_inicio: DataISO; p_fim: DataISO; p_empresa?: Uuid | null }; retorno: GastosPeriodo }
  // reservas (adendo R.3)
  reserva_criar: {
    args: {
      p_data: DataISO
      p_horario: string | null
      p_nome_cliente: string
      p_pessoas?: number
      p_telefone?: string | null
      p_area?: string | null
      p_mesa?: string | null
      p_observacao?: string | null
      p_status?: StatusReserva
      p_email?: string | null
      p_empresa?: Uuid | null
    }
    retorno: Uuid
  }
  reserva_atualizar: {
    args: {
      p_reserva: Uuid
      p_data: DataISO
      p_horario: string | null
      p_nome_cliente: string
      p_pessoas: number
      p_telefone: string | null
      p_area: string | null
      p_mesa: string | null
      p_observacao: string | null
      p_status: StatusReserva
      p_email: string | null
    }
    retorno: null
  }
  reserva_mudar_status: { args: { p_reserva: Uuid; p_status: StatusReserva }; retorno: null }
  reserva_cancelar: { args: { p_reserva: Uuid }; retorno: null }
  reserva_excluir: { args: { p_reserva: Uuid }; retorno: null }
  reservas_listar: {
    args: { p_inicio: DataISO; p_fim?: DataISO | null; p_status?: StatusReserva[] | null; p_empresa?: Uuid | null }
    retorno: Reserva[]
  }
  reservas_importar: { args: { p_linhas: LinhaImportacaoReserva[]; p_empresa?: Uuid | null }; retorno: RetornoImportacaoReservas }
  // escala (adendo escala v2)
  escala_configurar: {
    args: { p_ancora: DataISO; p_fase?: number; p_empresa?: Uuid | null }
    retorno: { empresa_id: Uuid; ancora: DataISO; fase: number }
  }
  escala_salvar_setor: {
    args: { p_nome: string; p_ordem?: number | null; p_fase?: number; p_setor?: Uuid | null; p_empresa?: Uuid | null }
    retorno: Uuid
  }
  escala_excluir_setor: { args: { p_setor: Uuid }; retorno: null }
  escala_salvar_membro: {
    args: {
      p_setor: Uuid
      p_funcionario: Uuid
      p_folgas_base?: number[]
      p_chegada_padrao?: string | null
      p_caminho?: number | null
      p_posicao?: number | null
      p_ordem?: number | null
    }
    retorno: Uuid
  }
  escala_definir_membros: { args: { p_setor: Uuid; p_membros: EscalaMembroEntrada[] }; retorno: number }
  escala_remover_membro: { args: { p_funcionario: Uuid }; retorno: null }
  escala_adicionar_funcionario: {
    args: {
      p_setor: Uuid
      p_nome: string
      p_cargo?: string | null
      p_folgas_base?: number[]
      p_chegada_padrao?: string | null
      p_caminho?: number | null
      p_posicao?: number | null
    }
    retorno: Uuid
  }
  escala_aplicar_modelo_macaw: {
    args: { p_empresa?: Uuid | null; p_ancora?: DataISO | null }
    retorno: { ancora: DataISO; setores: number; membros: number; funcionarios_criados: number }
  }
  escala_ajustar: {
    args: { p_funcionario: Uuid; p_data: DataISO; p_status?: StatusAjusteEscala | 'auto' | null; p_chegada?: string | null; p_motivo?: string | null }
    retorno: EscalaDiaFuncionario
  }
  escala_ajustar_periodo: {
    args: { p_funcionario: Uuid; p_inicio: DataISO; p_fim: DataISO; p_status: StatusAjusteEscala | 'auto' | null; p_motivo?: string | null }
    retorno: number
  }
  escala_trocar: {
    args: { p_funcionario_a: Uuid; p_data_a: DataISO; p_funcionario_b?: Uuid | null; p_data_b?: DataISO | null; p_motivo?: string | null }
    retorno: EscalaDiaFuncionario[]
  }
  escala_mes: { args: { p_ano_mes: string; p_empresa?: Uuid | null }; retorno: EscalaMes }
  escala_semana: { args: { p_data?: DataISO | null; p_empresa?: Uuid | null }; retorno: EscalaSemana }
}

export type NomeRpc = keyof Rpcs
