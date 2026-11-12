/**
 * Adendo extras / ocorrências / reservas: ocorrência com foto (até a fila — o Storage não existe localmente),
 * pontos extras entrando no fechamento, diária, gastos do período, reserva manual e importação de CSV de reservas,
 * integração Tagme e guardas do papel leitura. Contra o ambiente local com a carga demo (pulado sem backend).
 */
import type { Locator } from '@playwright/test'
import { backendNoAr, entrar, expect, ignorarErrosDoConsole, semRolagemHorizontal, test, USUARIOS_DEMO } from './apoio/fixtures'

const DAVI = 'a0000000-0000-4000-8000-000000000304'
const EVA = 'a0000000-0000-4000-8000-000000000305'

// PNG 2×2 válido (o navegador decodifica, redimensiona e comprime em JPEG)
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg==',
  'base64',
)

/** Escolhe a opção cujo texto começa com `texto` (o seletor mostra "Nome — Cargo"). */
async function escolher(select: Locator, texto: string) {
  const valor = await select.locator('option', { hasText: texto }).first().getAttribute('value')
  await select.selectOption(valor!)
}

const sufixo = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar (npm run local)')
})

test('ocorrência: contador na ficha, registro com foto do documento (fila) e lista', async ({ page }) => {
  // o upload vai para o Storage, que não existe no ambiente local (portão responde 501)
  ignorarErrosDoConsole(page, /501|Not Implemented|Failed to load resource/i)
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto(`/funcionarios/${DAVI}`)
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Davi')
  await expect(page.getByRole('button', { name: /Ocorrências: \d+ advertência/ })).toBeVisible()
  await page.getByRole('tab', { name: /Ocorrências/ }).click()
  await expect(page.getByText('Atrasos recorrentes (demo)')).toBeVisible()
  await semRolagemHorizontal(page)

  const motivo = `Uso do celular no salão ${sufixo()}`
  await page.getByRole('button', { name: 'Registrar ocorrência' }).first().click()
  const modal = page.getByRole('dialog')
  await modal.getByLabel('Motivo').fill(motivo)
  await modal.getByLabel('Descrição').fill('Orientado verbalmente antes.')
  // câmera do celular: input com capture; aqui o arquivo escolhido
  await expect(modal.getByLabel('Tirar foto do documento')).toHaveAttribute('capture', 'environment')
  await modal.getByLabel('Escolher arquivo do documento').setInputFiles({ name: 'assinada.png', mimeType: 'image/png', buffer: PNG })
  await expect(modal.getByRole('img', { name: 'Prévia de assinada.jpg' })).toBeVisible()
  await semRolagemHorizontal(page)
  await modal.getByRole('button', { name: 'Registrar', exact: true }).click()
  // a ocorrência é salva; a foto fica pendente por falta do Storage local
  await expect(page.getByText(/Ocorrência salva, mas 1 foto\(s\) não foram enviadas/)).toBeVisible()
  await expect(page.getByText(motivo)).toBeVisible()

  // suspensão: período calculado
  await page.getByRole('button', { name: 'Registrar ocorrência' }).first().click()
  await modal.getByLabel('Tipo').selectOption('suspensao')
  await expect(modal.getByLabel('Dias de suspensão')).toBeVisible()
  await expect(modal.getByText(/Volta ao trabalho em/)).toBeVisible()
  await modal.getByRole('button', { name: 'Cancelar' }).click()
})

test('ocorrência: atalho do painel e suspensão da carga demo', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await expect(page.getByRole('heading', { name: /Ocorrências recentes/ })).toBeVisible()
  await expect(page.getByText(/suspenso.? hoje/).first()).toBeVisible()
  await page.getByRole('button', { name: 'Registrar ocorrência' }).click()
  await expect(page.getByRole('dialog').getByLabel('Funcionário')).toBeVisible()
  await page.getByRole('dialog').getByRole('button', { name: 'Cancelar' }).click()
  await page.goto(`/funcionarios/${EVA}`)
  await page.getByRole('tab', { name: /Ocorrências/ }).click()
  await expect(page.getByText('Falta sem aviso (demo)')).toBeVisible()
  await expect(page.getByText(/2 dias · /)).toBeVisible()
})

