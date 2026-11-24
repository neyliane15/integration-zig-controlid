// Assistente de IA do "Meu Dia de Gerente": responde perguntas do gerente sobre os dados da loja (vendas, ponto, faltas,
// atrasos, banco de horas, escala, reservas, funcionários). Funções puras, sem import: copiada no nó Code do workflow
// "MDG · Assistente" com `// @lib assistente/lib/assistente.mjs` (conferida por `npm run n8n:verificar`).
//
// Como funciona: loop de uso de ferramentas da Messages API da Anthropic (HTTP puro — o nó Code não tem o SDK). Cada
// ferramenta é uma RPC/consulta do Supabase feita COM O LOGIN DE QUEM PERGUNTA (JWT do usuário + chave anon): RLS e as
// checagens de permissão valem exatamente como no site — o assistente só vê o que a pessoa já pode ver.
// Modelo: claude-opus-5-5 (raciocínio adaptativo sempre ligado; esforço "medium"), com fallback do servidor em caso de recusa.
// Custo: prompt do sistema + ferramentas fixos e em cache (cache_control automático); só a conversa muda.

export const ASSISTENTE_MODELO = 'claude-opus-5-5'
export const ASSISTENTE_API = 'https://api.anthropic.com/v1/messages'
export const ASSISTENTE_VERSAO_API = '2026-10-21'
export const ASSISTENTE_MAX_RODADAS = 8
export const ASSISTENTE_MAX_LINHAS = 400

export const ASSISTENTE_SISTEMA = `Você é o assistente do "Meu Dia de Gerente", o sistema de gestão do restaurante. Você conversa em português do Brasil com o gerente ou o dono e responde perguntas sobre os dados da loja: vendas e faturamento (da Zig), ponto (batidas, faltas, atrasos, horas e banco de horas, vindos do relógio/RHiD), escala de trabalho, reservas e funcionários.

Regras:
- Números e nomes vêm SEMPRE das ferramentas. Nunca invente ou estime um dado; se a ferramenta não trouxer o dado, diga que não há registro no sistema para aquele período.
- Antes de consultar, transforme o período pedido em datas (AAAA-MM-DD) a partir de "hoje", que vem no contexto da conversa. "Mês de novembro" sem ano = o novembro mais recente que já começou. "Semana passada" = segunda a domingo da semana anterior.
- Quando a pergunta for de ranking ("quem menos atrasou", "qual dia mais vendeu"), consulte o período inteiro e compare todos; em caso de empate, diga quem empatou.
- Valores de dinheiro já vêm em reais: escreva como R$ 1.234,56. Minutos: escreva em horas e minutos (ex.: 445 min = 7h25). Datas: DD/MM/AAAA, com o dia da semana quando ajudar.
- Faltas = dias com horário previsto e sem nenhuma batida, mais as faltas registradas no sistema. Atraso = primeira batida depois da chegada prevista na escala, além da tolerância. Funcionário sem escala com chegada no dia não tem atraso calculado — diga isso se for relevante.
- Responda curto e direto: primeiro a resposta, depois (se útil) 2 a 5 linhas de apoio. Texto simples, sem tabelas nem markdown pesado; listas com "- ". Diga qual período você considerou.
- Se a pessoa não tiver permissão para um dado, a ferramenta devolve erro de permissão: explique que o perfil dela não acessa essa informação.
- Você só consulta; não altera nada no sistema. Se pedirem para lançar, mudar ou apagar algo, explique onde fazer isso no site.
- Não exponha documentos pessoais (CPF, telefone) nem dados de outras empresas.`

const DATA = { type: 'string', format: 'date', description: 'Data no formato AAAA-MM-DD' }
const periodo = (descricao) => ({
  type: 'object',
  properties: { inicio: { ...DATA, description: 'Primeiro dia do período (AAAA-MM-DD)' }, fim: { ...DATA, description: 'Último dia do período (AAAA-MM-DD), inclusive' } },
  required: ['inicio', 'fim'],
  additionalProperties: false,
  description: descricao,
})

