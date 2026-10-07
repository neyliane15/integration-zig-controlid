-- 65_painel.sql (b2) — painel_do_dia: formato exato (§10.7), números do dia, ponto ao vivo, tarefas, sincronização e permissões.
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

-- escala de terça (dia atual = ter 06/10) 10:00–18:00 para a jornada de A
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) values ('e2000000-0000-4000-8000-000000000201', 2, '10:00', '18:00');
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000301', 'manual', '2026-10-06 10:05-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000302', 'manual', '2026-10-06 10:00-03', 't'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000302', 'manual', '2026-10-06 11:00-03', 't');
insert into public.ponto_batidas (empresa_id, integracao_id, origem, id_externo, pessoa_externa, instante) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000102', 'controlid_acesso', 'x1', '77', '2026-10-06 09:00-03');
select public.ponto_apurar_empresa('e2000000-0000-4000-8000-00000000000a', '2026-09-26', '2026-10-06');

-- Zig: faturamento e serviço
insert into public.zig_faturamento (empresa_id, loja_id_externo, data_operacao, payment_id, payment_name, valor) values
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-06', 1, 'Crédito', 1000),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-05', 1, 'Crédito', 2000),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-05', 2, 'Pix', 500),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-01', 1, 'Crédito', 7000),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-09-30', 1, 'Crédito', 99999),
  ('e2000000-0000-4000-8000-00000000000b', 'l', '2026-10-06', 1, 'Crédito', 55555);
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, valor_total) values
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-05', 't', 'Tip', 250),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-02', 't', 'Tip', 100),
  ('e2000000-0000-4000-8000-00000000000a', 'l', '2026-10-05', 't', 'Normal', 9999);

-- tarefas: hoje (concluída, atrasada 11:00, no prazo 16:30, cancelada) e uma de ontem em aberto
insert into public.tarefas (empresa_id, data, titulo, status, horario_limite) values
  ('e2000000-0000-4000-8000-00000000000a', '2026-10-06', 'Abrir caixa', 'concluida', '10:00'),
  ('e2000000-0000-4000-8000-00000000000a', '2026-10-06', 'Conferir estoque', 'pendente', '11:00'),
  ('e2000000-0000-4000-8000-00000000000a', '2026-10-06', 'Limpar chopeira', 'em_andamento', '16:30'),
  ('e2000000-0000-4000-8000-00000000000a', '2026-10-06', 'Cancelada', 'cancelada', null),
  ('e2000000-0000-4000-8000-00000000000a', '2026-10-05', 'Fechar caixa ontem', 'pendente', null);

-- sincronização: Zig executando, acesso com solicitação pendente, REP parado com erro
insert into public.sync_execucoes (empresa_id, integracao_id, tipo, gatilho, workflow, status) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000101', 'zig_importar', 'agendado', 'MDG · Zig · Importar', 'executando');
insert into public.sync_solicitacoes (empresa_id, integracao_id, escopo, status) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000102', 'batidas', 'pendente');
update public.integracoes set ultimo_status = 'erro', ultimo_erro = 'Equipamento fora do ar', ultima_execucao_em = '2026-10-06 11:00-03'
 where id = 'e2000000-0000-4000-8000-000000000103';

select teste.como('b2.lei.a@teste.local');
create temp table p on commit drop as select public.painel_do_dia() as j;
select teste.ok('chaves de primeiro nível exatas', (select array_agg(k order by k) from p, jsonb_object_keys(j) k)
  = array['dia_trabalho', 'empresa_id', 'faturamento', 'ontem', 'ponto', 'servico', 'sincronizacao', 'tarefas']);
select teste.ok('empresa e datas', (select (j ->> 'empresa_id', j ->> 'dia_trabalho', j ->> 'ontem')
  = ('e2000000-0000-4000-8000-00000000000a'::text, '2026-10-06'::text, '2026-10-05'::text) from p));
select teste.ok('faturamento hoje/ontem/mês e tem_zig', (select j -> 'faturamento' from p)
  = '{"hoje": 1000, "ontem": 2500, "mes": 10500, "tem_zig": true}'::jsonb);
select teste.ok('serviço ontem/mês (só Tips)', (select j -> 'servico' from p) = '{"ontem": 250, "mes": 350}'::jsonb);
select teste.ok('ponto: chaves exatas', (select array_agg(k order by k) from p, jsonb_object_keys(j -> 'ponto') k)
  = array['alarmes', 'alarmes_abertos', 'batidas_sem_funcionario', 'escalados_hoje', 'presentes_agora']);
