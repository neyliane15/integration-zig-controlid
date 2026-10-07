# Relatório da revisão 2 — segundo testador (independente)

Data: 2026-10-07 · Branch: `claude/practical-meitner-i0phas` (sobre o snapshot `fd5d22c`, que já contém parte destas alterações) ·
Sem commit/push.

Escopo: refazer do zero tudo o que a revisão 1 afirmou, seguir o README como o cliente, testar ponta a ponta com um cenário novo
calculado à mão, caçar furos (fuzz, entradas maliciosas, concorrência, CSV, papéis, acessibilidade, celular) e corrigir.

---

## 1. Comandos e números

### 1.1 Reprodução limpa (antes de qualquer correção)
`rm -rf node_modules dist`, `npm ci`, Postgres parado e o diretório de dados apagado, `mdg_revisor` (54361/54363) derrubado e recriado.

| comando | revisão 1 (§1.2) | revisão 2 (reprodução) |
|---|---|---|
| `npm run typecheck` | ok | ok |
| `npm test` | 19 arquivos + 1 pulado; 221 ok, 3 pulados | **igual** (19 + 1; 221 ok, 3 pulados) |
| `npm run build` | ok | ok |
| `npm run test:banco` | 18 arquivos, 722 verificações | **igual** (722) |
| `gerar-instalar.sh --verificar` + `sql:conferir` | ok, idêntico | ok, idêntico |
| `npm run n8n:verificar` | 9 workflows, 0/0 | igual |
| `node --test "n8n/**/*.test.mjs"` | 100 ok (+1 suíte pulada) | 100 ok (a suíte da integração real aparece como `# SKIP`) |
| `npm run test:integracao` | 3/3, 2× | 3/3, 2× |
| Playwright (desktop + celular) | 43 ok + 1 pulado | 43 ok + 1 pulado |

Nenhuma divergência numérica. **Divergência de conclusão**: a revisão 1 (§4, risco 5) afirmou que agendador e "Sincronizar agora" rodando
a mesma integração ao mesmo tempo "é seguro (ingestões idempotentes)". **Não é** — ver V2-02 (dados da Zig em dobro).

### 1.2 Bateria final (depois das correções), do zero
| comando | resultado |
|---|---|
| `npm ci` / `npm run typecheck` / `npm run build` | ok / ok / ok |
| `npm test` | 21 arquivos + 3 pulados (opt-in); **236** testes ok, 9 pulados |
| `npm run test:banco` | 19 arquivos, **739** verificações (novo `94_revisao2.sql`: 17) |
| `ferramentas/gerar-instalar.sh --verificar` e `npm run sql:conferir` | ok; `instalar.sql` regenerado e idêntico |
| atualização: `instalar.sql` da revisão 1 + demo → `instalar.sql` novo | ok, dados mantidos, `dia_de_trabalho` sem `execute` para `authenticated` |
| `npm run n8n:verificar` | 9 workflows, 0 erro, 0 aviso (cópia da lib CSV atualizada com `--atualizar`) |
| `node --test "n8n/**/*.test.mjs"` | **101** ok |
| `npm run test:integracao` (agora 2 arquivos, em sequência) | **7/7**, rodado 2× seguidas |
| `MDG_PG_BANCO=mdg_revisor npm run test:fuzz` | 4/4; repetido com 8 sementes (`MDG_FUZZ_SEMENTE=1..8`): tudo ok |
| Playwright, todos os specs, desktop + celular | **49 ok** + 1 pulado (novo `e2e/revisao2.spec.ts`) |
| varredura própria: 27 rotas × 4 papéis + 5 públicas, 390 e 1440 px | **226 visitas, 0 problemas** (rolagem horizontal, console, rótulos, nomes, h1, contraste AA) |
| app servido com o CSP do `vercel.json` | 0 violações (login, painel, ponto, vendas, comissões, ficha + recorte de foto) |

