// Ponta a ponta: o MESMO código das libs que vai nos nós Code, falando HTTP de verdade com o mock do n2
// (n8n/mocks/servidor.mjs, portas aleatórias). Só o Supabase fica de fora (os corpos das RPCs são conferidos).
// Rodam com `node --test n8n/controlid/lib/` e com `npm test` (vitest). Sem o mock no repositório, são puladas.
import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { createServer } from 'node:net'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as L from './controlid.mjs'
import { lerAfd, separarLotes } from './afd.mjs'

const { describe, it, before, after } = process.env.VITEST
  ? await import('vitest').then((v) => ({ ...v, before: v.beforeAll, after: v.afterAll }))
  : await import('node:test')

const CAMINHO_MOCK = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'mocks', 'servidor.mjs')
const temMock = existsSync(CAMINHO_MOCK)
const CPFS = ['52998224725', '11144477735', '39053344705', '15350946056', '71428793860']
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0, 1, 0xff, 0xd9])

/** Adaptador http da lib com fetch (no N8N é adaptadorHttpN8n com this.helpers.httpRequest). */
async function httpFetch({ metodo, url, corpo, corpoBinario, tipoConteudo, timeoutMs, texto }) {
  const binario = corpoBinario !== undefined && corpoBinario !== null
  const r = await fetch(url, {
    method: metodo || 'POST',
    headers: { 'Content-Type': binario ? tipoConteudo || 'application/octet-stream' : 'application/json' },
    body: binario ? corpoBinario : corpo === undefined || corpo === null ? undefined : JSON.stringify(corpo),
    signal: AbortSignal.timeout(timeoutMs || 30000),
  })
  return { status: r.status, corpo: texto ? await r.text() : await r.text() }
}

