# Meu Dia de Gerente

Sistema para o gerente de bar, restaurante ou loja acompanhar o dia num só lugar: **ponto dos funcionários** (relógios e
leitores Control iD), **vendas e faturamento** (Zig), **comissão** (serviço/10%), **banco de horas** e **tarefas** da rotina.

> Este guia é para quem vai **instalar e usar** o sistema. Detalhes técnicos ficam em `docs/CONTRATO.md` (regras e banco),
> `supabase/README.md`, `n8n/README.md` e `n8n/controlid/README.md`.

---

## 1. O que o sistema faz

| Pedido | Como o sistema atende |
|---|---|
| Puxar do Control iD os funcionários cadastrados | Importa os usuários de cada equipamento e liga cada um ao funcionário do sistema automaticamente (pela **matrícula**, depois CPF, depois PIS). Os que sobrarem você liga com um clique. |
| Banco de horas de cada funcionário | Os equipamentos não guardam banco de horas, então o **sistema calcula**: batidas × jornada (escala) de cada dia, com tolerância, saldo inicial e lançamentos manuais (ajuste, compensação, pagamento em folha). |
| Quantas vezes bateu o ponto e **alarme** se faltou algum horário | Tela *Ponto* mostra, para cada funcionário, "3 de 4 batidas" e **qual** batida faltou (ex.: "Faltou a volta do intervalo (21:30)"). Alarmes: batida faltando, número ímpar de batidas, nenhuma batida em dia de escala e (opcional) atraso. O alarme some sozinho se a batida aparecer depois; o gerente pode justificar. |
| Faturamento da Zig | Faturamento por dia e por forma de pagamento (e por bandeira de cartão), no painel e na tela *Vendas*. |
| Venda por garçom | Ranking por garçom (valor vendido, serviço/10% e nº de vendas), ligado ao cadastro do funcionário pelo nome usado na Zig. |
| Comissão | **Serviço (10%) da Zig − 20%** (percentual configurável) = valor a dividir; dividido pelos **pontos de comissão** de cada funcionário, com centavos exatos (a soma bate sempre). Opcional: proporcional aos dias trabalhados. Depois de **fechada** a comissão não muda mais; exporta CSV e envia por e-mail. |
| Enviar dados ao Control iD | Cadastro e desligamento do funcionário, **foto facial** (iDFace), **cartão/crachá**, **senha (PIN)** e **horários de acesso**. Funciona com relógio de ponto **REP iDClass** e com controle de acesso **iDFace / iDFlex / iDAccess** (o modelo é escolhido na integração). Desligado por padrão: você liga por equipamento. |
| Cadastros, tarefas | Funcionários, jornadas (escalas), usuários do sistema com papéis, rotinas de tarefas com checklist (diárias, semanais, mensais). |

**Papéis de acesso**

| Papel | Pode |
|---|---|
| Master | Dono da plataforma: cria e desativa empresas, vê todas. |
| Administrador | Tudo da própria empresa: usuários, integrações (senhas dos equipamentos e token da Zig), configurações, **fechar** comissão. |
| Gerente | Operação do dia: funcionários, ponto (incluir/desconsiderar batida, justificar, abonar), banco de horas, tarefas, sincronizar, comissão em rascunho. |
| Somente leitura | Vê painel, ponto, banco de horas, vendas e tarefas. Não vê comissões nem integrações. Pode marcar as tarefas atribuídas a ele. |

---

## 2. Como as peças se encaixam

```
 Navegador (celular ou computador)
        │  site (Vercel)
        ▼
 Supabase  ── banco de dados, login e fotos (tudo protegido por empresa)
        ▲
        │  grava os dados
 N8N (robô de integração, de preferência num computador NA LOJA)
   ├── Zig (internet)            → vendas, faturamento, serviço
   └── Control iD (rede da loja) → funcionários, batidas; e envia cadastros/fotos/cartões/horários
```

O botão **"Sincronizar agora"** só deixa um pedido no banco; o N8N confere os pedidos a cada minuto e também sincroniza
sozinho de tempos em tempos (padrão: a cada 60 min a Zig, a cada 15 min o controle de acesso). Toda madrugada (05:30) ele
recalcula o ponto e gera as tarefas do dia.

Você vai precisar de contas em: **Supabase** (banco), **Vercel** (site), um **N8N** (de preferência instalado num computador na
loja, ou com VPN até ela), o **token da API da Zig** e acesso de administrador aos **equipamentos Control iD**.

---

## 3. Instalação passo a passo

