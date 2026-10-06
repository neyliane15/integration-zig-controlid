// Testes do mock (n8n/mocks/servidor.mjs) — garantem o comportamento que n8n-1 e n8n-2 usam. node --test / vitest.
import assert from 'node:assert/strict'
import { iniciarMocks } from './servidor.mjs'

const { test, before, after } = process.env.VITEST ? await import('vitest') : await import('node:test')
const beforeAll = process.env.VITEST ? (await import('vitest')).beforeAll : before
const afterAll = process.env.VITEST ? (await import('vitest')).afterAll : after

let m
const post = async (porta, caminho, corpo, tipo = 'application/json') => {
  const r = await fetch(`http://127.0.0.1:${porta}${caminho}`, { method: 'POST', headers: { 'content-type': tipo }, body: tipo === 'application/json' ? JSON.stringify(corpo) : corpo })
  const t = await r.text()
  let j = t
  try { j = JSON.parse(t) } catch { /* texto */ }
  return { status: r.status, corpo: j }
}
beforeAll(async () => {
  process.env.MOCK_AGORA = '2026-10-06T12:00:00-03:00'
  m = await iniciarMocks({ zig: 0, acesso: 0, rep: 0 })
})
afterAll(async () => {
  await m.fechar()
  delete process.env.MOCK_AGORA
})

test('Zig: autenticação, lojas, dados determinísticos e erros fixos', async () => {
  const z = (c, h = { Authorization: 'token-mock' }) => fetch(`http://127.0.0.1:${m.portas.zig}/integration${c}`, { headers: h })
  assert.equal((await z('/erp/lojas?rede=rede-mock', {})).status, 401)
  assert.deepEqual(await (await z('/erp/lojas?rede=rede-mock')).json(), [{ id: 'loja-1', name: 'Bossa Nova Salão' }])
  const a = await (await z('/erp/saida-produtos?dtinicio=2026-10-03&dtfim=2026-10-03&loja=loja-1')).json()
  const b = await (await z('/erp/saida-produtos?dtinicio=2026-10-03&dtfim=2026-10-03&loja=loja-1')).json()
  assert.deepEqual(a, b)
  assert.ok(a.some((i) => i.type === 'Tip'))
  assert.ok(new Set(a.map((i) => i.employeeName)).has('Ana Souza'))
  assert.deepEqual(await (await z('/erp/faturamento?dtinicio=2026-10-07&dtfim=2026-10-07&loja=loja-1')).json(), [], 'futuro vazio')
  assert.equal((await z('/erp/faturamento?dtinicio=2026-10-05&dtfim=2026-10-05&loja=loja-500')).status, 500)
  const r429 = await z('/erp/faturamento?dtinicio=2026-10-05&dtfim=2026-10-05&loja=loja-429')
  assert.equal(r429.status, 429)
  assert.equal(r429.headers.get('retry-after'), '1')
  assert.equal((await z('/erp/faturamento?dtinicio=2026-10-05&loja=loja-1')).status, 400)
})

