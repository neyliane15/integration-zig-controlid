// Cenário NOVO da revisão 2, ponta a ponta com dados calculados À MÃO (opt-in, grava no banco local):
//   mocks controlados (n8n/mocks/cenario-revisao2.mjs: REP com AFD que atravessa a meia-noite, batida esquecida e duplicada;
//   Zig com serviço/Tip de dois garçons + balcão) → workflows reais no simulador → banco local → RPCs chamadas COMO OS USUÁRIOS
//   (master cria a empresa, administrador cadastra as integrações, gerente opera, administrador fecha a comissão).
// Também: reimportação idempotente, importações SIMULTÂNEAS do mesmo dia (achado V2-02) e o CSV do e-mail sem fórmula (V2-01).
//
//   npm run local  &&  MDG_INTEGRACAO_REAL=1 node --test n8n/cenario-revisao2.test.mjs      (ou npm run test:integracao)
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { executarWorkflow } from './mocks/simulador-n8n.mjs'
import { CENARIO, diaDeTrabalho, iniciarCenario, somarDias } from './mocks/cenario-revisao2.mjs'

const { describe, it, before, after } = process.env.VITEST
  ? await import('vitest').then((v) => ({ ...v, before: v.beforeAll, after: v.afterAll }))
  : await import('node:test')

const N8N = dirname(fileURLToPath(import.meta.url))
const RAIZ = join(N8N, '..')
const ler = (rel) => JSON.parse(readFileSync(join(N8N, rel), 'utf8'))
const ATIVO = process.env.MDG_INTEGRACAO_REAL === '1'

function configLocal() {
  let url = process.env.MDG_SUPABASE_URL
  if (!url && existsSync(join(RAIZ, '.env.local'))) {
    url = /^VITE_SUPABASE_URL=(.+)$/m.exec(readFileSync(join(RAIZ, '.env.local'), 'utf8'))?.[1]?.trim()
  }
  const chaves = JSON.parse(execFileSync('node', [join(RAIZ, 'ferramentas/local/portao.mjs'), '--chaves'], { encoding: 'utf8' }))
  return { url: url.replace(/\/+$/, ''), servico: process.env.MDG_SERVICE_ROLE_KEY || chaves.service_role, anon: chaves.anon }
}

