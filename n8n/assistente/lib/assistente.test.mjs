// Roda com `node --test "n8n/**/*.test.mjs"` e com `npm test` (vitest). Funções puras do assistente, com um Claude falso.
import assert from 'node:assert/strict'
import {
  validarPedidoAssistente, mensagensDoHistoricoAssistente, prepararResultadoAssistente, executarFerramentaAssistente,
  conversarAssistente, corpoClaudeAssistente, cabecalhosClaudeAssistente, ASSISTENTE_FERRAMENTAS, ASSISTENTE_MODELO,
} from './assistente.mjs'

const { test } = process.env.VITEST ? await import('vitest') : await import('node:test')
const EMP = 'a0000000-0000-4000-8000-00000000000a'

test('pedido: valida pergunta, empresa, histórico e contexto', () => {
  assert.throws(() => validarPedidoAssistente({}), /Escreva uma pergunta/)
  assert.throws(() => validarPedidoAssistente({ pergunta: 'x'.repeat(2001), empresa_id: EMP }), /longa demais/)
  assert.throws(() => validarPedidoAssistente({ pergunta: 'oi', empresa_id: 'abc' }), /Empresa não informada/)
  const p = validarPedidoAssistente({ pergunta: '  Quem mais atrasou?  ', empresa_id: EMP, historico: Array(20).fill({ papel: 'usuario', texto: 'a' }),
    contexto: { empresa_nome: 'Macaw', hoje: '2026-11-24', dia_semana: 'terça' } })
  assert.equal(p.pergunta, 'Quem mais atrasou?')
  assert.equal(p.historico.length, 12)
  assert.deepEqual(p.contexto, { empresa_nome: 'Macaw', hoje: '2026-11-24', dia_semana: 'terça' })
  assert.equal(validarPedidoAssistente({ pergunta: 'oi', empresa_id: EMP, contexto: { hoje: 'ontem' } }).contexto.hoje, null)
})

test('mensagens: começa no usuário, alterna papéis, contexto na pergunta nova', () => {
  const m = mensagensDoHistoricoAssistente([
    { papel: 'assistente', texto: 'Olá!' },
    { papel: 'usuario', texto: 'Quanto vendemos ontem?' },
    { papel: 'assistente', texto: 'R$ 10.000,00' },
    { papel: 'assistente', texto: 'Quer mais detalhes?' },
    { papel: 'sistema', texto: 'ignorar' },
  ], 'E anteontem?', { empresa_nome: 'Macaw', hoje: '2026-11-24', dia_semana: 'terça' })
  assert.deepEqual(m.map((x) => x.role), ['user', 'assistant', 'user'])
  assert.equal(m[1].content, 'R$ 10.000,00\n\nQuer mais detalhes?')
  assert.match(m[2].content, /^\[Contexto: empresa "Macaw"; hoje é 2026-11-24 \(terça\)\.\]\n\nE anteontem\?$/)
})

test('resultados: centavos viram reais, listas longas são cortadas com aviso', () => {
  assert.deepEqual(prepararResultadoAssistente([{ data: '2026-11-01', valor: 1234567 }]), [{ data: '2026-11-01', valor: 12345.67 }])
  assert.deepEqual(prepararResultadoAssistente({ faturamento: '500', transacoes: 3 }), { faturamento: 5, transacoes: 3 })
  const r = prepararResultadoAssistente(Array.from({ length: 5 }, (_, i) => ({ i })), 2)
  assert.equal(r.linhas.length, 2)
  assert.match(r.aviso, /2 de 5/)
})

test('ferramentas: cada uma chama a RPC certa com a empresa; entradas ruins e erros viram { erro }', async () => {
  const chamadas = []
  const ctx = {
    empresaId: EMP,
    rpc: async (nome, args) => { chamadas.push([nome, args]); if (nome === 'ocorrencias_ponto') throw new Error('Sem permissão'); return [{ valor: 100 }] },
    tabela: async (q) => { chamadas.push(['tabela', q]); return [{ nome: 'Ana' }] },
  }
  const per = { inicio: '2026-11-01', fim: '2026-11-30' }
  assert.deepEqual(await executarFerramentaAssistente('vendas_por_dia', per, ctx), [{ valor: 1 }])
  await executarFerramentaAssistente('ponto_por_funcionario', per, ctx)
  await executarFerramentaAssistente('escala_do_dia', { data: '2026-11-24' }, ctx)
  await executarFerramentaAssistente('banco_de_horas', {}, ctx)
  await executarFerramentaAssistente('funcionarios', {}, ctx)
  assert.deepEqual(chamadas.map((c) => c[0]), ['vendas_faturamento_por_dia', 'assistente_ponto_resumo', 'assistente_escala_dia', 'banco_horas_resumo', 'tabela'])
  assert.deepEqual(chamadas[0][1], { p_inicio: '2026-11-01', p_fim: '2026-11-30', p_empresa: EMP })
  assert.deepEqual(chamadas[3][1], { p_ate: null, p_empresa: EMP })
  assert.match(chamadas[4][1], /empresa_id=eq\.a0000000-.*&ativo=eq\.true$/)
  assert.doesNotMatch(chamadas[4][1], /cpf/)
  assert.deepEqual(await executarFerramentaAssistente('faltas_e_atrasos', per, ctx), { erro: 'Sem permissão' })
  assert.deepEqual(await executarFerramentaAssistente('vendas_resumo', { inicio: '01/11/2026', fim: '2026-11-30' }, ctx), { erro: 'Datas inválidas: use AAAA-MM-DD' })
  assert.deepEqual(await executarFerramentaAssistente('vendas_resumo', { inicio: '2026-11-30', fim: '2026-11-01' }, ctx), { erro: 'O fim do período é antes do início' })
  assert.match((await executarFerramentaAssistente('apagar_tudo', {}, ctx)).erro, /desconhecida/)
})

