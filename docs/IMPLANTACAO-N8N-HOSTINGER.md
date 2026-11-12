# Implantação do N8N na VPS da Hostinger — passo a passo

Guia para quem **não é técnico**. Ao final, o N8N da sua VPS vai: buscar as vendas na **Zig**, as batidas e os funcionários nos
equipamentos **Control iD** da loja, as reservas da **Tagme** (quando houver acesso), apurar o ponto e mandar o CSV da comissão por
e-mail — gravando tudo no Supabase do sistema.

> Onde aparecer `ASSIM`, troque pelo seu valor. Onde a tela da Hostinger/Tailscale/N8N puder ser diferente da descrita (elas mudam
> com o tempo), o guia diz **o que procurar** em vez de prometer o nome exato do botão.

**O que você vai precisar ter em mãos**

| item | onde conseguir |
|---|---|
| acesso à VPS (SSH como `root`) | hPanel da Hostinger → VPS → *Visão geral*: IP e senha de root; ou o **Terminal do navegador** do próprio hPanel |
| endereço do N8N (ex.: `https://n8n.seudominio.com.br`) | o que você configurou ao instalar o template "n8n" |
| URL e chave **service_role** do Supabase | Supabase → *Project Settings → API* (`service_role` / *secret key*) |
| um e-mail que envie mensagens (SMTP) | seu provedor de e-mail (Hostinger Mail, Google Workspace, etc.) |
| um computador **sempre ligado** na loja (Windows serve) | para o Control iD (§4) |
| token e id da rede da **Zig** | suporte/gerente de conta da Zig |
| a pasta `n8n/pacote/` deste repositório | já vem pronta: workflows numerados + modelo de variáveis |

---

## 1. Entenda o desenho (1 minuto)

```
  Zig (internet) ───────────┐
  Tagme (internet) ─────────┤
                            ▼
                  VPS Hostinger: N8N ──────► Supabase (banco do sistema)
                            │
                            │  túnel Tailscale (§4)
                            ▼
          computador da loja (sempre ligado) ──► Control iD (IP 192.168.x.x da loja)
```

A VPS está na internet; os equipamentos Control iD estão na rede **interna** da loja. A VPS **não enxerga** essa rede sozinha —
por isso o §4 cria um túnel seguro (Tailscale). Zig e Tagme são serviços de internet: funcionam direto.

---

## 2. Achar onde o N8N está instalado na VPS

O template "n8n" da Hostinger instala o N8N em **Docker Compose**: há um arquivo `docker-compose.yml` e, normalmente, um `.env`
na mesma pasta (costuma ser `/root` ou `/docker/n8n`, mas varia com a versão do template).

1. Entre na VPS: no hPanel, abra o **terminal do navegador** (procure "Terminal" / "Browser terminal" na página da VPS) ou, no seu
   computador, `ssh root@IP-DA-VPS`.
2. Descubra o nome do container e a pasta do Compose:
   ```bash
   docker ps --format '{{.Names}}\t{{.Image}}'
   # anote o nome da linha cuja imagem contém "n8n" (ex.: root-n8n-1, n8n-n8n-1 ou n8n)
   docker inspect NOME-DO-CONTAINER --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'
   # → mostra a pasta (ex.: /root). É nela que estão docker-compose.yml e .env
   ```
   Se o segundo comando vier vazio: `find / -name docker-compose.yml -not -path '*/proc/*' 2>/dev/null`.
3. Entre na pasta e faça **cópia de segurança** antes de mexer:
   ```bash
   cd /root            # a pasta que apareceu acima
   cp docker-compose.yml docker-compose.yml.bak
   cp .env .env.bak 2>/dev/null || true
   ```

> Se o hPanel tiver um gerenciador de Docker ("Docker Manager" ou parecido) que mostra e edita o Compose, pode usá-lo no lugar do
> terminal — o efeito é o mesmo. O importante é que as variáveis do §3 cheguem **ao container do n8n**.

---

## 3. Variáveis de ambiente

### 3.1 Criar o arquivo de variáveis do sistema

Use o modelo [`n8n/pacote/env.hostinger.exemplo`](../n8n/pacote/env.hostinger.exemplo) (não tem segredo nenhum). Na pasta do
Compose:

