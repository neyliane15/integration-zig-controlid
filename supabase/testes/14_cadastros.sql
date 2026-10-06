-- 14_cadastros.sql (backend-1): funcionários, pontos, jornadas, RLS e isolamento.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- ------------------------------------------------------------------------------ funcionários
select teste.como('b1.gerente1@teste.local');
insert into public.funcionarios (empresa_id, nome, cpf, pis, zig_employee_name, pontos_comissao)
values ('c1000000-0000-4000-8000-0000000000e1', '  Cicrano  ', '390.533.447-05', '', '  Cicrano C ', 3);
select teste.ok('normalização: nome, cpf dígitos, pis vazio → null, zig btrim',
  (select nome = 'Cicrano' and cpf = '39053344705' and pis is null and zig_employee_name = 'Cicrano C'
     from public.funcionarios where nome = 'Cicrano'));
select teste.ok('matrícula sequencial gerada (3)', (select matricula = '3' from public.funcionarios where nome = 'Cicrano'));
select teste.ok('histórico de pontos criado no insert (dia atual)',
  (select pontos = 3 and vigente_desde = '2026-10-06' from public.funcionario_pontos fp
     join public.funcionarios f on f.id = fp.funcionario_id where f.nome = 'Cicrano'));
select teste.erro('CPF repetido na empresa',
  $$insert into public.funcionarios (empresa_id, nome, cpf) values ('c1000000-0000-4000-8000-0000000000e1', 'Dup', '52998224725')$$,
  'funcionarios_cpf_uk');
select teste.erro('nome Zig repetido (case-insensitive)',
  $$insert into public.funcionarios (empresa_id, nome, zig_employee_name) values ('c1000000-0000-4000-8000-0000000000e1', 'Dup', 'cicrano c')$$,
  'funcionarios_zig_uk');
select teste.erro('gerente não cria funcionário em outra empresa',
  $$insert into public.funcionarios (empresa_id, nome) values ('c1000000-0000-4000-8000-0000000000e2', 'Intruso')$$,
  'row-level security');
select teste.ok('gerente vê só funcionários da E1 (3)', teste.contar('select 1 from public.funcionarios') = 3);
select teste.ok('gerente não altera funcionário da E2',
  teste.afetadas($$update public.funcionarios set nome = 'X' where id = 'c1000000-0000-4000-8000-0000000001a2'$$) = 0);
update public.funcionarios set empresa_id = 'c1000000-0000-4000-8000-0000000000e2', pontos_comissao = 12
 where id = 'c1000000-0000-4000-8000-0000000001a1';
