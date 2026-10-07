/**
 * Playwright (contrato §15.4). Dono: frontend-1.
 * Projetos `desktop` (1440×900) e `celular` (390×844). Sobe o Vite em 127.0.0.1:5173 (ou reaproveita).
 * Testes que precisam do banco rodam contra o ambiente local (§15.2: `npm run local` grava `.env.local`) e são
 * pulados se ele não estiver no ar. Chromium: PW_CHROMIUM, ou o instalado em /opt/pw-browsers, ou o padrão do Playwright.
 */
import { defineConfig, devices } from '@playwright/test'
import { existsSync, readdirSync } from 'node:fs'

function chromiumLocal(): string | undefined {
  if (process.env.PW_CHROMIUM) return process.env.PW_CHROMIUM
  const raiz = '/opt/pw-browsers'
  if (!existsSync(raiz)) return undefined
  const pasta = readdirSync(raiz)
    .filter((d) => /^chromium-\d+$/.test(d))
    .sort()
    .pop()
  const exe = pasta ? `${raiz}/${pasta}/chrome-linux/chrome` : undefined
  return exe && existsSync(exe) ? exe : undefined
}

const executablePath = chromiumLocal()
const baseURL = process.env.E2E_URL ?? 'http://127.0.0.1:5173'

export default defineConfig({
  testDir: 'e2e',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  timeout: 30_000,
  expect: { timeout: 7_000 },
  use: {
    baseURL,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    launchOptions: executablePath ? { executablePath } : {},
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'celular', use: { ...devices['Desktop Chrome'], viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } },
  ],
  webServer: process.env.E2E_URL
    ? undefined
    : {
        command: 'npm run dev',
        url: baseURL,
        reuseExistingServer: true,
        timeout: 60_000,
      },
})