test('corpo e cabeçalhos: modelo, ferramentas fixas, cache, esforço, fallback; sem sampling nem tool_choice forçado', () => {
  const c = corpoClaudeAssistente([{ role: 'user', content: 'oi' }])
  assert.equal(c.model, ASSISTENTE_MODELO)
  assert.equal(c.model, 'claude-opus-5-5')
  assert.deepEqual(c.cache_control, { type: 'ephemeral' })
  assert.deepEqual(c.tool_choice, { type: 'auto' })
  assert.deepEqual(c.output_config, { effort: 'medium' })
  assert.equal(c.fallbacks, 'default')
  assert.equal(c.tools.length, ASSISTENTE_FERRAMENTAS.length)
  assert.ok(!('temperature' in c) && !('thinking' in c))
  assert.ok(c.tools.every((t) => t.input_schema.type === 'object' && t.input_schema.additionalProperties === false))
  const h = cabecalhosClaudeAssistente('chave-teste')
  assert.equal(h['anthropic-version'], '2026-10-21')
  assert.equal(h['anthropic-beta'], 'server-side-fallback-2026-07-01')
  assert.equal(h['x-api-key'], 'chave-teste')
})

test('conversa: executa as ferramentas em paralelo, devolve tudo numa mensagem e para na resposta final', async () => {
  const corpos = []
  const respostas = [
    { stop_reason: 'tool_use', usage: { input_tokens: 100, output_tokens: 20, cache_read_input_tokens: 0, cache_creation_input_tokens: 900 },
      content: [{ type: 'thinking', thinking: '', signature: 'sig' },
        { type: 'tool_use', id: 't1', name: 'ponto_por_funcionario', input: { inicio: '2026-11-01', fim: '2026-11-30' } },
        { type: 'tool_use', id: 't2', name: 'faltas_e_atrasos', input: { inicio: '2026-11-01', fim: '2026-11-30' } }] },
    { stop_reason: 'end_turn', usage: { input_tokens: 50, output_tokens: 30, cache_read_input_tokens: 900 },
      content: [{ type: 'thinking', thinking: '', signature: 'sig2' }, { type: 'text', text: 'Quem menos atrasou foi a Ana.' }] },
  ]
  const ctx = { empresaId: EMP, rpc: async (nome) => (nome === 'ocorrencias_ponto' ? Promise.reject(new Error('Sem permissão')) : [{ funcionario_nome: 'Ana', atrasos: 0 }]), tabela: async () => [] }
  const r = await conversarAssistente([{ role: 'user', content: 'Quem menos atrasou em novembro?' }], {
    ctx,
    claude: async (corpo) => { corpos.push(JSON.parse(JSON.stringify(corpo))); return respostas.shift() },
  })
  assert.equal(r.resposta, 'Quem menos atrasou foi a Ana.')
  assert.deepEqual(r.ferramentas, ['ponto_por_funcionario', 'faltas_e_atrasos'])
  assert.deepEqual(r.uso, { entrada: 150, saida: 50, cache_lido: 900, cache_criado: 900 })
  const seg = corpos[1].messages
  assert.equal(seg.length, 3)
  assert.deepEqual(seg[1].content[0], { type: 'thinking', thinking: '', signature: 'sig' }, 'conteúdo do assistente volta sem mexer')
  assert.equal(seg[2].role, 'user')
  assert.deepEqual(seg[2].content.map((b) => [b.type, b.tool_use_id, !!b.is_error]), [['tool_result', 't1', false], ['tool_result', 't2', true]])
})

test('conversa: recusa, corte por max_tokens e limite de rodadas', async () => {
  const ctx = { empresaId: EMP, rpc: async () => [], tabela: async () => [] }
  const recusa = await conversarAssistente([{ role: 'user', content: 'x' }], { ctx, claude: async () => ({ stop_reason: 'refusal', content: [] }) })
  assert.match(recusa.resposta, /Não consigo responder/)
  const corte = await conversarAssistente([{ role: 'user', content: 'x' }], { ctx, claude: async () => ({ stop_reason: 'max_tokens', content: [{ type: 'text', text: 'Parcial' }] }) })
  assert.match(corte.resposta, /^Parcial\n\n\(A resposta ficou longa demais/)
  let n = 0
  const laco = await conversarAssistente([{ role: 'user', content: 'x' }], {
    ctx, maxRodadas: 3,
    claude: async () => ({ stop_reason: 'tool_use', content: [{ type: 'tool_use', id: `t${++n}`, name: 'funcionarios', input: {} }] }),
  })
  assert.equal(laco.rodadas, 3)
  assert.match(laco.resposta, /consultas demais/)
})
