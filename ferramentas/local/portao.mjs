// Portão local que imita o necessário do Supabase para o front e o N8N (só desenvolvimento).
//   /auth/v1/*  → GoTrue mínimo (senha bcrypt em auth.users, via funções local_auth no PostgREST)
//   /rest/v1/*  → repassa ao PostgREST
// JWT HS256 com segredo local. Sem dependências (só Node ≥ 22).
//
// Uso:
//   node ferramentas/local/portao.mjs              # sobe na porta 54321 (MDG_PORTA_PORTAO)
//   node ferramentas/local/portao.mjs --chaves     # imprime {"anon": "...", "service_role": "..."} e sai
// Variáveis: MDG_JWT_SEGREDO, MDG_PORTA_PORTAO (54321), MDG_POSTGREST_URL (http://127.0.0.1:54323)

import { createServer } from 'node:http'
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto'

const SEGREDO = process.env.MDG_JWT_SEGREDO || 'segredo-local-do-meu-dia-de-gerente-nao-use-em-producao'
const PORTA = Number(process.env.MDG_PORTA_PORTAO || 54321)
const POSTGREST = (process.env.MDG_POSTGREST_URL || 'http://127.0.0.1:54323').replace(/\/$/, '')
const EMISSOR = `http://127.0.0.1:${PORTA}/auth/v1`
const DURACAO = 3600

// ------------------------------------------------------------------------------------------- JWT
const b64url = (buf) => Buffer.from(buf).toString('base64url')

export function assinarJwt(carga, segredo = SEGREDO) {
  const cabecalho = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const corpo = b64url(JSON.stringify(carga))
  const assinatura = createHmac('sha256', segredo).update(`${cabecalho}.${corpo}`).digest('base64url')
  return `${cabecalho}.${corpo}.${assinatura}`
}

export function verificarJwt(token, segredo = SEGREDO) {
  const partes = String(token || '').split('.')
  if (partes.length !== 3) return null
  const esperado = createHmac('sha256', segredo).update(`${partes[0]}.${partes[1]}`).digest()
  const recebido = Buffer.from(partes[2], 'base64url')
  if (recebido.length !== esperado.length || !timingSafeEqual(recebido, esperado)) return null
  try {
    const carga = JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8'))
    if (carga.exp && carga.exp < Math.floor(Date.now() / 1000)) return null
    return carga
  } catch {
    return null
  }
}

export function chaves(segredo = SEGREDO) {
  const iat = 1759708800 // fixo: as chaves não mudam entre execuções
  const exp = iat + 20 * 365 * 24 * 3600
  return {
    anon: assinarJwt({ iss: 'supabase-local', role: 'anon', iat, exp }, segredo),
    service_role: assinarJwt({ iss: 'supabase-local', role: 'service_role', iat, exp }, segredo),
  }
}

// ---------------------------------------------------------------------------------- PostgREST
const CHAVES = chaves()

async function rpcAuth(nome, args) {
  const r = await fetch(`${POSTGREST}/rpc/${nome}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${CHAVES.service_role}`,
      'Content-Profile': 'local_auth',
      'Accept-Profile': 'local_auth',
    },
    body: JSON.stringify(args),
  })
  const texto = await r.text()
  const corpo = texto ? JSON.parse(texto) : null
  if (!r.ok) {
    const erro = new Error(corpo?.message || `PostgREST ${r.status}`)
    erro.status = r.status === 409 ? 422 : 400
    throw erro
  }
  return corpo
}

