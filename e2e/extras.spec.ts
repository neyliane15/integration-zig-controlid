/**
 * Adendo extras / ocorrências / reservas: ocorrência com foto (até a fila — o Storage não existe localmente),
 * cadastro de extras, dia trabalhado, rateio diário da comissão com o extra só no dia dele, gastos do período, reserva manual e importação de CSV de reservas,
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

/** Data 'AAAA-MM-DD' ± n dias. */
const somar = (iso: string, n: number) => new Date(Date.parse(`${iso}T12:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10)
const br = (iso: string) => iso.split('-').reverse().join('/')

test('extras: cadastrar, buscar, editar e desativar', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/extras')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Extras')
  await expect(page.getByRole('tab', { name: 'Extras', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByText('Marcos Freitas').filter({ visible: true }).first()).toBeVisible()
  await expect(page.getByText('Pedro Alves')).toHaveCount(0) // inativo
  await semRolagemHorizontal(page)

  const nome = `Freela Teste ${sufixo()}`
  await page.getByRole('button', { name: 'Novo extra' }).first().click()
  const modal = page.getByRole('dialog')
  await modal.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(modal.getByText('Informe o nome')).toBeVisible()
  await modal.getByLabel('Nome').fill(nome)
  await modal.getByLabel('Função').fill('Bar')
  await modal.getByLabel('Telefone').fill('11977776666')
  await modal.getByLabel('Pontuação padrão').fill('4,5')
  await modal.getByLabel('Valor da diária').fill('170,00')
  await modal.getByLabel('Valor da diária').blur()
  await modal.getByLabel('Documento').fill('123.456.789-00')
  await semRolagemHorizontal(page)
  await modal.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(page.getByText(`${nome} cadastrado`)).toBeVisible()

  // busca pelo telefone (só dígitos) e pelo nome sem acento
  await page.getByLabel('Buscar extra').fill('977776666')
  await expect(page.getByText(nome, { exact: true }).filter({ visible: true })).toBeVisible()
  await expect(page.getByText('Marcos Freitas').filter({ visible: true })).toHaveCount(0)
  await expect(page.getByText('(11) 97777-6666').filter({ visible: true }).first()).toBeVisible()

  // editar a pontuação
  await page.getByRole('button', { name: `Editar ${nome}` }).filter({ visible: true }).click()
  await expect(modal.getByLabel('Pontuação padrão')).toHaveValue('4,5')
  await expect(modal.getByLabel('Valor da diária')).toHaveValue('170,00')
  await modal.getByLabel('Pontuação padrão').fill('5')
  await modal.getByRole('button', { name: 'Salvar' }).click()
  await expect(page.getByText('Cadastro atualizado')).toBeVisible()

  // sem dias lançados: pode excluir; desativa → some da lista (até mostrar inativos)
  await expect(page.getByRole('button', { name: `Excluir ${nome}` }).filter({ visible: true })).toBeVisible()
  await page.getByRole('button', { name: `Desativar ${nome}` }).filter({ visible: true }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Desativar' }).click()
  await expect(page.getByText(`${nome} desativado`)).toBeVisible()
  await expect(page.getByText(nome, { exact: true }).filter({ visible: true })).toHaveCount(0)
  await page.getByText('Mostrar inativos').click()
  await expect(page.getByText(nome, { exact: true }).filter({ visible: true })).toBeVisible()
  await expect(page.getByText('Inativo').filter({ visible: true }).first()).toBeVisible()
})

test('dia trabalhado: cadastro do extra na hora, pontos e valor do cadastro (editáveis), pagar e CSV', async ({ page }) => {
  // o lançamento repetido (mesmo extra, mesmo dia) é recusado pelo banco com 409
  ignorarErrosDoConsole(page, /409|Conflict/)
  await entrar(page, USUARIOS_DEMO.gerente)
  await page.goto('/extras?aba=dias')
  await expect(page.getByText('Marcos Freitas').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  const nome = `Diarista ${sufixo()}`

  await page.getByRole('button', { name: 'Lançar dia' }).first().click()
  const modal = page.getByRole('dialog')
  await expect(modal.getByRole('radio', { name: 'Extra (freela)' })).toHaveAttribute('aria-checked', 'true')
  // cadastra o extra sem sair do lançamento
  await modal.getByRole('button', { name: 'Cadastrar extra' }).click()
  await expect(page.getByRole('dialog', { name: 'Novo extra' })).toBeVisible()
  const cadastro = page.getByRole('dialog', { name: 'Novo extra' })
  await cadastro.getByLabel('Nome').fill(nome)
  await cadastro.getByLabel('Função').fill('Garçom')
  await cadastro.getByLabel('Pontuação padrão').fill('4')
  await cadastro.getByLabel('Valor da diária').fill('160,00')
  await cadastro.getByLabel('Valor da diária').blur()
  await cadastro.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(page.getByText(`${nome} cadastrado`)).toBeVisible()

  // de volta ao lançamento, com o extra escolhido e os padrões do cadastro
  const lanc = page.getByRole('dialog', { name: 'Lançar dia trabalhado' })
  await expect(lanc.getByLabel('Extra')).toHaveValue(/[0-9a-f-]{36}/)
  await expect(lanc.getByLabel('Pontos do dia')).toHaveValue('4')
  await expect(lanc.getByLabel('Valor da diária')).toHaveValue('160,00')
  await expect(lanc.getByLabel('Função do dia')).toHaveValue('Garçom')
  await semRolagemHorizontal(page)
  // editáveis no dia
  await lanc.getByLabel('Pontos do dia').fill('4,5')
  await lanc.getByLabel('Valor da diária').fill('175,00')
  await lanc.getByLabel('Valor da diária').blur()
  await lanc.getByLabel('Observação').fill('Cobriu o salão')
  await lanc.getByRole('button', { name: 'Lançar', exact: true }).click()
  await expect(page.getByText(`Dia de ${nome} lançado`)).toBeVisible()
  const linha = page.getByRole('row').filter({ hasText: nome })
  if (await linha.count()) {
    await expect(linha).toContainText('4,5')
    await expect(linha).toContainText('175,00')
  }

  // mesmo extra no mesmo dia → recusado pelo banco
  await page.getByRole('button', { name: 'Lançar dia' }).first().click()
  await escolher(lanc.getByLabel('Extra'), nome)
  await lanc.getByRole('button', { name: 'Lançar', exact: true }).click()
  await expect(page.getByText(/Extra já tem dia lançado em \d{2}\/\d{2}\/\d{4}/)).toBeVisible()
  await lanc.getByRole('button', { name: 'Cancelar' }).click()

  await page.getByRole('button', { name: `Marcar dia de ${nome} como pago` }).filter({ visible: true }).click()
  await expect(page.getByText(`Dia de ${nome} marcado como pago`)).toBeVisible()
  await expect(page.getByRole('button', { name: `Desfazer pagamento de ${nome}` }).filter({ visible: true })).toBeVisible()

  // filtro por tipo e CSV
  await page.getByRole('radio', { name: 'Funcionários' }).click()
  await expect(page.getByText(nome).filter({ visible: true })).toHaveCount(0)
  await expect(page.getByText('Eva Martins').filter({ visible: true }).first()).toBeVisible()
  await page.getByRole('radio', { name: 'Todos' }).click()
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'CSV' }).click()])
  expect(download.suggestedFilename()).toMatch(/^dias-trabalhados_bar-bossa-nova_\d{4}-\d{2}-01_\d{4}-\d{2}-\d{2}\.csv$/)

  // diária de funcionário: só custo, valor padrão da ficha
  await page.getByRole('button', { name: 'Lançar dia' }).first().click()
  await lanc.getByRole('radio', { name: 'Funcionário (só custo)' }).click()
  await expect(lanc.getByLabel('Pontos do dia')).toHaveCount(0)
  await escolher(lanc.getByLabel('Funcionário'), 'Eva Martins')
  await expect(lanc.getByLabel('Valor da diária')).toHaveValue('150,00')
  await expect(lanc.getByText('Padrão do funcionário: R$ 150,00')).toBeVisible()
  await lanc.getByRole('button', { name: 'Cancelar' }).click()

  // ficha do funcionário: valor padrão da diária
  await page.goto(`/funcionarios/${EVA}`)
  await page.getByRole('tab', { name: 'Comissão' }).click()
  await expect(page.getByLabel('Valor padrão da diária')).toHaveValue('150,00')
})

test('comissão diária: o extra entra só no dia em que trabalhou; detalhe por dia e CSV', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  const nome = `Extra Rateio ${sufixo()}`
  // cadastra o extra e lança o dia de ontem com 7 pontos
  await page.goto('/extras?aba=dias')
  await page.getByRole('button', { name: 'Lançar dia' }).first().click()
  const lanc = page.getByRole('dialog', { name: 'Lançar dia trabalhado' })
  const hoje = await lanc.locator('input[type="date"]').first().inputValue()
  const ontem = somar(hoje, -1)
  await lanc.getByRole('button', { name: 'Cadastrar extra' }).click()
  const cadastro = page.getByRole('dialog', { name: 'Novo extra' })
  await cadastro.getByLabel('Nome').fill(nome)
  await cadastro.getByLabel('Pontuação padrão').fill('7')
  await cadastro.getByLabel('Valor da diária').fill('150,00')
  await cadastro.getByLabel('Valor da diária').blur()
  await cadastro.getByRole('button', { name: 'Cadastrar' }).click()
  await expect(lanc.getByLabel('Pontos do dia')).toHaveValue('7')
  await lanc.locator('input[type="date"]').first().fill(ontem)
  await lanc.getByRole('button', { name: 'Lançar', exact: true }).click()
  await expect(page.getByText(`Dia de ${nome} lançado`)).toBeVisible()

  // novo fechamento (rateio diário é o padrão) de ontem a hoje
  await page.goto('/comissoes')
  await page.getByRole('button', { name: 'Novo fechamento' }).first().click()
  const novo = page.getByRole('dialog')
  await novo.getByLabel('Data inicial').fill(ontem)
  await novo.getByLabel('Data final').fill(hoje)
  await expect(novo.getByRole('radio', { name: /Diário/ })).toHaveAttribute('aria-checked', 'true')
  await expect(novo.getByText('Proporcional aos dias trabalhados')).toHaveCount(0)
  await novo.getByRole('button', { name: 'Criar rascunho' }).click()
  await expect(page).toHaveURL(/\/comissoes\/[0-9a-f-]{36}/)
  await expect(page.getByText('Rateio diário').first()).toBeVisible()
  await expect(page.getByText('Prévia confere com o banco')).toBeVisible()
  await semRolagemHorizontal(page)

  // participante extra com selo e 1 dia
  const participantes = page.getByRole(test.info().project.name === 'celular' ? 'listitem' : 'row').filter({ hasText: nome })
  await expect(participantes).toContainText('Extra')
  await expect(participantes).toContainText('1 dia(s)')

  // detalhe por dia: está em ontem, não está em hoje
  await page.getByRole('button', { name: new RegExp(`^${br(ontem)}`) }).click()
  await expect(page.getByRole('table', { name: `Rateio de ${br(ontem)}` })).toContainText(nome)
  const botaoHoje = page.getByRole('button', { name: new RegExp(`^${br(hoje)}`) })
  if (await botaoHoje.count()) {
    await botaoHoje.click()
    await expect(page.getByRole('table', { name: `Rateio de ${br(hoje)}` })).not.toContainText(nome)
  }

  // tirar o extra (prévia) e descartar; modo período mostra o interruptor proporcional
  await page.getByLabel(`Incluir ${nome}`).uncheck()
  await expect(page.getByText(/Prévia com alterações não salvas/)).toBeVisible()
  await page.getByRole('button', { name: 'Descartar' }).click()
  await page.getByRole('radio', { name: 'Por período' }).click()
  await expect(page.getByText('Proporcional aos dias trabalhados')).toBeVisible()
  await expect(page.getByText('Rateio por dia')).toHaveCount(0)
  await page.getByRole('button', { name: 'Descartar' }).click()

  // CSV no formato novo
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Exportar CSV' }).click()])
  const caminho = await download.path()
  const csv = (await import('node:fs')).readFileSync(caminho!, 'utf8')
  expect(csv).toContain('Modo de rateio;Diário')
  expect(csv).toContain('Participante;Tipo;Cargo;Incluído;Pontos;Dias presentes;Valor (R$)')
  expect(csv).toMatch(new RegExp(`${nome};Extra;;Sim;7;1;`))

  // limpa: exclui o rascunho
  await page.getByRole('button', { name: 'Excluir rascunho' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Excluir' }).click()
  await expect(page).toHaveURL(/\/comissoes$/)
})

test('importar extras: CSV com pontuação pendente (prévia, erros por linha), filtro, edição rápida e fechamento bloqueado', async ({ page }) => {
  test.setTimeout(90_000)
  await entrar(page, USUARIOS_DEMO.admin)
  const s = sufixo()
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())
  const ontem = somar(hoje, -1)
  const pendente = `Pendente ${s}`
  const comPontos = `Com Pontos ${s}`
  const csv = [
    'Nome completo;Cargo;CPF;Diária;Pontuação;Datas trabalhadas',
    `${pendente};Cumim;DOC-${s};150,00;;${br(ontem)}`,
    `${comPontos};Bar;;R$ 160;5;${br(ontem)}, ${br(hoje)}`,
    `Antigo ${s};Bar;;100;3;01/01/2020`,
    `Errado ${s};;;;abc;`,
  ].join('\r\n')

  await page.goto('/extras')
  await page.getByRole('button', { name: 'Importar extras' }).click()
  const modal = page.getByRole('dialog', { name: 'Importar extras' })
  const [download] = await Promise.all([page.waitForEvent('download'), modal.getByRole('button', { name: 'Baixar modelo' }).click()])
  expect(download.suggestedFilename()).toBe('modelo-extras.csv')
  await modal.getByLabel('Arquivo CSV de extras').setInputFiles({ name: 'macaw.csv', mimeType: 'text/csv', buffer: Buffer.from(csv) })
  // colunas reconhecidas pelo nome
  await expect(modal.getByRole('combobox', { name: 'Nome', exact: true })).toHaveValue('0')
  await expect(modal.getByRole('combobox', { name: 'Pontos', exact: true })).toHaveValue('4')
  await expect(modal.getByRole('combobox', { name: 'Dias trabalhados (data)' })).toHaveValue('5')
  const previa = modal.locator('[data-teste="previa-extras"]')
  await expect(previa.getByText('3 extra(s)')).toBeVisible()
  await expect(previa.getByText('1 sem pontuação')).toBeVisible()
  await expect(previa.getByText('1 com problema')).toBeVisible()
  await expect(previa.getByText(/Linha 5: Pontos inválidos/)).toBeVisible()
  await expect(previa.getByRole('row').filter({ hasText: pendente })).toContainText('Pendente')
  await semRolagemHorizontal(page)
  await modal.getByRole('button', { name: 'Importar 3 extra(s)' }).click()
  const resultado = modal.locator('[data-teste="resultado-importacao"]')
  await expect(resultado).toBeVisible()
  await expect(resultado.getByText(/Linha 4: Data fora do limite/)).toBeVisible()
  await expect(resultado).toContainText('ficaram com pontuação pendente')
  await modal.getByRole('button', { name: 'Preencher pontuação' }).click()

  // filtro "só pendentes": o importado sem pontos aparece com selo; o com pontos não
  await expect(page).toHaveURL(/pendentes=1/)
  await expect(page.getByText(pendente, { exact: true }).filter({ visible: true })).toBeVisible()
  await expect(page.getByText(comPontos, { exact: true }).filter({ visible: true })).toHaveCount(0)
  await expect(page.getByText('Pontuação pendente').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)

  // dias trabalhados: o dia importado sem pontos aparece pendente
  await page.goto(`/extras?aba=dias&de=${ontem}&ate=${hoje}`)
  const linhaDia = page.getByRole(test.info().project.name === 'celular' ? 'listitem' : 'row').filter({ hasText: pendente })
  await expect(linhaDia.first()).toContainText('Pontuação pendente')

  // fechamento de ontem a hoje: aviso e "Fechar" bloqueado
  await page.goto('/comissoes')
  await page.getByRole('button', { name: 'Novo fechamento' }).first().click()
  const novo = page.getByRole('dialog')
  await novo.getByLabel('Data inicial').fill(ontem)
  await novo.getByLabel('Data final').fill(hoje)
  await novo.getByRole('button', { name: 'Criar rascunho' }).click()
  await expect(page).toHaveURL(/\/comissoes\/[0-9a-f-]{36}/)
  const urlFechamento = page.url()
  const aviso = page.locator('[data-teste="aviso-extras-pendentes"]')
  await expect(aviso).toContainText(pendente)
  await expect(page.getByRole('button', { name: 'Fechar comissão' })).toBeDisabled()
  await expect(page.getByText('Prévia confere com o banco')).toBeVisible()
  const participante = page.getByRole(test.info().project.name === 'celular' ? 'listitem' : 'row').filter({ hasText: pendente })
  await expect(participante.first()).toContainText('Pontuação pendente')

  // edição rápida na lista de extras → o rascunho é recalculado pelo banco
  await aviso.getByRole('link', { name: 'Preencher pontuação' }).click()
  await page.getByLabel(`Pontos de ${pendente}`, { exact: true }).filter({ visible: true }).fill('4')
  await page.getByRole('button', { name: `Salvar pontos de ${pendente}` }).filter({ visible: true }).click()
  await expect(page.getByText(new RegExp(`Pontuação de ${pendente} definida`))).toBeVisible()
  await expect(page.getByText(pendente, { exact: true }).filter({ visible: true })).toHaveCount(0)
  await page.goto(urlFechamento)
  await expect(page.getByText('Prévia confere com o banco')).toBeVisible()
  await expect(page.locator('[data-teste="aviso-extras-pendentes"]').filter({ hasText: pendente })).toHaveCount(0)
  await page.getByRole('button', { name: 'Excluir rascunho' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Excluir' }).click()
  await expect(page).toHaveURL(/\/comissoes$/)
})

test('gastos do período: cartões, gráfico, tabela por pessoa (extras com selo) e CSV', async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin)
  await page.goto('/extras?aba=gastos')
  await page.getByRole('button', { name: 'Mês anterior' }).click()
  await page.getByRole('button', { name: 'Este mês' }).click()
  await expect(page.getByText('Total geral')).toBeVisible()
  await expect(page.getByText('Diárias a pagar').first()).toBeVisible()
  await expect(page.getByText('Comissões previstas').first()).toBeVisible()
  const marcos = page.getByRole('row').filter({ hasText: 'Marcos Freitas' })
  if (test.info().project.name !== 'celular') await expect(marcos.first()).toContainText('Extra')
  else await expect(page.getByText('Marcos Freitas').filter({ visible: true }).first()).toBeVisible()
  await semRolagemHorizontal(page)
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Exportar CSV' }).click()])
  expect(download.suggestedFilename()).toMatch(/^gastos_bar-bossa-nova_\d{4}-\d{2}-01_\d{4}-\d{2}-\d{2}\.csv$/)
  // mês anterior: a comissão fechada (diária) cai dia a dia no gráfico
  await page.getByRole('button', { name: 'Mês anterior' }).click()
  await expect(page.getByRole('list').filter({ has: page.getByRole('listitem', { name: /Comissões fechadas/ }) })).toBeVisible()
  await expect(page.getByText('Fechamentos considerados')).toBeVisible()
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
  // "Hoje" da tela é o dia em America/Sao_Paulo (não o dia UTC)
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())
  const csv = [
    'Reservation ID,Guest name,Date,Time,Party size,Status,Phone,Coluna X',
    `T-${s}-1,Importada Um ${s},${hoje},20:00,4,Confirmed,11999990000,Janela`,
    `T-${s}-2,Importada Dois ${s},2099-01-01,21:15,2,Canceled,,`,
    `T-${s}-3,,${hoje},20:00,2,Confirmed,,`,
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