/** Ferramentas (ordem fixa: entra no cache do prompt). */
export const ASSISTENTE_FERRAMENTAS = [
  { name: 'vendas_resumo', description: 'Totais de vendas da Zig no período: faturamento, vendas, serviço (10%), descontos e número de transações. Valores em reais.', input_schema: periodo('Período') },
  { name: 'vendas_por_dia', description: 'Faturamento de cada dia do período (Zig), em reais. Use para "qual dia mais/menos vendeu", médias e comparações entre dias.', input_schema: periodo('Período') },
  { name: 'vendas_por_garcom', description: 'Vendas por garçom/funcionário no período (Zig): quantidade de itens, valor vendido, serviço e transações, em reais.', input_schema: periodo('Período') },
  { name: 'vendas_por_forma_pagamento', description: 'Faturamento por forma de pagamento (crédito, débito, pix, dinheiro...) no período, em reais.', input_schema: periodo('Período') },
  { name: 'ponto_por_funcionario', description: 'Resumo do ponto de cada funcionário no período: dias com batida, faltas (sem justificativa), faltas justificadas, quantidade de atrasos, minutos de atraso, minutos trabalhados e saldo de horas (minutos; negativo = deve horas). Use para rankings de atraso, falta, horas trabalhadas.', input_schema: periodo('Período') },
  { name: 'faltas_e_atrasos', description: 'Lista detalhada de cada falta e cada atraso no período, com data, funcionário, minutos de atraso, hora que chegou e horário previsto da escala.', input_schema: periodo('Período') },
  { name: 'banco_de_horas', description: 'Saldo do banco de horas de cada funcionário até uma data (padrão: ontem), em minutos, e o saldo do mês.', input_schema: { type: 'object', properties: { ate: { ...DATA, description: 'Data de corte (AAAA-MM-DD); omita para ontem' } }, required: [], additionalProperties: false } },
  { name: 'escala_do_dia', description: 'Escala de um dia: cada funcionário com o setor, status (trabalha, folga, ferias, banco_horas = folga de banco de horas, fora) e horário de chegada.', input_schema: { type: 'object', properties: { data: DATA }, required: ['data'], additionalProperties: false } },
  { name: 'reservas', description: 'Reservas (Tagme/manual) do período: data, horário, nome, número de pessoas, status e ambiente.', input_schema: periodo('Período') },
  { name: 'funcionarios', description: 'Funcionários cadastrados: nome, cargo, ativo, admissão, desligamento, pontos de comissão e se participa da comissão.', input_schema: { type: 'object', properties: { incluir_desligados: { type: 'boolean', description: 'true para incluir quem já foi desligado' } }, required: [], additionalProperties: false } },
]

const CAMPOS_CENTAVOS = new Set(['valor', 'faturamento', 'vendas', 'servico', 'descontos', 'valor_vendas', 'valor_servico', 'servico_compradores'])

/** Centavos → reais nos campos de dinheiro conhecidos; listas longas são cortadas (com aviso). */
export function prepararResultadoAssistente(dados, maxLinhas = ASSISTENTE_MAX_LINHAS) {
  const reais = (v) => (v === null || v === undefined || v === '' ? v : Math.round(Number(v)) / 100)
  const linha = (o) => {
    if (!o || typeof o !== 'object' || Array.isArray(o)) return o
    const r = {}
    for (const [k, v] of Object.entries(o)) r[k] = CAMPOS_CENTAVOS.has(k) && v !== null && !Number.isNaN(Number(v)) ? reais(v) : v
    return r
  }
  if (Array.isArray(dados)) {
    const linhas = dados.slice(0, maxLinhas).map(linha)
    return dados.length > maxLinhas ? { linhas, aviso: `Mostrando ${maxLinhas} de ${dados.length} linhas; peça um período menor.` } : linhas
  }
  return linha(dados)
}

const dataOk = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + 'T00:00:00Z'))

/**
 * Executa uma ferramenta. ctx: { rpc(nome, args), tabela(caminhoQuery), empresaId }.
 * Erros viram { erro } (o modelo explica ao usuário); nunca lança.
 */