```bash
nano mdg.env        # cole o conteúdo do modelo e preencha; Ctrl+O, Enter, Ctrl+X para salvar
chmod 600 mdg.env   # só o root lê
```

| variável | o que pôr | obrigatória? |
|---|---|---|
| `SUPABASE_URL` | `https://SEU-PROJETO.supabase.co` | sim |
| `SUPABASE_SERVICE_ROLE_KEY` | a chave **service_role** (nunca a *anon*; nunca no site; nunca num nó do N8N) | sim |
| `MDG_WF_CONTROLID_USUARIOS`, `MDG_WF_CONTROLID_BATIDAS`, `MDG_WF_CONTROLID_EXPORTAR`, `MDG_WF_ZIG_IMPORTAR`, `MDG_WF_TAGME_IMPORTAR`, `MDG_WF_EXPORTAR_FECHAMENTO` | ids dos subfluxos — **deixe em branco agora**, preencha no §5.3 | sim (depois) |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | `false` — sem isso os workflows não conseguem ler as variáveis | sim |
| `GENERIC_TIMEZONE`, `TZ` | `America/Sao_Paulo` (a Rotina diária roda às 05:30 deste fuso) | sim |
| `N8N_RUNNERS_TASK_TIMEOUT` | `900` — a importação da Zig leva minutos (o padrão de 60 s corta no meio) | sim |
| `EXECUTIONS_TIMEOUT` | `-1` (sem limite geral) | recomendado |
| `ZIG_BASE_URL` | `https://api.zigcore.com.br/integration` (já vem) | não |
| `TAGME_BASE_URL` | vazio, ou o endereço base da Tagme se ela informar um (ver §7) | não |
| `MDG_EMAIL_RELATORIOS` | quem recebe o CSV da comissão e os avisos de erro | sim, para a exportação |
| `MDG_EMAIL_REMETENTE` | remetente aceito pelo seu SMTP (vazio = o mesmo de cima) | não |

> **Atenção com o `.env` do template**: ele já tem variáveis da própria Hostinger (domínio, e-mail do SSL, fuso…). **Não apague**.
> Se ele já tiver `GENERIC_TIMEZONE`, deixe igual a `America/Sao_Paulo`.

### 3.2 Fazer o container enxergar o arquivo

Abra o Compose (`nano docker-compose.yml`) e, **dentro do serviço do n8n** (o bloco que tem `image: ...n8n...`), acrescente
`env_file` alinhado com `image:`:

```yaml
services:
  n8n:                      # o nome pode ser outro; é o bloco da imagem n8n
    image: docker.n8n.io/n8nio/n8n
    # ... (o que já existe fica como está)
    env_file:
      - ./mdg.env
```

Se o bloco já tiver um `env_file:`, só acrescente a linha `- ./mdg.env` nele. Salve e aplique:

```bash
docker compose up -d          # (em versões antigas: docker-compose up -d)
docker exec NOME-DO-CONTAINER printenv | grep -E 'SUPABASE_URL|MDG_|N8N_BLOCK|RUNNERS'
```

O segundo comando deve listar as variáveis (a chave aparece — não tire print dela). **Toda vez que mudar `mdg.env`, rode
`docker compose up -d` de novo** (é o "reiniciar" do N8N).

### 3.3 Sem acesso às variáveis (N8N Cloud ou painel gerenciado)

Se o seu N8N não deixa definir variáveis de ambiente (N8N Cloud, por exemplo), cadastre as **mesmas chaves e valores** em
*Settings/Configurações → Variables* do N8N (recurso de alguns planos). Os nós Code dos workflows leem `$env` e, se não houver,
`$vars`. **Limitação**: os workflows do Control iD também usam `$env` em nós HTTP — eles só funcionam com variáveis de ambiente de
verdade (self-hosted, como a VPS deste guia). Na VPS Hostinger, use sempre o §3.1–3.2.

---

## 4. Control iD: ligar a VPS à rede da loja com Tailscale (recomendado)

O Tailscale cria uma rede privada criptografada entre a VPS e um computador da loja. Esse computador "anuncia" a rede da loja
(*subnet router*), e a VPS passa a alcançar `http://192.168.x.x` dos equipamentos — sem abrir porta no roteador. É gratuito para
uso pequeno.