select teste.ok('empresa_id do funcionário é imutável',
  (select empresa_id = 'c1000000-0000-4000-8000-0000000000e1' from public.funcionarios where id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('mudança de pontos grava vigência no dia atual',
  (select count(*) = 2 and max(pontos) = 12 from public.funcionario_pontos where funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
update public.funcionarios set pontos_comissao = 11 where id = 'c1000000-0000-4000-8000-0000000001a1';
select teste.ok('mesmo dia: upsert (continua com 2 linhas)',
  (select count(*) = 2 from public.funcionario_pontos where funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('pontos_vigentes antes da mudança = 10',
  public.pontos_vigentes('c1000000-0000-4000-8000-0000000001a1', '2026-10-05') = 10);
select teste.ok('pontos_vigentes depois = 11',
  public.pontos_vigentes('c1000000-0000-4000-8000-0000000001a1', '2026-10-06') = 11);
select teste.ok('pontos_vigentes antes de todo histórico = o mais antigo',
  public.pontos_vigentes('c1000000-0000-4000-8000-0000000001a1', '2020-01-01') = 10);
select teste.erro('pontos_vigentes de outra empresa',
  $$select public.pontos_vigentes('c1000000-0000-4000-8000-0000000001a2', '2026-10-06')$$, 'Sem permissão', '42501');
select teste.erro('gerente não escreve funcionario_pontos direto',
  $$insert into public.funcionario_pontos (empresa_id, funcionario_id, pontos, vigente_desde)
    values ('c1000000-0000-4000-8000-0000000000e1', 'c1000000-0000-4000-8000-0000000001a1', 1, '2026-01-01')$$, 'permission denied');
select teste.ok('gerente não exclui funcionário (só A)',
  teste.afetadas($$delete from public.funcionarios where nome = 'Cicrano'$$) = 0);
select teste.erro('datas incoerentes',
  $$update public.funcionarios set data_desligamento = '2025-01-01' where id = 'c1000000-0000-4000-8000-0000000001a1'$$,
  'funcionarios_datas');

select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê funcionários da E1', teste.contar('select 1 from public.funcionarios') = 3);
select teste.ok('leitura não vê histórico de pontos', teste.contar('select 1 from public.funcionario_pontos') = 0);
select teste.erro('leitura não cria funcionário',
  $$insert into public.funcionarios (empresa_id, nome) values ('c1000000-0000-4000-8000-0000000000e1', 'X')$$, 'row-level security');
select teste.ok('leitura não altera funcionário', teste.afetadas($$update public.funcionarios set nome = 'X'$$) = 0);
select teste.erro('leitura não chama pontos_vigentes',
  $$select public.pontos_vigentes('c1000000-0000-4000-8000-0000000001a1', '2026-10-06')$$, 'Sem permissão', '42501');

select teste.como('b1.admin1@teste.local');
select teste.ok('admin exclui funcionário', teste.afetadas($$delete from public.funcionarios where nome = 'Cicrano'$$) = 1);
select teste.como('b1.admin2@teste.local');
select teste.ok('admin2 não vê funcionários da E1', teste.contar($$select 1 from public.funcionarios where empresa_id = 'c1000000-0000-4000-8000-0000000000e1'$$) = 0);
select teste.ok('admin2 não exclui da E1',
  teste.afetadas($$delete from public.funcionarios where id = 'c1000000-0000-4000-8000-0000000001b1'$$) = 0);

-- --------------------------------------------------------------------------------- jornadas
select teste.como('b1.gerente1@teste.local');
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
values ('c1000000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
select teste.ok('jornada noturna: 450 min, 4 batidas, empresa do pai',
  (select minutos_previstos = 450 and batidas_esperadas = 4 and empresa_id = 'c1000000-0000-4000-8000-0000000000e1'
     from public.jornada_dias where jornada_id = 'c1000000-0000-4000-8000-000000000201' and dia_semana = 6));
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) values ('c1000000-0000-4000-8000-000000000201', 5, '18:00', '23:00');
select teste.ok('jornada sem intervalo: 300 min, 2 batidas',
  (select minutos_previstos = 300 and batidas_esperadas = 2 from public.jornada_dias
    where jornada_id = 'c1000000-0000-4000-8000-000000000201' and dia_semana = 5));
select teste.erro('horários fora de ordem',
  $$insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
    values ('c1000000-0000-4000-8000-000000000201', 4, '17:00', '21:30', '21:00', '01:00')$$, 'Horários da jornada fora de ordem', '22023');
select teste.erro('saída igual à entrada',
  $$insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida)
    values ('c1000000-0000-4000-8000-000000000201', 4, '17:00', '17:00')$$, 'Horários da jornada fora de ordem', '22023');
select teste.erro('intervalo pela metade',
  $$insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, saida)
    values ('c1000000-0000-4000-8000-000000000201', 4, '17:00', '19:00', '23:00')$$, 'jornada_dias_intervalo');
select teste.erro('dia na jornada de outra empresa (empresa vem do pai → RLS)',
  $$insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida)
    values ('c1000000-0000-4000-8000-000000000202', 1, '10:00', '18:00')$$, 'row-level security');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
values ('c1000000-0000-4000-8000-0000000001a1', 'c1000000-0000-4000-8000-000000000201', '2026-01-01');
select teste.ok('funcionario_jornadas com empresa do funcionário',
  (select empresa_id = 'c1000000-0000-4000-8000-0000000000e1' from public.funcionario_jornadas
    where funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.erro('jornada de outra empresa',
  $$insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
    values ('c1000000-0000-4000-8000-0000000001b1', 'c1000000-0000-4000-8000-000000000202', '2026-01-01')$$,
  'Jornada de outra empresa', '22023');
select teste.erro('funcionário de outra empresa (RLS)',
  $$insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
    values ('c1000000-0000-4000-8000-0000000001a2', 'c1000000-0000-4000-8000-000000000202', '2026-01-01')$$,
  'row-level security');
select teste.erro('jornada em uso não pode ser apagada',
  $$delete from public.jornadas where id = 'c1000000-0000-4000-8000-000000000201'$$, 'funcionario_jornadas');
update public.jornadas set empresa_id = 'c1000000-0000-4000-8000-0000000000e2', nome = 'Noite 2'
 where id = 'c1000000-0000-4000-8000-000000000201';
select teste.ok('empresa da jornada imutável',
  (select empresa_id = 'c1000000-0000-4000-8000-0000000000e1' and nome = 'Noite 2' from public.jornadas
    where id = 'c1000000-0000-4000-8000-000000000201'));
select teste.ok('gerente vê só a jornada da E1', teste.contar('select 1 from public.jornadas') = 1);

select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê jornadas e dias', teste.contar('select 1 from public.jornada_dias') = 2);
select teste.erro('leitura não cria jornada',
  $$insert into public.jornadas (empresa_id, nome) values ('c1000000-0000-4000-8000-0000000000e1', 'X')$$, 'row-level security');
select teste.ok('leitura não apaga dia de jornada', teste.afetadas('delete from public.jornada_dias') = 0);

select teste.como('b1.gerente2@teste.local');
select teste.ok('gerente2 não vê nada da E1 (jornadas, dias, vínculos)',
  teste.contar($$select 1 from public.jornadas where empresa_id = 'c1000000-0000-4000-8000-0000000000e1'
                 union all select 1 from public.jornada_dias union all select 1 from public.funcionario_jornadas$$) = 0);
select teste.ok('gerente2 não altera jornada da E1',
  teste.afetadas($$update public.jornadas set nome = 'X' where id = 'c1000000-0000-4000-8000-000000000201'$$) = 0);

select teste.como(null);
select teste.erro('anon não lê funcionários', 'select * from public.funcionarios', 'permission denied');
select teste.erro('anon não lê jornadas', 'select * from public.jornadas', 'permission denied');

-- ---------------------------------------------------------------- perfis.funcionario_id
select teste.como('b1.leitura1@teste.local');
select teste.ok('meu_funcionario do leitura', public.meu_funcionario() = 'c1000000-0000-4000-8000-0000000001a1');
rollback;
