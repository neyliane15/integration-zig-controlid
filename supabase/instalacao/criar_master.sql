-- =====================================================================================================
-- Criar o usuário MASTER (dono da plataforma). Rode no SQL Editor do Supabase DEPOIS de supabase/instalar.sql.
-- Escolha UMA das opções abaixo, troque os valores e rode só ela.
-- =====================================================================================================

-- Opção A — criar o master já com senha (e-mail confirmado):
-- select public.admin_criar_usuario('voce@seudominio.com.br', 'troque-esta-senha', 'Seu Nome', 'master', null);

-- Opção B — a conta já existe (cadastrou-se pela tela ou pelo Google): promover a master:
-- select public.tornar_master('voce@seudominio.com.br');

-- Opção C — quem se cadastrar com este e-mail vira master (vale enquanto não houver master):
-- update public.configuracao set master_email = 'voce@seudominio.com.br' where id = 1;

-- Opcional — fechar o cadastro aberto de novas empresas (só o master cria empresas):
-- update public.configuracao set cadastro_aberto = false where id = 1;

-- Conferir:
select p.email, p.papel, p.ativo from public.perfis p where p.papel = 'master';