### 4.1 Descobrir a sub-rede da loja

No computador da loja (Windows), abra o *Prompt de Comando* e rode `ipconfig`. Veja o "Endereço IPv4" (ex.: `192.168.0.25`) e a
"Máscara" (normalmente `255.255.255.0`). Com máscara `255.255.255.0`, a sub-rede é o IP com o último número trocado por `0/24`:
`192.168.0.0/24`. Anote também o **IP de cada Control iD** (aparece no menu de rede do próprio equipamento) — de preferência fixo
(peça ao técnico de rede para reservar o IP no roteador).

### 4.2 Criar a conta e instalar no computador da loja (Windows)

1. Crie uma conta em `tailscale.com` (pode usar a conta Google/Microsoft da empresa). Use **a mesma conta** em todos os passos.
2. No computador da loja, baixe e instale o Tailscale para Windows, faça login.
3. Para ele continuar conectado mesmo sem ninguém logado no Windows: no ícone do Tailscale (perto do relógio), procure a opção
   **"Run unattended"** (executar sem usuário) e ative. Configure o Windows para **não suspender/hibernar**.
4. Anuncie a rede da loja. Abra o **PowerShell como administrador** e rode (trocando a sub-rede):
   ```powershell
   tailscale up --advertise-routes=192.168.0.0/24 --unattended
   ```
   (Se o comando reclamar de outras opções já usadas antes, ele mesmo mostra a linha completa a repetir — copie e acrescente
   `--advertise-routes=...`.)

> Alternativa mais robusta que um PC Windows: um mini-PC/Raspberry Pi com Linux na loja. Lá: instale como no §4.4, ative o
> encaminhamento (`echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf && sudo sysctl -p /etc/sysctl.d/99-tailscale.conf`)
> e rode `sudo tailscale up --advertise-routes=192.168.0.0/24`.

### 4.3 Aprovar a rota no painel do Tailscale

No painel web do Tailscale (*admin console* → **Machines**), abra o computador da loja → procure **"Edit route settings…"**
(editar rotas) → marque `192.168.0.0/24` → salvar. Sem essa aprovação a rota não vale.

Aproveite e, para **as duas máquinas** (loja e VPS), use **"Disable key expiry"** (desativar expiração da chave) — senão o túnel cai
sozinho depois de alguns meses.

### 4.4 Instalar o Tailscale na VPS (Ubuntu)

No terminal da VPS:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --accept-routes
# abre um link de login: copie para o navegador e entre com a MESMA conta
tailscale status            # deve listar o computador da loja
ping -c 3 192.168.0.50      # IP de um Control iD (alguns equipamentos não respondem ping — tudo bem; teste o passo 4.5)
```

`--accept-routes` é o que faz a VPS usar a rota anunciada pela loja. **Cuidado**: se a própria VPS já usar uma faixa igual à da loja
(raro na Hostinger), as redes conflitam — fale com o técnico.

### 4.5 Garantir que o container do N8N alcança o equipamento

O jeito **mais simples e confiável**: Tailscale instalado **no host** (a VPS, passo 4.4) com `--accept-routes`, e o container do N8N
na rede padrão do Docker. O tráfego que sai do container passa pelo host e segue a rota do Tailscale — não é preciso mudar o Compose.

Teste **de dentro do container** (troque o IP, o usuário e a senha do equipamento):

```bash
docker exec NOME-DO-CONTAINER node -e "fetch('http://192.168.0.50/login.fcgi',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({login:'admin',password:'SENHA'})}).then(r=>r.text()).then(t=>console.log('OK',t),e=>console.log('FALHOU',e.cause||e))"
```

- `OK {"session":"..."}` → funcionando.
- `OK {"error":...}` / 401 → o equipamento respondeu (rede OK), mas usuário/senha estão errados.
- `FALHOU ... ETIMEDOUT/EHOSTUNREACH` → a rota não chegou ao container. Confira, na ordem:
  1. `tailscale status` na VPS mostra a loja online? A rota foi aprovada (§4.3)? O PC da loja está ligado?
  2. Do **host** funciona? `curl -m 5 -X POST -H 'content-type: application/json' -d '{"login":"admin","password":"SENHA"}' http://192.168.0.50/login.fcgi`
     — se do host funciona e do container não, rode `sysctl net.ipv4.ip_forward` (deve ser `1`; o Docker liga) e reinicie o Docker
     (`systemctl restart docker && docker compose up -d`).
  3. Último recurso: rodar o Tailscale como *sidecar* (um container `tailscale/tailscale` com `TS_ACCEPT_ROUTES=true`, e o n8n com
     `network_mode: service:tailscale`). Isso mexe na rede do template da Hostinger (proxy/HTTPS) — peça a um técnico.