function sessao(usuario) {
  const agora = Math.floor(Date.now() / 1000)
  const sessaoId = randomUUID()
  const access = assinarJwt({
    aud: 'authenticated', exp: agora + DURACAO, iat: agora, iss: EMISSOR, sub: usuario.id, email: usuario.email,
    phone: '', app_metadata: usuario.app_metadata, user_metadata: usuario.user_metadata, role: 'authenticated',
    aal: 'aal1', amr: [{ method: 'password', timestamp: agora }], session_id: sessaoId, is_anonymous: false,
  })
  const refresh = assinarJwt({ tipo: 'refresh', sub: usuario.id, iat: agora, exp: agora + 30 * 24 * 3600, jti: randomUUID() })
  return {
    access_token: access, token_type: 'bearer', expires_in: DURACAO, expires_at: agora + DURACAO,
    refresh_token: refresh, user: usuario,
  }
}

// --------------------------------------------------------------------------------------- HTTP
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD',
  'Access-Control-Allow-Headers':
    'authorization, apikey, content-type, x-client-info, prefer, range, range-unit, accept-profile, content-profile, ' +
    'x-supabase-api-version, accept',
  'Access-Control-Expose-Headers': 'content-range, content-profile, content-location, preference-applied, location',
  'Access-Control-Max-Age': '86400',
}

function responder(res, status, corpo) {
  res.writeHead(status, { ...CORS, 'Content-Type': 'application/json; charset=utf-8' })
  res.end(corpo === undefined ? '' : JSON.stringify(corpo))
}

function erroAuth(res, status, mensagem, codigo = 'erro') {
  responder(res, status, { code: status, error_code: codigo, msg: mensagem, error: codigo, error_description: mensagem })
}

async function lerCorpo(req) {
  const partes = []
  for await (const p of req) partes.push(p)
  return Buffer.concat(partes)
}

function usuarioDoToken(req) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '')
  const carga = verificarJwt(token)
  return carga && carga.role === 'authenticated' && carga.sub ? carga : null
}

async function tratarAuth(req, res, caminho, url) {
  if (caminho === '/auth/v1/health') return responder(res, 200, { name: 'GoTrue (local)', version: 'mdg-local' })
  if (caminho === '/auth/v1/settings') {
    return responder(res, 200, {
      external: { email: true, google: false, phone: false }, disable_signup: false, mailer_autoconfirm: true,
      phone_autoconfirm: false, sms_provider: '',
    })
  }
  const bruto = req.method === 'GET' ? Buffer.alloc(0) : await lerCorpo(req)
  let corpo = {}
  try {
    corpo = bruto.length ? JSON.parse(bruto.toString('utf8')) : {}
  } catch {
    return erroAuth(res, 400, 'JSON inválido', 'bad_json')
  }

  if (caminho === '/auth/v1/token' && req.method === 'POST') {
    const tipo = url.searchParams.get('grant_type')
    if (tipo === 'password') {
      const usuario = await rpcAuth('entrar', { p_email: corpo.email || '', p_senha: corpo.password || '' })
      if (!usuario) return erroAuth(res, 400, 'Invalid login credentials', 'invalid_credentials')
      return responder(res, 200, sessao(usuario))
    }
    if (tipo === 'refresh_token') {
      const carga = verificarJwt(corpo.refresh_token)
      if (!carga || carga.tipo !== 'refresh') return erroAuth(res, 400, 'Invalid Refresh Token', 'refresh_token_not_found')
      const usuario = await rpcAuth('usuario', { p_id: carga.sub })
      if (!usuario) return erroAuth(res, 400, 'User not found', 'user_not_found')
      return responder(res, 200, sessao(usuario))
    }
    return erroAuth(res, 400, 'grant_type não suportado', 'unsupported_grant_type')
  }

  if (caminho === '/auth/v1/signup' && req.method === 'POST') {
    try {
      const usuario = await rpcAuth('cadastrar', { p_email: corpo.email || '', p_senha: corpo.password || '', p_meta: corpo.data || {} })
      return responder(res, 200, sessao(usuario))
    } catch (e) {
      return erroAuth(res, e.status || 400, e.message, /registered/.test(e.message) ? 'user_already_exists' : 'validation_failed')
    }
  }

  if (caminho === '/auth/v1/recover' && req.method === 'POST') {
    console.log(`[portão] recuperação de senha pedida para ${corpo.email} (local: nenhum e-mail é enviado)`)
    return responder(res, 200, {})
  }

  if (caminho === '/auth/v1/logout' && req.method === 'POST') {
    res.writeHead(204, CORS)
    return res.end()
  }

  if (caminho === '/auth/v1/user') {
    const carga = usuarioDoToken(req)
    if (!carga) return erroAuth(res, 401, 'invalid JWT', 'bad_jwt')
    if (req.method === 'GET') {
      const usuario = await rpcAuth('usuario', { p_id: carga.sub })
      return usuario ? responder(res, 200, usuario) : erroAuth(res, 404, 'User not found', 'user_not_found')
    }
    if (req.method === 'PUT') {
      try {
        const usuario = await rpcAuth('atualizar', { p_id: carga.sub, p_senha: corpo.password ?? null, p_meta: corpo.data ?? null })
        return responder(res, 200, usuario)
      } catch (e) {
        return erroAuth(res, 422, e.message, 'weak_password')
      }
    }
  }

  return erroAuth(res, 404, `Rota não implementada no portão local: ${req.method} ${caminho}`, 'not_found')
}

