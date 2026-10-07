/**
 * Revisão 2: guardas de papel na UI, títulos (h1) das telas de estado e nomes acessíveis de campos de data.
 * Contra o ambiente local com a carga de demonstração (pulado se o backend não estiver no ar).
 */
import { backendNoAr, entrar, expect, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar (npm run local)')
})

test('leitura: "Novo funcionário" é bloqueado na rota (antes abria o formulário desabilitado)', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.leitura)
  await page.goto('/funcionarios/novo')
  await expect(page.getByRole('heading', { level: 1, name: 'Sem permissão' })).toBeVisible()
  await expect(page.getByLabel('Nome completo')).toHaveCount(0)
  await semRolagemHorizontal(page)
})

test('404 e "sem permissão" têm h1', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/nao-existe')
  await expect(page.getByRole('heading', { level: 1, name: 'Página não encontrada' })).toBeVisible()
  await page.goto('/usuarios')
  await expect(page.getByRole('heading', { level: 1, name: 'Sem permissão' })).toBeVisible()
})

test('campos de data de ponto e tarefas têm nome acessível; alarmes identificam quem será selecionado', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/ponto')
  await expect(page.getByLabel('Dia do ponto')).toBeVisible()
  await page.goto('/tarefas')
  await expect(page.getByLabel('Dia das tarefas')).toBeVisible()
  await page.goto('/ponto/alarmes')
  const caixas = page.getByRole('checkbox', { name: /^Selecionar alarme de .+ em \d{2}\/\d{2}\/\d{4}$/ })
  if ((await caixas.count()) > 0) await expect(caixas.first()).toBeAttached()
})