(Também dá para testar com `curl`, se a imagem do seu N8N tiver: `docker exec NOME-DO-CONTAINER curl -m 5 http://192.168.0.50/login.fcgi`.
A imagem oficial nem sempre tem `curl`; o teste com `node` acima sempre funciona.)

### 4.6 Cadastrar o equipamento no sistema

No site do sistema → **Integrações** → *Nova integração* → Control iD (acesso ou REP) → URL `http://192.168.0.50` (o IP **da loja**,
não o da VPS), login e senha do equipamento. Salve e use **Sincronizar agora**. Detalhes do Control iD: `README.md` §3.4.

### 4.7 Alternativa: redirecionamento de porta (não recomendado)

Abrir no roteador da loja uma porta externa → `192.168.0.50:80` e cadastrar a URL `http://IP-PUBLICO-DA-LOJA:PORTA`. Riscos:

- o equipamento fica **exposto na internet** e a interface dele trafega usuário/senha **sem criptografia** (HTTP);
- muitas operadoras usam **CGNAT** (o IP do roteador não é público): aí o redirecionamento simplesmente não funciona;
- o IP da loja muda (precisa de IP fixo ou DNS dinâmico).

Se ainda assim for usar: **troque a senha `admin`** do equipamento por uma forte, libere a porta **só para o IP da VPS** (se o
roteador permitir filtro por origem), use uma porta alta (ex.: 18080) e revise o acesso periodicamente.

---

## 5. Importar os workflows

### 5.1 Importar na ordem

Baixe a pasta `n8n/pacote/workflows/` (são os mesmos JSON dos originais, só numerados; o `npm run n8n:verificar` garante que estão
idênticos). No N8N: *Workflows* → menu (⋯ / "+") → **Import from File** (*Importar de arquivo*), um por vez, **nesta ordem**:

| # | arquivo | nome no N8N | vai para a variável | ativar? |
|---|---|---|---|---|
| 01 | `01-erros.json` | MDG · Tratador de erros | — | não precisa |
| 02 | `02-controlid-importar-usuarios.json` | MDG · Control iD · Importar usuários | `MDG_WF_CONTROLID_USUARIOS` | não |
| 03 | `03-controlid-importar-batidas.json` | MDG · Control iD · Importar batidas | `MDG_WF_CONTROLID_BATIDAS` | não |
| 04 | `04-controlid-exportar-usuarios.json` | MDG · Control iD · Exportar funcionários | `MDG_WF_CONTROLID_EXPORTAR` | não |
| 05 | `05-zig-importar.json` | MDG · Zig · Importar | `MDG_WF_ZIG_IMPORTAR` | não |
| 06 | `06-tagme-importar.json` | MDG · Tagme · Importar | `MDG_WF_TAGME_IMPORTAR` | não |
| 07 | `07-exportar-fechamento.json` | MDG · Exportar fechamento CSV | `MDG_WF_EXPORTAR_FECHAMENTO` | não |
| 08 | `08-sincronizar-agora.json` | MDG · Sincronizar agora (fila) — a cada 1 min | — | **sim** |
| 09 | `09-agendador.json` | MDG · Agendador — a cada 15 min | — | **sim** |
| 10 | `10-rotina-diaria.json` | MDG · Rotina diária — 05:30 | — | **sim** |

Salve cada um depois de importar. **Não ative nada ainda.**

### 5.2 Pegar os ids

Abra cada subfluxo (02 a 07). O endereço no navegador termina em `/workflow/XXXXXXXX` — esse `XXXXXXXX` é o id.

### 5.3 Preencher e reiniciar

Cole cada id na variável correspondente em `mdg.env` (tabela acima) e rode `docker compose up -d`. Confira com
`docker exec NOME-DO-CONTAINER printenv | grep MDG_WF`.