Ambiente: `MDG_PORTA_PORTAO=54361 MDG_PORTA_POSTGREST=54363 MDG_LOCAL_BANCO=mdg_revisor ferramentas/local/subir.sh --recriar`,
Vite próprio `npx vite --host 127.0.0.1 --port 5191 --strictPort`, `E2E_URL=http://127.0.0.1:5191 npx playwright test`.
Para o "cliente": banco `mdg_cliente` instalado só com `00_ambiente_supabase.sql` + `supabase/instalar.sql` + `criar_master.sql`
(opção A) + seeds, portão 54371/54373 e Vite 5192 apontando para ele.

---

## 2. Achados novos

Gravidade: **Alta** = dado errado/segurança; **Média** = comportamento errado visível; **Baixa** = robustez/clareza.

| # | grav. | onde | descrição | correção | teste |
|---|---|---|---|---|---|
| V2-02 | **Alta** | `supabase/migrations/20261006000230_ingestao.sql` (4 ingestões Zig "substitui o dia") | Duas cargas do mesmo dia/loja ao mesmo tempo (agendador × "Sincronizar agora", ou 2 pedidos) apagavam o dia e **ambas inseriam**: reproduzido com 8 chamadas paralelas → 4 cópias de cada item; com fila + agendador → itens em dobro. Vendas, **serviço e comissão** inflados. (`zig_faturamento` escapava por um índice único; `saida-produtos`, que alimenta a comissão, não.) | `pg_advisory_xact_lock(hashtextextended('mdg:<tabela>:<empresa>:<loja>:<dia>',0))` antes do `delete` nas 4 funções. Contrato §11.5. | `n8n/cenario-revisao2.test.mjs` (fila + 2 subfluxos agendados simultâneos + 6 RPCs paralelas; **falha com a função antiga**, passa com a nova) e `94_revisao2.sql` |
| V2-01 | Média | `web/src/lib/csv.ts`, `n8n/comum/lib/csv.mjs` (+ cópia no `exportar-fechamento.json`) | **Injeção de fórmula no CSV**: nome de funcionário/cargo e, pior, `employeeName` vindo da Zig iam crus: `=HYPERLINK(...)`, `@SUM(...)` viravam fórmula no Excel (reproduzido exportando a comissão pela tela). | Texto que começa com `= + - @ TAB CR` ganha `'` na frente; números gerados por nós (`-50,00`, `-03:26`) ficam intactos. Mesma regra no front e no N8N. Contrato §13, README §6. | `csv.test.ts`, `csv.test.mjs` (inclui "idêntico ao front"), cenário (CSV do e-mail) |
| V2-03 | Baixa | `dia_de_trabalho`, `dia_de_trabalho_instante` | Risco 1 da revisão 1: `[api]` sem checagem de empresa → fuso/virada de outra empresa pelo id. Todos os chamadores internos são `security definer` (conferido no catálogo); front e N8N não usam. | Etiqueta `[interno]` (sem `execute` para `authenticated`); tipo removido de `tipos/banco.ts`. Contrato §10.1. | `94_revisao2.sql` (falha no código antigo) + gatilhos continuam funcionando |
| V2-04 | Baixa | `vercel.json` | Risco 3 da revisão 1: sem CSP. | CSP (`default-src 'self'`, `connect-src`/`img-src` `*.supabase.co`, `frame-ancestors 'none'`, `object-src 'none'`…) + `Permissions-Policy`. README §3.2 explica domínio próprio do Supabase. | `dist/` servido com o CSP + Playwright: 0 violações |
| V2-05 | Baixa | `ingestao_controlid_envio_resultado` | Funcionário com horário de acesso fica `aguardando`; quando os horários são enviados ele vira `pendente` **depois** de o N8N ler as pendências → ficava parado até o agendador (padrão 1 h). Visto na tela: "Enviar agora" e o Zeca continuou "Aguardando". | Ao registrar `enviado` dos horários, cria um pedido `exportar_funcionarios` automático (sem duplicar). Adendo A.3-6, README §3.4-7. | `94_revisao2.sql` |
| V2-06 | Baixa | `FormularioIntegracao.tsx` × README | README dizia "a cada 15 min o controle de acesso"; o formulário criava todas com 60 min. | Padrão 15 min para `controlid_acesso`. README §3.4. | revisão manual (tela) |
| V2-07 | Baixa | `ponto_incluir_batida`, `banco_horas_lancar` | Fuzz de RPC: batida manual em **1900** aceita; lançamento de **2.147.483.647 min** aceito. | `Horário muito antigo (máximo 1 ano)` e `Minutos fora do limite (máximo 100.000)`. Contrato §10.4/§10.9. | `94_revisao2.sql` |
| V2-08 | Baixa | `web/src/lib/supabase.ts` | Erros do Postgres chegavam em inglês (`date/time field value out of range`, `numeric field overflow`, `duplicate key…`). | Traduções para português. Contrato §10.9. | `web/src/lib/mensagens.test.ts` |
| V2-09 | Baixa (a11y) | `estilos.css`, `ui.tsx`, `PaginaPontoDia`, `PaginaTarefas`, `PaginaAlarmes`, 404 e "Sem permissão" | Contraste do token `lavanda-escuro` 2,7–3,4:1 (rótulos do menu, "—", "folga"); campo de data do ponto/tarefas sem nome; 404 e "Sem permissão" sem `h1`; caixas "Selecionar" iguais em todos os alarmes. | Token `#848AB0` (≥ 4,6:1 em todos os fundos; contrato §14.1); `rotulo` em `EntradaData`; `Vazio principal` vira `h1`; "Selecionar alarme de <nome> em <data>". | varredura (0 problemas) + `e2e/revisao2.spec.ts` |
| V2-10 | Baixa | `web/src/App.tsx` | Leitura abria `/funcionarios/novo` (formulário desabilitado; o banco recusaria). | Rota com `So permitir={podeOperar}`. | `e2e/revisao2.spec.ts` |
| V2-11 | Baixa | `FiltroPeriodo` (`ui.tsx`) | Atalhos "Hoje/Ontem/Este mês" calculavam o dia em São Paulo/05:00 fixo, ignorando fuso e virada da empresa. | Prop `hoje` vinda de `useContextoEmpresa` nas 4 telas. | typecheck + e2e |
| V2-12 | Baixa | `PaginaFechamento.tsx` | Cabeçalho "2 participante(s)" e confirmação "para 3 participante(s)" (contava incluído com 0 pontos). | Confirmação conta só quem tem pontos. | manual |
| V2-13 | Baixa (ferramenta) | `ferramentas/local/subir.sh` | Subir um 2º ambiente em outras portas **matava** o primeiro (pids compartilhados em `run/`). | Pasta `run-<porta>` por porta (padrão inalterado). `ferramentas/local/README.md`. | uso (dois ambientes no ar o tempo todo) |
| V2-14 | Baixa (teste) | `supabase/testes/22_ponto_alarmes.sql` | Falhava depois das 05:00 de 07/10: "nenhum alarme em 06/10" olhava o banco todo, e a carga demo usa o relógio real. | Restrito às empresas do teste. | `npm run test:banco` |
| V2-15 | Baixa (teste) | `package.json` `test:integracao` | Com 2 arquivos, o `node --test` roda em paralelo e um teste lia as execuções do outro. | `--test-concurrency=1`. | 7/7 2× |
| V2-16 | Baixa (doc) | README §3.1-8 | Mandava rodar `carga_demo.sql`, que sozinho não carrega nada. | Instrução com os dois arquivos de `supabase/seed/`. | seguido à risca |

