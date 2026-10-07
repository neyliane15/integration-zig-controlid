-- 20_ponto_apuracao.sql (b2) — apuração diária: vetor obrigatório do §7.6, virada do dia, fuso por empresa,
-- duplicadas, situações, vínculo, abono, espelho e ponto do dia.
begin;
-- ------------------------------------------------------------------ cenário comum b2 (dentro da transação)
-- Relógio fixo, duas empresas (A = SP, B = Manaus), usuários de todos os papéis, jornada "Salão noite" (só sábado).
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e2000000-0000-4000-8000-00000000000a', 'Teste b2 A', 'America/Sao_Paulo', '05:00'),
  ('e2000000-0000-4000-8000-00000000000b', 'Teste b2 B', 'America/Manaus', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e2000000-0000-4000-8000-000000000a01', 'b2.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e2000000-0000-4000-8000-000000000a02', 'b2.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e2000000-0000-4000-8000-000000000a03', 'b2.lei.a@teste.local', '{"nome":"Leitura A"}'),
  ('e2000000-0000-4000-8000-000000000b01', 'b2.adm.b@teste.local', '{"nome":"Adm B"}'),
  ('e2000000-0000-4000-8000-000000000f01', 'b2.master@teste.local', '{"nome":"Master b2"}');
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a03';
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000b' where id = 'e2000000-0000-4000-8000-000000000b01';
update public.perfis set papel = 'master', empresa_id = null where id = 'e2000000-0000-4000-8000-000000000f01';
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e2000000-0000-4000-8000-000000000201', 'e2000000-0000-4000-8000-00000000000a', 'Salão noite b2', 5, 10),
  ('e2000000-0000-4000-8000-000000000202', 'e2000000-0000-4000-8000-00000000000b', 'Turno B', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values
  ('e2000000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) select 'e2000000-0000-4000-8000-000000000202', d, '09:00', '17:00' from generate_series(1, 5) d;
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, pontos_comissao, data_admissao, zig_employee_name) values
  ('e2000000-0000-4000-8000-000000000301', 'e2000000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', '52998224725', 10, '2026-01-01', 'Ana Souza'),
  ('e2000000-0000-4000-8000-000000000302', 'e2000000-0000-4000-8000-00000000000a', 'Bruno Lima', 'Garçom', '11144477735', 10, '2026-01-01', 'Bruno Lima'),
  ('e2000000-0000-4000-8000-000000000303', 'e2000000-0000-4000-8000-00000000000a', 'Carla Dias', 'Cumim', '39053344705', 6, '2026-01-01', 'Carla Dias'),
  ('e2000000-0000-4000-8000-000000000304', 'e2000000-0000-4000-8000-00000000000a', 'Davi Rocha', 'Bartender', '15350946056', 8, '2026-01-01', 'Davi Rocha'),
  ('e2000000-0000-4000-8000-000000000305', 'e2000000-0000-4000-8000-00000000000a', 'Eva Martins', 'Cozinha', '71428793860', 4, '2026-01-01', null),
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-00000000000b', 'Paolo B2', 'Garçom', null, 5, '2026-01-01', 'Paolo');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e2000000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e2000000-0000-4000-8000-000000000301','e2000000-0000-4000-8000-000000000302',
                    'e2000000-0000-4000-8000-000000000303','e2000000-0000-4000-8000-000000000304',
                    'e2000000-0000-4000-8000-000000000305']::uuid[]) f;
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde) values
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-000000000202', '2026-09-01');
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e2000000-0000-4000-8000-000000000101', 'e2000000-0000-4000-8000-00000000000a', 'zig', 'Zig b2', '{"rede":"r"}'),
  ('e2000000-0000-4000-8000-000000000102', 'e2000000-0000-4000-8000-00000000000a', 'controlid_acesso', 'iDFace b2', '{}'),
  ('e2000000-0000-4000-8000-000000000103', 'e2000000-0000-4000-8000-00000000000a', 'controlid_rep', 'iDClass b2', '{}'),
  ('e2000000-0000-4000-8000-000000000111', 'e2000000-0000-4000-8000-00000000000b', 'zig', 'Zig B b2', '{}'),
  ('e2000000-0000-4000-8000-000000000112', 'e2000000-0000-4000-8000-00000000000b', 'controlid_rep', 'REP B b2', '{}');
