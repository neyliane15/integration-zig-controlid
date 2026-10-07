-- 22_ponto_alarmes.sql (b2) — alarmes: qual batida faltou (combinação de menor distância, empate lexicográfico),
-- ímpares, sem batida, atraso no dia corrente, justificar/reabrir, resolução e reabertura automáticas, permissões.
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

create temp table bat (f uuid, i timestamptz) on commit drop;
-- Bruno (302) — sáb 03/10: falta a entrada (21:00, 21:30, 01:00)
insert into bat values ('e2000000-0000-4000-8000-000000000302', '2026-10-03 21:00-03'),
                       ('e2000000-0000-4000-8000-000000000302', '2026-10-03 21:31-03'),
                       ('e2000000-0000-4000-8000-000000000302', '2026-10-04 01:00-03');
-- Bruno — sáb 26/09: 19:00 e 23:15 → empate entre {1,3},{1,4},{2,3},{2,4}: escolhe {1,3} → faltam saída p/ intervalo e saída
insert into bat values ('e2000000-0000-4000-8000-000000000302', '2026-09-26 19:00-03'),
                       ('e2000000-0000-4000-8000-000000000302', '2026-09-26 23:15-03');
-- Bruno — sáb 19/09: 5 batidas (ímpar acima do esperado)
insert into bat select 'e2000000-0000-4000-8000-000000000302', x::timestamptz from unnest(array[
  '2026-09-19 17:00-03', '2026-09-19 21:00-03', '2026-09-19 21:30-03', '2026-09-20 01:00-03', '2026-09-20 02:00-03']) x;
-- Bruno — dom 27/09 (folga): 1 batida
insert into bat values ('e2000000-0000-4000-8000-000000000302', '2026-09-27 15:00-03');
-- Paolo (B, Manaus, 09–17 seg–sex) — seg 05/10: só 16:50 → falta a entrada
insert into bat values ('e2000000-0000-4000-8000-000000000391', '2026-10-05 16:50-04');
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
select f.empresa_id, bat.f, 'manual', bat.i, 'teste' from bat join public.funcionarios f on f.id = bat.f;
select public.ponto_apurar('e2000000-0000-4000-8000-000000000302', '2026-09-19', '2026-10-06');
select public.ponto_apurar('e2000000-0000-4000-8000-000000000391', '2026-10-05', '2026-10-05');

create temp view al as
  select data, tipo, batida_esperada, detalhe, status, id, funcionario_id from public.ponto_alarmes where status <> 'resolvido';

