/** Telas de acesso (dono: frontend-1). Rodam sem backend; os de login real exigem o ambiente local (§15.2). */
import { backendNoAr, entrar, expect, ignorarErrosDoConsole, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

test.describe('tela de entrar', () => {
  test('mostra a identidade visual da referência', async ({ page }) => {
    await page.goto('/entrar')
    await expect(page.getByText('Meu dia de gerente', { exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Organize seu dia.')
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Não esqueça nada.')
    await expect(page.getByText('Seu assistente diário de rotina na loja.')).toBeVisible()
    await expect(page.getByLabel('E-mail')).toBeVisible()
    await expect(page.getByLabel('Senha', { exact: true })).toHaveAttribute('type', 'password')
    await expect(page.getByLabel('Manter-me conectado')).toBeChecked()
    await expect(page.getByRole('button', { name: 'Entrar', exact: true })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Recuperar senha' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Criar conta' })).toBeVisible()
    await semRolagemHorizontal(page)
  })

  test('mostrar/ocultar senha e foco visível pelo teclado', async ({ page }) => {
    await page.goto('/entrar')
    const senha = page.getByLabel('Senha', { exact: true })
    await senha.fill('segredo')
    await page.getByRole('button', { name: 'Mostrar senha' }).click()
    await expect(senha).toHaveAttribute('type', 'text')
    await page.getByRole('button', { name: 'Ocultar senha' }).click()
    await expect(senha).toHaveAttribute('type', 'password')
    await page.getByLabel('E-mail').focus()
    const contorno = await page.getByLabel('E-mail').evaluate((el) => getComputedStyle(el).borderColor)
    expect(contorno).not.toBe('')
  })

  test('navega para recuperar senha e criar conta', async ({ page }) => {
    await page.goto('/entrar')
    await page.getByRole('link', { name: 'Recuperar senha' }).click()
    await expect(page).toHaveURL(/\/recuperar-senha$/)
    await expect(page.getByRole('button', { name: 'Enviar link' })).toBeVisible()
    await page.getByRole('link', { name: 'Voltar para entrar' }).click()
    await page.getByRole('link', { name: 'Criar conta' }).click()
    await expect(page).toHaveURL(/\/criar-conta$/)
    await expect(page.getByLabel('Seu nome')).toBeVisible()
    await semRolagemHorizontal(page)
  })

  test('rota protegida sem sessão vai para /entrar', async ({ page }) => {
    await page.goto('/ponto')
    await expect(page).toHaveURL(/\/entrar$/)
  })
})

test.describe('com o ambiente local', () => {
  test.beforeEach(async () => {
    test.skip(!(await backendNoAr()), 'backend local fora do ar (npm run local)')
  })

  test('senha errada mostra mensagem em português', async ({ page }) => {
    ignorarErrosDoConsole(page, /400|Failed to load resource/i)
    await page.goto('/entrar')
    await page.getByLabel('E-mail').fill(USUARIOS_DEMO.gerente)
    await page.getByLabel('Senha', { exact: true }).fill('errada123')
    await page.getByRole('button', { name: 'Entrar', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('E-mail ou senha incorretos')
  })

  test('entra e sai', async ({ page }) => {
    await entrar(page, USUARIOS_DEMO.gerente)
    await expect(page).toHaveURL(/\/$/)
    await expect(page.getByRole('heading', { level: 1 })).toContainText(/Bom dia|Boa tarde|Boa noite/)
    if ((page.viewportSize()?.width ?? 0) < 1024) await page.getByRole('button', { name: 'Abrir menu' }).click()
    await page.getByRole('button', { name: 'Sair' }).last().click()
    await expect(page).toHaveURL(/\/entrar$/)
  })

  test('"Manter-me conectado" desmarcado guarda a sessão só na aba', async ({ page }) => {
    await page.goto('/entrar')
    await page.getByLabel('Manter-me conectado').uncheck()
    await page.getByLabel('E-mail').fill(USUARIOS_DEMO.gerente)
    await page.getByLabel('Senha', { exact: true }).fill('gerente123')
    await page.getByRole('button', { name: 'Entrar', exact: true }).click()
    await expect(page.locator('#conteudo')).toBeVisible({ timeout: 15_000 })
    const onde = await page.evaluate(() => ({ local: localStorage.getItem('mdg-auth'), sessao: sessionStorage.getItem('mdg-auth') }))
    expect(onde.local).toBeNull()
    expect(onde.sessao).not.toBeNull()
  })
})
