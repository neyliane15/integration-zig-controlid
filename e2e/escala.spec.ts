/**
 * Escala rotativa (adendo escala v2). Exigem o ambiente local (§15.2) com a migração …0280 e a carga 40_demo_escala.
 * - leitura vê a escala do mês da demo (sem editar);
 * - empresa nova (sem escala, sem ponto, sem integração): montar pelo modelo Macaw → renomear funcionário → marcar folga
 *   clicando → voltar ao automático → digitar horário → copiar TSV. Cada projeto cria a sua conta, então não há disputa de dados.
 */
import type { Page } from "@playwright/test";
import {
  backendNoAr,
  entrar,
  expect,
  semRolagemHorizontal,
  test,
  USUARIOS_DEMO,
} from "./apoio/fixtures";

test.beforeEach(async () => {
  test.skip(!(await backendNoAr()), "backend local fora do ar");
});

function dataBR(iso: string): string {
  const [a, m, d] = iso.split("-");
  return `${d}/${m}/${a}`;
}

async function abrirAba(page: Page, nome: string | RegExp) {
  await page.getByRole("tab", { name: nome }).click();
}

test("leitura vê a escala do mês da demonstração, sem editar", async ({
  page,
}) => {
  await entrar(page, USUARIOS_DEMO.leitura);
  await page.goto("/escala?aba=mes");
  const grade = page.locator('[data-teste="grade-mes"]');
  await expect(grade).toBeVisible();
  await expect(grade.getByText("Salão", { exact: true })).toBeVisible();
  await expect(grade.getByText("Na escala", { exact: true })).toBeVisible();
  const celula = grade.locator('input[aria-label^="Ana Souza, dia"]').first();
  await expect(celula).toHaveAttribute("readonly", "");
  await expect(
    page.getByRole("button", { name: "Folga", exact: true }),
  ).toHaveCount(0);
  await semRolagemHorizontal(page);
  // aba geral e de setor
  await abrirAba(page, "Geral");
  await expect(page.getByRole("cell", { name: "Todos" })).toBeVisible();
  await abrirAba(page, "Salão");
  await expect(page.getByText("Caminho a seguir")).toBeVisible();
  await semRolagemHorizontal(page);
});