test('Control iD acesso: sessão, logs, escrita, foto, senha e erro simulável', async () => {
  const p = m.portas.acesso
  assert.equal((await post(p, '/login.fcgi', { login: 'admin', password: 'x' })).status, 401)
  const { corpo: { session } } = await post(p, '/login.fcgi', { login: 'admin', password: 'admin' })
  assert.equal(session, 'sessao-mock')
  const s = `?session=${session}`
  assert.equal((await post(p, '/load_objects.fcgi?session=errada', { object: 'users' })).status, 401)
  const users = (await post(p, `/load_objects.fcgi${s}`, { object: 'users' })).corpo.users
  assert.deepEqual(users.map((u) => [u.id, u.registration]), [[1, '1'], [2, '2'], [3, '3'], [4, '4'], [5, '5']])
  const logs = (await post(p, `/load_objects.fcgi${s}`, { object: 'access_logs' })).corpo.access_logs
  assert.ok(logs.length > 50 && logs.every((l) => l.event === 7))
  // Carla (user 3) sem a volta do intervalo no dia de trabalho de anteontem (2026-10-04, domingo, escala 17/21/21:30/01)
  const bloco = (iso) => Math.round((Date.parse(iso) - Date.parse('2026-01-01')) / 86400000) // ids = dia*100 + seq
  assert.equal(logs.filter((l) => l.user_id === 3 && Math.floor(l.id / 100) === bloco('2026-10-04')).length, 3)
  assert.equal(logs.filter((l) => l.user_id === 3 && Math.floor(l.id / 100) === bloco('2026-10-03')).length, 4)
  const T = logs[10].time
  const filtrados = (await post(p, `/load_objects.fcgi${s}`, { object: 'access_logs', where: { access_logs: { time: { '>=': T } } }, limit: 5, offset: 2 })).corpo.access_logs
  assert.equal(filtrados.length, 5)
  assert.ok(filtrados.every((l) => l.time >= T))
  // escrita
  const { corpo: { ids: [novo] } } = await post(p, `/create_objects.fcgi${s}`, { object: 'users', values: [{ name: 'Novo', registration: 9 }] })
  assert.equal(novo, 6)
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'cards', values: [{ value: 123, user_id: novo }] })).status, 200)
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'cards', values: [{ value: 123, user_id: novo }] })).status, 400)
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'user_access_rules', values: [{ user_id: novo, access_rule_id: 99 }] })).status, 400)
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'users', values: [{ name: 'X #ERRO' }] })).status, 400)
  assert.deepEqual((await post(p, `/modify_objects.fcgi${s}`, { object: 'users', values: { end_time: 1 }, where: { users: { id: novo } } })).corpo, { changes: 1 })
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3])
  assert.equal((await post(p, `/user_set_image.fcgi${s}&user_id=${novo}&match=0&timestamp=100`, jpeg, 'application/octet-stream')).status, 200)
  assert.equal((await post(p, `/user_set_image.fcgi${s}&user_id=${novo}`, Buffer.from('texto'), 'image/jpeg')).status, 400)
  const h1 = (await post(p, `/user_hash_password.fcgi${s}`, { password: '1234' })).corpo
  const h2 = (await post(p, `/user_hash_password.fcgi${s}`, { password: '1234' })).corpo
  assert.deepEqual(h1, h2)
  assert.match(h1.password, /^[0-9a-f]{64}$/)
  let estado = await (await fetch(`http://127.0.0.1:${p}/__estado`)).json()
  assert.equal(estado.imagens[novo].bytes, 7)
  assert.equal(estado.objetos.cards.length, 1)
  assert.deepEqual((await post(p, `/destroy_objects.fcgi${s}`, { object: 'users', where: { users: { id: novo } } })).corpo, { changes: 1 })
  estado = await (await fetch(`http://127.0.0.1:${p}/__estado`)).json()
  assert.equal(estado.objetos.cards.length, 0, 'cascata')
  assert.equal(estado.imagens[novo], undefined)
  // falha injetada
  await post(p, '/__mock/falhas', { caminho: '/create_objects.fcgi', status: 500, vezes: 1 })
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'users', values: [{ name: 'Y' }] })).status, 500)
  assert.equal((await post(p, `/create_objects.fcgi${s}`, { object: 'users', values: [{ name: 'Y' }] })).status, 200)
  assert.equal((await post(p, `/logout.fcgi${s}`, {})).status, 200)
  assert.equal((await post(p, `/load_objects.fcgi${s}`, { object: 'users' })).status, 401)
})

test('Control iD REP: usuários, envio e AFD 671', async () => {
  const p = m.portas.rep
  const { corpo: { session } } = await post(p, '/login.fcgi', { login: 'admin', password: 'admin' })
  const s = `?session=${session}`
  const u = (await post(p, `/load_users.fcgi${s}`, {})).corpo.users
  assert.equal(u.length, 5)
  assert.equal(u[0].cpf, 52998224725)
  assert.equal((await post(p, `/add_users.fcgi${s}`, { users: [{ name: 'FULANO', cpf: 12345678909, registration: 7 }] })).status, 200)
  assert.equal((await post(p, `/add_users.fcgi${s}`, { users: [{ name: 'FULANO', cpf: 12345678909 }] })).status, 400)
  assert.equal((await post(p, `/update_users.fcgi${s}`, { users: [{ cpf: 12345678909, name: 'FULANO 2' }] })).status, 200)
  assert.equal((await post(p, `/update_users.fcgi${s}`, { users: [{ cpf: 1, name: 'X' }] })).status, 400)
  assert.equal((await post(p, `/load_users.fcgi${s}`, { limit: 2, offset: 5 })).corpo.users[0].name, 'FULANO 2')
  assert.equal((await post(p, `/remove_users.fcgi${s}`, { users: [12345678909] })).status, 200)
  assert.equal((await post(p, `/remove_users.fcgi${s}`, { users: [12345678909] })).status, 400)
  const afd = (await post(p, `/get_afd.fcgi${s}`, { initial_date: { day: 5, month: 10, year: 2026 } })).corpo
  const linhas = afd.split('\r\n').filter(Boolean)
  const tipo3 = linhas.filter((l) => l[9] === '3')
  assert.ok(tipo3.length > 0)
  assert.ok(tipo3.every((l) => l.length === 50 && l[20] === 'T' && l.slice(10, 20) >= '2026-10-05'))
  const nsr = Number(tipo3[3].slice(0, 9))
  const depois = (await post(p, `/get_afd.fcgi${s}`, { initial_nsr: nsr })).corpo.split('\r\n').filter((l) => l[9] === '3')
  assert.equal(Number(depois[0].slice(0, 9)), nsr)
  assert.equal(depois.length, tipo3.length - 3)
})