### Conferido sem achado (resumo)
- **Fluxo do cliente pelo navegador** (banco instalado do `instalar.sql`): master cria empresa (nome com `<img onerror>` exibido como texto);
  administrador configura, cria gerente e leitura; gerente cria jornada noturna 18:00/22:00/22:30/02:00, funcionários com pontos e
  jornada; integrações REP e Zig com segredos ("Não configurado" → nunca exibidos; `integracoes_segredos`, `funcionario_credenciais`,
  `funcionario_cartoes` dão 403 para admin, master e leitura); "Sincronizar tudo" cria 2 pedidos; N8N simulado importa; vínculo
  automático pelo CPF; ponto do dia com "3 de 4" e chip "Faltou: Volta do intervalo (prevista 22:30)"; incluir batida (motivo) → dia
  completo 7h36, alarme resolvido sozinho; justificar alarme; banco de horas; vendas R$ 447,95 / serviço R$ 38,45 / ranking; comissão
  R$ 30,76 → **Zeca R$ 20,51 (+1¢), Yara R$ 10,25** (conta à mão abaixo), gerente não vê "Fechar", admin fecha, toda edição posterior
  recusada (RPC e PATCH direto, inclusive master); tarefas com responsável = funcionário ligado à leitura, que marca item e conclui;
  leitura recebe "Sem permissão" em comissões, integrações, configurações, usuários, rotinas e empresas; cartão (só "•••• 7890"), senha
  ("Definida") e horário de acesso entram na fila e chegam ao mock (`time_spans` com a faixa que passa da meia-noite dividida).
