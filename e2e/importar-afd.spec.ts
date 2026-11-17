/**
 * Importar AFD (RHiD/arquivo): empresa nova com a escala do modelo Macaw (provisórios "Garçom 1"…), relógio por arquivo criado
 * pela própria tela, AFD 671 gerado aqui (tipos 1, 2, 3, 5, 7, 9 e a linha de assinatura do RHiD), prévia, importação,
 * "Ligar funcionários" (renomeia o provisório e grava o CPF), reimportação idempotente e batidas/alarmes no ponto do dia.
 * Cada projeto cria a sua conta. Com MDG_TELAS=<pasta> grava as telas (prévia, resultado, ligar).
 */
import type { Locator, Page } from '@playwright/test'
import { backendNoAr, expect, semRolagemHorizontal, test } from './apoio/fixtures'

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), 'backend local fora do ar')
})

const BRUNO = '11144477735'
const CARLA = '39053344705'

const n = (v: number | string, t: number) => String(v).padStart(t, '0')
const nsr = (i: number) => n(i, 9)

/** Dia de trabalho de São Paulo (virada 05:00) − `dias`. */
function diaSP(dias: number): string {
  const agora = new Date(Date.now() - 3 * 3600_000 - 5 * 3600_000) // UTC−3 e virada às 05:00
  return new Date(Date.UTC(agora.getUTCFullYear(), agora.getUTCMonth(), agora.getUTCDate() - dias)).toISOString().slice(0, 10)
}

/** AFD Portaria 671 (layout do RHiD/REP-P) em Latin-1, CRLF. */
function gerarAfd(dia: string): Buffer {
  const dh = (hora: string) => `${dia}T${hora}:00-0300`
  const marcacao = (i: number, hora: string, cpf: string, tipo = '3') =>
    tipo === '3' ? `${nsr(i)}3${dh(hora)}0${cpf}ABCD` : `${nsr(i)}7${dh(hora)}0${cpf}${dh(hora)}01` + '0'.repeat(64)
  const empregado = (i: number, cpf: string, nome: string) => `${nsr(i)}5${dh('09:00')}I0${cpf}${nome.padEnd(52, ' ')}0000123456789091a2b3`
  const linhas = [
    `${nsr(0)}11${'12345678000190'}${'0'.repeat(14)}${'MACAW TESTE LTDA'.padEnd(150, ' ')}${'0'.repeat(17)}${dia}${dia}${dh('23:59')}003`,
    `${nsr(1)}2${dh('08:00')}${'12345678909'}1${'12345678000190'}${'0'.repeat(14)}${'MACAW TESTE LTDA'.padEnd(150, ' ')}${'SALÃO'.padEnd(100, ' ')}a58b`,
    empregado(2, BRUNO, 'BRUNO LIMA'),
    empregado(3, CARLA, 'CARLA DE SOUZA'),
    marcacao(4, '18:00', BRUNO),
    marcacao(5, '22:00', BRUNO),
    marcacao(6, '22:30', BRUNO),
    marcacao(7, '18:10', CARLA),
    marcacao(8, '23:40', CARLA, '7'),
    `999999999${n(0, 9)}${n(2, 9)}${n(4, 9)}${n(0, 9)}${n(2, 9)}${n(0, 9)}9`,
    'ASSINATURA_DIGITAL_EM_ARQUIVO_P7S'.padEnd(100, ' '),
    '',
  ]
  return Buffer.from(linhas.join('\r\n'), 'latin1')
}

async function tela(page: Page, nome: string, info: { project: { name: string } }) {
  const pasta = process.env.MDG_TELAS
  if (pasta) await page.screenshot({ path: `${pasta}/${nome}-${info.project.name === 'celular' ? '390' : '1440'}.png`, fullPage: false })
}

/** Valor do quadro de número (dt rótulo + dd valor). */
const numero = (onde: Locator, rotulo: string) => onde.locator('dt', { hasText: new RegExp(`^${rotulo}$`) }).locator('xpath=following-sibling::dd')

async function escolher(select: Locator, texto: string) {
  const valor = await select.locator('option', { hasText: texto }).first().getAttribute('value')
  await select.selectOption(valor!)
}

