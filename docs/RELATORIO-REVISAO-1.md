# Relatório da revisão 1 — revisor/testador

Data: 2026-10-07 · Branch: `claude/practical-meitner-i0phas` (base: commit `e7110e3`) · Sem commit/push (o coordenador faz).

Escopo: rodar toda a bateria, revisão adversarial (segurança, regras de negócio, integrações, front), corrigir os furos com teste
que reproduz, README do cliente e este relatório. Outro agente vai refazer os testes: a seção 5 traz os comandos exatos.

---

## 1. Comandos rodados e resultados

### 1.1 Antes das correções (estado recebido)
| comando | resultado |
|---|---|
| `npm run typecheck` | ok (0 erros) |
| `npm test` (vitest) | 19 arquivos, **219** testes ok |
| `npm run build` | ok |
| `supabase/testes/preparar-postgres.sh && npm run test:banco` | 15 arquivos, **695** verificações ok |
| `ferramentas/gerar-instalar.sh --verificar` + `cmp` com o versionado | instala limpo, reinstala, auditoria ok; `instalar.sql` **idêntico** ao gerado |
| `npm run n8n:verificar` | 9 workflows, 0 erro, 0 aviso |
| `node --test "n8n/**/*.test.mjs"` | **100** testes ok |
| `npm run local` (portas próprias) + Playwright, todos os specs, desktop e celular | **40 ok, 2 falhas** (`casca.spec.ts` "master: seletor de empresa…" nos dois projetos — ver R-07) |

Ambiente usado: `MDG_PORTA_PORTAO=54361 MDG_PORTA_POSTGREST=54363 MDG_LOCAL_BANCO=mdg_revisor ferramentas/local/subir.sh`
(evita colidir com os mocks 54340–54342 e com outros agentes), Vite próprio em `127.0.0.1:5191`
(`npx vite --host 127.0.0.1 --port 5191 --strictPort`) e `E2E_URL=http://127.0.0.1:5191 npx playwright test`
(Chromium de `/opt/pw-browsers`, sem `playwright install`).

### 1.2 Depois das correções
| comando | resultado |
|---|---|
| `npm run typecheck` | ok |
| `npm test` | 19 arquivos ok + 1 pulado (integração real, opt-in); **221** testes ok, 3 pulados |
| `npm run build` | ok |
| `npm run test:banco` | 18 arquivos, **722** verificações ok (novos: `26_ponto_revisao` 7, `56_comissao_desempate` 5, `92_isolamento` 15) |
| `ferramentas/gerar-instalar.sh --verificar` e `npm run sql:conferir` | ok; `instalar.sql` regenerado e idêntico ao gerado |
| atualização de instalação existente (instalar.sql **antigo** + carga demo → instalar.sql **novo** → auditoria) | ok (troca de tipo de retorno de `ponto_dia_empresa` sem erro, privilégios mantidos) |
| `npm run n8n:verificar` | 9 workflows, 0 erro, 0 aviso |
| `node --test "n8n/**/*.test.mjs"` | 100 ok (+1 suíte pulada: integração real) |
| `npm run test:integracao` (novo; com `npm run local` no ar) | **3/3 ok**, rodado 2× seguidas (idempotente) |
| Playwright todos os specs, desktop + celular | **43 ok**, 1 pulado (teste da barra lateral só vale no desktop) |

---

## 2. Achados

Gravidade: **Alta** = dado errado/segurança; **Média** = comportamento errado visível ao usuário ou divergência entre camadas;
**Baixa** = robustez/clareza. Linhas referem-se ao código **depois** da correção.