describe('ponta a ponta contra o mock do n2', { skip: !temMock && 'n8n/mocks/servidor.mjs ausente' }, () => {
  let mocks, base, diaTrabalho
  const urlDe = (q) => `http://127.0.0.1:${mocks.portas[q]}`
  const controle = async (q, caminho, corpo) => {
    const r = await fetch(urlDe(q) + caminho, corpo === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
    return r.json()
  }
  const config = (tipo, extra = {}) => ({
    integracao_id: 'a0000000-0000-4000-8000-00000000010' + (tipo === 'controlid_acesso' ? '2' : '3'),
    empresa_id: 'a0000000-0000-4000-8000-00000000000a', tipo, nome: tipo, ativa: true,
    parametros: { dias_retroativos: 7, relogio_em_hora_local: true, identificador: 'cpf', espera_segundos: 0, timeout_segundos: 5, ...(extra.parametros || {}) },
    segredos: { url: urlDe(tipo === 'controlid_acesso' ? 'acesso' : 'rep'), login: 'admin', senha: 'admin' },
    cursor: extra.cursor || {}, fuso: 'America/Sao_Paulo', virada_dia: '05:00:00', dia_trabalho_atual: diaTrabalho,
  })

  before(async () => {
    const { iniciarMocks } = await import(CAMINHO_MOCK)
    mocks = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
    base = await controle('acesso', '/__mock/estado')
    diaTrabalho = base.dia_trabalho
  })
  after(async () => { if (mocks) await mocks.fechar() })

  it('acesso: importa os 5 usuários e faz logout', async () => {
    const r = await L.buscarUsuarios({ http: httpFetch, config: config('controlid_acesso') })
    assert.equal(r.ok, true, r.erro)
    assert.deepEqual(r.usuarios.map((u) => u.registration), ['1', '2', '3', '4', '5'])
    assert.equal(r.usuarios[0].name, 'Ana Souza')
    const chamadas = await controle('acesso', '/__mock/chamadas')
    assert.equal(chamadas.at(-1).caminho.startsWith('/logout.fcgi'), true)
  })

  it('acesso: importa batidas (hora local), lotes e payload da RPC', async () => {
    const r = await L.buscarBatidas({ http: httpFetch, config: config('controlid_acesso'), entrada: {} })
    assert.equal(r.ok, true, r.erro)
    assert.ok(r.batidas.length > 20, `batidas: ${r.batidas.length}`)
    for (const b of r.batidas) {
      assert.match(b.instante_local, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/)
      assert.equal(b.evento, 7)
      assert.ok(['1', '2', '3', '4', '5'].includes(b.user_id))
    }
    // horários da escala do mock aparecem como hora de parede (17:00, 21:00, 21:30, 01:00, 10:00…)
    assert.ok(r.batidas.some((b) => /T17:0\d:/.test(b.instante_local)))
    const lotes = separarLotes(r, 1000)
    assert.equal(lotes[0].lote.length, r.batidas.length)
    // segunda leitura com cursor: só a janela desde cursor − 1 dia
    const ultimo = r.batidas.map((b) => b.instante_local).sort().at(-1)
    const r2 = await L.buscarBatidas({ http: httpFetch, config: config('controlid_acesso', { cursor: { ultimo_id: '9', ultimo_instante: ultimo + '-03:00' } }), entrada: {} })
    assert.ok(r2.batidas.length < r.batidas.length)
    assert.ok(r2.batidas.every((b) => b.instante_local >= L.dataMaisDias(ultimo.slice(0, 10), -1)))
  })

  it('acesso: sessão expirada no meio e 503 transitório são recuperados', async () => {
    await controle('acesso', '/__mock/falhas', { caminho: '/load_objects.fcgi', status: 401, vezes: 1 })
    await controle('acesso', '/__mock/falhas', { caminho: '/load_objects.fcgi', status: 503, vezes: 1 })
    const r = await L.buscarUsuarios({ http: httpFetch, config: config('controlid_acesso') })
    assert.equal(r.ok, true, r.erro)
    assert.equal(r.usuarios.length, 5)
    assert.equal(r.tentativas, 2)
  })

  it('acesso: senha errada → erro claro', async () => {
    const c = config('controlid_acesso')
    c.segredos.senha = 'errada'
    const r = await L.buscarUsuarios({ http: httpFetch, config: c })
    assert.equal(r.ok, false)
    assert.match(r.erro, /Login recusado/)
  })

  it('REP: importa usuários por CPF', async () => {
    const r = await L.buscarUsuarios({ http: httpFetch, config: config('controlid_rep') })
    assert.equal(r.ok, true, r.erro)
    assert.deepEqual(r.usuarios.map((u) => u.id).sort(), [...CPFS].sort())
  })

  it('REP: AFD 671 sem cursor e depois pelo NSR (incremental)', async () => {
    const r = await L.buscarBatidas({ http: httpFetch, config: config('controlid_rep'), entrada: {} })
    assert.equal(r.ok, true, r.erro)
    assert.deepEqual(r.detalhes.afd_pedido.initial_date.year > 2000, true)
    const leitura = lerAfd(r.afd)
    assert.ok(leitura.marcacoes.length > 20)
    assert.equal(leitura.ignoradas.length, 0, JSON.stringify(leitura.ignoradas))
    assert.ok(leitura.marcacoes.every((m) => CPFS.includes(m.cpf) && /-03:00$/.test(m.instante)))
    assert.ok(leitura.outros_registros['9'] >= 1)
    const maxNsr = Math.max(...leitura.marcacoes.map((m) => m.nsr))
    const r2 = await L.buscarBatidas({ http: httpFetch, config: config('controlid_rep', { cursor: { ultimo_nsr: maxNsr - 3 } }), entrada: {} })
    assert.deepEqual(r2.detalhes.afd_pedido, { initial_nsr: maxNsr - 2 })
    assert.deepEqual(lerAfd(r2.afd).marcacoes.map((m) => m.nsr), [maxNsr - 2, maxNsr - 1, maxNsr])
  })

  it('envio acesso: horários, criar/alterar/bloquear/remover, senha, cartões, regras e foto — idempotente', async () => {
    await controle('acesso', '/__mock/reset', {})
    const envio = { ativo: true, foto: true, cartao: true, senha: true, horarios: true, ao_desligar: 'remover' }
    const horarios = {
      envio_id: 'h1', versao: 1, alvo: 'horarios', operacao: 'salvar', mapa_anterior: {},
      horarios: [{ horario_id: 'H-noite', nome: 'Salão noite', faixas: [
        { dia_semana: 6, inicio: '16:30:00', fim: '23:59:59', inicio_segundos: 59400, fim_segundos: 86399 },
        { dia_semana: 5, inicio: '16:30:00', fim: '23:59:59' },
        { dia_semana: 0, inicio: '00:00:00', fim: '02:00:00' },
      ] }],
    }
    const r1 = await L.enviarPendencias({ http: httpFetch, config: config('controlid_acesso'), pendencias: { tipo: 'controlid_acesso', envio, itens: [horarios] } })
    assert.equal(r1.resultados[0].status, 'enviado', r1.resultados[0].erro)
    const mapa = r1.resultados[0].mapa_remoto
    const regra = mapa['H-noite'].access_rule_id
    let est = await controle('acesso', '/__estado')
    assert.equal(est.objetos.time_spans.filter((s) => s.time_zone_id === mapa['H-noite'].time_zone_id).length, 2) // sex+sáb agrupados
    const itens = [
      { envio_id: 'f6', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'F6', id_remoto: null,
        usuario: { nome: 'Fabio Novo', matricula: '6', cpf: '12345678909', pis: null }, senha: '1234', cartoes: ['123456789', '987'],
        foto: { bucket: 'funcionarios-fotos', caminho: 'e/f/x.jpg', atualizado_em: '2026-10-06T12:00:00Z' }, regras_acesso: [{ horario_id: 'H-noite', access_rule_id: regra }] },
      { envio_id: 'f1', versao: 2, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'F1', id_remoto: '1',
        usuario: { nome: 'Ana Souza Lima', matricula: '1', cpf: CPFS[0], pis: null }, senha: null, cartoes: [], foto: null, regras_acesso: [] },
      { envio_id: 'f2', versao: 1, alvo: 'funcionario', operacao: 'bloquear', funcionario_id: 'F2', id_remoto: '2',
        usuario: { nome: 'Bruno Lima', matricula: '2' }, senha: null, cartoes: [], foto: null, regras_acesso: [] },
      { envio_id: 'f3', versao: 1, alvo: 'funcionario', operacao: 'remover', funcionario_id: null, id_remoto: '3',
        usuario: { nome: 'Carla Dias', matricula: '3' }, senha: null, cartoes: [], foto: null, regras_acesso: [] },
      { envio_id: 'f4', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'F4', id_remoto: '4',
        usuario: { nome: 'Davi #ERRO', matricula: '4' }, senha: null, cartoes: [], foto: null, regras_acesso: [] },
      { envio_id: 'f5', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_id: 'F5', id_remoto: null,
        usuario: { nome: 'Eva Martins', matricula: '5' }, senha: null, cartoes: null, foto: undefined, regras_acesso: null },
    ]
    const baixarFoto = async (foto) => { assert.equal(foto.caminho, 'e/f/x.jpg'); return JPEG }
    const r2 = await L.enviarPendencias({ http: httpFetch, config: config('controlid_acesso'), pendencias: { tipo: 'controlid_acesso', envio, itens }, baixarFoto })
    const porId = Object.fromEntries(r2.resultados.map((r) => [r.envio_id, r]))
    for (const id of ['f6', 'f1', 'f2', 'f3', 'f5']) assert.equal(porId[id].status, 'enviado', `${id}: ${porId[id].erro}`)
    assert.equal(porId.f4.status, 'erro')
    assert.match(porId.f4.erro, /#ERRO/)
    assert.equal(porId.f5.id_remoto, '5') // reaproveitou pela matrícula, não duplicou
    assert.deepEqual(porId.f3.id_remoto, null)
    est = await controle('acesso', '/__estado')
    const novo = est.objetos.users.find((u) => u.registration === '6')
    assert.equal(porId.f6.id_remoto, String(novo.id))
    assert.ok(novo.password && novo.salt, 'senha com hash')
    assert.deepEqual(est.objetos.cards.filter((c) => c.user_id === novo.id).map((c) => c.value).sort((a, b) => a - b), [987, 123456789])
    assert.deepEqual(est.objetos.user_access_rules.filter((x) => x.user_id === novo.id).map((x) => x.access_rule_id), [regra])
    assert.ok(est.imagens[novo.id], 'foto enviada')
    assert.equal(est.objetos.users.find((u) => u.id === 1).name, 'Ana Souza Lima')
    assert.ok(est.objetos.users.find((u) => u.id === 2).end_time > 0, 'bloqueado')
    assert.equal(est.objetos.users.some((u) => u.id === 3), false, 'removido')
    assert.equal(est.objetos.users.filter((u) => u.registration === '5').length, 1)
    // idempotência: reenviar o mesmo payload não duplica nada nem reenvia a foto
    const r3 = await L.enviarPendencias({ http: httpFetch, config: config('controlid_acesso'), pendencias: { tipo: 'controlid_acesso', envio, itens: itens.filter((i) => i.envio_id !== 'f4') }, baixarFoto })
    assert.ok(r3.resultados.every((r) => r.status === 'enviado'), JSON.stringify(r3.resultados.filter((r) => r.status !== 'enviado')))
    const est2 = await controle('acesso', '/__estado')
    assert.equal(est2.objetos.users.length, est.objetos.users.length)
    assert.equal(est2.objetos.cards.length, est.objetos.cards.length)
    assert.ok(porId.f6.acoes.includes('foto_enviada'))
    assert.ok(r3.resultados.find((r) => r.envio_id === 'f6').acoes.includes('foto_igual'))
    const chamadas = await controle('acesso', '/__mock/chamadas')
    assert.equal(chamadas.at(-1).caminho.startsWith('/logout.fcgi'), true)
    // horários de novo (mapa anterior) recria sem deixar sobra
    const r4 = await L.enviarPendencias({ http: httpFetch, config: config('controlid_acesso'), pendencias: { tipo: 'controlid_acesso', envio, itens: [{ ...horarios, versao: 2, mapa_anterior: mapa }] } })
    assert.equal(r4.resultados[0].status, 'enviado', r4.resultados[0].erro)
    const est3 = await controle('acesso', '/__estado')
    assert.equal(est3.objetos.time_zones.filter((t) => t.name.startsWith('MDG ')).length, 1)
    assert.equal(est3.objetos.access_rules.filter((t) => t.name.startsWith('MDG ')).length, 1)
    // corpos prontos para ingestao_controlid_envio_resultado
    const itensRpc = L.itensDeResultado(r2)
    assert.deepEqual(Object.keys(itensRpc[0].corpo), ['p_envio', 'p_versao', 'p_status', 'p_id_remoto', 'p_erro', 'p_mapa_remoto'])
    const resumo = L.resumirEnvio({ envio: r2, itens: itensRpc, respostas: itensRpc.map(() => ({ status: 'enviado', versao: 1 })) })
    assert.equal(resumo[0].finalizacao.p_status, 'parcial')
    assert.equal(resumo[0].finalizacao.p_gravados, 5)
  })

  it('envio REP: criar, alterar, trocar CPF, remover; sem CPF → erro do item', async () => {
    await controle('rep', '/__mock/reset', {})
    const envio = { ativo: true, foto: true, cartao: true, senha: true, horarios: true, ao_desligar: 'bloquear' }
    const itens = [
      { envio_id: 'r6', versao: 1, alvo: 'funcionario', operacao: 'salvar', id_remoto: null,
        usuario: { nome: 'Fabio Novo', matricula: '6', cpf: '12345678909' }, senha: '4321', cartoes: ['555'], foto: null, regras_acesso: null },
      { envio_id: 'r1', versao: 1, alvo: 'funcionario', operacao: 'salvar', id_remoto: CPFS[0],
        usuario: { nome: 'Ana Souza Lima', matricula: '1', cpf: CPFS[0] }, senha: null, cartoes: [], foto: null, regras_acesso: null },
      { envio_id: 'r2', versao: 1, alvo: 'funcionario', operacao: 'salvar', id_remoto: CPFS[1],
        usuario: { nome: 'Bruno Lima', matricula: '2', cpf: '98765432100' }, senha: null, cartoes: [], foto: null, regras_acesso: null },
      { envio_id: 'r3', versao: 1, alvo: 'funcionario', operacao: 'bloquear', id_remoto: CPFS[2],
        usuario: { nome: 'Carla Dias' }, senha: null, cartoes: [], foto: null, regras_acesso: null },
      { envio_id: 'r9', versao: 1, alvo: 'funcionario', operacao: 'salvar', id_remoto: null,
        usuario: { nome: 'Sem Documento', matricula: '9', cpf: null }, senha: null, cartoes: [], foto: null, regras_acesso: null },
    ]
    const r = await L.enviarPendencias({ http: httpFetch, config: config('controlid_rep'), pendencias: { tipo: 'controlid_rep', envio, identificador: 'cpf', itens } })
    const porId = Object.fromEntries(r.resultados.map((x) => [x.envio_id, x]))
    for (const id of ['r6', 'r1', 'r2', 'r3']) assert.equal(porId[id].status, 'enviado', `${id}: ${porId[id].erro}`)
    assert.equal(porId.r9.status, 'erro')
    assert.equal(porId.r9.erro, 'CPF obrigatório no REP')
    assert.equal(porId.r2.id_remoto, '98765432100')
    const est = await controle('rep', '/__estado')
    const cpfs = est.rep_usuarios.map((u) => String(u.cpf).padStart(11, '0'))
    assert.ok(cpfs.includes('12345678909') && cpfs.includes('98765432100'))
    assert.equal(cpfs.includes(CPFS[1]), false)
    assert.equal(cpfs.includes(CPFS[2]), false)
    const fabio = est.rep_usuarios.find((u) => u.cpf === 12345678909)
    assert.equal(fabio.password, '4321')
    assert.equal(fabio.rfid, 555)
    assert.equal(fabio.registration, 6)
    // repetir: update em vez de add, sem erro
    const r2 = await L.enviarPendencias({ http: httpFetch, config: config('controlid_rep'), pendencias: { tipo: 'controlid_rep', envio, identificador: 'cpf', itens: itens.slice(0, 4) } })
    assert.ok(r2.resultados.every((x) => x.status === 'enviado'), JSON.stringify(r2.resultados))
  })

  it('envio sem itens não loga no equipamento; equipamento fora do ar → erro em todos os itens', async () => {
    const antes = (await controle('acesso', '/__mock/chamadas')).length
    const vazio = await L.enviarPendencias({ http: httpFetch, config: config('controlid_acesso'), pendencias: { tipo: 'controlid_acesso', envio: { ativo: false }, itens: [] } })
    assert.equal(vazio.ok, true)
    assert.equal((await controle('acesso', '/__mock/chamadas')).length, antes)
    const c = config('controlid_acesso')
    const livre = createServer()
    await new Promise((ok) => livre.listen(0, '127.0.0.1', ok))
    const porta = livre.address().port
    await new Promise((ok) => livre.close(ok))
    c.segredos.url = 'http://127.0.0.1:' + porta
    const fora = await L.enviarPendencias({ http: httpFetch, config: c, pendencias: { tipo: 'controlid_acesso', envio: {}, itens: [{ envio_id: 'x', versao: 1, alvo: 'funcionario', operacao: 'remover', id_remoto: '1' }] } })
    assert.equal(fora.resultados[0].status, 'erro')
    assert.match(fora.resultados[0].erro, /conexão recusada/)
  })
})