test('pontos extras entram no fechamento em rascunho (coluna Extras)', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/extras?aba=pontos')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Extras')
  await semRolagemHorizontal(page)
  const motivo = `Meta de vinhos ${sufixo()}`
  await escolher(page.getByLabel('Funcionário'), 'Bruno Lima')
  await page.getByRole('textbox', { name: 'Pontos extras' }).fill('1,5')
  await page.getByRole('textbox', { name: 'Motivo' }).fill(motivo)
  await page.getByRole('button', { name: 'Lançar pontos' }).click()
  await expect(page.getByText(/Pontos lançados|Pontos extras lançados/)).toBeVisible()
  await expect(page.getByText(motivo).filter({ visible: true })).toBeVisible()

  // abre o rascunho do mês pelo link e relê
  await page.getByRole('link', { name: /^Comissão / }).first().click()
  await expect(page).toHaveURL(/\/comissoes\/[0-9a-f-]{36}/)
  await page.getByRole('button', { name: 'Reler serviço e presença' }).click()
  await expect(page.getByText('Recalculado com o serviço e a presença atuais')).toBeVisible()
  await expect(page.getByRole('columnheader', { name: 'Extras' })).toBeVisible()
  const linhaBruno = page.getByRole('row').filter({ hasText: 'Bruno Lima' })
  await expect(linhaBruno).toContainText(/\+\d/)
  // Ana tem 2 extras da carga demo
  await expect(page.getByRole('row').filter({ hasText: 'Ana Souza' })).toContainText('+2')
})