test("empresa sem escala: modelo Macaw → renomear → folga clicando → automático → horário → copiar", async ({
  page,
  context,
}, info) => {
  test.setTimeout(90_000);
  await context
    .grantPermissions(["clipboard-read", "clipboard-write"])
    .catch(() => undefined);
  const email = `escala-${info.project.name}-${Date.now()}@teste.local`;

  // conta e estabelecimento novos (sem funcionários, sem ponto, sem integração)
  await page.goto("/criar-conta");
  await page.getByLabel("Seu nome").fill("Gerente Macaw");
  await page.getByLabel("E-mail").fill(email);
  await page.getByLabel("Senha", { exact: true }).fill("gerente123");
  await page.getByRole("button", { name: "Criar conta" }).click();
  await expect(page).toHaveURL(/\/comecar/, { timeout: 15_000 });
  await page.getByLabel("Nome do estabelecimento").fill("Macaw Teste");
  await page.getByRole("button", { name: "Criar estabelecimento" }).click();
  await expect(page.locator("#conteudo")).toBeVisible({ timeout: 15_000 });

  // estado vazio → montar pelo modelo
  await page.goto("/escala");
  await expect(page.getByText("A escala ainda não foi montada")).toBeVisible();
  await page
    .getByRole("button", { name: "Montar escala a partir do modelo Macaw" })
    .click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "Montar escala" })
    .click();
  await expect(
    page.getByText(/Escala montada: 6 setor\(es\), 33 posição/),
  ).toBeVisible();
  for (const s of ["Salão", "Maître", "Areia", "Bar", "ASG", "Cozinha"])
    await expect(page.getByRole("tab", { name: s, exact: true })).toBeVisible();

  // aba do setor: caminho com setas
  await abrirAba(page, "Areia");
  await expect(page.getByLabel("Caminho 1").getByText("Areia 2")).toBeVisible();

  // renomear funcionário na aba Equipe
  await abrirAba(page, /^Equipe/);
  await page.getByRole("button", { name: "Editar nome de Garçom 1" }).click();
  await page.getByLabel("Nome do funcionário").fill("Joana Lima");
  await page.getByRole("button", { name: "Salvar nome" }).click();
  await expect(page.getByText("Nome atualizado.")).toBeVisible();
  await expect(
    page.locator('[data-teste="membro"][data-nome="Joana Lima"]'),
  ).toBeVisible();
  await semRolagemHorizontal(page);

  // escala do mês: marcar folga clicando no dia de hoje
  await abrirAba(page, "Escala do mês");
  const grade = page.locator('[data-teste="grade-mes"]');
  await expect(grade).toBeVisible();
  const hoje = (await grade.getAttribute("data-hoje"))!;
  const td = grade
    .locator(`td[data-data="${hoje}"]`)
    .filter({ has: page.locator('input[aria-label^="Joana Lima,"]') });
  const celula = grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`);
  await celula.click();
  const painel = page.locator('[data-teste="painel-dia"]');
  await expect(painel).toContainText("Joana Lima");
  const automatico = await td.getAttribute("data-status");
  const alvo = automatico === "folga" ? "Trabalha" : "Folga";
  const status = automatico === "folga" ? "trabalha" : "folga";
  await painel.getByRole("button", { name: alvo, exact: true }).click();
  await expect(td).toHaveAttribute("data-status", status);
  await expect(td).toHaveAttribute("data-ajustado", "1");
  await expect(painel.locator('[data-teste="estado-dia"]')).toContainText(
    /ajustad/,
  );

  // persiste no banco
  await page.reload();
  await expect(
    grade
      .locator(`td[data-data="${hoje}"]`)
      .filter({ has: page.locator('input[aria-label^="Joana Lima,"]') }),
  ).toHaveAttribute("data-status", status);

  // voltar ao automático
  await grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`).click();
  await painel.getByRole("button", { name: "Automático", exact: true }).click();
  await expect(td).toHaveAttribute("data-status", automatico!);
  await expect(td).not.toHaveAttribute("data-ajustado", "1");

  // digitar: "f" + Enter marca folga (ou mantém a automática) e desce; digitar horário vira 11h30
  const c2 = grade.getByLabel(`Joana Lima, dia ${dataBR(hoje)}`);
  await c2.click();
  await c2.fill("11:30");
  await c2.press("Enter");
  await expect(c2).toHaveValue("11h30");
  await expect(td).toHaveAttribute("data-status", "trabalha");
  await expect(td).toHaveAttribute("data-ajustado", "1");

  // copiar para o Excel (TSV); sem área de transferência, cai na caixa de texto
  await page.getByRole("button", { name: "Copiar para Excel" }).click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: /Escala copiada|Não consegui copiar/ }),
  ).toBeVisible();
  const caixa = page.getByLabel("Escala em texto para copiar");
  const tsv = (await caixa.count())
    ? await caixa.inputValue()
    : await page.evaluate(() => navigator.clipboard.readText());
  const linhas = tsv.split("\n");
  expect(linhas[0]).toMatch(/^Nome\t1 [A-ZÁ]{3}\t/);
  expect(linhas).toContain("Salão");
  expect(
    linhas.some((l) => l.startsWith("Joana Lima\t") && l.includes("11h30")),
  ).toBe(true);
  expect(linhas.at(-1)).toMatch(/^Na escala\t/);
  await semRolagemHorizontal(page);
});

