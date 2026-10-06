# Divisão de trabalho — 6 agentes em paralelo

Regra de ouro: **cada arquivo tem exatamente um dono**. Só o dono cria, edita ou apaga o arquivo. Precisa de mudança num arquivo
alheio? Peça ao dono (ou ao coordenador). Se for mudança de contrato, altere `docs/CONTRATO.md` primeiro (dono: **coordenador**).

Siglas: **b1** = backend-1, **b2** = backend-2, **f1** = frontend-1, **f2** = frontend-2, **n1** = n8n-1, **n2** = n8n-2.
"Pasta inteira" = tudo dentro dela, inclusive arquivos novos.

---

## Coordenador (planejamento — não é um dos 6)
- `docs/CONTRATO.md`, `docs/DIVISAO.md`
- `package.json`, `package-lock.json` (dependência nova: peça ao coordenador; `npm install <pacote>` só ele roda)
- `tsconfig.json`, `vite.config.ts`, `vercel.json`, `.gitignore`, `.env.example`, `README.md` (raiz)

---

## backend-1 (b1) — base, auth, empresas, cadastros, integrações, sync, tarefas
Migrações:
- `supabase/migrations/20261006000100_base.sql`
- `supabase/migrations/20261006000110_cadastros.sql`
- `supabase/migrations/20261006000120_integracoes_sync.sql`
- `supabase/migrations/20261006000130_tarefas.sql`
- `supabase/migrations/20261006000900_permissoes.sql` (varredura de etiquetas — sempre a última)

Infra de banco e testes:
- `supabase/testes/00_ambiente_supabase.sql`, `supabase/testes/preparar-postgres.sh`, `supabase/testes/executar.sh`
- `supabase/testes/10_base_rls.sql`, `12_usuarios.sql`, `14_cadastros.sql`, `16_integracoes_sync.sql`, `18_tarefas.sql`, `90_auditoria.sql`
  (todo `supabase/testes/1*.sql` e `supabase/testes/9*.sql`)
- `supabase/seed/10_demo_base.sql`
- `supabase/README.md`, `supabase/instalar.sql` (gerado; regerar no fim), `supabase/instalacao/` (pasta inteira: SQLs avulsos de instalação, ex.: criar master)
- `ferramentas/gerar-instalar.sh`
- `ferramentas/local/` (pasta inteira: `subir.sh`, `portao.mjs`, `preparar.sql`, `README.md`, …)

Entrega (contrato §5, §10.1–10.3, §11.3, §15.1–15.3): tabelas `empresas`, `perfis`, `configuracao`, `funcionarios`, `funcionario_pontos`,
`jornadas`, `jornada_dias`, `funcionario_jornadas`, `integracoes`, `integracoes_segredos`, `controlid_usuarios`, `sync_solicitacoes`,
`sync_execucoes`, `tarefas_rotinas`, `tarefas_rotina_itens`, `tarefas`, `tarefa_itens`; funções `agora`, `tocar_atualizado_em`, auxiliares
de política, `dia_de_trabalho*`, `resolver_empresa`, `pontos_vigentes`; RPCs de usuários/empresa, integrações, sync, tarefas,
`ingestao_controlid_usuarios`, `ingestao_integracoes_ativas`, `ingestao_integracao_config`, `ingestao_funcionarios_para_exportar`,
`ingestao_sync_*`, `ingestao_tarefas_gerar`.
**Prioridade**: `…0100` e `…0110` primeiro (b2 depende), depois `executar.sh`/`00_ambiente` (b2 precisa para testar).

---

## backend-2 (b2) — ponto, banco de horas, Zig, comissões, ingestão, painel
Migrações:
- `supabase/migrations/20261006000200_ponto.sql` (inclui os gatilhos do §7.8 em tabelas do b1)
- `supabase/migrations/20261006000210_zig.sql`
- `supabase/migrations/20261006000220_comissoes.sql`
- `supabase/migrations/20261006000230_ingestao.sql`
- `supabase/migrations/20261006000240_painel.sql`

Testes e carga:
- `supabase/testes/20_ponto_apuracao.sql`, `22_ponto_alarmes.sql`, `24_ponto_ajustes.sql`, `30_banco_horas.sql`, `40_zig.sql`,
  `50_comissoes.sql`, `60_ingestao.sql`, `65_painel.sql` (todo `supabase/testes/2*.sql` … `6*.sql`)
- `supabase/seed/20_demo_operacao.sql`

Entrega (contrato §6–§9, §10.4–10.8, §11.4–11.6): tabelas `ponto_*`, `banco_horas_lancamentos`, `zig_*`, `comissao_*`; apuração; RPCs de ponto,
banco de horas, vendas, comissões, `painel_do_dia`, `ingestao_controlid_batidas`, `ingestao_zig_*`, `ingestao_apurar_ponto`,
`ingestao_fechamento_exportar`. Escreve contra o DDL do §5 sem alterá-lo. Toda tabela/função com etiqueta (§2.2).

---

## frontend-1 (f1) — design system, casca, acesso, painel, integrações, configurações, master
- `web/index.html`, `web/public/` (pasta inteira: favicon etc.)
- `web/src/main.tsx`, `web/src/App.tsx`, `web/src/estilos.css`
- `web/src/tipos/banco.ts` (versão inicial do coordenador; f1 mantém — mudanças pedidas por f2 entram aqui)
- `web/src/componentes/ui.tsx`, `web/src/componentes/avisos.tsx`, `web/src/componentes/layout/` (pasta inteira: casca, menu, seletor de empresa, rota protegida)
- `web/src/componentes/acesso/` (pasta inteira), `web/src/componentes/integracoes/` (pasta inteira)
- `web/src/lib/supabase.ts`, `sessao.tsx`, `permissoes.ts`, `formato.ts` (+ `formato.test.ts`), `csv.ts` (+ `csv.test.ts`), `rotulos.ts`,
  `consultas.ts`, `configuracao.ts`