| # | grav. | onde | descrição | correção | teste que cobre |
|---|---|---|---|---|---|
| R-01 | Média | `supabase/migrations/20261006000220_comissoes.sql` (`comissao_calcular`, bloco "9. maior resto") | **Desempate por nome diferente entre banco e prévia do front.** O banco ordenava `funcionario_nome asc` na collation do banco (no Supabase é linguística: `ana < Ágata < Bruno`); o front compara por código de caractere (`B < a < Á`). Com frações e pontos iguais, o centavo extra ia para pessoas diferentes na prévia e no valor oficial (pendência a). | `funcionario_nome collate "C"` no desempate (= comparação do JS). Contrato §9 atualizado. | `supabase/testes/56_comissao_desempate.sql` (força a coluna para `pt-BR-x-icu`; falha no código antigo) + `web/src/lib/comissao.test.ts` "desempate igual ao banco" |
| R-02 | Média | `web/src/lib/comissao.ts` (ordenação do maior resto) | Desempate final por `funcionario_id`: o front tratava id nulo (snapshot de funcionário excluído) como `''` → **primeiro**; o banco usa `nulls last`. | Nulos por último no front. | `comissao.test.ts` "nomes iguais…" + `56_comissao_desempate.sql` |
| R-03 | Baixa | `comissao_calcular` | Piso e fração calculados com divisão `numeric` de escala finita: em valores extremos (muitos pontos/base enorme) o piso podia arredondar para cima e a soma passar da base (`limit` negativo). | Aritmética exata: `piso = div(base×pe, soma)`, ordem por `mod(base×pe, soma)`. | `56_comissao_desempate.sql` (37 participantes, base ~10¹⁵, Σ = base e cada valor = piso ou piso+1) |
| R-04 | Média | `supabase/migrations/20261006000200_ponto.sql` (`ponto_calcular_dia`, passo 6) | **Atraso falso quando a entrada é esquecida**: com batidas 21:02, 21:29, 01:04 (escala 17:00…) o dia gerava "batida faltando: entrada" **e** "atraso de 242 min", e `atraso_minutos = 242`. | O atraso só vale se a combinação de slots escolhida (§7.3) inclui a entrada; a combinação passou a ser calculada também no dia em andamento. Contrato §7.2 atualizado. | `supabase/testes/26_ponto_revisao.sql` (falha no código antigo) |
| R-05 | Média | `ponto_dia_empresa` (SQL) + `web/src/paginas/ponto/PaginaPontoDia.tsx` + `web/src/consultas/ponto.ts` | **Batidas esperadas recalculadas no front** (pendência b): o front relia `funcionario_jornadas`/`jornada_dias` e montava as esperadas; num **dia abonado em andamento** (situação `em_andamento`) mostrava "FALTA" em todos os horários, e a regra duplicava a do banco. | `ponto_dia_empresa` passou a devolver `esperadas jsonb` (mesmo cálculo do espelho; vazio em abono/folga/sem escala); o front usa o dado do banco e o hook `useEsperadasDoDia` foi removido. Migração faz `drop` condicional (troca de tipo de retorno) — testado o upgrade. Contrato §10.4 e `web/src/tipos/banco.ts` atualizados. | `26_ponto_revisao.sql` (esperadas e abono) + `e2e/operacao.spec.ts` ("n de 2|4 batidas") |
| R-06 | Média | `web/src/componentes/layout/Casca.tsx` | **Bug conhecido: barra lateral do desktop não ocupava a altura total** quando o conteúdo era mais longo que a tela (era `fixed` com a altura da janela; em captura de página inteira, impressão etc. a coluna terminava no meio). | Layout em colunas (`lg:flex`): a coluna lateral estica até o fim do conteúdo (fundo + borda) e o miolo é `sticky top-0 h-dvh` (menu sempre visível ao rolar). | `e2e/casca.spec.ts` "desktop: barra lateral ocupa a altura toda…" (falha no layout antigo: 600 px × 993 px) |
| R-07 | Baixa (teste) | `e2e/casca.spec.ts` "master: seletor de empresa…" | Falhava em desktop e celular: `getByText('Bar Bossa Nova')` casava 3 elementos (opção do seletor, linha da tabela e cartão) → violação de modo estrito do Playwright. O app estava certo. | Seleciona só o elemento visível. | o próprio teste |
| R-08 | Baixa | `web/src/componentes/dominio/VinculoControlId.tsx` | Desvínculo manual (pendência f): o banco grava `vinculo='manual'` com `funcionario_id` nulo **de propósito** (a importação só liga automaticamente `vinculo is null`), mas a tela mostrava só "Sem vínculo", sem explicar por que a importação não religava. | Selo "Desvinculado manualmente" com explicação. Comportamento documentado no contrato §10.2. | revisão manual; regra do banco já coberta em `16_integracoes_sync.sql` |
| R-09 | Baixa (doc) | `docs/CONTRATO.md` §10.9 | ~35 mensagens de erro usadas nas migrações não estavam no contrato (pendência g). | Lista completa adicionada (e os motivos por item das ingestões). | — |
| R-10 | Média (verificação) | integração N8N ↔ banco | Não havia nenhum teste executando os workflows contra as **assinaturas reais** das RPCs (o Supabase dos testes do N8N é falso; os subfluxos de Control iD eram *stubs* no teste da fila). | Simulador (`n8n/mocks/simulador-n8n.mjs`) passou a executar nós **HTTP Request** (+ IF `true/false` e `$()`/`$execution` nas expressões); novo `n8n/integracao-real.test.mjs` roda fila → Zig + Control iD (acesso com envio, REP/AFD), exportação do fechamento, apuração, rotina diária e agendador contra PostgREST local + mocks. **Resultado: nenhuma divergência** de nome/formato de parâmetro; idempotência confirmada. | `npm run test:integracao` |
| R-11 | Média (verificação) | todas as tabelas | Isolamento entre empresas só era testado tabela a tabela, à mão. | `supabase/testes/92_isolamento.sql` varre o catálogo: para **toda** tabela com `empresa_id` (36 tabelas hoje, incluindo `empresas`) e 4 usuários (admin B; admin/gerente/leitura A) confere leitura, update, delete e insert de cópia (inclusive filho apontando para pai da outra empresa), Storage e RPCs cruzadas. **Nenhum vazamento encontrado.** Validado injetando uma política vazada (o teste acusa). | `92_isolamento.sql` |
| R-12 | Baixa (ferramenta) | `ferramentas/gerar-instalar.sh` | Não havia como **só conferir** se o `instalar.sql` versionado está em dia (o `--verificar` regrava o arquivo). | Modo `--conferir` (+ `npm run sql:conferir`). | uso direto |

