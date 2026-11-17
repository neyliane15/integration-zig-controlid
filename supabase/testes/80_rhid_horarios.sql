-- 80_rhid_horarios.sql — previsto do dia vindo do RHiD (adendo RHiD §R.9): ingestao_rhid_horarios grava por CPF ligado,
-- só o que mudou, reapura; ponto_calcular_dia usa o previsto do RHiD no lugar da jornada/escala
-- (saldo = trabalhado − previsto; folga/feriado = previsto 0; dia previsto sem batida = ausente, −previsto).
begin;
set local app.agora = '2026-11-17 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e8000000-0000-4000-8000-00000000000a', 'Teste Horários RHiD', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e8000000-0000-4000-8000-000000000a01', 'rhidh.ger@teste.local', '{"nome":"Gerente"}');
update public.perfis set papel = 'gerente', empresa_id = 'e8000000-0000-4000-8000-00000000000a'
 where id = 'e8000000-0000-4000-8000-000000000a01';
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, pontos_comissao, data_admissao) values
  ('e8000000-0000-4000-8000-000000000301', 'e8000000-0000-4000-8000-00000000000a', 'ALEPH', 'Garçom', '52998224725', 1, '2026-01-01'),
  ('e8000000-0000-4000-8000-000000000302', 'e8000000-0000-4000-8000-00000000000a', 'Sem vínculo', 'Garçom', null, 1, '2026-01-01');
insert into public.integracoes (id, empresa_id, tipo, nome)
values ('e8000000-0000-4000-8000-000000000101', 'e8000000-0000-4000-8000-00000000000a', 'rhid', 'Relógio de ponto (RHiD)');

select teste.como_servico();
select public.ingestao_rhid_pessoas('e8000000-0000-4000-8000-000000000101', $$[
  {"id": 123, "cpf": 52998224725, "name": "ALEPH SOUZA CORDOVIL"},
  {"id": 124, "cpf": 11144477735, "name": "PESSOA SEM FUNCIONARIO"}]$$);
select teste.ok('vinculados: só o CPF ligado', public.ingestao_rhid_vinculados('e8000000-0000-4000-8000-000000000101') = '["52998224725"]');

-- batidas do ALEPH (iguais às do RHiD): 11/11 08:07 11:18 12:22 15:52 (6h41); 15/11 08:10 19:02 (10h52, feriado);
-- 16/11 11:09 (folga); 14/11 nenhuma
select public.ingestao_rhid_batidas('e8000000-0000-4000-8000-000000000101', '2', $$[
  {"nsr": 1, "instante": "2026-11-11T08:07:00-03:00", "cpf": "52998224725"},
  {"nsr": 2, "instante": "2026-11-11T11:18:00-03:00", "cpf": "52998224725"},
  {"nsr": 3, "instante": "2026-11-11T12:22:00-03:00", "cpf": "52998224725"},
  {"nsr": 4, "instante": "2026-11-11T15:52:00-03:00", "cpf": "52998224725"},
  {"nsr": 5, "instante": "2026-11-15T08:10:00-03:00", "cpf": "52998224725"},
  {"nsr": 6, "instante": "2026-11-15T19:02:00-03:00", "cpf": "52998224725"},
  {"nsr": 7, "instante": "2026-11-16T11:09:00-03:00", "cpf": "52998224725"}]$$);
