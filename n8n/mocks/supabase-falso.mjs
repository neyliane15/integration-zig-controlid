// Supabase (PostgREST) falso, só para testes das libs do N8N: registra as chamadas de RPC e devolve respostas plausíveis.
// Não substitui o banco real (ferramentas/local); serve para testar o caminho HTTP ponta a ponta sem Postgres.
// Uso: const sb = await iniciarSupabaseFalso({ chave: 'service-falsa', rpcs: { nome: (args) => resposta } })
//      sb.url, sb.chamadas (lista {rpc, args}), sb.fechar()

import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'

const contar = (args) => {
  const n = Array.isArray(args?.p_itens) ? args.p_itens.length : Array.isArray(args?.p_lojas) ? args.p_lojas.length : 0
  return { lidos: n, gravados: n, ignorados: 0, removidos: 0 }
}

export const RPCS_PADRAO = {
  ingestao_sync_iniciar: () => randomUUID(),
  ingestao_sync_finalizar: () => undefined, // void → 204
  ingestao_sync_concluir_solicitacao: () => undefined,
  ingestao_sync_pegar_solicitacoes: () => [],
  ingestao_integracoes_ativas: () => [],
  ingestao_zig_lojas: contar,
  ingestao_zig_saida_produtos: contar,
  ingestao_zig_faturamento: contar,
  ingestao_zig_compradores: contar,
  ingestao_zig_faturamento_bandeiras: contar,
  ingestao_apurar_ponto: () => ({ empresas: 1, funcionarios: 5, dias: 15 }),
  ingestao_tarefas_gerar: () => 2,
}

export async function iniciarSupabaseFalso(opcoes = {}) {
  const chave = opcoes.chave || 'service-role-falsa'
  const rpcs = { ...RPCS_PADRAO, ...(opcoes.rpcs || {}) }
  const tabelas = opcoes.tabelas || {}
  const chamadas = []
  const servidor = createServer((req, res) => {
    const partes = []
    req.on('data', (c) => partes.push(c))
    req.on('end', async () => {
      const responder = (status, corpo) => {
        if (corpo === undefined) { res.writeHead(status); return res.end() }
        res.writeHead(status, { 'content-type': 'application/json' })
        res.end(JSON.stringify(corpo))
      }
      if (req.headers.apikey !== chave || req.headers.authorization !== `Bearer ${chave}`) return responder(401, { message: 'Invalid API key' })
      const url = new URL(req.url, 'http://x')
      const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_0-9]+)$/)
      try {
        if (m && req.method === 'POST') {
          const args = partes.length ? JSON.parse(Buffer.concat(partes).toString('utf8')) : {}
          chamadas.push({ rpc: m[1], args })
          const f = rpcs[m[1]]
          if (!f) return responder(404, { code: 'PGRST202', message: `Could not find the function public.${m[1]}` })
          const r = await f(args, chamadas)
          return r === undefined ? responder(204) : responder(200, r)
        }
        const t = url.pathname.match(/^\/rest\/v1\/([a-z_0-9]+)$/)
        if (t && req.method === 'GET') {
          chamadas.push({ tabela: t[1], filtros: Object.fromEntries(url.searchParams) })
          const f = tabelas[t[1]]
          return responder(200, f ? await f(Object.fromEntries(url.searchParams)) : [])
        }
        return responder(404, { message: 'not found' })
      } catch (e) {
        return responder(e.status || 400, { code: e.code || 'P0001', message: e.message })
      }
    })
  })
  await new Promise((ok) => servidor.listen(0, '127.0.0.1', ok))
  return {
    url: `http://127.0.0.1:${servidor.address().port}`,
    chave,
    chamadas,
    rpcs,
    fechar: () => new Promise((ok) => servidor.close(ok)),
  }
}