export async function executarFerramentaAssistente(nome, entrada, ctx) {
  const e = entrada || {}
  const p = (extra = {}) => ({ p_inicio: e.inicio, p_fim: e.fim, p_empresa: ctx.empresaId, ...extra })
  const exigePeriodo = () => {
    if (!dataOk(e.inicio) || !dataOk(e.fim)) throw new Error('Datas inválidas: use AAAA-MM-DD')
    if (e.fim < e.inicio) throw new Error('O fim do período é antes do início')
  }
  try {
    switch (nome) {
      case 'vendas_resumo': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('vendas_resumo', p()))
      case 'vendas_por_dia': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('vendas_faturamento_por_dia', p()))
      case 'vendas_por_garcom': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('vendas_por_garcom', p()))
      case 'vendas_por_forma_pagamento': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('vendas_faturamento_por_forma', p()))
      case 'ponto_por_funcionario': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('assistente_ponto_resumo', p()))
      case 'faltas_e_atrasos': exigePeriodo(); return prepararResultadoAssistente(await ctx.rpc('ocorrencias_ponto', { p_inicio: e.inicio, p_fim: e.fim, p_funcionario: null, p_empresa: ctx.empresaId }))
      case 'banco_de_horas':
        if (e.ate !== undefined && e.ate !== null && !dataOk(e.ate)) throw new Error('Data inválida: use AAAA-MM-DD')
        return prepararResultadoAssistente(await ctx.rpc('banco_horas_resumo', { p_ate: e.ate || null, p_empresa: ctx.empresaId }))
      case 'escala_do_dia':
        if (!dataOk(e.data)) throw new Error('Data inválida: use AAAA-MM-DD')
        return prepararResultadoAssistente(await ctx.rpc('assistente_escala_dia', { p_data: e.data, p_empresa: ctx.empresaId }))
      case 'reservas': {
        exigePeriodo()
        const linhas = (await ctx.rpc('reservas_listar', p())) || []
        return prepararResultadoAssistente(linhas.map((r) => ({ data: r.data, horario: r.horario, nome: r.nome_cliente, pessoas: r.pessoas, status: r.status, area: r.area, mesa: r.mesa, observacao: r.observacao, origem: r.origem })))
      }
      case 'funcionarios': {
        let q = `funcionarios?select=nome,cargo,ativo,data_admissao,data_desligamento,pontos_comissao,participa_comissao&empresa_id=eq.${encodeURIComponent(ctx.empresaId)}&order=nome`
        if (!e.incluir_desligados) q += '&ativo=eq.true'
        return prepararResultadoAssistente(await ctx.tabela(q))
      }
      default:
        return { erro: `Ferramenta desconhecida: ${nome}` }
    }
  } catch (err) {
    return { erro: String((err && err.message) || err).slice(0, 300) }
  }
}

/** Histórico vindo do site → mensagens (só texto; começa no usuário, papéis alternados, últimas 12). */
export function mensagensDoHistoricoAssistente(historico, pergunta, contexto) {
  const msgs = []
  for (const h of (Array.isArray(historico) ? historico : []).slice(-12)) {
    const role = h && h.papel === 'assistente' ? 'assistant' : h && h.papel === 'usuario' ? 'user' : null
    const texto = h && typeof h.texto === 'string' ? h.texto.trim().slice(0, 4000) : ''
    if (!role || !texto) continue
    if (!msgs.length && role !== 'user') continue
    if (msgs.length && msgs[msgs.length - 1].role === role) msgs[msgs.length - 1].content += '\n\n' + texto
    else msgs.push({ role, content: texto })
  }
  if (msgs.length && msgs[msgs.length - 1].role === 'user') msgs.pop() // a pergunta nova é a última mensagem do usuário
  const c = contexto || {}
  const cab = `[Contexto: empresa "${String(c.empresa_nome || '').slice(0, 120)}"; hoje é ${c.hoje || 'desconhecido'}${c.dia_semana ? ` (${c.dia_semana})` : ''}.]`
  msgs.push({ role: 'user', content: `${cab}\n\n${String(pergunta).trim().slice(0, 2000)}` })
  return msgs
}

/** Corpo da requisição à Messages API (sistema + ferramentas fixos para o cache; fallback do servidor na recusa). */
export function corpoClaudeAssistente(mensagens) {
  return {
    model: ASSISTENTE_MODELO,
    max_tokens: 16000,
    cache_control: { type: 'ephemeral' },
    system: ASSISTENTE_SISTEMA,
    // sem strict: as entradas são conferidas no código (executarFerramentaAssistente) antes de qualquer consulta
    tools: ASSISTENTE_FERRAMENTAS,
    tool_choice: { type: 'auto' },
    output_config: { effort: 'medium' },
    fallbacks: 'default',
    messages: mensagens,
  }
}

