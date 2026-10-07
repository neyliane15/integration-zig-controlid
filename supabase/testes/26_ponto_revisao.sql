-- 26_ponto_revisao.sql (revisão 1) — achados da revisão no ponto:
--  * atraso só quando a 1ª batida corresponde à entrada (entrada esquecida = "batida faltando", não 4 h de atraso);
--  * ponto_dia_empresa devolve as batidas esperadas do dia (abono/folga → nenhuma), em vez do front recalcular.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, ponto_alarme_atraso) values ('e2600000-0000-4000-8000-00000000000a', 'Teste ponto rev', true);
insert into auth.users (id, email, raw_user_meta_data) values ('e2600000-0000-4000-8000-000000000a03', 'r26.lei@teste.local', '{"nome":"Leitura"}');
update public.perfis set papel = 'leitura', empresa_id = 'e2600000-0000-4000-8000-00000000000a' where id = 'e2600000-0000-4000-8000-000000000a03';
insert into public.jornadas (id, empresa_id, nome) values ('e2600000-0000-4000-8000-000000000201', 'e2600000-0000-4000-8000-00000000000a', 'Noite');
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
select 'e2600000-0000-4000-8000-000000000201', d, '17:00', '21:00', '21:30', '01:00' from unnest(array[2, 6]) d;
insert into public.funcionarios (id, empresa_id, nome, data_admissao) values
  ('e2600000-0000-4000-8000-000000000301', 'e2600000-0000-4000-8000-00000000000a', 'Ana', '2026-01-01'),
  ('e2600000-0000-4000-8000-000000000302', 'e2600000-0000-4000-8000-00000000000a', 'Bia', '2026-01-01');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e2600000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e2600000-0000-4000-8000-000000000301', 'e2600000-0000-4000-8000-000000000302']::uuid[]) f;

-- sáb 2026-09-19: esqueceu a entrada (21:02, 21:29, 01:04)
select public.ponto_incluir_batida('e2600000-0000-4000-8000-000000000301', t, 'teste')
  from unnest(array['2026-09-19 21:02-03', '2026-09-19 21:29-03', '2026-09-20 01:04-03']::timestamptz[]) t;
select teste.ok('entrada esquecida: alarme de batida faltando na entrada',
  exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2600000-0000-4000-8000-000000000301'
             and data = '2026-09-19' and tipo = 'batida_faltando' and batida_esperada = 'entrada' and status = 'aberto'));
select teste.ok('entrada esquecida: sem alarme de atraso',
  not exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2600000-0000-4000-8000-000000000301'
                 and data = '2026-09-19' and tipo = 'atraso'));
select teste.ok('entrada esquecida: atraso_minutos = 0 no dia',
  (select atraso_minutos from public.ponto_dias where funcionario_id = 'e2600000-0000-4000-8000-000000000301' and data = '2026-09-19') = 0);

-- sáb 2026-09-26: entrada batida com 20 min de atraso e faltou a volta do intervalo → atraso continua valendo
select public.ponto_incluir_batida('e2600000-0000-4000-8000-000000000301', t, 'teste')
  from unnest(array['2026-09-26 17:20-03', '2026-09-26 21:00-03', '2026-09-27 01:00-03']::timestamptz[]) t;
select teste.ok('entrada atrasada com batida faltando: atraso de 20 min continua',
  (select atraso_minutos from public.ponto_dias where funcionario_id = 'e2600000-0000-4000-8000-000000000301' and data = '2026-09-26') = 20
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2600000-0000-4000-8000-000000000301'
                 and data = '2026-09-26' and tipo = 'atraso' and minutos = 20));

-- ponto_dia_empresa devolve as esperadas do dia de hoje (ter 2026-10-06, em andamento)
select public.ponto_abonar('2026-10-06', '2026-10-06', 'atestado', 'médico', 'e2600000-0000-4000-8000-000000000302');
select teste.como('r26.lei@teste.local');
select teste.ok('ponto_dia_empresa: esperadas com os 4 horários da escala (Ana)',
  (select array_agg(e ->> 'batida' order by o) from public.ponto_dia_empresa() d,
          jsonb_array_elements(d.esperadas) with ordinality x(e, o) where d.funcionario_nome = 'Ana')
  = array['entrada', 'saida_intervalo', 'volta_intervalo', 'saida']);
select teste.ok('ponto_dia_empresa: 1ª esperada = 17:00 de hoje; a última cai no dia seguinte (01:00)',
  (select (esperadas -> 0 ->> 'instante')::timestamptz = '2026-10-06 17:00-03'
      and (esperadas -> 3 ->> 'instante')::timestamptz = '2026-10-07 01:00-03'
     from public.ponto_dia_empresa() where funcionario_nome = 'Ana'));
select teste.ok('ponto_dia_empresa: dia abonado (em andamento) não tem esperadas',
  (select esperadas = '[]'::jsonb from public.ponto_dia_empresa() where funcionario_nome = 'Bia'));
rollback;