### 3.1 Supabase (banco de dados e login)
1. Crie um projeto em <https://supabase.com> (região **São Paulo**). Guarde a senha do banco.
2. Abra **SQL Editor**, cole **todo** o conteúdo de [`supabase/instalar.sql`](supabase/instalar.sql) e clique **Run**.
   - Para atualizar uma versão nova no futuro, rode o arquivo novo do mesmo jeito (não apaga dados).
3. Crie o seu usuário **master**: abra [`supabase/instalacao/criar_master.sql`](supabase/instalacao/criar_master.sql), escolha
   **uma** das opções (a mais simples é a A: troque e-mail, senha e nome), cole no SQL Editor e rode.
4. **Authentication → Providers**: deixe *Email* ligado. Recomendado: **Confirm email** ligado.
   - Quer o botão "Entrar com Google"? Ligue o provedor *Google* (precisa criar as credenciais no Google Cloud — o Supabase
     mostra o passo a passo na própria tela). Se não quiser, use `VITE_LOGIN_GOOGLE=false` no Vercel (passo 3.2).
5. **Authentication → URL Configuration**:
   - *Site URL*: o endereço do site (ex.: `https://meudiadegerente.vercel.app`).
   - *Redirect URLs*: `https://SEU-SITE/redefinir-senha` e `https://SEU-SITE/` (troque `SEU-SITE`).
6. **Authentication → SMTP** (recomendado): configure um e-mail próprio para os e-mails de confirmação e de "Recuperar senha"
   (o envio padrão do Supabase é limitado a poucos e-mails por hora).
7. **Project Settings → API** (ou *API Keys*): anote
   - **Project URL** → vai para o Vercel e para o N8N;
   - chave **anon / publishable** → vai **só** para o Vercel;
   - chave **service_role / secret** → vai **só** para o N8N. **Nunca** coloque a service_role no site, em planilha ou mensagem.
8. Opcional:
   - Fechar o cadastro aberto (só o master cria empresas): no SQL Editor, `update public.configuracao set cadastro_aberto = false where id = 1;`
   - Dados de demonstração: rode no SQL Editor o conteúdo de [`supabase/seed/10_demo_base.sql`](supabase/seed/10_demo_base.sql) e
     depois o de [`supabase/seed/20_demo_operacao.sql`](supabase/seed/20_demo_operacao.sql) (o arquivo
     [`supabase/instalacao/carga_demo.sql`](supabase/instalacao/carga_demo.sql) só explica isso e como remover a demonstração; sozinho
     ele não carrega nada). **Não** use num ambiente com clientes reais (os usuários de demonstração têm senha conhecida).

O depósito de fotos faciais (privado, separado por empresa) já é criado pelo `instalar.sql`.

### 3.2 Vercel (o site)
1. Em <https://vercel.com>, *Add New → Project* e importe este repositório do GitHub. O Vercel lê o `vercel.json` (Vite, `npm run build`, pasta `dist`) — não mude nada.
   - O `vercel.json` envia uma política de segurança (CSP) que só deixa o site falar com `https://*.supabase.co`. Se o seu Supabase
     usar **domínio próprio** (ex.: `api.seudominio.com.br`), acrescente esse endereço em `connect-src` e `img-src` (e `wss://…` em
     `connect-src`) no `vercel.json`, senão o login não funciona.
2. Em *Environment Variables* cadastre:

   | variável | valor |
   |---|---|
   | `VITE_SUPABASE_URL` | Project URL do Supabase (ex.: `https://abcd1234.supabase.co`) |
   | `VITE_SUPABASE_ANON_KEY` | chave **anon / publishable** do Supabase |
   | `VITE_LOGIN_GOOGLE` | `true` para mostrar "Entrar com Google" (exige o provedor ligado no Supabase), `false` para esconder |

3. *Deploy*. Depois, se quiser, ligue um domínio próprio em *Settings → Domains* e **atualize as URLs do passo 3.1-5**.
4. Toda alteração de variável exige um novo *Redeploy*.

### 3.3 N8N (o robô que conversa com a Zig e o Control iD)
**Onde instalar**: num computador ligado o tempo todo **na rede da loja** (mini-PC, servidor) — assim ele alcança o IP dos
equipamentos Control iD. N8N na nuvem só funciona para a Zig, ou com VPN até a loja (ver 3.4).

1. Instale o N8N (Docker é o mais simples):
   ```bash
   docker volume create n8n_dados
   docker run -d --name n8n --restart unless-stopped -p 5678:5678 \
     --env-file /caminho/seguro/n8n.env -v n8n_dados:/home/node/.n8n docker.n8n.io/n8nio/n8n
   ```