select teste.ok('03/10: falta a entrada', (select array_agg(batida_esperada || ':' || detalhe) from al
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03')
   = array['entrada:Faltou a entrada (17:00)']);
select teste.ok('26/09: empate → combinação lexicograficamente menor (faltam saída p/ intervalo e saída)',
  (select array_agg(batida_esperada order by batida_esperada) from al
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-26')
  = array['saida', 'saida_intervalo']);
select teste.ok('26/09: textos dos alarmes', (select array_agg(detalhe order by detalhe) from al
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-26')
  = array['Faltou a saída (01:00)', 'Faltou a saída para o intervalo (21:00)']);
select teste.ok('19/09: 5 batidas → batidas_impares', (select array_agg(tipo || ':' || detalhe) from al
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares')
  = array['batidas_impares:5 batidas (número ímpar)']);
select teste.ok('27/09 (folga): 1 batida → batidas_impares', (select detalhe from al
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-27' and tipo = 'batidas_impares') = '1 batida (número ímpar)');
select teste.ok('dia sem escala nem batida não gera alarme', not exists (select 1 from al
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-28'));
select teste.ok('Manaus (2 batidas esperadas): só 16:50 → falta a entrada (09:00 local)',
  (select array_agg(batida_esperada || ':' || detalhe) from al where funcionario_id = 'e2000000-0000-4000-8000-000000000391'
     and data = '2026-10-05') = array['entrada:Faltou a entrada (09:00)']);
-- (revisão 2) restrito às empresas do teste: a carga demo usa o relógio REAL e, depois das 05:00 de 07/10, tem alarmes em 06/10
select teste.ok('dia corrente sem alarmes de falta', not exists (select 1 from public.ponto_alarmes where data = '2026-10-06'
  and empresa_id in ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-00000000000b')));

-- resolução/reabertura automáticas
select teste.como('b2.ger.a@teste.local');
select public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000302', '2026-10-03 16:59-03', 'Esqueceu de bater a entrada');
select teste.ok('incluir a entrada resolve o alarme automaticamente',
  (select (status, resolvido_automaticamente) = ('resolvido'::text, true) from public.ponto_alarmes
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03' and batida_esperada = 'entrada'));
select teste.ok('dia ficou completo', (select (situacao, alarmes_abertos) = ('completo'::text, 0::smallint) from public.ponto_dias
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03'));
select public.ponto_desconsiderar_batida((select id from public.ponto_batidas
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and instante = '2026-10-03 16:59-03'), 'Incluída por engano');
select teste.ok('desconsiderar a batida reabre o mesmo alarme (mesmo id)',
  (select (status, resolvido_automaticamente, resolvido_em is null) = ('aberto'::text, false, true) from public.ponto_alarmes
    where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03' and batida_esperada = 'entrada')
  and (select count(*) from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000302'
         and data = '2026-10-03' and tipo = 'batida_faltando') = 1);

-- justificar / reabrir
select teste.erro('justificativa obrigatória', $$select public.ponto_justificar_alarme((select id from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares'), '  ')$$, 'Informe a justificativa', '22023');
select teste.erro('alarme inexistente', $$select public.ponto_justificar_alarme(gen_random_uuid(), 'x')$$, 'Alarme não encontrado', 'P0002');
select public.ponto_justificar_alarme((select id from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares'), 'Fez hora extra autorizada');
select teste.ok('justificado: status, justificativa, autor e data', (select (status, justificativa, justificado_por, justificado_em)
   = ('justificado'::text, 'Fez hora extra autorizada'::text, 'e2000000-0000-4000-8000-000000000a02'::uuid, '2026-10-06 12:00-03'::timestamptz)
   from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares'));
select teste.ok('justificar não altera saldo e zera alarmes_abertos do dia', (select (saldo_minutos, alarmes_abertos) = (0, 0::smallint)
   from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19'));
select public.ponto_reapurar('2026-09-19', '2026-09-19', 'e2000000-0000-4000-8000-000000000302');
select teste.ok('reapurar mantém justificado', (select status from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares') = 'justificado');
-- some a 5ª batida: o alarme não é mais esperado, mas justificado continua justificado
select public.ponto_desconsiderar_batida((select id from public.ponto_batidas
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and instante = '2026-09-20 02:00-03'), 'Batida acidental');
select teste.ok('justificado que deixa de ser esperado continua justificado', (select status from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares') = 'justificado');
select public.ponto_reabrir_alarme((select id from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares'));
select teste.ok('reabrir alarme que não é mais esperado: a apuração o resolve', (select (status, justificativa) is not distinct from ('resolvido'::text, null::text)
   from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-19' and tipo = 'batidas_impares'));
select public.ponto_justificar_alarme((select id from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-27' and tipo = 'batidas_impares'), 'Veio buscar o uniforme');
select public.ponto_reabrir_alarme((select id from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-27' and tipo = 'batidas_impares'));
select teste.ok('reabrir alarme ainda esperado: volta a aberto e limpa a justificativa',
  (select (status, justificativa, justificado_por, justificado_em) is not distinct from ('aberto'::text, null::text, null::uuid, null::timestamptz)
     from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-27' and tipo = 'batidas_impares')
  and (select alarmes_abertos from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-09-27') = 1);

-- atraso vale também no dia corrente
select teste.como_dono();
update public.empresas set ponto_alarme_atraso = true where id = 'e2000000-0000-4000-8000-00000000000b';
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000b', 'e2000000-0000-4000-8000-000000000391', 'manual', '2026-10-06 09:23-04', 't');
select public.ponto_apurar('e2000000-0000-4000-8000-000000000391', '2026-10-06', '2026-10-06');
select teste.ok('atraso no dia corrente (em andamento): alarme com 23 min e horário previsto',
  (select (tipo, batida_esperada, minutos, detalhe, horario_previsto)
     = ('atraso'::text, 'entrada'::text, 23, 'Entrada 09:23 (23 min de atraso)'::text, '2026-10-06 09:00-04'::timestamptz)
     from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000391' and data = '2026-10-06'));
select teste.ok('dia corrente: só o atraso (sem ímpar/falta)', (select count(*) from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000391' and data = '2026-10-06') = 1);

-- permissões e isolamento
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura vê alarmes da própria empresa', teste.contar('select * from public.ponto_alarmes') > 0
  and teste.contar($$select * from public.ponto_alarmes where empresa_id <> 'e2000000-0000-4000-8000-00000000000a'$$) = 0);
select teste.erro('leitura não justifica', $$select public.ponto_justificar_alarme((select id from public.ponto_alarmes limit 1), 'x')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não reabre', $$select public.ponto_reabrir_alarme((select id from public.ponto_alarmes limit 1))$$,
  'Sem permissão', '42501');
select teste.erro('leitura não altera alarmes direto', $$update public.ponto_alarmes set status = 'resolvido'$$, null, '42501');
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B não vê alarmes de A', teste.contar($$select * from public.ponto_alarmes
   where empresa_id = 'e2000000-0000-4000-8000-00000000000a'$$) = 0);
select teste.como_dono();
create temp table alarme_a on commit drop as select id from public.ponto_alarmes
 where empresa_id = 'e2000000-0000-4000-8000-00000000000a' limit 1;
grant select on alarme_a to authenticated;
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não justifica alarme de A', $$select public.ponto_justificar_alarme((select id from alarme_a), 'x')$$,
  'Sem permissão', '42501');
select teste.como(null);
select teste.erro('anon não lê alarmes', $$select * from public.ponto_alarmes$$, null, '42501');
select teste.erro('anon não chama RPC', $$select public.ponto_justificar_alarme(gen_random_uuid(), 'x')$$, null, '42501');
select teste.como_dono();

rollback;
