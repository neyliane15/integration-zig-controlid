/**
 * Cliente Supabase + utilitários de chamada (contrato §14.2 e §14.6). Dono: frontend-1.
 */
import { createClient } from '@supabase/supabase-js'
import type { Rpcs } from '@/tipos/banco'
import { CHAVES_LOCAIS, configuracao, lerLocal } from './configuracao'

/** true quando VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY não foram definidos (a tela de entrada avisa). */
export const configuracaoAusente = !configuracao.supabaseUrl || !configuracao.supabaseAnonKey

/**
 * "Manter-me conectado": com `localStorage['mdg:lembrar'] === '0'` a sessão vai para o sessionStorage
 * (some ao fechar o navegador); caso contrário, localStorage.
 */
function armazenamento(): Storage | null {
  try {
    return lerLocal(CHAVES_LOCAIS.lembrar) === '0' ? window.sessionStorage : window.localStorage
  } catch {
    return null
  }
}

const memoria = new Map<string, string>()

const armazenamentoDaSessao = {
  getItem(chave: string): string | null {
    const s = armazenamento()
    if (!s) return memoria.get(chave) ?? null
    try {
      return s.getItem(chave) ?? (s === window.sessionStorage ? null : window.sessionStorage.getItem(chave))
    } catch {
      return memoria.get(chave) ?? null
    }
  },
  setItem(chave: string, valor: string): void {
    const s = armazenamento()
    if (!s) return void memoria.set(chave, valor)
    try {
      s.setItem(chave, valor)
      // evita sessão "fantasma" no outro armazenamento
      const outro = s === window.localStorage ? window.sessionStorage : window.localStorage
      outro.removeItem(chave)
    } catch {
      memoria.set(chave, valor)
    }
  },
  removeItem(chave: string): void {
    memoria.delete(chave)
    try {
      window.localStorage.removeItem(chave)
      window.sessionStorage.removeItem(chave)
    } catch {
      /* nada */
    }
  },
}

export const supabase = createClient(
  configuracao.supabaseUrl || 'http://127.0.0.1:54321',
  configuracao.supabaseAnonKey || 'chave-ausente',
  {
    auth: {
      storage: armazenamentoDaSessao,
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'mdg-auth',
    },
  },
)

/** Erro de API com o código do Postgres/GoTrue preservado (ex.: '42501'). */
export class ErroApi extends Error {
  codigo: string | null
  constructor(mensagem: string, codigo: string | null = null) {
    super(mensagem)
    this.name = 'ErroApi'
    this.codigo = codigo
  }
}

/** Traduções para mensagens que vêm em inglês do GoTrue/PostgREST/navegador. As do §10.9 passam como vierem. */
const TRADUCOES: [RegExp, string][] = [
  [/invalid login credentials/i, 'E-mail ou senha incorretos.'],
  [/email not confirmed/i, 'Confirme seu e-mail antes de entrar (veja sua caixa de entrada).'],
  [/user already registered|already been registered/i, 'E-mail já cadastrado'],
  [/password should be at least|at least 6 characters/i, 'A senha deve ter pelo menos 6 caracteres'],
  [/unable to validate email|invalid email|email address .* is invalid/i, 'E-mail inválido'],
  [/new password should be different/i, 'A nova senha precisa ser diferente da atual.'],
  [/rate limit|too many requests|security purposes/i, 'Muitas tentativas. Aguarde um pouco e tente de novo.'],
  [/failed to fetch|networkerror|network request failed|load failed/i, 'Sem conexão com o servidor. Verifique a internet e tente de novo.'],
  [/jwt expired|invalid jwt|refresh token/i, 'Sua sessão expirou. Entre novamente.'],
  [/row-level security|permission denied/i, 'Sem permissão'],
  [/signups not allowed|signup is disabled/i, 'Cadastro de novas contas desativado.'],
  [/auth session missing/i, 'O link expirou ou já foi usado. Peça um novo.'],
]

/** Converte qualquer erro (Error, PostgrestError, AuthError, string) em texto para o usuário. */
export function mensagemDeErro(e: unknown): string {
  let texto = ''
  if (typeof e === 'string') texto = e
  else if (e instanceof Error) texto = e.message
  else if (e && typeof e === 'object' && 'message' in e) texto = String((e as { message: unknown }).message)
  texto = texto.trim()
  if (!texto) return 'Algo deu errado. Tente de novo.'
  for (const [padrao, traducao] of TRADUCOES) if (padrao.test(texto)) return traducao
  return texto
}

function codigoDe(e: unknown): string | null {
  if (e && typeof e === 'object' && 'code' in e) {
    const c = (e as { code: unknown }).code
    return c == null ? null : String(c)
  }
  return null
}

/** Desembrulha `{ data, error }` do supabase-js: lança `ErroApi` se houver erro. */
export function exigir<T>(r: { data: T | null; error: unknown }): T {
  if (r.error) throw new ErroApi(mensagemDeErro(r.error), codigoDe(r.error))
  return r.data as T
}

/** Chamada tipada de RPC (mapa `Rpcs` em tipos/banco.ts). Lança `ErroApi` com a mensagem do banco. */
export async function chamarRpc<K extends keyof Rpcs>(nome: K, args: Rpcs[K]['args']): Promise<Rpcs[K]['retorno']> {
  const { data, error } = await supabase.rpc(nome as string, args as Record<string, unknown>)
  if (error) throw new ErroApi(mensagemDeErro(error), codigoDe(error))
  return data as Rpcs[K]['retorno']
}
