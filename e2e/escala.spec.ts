/**
 * Escala rotativa (adendo escala v2). Exigem o ambiente local (§15.2) com a migração …0280 e a carga 40_demo_escala.
 * - leitura vê a escala do mês da demo (sem editar);
 * - empresa nova (sem escala, sem ponto, sem integração): montar pelo modelo Macaw → renomear funcionário → marcar folga
 *   clicando → voltar ao automático → digitar horário → copiar TSV. Cada projeto cria a sua conta, então não há disputa de dados.
 */
import type { Page } from '@playwright/test'
import { backendNoAr, entrar, expect, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar')
})

function dataBR(iso: string): string {
  const [a, m, d] = iso.split('-')
  return `${d}/${m}/${a}`
}

async function abrirAba(page: Page, nome: string | RegExp) {
  await page.getByRole('tab', { name: nome }).click()
}

test('leitura vê a escala do mês da demonstração, sem editar', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.leitura)
  await page.goto('/escala?aba=mes')
  const grade = page.locator('[data-teste="grade-mes"]')
  await expect(grade).toBeVisible()
  await expect(grade.getByText('Salão', { exact: true })).toBeVisible()
  await expect(grade.getByText('Na escala', { exact: true })).toBeVisible()
  const celula = grade.locator('input[aria-label^="Ana Souza, dia"]').first()
  await expect(celula).toHaveAttribute('readonly', '')
  await expect(page.getByRole('button', { name: 'Folga', exact: true })).toHaveCount(0)
  await semRolagemHorizontal(page)
  // aba geral e de setor
  await abrirAba(page, 'Geral')
  await expect(page.getByRole('cell', { name: 'Todos' })).toBeVisible()
  await abrirAba(page, 'Salão')
  await expect(page.getByText('Caminho a seguir')).toBeVisible()
  await semRolagemHorizontal(page)
})

test('empresa sem escala: modelo Macaw → renomear → folga clicando → automático → horário → copiar', async ({ page, context }, info) => {
  test.setTimeout(90_000)
  await context.grantPermissions(['clipboard-read', 'clipboard-write']).catch(() => undefined)
  const email = `escala-${info.project.name}-${Date.now()}@teste.local`

  // conta e estabelecimento novos (sem funcionários, sem ponto, sem integração)
  await page.goto('/criar-conta')
  await page.getByLabel('Seu nome').fill('Gerente Macaw')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha', { exact: true }).fill('gerente123')
  await page.getByRole('button', { name: 'Criar conta' }).click()
  await expect(page).toHaveURL(/\/comecar/, { timeout: 15_000 })
  await page.getByLabel('Nome do estabelecimento').fill('Macaw Teste')
  await page.getByRole('button', { name: 'Criar estabelecimento' }).click()
  await expect(page.locator('#conteudo')).toBeVisible({ timeout: 15_000 })

  // estado vazio → montar pelo modelo
  await page.goto('/escala')
  await expect(page.getByText('A escala ainda não foi montada')).toBeVisible()
  await page.getByRole('button', { name: 'Montar escala a partir do modelo Macaw' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Montar escala' }).click()
  await expect(page.getByText(/Escala montada: 6 setor\(es\), 33 posição/)).toBeVisible()
  for (const s of ['Salão', 'Maître', 'Areia', 'Bar', 'ASG', 'Cozinha']) await expect(page.getByRole('tab', { name: s, exact: true })).toBeVisible()

  // aba do setor: caminho com setas
  await abrirAba(page, 'Areia')
  await expect(page.getByLabel('Caminho 1').getByText('Areia 2')).toBeVisible()

  // renomear funcionário na aba Equipe
  await abrirAba(page, /^Equipe/)
  await page.getByRole('button', { name: 'Editar nome de Garçom 1' }).click()
  await page.getByLabel('Nome do funcionário').fill('Joana Lima')
  await page.getByRole('button', { name: 'Salvar nome' }).click()
  await expect(page.getByText('Nome atualizado.')).toBeVisible()
  await expect(page.locator('[data-teste="membro"][data-nome="Joana Lima"]')).toBeVisible()
  await semRolagemHorizontal(page)

  // escala do mês: marcar folga clicando no dia de hoje
  await abrirAba(page, 'Escala do mês')
  const grade = page.locator('[data-teste="grade-mes"]')
  await expect(grade).toBeVisible()
  const hoje = (await grade.getAttribute('data-hoje'))!
  const td = grade.locator(`td[data-data="${hoje}"]`).filter({ has: page.locator('input[aria-label^="Joana Lima,"]') })
  const celula = grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`)
  await celula.click()
  const painel = page.locator('[data-teste="painel-dia"]')
  await expect(painel).toContainText('Joana Lima')
  const automatico = await td.getAttribute('data-status')
  const alvo = automatico === 'folga' ? 'Trabalha' : 'Folga'
  const status = automatico === 'folga' ? 'trabalha' : 'folga'
  await painel.getByRole('button', { name: alvo, exact: true }).click()
  await expect(td).toHaveAttribute('data-status', status)
  await expect(td).toHaveAttribute('data-ajustado', '1')
  await expect(painel.locator('[data-teste="estado-dia"]')).toContainText(/ajustad/)

  // persiste no banco
  await page.reload()
  await expect(grade.locator(`td[data-data="${hoje}"]`).filter({ has: page.locator('input[aria-label^="Joana Lima,"]') })).toHaveAttribute(
    'data-status',
    status,
  )

  // voltar ao automático
  await grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`).click()
  await painel.getByRole('button', { name: 'Automático', exact: true }).click()
  await expect(td).toHaveAttribute('data-status', automatico!)
  await expect(td).not.toHaveAttribute('data-ajustado', '1')

  // digitar: "f" + Enter marca folga (ou mantém a automática) e desce; digitar horário vira 11h30
  const c2 = grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`)
  await c2.click()
  await c2.fill('11:30')
  await c2.press('Enter')
  await expect(c2).toHaveValue('11h30')
  await expect(td).toHaveAttribute('data-status', 'trabalha')
  await expect(td).toHaveAttribute('data-ajustado', '1')

  // copiar para o Excel (TSV); sem área de transferência, cai na caixa de texto
  await page.getByRole('button', { name: 'Copiar para Excel' }).click()
  await expect(page.getByRole('status').filter({ hasText: /Escala copiada|Não consegui copiar/ })).toBeVisible()
  const caixa = page.getByLabel('Escala em texto para copiar')
  const tsv = (await caixa.count()) ? await caixa.inputValue() : await page.evaluate(() => navigator.clipboard.readText())
  const linhas = tsv.split('\n')
  expect(linhas[0]).toMatch(/^Nome\t1 [A-ZÁ]{3}\t/)
  expect(linhas).toContain('Salão')
  expect(linhas.some((l) => l.startsWith('Joana Lima\t') && l.includes('11h30'))).toBe(true)
  expect(linhas.at(-1)).toMatch(/^Na escala\t/)
  await semRolagemHorizontal(page)
})