select teste.ok('ponto: presentes agora (ímpar) e escalados hoje', (select ((j -> 'ponto' ->> 'presentes_agora')::int, (j -> 'ponto' ->> 'escalados_hoje')::int) = (1, 5) from p));
select teste.ok('ponto: batidas sem funcionário', (select (j -> 'ponto' ->> 'batidas_sem_funcionario')::int from p) = 1);
select teste.ok('ponto: total de alarmes abertos = tabela', (select (j -> 'ponto' ->> 'alarmes_abertos')::int from p)
  = (select count(*) from public.ponto_alarmes where status = 'aberto'));
select teste.ok('ponto: até 5 alarmes, mais recentes primeiro, com nome', (select jsonb_array_length(j -> 'ponto' -> 'alarmes') = 5
   and (j -> 'ponto' -> 'alarmes' -> 0 ->> 'data') >= (j -> 'ponto' -> 'alarmes' -> 4 ->> 'data')
   and (j -> 'ponto' -> 'alarmes' -> 0) ?& array['id', 'funcionario_id', 'funcionario_nome', 'data', 'tipo', 'batida_esperada', 'detalhe'] from p));
select teste.ok('tarefas: total, concluídas, pendentes, atrasadas', (select j -> 'tarefas' from p)
  = '{"total": 3, "concluidas": 1, "pendentes": 2, "atrasadas": 2}'::jsonb);
select teste.ok('sincronização: 3 integrações com status e "executando"', (select jsonb_agg(jsonb_build_array(s ->> 'tipo', s -> 'executando', s ->> 'ultimo_status', s ->> 'ultimo_erro')
   order by s ->> 'tipo') from p, jsonb_array_elements(j -> 'sincronizacao') s)
  = '[["controlid_acesso", true, null, null], ["controlid_rep", false, "erro", "Equipamento fora do ar"], ["zig", true, null, null]]'::jsonb);
select teste.ok('sincronização: chaves exatas e nenhum segredo', (select array_agg(k order by k) from p, jsonb_object_keys(j -> 'sincronizacao' -> 0) k)
  = array['ativa', 'executando', 'integracao_id', 'nome', 'tipo', 'ultimo_erro', 'ultimo_status', 'ultimo_sucesso_em']);

-- relógio na madrugada: 01:30 de quarta ainda é o dia de trabalho de terça
set local app.agora = '2026-10-07 01:30:00-03';
select teste.ok('01:30 ainda é o dia de trabalho anterior', (public.painel_do_dia() ->> 'dia_trabalho') = '2026-10-06');
set local app.agora = '2026-10-06 12:00:00-03';

-- permissões
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B vê o próprio painel', (select (j ->> 'empresa_id', (j -> 'faturamento' ->> 'hoje')::int, (j -> 'faturamento' ->> 'tem_zig')::boolean)
   = ('e2000000-0000-4000-8000-00000000000b'::text, 55555, true) from (select public.painel_do_dia() j) x));
select teste.erro('admin B não vê painel de A', $$select public.painel_do_dia('e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão', '42501');
select teste.como('b2.master@teste.local');
select teste.erro('master sem empresa', $$select public.painel_do_dia()$$, 'Informe a empresa', '22023');
select teste.ok('master com empresa', (public.painel_do_dia('e2000000-0000-4000-8000-00000000000a') ->> 'empresa_id') = 'e2000000-0000-4000-8000-00000000000a');
select teste.como(null);
select teste.erro('anon não chama painel', $$select public.painel_do_dia()$$, null, '42501');
select teste.como_dono();
-- empresa sem nada: zeros
insert into public.empresas (id, nome) values ('e2000000-0000-4000-8000-00000000000c', 'Vazia');
select teste.ok('empresa vazia: zeros e listas vazias', (select (j -> 'faturamento', j -> 'servico', j -> 'tarefas', j -> 'sincronizacao', j -> 'ponto' -> 'alarmes')
  = ('{"hoje": 0, "ontem": 0, "mes": 0, "tem_zig": false}'::jsonb, '{"ontem": 0, "mes": 0}'::jsonb,
     '{"total": 0, "concluidas": 0, "pendentes": 0, "atrasadas": 0}'::jsonb, '[]'::jsonb, '[]'::jsonb)
  from (select public.painel_do_dia('e2000000-0000-4000-8000-00000000000c') j) x));

rollback;
