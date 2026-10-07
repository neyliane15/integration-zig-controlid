-- 12_usuarios.sql (backend-1): gatilho em auth.users e RPCs de usuários/empresa (§10.1).
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- --------------------------------------------------------------------- gatilho em auth.users
select teste.ok('cadastro aberto: perfil administrador sem empresa',
  (select papel = 'administrador' and empresa_id is null and nome = 'Sem Empresa'
     from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f0'));
insert into auth.users (id, email, raw_user_meta_data) values
  ('c1000000-0000-4000-8000-00000000f0f1', 'Google@Teste.Local', '{"full_name":"Pessoa Google"}'),
  ('c1000000-0000-4000-8000-00000000f0f2', 'sem.nome@teste.local', '{"papel":"master","empresa_id":"c1000000-0000-4000-8000-0000000000e1"}');
select teste.ok('nome do Google (full_name) e e-mail minúsculo',
  (select nome = 'Pessoa Google' and email = 'google@teste.local' from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f1'));
select teste.ok('metadados de papel/empresa ignorados fora do admin_criar_usuario',
  (select nome = 'sem.nome' and papel = 'administrador' and empresa_id is null
     from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f2'));
-- master_email: vira master só se ainda não houver master
update public.configuracao set master_email = 'dono@teste.local';
insert into auth.users (id, email) values ('c1000000-0000-4000-8000-00000000f0f3', 'dono@teste.local');
select teste.ok('master_email com master existente → administrador',
  (select papel = 'administrador' from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f3'));
update public.perfis set papel = 'administrador' where papel = 'master';
delete from auth.users where id = 'c1000000-0000-4000-8000-00000000f0f3';
insert into auth.users (id, email) values ('c1000000-0000-4000-8000-00000000f0f3', 'DONO@teste.local');
select teste.ok('master_email sem master → master',
  (select papel = 'master' and empresa_id is null from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f3'));
update public.perfis set papel = 'master', empresa_id = null where email = 'b1.master@teste.local';
update auth.users set email = 'google2@teste.local' where id = 'c1000000-0000-4000-8000-00000000f0f1';
select teste.ok('troca de e-mail espelhada no perfil',
  (select email = 'google2@teste.local' from public.perfis where id = 'c1000000-0000-4000-8000-00000000f0f1'));

-- --------------------------------------------------------------------------- admin_criar_usuario
select teste.ok('usuário criado tem senha bcrypt e identidade email',
  (select u.encrypted_password like '$2%' and u.email_confirmed_at is not null and u.confirmation_token = ''
          and exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email' and i.provider_id = u.id::text)
     from auth.users u where u.email = 'b1.admin1@teste.local'));
select teste.ok('senha confere com crypt',
  (select encrypted_password = extensions.crypt('segredo1', encrypted_password) from auth.users where email = 'b1.admin1@teste.local'));

select teste.como('b1.admin1@teste.local');
select teste.passa('admin cria gerente na própria empresa',
  $$select public.admin_criar_usuario('novo.gerente@teste.local', 'abcdef', 'Novo Gerente', 'gerente',
       'c1000000-0000-4000-8000-0000000000e1', 'c1000000-0000-4000-8000-0000000001b1')$$);
select teste.ok('perfil novo com papel, empresa e funcionário',
  (select papel = 'gerente' and empresa_id = 'c1000000-0000-4000-8000-0000000000e1'
          and funcionario_id = 'c1000000-0000-4000-8000-0000000001b1'
     from public.perfis where email = 'novo.gerente@teste.local'));
select teste.erro('admin não cria em outra empresa',
  $$select public.admin_criar_usuario('x1@teste.local', 'abcdef', 'X', 'gerente', 'c1000000-0000-4000-8000-0000000000e2')$$,
  'Sem permissão', '42501');
select teste.erro('admin não cria master',
  $$select public.admin_criar_usuario('x2@teste.local', 'abcdef', 'X', 'master', null)$$, 'Sem permissão', '42501');
select teste.erro('e-mail repetido',
  $$select public.admin_criar_usuario('B1.Gerente1@teste.local', 'abcdef', 'X', 'gerente', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'E-mail já cadastrado', '23505');
select teste.erro('e-mail inválido',
  $$select public.admin_criar_usuario('sem-arroba', 'abcdef', 'X', 'gerente', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'E-mail inválido', '22023');
select teste.erro('senha curta',
  $$select public.admin_criar_usuario('x3@teste.local', '12345', 'X', 'gerente', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'A senha deve ter pelo menos 6 caracteres', '22023');
select teste.erro('nome vazio',
  $$select public.admin_criar_usuario('x3@teste.local', '123456', '  ', 'gerente', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'Informe o nome', '22023');
select teste.erro('papel inválido',
  $$select public.admin_criar_usuario('x3@teste.local', '123456', 'X', 'dono', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'Papel inválido', '22023');
select teste.erro('funcionário de outra empresa',
  $$select public.admin_criar_usuario('x3@teste.local', '123456', 'X', 'leitura', 'c1000000-0000-4000-8000-0000000000e1',
       'c1000000-0000-4000-8000-0000000001a2')$$, 'Funcionário de outra empresa', '22023');

select teste.como('b1.gerente1@teste.local');
select teste.erro('gerente não cria usuário',
  $$select public.admin_criar_usuario('x4@teste.local', '123456', 'X', 'leitura', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'Sem permissão', '42501');
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não cria usuário',
  $$select public.admin_criar_usuario('x4@teste.local', '123456', 'X', 'leitura', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'Sem permissão', '42501');
select teste.como('b1.semempresa@teste.local');
select teste.erro('sem empresa não cria usuário com empresa nula',
  $$select public.admin_criar_usuario('x4@teste.local', '123456', 'X', 'leitura', null)$$, 'Informe a empresa', '22023');
select teste.erro('sem empresa não cria usuário em empresa alheia',
  $$select public.admin_criar_usuario('x4@teste.local', '123456', 'X', 'leitura', 'c1000000-0000-4000-8000-0000000000e1')$$,
  'Sem permissão', '42501');
select teste.como('b1.master@teste.local');
select teste.passa('master cria em qualquer empresa',
  $$select public.admin_criar_usuario('x5@teste.local', '123456', 'X5', 'leitura', 'c1000000-0000-4000-8000-0000000000e2')$$);
select teste.erro('master (com JWT) não cria master',
  $$select public.admin_criar_usuario('x6@teste.local', '123456', 'X6', 'master', null)$$, 'Sem permissão', '42501');
select teste.como_servico();
select teste.erro('service_role não cria master',
  $$select public.admin_criar_usuario('x6@teste.local', '123456', 'X6', 'master', null)$$, 'Sem permissão', '42501');
select teste.como_dono();
select teste.passa('SQL Editor cria master',
  $$select public.admin_criar_usuario('x6@teste.local', '123456', 'X6', 'master', 'c1000000-0000-4000-8000-0000000000e1')$$);
select teste.ok('master criado sem empresa', (select papel = 'master' and empresa_id is null from public.perfis where email = 'x6@teste.local'));

-- ------------------------------------------------------------------- admin_atualizar_usuario
select teste.como('b1.admin1@teste.local');
select teste.passa('admin promove gerente a administrador',
  $$select public.admin_atualizar_usuario(teste.uid('novo.gerente@teste.local'),
       'Novo Admin', 'administrador', true, null)$$);
select teste.ok('papel e funcionário atualizados',
  (select papel = 'administrador' and nome = 'Novo Admin' and funcionario_id is null
     from public.perfis where email = 'novo.gerente@teste.local'));
select teste.erro('ninguém altera o próprio papel',
  $$select public.admin_atualizar_usuario(auth.uid(), 'Eu', 'gerente', true)$$,
  'Você não pode alterar o próprio papel ou situação', '42501');
select teste.erro('ninguém se desativa',
  $$select public.admin_atualizar_usuario(auth.uid(), 'Eu', 'administrador', false)$$,
  'Você não pode alterar o próprio papel ou situação', '42501');
select teste.passa('mas pode mudar o próprio nome', $$select public.admin_atualizar_usuario(auth.uid(), 'Eu Mesmo', 'administrador', true)$$);
select teste.erro('não promove a master',
  $$select public.admin_atualizar_usuario(teste.uid('b1.gerente1@teste.local'), 'G', 'master', true)$$,
  'Papel inválido', '22023');
select teste.erro('admin não edita usuário de outra empresa',
  $$select public.admin_atualizar_usuario(teste.uid('b1.gerente2@teste.local'), 'G', 'leitura', true)$$,
  'Sem permissão', '42501');
select teste.erro('admin não edita master',
  $$select public.admin_atualizar_usuario(teste.uid('b1.master@teste.local'), 'M', 'master', true)$$,
  'Sem permissão', '42501');
select teste.como('b1.gerente1@teste.local');
select teste.erro('gerente não edita usuários',
  $$select public.admin_atualizar_usuario(teste.uid('b1.leitura1@teste.local'), 'L', 'gerente', true)$$,
  'Sem permissão', '42501');

-- -------------------------------------------------------------------- senha / exclusão
select teste.como('b1.admin1@teste.local');
select teste.passa('admin redefine senha de gerente',
  $$select public.admin_redefinir_senha(teste.uid('b1.gerente1@teste.local'), 'novasenha')$$);
select teste.erro('senha curta na redefinição',
  $$select public.admin_redefinir_senha(teste.uid('b1.gerente1@teste.local'), '123')$$,
  'A senha deve ter pelo menos 6 caracteres', '22023');
select teste.erro('admin não redefine senha em outra empresa',
  $$select public.admin_redefinir_senha(teste.uid('b1.gerente2@teste.local'), 'novasenha')$$,
  'Sem permissão', '42501');
select teste.erro('não exclui a si mesmo', $$select public.admin_excluir_usuario(auth.uid())$$, 'Você não pode excluir a si mesmo', '42501');
select teste.erro('admin não exclui de outra empresa',
  $$select public.admin_excluir_usuario(teste.uid('b1.leitura2@teste.local'))$$, 'Sem permissão', '42501');
select teste.passa('admin exclui leitura da empresa',
  $$select public.admin_excluir_usuario(teste.uid('b1.leitura1@teste.local'))$$);
select teste.como_dono();
select teste.ok('exclusão apaga auth.users e perfil (cascata)',
  not exists (select 1 from auth.users where email = 'b1.leitura1@teste.local')
  and not exists (select 1 from public.perfis where email = 'b1.leitura1@teste.local'));
select teste.ok('senha redefinida confere',
  (select encrypted_password = extensions.crypt('novasenha', encrypted_password) from auth.users where email = 'b1.gerente1@teste.local'));
select teste.como('b1.master@teste.local');
select teste.erro('master não exclui master',
  $$select public.admin_excluir_usuario(teste.uid('x6@teste.local'))$$, 'Sem permissão', '42501');

-- ----------------------------------------------------------------------- atualizar_meu_perfil
select teste.como('b1.gerente2@teste.local');
select teste.passa('atualiza o próprio nome', $$select public.atualizar_meu_perfil('  Gerente Dois  ')$$);
select teste.ok('nome com btrim', (select nome = 'Gerente Dois' from public.perfis where id = auth.uid()));
select teste.erro('nome vazio', $$select public.atualizar_meu_perfil('')$$, 'Informe o nome', '22023');

-- ------------------------------------------------------------------------ criar_minha_empresa
select teste.como('b1.semempresa@teste.local');
select teste.passa('sem empresa cria a sua', $$select public.criar_minha_empresa('Minha Loja', '11.222.333/0001-81')$$);
select teste.ok('vira administrador da nova empresa',
  (select p.papel = 'administrador' and e.nome = 'Minha Loja' and e.cnpj = '11222333000181'
     from public.perfis p join public.empresas e on e.id = p.empresa_id where p.id = auth.uid()));
select teste.ok('e passa a ver a própria empresa', teste.contar('select 1 from public.empresas') = 1);
select teste.erro('não cria segunda empresa', $$select public.criar_minha_empresa('Outra')$$, 'Você já pertence a uma empresa');
select teste.como('b1.master@teste.local');
select teste.erro('master não usa criar_minha_empresa', $$select public.criar_minha_empresa('Do Master')$$, 'Sem permissão', '42501');
select teste.como_dono();
update public.configuracao set cadastro_aberto = false;
select teste.como('google2@teste.local');
select teste.erro('cadastro fechado', $$select public.criar_minha_empresa('Fechada')$$, 'Cadastro de novas empresas desativado', '42501');

-- ----------------------------------------------------------------------- master_criar_empresa
select teste.como('b1.admin1@teste.local');
select teste.erro('admin não usa master_criar_empresa',
  $$select public.master_criar_empresa('E3', null, 'adm3@teste.local', '123456', 'Adm 3')$$, 'Sem permissão', '42501');
select teste.como('b1.master@teste.local');
select teste.passa('master cria empresa + admin',
  $$select public.master_criar_empresa('Empresa Três', null, 'adm3@teste.local', '123456', 'Adm 3')$$);
select teste.ok('admin da nova empresa',
  (select p.papel = 'administrador' and e.nome = 'Empresa Três'
     from public.perfis p join public.empresas e on e.id = p.empresa_id where p.email = 'adm3@teste.local'));
select teste.erro('falha no admin desfaz a empresa (transação)',
  $$select public.master_criar_empresa('Empresa Quatro', null, 'adm3@teste.local', '123456', 'Adm 4')$$, 'E-mail já cadastrado');
select teste.ok('empresa quatro não ficou', not exists (select 1 from public.empresas where nome = 'Empresa Quatro'));

-- ------------------------------------------------------------------------------ tornar_master
select teste.como('b1.admin1@teste.local');
select teste.erro('tornar_master é interno', $$select public.tornar_master('b1.admin1@teste.local')$$, 'permission denied');
select teste.como_dono();
select public.tornar_master('adm3@teste.local');
select teste.ok('tornar_master pelo SQL Editor', (select papel = 'master' and empresa_id is null from public.perfis where email = 'adm3@teste.local'));
rollback;