-- ------------------------------------------------------------------ fim do cenário comum

-- Ana (301): vetor do §7.6 (sábados de escala 17:00/21:00/21:30/01:00 e um domingo de folga)
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
select 'e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000301', 'manual', i::timestamptz, 'teste'
  from unnest(array[
    '2026-10-03 16:58-03', '2026-10-03 21:02-03', '2026-10-03 21:29-03', '2026-10-04 01:04-03',
    '2026-09-26 17:20-03', '2026-09-26 17:21-03', '2026-09-26 21:00-03', '2026-09-26 21:30-03', '2026-09-27 01:00-03',
    '2026-09-19 16:58-03', '2026-09-19 21:02-03', '2026-09-20 01:05-03',
    '2026-09-13 10:00-03', '2026-09-13 12:00-03', '2026-09-13 13:00-03']) i;

select teste.ok('data_trabalho: 01:04 de domingo pertence ao sábado',
  (select data_trabalho from public.ponto_batidas where instante = '2026-10-04 01:04-03') = '2026-10-03');
select teste.ok('ponto_apurar devolve nº de dias apurados (até o dia atual)',
  public.ponto_apurar('e2000000-0000-4000-8000-000000000301', '2026-09-12', '2026-10-10') = 25);

create temp table d on commit drop as
  select * from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301';

select teste.ok('03/10: 4 batidas, 459 trabalhados, saldo 0 (tolerância), completo',
  (select (batidas_validas, trabalhado_minutos, saldo_minutos, situacao, previsto_minutos, encerrado)
     = (4::smallint, 459, 0, 'completo'::text, 450, true) from d where data = '2026-10-03'));
select teste.ok('26/09: duplicada 17:21 ignorada; 430 trabalhados; saldo −20; completo; atraso 20',
  (select (batidas_validas, batidas_duplicadas, trabalhado_minutos, saldo_minutos, situacao, atraso_minutos)
     = (4::smallint, 1::smallint, 430, -20, 'completo'::text, 20) from d where data = '2026-09-26'));
select teste.ok('19/09: 3 batidas, 244 trabalhados, saldo −206, incompleto',
  (select (batidas_validas, trabalhado_minutos, saldo_minutos, situacao)
     = (3::smallint, 244, -206, 'incompleto'::text) from d where data = '2026-09-19'));
select teste.ok('12/09: ausente, saldo −450',
  (select (batidas_validas, trabalhado_minutos, saldo_minutos, situacao)
     = (0::smallint, 0, -450, 'ausente'::text) from d where data = '2026-09-12'));
select teste.ok('13/09 (folga): 3 batidas, 120 trabalhados, saldo +120, incompleto',
  (select (batidas_validas, trabalhado_minutos, saldo_minutos, situacao, previsto_minutos)
     = (3::smallint, 120, 120, 'incompleto'::text, 0) from d where data = '2026-09-13'));
select teste.ok('dia de folga sem batida: situação folga, saldo 0',
  (select (situacao, saldo_minutos) = ('folga'::text, 0) from d where data = '2026-09-14'));
select teste.ok('dia atual (06/10): em_andamento, não encerrado',
  (select (situacao, encerrado, saldo_minutos) = ('em_andamento'::text, false, 0) from d where data = '2026-10-06'));
select teste.ok('dias futuros não são apurados', not exists (select 1 from d where data > '2026-10-06'));

select teste.ok('alarmes do vetor §7.6 (sem atraso: desligado na empresa)',
  (select array_agg(data::text || ' ' || tipo || ' ' || batida_esperada order by data, tipo)
     from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
      and data >= '2026-09-12' and status = 'aberto')
  = array['2026-09-12 sem_batida_dia_escalado ', '2026-09-13 batidas_impares ', '2026-09-19 batida_faltando volta_intervalo']);
select teste.ok('detalhe do alarme de batida faltando',
  (select detalhe from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
      and tipo = 'batida_faltando') = 'Faltou a volta do intervalo (21:30)');