test('pontos extras: data em fechamento fechado é avisada e bloqueada', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/extras?aba=pontos')
  const dataCampo = page.getByRole('textbox', { name: 'Data', exact: true })
  // primeiro dia do mês anterior (o fechamento demo do mês anterior está fechado)
  const hoje = await dataCampo.inputValue()
  const [a, m] = hoje.split('-').map(Number)
  const anterior = m === 1 ? `${a! - 1}-12-01` : `${a}-${String(m! - 1).padStart(2, '0')}-01`
  await dataCampo.fill(anterior)
  await expect(page.getByRole('alert').filter({ hasText: 'já foi fechado' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Lançar pontos' })).toBeDisabled()
})

test('diária: lançar avulso, marcar como paga; valor padrão do funcionário', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/extras?aba=diarias')
  await expect(page.getByText('Marcos Freitas (freela)').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  const nome = `Freela ${sufixo()}`
  await page.getByRole('button', { name: 'Lançar diária' }).first().click()
  const modal = page.getByRole('dialog')
  // valor padrão pré-preenchido para a Eva
  await escolher(modal.getByLabel('Funcionário'), 'Eva Martins')
  await expect(modal.getByText('Padrão do funcionário: R$ 150,00')).toBeVisible()
  await modal.getByRole('radio', { name: 'Avulso (freelancer)' }).click()
  await modal.getByLabel('Nome').fill(nome)
  await modal.getByLabel('Função').fill('Bar')
  await modal.getByLabel('Valor').fill('120,00')
  await modal.getByLabel('Valor').blur()
  await modal.getByRole('button', { name: 'Lançar', exact: true }).click()
  await expect(page.getByText('Diária lançada')).toBeVisible()
  await page.getByRole('button', { name: `Marcar diária de ${nome} como paga` }).filter({ visible: true }).click()
  await expect(page.getByText(`Diária de ${nome} marcada como paga`)).toBeVisible()
  await expect(page.getByRole('button', { name: `Desfazer pagamento de ${nome}` }).filter({ visible: true })).toBeVisible()

  // ficha: campo de valor padrão
  await page.goto(`/funcionarios/${EVA}`)
  await page.getByRole('tab', { name: 'Comissão' }).click()
  await expect(page.getByLabel('Valor padrão da diária')).toHaveValue('150,00')
})

test('gastos do período: cartões, gráfico, tabela por pessoa e CSV', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/extras?aba=gastos')
  await page.getByRole('button', { name: 'Mês anterior' }).click()
  await page.getByRole('button', { name: 'Este mês' }).click()
  await expect(page.getByText('Total geral')).toBeVisible()
  await expect(page.getByText('Diárias pagas').first()).toBeVisible()
  await expect(page.getByText('Comissões previstas').first()).toBeVisible()
  await expect(page.getByText('Marcos Freitas (freela)').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Exportar CSV' }).click()])
  expect(download.suggestedFilename()).toMatch(/^gastos_bar-bossa-nova_\d{4}-\d{2}-01_\d{4}-\d{2}-\d{2}\.csv$/)
  // mês anterior: comissão fechada entra no gráfico
  await page.getByRole('button', { name: 'Mês anterior' }).click()
  await expect(page.getByRole('list').filter({ has: page.getByRole('listitem', { name: /Comissões fechadas/ }) })).toBeVisible()
})

test('reserva manual: cadastrar, mudar status, cancelar; painel mostra reservas de hoje', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await expect(page.getByRole('heading', { name: /Reservas de hoje/ })).toBeVisible()
  await page.goto('/reservas')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Reservas')
  await semRolagemHorizontal(page)
  const nome = `Cliente ${sufixo()}`
  await page.getByRole('button', { name: 'Nova reserva' }).first().click()
  const modal = page.getByRole('dialog')
  await modal.getByLabel('Nome do cliente').fill(nome)
  await modal.getByLabel('Horário').fill('23:30')
  await modal.getByLabel('Pessoas').fill('3')
  await modal.getByLabel('Área / ambiente').fill('Varanda')
  await modal.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(page.getByText('Reserva cadastrada')).toBeVisible()
  await expect(page.getByText(nome, { exact: true })).toBeVisible()
  await page.getByLabel(`Status da reserva de ${nome}`).selectOption('sentada')
  await expect(page.getByText(`${nome}: Sentada`)).toBeVisible()
  await page.getByRole('button', { name: `Cancelar reserva de ${nome}` }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Cancelar reserva' }).click()
  await expect(page.getByText('Reserva cancelada')).toBeVisible()
  await expect(page.getByLabel(`Status da reserva de ${nome}`)).toHaveValue('cancelada')
})

test('reservas: importar CSV (cabeçalhos em inglês, vírgula, mapeamento manual) e modelo', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/reservas')
  const s = sufixo()
  const csv = [
    'Reservation ID,Guest name,Date,Time,Party size,Status,Phone,Coluna X',
    `T-${s}-1,Importada Um ${s},${new Date().toISOString().slice(0, 10)},20:00,4,Confirmed,11999990000,Janela`,
    `T-${s}-2,Importada Dois ${s},2099-01-01,21:15,2,Canceled,,`,
    `T-${s}-3,,${new Date().toISOString().slice(0, 10)},20:00,2,Confirmed,,`,
  ].join('\n')
  await page.getByRole('button', { name: 'Importar CSV' }).click()
  const modal = page.getByRole('dialog')
  const [download] = await Promise.all([page.waitForEvent('download'), modal.getByRole('button', { name: 'Baixar modelo' }).click()])
  expect(download.suggestedFilename()).toBe('modelo-reservas.csv')
  await modal.getByLabel('Arquivo CSV de reservas').setInputFiles({ name: 'tagme.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) })
  await expect(modal.getByLabel('Nome do cliente')).toHaveValue('1')
  await expect(modal.getByLabel('Pessoas')).toHaveValue('4')
  // coluna desconhecida mapeada à mão
  await modal.getByLabel('Mesa').selectOption({ label: 'Coluna X' })
  await expect(modal.getByText('2 ok')).toBeVisible()
  await expect(modal.getByText(/Linha 4: Sem nome do cliente/)).toBeVisible()
  await semRolagemHorizontal(page)
  await modal.getByRole('button', { name: 'Importar 2 reserva(s)' }).click()
  await expect(page.getByText(/Reservas importadas: 2 nova\(s\)/)).toBeVisible()
  await page.getByRole('button', { name: 'Hoje' }).click()
  await expect(page.getByText(`Importada Um ${s}`, { exact: true })).toBeVisible()
})

test('integração Tagme: texto de ajuda e parâmetros avançados', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/integracoes')
  await page.getByRole('button', { name: /Nova integração/ }).first().click()
  await page.getByRole('button', { name: /Tagme/ }).click()
  const modal = page.getByRole('dialog')
  await expect(modal.getByText('A Tagme só libera API para parceiros.')).toBeVisible()
  await expect(modal.getByText('waitlist.tagme.com.br')).toBeVisible()
  await expect(modal.getByText('docs/IMPLANTACAO-N8N-HOSTINGER.md')).toBeVisible()
  await expect(modal.getByLabel('Id do restaurante na Tagme')).toBeVisible()
  await expect(modal.getByLabel('Client ID')).toBeVisible()
  await modal.getByLabel('Parâmetros avançados (JSON)').fill('{ "caminho": ')
  await expect(modal.getByText('JSON inválido')).toBeVisible()
  await modal.getByLabel('Parâmetros avançados (JSON)').fill('{ "caminho": "/api/reservas" }')
  await expect(modal.getByText('JSON inválido')).toHaveCount(0)
  await semRolagemHorizontal(page)
})

test('leitura: sem aba Ocorrências nem Extras; vê reservas sem telefone e sem ações', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.leitura)
  await page.goto(`/funcionarios/${DAVI}`)
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Davi')
  await expect(page.getByRole('tab', { name: /Ocorrências/ })).toHaveCount(0)
  await page.goto('/extras')
  await expect(page.getByRole('heading', { level: 1, name: 'Sem permissão' })).toBeVisible()
  await page.goto('/reservas')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Reservas')
  await expect(page.getByRole('button', { name: 'Nova reserva' })).toHaveCount(0)
  await expect(page.locator('a[href^="tel:"]')).toHaveCount(0)
  await page.goto('/')
  await expect(page.getByRole('heading', { name: /Ocorrências recentes/ })).toHaveCount(0)
})