2. O arquivo `n8n.env` é uma cópia preenchida de [`n8n/.env.example`](n8n/.env.example) (guarde **fora** do repositório):
   - `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` (do passo 3.1-7);
   - `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (**obrigatório**), `GENERIC_TIMEZONE=America/Sao_Paulo`, `TZ=America/Sao_Paulo`;
   - `N8N_RUNNERS_TASK_TIMEOUT=900` (a importação da Zig leva alguns minutos);
   - `MDG_EMAIL_RELATORIOS` (quem recebe o CSV da comissão e os avisos de erro) e, se precisar, `MDG_EMAIL_REMETENTE`;
   - `ZIG_BASE_URL` pode ficar como está (`https://api.zigcore.com.br/integration`);
   - `MDG_WF_*` ficam em branco por enquanto (passo 4).
3. Abra `http://IP-DO-COMPUTADOR:5678`, crie o usuário dono do N8N.
4. *Workflows → Import from File*, **nesta ordem**, e anote o **id** de cada um (aparece no endereço: `/workflow/<id>`):

   | # | arquivo | ativar? |
   |---|---|---|
   | 1 | `n8n/comum/workflows/erros.json` (Tratador de erros) | não |
   | 2 | `n8n/controlid/workflows/controlid-importar-usuarios.json` | não |
   | 3 | `n8n/controlid/workflows/controlid-importar-batidas.json` | não |
   | 4 | `n8n/controlid/workflows/controlid-exportar-usuarios.json` | não |
   | 5 | `n8n/zig/workflows/zig-importar.json` | não |
   | 6 | `n8n/comum/workflows/exportar-fechamento.json` | não |
   | 7 | `n8n/comum/workflows/sincronizar-agora.json` (a cada 1 min) | **sim** |
   | 8 | `n8n/comum/workflows/agendador.json` (a cada 15 min) | **sim** |
   | 9 | `n8n/comum/workflows/rotina-diaria.json` (05:30) | **sim** |

