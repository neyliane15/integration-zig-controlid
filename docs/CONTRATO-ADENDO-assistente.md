# Adendo — Assistente de IA (A)

## A.1 O que é

O assistente é um botão "Assistente" que aparece em todas as telas do site para gerente, administrador e master. Ele abre
um painel de conversa (`web/src/componentes/dominio/Assistente.tsx`). O gerente pergunta em português, por exemplo "quem
menos atrasou em novembro?" ou "qual dia mais vendeu em outubro?", e recebe uma resposta curta feita a partir dos dados do
sistema. O assistente só consulta: nunca altera nada.

## A.2 Fluxo

1. O site faz `POST {VITE_ASSISTENTE_URL}` para o webhook `mdg-assistente` do workflow **"MDG · Assistente"** no n8n
   (`n8n/assistente/workflows/assistente.json`, pacote `12-assistente.json`, deixado ativo).
   - Cabeçalhos: `Authorization: Bearer <JWT do usuário>` e `apikey: <chave anon>`.
   - Corpo: `{pergunta, empresa_id, historico[≤12 {papel, texto}], contexto {empresa_nome, hoje, dia_semana}}`.
2. O nó Code (`n8n/assistente/lib/assistente.mjs`) faz o seguinte:
   - valida o login em `GET /auth/v1/user`;
   - roda o laço de ferramentas da Messages API com `claude-opus-5-5` (`effort: "medium"`, `fallbacks: "default"`,
     prompt de sistema e ferramentas fixos com `cache_control` automático, no máximo 8 rodadas);
   - executa cada ferramenta com o **login de quem pergunta**: chave anon + JWT na API REST do Supabase. RLS e as
     checagens `pode_*` valem exatamente como no site.
3. A resposta tem o formato `{resposta, ferramentas[], uso{entrada, saida, cache_lido, cache_criado}, rodadas}`, ou
   `{erro}` com o status HTTP do problema (400, 401, 502 ou 503).

O workflow não salva execuções (`saveData*: none`), porque o pedido traz o token do usuário.

## A.3 Ferramentas

| Ferramenta | Consulta |
|---|---|
| `vendas_resumo` | `vendas_resumo` |
| `vendas_por_dia` | `vendas_faturamento_por_dia` |
| `vendas_por_garcom` | `vendas_por_garcom` |
| `vendas_por_forma_pagamento` | `vendas_faturamento_por_forma` |
| `ponto_por_funcionario` | `assistente_ponto_resumo` (nova, G A M) |
| `faltas_e_atrasos` | `ocorrencias_ponto` |
| `banco_de_horas` | `banco_horas_resumo` |
| `escala_do_dia` | `assistente_escala_dia` (nova, G A M L) |
| `reservas` | `reservas_listar` (sem telefone nem e-mail) |
| `funcionarios` | tabela `funcionarios` (sem CPF) |

- Os valores em centavos são convertidos para reais antes de chegar ao modelo.
- Listas com mais de 400 linhas são cortadas, com um aviso.

## A.4 Configuração

- **n8n:** `ANTHROPIC_API_KEY` no ambiente. Sem ela, o webhook responde 503 com a mensagem de que falta a chave.
- **Front:** `VITE_ASSISTENTE_URL` é opcional. O padrão é o n8n da Hostinger.
- **CORS:** a opção `allowedOrigins: *` do webhook.