select teste.ok('horario_previsto da volta do intervalo = 21:30 local',
  (select horario_previsto from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
      and tipo = 'batida_faltando') = '2026-09-19 21:30-03');
select teste.ok('detalhe sem batida em dia de escala',
  (select detalhe from public.ponto_alarmes where tipo = 'sem_batida_dia_escalado' and data = '2026-09-12'
      and funcionario_id = 'e2000000-0000-4000-8000-000000000301') = 'Nenhuma batida em dia de escala (17:00–01:00)');
select teste.ok('detalhe de batidas ímpares', (select detalhe from public.ponto_alarmes where tipo = 'batidas_impares'
      and funcionario_id = 'e2000000-0000-4000-8000-000000000301') = '3 batidas (número ímpar)');
select teste.ok('ponto_dias.alarmes_abertos', (select alarmes_abertos from public.ponto_dias
   where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-19') = 1);

-- reapurar é idempotente (mesmos dados, mesmos alarmes, sem duplicar)
select public.ponto_apurar('e2000000-0000-4000-8000-000000000301', '2026-09-12', '2026-10-06');
select teste.ok('reapuração idempotente: 3 alarmes abertos no período', (select count(*) from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data >= '2026-09-12' and status = 'aberto') = 3);
select teste.ok('sem_batida de 19/09 (gerado antes das batidas chegarem) foi resolvido automaticamente',
  (select (status, resolvido_automaticamente) = ('resolvido'::text, true) from public.ponto_alarmes
    where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-19' and tipo = 'sem_batida_dia_escalado'));
select teste.ok('reapuração idempotente: mesmos dias', (select count(*) from public.ponto_dias
   where funcionario_id = 'e2000000-0000-4000-8000-000000000301') = 36);

-- alarme de atraso ligado (gatilho da empresa reapura 31 dias)
update public.empresas set ponto_alarme_atraso = true where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('atraso ligado → alarme de atraso em 26/09',
  (select (minutos, detalhe, batida_esperada) = (20, 'Entrada 17:20 (20 min de atraso)'::text, 'entrada'::text)
     from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and tipo = 'atraso'));
select teste.ok('atraso de 2 min (≤ tolerância 5) não gera alarme',
  not exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
                and tipo = 'atraso' and data <> '2026-09-26'));
update public.empresas set ponto_alarme_atraso = false where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('atraso desligado → alarme resolvido automaticamente',
  (select (status, resolvido_automaticamente) = ('resolvido'::text, true)
     from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and tipo = 'atraso'));

-- janela de duplicidade 0 → 17:21 passa a valer (5 batidas, ímpar)
update public.empresas set ponto_janela_duplicada_minutos = 0 where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('janela 0: 5 batidas válidas e alarme ímpar em 26/09',
  (select batidas_validas from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
      and data = '2026-09-26') = 5
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
                and data = '2026-09-26' and tipo = 'batidas_impares' and status = 'aberto'));
update public.empresas set ponto_janela_duplicada_minutos = 2 where id = 'e2000000-0000-4000-8000-00000000000a';
select teste.ok('janela 2 de novo: alarme ímpar resolvido', (select status from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-26' and tipo = 'batidas_impares') = 'resolvido');

-- batida duplicada exatamente no limite (2 min) NÃO é duplicada
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000302', 'manual', '2026-10-03 17:00-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000302', 'manual', '2026-10-03 17:01:59-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000302', 'manual', '2026-10-03 17:03:59-03', 't');
select teste.ok('duplicada: < 2 min da última válida (17:01:59) e ≥ 2 min (17:03:59) vale',
  (select (batidas_validas, batidas_duplicadas) = (2::smallint, 1::smallint)
     from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000302', '2026-10-03')));

-- virada do dia: 04:59 ainda é o dia anterior; 05:00 já é o novo dia
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', '2026-10-04 04:59:59-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', '2026-10-04 05:00:00-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', '2026-10-03 23:59:00-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', '2026-10-04 00:00:00-03', 't');
select teste.ok('virada 05:00: 04:59:59 → sábado; 05:00 → domingo; meia-noite não vira o dia',
  (select array_agg(data_trabalho::text order by instante) from public.ponto_batidas
    where funcionario_id = 'e2000000-0000-4000-8000-000000000303')
  = array['2026-10-03', '2026-10-03', '2026-10-03', '2026-10-04']);

-- fuso por empresa: o mesmo instante em SP e em Manaus (UTC−4) cai em dias diferentes
select teste.ok('fuso: 08:30Z = 05:30 em SP (dia 04) e 04:30 em Manaus (dia 03)',
  public.dia_de_trabalho('2026-10-04 08:30:00Z', 'e2000000-0000-4000-8000-00000000000a') = '2026-10-04'
  and public.dia_de_trabalho('2026-10-04 08:30:00Z', 'e2000000-0000-4000-8000-00000000000b') = '2026-10-03');
-- escala de Manaus: 09:00 local = 13:00Z
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000b', 'e2000000-0000-4000-8000-000000000391', 'manual', '2026-10-05 13:00:00Z', 't'),
  ('e2000000-0000-4000-8000-00000000000b', 'e2000000-0000-4000-8000-000000000391', 'manual', '2026-10-05 21:00:00Z', 't');
select teste.ok('Manaus: entrada esperada 09:00 local = 13:00Z; 480 trabalhados; completo; sem atraso',
  (select (esperadas -> 0 ->> 'batida', (esperadas -> 0 ->> 'instante')::timestamptz, trabalhado_minutos, situacao, atraso_minutos)
     = ('entrada'::text, '2026-10-05 13:00:00Z'::timestamptz, 480, 'completo'::text, 0)
     from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000391', '2026-10-05')));
-- mudar o fuso da empresa recalcula data_trabalho das batidas
update public.empresas set fuso = 'America/Sao_Paulo' where id = 'e2000000-0000-4000-8000-00000000000b';
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000b', 'e2000000-0000-4000-8000-000000000391', 'manual', '2026-10-02 08:30:00Z', 't');
select teste.ok('instante 08:30Z em SP → dia 02', (select data_trabalho from public.ponto_batidas
   where instante = '2026-10-02 08:30:00Z') = '2026-10-02');
update public.empresas set fuso = 'America/Manaus' where id = 'e2000000-0000-4000-8000-00000000000b';
select teste.ok('após trocar o fuso para Manaus a mesma batida vai para o dia 01', (select data_trabalho from public.ponto_batidas
   where instante = '2026-10-02 08:30:00Z') = '2026-10-01');

-- sem escala vigente: sem_escala; batidas viram hora extra
select teste.ok('antes de vigorar a jornada (agosto): sem_escala',
  (select (situacao, previsto_minutos) = ('sem_escala'::text, 0)
     from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000301', '2026-08-15')));

-- fora do vínculo
update public.funcionarios set data_desligamento = '2026-09-20' where id = 'e2000000-0000-4000-8000-000000000301';
select teste.ok('desligamento: dias após o vínculo saem de ponto_dias',
  not exists (select 1 from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data > '2026-09-20')
  and exists (select 1 from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-19'));
select teste.ok('fora do vínculo: ponto_calcular_dia sinaliza', (select fora_do_vinculo
   from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000301', '2026-10-03')));
update public.funcionarios set data_desligamento = null where id = 'e2000000-0000-4000-8000-000000000301';
select teste.ok('religado: 03/10 volta a ser apurado', exists (select 1 from public.ponto_dias
   where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03' and situacao = 'completo'));

-- abono da empresa (feriado) → abonado, sem alarme, saldo 0
select teste.como('b2.ger.a@teste.local');
select teste.ok('abonar 12/09 para a empresa toda', public.ponto_abonar('2026-09-12', '2026-09-12', 'feriado', 'Feriado municipal') = 1);
select teste.como_dono();
select teste.ok('abonado: situação abonado, saldo 0, alarme sem batida resolvido',
  (select (situacao, saldo_minutos, abono_tipo) = ('abonado'::text, 0, 'feriado'::text) from public.ponto_dias
    where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-12')
  and (select status from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
         and data = '2026-09-12' and tipo = 'sem_batida_dia_escalado') = 'resolvido');
-- abono do funcionário prevalece sobre o da empresa
insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000301', '2026-09-12', 'atestado');
select teste.ok('abono do funcionário prevalece', (select abono_tipo
   from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000301', '2026-09-12')) = 'atestado');
select teste.como('b2.ger.a@teste.local');
select public.ponto_remover_abono((select id from public.ponto_abonos where funcionario_id is null
                                    and empresa_id = 'e2000000-0000-4000-8000-00000000000a' and data = '2026-09-12'));
select public.ponto_remover_abono((select id from public.ponto_abonos
                                    where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-12'));
select teste.como_dono();
select teste.ok('abono removido: ausente de novo e alarme reaberto',
  (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-12') = 'ausente'
  and (select status from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301'
         and data = '2026-09-12' and tipo = 'sem_batida_dia_escalado') = 'aberto');

-- espelho e ponto do dia (leitura)
select teste.como('b2.lei.a@teste.local');
select teste.ok('espelho: dias no período (vínculo) com batidas/esperadas/alarmes',
  (select count(*) from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-09-19', '2026-09-19')) = 1
  and (select (jsonb_array_length(batidas), jsonb_array_length(esperadas), alarmes -> 0 ->> 'tipo', dia_semana, jornada_nome)
              = (3, 4, 'batida_faltando'::text, 6::smallint, 'Salão noite b2'::text)
         from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-09-19', '2026-09-19')));
select teste.ok('espelho marca a batida duplicada',
  (select (batidas -> 1 ->> 'duplicada')::boolean
     from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-09-26', '2026-09-26')));
select teste.erro('espelho: máx. 62 dias', $$select * from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-01-01', '2026-03-31')$$,
  'Período máximo de 62 dias', '22023');
select teste.erro('espelho: período invertido', $$select * from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-02-01', '2026-01-31')$$,
  'Período inválido', '22023');
select teste.ok('ponto do dia: 5 funcionários de A, ordenados por nome',
  (select array_agg(funcionario_nome) from public.ponto_dia_empresa('2026-10-03'))
  = array['Ana Souza', 'Bruno Lima', 'Carla Dias', 'Davi Rocha', 'Eva Martins']);
select teste.ok('ponto do dia: dados ao vivo da Ana', (select (situacao, trabalhado_minutos, jsonb_array_length(batidas))
   = ('completo'::text, 459, 4) from public.ponto_dia_empresa('2026-10-03') where funcionario_nome = 'Ana Souza'));
select teste.ok('ponto do dia padrão = dia atual (em andamento)',
  (select bool_and(situacao = 'em_andamento') from public.ponto_dia_empresa()));
select teste.erro('leitura de A não lê espelho de B', $$select * from public.ponto_espelho('e2000000-0000-4000-8000-000000000391', '2026-10-01', '2026-10-05')$$,
  'Sem permissão', '42501');
select teste.erro('leitura de A não lê ponto do dia de B', $$select * from public.ponto_dia_empresa(null, 'e2000000-0000-4000-8000-00000000000b')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não reapura', $$select public.ponto_reapurar('2026-10-01', '2026-10-05')$$, 'Sem permissão', '42501');
select teste.como('b2.master@teste.local');
select teste.erro('master sem p_empresa', $$select * from public.ponto_dia_empresa()$$, 'Informe a empresa', '22023');
select teste.ok('master lê qualquer empresa', (select count(*) from public.ponto_dia_empresa('2026-10-05', 'e2000000-0000-4000-8000-00000000000b')) = 1);
select teste.como('b2.ger.a@teste.local');
select teste.ok('gerente reapura a empresa', public.ponto_reapurar('2026-10-01', '2026-10-05') > 0);
select teste.erro('reapurar: máx. 93 dias', $$select public.ponto_reapurar('2026-01-01', '2026-10-05')$$, 'Período máximo de 93 dias', '22023');

-- tabelas de ponto são só leitura para authenticated
select teste.erro('authenticated não insere em ponto_dias', $$insert into public.ponto_dias (funcionario_id, data, empresa_id, situacao, encerrado)
  values ('e2000000-0000-4000-8000-000000000301', '2026-01-02', 'e2000000-0000-4000-8000-00000000000a', 'folga', true)$$, null, '42501');
select teste.erro('authenticated não altera batidas', $$update public.ponto_batidas set desconsiderada = true$$, null, '42501');
select teste.como_dono();

rollback;