select teste.ok('sem previsto do RHiD: 11/11 sem escala, saldo = trabalhado',
  (select situacao = 'sem_escala' or (previsto_minutos = 0 and saldo_minutos = 401)
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-11'));

create temp table r_h (n int, r jsonb);
insert into r_h select 1, public.ingestao_rhid_horarios('e8000000-0000-4000-8000-000000000101', $$[
  {"cpf": 52998224725, "data": "2026-11-11", "previsto_minutos": 440, "horarios": ["08:00","13:00","13:30","15:50"], "folga": false, "saldo_minutos": -39},
  {"cpf": 52998224725, "data": "2026-11-14", "previsto_minutos": 440, "horarios": ["08:00","13:00","13:30","15:50"], "folga": false},
  {"cpf": 52998224725, "data": "2026-11-15", "previsto_minutos": 440, "horarios": [], "folga": false, "feriado": "Proclamação da República"},
  {"cpf": 52998224725, "data": "2026-11-16", "previsto_minutos": 440, "horarios": ["08:00","13:00","13:30","15:50"], "folga": true},
  {"cpf": 11144477735, "data": "2026-11-11", "previsto_minutos": 440, "horarios": []},
  {"cpf": 52998224725, "data": "xx", "previsto_minutos": 440},
  {"cpf": 52998224725, "data": "2026-11-12", "previsto_minutos": 5000},
  7]$$);
select teste.ok('ingestão: 4 gravados, 1 sem funcionário, 3 inválidos',
  (select r ->> 'gravados' = '4' and r ->> 'sem_funcionario' = '1' and r ->> 'invalidos' = '3' and r ->> 'lidos' = '8'
     from r_h where n = 1));
select teste.ok('feriado e folga gravados com previsto 0',
  (select count(*) = 2 from public.ponto_previsto_externo
    where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and previsto_minutos = 0
      and ((data = '2026-11-15' and feriado is not null) or (data = '2026-11-16' and folga))));
select teste.ok('cursor.horarios_em gravado',
  (select cursor ? 'horarios_em' from public.integracoes where id = 'e8000000-0000-4000-8000-000000000101'));

select teste.ok('11/11: previsto 7h20, trabalhado 6h41, saldo −0h39, completo (4 batidas esperadas)',
  (select previsto_minutos = 440 and trabalhado_minutos = 401 and saldo_minutos = -39 and situacao = 'completo'
          and batidas_esperadas = 4
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-11'));
select teste.ok('14/11: previsto sem batida → ausente, saldo −7h20',
  (select previsto_minutos = 440 and saldo_minutos = -440 and situacao = 'ausente'
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-14'));
select teste.ok('14/11: alarme de dia escalado sem batida',
  exists (select 1 from public.ponto_alarmes where funcionario_id = 'e8000000-0000-4000-8000-000000000301'
             and data = '2026-11-14' and tipo = 'sem_batida_dia_escalado' and status = 'aberto'));
select teste.ok('15/11 feriado: previsto 0, trabalhado 10h52 todo positivo',
  (select previsto_minutos = 0 and trabalhado_minutos = 652 and saldo_minutos = 652
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-15'));
select teste.ok('16/11 folga com batida solta: previsto 0, saldo 0',
  (select previsto_minutos = 0 and saldo_minutos = 0
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-16'));

-- repetir igual não regrava; mudar um dia regrava só ele
insert into r_h select 2, public.ingestao_rhid_horarios('e8000000-0000-4000-8000-000000000101', $$[
  {"cpf": 52998224725, "data": "2026-11-11", "previsto_minutos": 440, "horarios": ["08:00","13:00","13:30","15:50"], "folga": false, "saldo_minutos": -39},
  {"cpf": 52998224725, "data": "2026-11-14", "previsto_minutos": 440, "horarios": ["08:00","13:00","13:30","15:50"], "folga": true}]$$);
select teste.ok('reenvio: 1 igual, 1 alterado',
  (select r ->> 'gravados' = '1' and r ->> 'iguais' = '1' from r_h where n = 2));
select teste.ok('14/11 virou folga: situação folga, saldo 0, alarme resolvido',
  (select previsto_minutos = 0 and saldo_minutos = 0 and situacao = 'folga' and alarmes_abertos = 0
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-14'));

-- tolerância do horário do RHiD (CLT 10/10) e pessoa sem horário (apaga o previsto)
insert into r_h select 3, public.ingestao_rhid_horarios('e8000000-0000-4000-8000-000000000101', $$[
  {"cpf": 52998224725, "data": "2026-11-11", "previsto_minutos": 405, "horarios": ["08:00","13:00","13:30","15:15"], "saldo_minutos": 0,
   "tolerancia_extra_minutos": 10, "tolerancia_falta_minutos": 10},
  {"cpf": 52998224725, "data": "2026-11-15", "sem_horario": true}]$$);
select teste.ok('3ª ingestão: 1 gravado, 1 apagado', (select r ->> 'gravados' = '1' and r ->> 'apagados' = '1' from r_h where n = 3));
select teste.ok('11/11: trabalhado 6h41 vs previsto 6h45 (−4 min ≤ 10) → saldo 0',
  (select previsto_minutos = 405 and saldo_minutos = 0
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-11'));
select teste.ok('15/11 sem horário no RHiD: previsto apagado, volta a valer jornada/escala (sem escala: saldo = trabalhado)',
  not exists (select 1 from public.ponto_previsto_externo where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-15')
  and (select previsto_minutos = 0 and saldo_minutos = 652
         from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-15'));

-- saída repetida vale a última; entrada repetida vale a primeira (janela 5 min)
select teste.como_dono();
update public.empresas set ponto_janela_duplicada_minutos = 5 where id = 'e8000000-0000-4000-8000-00000000000a';
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', 'manual', '2026-11-10 14:11-03', 't'),
  ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', 'manual', '2026-11-10 14:13-03', 't'),
  ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', 'manual', '2026-11-10 15:08-03', 't'),
  ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', 'manual', '2026-11-10 15:10-03', 't'),
  ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', 'manual', '2026-11-10 18:51-03', 't');
select public.ponto_apurar('e8000000-0000-4000-8000-000000000301', '2026-11-10', '2026-11-10');
select teste.ok('10/11: 14:11 (14:13 duplicada), 15:10 (15:08 duplicada), 18:51 ímpar → trabalhado 59',
  (select batidas_validas = 3 and batidas_duplicadas = 2 and trabalhado_minutos = 59
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-10'));
select teste.ok('espelho marca as duplicadas certas',
  (select array_agg(to_char(x.instante at time zone 'America/Sao_Paulo', 'HH24:MI') order by x.instante)
     from public.ponto_calcular_dia('e8000000-0000-4000-8000-000000000301', '2026-11-10') c,
          jsonb_to_recordset(c.batidas) x(instante timestamptz, duplicada boolean)
    where x.duplicada) = array['14:13', '15:08']);

-- abono do dia prevalece sobre o previsto do RHiD
select teste.como_dono();
insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo)
values ('e8000000-0000-4000-8000-00000000000a', 'e8000000-0000-4000-8000-000000000301', '2026-11-11', 'atestado', 'teste');
select public.ponto_apurar('e8000000-0000-4000-8000-000000000301', '2026-11-11', '2026-11-11');
select teste.ok('abono prevalece: 11/11 abonado, previsto 0',
  (select situacao = 'abonado' and previsto_minutos = 0
     from public.ponto_dias where funcionario_id = 'e8000000-0000-4000-8000-000000000301' and data = '2026-11-11'));

-- permissões
select teste.como('rhidh.ger@teste.local');
select teste.ok('gerente lê o previsto da empresa',
  (select count(*) = 3 from public.ponto_previsto_externo));
select teste.erro('gerente não chama a ingestão',
  $$select public.ingestao_rhid_horarios('e8000000-0000-4000-8000-000000000101', '[]')$$, 'permission denied');
select teste.erro('gerente não grava previsto direto',
  $$insert into public.ponto_previsto_externo (funcionario_id, data, empresa_id, previsto_minutos)
    values ('e8000000-0000-4000-8000-000000000302', '2026-11-11', 'e8000000-0000-4000-8000-00000000000a', 1)$$,
  'permission denied');
rollback;