### 5.4 Tratador de erros, fuso e e-mail

1. Em **cada** workflow (01 a 10): *Settings/Configurações do workflow* → **Error workflow** = "MDG · Tratador de erros"; confira
   *Timezone* = America/Sao_Paulo (já vem no arquivo). Salve.
2. **SMTP**: abra o nó **"Enviar e-mail"** (workflow 07) e o nó **"Avisar por e-mail"** (workflow 01) → em *Credential*, crie uma
   credencial SMTP (servidor, porta, usuário, senha do seu e-mail; a Hostinger Mail, por exemplo, informa esses dados no painel de
   e-mail) e use a mesma nos dois. Salve.

### 5.5 Testar e ativar

1. No site do sistema, faça um pedido de sincronização (tela **Integrações** → *Sincronizar agora*).
2. No N8N, abra "MDG · Sincronizar agora (fila)" e clique em **Test workflow / Executar**. Veja se o pedido no site muda para
   concluído (ou mostra o erro com a explicação).
3. Ative **nesta ordem**: 08 (fila) → 09 (agendador) → 10 (rotina diária). Os demais **não** precisam ficar ativos (são chamados
   pelos de cima).

---

## 6. Zig

1. Peça à Zig o **token de integração (ERP)** e o **id da rede**.
2. No site do sistema → **Integrações** → *Nova integração* → **Zig**: preencha "Id da rede na Zig"; em **Credenciais**, cole o
   "Token da Zig". Salve. (O token fica guardado só para o N8N; o site não mostra de volta.)
3. Clique em **Sincronizar agora** no cartão da Zig. Em até 1–2 minutos o histórico deve mostrar "sucesso" com lojas e dias
   importados. Depois, em *Lojas*, desmarque as que não devem entrar.
4. Erros comuns: `HTTP 401` = token errado; `parcial` com `HTTP 429` = limite da Zig (o próximo ciclo reimporta, sem duplicar);
   `Task request timed out` = falta `N8N_RUNNERS_TASK_TIMEOUT=900` (§3).

---

## 7. Tagme (reservas)

A Tagme **não tem API pública** — só libera para **parceiros**, sob contrato. O sistema já está pronto: o workflow
"MDG · Tagme · Importar" lê **qualquer** endpoint de reservas que devolva JSON, e tudo (endereço, autenticação, nomes dos campos) é
configurado na integração, **sem mexer em código**. Enquanto não houver acesso, use a importação de CSV (§7.4).

### 7.1 Caminho oficial: pedir acesso de parceiro (recomendado)

Escreva ao suporte/comercial da Tagme pedindo acesso de **integração/parceiro** para o seu restaurante. Peça especificamente:

- um **endpoint de reservas por período** (data inicial e final) ou por dia, em JSON, do restaurante (id do restaurante/unidade);
- a **forma de autenticação** (token de API, *client id/secret*, cabeçalho usado) e por quanto tempo a credencial vale;
- a **lista de campos** de cada reserva: id, data e hora, nome, telefone, e-mail, nº de pessoas, **status** (e a lista de status
  possíveis: confirmada, cancelada, sentada, no-show…), área/salão, mesa, observação;
- se há **paginação** (nome dos parâmetros e tamanho máximo) e **limite de chamadas** por minuto;
- um **exemplo de resposta** (com dados fictícios).

Com isso, o técnico preenche a integração (§7.3).

### 7.2 Enquanto isso: descobrir o endpoint que o painel usa (não oficial)

O painel que vocês usam (`https://waitlist.tagme.com.br/admin/reservations`) busca a lista de reservas num endereço interno.
Dá para descobri-lo pelo navegador e passar ao técnico:

1. No computador, abra o painel **logado**, na página de reservas.
2. Aperte **F12** (Ferramentas do desenvolvedor) → aba **Network/Rede** → filtro **Fetch/XHR**.
3. Recarregue a página (F5) e, se preciso, mude a data no painel.
4. Procure na lista a requisição cuja **resposta** (aba *Response/Resposta* ou *Preview/Visualização*) é a lista de reservas em JSON.
5. Anote: a **URL** (sem a parte de token, se houver), o **método** (GET/POST), os **parâmetros de data** (nome e formato, ex.:
   `start_date=2026-11-12`), o **caminho da lista** dentro do JSON (ex.: `data.reservations`) e os **nomes dos campos** de **um**
   item (id, data/hora, nome, pessoas, status…). Anote também **qual cabeçalho** autentica (ex.: `Authorization: Bearer …` ou
   `Cookie`), **sem copiar o valor**.
