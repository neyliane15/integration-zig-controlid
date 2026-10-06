-- 10_base_rls.sql (backend-1): empresas, perfis, configuracao, auxiliares de política, dia de trabalho.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- ------------------------------------------------------------------- dia de trabalho (§2.4)
select teste.ok('01:30 local pertence ao dia anterior',
  public.dia_de_trabalho('2026-10-04 01:30:00-03', 'c1000000-0000-4000-8000-0000000000e1') = '2026-10-03');
select teste.ok('05:00 local já é o próprio dia',
  public.dia_de_trabalho('2026-10-04 05:00:00-03', 'c1000000-0000-4000-8000-0000000000e1') = '2026-10-04');
select teste.ok('04:59:59 local ainda é o dia anterior',
  public.dia_de_trabalho('2026-10-04 04:59:59-03', 'c1000000-0000-4000-8000-0000000000e1') = '2026-10-03');
select teste.ok('instante de escala 01:00 cai no dia seguinte',
  public.dia_de_trabalho_instante('2026-10-03', '01:00', 'c1000000-0000-4000-8000-0000000000e1') = '2026-10-04 01:00:00-03');
select teste.ok('instante de escala 17:00 cai no mesmo dia',
  public.dia_de_trabalho_instante('2026-10-03', '17:00', 'c1000000-0000-4000-8000-0000000000e1') = '2026-10-03 17:00:00-03');
select teste.ok('agora() respeita app.agora', public.agora() = '2026-10-06 12:00:00-03');
select teste.erro('fuso inválido recusado',
  $$update public.empresas set fuso = 'Marte/Olympus' where id = 'c1000000-0000-4000-8000-0000000000e1'$$,
  'Fuso horário inválido', '22023');
update public.empresas set cnpj = '12.345.678/0001-95' where id = 'c1000000-0000-4000-8000-0000000000e1';
select teste.ok('cnpj normalizado para dígitos',
  (select cnpj = '12345678000195' from public.empresas where id = 'c1000000-0000-4000-8000-0000000000e1'));

-- ---------------------------------------------------------- auxiliares: sempre boolean estrito
select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura: pode_ler da própria = true', public.pode_ler('c1000000-0000-4000-8000-0000000000e1') is true);
select teste.ok('leitura: pode_operar = false (não null)', public.pode_operar('c1000000-0000-4000-8000-0000000000e1') is false);
select teste.ok('leitura: pode_administrar = false (não null)', public.pode_administrar('c1000000-0000-4000-8000-0000000000e1') is false);
select teste.ok('leitura: pode_ler de outra = false', public.pode_ler('c1000000-0000-4000-8000-0000000000e2') is false);
select teste.ok('leitura: pode_ler(null) = false', public.pode_ler(null) is false);
select teste.ok('dia_de_trabalho_atual da própria', public.dia_de_trabalho_atual() = '2026-10-06');
select teste.erro('leitura: dia_de_trabalho_atual de outra empresa',
  $$select public.dia_de_trabalho_atual('c1000000-0000-4000-8000-0000000000e2')$$, 'Sem permissão', '42501');

-- resolver_empresa é [interno]: testado como dono vestindo claims de leitura (regressão do bug NULL)
select teste.como_dono();
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'b1.leitura1@teste.local'), 'role', 'authenticated')::text, true);
select teste.ok('resolver_empresa ler (null → própria)',
  public.resolver_empresa(null, 'ler') = 'c1000000-0000-4000-8000-0000000000e1');
select teste.erro('resolver_empresa nega operar para leitura (p_empresa null)',
  $$select public.resolver_empresa(null, 'operar')$$, 'Sem permissão', '42501');
select teste.erro('resolver_empresa nega administrar para leitura',
  $$select public.resolver_empresa(null, 'administrar')$$, 'Sem permissão', '42501');
select teste.erro('resolver_empresa nega nível desconhecido',
  $$select public.resolver_empresa(null, 'qualquer')$$, 'Sem permissão', '42501');
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'b1.gerente1@teste.local'), 'role', 'authenticated')::text, true);
select teste.ok('resolver_empresa operar para gerente', public.resolver_empresa(null, 'operar') = 'c1000000-0000-4000-8000-0000000000e1');
select teste.erro('resolver_empresa nega administrar para gerente',
  $$select public.resolver_empresa(null, 'administrar')$$, 'Sem permissão', '42501');
select teste.erro('resolver_empresa nega outra empresa para gerente',
  $$select public.resolver_empresa('c1000000-0000-4000-8000-0000000000e2', 'ler')$$, 'Sem permissão', '42501');
select set_config('request.jwt.claims',
  json_build_object('sub', 'c1000000-0000-4000-8000-00000000f0f0', 'role', 'authenticated')::text, true);
select teste.erro('resolver_empresa: sem empresa → Informe a empresa',
  $$select public.resolver_empresa(null, 'ler')$$, 'Informe a empresa', '22023');
select teste.erro('resolver_empresa: sem empresa não lê empresa alheia',
  $$select public.resolver_empresa('c1000000-0000-4000-8000-0000000000e1', 'ler')$$, 'Sem permissão', '42501');
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'b1.master@teste.local'), 'role', 'authenticated')::text, true);
select teste.erro('resolver_empresa: master sem p_empresa', $$select public.resolver_empresa(null, 'ler')$$, 'Informe a empresa', '22023');
select teste.erro('resolver_empresa: empresa inexistente',
  $$select public.resolver_empresa('c1000000-0000-4000-8000-0000000000ff', 'ler')$$, 'Empresa não encontrada', 'P0002');
