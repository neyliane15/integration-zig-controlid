// Testes das funções puras do envio sistema → equipamento (adendo A.5) em lib/controlid.mjs.
import assert from 'node:assert/strict'
import * as L from './controlid.mjs'

const { describe, it } = process.env.VITEST ? await import('vitest') : await import('node:test')

describe('horários → time_spans', () => {
  it('segundos do dia', () => {
    assert.equal(L.segundosDoDia('16:30'), 59400)
    assert.equal(L.segundosDoDia('23:59:59'), 86399)
    assert.equal(L.segundosDoDia('24:00:00'), 86399)
    assert.equal(L.segundosDoDia('x'), null)
  })
  it('agrupa faixas iguais em um span com as flags dos dias (0 = domingo = sun)', () => {
    const spans = L.faixasParaTimeSpans([
      { dia_semana: 6, inicio: '16:30:00', fim: '23:59:59', inicio_segundos: 59400, fim_segundos: 86399 },
      { dia_semana: 5, inicio: '16:30:00', fim: '23:59:59' },
      { dia_semana: 0, inicio: '00:00:00', fim: '02:00:00' },
    ], 101)
    assert.deepEqual(spans, [
      { time_zone_id: 101, start: 0, end: 7200, sun: 1, mon: 0, tue: 0, wed: 0, thu: 0, fri: 0, sat: 0, hol1: 0, hol2: 0, hol3: 0 },
      { time_zone_id: 101, start: 59400, end: 86399, sun: 0, mon: 0, tue: 0, wed: 0, thu: 0, fri: 1, sat: 1, hol1: 0, hol2: 0, hol3: 0 },
    ])
    assert.deepEqual(L.faixasParaTimeSpans([], 1), [])
    assert.throws(() => L.faixasParaTimeSpans([{ dia_semana: 7, inicio: '08:00', fim: '09:00' }], 1), /Faixa de horário inválida/)
    assert.throws(() => L.faixasParaTimeSpans([{ dia_semana: 1, inicio: '10:00', fim: '09:00' }], 1), /Faixa de horário inválida/)
  })
})

describe('corpos do envio', () => {
  it('create/modify/destroy/load', () => {
    assert.deepEqual(L.corpoCriar('cards', [{ value: 1, user_id: 2 }]), { object: 'cards', values: [{ value: 1, user_id: 2 }] })
    assert.deepEqual(L.corpoModificar('users', { name: 'A' }, { id: 3 }), { object: 'users', values: { name: 'A' }, where: { users: { id: 3 } } })
    assert.deepEqual(L.corpoApagar('users', { id: 3 }), { object: 'users', where: { users: { id: 3 } } })
    assert.deepEqual(L.corpoCarregar('time_zones'), { object: 'time_zones' })
  })
  it('cartão', () => {
    assert.equal(L.numeroCartao('0012-345'), 12345)
    assert.equal(L.numeroCartao(255 * 2 ** 32 + 65535), 1095216726015)
    assert.throws(() => L.numeroCartao('99999999999999999999'), /grande demais/)
    assert.throws(() => L.numeroCartao('abc'), /Número de cartão inválido/)
  })
  it('usuário do REP (cpf/pis numéricos, senha e rfid só com recurso ligado)', () => {
    const item = { usuario: { nome: 'Fulano de Tal', matricula: '7', cpf: '01234567890', pis: '12345678901' }, senha: '1234', cartoes: ['555', '666'] }
    assert.deepEqual(L.corpoUsuarioRep(item, 'cpf', { senha: true, cartao: true }), { name: 'Fulano de Tal', cpf: 1234567890, registration: 7, password: '1234', rfid: 555 })
    assert.deepEqual(L.corpoUsuarioRep(item, 'pis', {}), { name: 'Fulano de Tal', pis: 12345678901, registration: 7 })
    assert.deepEqual(L.corpoUsuarioRep({ ...item, senha: null, cartoes: [] }, 'cpf', { senha: true, cartao: true }).password, '')
    assert.equal(L.corpoUsuarioRep({ usuario: { nome: 'X'.repeat(80), matricula: 'A-1', cpf: '1' } }, 'cpf', {}).name.length, 52)
    assert.equal(L.chaveRep({ cpf: null, pis: '1' }, 'cpf'), null)
  })
  it('url da foto no Storage', () => {
    assert.equal(L.urlFotoStorage('http://sb/', { bucket: 'funcionarios-fotos', caminho: 'e1/f 1/x.jpg' }), 'http://sb/storage/v1/object/funcionarios-fotos/e1/f%201/x.jpg')
    assert.equal(L.base64DeBytes(new Uint8Array([255, 216])), '/9g=')
  })
})