5. **Ajustes manuais depois de importar** (o N8N não deixa isso vir no arquivo):
   1. No `n8n.env`, preencha com os ids anotados: `MDG_WF_CONTROLID_USUARIOS` (#2), `MDG_WF_CONTROLID_BATIDAS` (#3),
      `MDG_WF_CONTROLID_EXPORTAR` (#4), `MDG_WF_ZIG_IMPORTAR` (#5), `MDG_WF_EXPORTAR_FECHAMENTO` (#6). **Reinicie o N8N**
      (`docker restart n8n`).
   2. Em **cada** workflow: *Settings → Error workflow* = "MDG · Tratador de erros"; confira *Timezone* = America/Sao_Paulo.
   3. Credencial **SMTP** (*Credentials → New → SMTP*) e selecione-a nos nós de e-mail: "Enviar e-mail" (workflow #6) e
      "Avisar por e-mail" (workflow #1).
   4. Ative **na ordem** 7 → 8 → 9.
6. Teste: no site, *Integrações* → "Sincronizar agora". Em até 1 minuto o pedido muda de "Na fila" para "Concluída" e o histórico
   mostra o resultado. Não andou? Veja a seção 6.

Nenhuma senha, token ou chave fica dentro dos workflows: o N8N lê as chaves do Supabase das variáveis de ambiente e a senha dos
equipamentos/token da Zig direto do banco (área que nem o site consegue ler).

### 3.4 Control iD (relógio de ponto e controle de acesso)
1. **Rede**: dê **IP fixo** ao equipamento (reserva de DHCP no roteador). O computador do N8N precisa alcançar esse IP. Se o N8N
   não estiver na loja, use **VPN** (Tailscale/WireGuard ou VPN do roteador). Evite abrir porta do roteador para a internet.
   Teste no computador do N8N: `curl -s -X POST http://IP-DO-EQUIPAMENTO/login.fcgi -H 'Content-Type: application/json' -d '{"login":"admin","password":"SUA_SENHA"}'`
   deve responder `{"session":"…"}` (no REP iDClass use `https://` e `curl -k`).
2. **Troque a senha padrão** (`admin`/`admin`) do equipamento.
3. **Acerte data e hora** do equipamento (de preferência com NTP ligado).
4. No site, como administrador: *Integrações → Nova integração*:
   - Tipo: **Control iD — controle de acesso** (iDFace, iDFlex, iDAccess) ou **Control iD — relógio de ponto (REP)** (iDClass).
   - Nome (ex.: "iDFace porta dos fundos"), modelo, dias retroativos (2 está bom). Frequência automática: o controle de acesso já
     vem com 15 min (o ponto aparece quase na hora); Zig e REP com 1 h.
   - Segredos: URL (`http://192.168.x.x` no acesso, `https://192.168.x.x` no REP), login e senha do equipamento. Depois de
     salvos, aparecem só como "configurado ✓".
   - REP: identificador **CPF** (Portaria 671; só use PIS em relógio antigo).
5. **Sincronizar agora → Funcionários**. Em *Integrações → (o equipamento)* confira os usuários: os que não foram ligados
   automaticamente você liga escolhendo o funcionário. Dica: cadastre no equipamento a **matrícula** igual à do sistema.
6. **Valide o relógio** (só controle de acesso): bata o ponto, por exemplo, às 14:05, sincronize *Batidas* e veja na tela
   *Ponto* se aparece 14:05. Se aparecer 3 horas a mais ou a menos, desmarque/marque "Relógio do equipamento em hora local"
   na integração e sincronize de novo.
7. **Envio ao equipamento** (opcional): na integração, seção "Envio para o equipamento", ligue "Enviar dados para o equipamento" e escolha o que enviar (cartões,
   senha, foto — só iDFace —, horários de acesso) e o que fazer ao desligar alguém (remover ou bloquear). A partir daí, cadastrar,
   alterar ou desligar um funcionário (e sua foto, cartão, senha e horários na aba *Control iD* da ficha) é enviado na próxima
   sincronização; a situação aparece na própria ficha. Foto: JPEG, rosto de frente, até 1024 px.
   Com horários de acesso: os horários vão primeiro e, logo em seguida (pedido automático, ~1 min), os funcionários que dependiam deles.

### 3.5 Zig (vendas)
1. Peça à Zig (suporte/gerente de conta) o **token da API de integração** e o **id da sua rede**.
2. No site, como administrador: *Integrações → Nova integração → Zig*: id da rede, dias retroativos (2), token nos segredos.
3. **Sincronizar agora**. Em seguida, na mesma tela, confira as **lojas** encontradas e desmarque as que não devem entrar.
4. Na ficha de cada garçom (aba **"Nome na Zig"**), preencha o nome exatamente como aparece no ranking da tela *Vendas → Garçons*
   (o sistema sugere os nomes vistos nos últimos 60 dias). É assim que a venda é ligada ao funcionário.

---

## 4. Primeiro uso

1. Entre com o master. Crie a empresa e o primeiro administrador em *Empresas* (ou deixe o cliente se cadastrar em "Criar conta",
   se o cadastro aberto estiver ligado).
2. Como administrador, em *Configurações*: fuso horário, **"Virada do dia"** (padrão 05:00 — uma batida à 01:30 conta no
   dia anterior; para quem começa a trabalhar antes das 05:00, ajuste), **"Retenção do serviço (%)"** da comissão (padrão 20%),
   "Gerar alarme de atraso na entrada" (liga/desliga) e "Janela de batida duplicada" (padrão 2 min).
3. *Usuários*: crie gerentes e usuários de leitura.
4. *Funcionários → Jornadas*: cadastre as escalas (entrada, intervalo, saída por dia da semana; dia sem horário = folga).
5. *Funcionários*: cadastre cada um com **matrícula**, CPF, cargo, **pontos de comissão**, nome na Zig, admissão e a jornada.
6. Cadastre as integrações (3.4 e 3.5) e sincronize.
7. *Banco de horas*: lance o **saldo inicial** de quem já tinha saldo (só administrador).
8. Rotina do dia: o *Painel* mostra faturamento, serviço, alarmes de ponto, quem está presente, tarefas e a situação das
   sincronizações. Em *Ponto*, resolva os alarmes (incluir a batida esquecida com motivo, desconsiderar duplicada, justificar,
   abonar folga/atestado/feriado). Tudo fica registrado com quem fez e quando.
9. Comissão: *Comissões → Novo fechamento* (período e, se quiser, loja). Ajuste participantes, pontos e o serviço pago fora da Zig;
   a prévia mostra os valores na hora. O administrador **fecha**; depois exporte o CSV ou envie por e-mail.

---

## 5. Para o técnico: rodar localmente e testar

Requisitos: Node 22+, Postgres 16 em `/usr/lib/postgresql/16/bin` (ou `MDG_PG_BIN`), `curl`.

```bash
npm ci
npm run local          # Postgres + migrações + dados demo + PostgREST + login falso em http://127.0.0.1:54321 (grava .env.local)
                       # outras portas/banco (dá para ter dois ambientes no ar):
                       # MDG_PORTA_PORTAO=54361 MDG_PORTA_POSTGREST=54363 MDG_LOCAL_BANCO=mdg_outro ferramentas/local/subir.sh
npm run dev            # site em http://127.0.0.1:5173  (usuários demo: gerente@barbossanova.com.br etc., senha gerente123)
npm run n8n:mocks      # Zig e Control iD falsos (portas 54340–54342) para testar com um N8N de verdade
```

| comando | o que confere |
|---|---|
| `npm run typecheck` / `npm run build` | tipos e build do site |
| `npm test` | lógica do site e do N8N (vitest): comissão, ponto, CSV, AFD, Zig, Control iD, workflows no simulador |
| `npm run test:banco` | banco em Postgres 16 descartável: RLS e isolamento entre empresas em todas as tabelas, regras de ponto/banco de horas/comissão, ingestões, auditoria de privilégios |
| `npm run sql:instalar` / `npm run sql:conferir` | regera `supabase/instalar.sql` / confere se está idêntico ao gerado das migrações (`ferramentas/gerar-instalar.sh --verificar` instala num banco limpo) |
| `npm run n8n:verificar` | estrutura dos 9 workflows, cópias das bibliotecas, nenhuma credencial no JSON |
| `node --test "n8n/**/*.test.mjs"` | testes do N8N com o executor do Node |
| `npm run test:integracao` | com `npm run local` no ar: roda os workflows de verdade contra o banco local e os mocks (Zig + Control iD ponta a ponta), incluindo o cenário com valores calculados à mão (`n8n/cenario-revisao2.test.mjs`: AFD com virada, alarme, banco de horas, ranking, comissão, importações simultâneas) |
| `npm run test:fuzz` | testes de propriedade banco × front (comissão e apuração de ponto, centenas de casos aleatórios); usa o banco de `MDG_PG_BANCO` (padrão `mdg_local`, ou seja, rode `npm run local` antes) |
| `npm run test:e2e` | Playwright (celular 390 px e computador 1440 px). Com outro Vite já no ar: `E2E_URL=http://127.0.0.1:PORTA npx playwright test` |

Pastas: `web/` (site), `supabase/` (banco: migrações, testes, instalação), `n8n/` (workflows, bibliotecas, mocks), `e2e/`,
`ferramentas/` (ambiente local, gerador do instalador), `docs/` (contrato técnico e relatórios de revisão).

---

## 6. Problemas comuns

| sintoma | o que fazer |
|---|---|
| Pedido de sincronização fica "Na fila" | O workflow "Sincronizar agora (fila)" está desativado ou o N8N está parado. |
| Erro "Variável MDG_WF_… não configurada" | Preencha o id do subfluxo no `n8n.env` e reinicie o N8N (3.3-5). |
| "endereço inalcançável (rede/VPN?)" / "conexão recusada" | O N8N não alcança o equipamento: IP mudou, equipamento desligado, VPN caída. |
| "Login recusado pelo equipamento" | Login/senha errados nos segredos da integração. |
| Batidas com 3 h de diferença | Ajuste "Relógio do equipamento em hora local" (3.4-6). |
| Zig `HTTP 401` | Token da Zig errado. `parcial` com `429` = limite da Zig; a próxima rodada completa sozinha. |
| Não chega o e-mail de recuperar senha | Configure o SMTP do Supabase (3.1-6) e confira as Redirect URLs (3.1-5). |
| Ao abrir o CSV no Excel um nome aparece com `'` na frente (ex.: `'=Fulano`) | Proteção contra fórmulas maliciosas: textos que começam com `=`, `+`, `-` ou `@` ganham um apóstrofo. É esperado. |
| Funcionário não aparece ligado ao usuário do equipamento | Confira matrícula/CPF; ou ligue à mão na tela da integração. "Desvinculado manualmente" não é religado sozinho. |

---

## 7. Segurança e privacidade

- Cada empresa só enxerga os próprios dados (regras no próprio banco, testadas em todas as tabelas).
- Token da Zig, senhas dos equipamentos, senha (PIN) e número completo dos cartões dos funcionários **não podem ser lidos pelo
  site** — só gravados. A tela mostra apenas "configurado ✓" e os 4 últimos dígitos do cartão.
- Fotos faciais ficam num depósito **privado**, separado por empresa.
- Da Zig não guardamos dados pessoais de clientes (nome, documento, telefone, e-mail dos compradores são descartados).
- A chave `service_role` do Supabase só existe no N8N.
- O site envia cabeçalhos de segurança (CSP, `X-Frame-Options`, `nosniff`) e os CSV exportados neutralizam fórmulas de planilha.
- **Cadastro aberto**: por padrão qualquer pessoa pode criar uma conta e uma empresa vazia ("Criar conta"). Se só você vai criar as
  empresas, feche (3.1-8). Se deixar aberto, mantenha **Confirm email** ligado no Supabase.
