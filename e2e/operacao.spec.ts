/**
 * Operação do dia (dono: frontend-2): funcionários, ponto, banco de horas, vendas, comissões, tarefas.
 * Rodam contra o ambiente local com a carga de demonstração (§15.2–15.3); pulados se o backend não estiver no ar.
 * Projetos desktop (1440) e celular (390): toda tela é conferida sem rolagem horizontal.
 */
import { backendNoAr, entrar, expect, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar (npm run local)')
})

const ANA = 'a0000000-0000-4000-8000-000000000301'

test('funcionários: lista, busca e ficha com abas', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/funcionarios')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Funcionários')
  await expect(page.getByText('Ana Souza').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)

  await page.getByLabel('Buscar').fill('carla')
  await expect(page.getByText('Carla Dias').filter({ visible: true }).first()).toBeVisible()
  await expect(page.getByText('Ana Souza').filter({ visible: true })).toHaveCount(0)

  await page.goto(`/funcionarios/${ANA}`)
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Ana Souza')
  for (const aba of ['Dados', 'Vínculos', 'Comissão', 'Jornada', 'Control iD']) await expect(page.getByRole('tab', { name: aba })).toBeVisible()
  await page.getByRole('tab', { name: 'Comissão' }).click()
  await expect(page.getByLabel('Pontos')).toHaveValue(/10/)
  await page.getByRole('tab', { name: 'Control iD' }).click()
  await expect(page.getByRole('heading', { name: 'Estado do envio' })).toBeVisible()
  await expect(page.getByText('Senha de acesso')).toBeVisible()
  await semRolagemHorizontal(page)
})

test('cadastro valida campos obrigatórios', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/funcionarios/novo')
  await page.getByLabel('CPF').fill('123')
  await page.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(page.getByText('Informe o nome').filter({ visible: true }).first()).toBeVisible()
  await expect(page.getByText('CPF deve ter 11 dígitos').filter({ visible: true }).first()).toBeVisible()
})

test('jornadas e horários de acesso abrem', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/funcionarios/jornadas')
  await expect(page.getByText('Salão noite').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await page.goto('/funcionarios/horarios-acesso')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Horários')
  await semRolagemHorizontal(page)
})

test('ponto: dia, espelho com alarmes e alarmes', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/ponto')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Ponto')
  await expect(page.getByText('Ana Souza').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)

  await page.goto(`/ponto/funcionario/${ANA}`)
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Ana Souza')
  await expect(page.getByRole('list', { name: 'Dias do mês' })).toBeVisible()
  await semRolagemHorizontal(page)

  await page.goto('/ponto/alarmes?status=todos')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Alarmes')
  await semRolagemHorizontal(page)
})

test('banco de horas: resumo e extrato', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/banco-de-horas')
  await expect(page.getByText('Ana Souza').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await page.goto(`/banco-de-horas/${ANA}`)
  await expect(page.getByText('Saldo anterior').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
})

test('vendas: faturamento e ranking de garçons', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/vendas')
  await expect(page.getByText('Faturamento').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await page.getByRole('tab', { name: /Garçons/ }).click()
  await expect(page).toHaveURL(/aba=garcons/)
  await semRolagemHorizontal(page)
})

test('comissões: lista e detalhe com prévia', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/comissoes')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Comissões')
  await semRolagemHorizontal(page)
  // a carga demo tem um fechado do mês anterior e um rascunho do mês corrente
  await page.getByText(/^Comissão \d/).filter({ visible: true }).first().click()
  await expect(page).toHaveURL(/\/comissoes\/[0-9a-f-]{36}/)
  await expect(page.getByText('Base distribuível').filter({ visible: true }).first()).toBeVisible()
  await expect(page.getByText('Rateio por funcionário')).toBeVisible()
  await semRolagemHorizontal(page)
})

test('tarefas: lista do dia e rotinas', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/tarefas')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Tarefas')
  await page.getByRole('tab', { name: 'Todas' }).click()
  await expect(page.getByText('Abrir caixa').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await page.goto('/tarefas/rotinas')
  await expect(page.getByText('Conferir estoque do bar').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
})

test('leitura: vê o ponto mas não vê botões de ajuste', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.leitura)
  await page.goto('/ponto')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Ponto')
  await expect(page.getByRole('button', { name: 'Recalcular' })).toHaveCount(0)
  await page.goto('/funcionarios')
  await expect(page.getByRole('link', { name: 'Novo funcionário' })).toHaveCount(0)
})