describe('cenário revisão 2: AFD com virada + Zig com Tip → ponto, alarme, banco de horas, ranking e comissão', { skip: !ATIVO && 'defina MDG_INTEGRACAO_REAL=1 com `npm run local` no ar' }, () => {
  let sb, mocks, ctx, empresa, rep, zig, tokens
  const sufixo = Date.now().toString(36)
  const hoje = diaDeTrabalho()
  const D1 = somarDias(hoje, -1)
  const D2 = somarDias(hoje, -2)

  const chamar = async (token, caminho, opcoes = {}) => {
    const r = await fetch(`${sb.url}/${caminho}`, {
      ...opcoes,
      headers: { apikey: token === sb.servico ? sb.servico : sb.anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(opcoes.headers || {}) },
    })
    const t = await r.text()
    return { status: r.status, corpo: t ? JSON.parse(t) : null }
  }
  const rpc = async (quem, nome, args = {}) => {
    const r = await chamar(tokens[quem], `rest/v1/rpc/${nome}`, { method: 'POST', body: JSON.stringify(args) })
    if (r.status >= 400) throw Object.assign(new Error(`${quem} ${nome}: HTTP ${r.status} ${r.corpo?.message}`), { corpo: r.corpo })
    return r.corpo
  }
  const tabela = async (quem, caminho, metodo = 'GET', corpo) => {
    const r = await chamar(tokens[quem], `rest/v1/${caminho}`, { method: metodo, body: corpo === undefined ? undefined : JSON.stringify(corpo) })
    if (r.status >= 400) throw new Error(`${quem} ${metodo} ${caminho}: HTTP ${r.status} ${r.corpo?.message}`)
    return r.corpo
  }
  const entrar = async (email, senha) => {
    const r = await fetch(`${sb.url}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: sb.anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: senha }) })
    const j = await r.json()
    assert.ok(j.access_token, `login ${email}: ${JSON.stringify(j)}`)
    return j.access_token
  }
  const rodarFila = async () => {
    const r = await executarWorkflow(ctx.workflows.fila, [], ctx)
    assert.equal(r.erro, null, r.erro && `${r.erro.no}: ${r.erro.message}`)
  }

  before(async () => {
    sb = configLocal()
    mocks = await iniciarCenario({ rep: 0, zig: 0 })
    tokens = { servico: sb.servico, master: await entrar('master@meudiadegerente.app', 'gerente123') }
    // master cria a empresa e o administrador (tela Empresas → Nova empresa)
    const emailAdmin = `admin.${sufixo}@revisao2.local`
    empresa = await rpc('master', 'master_criar_empresa', { p_nome: `Revisão 2 ${sufixo}`, p_cnpj: null, p_admin_email: emailAdmin, p_admin_senha: 'senha123', p_admin_nome: 'Admin R2' })
    tokens.admin = await entrar(emailAdmin, 'senha123')
    const emailGerente = `gerente.${sufixo}@revisao2.local`
    await rpc('admin', 'admin_criar_usuario', { p_email: emailGerente, p_senha: 'senha123', p_nome: 'Gerente R2', p_papel: 'gerente', p_empresa_id: empresa })
    tokens.gerente = await entrar(emailGerente, 'senha123')

    // gerente: jornada "Noite teste" (todo dia 18:00 / 22:00 / 22:30 / 02:00) e os funcionários (admissão D-2)
    const [j] = await tabela('gerente', 'jornadas', 'POST', { empresa_id: empresa, nome: 'Noite teste', tolerancia_batida_minutos: 5, tolerancia_diaria_minutos: 10 })
    await tabela('gerente', 'jornada_dias', 'POST', [0, 1, 2, 3, 4, 5, 6].map((d) => ({ jornada_id: j.id, dia_semana: d, entrada: '18:00', saida_intervalo: '22:00', volta_intervalo: '22:30', saida: '02:00' })))
    for (const f of CENARIO.funcionarios) {
      const [novo] = await tabela('gerente', 'funcionarios', 'POST', { empresa_id: empresa, nome: f.nome, cargo: 'Garçom', matricula: f.matricula, cpf: f.cpf, zig_employee_name: f.zig.trim(), pontos_comissao: f.pontos, data_admissao: D2 })
      f.id = novo.id
      await tabela('gerente', 'funcionario_jornadas', 'POST', { funcionario_id: novo.id, jornada_id: j.id, vigente_desde: D2 })
    }
    // cadastro com nome "de fórmula" (CSV injection) — 0 pontos, entra no fechamento só como participante sem valor
    const [formula] = await tabela('gerente', 'funcionarios', 'POST', { empresa_id: empresa, nome: '=HYPERLINK("http://evil.example";"x")', cargo: '@SUM(1)', data_admissao: D2, pontos_comissao: 0 })
    CENARIO.formula = formula.id

    // administrador: integrações (tela Integrações → Nova integração) apontando para o cenário
    ;[rep] = await tabela('admin', 'integracoes', 'POST', { empresa_id: empresa, tipo: 'controlid_rep', nome: 'iDClass R2', parametros: { modelo: 'iDClass', identificador: 'cpf', dias_retroativos: 2 } })
    await rpc('admin', 'integracao_definir_segredos', { p_integracao: rep.id, p_segredos: { url: `http://127.0.0.1:${mocks.portas.rep}`, login: 'admin', senha: 'admin' } })
    ;[zig] = await tabela('admin', 'integracoes', 'POST', { empresa_id: empresa, tipo: 'zig', nome: 'Zig R2', parametros: { rede: CENARIO.rede, dias_retroativos: 2 } })
    await rpc('admin', 'integracao_definir_segredos', { p_integracao: zig.id, p_segredos: { token: CENARIO.token } })
    const visiveis = await rpc('admin', 'integracao_segredos_preenchidos', { p_integracao: rep.id })
    assert.deepEqual([...visiveis].sort(), ['login', 'senha', 'url'], 'a tela só sabe QUAIS segredos estão preenchidos')
    await assert.rejects(tabela('admin', `integracoes_segredos?integracao_id=eq.${rep.id}`), /permission denied/, 'segredo nunca é lido pela API')

    ctx = {
      env: {
        SUPABASE_URL: sb.url, SUPABASE_SERVICE_ROLE_KEY: sb.servico, ZIG_BASE_URL: `http://127.0.0.1:${mocks.portas.zig}/integration`,
        MDG_WF_ZIG_IMPORTAR: 'wf-zig', MDG_WF_EXPORTAR_FECHAMENTO: 'wf-exp', MDG_WF_CONTROLID_USUARIOS: 'wf-u',
        MDG_WF_CONTROLID_BATIDAS: 'wf-b', MDG_WF_CONTROLID_EXPORTAR: 'wf-e', MDG_EMAIL_RELATORIOS: 'gerente@revisao2.local',
      },
      workflows: {
        fila: ler('comum/workflows/sincronizar-agora.json'),
        'wf-zig': ler('zig/workflows/zig-importar.json'),
        'wf-exp': ler('comum/workflows/exportar-fechamento.json'),
        'wf-u': ler('controlid/workflows/controlid-importar-usuarios.json'),
        'wf-b': ler('controlid/workflows/controlid-importar-batidas.json'),
        'wf-e': ler('controlid/workflows/controlid-exportar-usuarios.json'),
      },
      emails: [], http: [], esperaRetentativaMs: 10,
    }
  })
  after(async () => {
    if (mocks) await mocks.fechar()
    // a empresa de teste fica desativada (o master pode excluir pela tela)
    if (empresa) await chamar(sb.servico, `rest/v1/empresas?id=eq.${empresa}`, { method: 'PATCH', body: JSON.stringify({ ativa: false }) })
  })

  it('"Sincronizar agora" (gerente) → N8N importa usuários, AFD e Zig; ponto do dia, alarme e banco de horas batem com a conta à mão', async () => {
    assert.equal(await rpc('gerente', 'sync_solicitar', { p_escopo: 'tudo', p_empresa: empresa }), 2)
    await rodarFila()
    const ex = await tabela('servico', `sync_execucoes?select=tipo,status,erro,registros_gravados&empresa_id=eq.${empresa}&order=iniciado_em`)
    for (const e of ex) assert.equal(e.status, 'sucesso', `${e.tipo}: ${e.erro}`)
    assert.deepEqual(ex.map((e) => e.tipo).sort(), ['controlid_batidas', 'controlid_usuarios', 'zig_importar'])

    // usuários do REP ligados automaticamente pelo CPF
    const usuarios = await tabela('gerente', `controlid_usuarios?select=user_id_externo,funcionario_id,vinculo&integracao_id=eq.${rep.id}`)
    assert.equal(usuarios.filter((u) => u.funcionario_id && u.vinculo === 'automatico').length, 2)

    const [zeca, yara] = CENARIO.funcionarios
    // D-1 (ontem): tela "Ponto do dia"
    const dia = await rpc('gerente', 'ponto_dia_empresa', { p_data: D1, p_empresa: empresa })
    const z1 = dia.find((l) => l.funcionario_id === zeca.id)
    const y1 = dia.find((l) => l.funcionario_id === yara.id)
    // Zeca: 17:58, 22:01, 02:03(+1) → 3 de 4, trabalhado 243 (só o 1º par), saldo 243 − 450 = −207
    assert.equal(z1.batidas.filter((b) => !b.duplicada && !b.desconsiderada).length, 3)
    assert.equal(z1.trabalhado_minutos, 243)
    assert.equal(z1.saldo_minutos, -207)
    assert.equal(z1.situacao, 'incompleto')
    // Yara: 18:10, 22:00, 22:30, 01:55(+1) → 230 + 205 = 435; saldo −15 (> tolerância 10); atraso 10 (> 5)
    assert.equal(y1.trabalhado_minutos, 435)
    assert.equal(y1.saldo_minutos, -15)
    assert.equal(y1.atraso_minutos, 10)
    assert.equal(y1.situacao, 'completo')
    // D-2: Zeca 18:00, 22:00, 22:31, 02:05(+1), 02:06(+1, duplicada) → 240 + 214 = 454 → saldo 0 (|+4| ≤ 10)
    const esp = await rpc('gerente', 'ponto_espelho', { p_funcionario: zeca.id, p_inicio: D2, p_fim: D1 })
    const z2 = esp.find((l) => l.data === D2)
    assert.equal(z2.trabalhado_minutos, 454)
    assert.equal(z2.saldo_minutos, 0)
    assert.equal(z2.batidas.filter((b) => b.duplicada).length, 1, 'a batida de 02:06 é duplicada (janela 2 min)')
    // alarme identificando a batida faltante
    const alarmes = await tabela('gerente', `ponto_alarmes?select=id,tipo,batida_esperada,detalhe,status&funcionario_id=eq.${zeca.id}&data=eq.${D1}&status=eq.aberto`)
    assert.deepEqual(alarmes.map((a) => [a.tipo, a.batida_esperada, a.detalhe]), [['batida_faltando', 'volta_intervalo', 'Faltou a volta do intervalo (22:30)']])
    // banco de horas até ontem: Zeca 0 + (−207); Yara D-2 ausente (−450) + (−15)
    const banco = await rpc('gerente', 'banco_horas_resumo', { p_empresa: empresa })
    assert.equal(banco.find((b) => b.funcionario_id === zeca.id).saldo_minutos, -207)
    assert.equal(banco.find((b) => b.funcionario_id === yara.id).saldo_minutos, -465)

    // o gerente inclui a batida esquecida (22:30 de D-1) → dia completo, alarme resolvido sozinho, banco recalculado
    const instante = new Date(Date.parse(`${D1}T22:30:00-03:00`)).toISOString()
    await rpc('gerente', 'ponto_incluir_batida', { p_funcionario: zeca.id, p_instante: instante, p_motivo: 'Esqueceu na volta do jantar' })
    const z1b = (await rpc('gerente', 'ponto_dia_empresa', { p_data: D1, p_empresa: empresa })).find((l) => l.funcionario_id === zeca.id)
    assert.equal(z1b.trabalhado_minutos, 243 + 213) // 22:30 → 02:03
    assert.equal(z1b.saldo_minutos, 0) // 456 − 450 = 6 ≤ 10
    const [al] = await tabela('gerente', `ponto_alarmes?select=status,resolvido_automaticamente&id=eq.${alarmes[0].id}`)
    assert.deepEqual(al, { status: 'resolvido', resolvido_automaticamente: true })
    assert.equal((await rpc('gerente', 'banco_horas_resumo', { p_empresa: empresa })).find((b) => b.funcionario_id === zeca.id).saldo_minutos, 0)
  })

  it('Zig: faturamento, serviço e ranking de garçons (nome da Zig com caixa/espaço diferentes liga ao cadastro)', async () => {
    const [r] = await rpc('gerente', 'vendas_resumo', { p_inicio: D2, p_fim: D1, p_empresa: empresa })
    assert.equal(Number(r.faturamento), 23210 + 21585)
    assert.equal(Number(r.vendas), 40950)
    assert.equal(Number(r.servico), 3845)
    const ranking = await rpc('gerente', 'vendas_por_garcom', { p_inicio: D2, p_fim: D1, p_empresa: empresa })
    const por = (nome) => ranking.find((g) => g.funcionario_nome === nome)
    assert.deepEqual([Number(por('Zeca Silva').valor_vendas), Number(por('Zeca Silva').valor_servico), Number(por('Zeca Silva').transacoes)], [25670, 2567, 3])
    assert.deepEqual([Number(por('Yara Lima').valor_vendas), Number(por('Yara Lima').valor_servico), Number(por('Yara Lima').transacoes)], [12780, 1278, 2])
    const balcao = ranking.find((g) => g.employee_name == null)
    assert.equal(Number(balcao.valor_vendas), 2500)
  })

  it('reimportar (pedido com período) não duplica batidas nem vendas; duas importações SIMULTÂNEAS do mesmo dia também não', async () => {
    const contar = async () => ({
      batidas: (await tabela('servico', `ponto_batidas?select=id&integracao_id=eq.${rep.id}`)).length,
      itens: (await tabela('servico', `zig_vendas_itens?select=id&empresa_id=eq.${empresa}`)).length,
      fat: (await tabela('servico', `zig_faturamento?select=id&empresa_id=eq.${empresa}`)).length,
    })
    const antes = await contar()
    assert.deepEqual(antes, { batidas: 12, itens: 11, fat: 3 })
    assert.equal(await rpc('gerente', 'sync_solicitar', { p_escopo: 'tudo', p_empresa: empresa, p_data_inicio: D2, p_data_fim: hoje }), 2)
    await rodarFila()
    assert.deepEqual(await contar(), antes, 'reimportação idempotente')

    // V2-02: "Sincronizar agora" (fila) e o agendador rodando o MESMO subfluxo da Zig ao mesmo tempo (a fila não deduplica
    // contra o agendador, que chama o subfluxo direto). Antes da correção: itens do dia em dobro → serviço e comissão em dobro.
    assert.equal(await rpc('gerente', 'sync_solicitar', { p_integracao: zig.id, p_escopo: 'vendas', p_empresa: empresa, p_data_inicio: D2, p_data_fim: D1 }), 1)
    const agendado = { json: { integracao_id: zig.id, empresa_id: empresa, tipo: 'zig', escopo: 'tudo', gatilho: 'agendado', solicitacao_id: null, data_inicio: D2, data_fim: D1, parametros: {} } }
    const r2 = await Promise.all([executarWorkflow(ctx.workflows.fila, [], ctx), executarWorkflow(ctx.workflows['wf-zig'], [agendado], ctx), executarWorkflow(ctx.workflows['wf-zig'], [agendado], ctx)])
    for (const r of r2) assert.equal(r.erro, null, r.erro && `${r.erro.no}: ${r.erro.message}`)
    // e direto na RPC, 6 cargas paralelas do mesmo dia
    const itensDia = (await import('./mocks/cenario-revisao2.mjs')).vendas(D1).length
    assert.ok(itensDia > 0)
    const fat = [{ eventId: 'e', eventDate: `${D1}T00:00:00`, paymentId: 1, paymentName: 'Crédito', value: 21585 }]
    await Promise.all(Array.from({ length: 6 }, () => rpc('servico', 'ingestao_zig_faturamento', { p_integracao: zig.id, p_loja: CENARIO.loja.id, p_data: D1, p_itens: fat })))
    const linhas = await tabela('servico', `zig_vendas_itens?select=transaction_id,tipo&empresa_id=eq.${empresa}&data_operacao=eq.${D1}`)
    const chaves = linhas.map((l) => `${l.transaction_id}|${l.tipo}`)
    assert.equal(new Set(chaves).size, chaves.length, `itens duplicados: ${chaves.join(', ')}`)
    assert.deepEqual(await contar(), antes, 'cargas simultâneas não duplicam')
    const [r] = await rpc('gerente', 'vendas_resumo', { p_inicio: D2, p_fim: D1, p_empresa: empresa })
    assert.equal(Number(r.servico), 3845, 'serviço não dobra')
  })

  it('comissão: (3845 − 20%) = 3076 rateado 10:5 → Zeca 2051, Yara 1025; fechada é imutável; CSV do e-mail sem fórmula', async () => {
    const id = await rpc('gerente', 'comissao_criar_fechamento', { p_data_inicio: D2, p_data_fim: D1, p_empresa: empresa })
    await rpc('gerente', 'comissao_definir_item', { p_fechamento: id, p_funcionario: CENARIO.formula, p_pontos: 0, p_incluido: true })
    const [f] = await tabela('gerente', `comissao_fechamentos?select=servico_zig_centavos,retencao_centavos,base_distribuivel_centavos,soma_pontos_efetivos&id=eq.${id}`)
    assert.deepEqual([f.servico_zig_centavos, f.retencao_centavos, f.base_distribuivel_centavos, Number(f.soma_pontos_efetivos)], [3845, 769, 3076, 15])
    const itens = await tabela('gerente', `comissao_itens?select=funcionario_nome,valor_centavos&fechamento_id=eq.${id}&order=funcionario_nome`)
    // exato: Zeca 3076×10/15 = 2050,667 → 2050 + 1 (maior resto); Yara 3076×5/15 = 1025,333 → 1025
    assert.deepEqual(Object.fromEntries(itens.map((i) => [i.funcionario_nome, i.valor_centavos])), { 'Zeca Silva': 2051, 'Yara Lima': 1025, '=HYPERLINK("http://evil.example";"x")': 0 })
    await assert.rejects(rpc('gerente', 'comissao_fechar', { p_fechamento: id }), /Somente o administrador fecha/, 'gerente não fecha')
    await rpc('admin', 'comissao_fechar', { p_fechamento: id })
    for (const quem of ['admin', 'master', 'gerente']) {
      await assert.rejects(rpc(quem, 'comissao_atualizar_fechamento', { p_fechamento: id, p_titulo: 'x', p_servico_ajuste_centavos: 100000, p_percentual_retencao: 0, p_proporcional_dias: false, p_observacoes: null }), /já está fechado/)
      await assert.rejects(rpc(quem, 'comissao_definir_item', { p_fechamento: id, p_funcionario: CENARIO.funcionarios[0].id, p_pontos: 99 }), /já está fechado/)
    }
    // exportação por e-mail (N8N) e CSV
    assert.equal(await rpc('admin', 'sync_solicitar', { p_escopo: 'exportar_fechamento', p_empresa: empresa, p_parametros: { fechamento_id: id } }), 1)
    await rodarFila()
    const email = ctx.emails.at(-1)
    const csv = Buffer.from(Object.values(email.anexos)[0].data, 'base64').toString('utf8')
    assert.match(csv, /\r\nZeca Silva;Garçom;Sim;10;2;10;20,51\r\n/)
    assert.match(csv, /\r\nYara Lima;Garçom;Sim;5;1;5;10,25\r\n/)
    assert.match(csv, /\r\n"'=HYPERLINK\(""http:\/\/evil.example"";""x""\)";'@SUM\(1\);Sim;0;0;0;0,00\r\n/, 'célula de fórmula neutralizada com apóstrofo')
    assert.match(csv, /\r\nTotal;;;15;;15;30,76\r\n$/)
  })
})