async function repassarRest(req, res, url) {
  const destino = `${POSTGREST}${url.pathname.replace(/^\/rest\/v1/, '') || '/'}${url.search}`
  const cabecalhos = {}
  for (const [k, v] of Object.entries(req.headers)) {
    if (['host', 'connection', 'content-length', 'apikey', 'accept-encoding'].includes(k)) continue
    cabecalhos[k] = v
  }
  // Sem Authorization, o apikey vale como token (comportamento do Supabase).
  if (!cabecalhos.authorization && req.headers.apikey) cabecalhos.authorization = `Bearer ${req.headers.apikey}`
  const corpo = ['GET', 'HEAD'].includes(req.method) ? undefined : await lerCorpo(req)
  const r = await fetch(destino, { method: req.method, headers: cabecalhos, body: corpo })
  const saida = { ...CORS }
  r.headers.forEach((v, k) => {
    if (k.startsWith('access-control-')) return // o CORS é do portão (evita cabeçalho duplicado)
    if (!['content-encoding', 'transfer-encoding', 'connection', 'content-length'].includes(k)) saida[k] = v
  })
  res.writeHead(r.status, saida)
  res.end(Buffer.from(await r.arrayBuffer()))
}

export function criarPortao() {
  return createServer(async (req, res) => {
    const url = new URL(req.url, `http://127.0.0.1:${PORTA}`)
    try {
      if (req.method === 'OPTIONS') {
        // Aceita qualquer cabeçalho pedido (supabase-js manda x-client-info, x-retry-count, …).
        const pedidos = req.headers['access-control-request-headers']
        res.writeHead(204, pedidos ? { ...CORS, 'Access-Control-Allow-Headers': pedidos } : CORS)
        return res.end()
      }
      if (url.pathname.startsWith('/auth/v1/')) return await tratarAuth(req, res, url.pathname.replace(/\/$/, ''), url)
      if (url.pathname === '/rest/v1' || url.pathname.startsWith('/rest/v1/')) return await repassarRest(req, res, url)
      if (url.pathname.startsWith('/storage/v1/')) {
        return responder(res, 501, { statusCode: '501', error: 'not_implemented', message: 'Storage não existe no ambiente local' })
      }
      return responder(res, 404, { message: 'não encontrado' })
    } catch (e) {
      console.error('[portão]', e)
      return responder(res, 502, { message: `Falha no portão local: ${e.message}` })
    }
  })
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (process.argv.includes('--chaves')) {
    console.log(JSON.stringify(chaves()))
  } else {
    criarPortao().listen(PORTA, '127.0.0.1', () => {
      console.log(`[portão] http://127.0.0.1:${PORTA} → PostgREST ${POSTGREST}`)
    })
  }
}