select set_config('request.jwt.claims', '', true);

-- ------------------------------------------------------------------------------- empresas
select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê só a própria empresa', teste.contar('select 1 from public.empresas') = 1);
select teste.ok('leitura não altera a empresa (0 linhas)', teste.afetadas($$update public.empresas set nome = 'X'$$) = 0);
select teste.como('b1.gerente1@teste.local');
select teste.ok('gerente não altera a empresa', teste.afetadas($$update public.empresas set nome = 'X'$$) = 0);
select teste.como('b1.admin1@teste.local');
select teste.ok('admin altera a própria empresa', teste.afetadas($$update public.empresas set nome = 'Empresa Um Ltda', ativa = false$$) = 1);
select teste.ok('admin não muda "ativa" (valor antigo mantido)', (select ativa and nome = 'Empresa Um Ltda' from public.empresas));
select teste.ok('admin não altera empresa alheia',
  teste.afetadas($$update public.empresas set nome = 'X' where id = 'c1000000-0000-4000-8000-0000000000e2'$$) = 0);
select teste.erro('admin não cria empresa direto', $$insert into public.empresas (nome) values ('Nova')$$, 'row-level security');
select teste.ok('admin não exclui empresa', teste.afetadas($$delete from public.empresas$$) = 0);
select teste.como('b1.inativo1@teste.local');
select teste.ok('perfil inativo não vê empresa', teste.contar('select 1 from public.empresas') = 0);
select teste.ok('perfil inativo ainda lê o próprio perfil', teste.contar('select 1 from public.perfis') = 1);
select teste.como('b1.semempresa@teste.local');
select teste.ok('sem empresa: não vê empresas', teste.contar('select 1 from public.empresas') = 0);
select teste.ok('sem empresa: vê só o próprio perfil', teste.contar('select 1 from public.perfis') = 1);
select teste.ok('sem empresa: não vê funcionários', teste.contar('select 1 from public.funcionarios') = 0);
select teste.como('b1.master@teste.local');
select teste.ok('master vê todas as empresas', teste.contar($$select 1 from public.empresas where id::text like 'c1%'$$) = 2);
select teste.ok('master desativa empresa',
  teste.afetadas($$update public.empresas set ativa = false where id = 'c1000000-0000-4000-8000-0000000000e2'$$) = 1);
select teste.ok('empresa ficou inativa', not (select ativa from public.empresas where id = 'c1000000-0000-4000-8000-0000000000e2'));
select teste.como('b1.gerente2@teste.local');
select teste.ok('empresa inativa: gerente não vê nada', teste.contar('select 1 from public.empresas') = 0);
select teste.ok('empresa inativa: gerente não vê funcionários', teste.contar('select 1 from public.funcionarios') = 0);
select teste.erro('empresa inativa: dia_de_trabalho_atual nega', $$select public.dia_de_trabalho_atual()$$, 'Sem permissão', '42501');
select teste.como('b1.master@teste.local');
update public.empresas set ativa = true where id = 'c1000000-0000-4000-8000-0000000000e2';

-- --------------------------------------------------------------------------------- perfis
select teste.como('b1.gerente1@teste.local');
select teste.ok('gerente vê perfis da própria empresa (4)', teste.contar('select 1 from public.perfis') = 4);
select teste.erro('gerente não altera perfis direto',
  $$update public.perfis set papel = 'administrador'$$, 'permission denied');
select teste.como('b1.admin2@teste.local');
select teste.ok('admin2 vê só perfis da E2 (3)', teste.contar('select 1 from public.perfis') = 3);

-- --------------------------------------------------------------------------- configuracao
select teste.como('b1.admin1@teste.local');
select teste.ok('admin não lê configuracao', teste.contar('select 1 from public.configuracao') = 0);
select teste.erro('admin não altera configuracao', $$update public.configuracao set cadastro_aberto = false$$, 'permission denied');
select teste.como('b1.master@teste.local');
select teste.ok('master lê configuracao', teste.contar('select 1 from public.configuracao') = 1);

-- ------------------------------------------------------------------------------------ anon
select teste.como(null);
select teste.erro('anon não lê empresas', $$select * from public.empresas$$, 'permission denied');
select teste.erro('anon não lê perfis', $$select * from public.perfis$$, 'permission denied');
select teste.erro('anon não executa funções', $$select public.dia_de_trabalho(now(), 'c1000000-0000-4000-8000-0000000000e1')$$, 'permission denied');
select teste.erro('anon não executa auxiliares', $$select public.eh_master()$$, 'permission denied');

-- --------------------------------------------------------------- service_role e contexto
select teste.como_servico();
select teste.ok('service_role é sistema', public.eh_sistema());
select teste.ok('service_role não é sem_jwt', not public.sem_jwt());
select teste.ok('service_role lê tudo', teste.contar($$select 1 from public.empresas where id::text like 'c1%'$$) = 2);
select teste.como('b1.admin1@teste.local');
select teste.ok('authenticated não é sistema', not public.pode_administrar('c1000000-0000-4000-8000-0000000000e2'));
rollback;