6. Passe **só isso** ao técnico. **Nunca envie token, cookie ou senha** por e-mail/WhatsApp; o valor é colado por você diretamente
   no campo **Credenciais → Token** da integração.

> **Atenção**: usar o endereço interno do painel **não é oficial**, pode **mudar sem aviso** (a sincronização para de funcionar),
> o cookie/token de sessão **expira** (precisa ser colado de novo) e o uso depende dos **termos de uso da Tagme** — confira antes. O
> caminho certo continua sendo o acesso de parceiro (§7.1). Os dados de clientes (nome, telefone, e-mail) são pessoais (LGPD): o
> sistema só guarda o necessário e esconde telefone/e-mail de quem só tem leitura.

### 7.3 Preencher a integração (técnico)

No site → **Integrações** → *Nova integração* → **Tagme**:

- **Endereço da API** (`url_base`): ex. `https://waitlist.tagme.com.br` (ou o informado pela Tagme);
- **Id do restaurante** (`restaurante_id`), **dias para trás** (`dias_retroativos`, padrão 1) e **dias à frente** (`dias_a_frente`,
  padrão 7) — a janela importada é `[hoje − dias para trás, hoje + dias à frente]`;
- **Credenciais**: `token` (o valor do token, ou o cookie inteiro `nome=valor` no caso do painel); `cliente_id`/`cliente_segredo`
  se a Tagme usar esse par;
- **Avançado (JSON)** — o que o N8N precisa saber do endpoint. Exemplo completo (todos os campos são opcionais e têm padrão):

```json
{
  "caminho": "/api/v1/restaurants/{restaurante_id}/reservations",
  "metodo": "GET",
  "autenticacao": { "cabecalho": "Authorization", "prefixo": "Bearer" },
  "consulta": { "modo": "periodo", "param_inicio": "start_date", "param_fim": "end_date", "formato_data": "AAAA-MM-DD" },
  "paginacao": { "param_pagina": "page", "param_tamanho": "per_page", "tamanho": 100, "caminho_total_paginas": "meta.total_pages" },
  "mapeamento": {
    "lista": "data.reservations",
    "id": "_id", "data_hora": "scheduled_at", "nome": "customer.name", "telefone": "customer.phone", "email": "customer.email",
    "pessoas": "party_size", "status": "status", "area": "area.name", "mesa": "table.name", "observacao": "notes",
    "status_map": { "WAITING": "pendente", "SEATED": "sentada" }
  }
}
```

| chave | para quê | valores |
|---|---|---|
| `caminho` | endereço do endpoint (soma-se a `url_base`; pode ser a URL inteira). `{restaurante_id}` é trocado pelo id | — |
| `metodo` | `GET` (parâmetros na URL) ou `POST` (no corpo JSON) | padrão `GET` |
| `autenticacao` | **em qual cabeçalho** vai o segredo `token` e com que prefixo. Sessão do painel: `{"cabecalho":"Cookie","prefixo":""}`; chave simples: `{"cabecalho":"x-api-key","prefixo":""}`; par cliente: `{"modo":"basic"}` | padrão `Authorization: Bearer <token>` |
| `consulta` | nome e formato das datas: `modo` `periodo` (início+fim) ou `dia` (`param_dia`, uma chamada por dia); `formato_data` `AAAA-MM-DD`, `DD/MM/AAAA`, `AAAAMMDD`, `iso`, `epoch`, `epoch_ms`; `param_restaurante` (manda o id como parâmetro); `extras` (parâmetros fixos) | padrão `start_date`/`end_date`, `AAAA-MM-DD` |
| `paginacao` | só se a lista vier em páginas | sem = uma chamada |
| `mapeamento` | `lista` = onde está a lista no JSON (ex.: `data.reservations`); demais = caminho de cada campo num item (`a.b.c`; aceita lista de alternativas). `data_hora` serve quando data e hora vêm juntas; `status_map` traduz status da Tagme para `confirmada`, `pendente`, `cancelada`, `sentada`, `concluida`, `nao_compareceu` | padrão: nomes comuns em inglês/português |