test("faltas: FI digitada, FJ pelo painel (motivo), legenda, bloqueios e remover; fechamento exclui o faltoso", async ({
  page,
}, info) => {
  test.setTimeout(90_000);
  await entrar(page, USUARIOS_DEMO.admin);
  await page.goto("/escala?aba=mes");
  const grade = page.locator('[data-teste="grade-mes"]');
  await expect(grade).toBeVisible();
  const hoje = (await grade.getAttribute("data-hoje"))!;
  await expect(page.locator('[data-teste="legenda-escala"]')).toContainText(
    "Falta injustificada",
  );
  await expect(page.locator('[data-teste="legenda-escala"]')).toContainText(
    "Falta justificada",
  );

  // quem trabalha hoje (sem batida ainda): uma pessoa por projeto, para os dois rodarem juntos
  const trabalham = grade.locator(
    `td[data-data="${hoje}"][data-status="trabalha"]:not([data-falta]) input`,
  );
  const rotulos = await trabalham.evaluateAll((els) =>
    els.map((e) => e.getAttribute("aria-label")!),
  );
  const rotulo = rotulos[info.project.name === "celular" ? 1 : 0]!;
  expect(rotulo).toBeTruthy();
  const nome = rotulo.split(",")[0]!;
  const celula = grade.getByLabel(rotulo, { exact: true });
  const td = grade
    .locator(`td[data-data="${hoje}"]`)
    .filter({ has: page.locator(`input[aria-label="${rotulo}"]`) });
  const painel = page.locator('[data-teste="painel-dia"]');

  // FI digitada na célula
  await celula.click();
  await celula.fill("fi");
  await celula.press("Enter");
  await expect(page.getByText(`Falta injustificada de ${nome} registrada`)).toBeVisible();
  await expect(td).toHaveAttribute("data-falta", "injustificada");
  await expect(celula).toHaveValue("FI");
  // com falta: folga/troca bloqueadas; remover pelo painel
  await celula.click();
  await expect(painel.locator('[data-teste="estado-dia"]')).toContainText("Falta injustificada");
  await expect(painel.getByRole("button", { name: "Folga", exact: true })).toBeDisabled();
  await painel.getByRole("button", { name: "Remover falta" }).click();
  await expect(page.getByText("Falta removida")).toBeVisible();
  await expect(td).not.toHaveAttribute("data-falta", /.+/);

  // FJ: o botão do painel abre o motivo; digitar "fj" na célula também (motivo obrigatório)
  await celula.click();
  await painel.getByRole("button", { name: "Falta justificada", exact: true }).click();
  await expect(painel.getByLabel("Motivo da falta justificada")).toBeVisible();
  await painel.getByRole("button", { name: "Falta justificada", exact: true }).click();
  await expect(painel.getByLabel("Motivo da falta justificada")).toHaveCount(0);
  await celula.click();
  await celula.fill("fj");
  await celula.press("Enter");
  await expect(painel.getByLabel("Motivo da falta justificada")).toBeFocused();
  await expect(painel).toContainText(nome);
  await painel.getByRole("button", { name: "Registrar falta" }).click();
  await expect(page.getByText("Informe o motivo")).toBeVisible();
  await painel.getByLabel("Motivo da falta justificada").fill("Atestado médico (e2e)");
  await expect(painel.getByLabel("Anexo da falta (opcional)")).toHaveAttribute("accept", /pdf/);
  await painel.getByRole("button", { name: "Registrar falta" }).click();
  await expect(page.getByText(`Falta justificada de ${nome} registrada`)).toBeVisible();
  await expect(td).toHaveAttribute("data-falta", "justificada");
  await expect(celula).toHaveValue("FJ");
  await semRolagemHorizontal(page);

  // digitar outra coisa num dia com falta é recusado (a célula volta)
  await celula.click();
  await celula.fill("f");
  await celula.press("Enter");
  await expect(page.getByText(/Dia com falta em \d{2}\/\d{2}\/\d{4}: remova a falta antes/)).toBeVisible();
  await expect(celula).toHaveValue("FJ");

  // ficha: falta listada; ponto do dia: situação
  // fechamento de hoje: o faltoso fica fora do rateio, com o motivo
  await page.goto("/comissoes");
  await page.getByRole("button", { name: "Novo fechamento" }).first().click();
  const novo = page.getByRole("dialog");
  await novo.getByLabel("Data inicial").fill(hoje);
  await novo.getByLabel("Data final").fill(hoje);
  await novo.getByRole("button", { name: "Criar rascunho" }).click();
  await expect(page).toHaveURL(/\/comissoes\/[0-9a-f-]{36}/);
  await expect(page.getByText("Prévia confere com o banco")).toBeVisible();
  await page.getByRole("button", { name: new RegExp(`^${dataBR(hoje)}`) }).click();
  const ausentes = page.locator('[data-teste="ausentes-dia"]');
  await expect(ausentes.getByRole("listitem").filter({ hasText: nome })).toContainText("Falta justificada");
  const tabelaDia = page.getByRole("table", { name: `Rateio de ${dataBR(hoje)}` });
  if (await tabelaDia.count()) await expect(tabelaDia).not.toContainText(nome);
  await semRolagemHorizontal(page);
  await page.getByRole("button", { name: "Excluir rascunho" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Excluir" }).click();
  await expect(page).toHaveURL(/\/comissoes$/);

  // limpa: apagar o código na célula remove a falta
  await page.goto("/escala?aba=mes");
  const c = page.locator('[data-teste="grade-mes"]').getByLabel(rotulo, { exact: true });
  await c.click();
  await c.fill("");
  await c.press("Enter");
  await expect(page.getByText("Falta removida")).toBeVisible();
});

test("ficha: desligar avisa que a pessoa sai da comissão; aba Comissão lista as faltas", async ({ page }) => {
  await entrar(page, USUARIOS_DEMO.admin);
  await page.goto("/funcionarios/a0000000-0000-4000-8000-000000000304");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Davi");
  await page.getByRole("button", { name: "Desligar" }).click();
  const dialogo = page.getByRole("dialog");
  await expect(dialogo.locator('[data-teste="aviso-desligamento-comissao"]')).toContainText(/sai do rateio a partir de \d{2}\/\d{2}\/\d{4}/);
  await dialogo.getByRole("button", { name: "Cancelar" }).click();
  await page.getByRole("tab", { name: "Comissão" }).click();
  await expect(page.getByText("Últimos 60 dias", { exact: false })).toBeVisible();
  await semRolagemHorizontal(page);
});
