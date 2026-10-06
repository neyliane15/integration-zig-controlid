/**
 * Apoio dos testes e2e (dono: frontend-1).
 * - `test`: igual ao do Playwright, mas FALHA se o navegador registrar erro no console ou exceção (§15.4).
 *   Use `ignorarErrosDoConsole(page, /padrão/)` para erros esperados (ex.: rede indisponível de propósito).
 * - Credenciais da carga de demonstração (§15.3) e `entrar()`.
 */
import { test as base, expect, type Page } from '@playwright/test'

const ignorados = new WeakMap<Page, RegExp[]>()

export function ignorarErrosDoConsole(page: Page, ...padroes: RegExp[]): void {
  ignorados.set(page, [...(ignorados.get(page) ?? []), ...padroes])
}

export const test = base.extend<{ vigiarConsole: void }>({
  vigiarConsole: [
    async ({ page }, use) => {
      const erros: string[] = []
      page.on('console', (m) => {
        if (m.type() === 'error') erros.push(m.text())
      })
      page.on('pageerror', (e) => erros.push(`pageerror: ${e.message}`))
      await use()
      const padroes = ignorados.get(page) ?? []
      const relevantes = erros.filter((e) => !padroes.some((p) => p.test(e)))
      expect(relevantes, 'erros no console do navegador').toEqual([])
    },
    { auto: true },
  ],
})

export { expect }

export const SENHA_DEMO = 'gerente123'
export const USUARIOS_DEMO = {
  master: 'master@meudiadegerente.app',
  admin: 'admin@barbossanova.com.br',
  gerente: 'gerente@barbossanova.com.br',
  leitura: 'leitura@barbossanova.com.br',
  adminB: 'admin@cantinaroma.com.br',
} as const

/** Lê o VITE_SUPABASE_URL do ambiente / .env.local / .env (para saber se o backend local está no ar). */
export async function urlSupabase(): Promise<string | null> {
  if (process.env.VITE_SUPABASE_URL) return process.env.VITE_SUPABASE_URL
  const { readFileSync, existsSync } = await import('node:fs')
  for (const arq of ['.env.local', '.env']) {
    if (!existsSync(arq)) continue
    const m = readFileSync(arq, 'utf8').match(/^VITE_SUPABASE_URL=(.+)$/m)
    if (m?.[1]) return m[1].trim()
  }
  return null
}

let cacheBackend: boolean | null = null
/** true se o backend (portão local ou Supabase) responde. Testes que precisam de login usam `test.skip(!await backendNoAr())`. */
export async function backendNoAr(): Promise<boolean> {
  if (cacheBackend != null) return cacheBackend
  const url = await urlSupabase()
  if (!url || /SEU-PROJETO/.test(url)) return (cacheBackend = false)
  try {
    const r = await fetch(`${url.replace(/\/$/, '')}/auth/v1/health`, { signal: AbortSignal.timeout(2500) })
    cacheBackend = r.status < 500
  } catch {
    cacheBackend = false
  }
  return cacheBackend
}

/** Faz login pela tela e espera a casca. */
export async function entrar(page: Page, email: string, senha = SENHA_DEMO): Promise<void> {
  await page.goto('/entrar')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha', { exact: true }).fill(senha)
  await page.getByRole('button', { name: 'Entrar', exact: true }).click()
  await expect(page.locator('#conteudo')).toBeVisible({ timeout: 15_000 })
}

/** A página não pode ter rolagem horizontal (§14.1). */
export async function semRolagemHorizontal(page: Page): Promise<void> {
  const largura = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth])
  expect(largura[0], 'rolagem horizontal').toBeLessThanOrEqual(largura[1]!)
}