- `web/src/consultas/painel.ts`, `integracoes.ts`, `usuarios.ts`, `empresas.ts`
- `web/src/paginas/acesso/` (pasta inteira), `web/src/paginas/painel/` (pasta inteira), `web/src/paginas/integracoes/` (pasta inteira),
  `web/src/paginas/configuracoes/` (pasta inteira), `web/src/paginas/master/` (pasta inteira), `web/src/paginas/PaginaNaoEncontrada.tsx`
- `playwright.config.ts`, `e2e/apoio/` (pasta inteira), `e2e/acesso.spec.ts`, `e2e/casca.spec.ts`

**Prioridade**: `ui.tsx`, `avisos.tsx`, `supabase.ts` (`chamarRpc`), `sessao.tsx`, `formato.ts`, `csv.ts`, `rotulos.ts`, `consultas.ts`,
`App.tsx` com as rotas lazy do §14.3 — f2 depende disso. Não mudar props/assinaturas do §14.5–14.6 sem atualizar o contrato.

---

## frontend-2 (f2) — funcionários, ponto, banco de horas, vendas, comissões, tarefas
- `web/src/paginas/funcionarios/`, `web/src/paginas/ponto/`, `web/src/paginas/banco-horas/`, `web/src/paginas/vendas/`,
  `web/src/paginas/comissoes/`, `web/src/paginas/tarefas/` (pastas inteiras)
- `web/src/componentes/dominio/` (pasta inteira: `SeletorFuncionario`, `VinculoControlId`, `SeloSituacaoDia`, `SeloAlarme`, …)
- `web/src/lib/ponto.ts`, `ponto.test.ts`, `comissao.ts`, `comissao.test.ts`, `vendas.ts`, `vendas.test.ts`, `tarefas.ts`, `tarefas.test.ts`
- `web/src/consultas/funcionarios.ts`, `ponto.ts`, `bancoHoras.ts`, `vendas.ts`, `comissoes.ts`, `tarefas.ts`
- `e2e/operacao.spec.ts`

**Primeiro passo**: criar cada página do §14.3 que é sua com o *named export* exato (mesmo que mínima), para o `App.tsx` do f1 compilar.
Usa componentes de `ui.tsx`/`avisos.tsx` e libs do f1 só pelas assinaturas do contrato. Tipo novo/faltando em `banco.ts`: pedir ao f1.

---

## n8n-1 (n1) — Control iD
- `n8n/controlid/` (pasta inteira):
  - `workflows/controlid-importar-usuarios.json`, `workflows/controlid-importar-batidas.json`, `workflows/controlid-exportar-usuarios.json`
  - `lib/afd.mjs` + `lib/afd.test.mjs` (parser AFD 671 e 1510, §12.4)
  - `lib/controlid.mjs` + `lib/controlid.test.mjs` (montagem de corpos, conversão unix → `instante_local`/`instante`, mapeamento de usuários/logs, cálculo de `T` a partir do cursor)
  - `lib/__dados__/` (amostras de AFD e respostas para os testes)
  - `README.md` (como cadastrar o equipamento, rede/VPN, como validar o relógio)

Entrada/saída dos subfluxos e chamadas: contrato §12.2–12.4. Testa contra o mock do n2 (portas 54341/54342) — se o mock ainda não
existir, usa os próprios `lib/__dados__`.

---

## n8n-2 (n2) — Zig, fila "sincronizar agora", agendador, rotina diária, exportação, erros, mocks, verificação
- `n8n/zig/` (pasta inteira): `workflows/zig-importar.json`, `lib/zig.mjs` + `lib/zig.test.mjs` (dias do período, URLs, resumo de contagens)
- `n8n/comum/` (pasta inteira): `workflows/sincronizar-agora.json`, `agendador.json`, `rotina-diaria.json`, `exportar-fechamento.json`, `erros.json`;
  `lib/supabase.mjs` (montar chamadas RPC), `lib/csv.mjs` + `lib/csv.test.mjs` (CSV de comissão, §13 — mesmo formato do front)
- `n8n/mocks/` (pasta inteira): `servidor.mjs` (Zig 54340, Control iD acesso 54341, REP 54342), `dados/`
- `n8n/README.md`, `n8n/.env.example`, `n8n/verificar.mjs` (valida JSON dos workflows, nomes `MDG · …`, presença dos gatilhos, e que o código
  dos nós Code marcado com `// @lib <arquivo>` é idêntico ao da lib correspondente)

---

## Arquivos que ninguém edita à mão
- `supabase/instalar.sql` — gerado por `ferramentas/gerar-instalar.sh` (b1 roda no fim).
- `package-lock.json` — gerado pelo `npm install` (coordenador).
- `dist/`, `node_modules/`, `test-results/`, `playwright-report/` — ignorados pelo git.

## Convenção para código dentro dos workflows N8N
O código-fonte de verdade fica em `n8n/**/lib/*.mjs` (funções puras com `export`, sem `import`). O nó Code do workflow contém uma cópia
começando com a linha `// @lib controlid/lib/afd.mjs` (caminho relativo a `n8n/`), seguida do conteúdo da lib **sem** as palavras `export`,
e depois o trecho que usa as funções. `npm run n8n:verificar` confere a cópia.

## Comunicação entre agentes
- Dúvida de contrato → coordenador. Pedido de mudança em arquivo alheio → dono do arquivo.
- Ninguém faz commit; o coordenador integra.