- **Conta à mão da comissão**: serviço (Tips) 1000 + 333 + 777 + 1234 + 501 = 3845 centavos; retenção round(3845 × 20%) = 769; base 3076;
  pontos 10 + 5 = 15; Zeca 3076 × 10/15 = 2050,667 → piso 2050; Yara 1025,333 → 1025; Σ pisos 3075, resto 1 → maior fração (Zeca) →
  **2051 + 1025 = 3076**. Banco, prévia ("Prévia confere com o banco") e CSV iguais.
- **Fuzz banco × front**: comissão 200 casos × 9 sementes centavo a centavo; ponto ~880 dias × 9 sementes (2 fusos, viradas 05:00/04:00,
  jornadas que atravessam a meia-noite, duplicadas, desconsideradas): duplicadas, trabalhado, batida faltante (= o que a tela mostra),
  situação e idempotência — **nenhuma divergência**. 3.000 casos só-JS contra referência independente.
- **Entradas maliciosas** (49 chamadas como gerente): ids de outra empresa → `Sem permissão` em todas; períodos invertidos/longos →
  `Período inválido`/`Período máximo de N dias`; datas inválidas → erro (agora traduzido); escopo com SQL → `Escopo inválido`; caminho de
  foto com `../` → `Foto inválida`; `ingestao_*` e `tornar_master` negados a `authenticated`.
- **Concorrência**: 8 ingestões de batidas iguais em paralelo → 3 linhas (on conflict); 8 `ingestao_apurar_ponto` paralelas → ok.
- **XSS**: nenhum `dangerouslySetInnerHTML`/`innerHTML`; nomes com `<script>` aparecem como texto em todas as telas e selects.
- **Login** idêntico à referência (screenshot `01-login_*`).

---

## 3. Cobertura dos requisitos do cliente