describe('diferenças (envio idempotente)', () => {
  it('usuário', () => {
    assert.deepEqual(L.diffUsuarioAcesso(null, { nome: ' Ana ', matricula: 1 }), { name: 'Ana', registration: '1' })
    assert.equal(L.diffUsuarioAcesso({ name: 'Ana', registration: '1', end_time: 0 }, { nome: 'Ana', matricula: '1' }), null)
    assert.deepEqual(L.diffUsuarioAcesso({ name: 'Ana', registration: '1', end_time: 999 }, { nome: 'Ana S', matricula: '1' }), { name: 'Ana S', end_time: 0 })
  })
  it('cartões: apaga os que sobram, cria os que faltam, toma de outro usuário', () => {
    const d = L.diffCartoes([{ id: 1, value: 10, user_id: 5 }, { id: 2, value: 20, user_id: 5 }], [{ id: 9, value: 30, user_id: 8 }], ['20', '30'], 5)
    assert.deepEqual(d, { apagar: [1, 9], criar: [{ value: 30, user_id: 5 }] })
    assert.deepEqual(L.diffCartoes([{ id: 1, value: 10, user_id: 5 }], [], ['10'], 5), { apagar: [], criar: [] })
    assert.deepEqual(L.diffCartoes([{ id: 1, value: 10, user_id: 5 }], [], [], 5).apagar, [1])
  })
  it('regras de acesso', () => {
    assert.deepEqual(L.diffRegras([{ access_rule_id: 1 }, { access_rule_id: 2 }], [{ access_rule_id: 2 }, { access_rule_id: 3 }]), { apagar: [1], criar: [3] })
    assert.deepEqual(L.diffRegras([], []), { apagar: [], criar: [] })
  })
})

describe('resultado e resumo do envio', () => {
  const envio = {
    ok: true, erro: null, tentativas: 1, lidos: 3, detalhes: { tipo: 'controlid_acesso' }, execucao_id: 'ex',
    resultados: [
      { envio_id: 'a', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_nome: 'Ana', status: 'enviado', id_remoto: '1', erro: null, mapa_remoto: null, acoes: [] },
      { envio_id: 'b', versao: 2, alvo: 'horarios', operacao: 'salvar', funcionario_nome: null, status: 'enviado', id_remoto: null, erro: null, mapa_remoto: { h: { time_zone_id: 1, access_rule_id: 2 } }, acoes: [] },
      { envio_id: 'c', versao: 1, alvo: 'funcionario', operacao: 'salvar', funcionario_nome: 'Bia', status: 'erro', id_remoto: null, erro: 'User not found', mapa_remoto: null, acoes: [] },
    ],
  }
  it('corpo da RPC de resultado', () => {
    const itens = L.itensDeResultado(envio)
    assert.equal(itens.length, 3)
    assert.deepEqual(itens[1].corpo, { p_envio: 'b', p_versao: 2, p_status: 'enviado', p_id_remoto: null, p_erro: null, p_mapa_remoto: { h: { time_zone_id: 1, access_rule_id: 2 } } })
    assert.deepEqual(L.itensDeResultado({ resultados: [] }), [{ sem_item: true }])
  })
  it('parcial quando parte falha; erro de registro também conta', () => {
    const itens = L.itensDeResultado(envio)
    const r = L.resumirEnvio({ envio, itens, respostas: [{ status: 'enviado' }, { error: { message: 'Envio não encontrado' } }, { status: 'erro' }] })
    const f = r[0].finalizacao
    assert.equal(f.p_status, 'parcial')
    assert.equal(f.p_gravados, 1)
    assert.equal(f.p_detalhes.com_erro, 2)
    assert.match(f.p_detalhes.erros[0].erro, /registro do resultado: Envio não encontrado/)
    assert.equal(r[0].saida.execucao_ids[0], 'ex')
  })
  it('sem pendências → sucesso; falha ao pegar pendências → erro', () => {
    const vazio = L.resumirEnvio({ envio: { ok: true, lidos: 0, detalhes: {}, execucao_id: 'ex' }, itens: [{ sem_item: true }], respostas: [] })
    assert.equal(vazio[0].finalizacao.p_status, 'sucesso')
    const ruim = L.resumirEnvio({ envio: { ok: false, erro: 'Falha ao ler as pendências de envio: x', lidos: 0, detalhes: {} }, itens: [{ sem_item: true }] })
    assert.equal(ruim[0].finalizacao.p_status, 'erro')
  })
  it('enviarPendencias com erro do Supabase não chama o equipamento', async () => {
    let chamou = false
    const r = await L.enviarPendencias({ http: async () => { chamou = true }, config: {}, pendencias: { error: { message: 'Integração inativa' } } })
    assert.equal(r.ok, false)
    assert.match(r.erro, /Integração inativa/)
    assert.equal(chamou, false)
  })
})
