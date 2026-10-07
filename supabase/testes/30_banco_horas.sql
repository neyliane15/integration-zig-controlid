-- 30_banco_horas.sql (b2) — saldo (com saldo inicial), lançamentos, extrato, resumo e permissões.
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

-- Ana (301): vetor do §7.6 + sábado 05/09 sem batidas (escala vigente desde 01/09)
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
select 'e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000301', 'manual', i::timestamptz, 'teste'
  from unnest(array[
    '2026-10-03 16:58-03', '2026-10-03 21:02-03', '2026-10-03 21:29-03', '2026-10-04 01:04-03',
    '2026-09-26 17:20-03', '2026-09-26 17:21-03', '2026-09-26 21:00-03', '2026-09-26 21:30-03', '2026-09-27 01:00-03',
    '2026-09-19 16:58-03', '2026-09-19 21:02-03', '2026-09-20 01:05-03',
    '2026-09-13 10:00-03', '2026-09-13 12:00-03', '2026-09-13 13:00-03']) i;
select public.ponto_apurar('e2000000-0000-4000-8000-000000000301', '2026-09-01', '2026-10-06');

select teste.como('b2.lei.a@teste.local');
-- dias encerrados: 05/09 −450, 12/09 −450, 13/09 +120, 19/09 −206, 26/09 −20, 03/10 0
select teste.ok('saldo sem lançamentos (padrão: até ontem) = −1006',
  public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301') = -1006);
select teste.ok('saldo até 13/09 = −780', public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-09-13') = -780);
select teste.ok('dia corrente não entra (06/10 em andamento)',
  public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-10-06') = -1006);
select teste.erro('leitura não lança', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-20', 'ajuste', 30, 'x')$$,
  'Sem permissão', '42501');

select teste.como('b2.ger.a@teste.local');
select teste.erro('gerente não lança saldo inicial', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-13', 'saldo_inicial', 60, 'Migração')$$,
  'Sem permissão', '42501');
select teste.erro('motivo obrigatório', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-20', 'ajuste', 30, ' ')$$,
  'Informe o motivo', '22023');
select teste.erro('tipo inválido', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-20', 'bonus', 30, 'x')$$,
  null, '22023');
select teste.ok('gerente lança ajuste', public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-20', 'ajuste', 30, 'Reunião fora do horário') is not null);
select teste.ok('gerente lança pagamento', public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-10-05', 'pagamento', -10, 'Pago em folha') is not null);
select teste.ok('lançamento registra o nome do autor', (select (criado_por_nome, criado_por) = ('Gerente A'::text, 'e2000000-0000-4000-8000-000000000a02'::uuid)
   from public.banco_horas_lancamentos where tipo = 'ajuste' and funcionario_id = 'e2000000-0000-4000-8000-000000000301'));

select teste.como('b2.adm.a@teste.local');
select teste.ok('administrador lança saldo inicial', public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-13', 'saldo_inicial', 60, 'Saldo do sistema antigo') is not null);
select teste.erro('saldo inicial duplicado na mesma data', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-13', 'saldo_inicial', 10, 'x')$$,
  'Já existe saldo inicial', '23505');
-- a partir de 13/09: 60 + 120 − 206 − 20 + 0 + 30 (ajuste 20/09) − 10 (pagamento 05/10) = −26
select teste.ok('saldo com saldo inicial (conta a partir do próprio dia)', public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301') = -26);
select teste.ok('antes do saldo inicial, vale o histórico antigo', public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-09-12') = -900);
select teste.ok('saldo até 20/09 = 4', public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-09-20') = 4);

create temp table ext on commit drop as
  select row_number() over () as n, * from public.banco_horas_extrato('e2000000-0000-4000-8000-000000000301', '2026-09-12', '2026-09-20');
select teste.ok('extrato: linhas e ordem', (select array_agg(data::text || ' ' || tipo || ' ' || minutos || ' ' || saldo_acumulado order by n) from ext)
  = array['2026-09-11 saldo_anterior -450 -450', '2026-09-12 dia -450 -900', '2026-09-13 saldo_inicial 60 60',
          '2026-09-13 dia 120 180', '2026-09-19 dia -206 -26', '2026-09-20 ajuste 30 4']);
select teste.ok('extrato: último acumulado = saldo da data final',
  (select saldo_acumulado from ext order by n desc limit 1) = public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-09-20'));
select teste.ok('extrato: descrição do dia e referência do lançamento',
  (select descricao from ext where tipo = 'dia' and data = '2026-09-19') = 'Incompleto — trabalhado 4h04 de 7h30'
  and (select (descricao, referencia_id is not null) = ('Reunião fora do horário'::text, true) from ext where tipo = 'ajuste'));
select teste.erro('extrato: máx. 366 dias', $$select * from public.banco_horas_extrato('e2000000-0000-4000-8000-000000000301', '2025-01-01', '2026-09-20')$$,
  'Período máximo de 366 dias', '22023');

select teste.ok('resumo: saldo e saldo do mês (outubro: 03/10 = 0 e pagamento −10)',
  (select (saldo_minutos, saldo_mes_minutos, ultimo_dia_apurado) = (-26::bigint, -10::bigint, '2026-10-05'::date)
     from public.banco_horas_resumo() where funcionario_id = 'e2000000-0000-4000-8000-000000000301'));
select teste.ok('resumo de setembro: saldo −16; mês = movimento desde o saldo inicial, sem ele (120 − 206 − 20 + 30 = −76)',
  (select (saldo_minutos, saldo_mes_minutos) = (-16::bigint, -76::bigint)
     from public.banco_horas_resumo('2026-09-30') where funcionario_id = 'e2000000-0000-4000-8000-000000000301'));
select teste.ok('resumo: só funcionários ativos da empresa', (select count(*) from public.banco_horas_resumo()) = 5);

-- excluir lançamento: só administrador
select teste.como('b2.ger.a@teste.local');
select teste.erro('gerente não exclui lançamento', $$select public.banco_horas_excluir_lancamento((select id from public.banco_horas_lancamentos where tipo = 'pagamento'))$$,
  'Sem permissão', '42501');
select teste.como('b2.adm.a@teste.local');
select public.banco_horas_excluir_lancamento((select id from public.banco_horas_lancamentos where tipo = 'pagamento'
   and funcionario_id = 'e2000000-0000-4000-8000-000000000301'));
select teste.ok('após excluir o pagamento: −16', public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301') = -16);
select teste.erro('excluir inexistente', $$select public.banco_horas_excluir_lancamento(gen_random_uuid())$$, 'Lançamento não encontrado', 'P0002');

-- isolamento
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não lê saldo de A', $$select public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301')$$, 'Sem permissão', '42501');
select teste.erro('admin B não lança para A', $$select public.banco_horas_lancar('e2000000-0000-4000-8000-000000000301', '2026-09-20', 'ajuste', 1, 'x')$$,
  'Sem permissão', '42501');
select teste.ok('admin B não vê lançamentos de A', teste.contar('select * from public.banco_horas_lancamentos') = 0);
select teste.ok('resumo de B só tem B', (select array_agg(funcionario_nome) from public.banco_horas_resumo()) = array['Paolo B2']);
select teste.erro('authenticated não insere lançamento direto', $$insert into public.banco_horas_lancamentos (empresa_id, funcionario_id, data, tipo, minutos, motivo, criado_por_nome)
  values ('e2000000-0000-4000-8000-00000000000b', 'e2000000-0000-4000-8000-000000000391', '2026-10-01', 'ajuste', 1, 'x', 'x')$$, null, '42501');
select teste.como_dono();

rollback;