| requisito | onde está | como foi testado nesta revisão |
|---|---|---|
| 1. Puxar do Control iD os funcionários | `controlid-importar-usuarios.json`, `ingestao_controlid_usuarios`, aba Control iD / Integrações → Usuários | cenário: 2 usuários do REP ligados pelo CPF (`automatico`); integração real (acesso, matrícula) |
| 2. Banco de horas por funcionário | `banco_horas_*`, `ponto_dias.saldo_minutos`, tela Banco de horas | cenário: −207/−465 → 0 após incluir batida; tela −7h45; fuzz do saldo diário |
| 3. Batidas do dia + alarme da batida faltante | `ponto_calcular_dia`, `ponto_alarmes`, telas Ponto/Alarmes/Espelho | navegador (chip "Faltou… 22:30"), cenário (alarme `volta_intervalo`, resolução automática), fuzz banco × `identificarFaltantes` |
| 4. Faturamento da Zig | `zig-importar.json`, `zig_faturamento`, `vendas_resumo`, Painel/Vendas | cenário (R$ 447,95 por forma de pagamento), concorrência (V2-02) |
| 5. Venda por garçom | `vendas_por_garcom`, aba Garçons | cenário: Zeca 25670/2567/3, Yara 12780/1278/2, balcão 2500; nome da Zig em maiúsculas com espaço liga ao cadastro |
| Comissão (serviço − 20%, por pontos) | `comissao_*`, `web/src/lib/comissao.ts`, telas Comissões | conta à mão, fuzz banco × front, fechamento imutável, CSV (V2-01) |
| Cadastros, pontos, tarefas | Funcionários/Jornadas/Usuários/Tarefas | navegador por papel; leitura conclui tarefa atribuída |
| Envio ao Control iD (cadastro/desligamento, foto, cartão, senha, horários; REP e iDFace/iDFlex/iDAccess) | `controlid-exportar-usuarios.json`, adendo | navegador + mock: cartão, senha, horário chegam ao iDFace; foto só até o recorte (Storage local = 501); V2-05 |
| Layout da tela de login | `PaginaEntrar`, `LayoutAcesso` | screenshots 1440/390; contraste e foco por teclado verificados |

---

## 4. O que não pôde ser verificado
- N8N, Control iD e Zig **reais** (mesmas ressalvas da revisão 1, §3); Supabase real (Auth/e-mails, **Storage — upload de foto**, collation).
- `lower()` do nome do garçom depende do `LC_CTYPE` do banco: no cluster de teste (`C`) `lower('GARÇOM')` ≠ `'garçom'`; no Supabase
  (UTF-8) funciona. Conferir na implantação (checklist). Não alterado (mudaria índice e regra já testada).
- Leitores de tela reais e Safari/iOS (a varredura é automática; o seletor de data nativo mostra o formato do navegador).
- Textos livres sem limite de tamanho (motivo, título, observações aceitam 200 mil caracteres) — só o próprio usuário da empresa grava;
  ficou documentado. Colunas `numeric(18,6)` do valor do ponto estouram acima de ~R$ 10 bilhões por ponto (irreal; fuzz limitado a R$ 1 mi).
- Formulário do master ("Nova empresa") mostra a senha inicial em texto (intencional para repassar; documentado).

## 5. Riscos remanescentes
1. **Cadastro aberto ligado por padrão** (risco 2 da revisão 1): mantido (é o fluxo "Criar conta" do produto); README §7 e checklist
   pedem fechar ou ligar "Confirm email".
2. CSP com domínio próprio do Supabase exige editar o `vercel.json` (README §3.2).
3. Fila + agendador ainda podem rodar a mesma integração juntos (só gasta chamadas): batidas são idempotentes e a Zig agora é serializada.

## 6. Checklist de implantação
- [ ] Supabase: rodar `supabase/instalar.sql`; criar o master (`criar_master.sql`, opção A); **Confirm email** ligado; SMTP próprio;
      Site URL e Redirect URLs; decidir `cadastro_aberto`.