### Pendências relatadas pelos agentes
| item | situação |
|---|---|
| (a) desempate de nomes front × collation | **corrigido** (R-01, R-02) |
| (b) `ponto_dia_empresa` sem esperadas | **corrigido** (R-05) |
| (c) `eslint-disable` em PaginaFechamento.tsx | já não existia (grep em `web/src`, `e2e`, `n8n`: nenhum `eslint`) |
| (d) campos da Zig em `/erp/faturamento` e `detalhesMaquinaIntegrada` | conferidos: a ingestão lê `paymentId`, `paymentName`, `value`, `eventId`, `eventDate` (e aceita `valor`/`totalValue` como alternativa) e, nos detalhes, `paymentId`, `paymentName`, `eventId`, `values[{cardBrand,totalValue}]`; `redeId`/`lojaId` não são necessários (loja vem do parâmetro da chamada). Mock e ingestão batem; **não validado contra a API real** |
| (e) chamadas ao Supabase em nós Code (n8n-2) | aceitável e documentado em `n8n/README.md` §5: mesmos cabeçalhos, retentativa com *backoff*/`Retry-After`, e o teste de integração real (R-10) confirma o comportamento. Exige `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (já documentado) |
| (f) desvínculo manual grava `vinculo='manual'` sem funcionário | coerente e intencional; documentado e tela ajustada (R-08) |
| (g) mensagens fora do §10.9 | incluídas (R-09) |

### Conferido sem achado (resumo da revisão adversarial)
- **Segurança**: RLS ligada em todas as tabelas; políticas na forma canônica; `[api:nenhum]` sem políticas (`integracoes_segredos`,
  `funcionario_credenciais`, `funcionario_cartoes`); `anon` sem nenhum privilégio; `[servico]` (todas as `ingestao_*`) só para
  `service_role` (auditoria `90_auditoria.sql`); todas as `security definer` com `search_path`; `pode_*` com `coalesce(…, false)` e
  checagens `is not true` (o padrão de NULL que já deu bug está protegido); `funcionario_credenciais()` não devolve senha nem número
  do cartão; bucket de fotos privado com política por pasta da empresa; nenhum segredo no front, nos JSON do N8N
  (`n8n:verificar` + `workflows.test`) nem no git (`.env.local` ignorado; a única ocorrência de `eyJ…` versionada é um hash do
  `package-lock.json`; a carga demo tem credenciais de **mock** e está marcada "não use em produção").
- **Regras de negócio**: comissão (retenção configurável, maior resto, soma exata, proporcional, fechamento imutável inclusive para o
  master) — vetores do §9 no banco e no vitest; ponto (virada 05:00, fuso, duplicidade 2 min, alarmes que identificam a batida
  faltante, auto-resolução e reabertura) — vetores do §7.6; banco de horas (saldo inicial no início do dia, lançamentos, só dias
  encerrados); venda por garçom (Tip fora das vendas, Tip = serviço, ligação na leitura); faturamento por `data_operacao`.
- **Integrações**: assinaturas front (`web/src/tipos/banco.ts`, mapa `Rpcs`) × SQL conferidas uma a uma; N8N × SQL conferido por
  execução real (R-10); AFD 671/1510 (tipo 3 e 7, CRLF/BOM, NSR repetido); janela/cursor do acesso (`max(cursor−1 dia, hoje−retro)`,
  `data_inicio` ignora cursor) e NSR+1 no REP; retentativas; CSV front × N8N idêntico (teste existente compara as duas libs).
- **Front**: todas as rotas do `App.tsx` abrem nos e2e (desktop e celular, sem rolagem horizontal, sem erro no console); guardas de
  papel na rota e na tela; estados de carregando/vazio/erro nas páginas revisadas. **Tela de login** comparada com a referência
  (screenshots 1440 e 390): fundo azul-noite `#060A17`, cartão marinho arredondado, sobrancelha dourada "MEU DIA DE GERENTE", título
  serifado "Organize seu dia." + itálico dourado "Não esqueça nada.", subtítulo lavanda, inputs escuros, checkbox dourado "Manter-me
  conectado", botão dourado "Entrar", botão escuro "Entrar com Google" (aparece com `VITE_LOGIN_GOOGLE=true`; o ambiente local usa
  `false`), "Recuperar senha" sublinhado e "Criar conta" dourado — **fiel**. Diferença menor: o contrato §14.1 cita um divisor "ou"
  entre os botões, que a tela não tem (a descrição da referência também não cita); mantido sem divisor.

