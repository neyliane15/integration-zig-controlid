/** Casca, menu por papel e seletor de empresa (dono: frontend-1). Exigem o ambiente local (§15.2). */
import { backendNoAr, entrar, expect, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar (npm run local)')
})

async function abrirMenu(page: import('@playwright/test').Page) {
  if ((page.viewportSize()?.width ?? 0) < 1024) await page.getByRole('button', { name: 'Abrir menu' }).click()
  return page.getByRole('navigation', { name: 'Menu principal' }).last()
}

test('gerente: menu sem Usuários nem Empresas; painel sem rolagem horizontal', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await expect(page.getByText('Alarmes de ponto')).toBeVisible()
  await semRolagemHorizontal(page)
  const menu = await abrirMenu(page)
  for (const item of ['Painel', 'Ponto', 'Banco de horas', 'Funcionários', 'Vendas', 'Comissões', 'Tarefas', 'Integrações', 'Configurações'])
    await expect(menu.getByRole('link', { name: item, exact: true })).toBeVisible()
  await expect(menu.getByRole('link', { name: 'Usuários', exact: true })).toHaveCount(0)
  await expect(menu.getByRole('link', { name: 'Empresas', exact: true })).toHaveCount(0)
})

test('leitura: não vê Comissões nem Integrações e recebe "Sem permissão" pela URL', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.leitura)
  const menu = await abrirMenu(page)
  await expect(menu.getByRole('link', { name: 'Comissões', exact: true })).toHaveCount(0)
  await expect(menu.getByRole('link', { name: 'Integrações', exact: true })).toHaveCount(0)
  await page.goto('/integracoes')
  await expect(page.getByText('Sem permissão')).toBeVisible()
})

test('administrador: integrações nunca mostram segredos', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/integracoes')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Integra')
  await page.getByRole('link', { name: 'Detalhes' }).first().click()
  await page.getByRole('tab', { name: 'Configuração' }).click()
  await expect(page.getByText('Configurado').first()).toBeVisible()
  const valores = await page.locator('input').evaluateAll((els) => els.map((e) => (e as HTMLInputElement).value))
  expect(valores.join(' ')).not.toMatch(/token-mock|admin123/)
  await semRolagemHorizontal(page)
})

test('master: seletor de empresa troca o contexto', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.master)
  await abrirMenu(page)
  const seletor = page.locator('[data-teste="seletor-empresa"]').last()
  await expect(seletor).toBeVisible()
  await seletor.selectOption({ label: 'Cantina Roma' })
  await page.goto('/master/empresas')
  // (revisão 1) o nome aparece no seletor e na lista: confere só o que está visível
  await expect(page.getByText('Bar Bossa Nova').filter({ visible: true }).first()).toBeVisible()
  await expect(page.getByText('(selecionada)').filter({ visible: true }).first()).toBeVisible()
})

test('desktop: barra lateral ocupa a altura toda mesmo com conteúdo mais longo que a tela', async ({ page }) => {
  test.skip((page.viewportSize()?.width ?? 0) < 1024, 'só no desktop')
  await page.setViewportSize({ width: 1440, height: 600 })
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/ponto')
  await expect(page.getByText('Ana Souza').filter({ visible: true }).first()).toBeVisible()
  const medidas = await page.evaluate(() => {
    const a = document.querySelector('[data-teste="barra-lateral"]')!.getBoundingClientRect()
    return { lateral: a.height, documento: document.documentElement.scrollHeight, janela: window.innerHeight }
  })
  expect(medidas.documento, 'a página de teste precisa ser mais longa que a janela').toBeGreaterThan(medidas.janela)
  expect(medidas.lateral).toBeGreaterThanOrEqual(medidas.documento - 1)
  // o menu continua visível depois de rolar até o fim
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight))
  await expect(page.getByRole('navigation', { name: 'Menu principal' }).first().getByRole('link', { name: 'Painel', exact: true })).toBeInViewport()
})

test('página inexistente mostra 404 dentro da casca', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/nao-existe')
  await expect(page.getByText('Página não encontrada')).toBeVisible()
})
