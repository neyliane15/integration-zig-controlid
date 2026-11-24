-- 84_assistente.sql — RPCs do assistente de IA: resumo de ponto por funcionário e escala de um dia (com permissões).
begin;
set local app.agora = '2026-11-17 12:00:00-03';
select teste.como_dono();
alter table public.empresas alter column ponto_alarme_prazo_dias set default 31;
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e8400000-0000-4000-8000-00000000000a', 'Teste Assistente A', 'America/Sao_Paulo', '05:00'),
  ('e8400000-0000-4000-8000-00000000000b', 'Teste Assistente B', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e8400000-0000-4000-8000-000000000a01', 'ass.ger@teste.local', '{"nome":"Gerente"}'),
  ('e8400000-0000-4000-8000-000000000a02', 'ass.leit@teste.local', '{"nome":"Leitura"}');
update public.perfis set papel = 'gerente', empresa_id = 'e8400000-0000-4000-8000-00000000000a' where id = 'e8400000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'leitura', empresa_id = 'e8400000-0000-4000-8000-00000000000a' where id = 'e8400000-0000-4000-8000-000000000a02';
insert into public.funcionarios (id, empresa_id, nome, cargo, data_admissao) values
  ('e8400000-0000-4000-8000-000000000301', 'e8400000-0000-4000-8000-00000000000a', 'Ana', 'Garçom', '2026-01-01'),
  ('e8400000-0000-4000-8000-000000000302', 'e8400000-0000-4000-8000-00000000000a', 'Bia', 'Cumim', '2026-01-01'),
  ('e8400000-0000-4000-8000-000000000303', 'e8400000-0000-4000-8000-00000000000b', 'Outra empresa', 'Bar', '2026-01-01');
insert into public.ponto_dias (funcionario_id, data, empresa_id, batidas_esperadas, batidas_validas, batidas_duplicadas,
                               previsto_minutos, trabalhado_minutos, saldo_minutos, atraso_minutos, situacao, encerrado) values
  ('e8400000-0000-4000-8000-000000000301', '2026-11-10', 'e8400000-0000-4000-8000-00000000000a', 4, 4, 0, 440, 450, 10, 15, 'completo', true),
  ('e8400000-0000-4000-8000-000000000301', '2026-11-11', 'e8400000-0000-4000-8000-00000000000a', 4, 4, 0, 440, 430, -10, 5, 'completo', true),
  ('e8400000-0000-4000-8000-000000000301', '2026-11-12', 'e8400000-0000-4000-8000-00000000000a', 4, 0, 0, 440, 0, -440, 0, 'ausente', true),
  ('e8400000-0000-4000-8000-000000000302', '2026-11-10', 'e8400000-0000-4000-8000-00000000000a', 4, 4, 0, 440, 440, 0, 0, 'completo', true);
insert into public.funcionario_faltas (empresa_id, funcionario_id, data, tipo, motivo, criado_por_nome) values
  ('e8400000-0000-4000-8000-00000000000a', 'e8400000-0000-4000-8000-000000000302', '2026-11-13', 'justificada', 'Atestado', 'Teste');

select teste.como('ass.ger@teste.local');
select teste.ok('resumo do ponto: Ana 2 dias, 1 falta, 2 atrasos (20 min), saldo −7h20; Bia 1 falta justificada',
  (select array_agg(funcionario_nome || ' ' || dias_com_batida || ' ' || faltas || ' ' || faltas_justificadas || ' ' || atrasos || ' '
                    || minutos_atraso || ' ' || trabalhado_minutos || ' ' || saldo_minutos order by funcionario_nome)
     from public.assistente_ponto_resumo('2026-11-01', '2026-11-17'))
  = array['Ana 2 1 0 2 20 880 -440', 'Bia 1 0 1 0 0 440 0']);
select teste.erro('período inválido', $$select * from public.assistente_ponto_resumo('2026-11-10', '2026-11-01')$$,
  'Período inválido (máximo de 366 dias)', '22023');
select teste.erro('outra empresa: sem permissão',
  $$select * from public.assistente_ponto_resumo('2026-11-01', '2026-11-17', 'e8400000-0000-4000-8000-00000000000b')$$, 'Sem permissão', '42501');
select teste.ok('escala de um dia sem escala configurada: vazia', not exists (select 1 from public.assistente_escala_dia('2026-11-17')));

select teste.como('ass.leit@teste.local');
select teste.erro('leitura não vê o resumo de ponto',
  $$select * from public.assistente_ponto_resumo('2026-11-01', '2026-11-17')$$, 'Sem permissão', '42501');
select teste.ok('leitura vê a escala do dia', (select count(*) = 0 from public.assistente_escala_dia('2026-11-17')));
rollback;