---

## 3. O que NÃO pôde ser verificado
- **N8N real**: os workflows foram executados num simulador (código real dos nós Code e das expressões, nós HTTP com `fetch`), não
  importados num N8N. Diferenças possíveis no N8N real: formato de saída do nó HTTP para resposta escalar/vazia (as libs aceitam
  string, `{data}` e `{<rpc>}`), limites do *task runner* (`N8N_RUNNERS_TASK_TIMEOUT`), credencial SMTP e o "Error workflow" que
  precisam ser ligados à mão.
- **Equipamentos Control iD reais** (iDClass, iDFace, iDFlex, iDAccess): validado só contra o mock. Pontos a conferir na implantação:
  `relogio_em_hora_local`, paginação de `load_objects`/`load_users`, formato do AFD do firmware, `user_set_image_list` vs
  `user_set_image`, IDs de portal (o envio usa portal 1), certificado autoassinado do REP.
- **API real da Zig**: nomes de campos conferidos contra a documentação recebida e o mock; limites de taxa e paginação reais não.
- **Supabase de verdade**: Auth (e-mail de confirmação/recuperação, Google), Storage (upload/URL assinada de foto — localmente o
  Storage responde 501) e a collation real do banco (o teste R-01 simula uma collation linguística com ICU).
- **Navegadores além do Chromium** (Safari iOS em especial) e leitores de tela reais.

