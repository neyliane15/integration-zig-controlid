/**
 * Configuração do front lida do ambiente (Vite). Dono: frontend-1.
 * Só valores PÚBLICOS: URL do Supabase e chave anon. Nunca a service_role.
 */

const env = import.meta.env

export const configuracao = {
  nomeApp: 'Meu Dia de Gerente',
  supabaseUrl: (env.VITE_SUPABASE_URL as string | undefined)?.trim() ?? '',
  supabaseAnonKey: (env.VITE_SUPABASE_ANON_KEY as string | undefined)?.trim() ?? '',
  /** Botão "Entrar com Google": escondido só com VITE_LOGIN_GOOGLE=false (contrato §14.2). */
  loginGoogle: String(env.VITE_LOGIN_GOOGLE ?? 'true').trim().toLowerCase() !== 'false',
  fusoPadrao: 'America/Sao_Paulo',
  viradaPadrao: '05:00',
} as const

/** Chaves de armazenamento local (prefixo `mdg:`). */
export const CHAVES_LOCAIS = {
  lembrar: 'mdg:lembrar',
  empresaMaster: 'mdg:empresa',
  menuRecolhido: 'mdg:menu-recolhido',
} as const

/** Lê do localStorage sem quebrar em modo privado/bloqueado. */
export function lerLocal(chave: string): string | null {
  try {
    return window.localStorage.getItem(chave)
  } catch {
    return null
  }
}

export function gravarLocal(chave: string, valor: string | null): void {
  try {
    if (valor == null) window.localStorage.removeItem(chave)
    else window.localStorage.setItem(chave, valor)
  } catch {
    /* armazenamento indisponível: segue sem lembrar */
  }
}