export function cabecalhosClaudeAssistente(chave) {
  return {
    'content-type': 'application/json',
    'x-api-key': chave,
    'anthropic-version': ASSISTENTE_VERSAO_API,
    'anthropic-beta': 'server-side-fallback-2026-07-01',
  }
}

/**
 * Conversa: chama o Claude e executa as ferramentas pedidas até a resposta final.
 * deps: { claude(corpo) → resposta JSON da API (lança em erro HTTP), ctx (ver executarFerramentaAssistente), maxRodadas? }
 * Devolve { resposta, ferramentas: [nomes usados], uso: {entrada, saida, cache_lido, cache_criado}, rodadas }.
 */
export async function conversarAssistente(mensagensIniciais, deps) {
  const mensagens = mensagensIniciais.slice()
  const usadas = []
  const uso = { entrada: 0, saida: 0, cache_lido: 0, cache_criado: 0 }
  const max = deps.maxRodadas || ASSISTENTE_MAX_RODADAS
  for (let rodada = 1; rodada <= max; rodada++) {
    const r = await deps.claude(corpoClaudeAssistente(mensagens))
    const u = (r && r.usage) || {}
    uso.entrada += Number(u.input_tokens) || 0
    uso.saida += Number(u.output_tokens) || 0
    uso.cache_lido += Number(u.cache_read_input_tokens) || 0
    uso.cache_criado += Number(u.cache_creation_input_tokens) || 0
    const conteudo = Array.isArray(r && r.content) ? r.content : []
    const texto = conteudo.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n').trim()
    if (r.stop_reason === 'refusal') {
      return { resposta: 'Não consigo responder a essa pergunta. Tente reformular, perguntando sobre vendas, ponto, escala, reservas ou funcionários.', ferramentas: usadas, uso, rodadas: rodada }
    }
    if (r.stop_reason !== 'tool_use') {
      const corte = r.stop_reason === 'max_tokens' ? '\n\n(A resposta ficou longa demais e foi cortada.)' : ''
      return { resposta: (texto || 'Não encontrei uma resposta.') + corte, ferramentas: usadas, uso, rodadas: rodada }
    }
    // devolve o conteúdo do assistente sem mexer (blocos de raciocínio incluídos) e todos os resultados numa mensagem só
    mensagens.push({ role: 'assistant', content: conteudo })
    const pedidos = conteudo.filter((b) => b && b.type === 'tool_use')
    const resultados = await Promise.all(pedidos.map(async (b) => {
      usadas.push(b.name)
      const dados = await executarFerramentaAssistente(b.name, b.input, deps.ctx)
      const erro = dados && typeof dados === 'object' && !Array.isArray(dados) && 'erro' in dados && Object.keys(dados).length === 1
      return { type: 'tool_result', tool_use_id: b.id, content: JSON.stringify(dados ?? null), ...(erro ? { is_error: true } : {}) }
    }))
    mensagens.push({ role: 'user', content: resultados })
  }
  return { resposta: 'A pergunta precisou de consultas demais. Tente algo mais específico (um período ou um funcionário).', ferramentas: usadas, uso, rodadas: max }
}

/** Valida o pedido vindo do site. Devolve { pergunta, historico, empresaId, contexto } ou lança com mensagem clara. */
export function validarPedidoAssistente(corpo) {
  const c = corpo && typeof corpo === 'object' ? corpo : {}
  const pergunta = typeof c.pergunta === 'string' ? c.pergunta.trim() : ''
  if (!pergunta) throw new Error('Escreva uma pergunta')
  if (pergunta.length > 2000) throw new Error('Pergunta longa demais (máximo de 2000 caracteres)')
  const empresaId = typeof c.empresa_id === 'string' && /^[0-9a-f-]{36}$/i.test(c.empresa_id) ? c.empresa_id : null
  if (!empresaId) throw new Error('Empresa não informada')
  const historico = Array.isArray(c.historico) ? c.historico.slice(-12) : []
  const ctx = c.contexto && typeof c.contexto === 'object' ? c.contexto : {}
  const contexto = {
    empresa_nome: typeof ctx.empresa_nome === 'string' ? ctx.empresa_nome.slice(0, 120) : '',
    hoje: dataOk(ctx.hoje) ? ctx.hoje : null,
    dia_semana: typeof ctx.dia_semana === 'string' ? ctx.dia_semana.slice(0, 20) : '',
  }
  return { pergunta, historico, empresaId, contexto }
}