## 4. Riscos remanescentes
1. `dia_de_trabalho(instante, empresa)` e `dia_de_trabalho_instante` são `[api]` sem checagem de empresa: qualquer usuário logado
   pode descobrir fuso/virada de outra empresa pelo id (dado não sensível; uuids não são enumeráveis). Mantido porque gatilhos
   dependem delas.
2. Cadastro aberto ligado por padrão (qualquer pessoa cria uma empresa vazia). Opção C do `criar_master.sql` (master por e-mail)
   só é segura com **confirmação de e-mail ligada** no Supabase — o README pede isso.
3. Sem CSP no `vercel.json` (há `nosniff`, `X-Frame-Options`, `Referrer-Policy`).
4. Batida importada com `transactionDate`/instante inválido é ignorada item a item (aparece em `erros` da execução, não some em
   silêncio) — vale acompanhar o histórico de execuções nas primeiras semanas.
5. Agendador e "Sincronizar agora" podem rodar a mesma integração ao mesmo tempo; é seguro (ingestões idempotentes), só gasta chamadas.
6. Comparação de nomes no desempate: `collate "C"` (bytes UTF-8) = ordem do JavaScript para todo texto do plano básico do Unicode;
   só caracteres fora dele (emoji) poderiam divergir — irrelevante para nomes.

## 5. Como refazer os testes (para o próximo agente)
```bash
npm ci                                   # se node_modules não existir
npm run typecheck && npm test && npm run build
supabase/testes/preparar-postgres.sh && npm run test:banco          # 722 verificações
ferramentas/gerar-instalar.sh --verificar && npm run sql:conferir
npm run n8n:verificar && node --test "n8n/**/*.test.mjs"
# ambiente local em portas próprias (não colide com os mocks 54340–54342):
MDG_PORTA_PORTAO=54361 MDG_PORTA_POSTGREST=54363 MDG_LOCAL_BANCO=mdg_revisor ferramentas/local/subir.sh --recriar
npm run test:integracao                  # N8N × banco real (3 testes)
npx vite --host 127.0.0.1 --port 5191 --strictPort &   # Vite próprio
E2E_URL=http://127.0.0.1:5191 npx playwright test      # 43 ok + 1 pulado
```

## 6. Arquivos alterados/criados
Alterados: `supabase/migrations/20261006000200_ponto.sql`, `supabase/migrations/20261006000220_comissoes.sql`,
`supabase/instalar.sql` (regenerado), `web/src/lib/comissao.ts`, `web/src/lib/comissao.test.ts`, `web/src/tipos/banco.ts`,
`web/src/consultas/ponto.ts`, `web/src/paginas/ponto/PaginaPontoDia.tsx`, `web/src/componentes/layout/Casca.tsx`,
`web/src/componentes/dominio/VinculoControlId.tsx`, `e2e/casca.spec.ts`, `e2e/operacao.spec.ts`, `n8n/mocks/simulador-n8n.mjs`,
`ferramentas/gerar-instalar.sh`, `package.json` (scripts `test:integracao`, `sql:conferir`), `docs/CONTRATO.md`, `n8n/README.md`,
`supabase/README.md`.
Criados: `README.md` (raiz, para o cliente), `docs/RELATORIO-REVISAO-1.md`, `supabase/testes/26_ponto_revisao.sql`,
`supabase/testes/56_comissao_desempate.sql`, `supabase/testes/92_isolamento.sql`, `n8n/integracao-real.test.mjs`.