Salve e clique em **Sincronizar agora**. O histórico mostra quantas reservas foram lidas/gravadas. Mensagens comuns:

- `Endpoint de reservas da Tagme não configurado` → falta `caminho` no Avançado;
- `HTTP 401/403` → token/cookie errado ou expirado (cole de novo);
- `Resposta da Tagme não é JSON` → sessão expirou (o painel devolveu a página de login) ou endereço errado;
- `Resposta da Tagme sem a lista de reservas em "…"` → ajuste `mapeamento.lista`;
- `Nenhuma das N reservas recebidas tem id e data reconhecíveis … (campos de um item: …)` → ajuste o `mapeamento` usando os nomes
  listados. Nesse caso **nada é apagado** no sistema.

Cada sincronização **substitui a janela**: reservas da Tagme que sumiram do lado de lá (ex.: excluídas) saem do sistema;
reimportar não duplica.

### 7.4 Sem API: importar CSV

Se o painel da Tagme tiver botão de **exportar** (CSV/Excel), exporte as reservas do período e importe no sistema em
**Reservas → Importar CSV** (o sistema mostra o modelo de colunas: `Data;Horário;Nome;Pessoas;Telefone;E-mail;Status;Área;Mesa;Observação;Código`).
Planilha do Excel: salve como "CSV (separado por ponto e vírgula)". Reservas também podem ser lançadas à mão na mesma tela.

---

## 8. Checklist final

- [ ] `docker exec NOME-DO-CONTAINER printenv` mostra `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, os 6 `MDG_WF_*` preenchidos,
      `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`, `GENERIC_TIMEZONE`/`TZ=America/Sao_Paulo`, `N8N_RUNNERS_TASK_TIMEOUT=900`, `MDG_EMAIL_RELATORIOS`.
- [ ] Os 10 workflows importados, com os nomes "MDG · …"; *Error workflow* = "MDG · Tratador de erros" em todos.
- [ ] Credencial SMTP nos nós "Enviar e-mail" (07) e "Avisar por e-mail" (01).
- [ ] 08, 09 e 10 **ativos**; 01–07 inativos (normal).
- [ ] `tailscale status` na VPS mostra a loja; rota da sub-rede aprovada; expiração de chave desativada nas duas máquinas.
- [ ] Teste do §4.5 de dentro do container devolve `OK {"session":…}` para cada equipamento.
- [ ] Integrações → Zig: *Sincronizar agora* → sucesso; vendas de ontem aparecem no painel.
- [ ] Integrações → Control iD: *Sincronizar agora* → usuários e batidas importados; funcionários ligados aos usuários.
- [ ] Integrações → Tagme (se configurada): *Sincronizar agora* → reservas lidas; ou CSV importado em Reservas.
- [ ] Comissões → exportar um fechamento → o e-mail com o CSV chega em `MDG_EMAIL_RELATORIOS`.
- [ ] No dia seguinte: o histórico mostra a **Rotina diária** (05:30) e o **Agendador** rodando sozinhos.
- [ ] Faça um erro de propósito (ex.: senha errada num equipamento) e veja o aviso por e-mail chegar.

Problemas comuns do N8N: `n8n/README.md` §8.

---

### Para o técnico

- Fonte dos workflows: `n8n/**/workflows/*.json`; o pacote `n8n/pacote/` é gerado por `node n8n/pacote/gerar.mjs` (também
  regenerado por `node n8n/verificar.mjs --atualizar`) e conferido por `npm run n8n:verificar`.
- Mock da Tagme para testar a configuração sem conta: `npm run n8n:mocks` → `http://127.0.0.1:54343/api/v1/reservations`
  (`Authorization: Bearer tagme-token-mock`; formato **inventado**, só para exercitar o mapeamento). Testes: `node --test n8n/tagme/lib/tagme.test.mjs`.
- Código da importação: `n8n/tagme/lib/tagme.mjs` (cabeçalho do arquivo documenta todas as chaves de `parametros`).