test('importar AFD do RHiD → ligar CPF ao provisório da escala → batidas e alarmes no ponto', async ({ page }, info) => {
  test.setTimeout(120_000)
  const email = `afd-${info.project.name}-${Date.now()}@teste.local`
  await page.goto('/criar-conta')
  await page.getByLabel('Seu nome').fill('Gerente Macaw')
  await page.getByLabel('E-mail').fill(email)
  await page.getByLabel('Senha', { exact: true }).fill('gerente123')
  await page.getByRole('button', { name: 'Criar conta' }).click()
  await expect(page).toHaveURL(/\/comecar/, { timeout: 15_000 })
  await page.getByLabel('Nome do estabelecimento').fill('Macaw AFD')
  await page.getByRole('button', { name: 'Criar estabelecimento' }).click()
  await expect(page.locator('#conteudo')).toBeVisible({ timeout: 15_000 })

  // escala do modelo Macaw: cria os provisórios ("Garçom 1"…)
  await page.goto('/escala')
  await page.getByRole('button', { name: 'Montar escala a partir do modelo Macaw' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Montar escala' }).click()
  await expect(page.getByText(/Escala montada: 6 setor\(es\)/)).toBeVisible()

  // Ponto → Importar AFD: sem relógio, cria o "por arquivo"
  const dia = diaSP(2)
  await page.goto('/ponto')
  await page.getByRole('button', { name: 'Importar AFD' }).click()
  const modal = page.getByRole('dialog')
  await expect(modal.getByText('Nenhum relógio de ponto ativo')).toBeVisible()
  await modal.getByRole('button', { name: /Criar “Relógio de ponto \(RHiD\/arquivo\)”/ }).click()
  await expect(modal.getByText(/Relatórios → Relatório de AFDs → período → Buscar → baixar o arquivo/)).toBeVisible()
  await modal.getByLabel('Arquivo AFD').setInputFiles({ name: 'AFD_RHID.txt', mimeType: 'text/plain', buffer: gerarAfd(dia) })

  // prévia
  const previa = modal.locator('[data-teste="previa-afd"]')
  await expect(previa).toBeVisible()
  await expect(numero(previa, 'Marcações')).toHaveText('5')
  await expect(numero(previa, 'Empregados no AFD')).toContainText('2')
  await expect(numero(previa, 'CPFs sem funcionário')).toContainText('2')
  await expect(previa.locator(`[data-teste="pessoa-afd"][data-documento="${BRUNO}"]`)).toContainText('BRUNO LIMA')
  await expect(previa.locator(`[data-teste="pessoa-afd"][data-documento="${CARLA}"]`)).toContainText('CARLA DE SOUZA')
  await semRolagemHorizontal(page)
  await tela(page, 'afd-previa', info)

  // importar
  await modal.getByRole('button', { name: 'Importar 5 marcação(ões)' }).click()
  const resultado = modal.locator('[data-teste="resultado-afd"]')
  await expect(resultado).toBeVisible({ timeout: 15_000 })
  await expect(numero(resultado, 'Marcações novas')).toContainText('5')
  await expect(numero(resultado, 'CPFs sem funcionário')).toContainText('2')
  await expect(resultado).toContainText('5 marcação(ões) de 2 CPF(s) ainda sem funcionário')
  await tela(page, 'afd-resultado', info)

  // ligar Bruno ao provisório "Garçom 1", renomeando e gravando o CPF
  await modal.getByRole('button', { name: 'Ligar funcionários' }).click()
  const bruno = modal.locator(`[data-teste="pendente-afd"][data-documento="${BRUNO}"]`)
  await expect(bruno).toContainText('BRUNO LIMA')
  await escolher(bruno.getByLabel('Funcionário para BRUNO LIMA'), 'Garçom 1 —')
  await expect(bruno.getByRole('checkbox', { name: 'Renomear “Garçom 1” para “Bruno Lima”' })).toBeChecked()
  await expect(bruno.getByRole('checkbox', { name: 'Cadastrar o CPF na ficha' })).toBeChecked()
  await semRolagemHorizontal(page)
  await tela(page, 'afd-ligar', info)
  await bruno.getByRole('button', { name: 'Ligar' }).click()
  await expect(page.getByText('Bruno Lima: 3 marcação(ões) ligada(s), nome atualizado, CPF na ficha.')).toBeVisible()
  await expect(bruno).toHaveCount(0)
  await expect(modal.locator(`[data-teste="pendente-afd"][data-documento="${CARLA}"]`)).toBeVisible()
  await modal.getByRole('button', { name: 'Concluir' }).click()

  // reimportar o mesmo arquivo: nada duplica; só a Carla continua sem funcionário
  await page.getByRole('button', { name: 'Importar AFD' }).click()
  await modal.getByLabel('Arquivo AFD').setInputFiles({ name: 'AFD_RHID.txt', mimeType: 'text/plain', buffer: gerarAfd(dia) })
  await expect(numero(previa, 'CPFs sem funcionário')).toContainText('1')
  await modal.getByRole('button', { name: 'Importar 5 marcação(ões)' }).click()
  await expect(numero(resultado, 'Marcações novas')).toContainText('0')
  await expect(numero(resultado, 'Já importadas')).toContainText('5')
  await modal.getByRole('button', { name: 'Concluir' }).click()

  // ponto do dia: Bruno Lima (ex-"Garçom 1") com as 3 batidas e alarme
  await page.goto(`/ponto?data=${dia}`)
  // tabela no computador, lista de cartões (botões) no celular
  const conteudo = page.locator('#conteudo')
  const linha = conteudo
    .getByRole('row', { name: /Bruno Lima/ })
    .or(conteudo.getByRole('button', { name: /Bruno Lima/ }))
    .filter({ visible: true })
    .first()
  await expect(linha).toBeVisible()
  for (const h of ['18:00', '22:00', '22:30']) await expect(linha.getByText(h, { exact: true }).first()).toBeVisible()
  await expect(linha.getByLabel('Precisa de atenção')).toBeVisible()
  await page.goto('/ponto/alarmes')
  await expect(page.getByText('3 batidas (número ímpar)').filter({ visible: true }).first()).toBeVisible()
  await expect(page.locator('#conteudo').getByText('Bruno Lima', { exact: true }).filter({ visible: true }).first()).toBeVisible()

  // Integrações: relógio por arquivo sem "Sincronizar", com o histórico da importação
  await page.goto('/integracoes')
  await expect(page.getByText('Arquivo AFD', { exact: true })).toBeVisible()
  await page.getByRole('link', { name: 'Relógio de ponto (RHiD/arquivo)' }).click()
  await expect(page.getByRole('button', { name: 'Importar AFD' })).toBeVisible()
  await expect(page.getByRole('button', { name: /Sincronizar/ })).toHaveCount(0)
  await page.getByRole('tab', { name: 'Ligar funcionários' }).click()
  await expect(page.locator(`[data-teste="pendente-afd"][data-documento="${CARLA}"]`)).toContainText('CARLA DE SOUZA')
  await semRolagemHorizontal(page)

  // Trocar para RHiD: a integração nova herda os CPFs (vínculos e os sem ficha) e também tem "Ligar funcionários"
  await page.getByRole('tab', { name: 'Visão geral' }).click()
  await page.getByRole('button', { name: 'Trocar para RHiD' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Trocar para RHiD' }).click()
  await expect(page.getByRole('heading', { name: 'Relógio de ponto (RHiD)' })).toBeVisible({ timeout: 15_000 })
  await page.getByRole('tab', { name: 'Configuração' }).click()
  await expect(page.getByLabel(/E-mail/).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await tela(page, 'rhid-formulario', info)
  await page.getByRole('tab', { name: 'Pessoas do relógio' }).click()
  await expect(page.locator('#conteudo').getByText('Bruno Lima').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  await tela(page, 'rhid-pessoas', info)
  await page.getByRole('tab', { name: 'Ligar funcionários' }).click()
  const carlaRhid = page.locator(`[data-teste="pendente-afd"][data-documento="${CARLA}"]`)
  await expect(carlaRhid).toContainText('CARLA DE SOUZA')
  await expect(page.getByText(/Escolha quem é cada pessoa do RHiD/)).toBeVisible()
  await escolher(carlaRhid.getByLabel('Funcionário para CARLA DE SOUZA'), 'Garçom 2 —')
  await expect(carlaRhid.getByRole('checkbox', { name: 'Renomear “Garçom 2” para “Carla de Souza”' })).toBeChecked()
  await semRolagemHorizontal(page)
  await tela(page, 'rhid-ligar', info)
  await carlaRhid.getByRole('button', { name: 'Ligar' }).click()
  await expect(page.getByText(/^Carla de Souza: 0 marcação\(ões\) ligada\(s\), nome atualizado, CPF na ficha\.$/)).toBeVisible()
  await expect(page.getByText('Todos os CPFs estão ligados')).toBeVisible()
})