- [ ] No SQL Editor: `select lower('GARÇOM') = 'garçom';` deve dar `true` (ranking de garçons com acento).
- [ ] Vercel: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_LOGIN_GOOGLE`; se o Supabase tiver domínio próprio, ajustar o CSP.
      Depois do deploy, abrir o site e conferir no console que não há "Refused to connect".
- [ ] N8N na rede da loja: `n8n.env` completo (`N8N_BLOCK_ENV_ACCESS_IN_NODE=false`), importar os 9 workflows na ordem, `MDG_WF_*`,
      Error workflow, SMTP, ativar 7 → 8 → 9.
- [ ] Control iD: IP fixo, senha trocada, NTP; validar o horário de uma batida (3.4-6); se usar envio, testar com 1 funcionário
      (cartão, senha, foto no iDFace, horário) antes de ligar para todos.
- [ ] Zig: token e rede; conferir lojas; nome na Zig de cada garçom.
- [ ] Primeira comissão: conferir à mão (serviço − retenção, ÷ soma dos pontos × pontos) antes de fechar; abrir o CSV no Excel.
- [ ] Acompanhar *Integrações → Últimas execuções* na primeira semana (itens ignorados aparecem em `erros`).

## 7. Arquivos
Alterados: `supabase/migrations/20261006000100_base.sql`, `…0140_envio_controlid.sql`, `…0200_ponto.sql`, `…0230_ingestao.sql`,
`supabase/instalar.sql` (regenerado), `supabase/testes/22_ponto_alarmes.sql`, `web/src/lib/csv.ts`, `web/src/lib/csv.test.ts`,
`web/src/lib/supabase.ts`, `web/src/componentes/ui.tsx`, `web/src/componentes/integracoes/FormularioIntegracao.tsx`,
`web/src/componentes/layout/RotaProtegida.tsx`, `web/src/estilos.css`, `web/src/App.tsx`, `web/src/tipos/banco.ts`,
`web/src/paginas/{PaginaNaoEncontrada,ponto/PaginaPontoDia,ponto/PaginaAlarmes,tarefas/PaginaTarefas,vendas/PaginaVendas,banco-horas/PaginaExtratoBancoHoras,comissoes/PaginaComissoes,comissoes/PaginaFechamento}.tsx`,
`n8n/comum/lib/csv.mjs`, `n8n/comum/lib/csv.test.mjs`, `n8n/comum/workflows/exportar-fechamento.json`, `ferramentas/local/subir.sh`,
`ferramentas/local/README.md`, `vercel.json`, `package.json` (`test:integracao`, `test:fuzz`), `README.md`, `docs/CONTRATO.md`,
`docs/CONTRATO-ADENDO-envio-controlid.md`.
Criados: `docs/RELATORIO-REVISAO-2.md`, `supabase/testes/94_revisao2.sql`, `n8n/mocks/cenario-revisao2.mjs`,
`n8n/cenario-revisao2.test.mjs`, `web/src/lib/comissao.fuzz.test.ts`, `web/src/lib/ponto.fuzz.test.ts`, `web/src/lib/mensagens.test.ts`,
`e2e/revisao2.spec.ts`.
Screenshots finais (1440 e 390): `scratchpad/telas-final/` — login, painel, funcionários, ficha (aba Control iD), ponto do dia, alarmes,
banco de horas, vendas (faturamento e garçons), fechamento de comissão, tarefas, integrações.

## 8. Como refazer
```bash
npm ci && npm run typecheck && npm test && npm run build
supabase/testes/preparar-postgres.sh && npm run test:banco                 # 739 verificações
ferramentas/gerar-instalar.sh --verificar && npm run sql:conferir
npm run n8n:verificar && node --test "n8n/**/*.test.mjs"                     # 101
MDG_PORTA_PORTAO=54361 MDG_PORTA_POSTGREST=54363 MDG_LOCAL_BANCO=mdg_revisor ferramentas/local/subir.sh --recriar
npm run test:integracao                                                      # 7 (2 arquivos, em sequência)
MDG_PG_BANCO=mdg_revisor npm run test:fuzz                                   # 4 (MDG_FUZZ_SEMENTE=n para outra semente)
npx vite --host 127.0.0.1 --port 5191 --strictPort &
E2E_URL=http://127.0.0.1:5191 npx playwright test                            # 49 ok + 1 pulado
```
