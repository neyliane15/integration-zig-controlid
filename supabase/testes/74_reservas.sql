-- 74_reservas.sql — reservas (adendo R): integração 'tagme' (tipo, segredos, escopo, execução), cadastro manual, importação CSV,
-- ingestão idempotente do N8N, bloco do painel, telefone oculto para leitura e isolamento entre empresas.
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

insert into public.integracoes (id, empresa_id, tipo, nome) values
  ('e2000000-0000-4000-8000-000000000121', 'e2000000-0000-4000-8000-00000000000a', 'tagme', 'Tagme A'),
  ('e2000000-0000-4000-8000-000000000122', 'e2000000-0000-4000-8000-00000000000b', 'tagme', 'Tagme B');
create temp table rx (nome text primary key, id uuid) on commit drop;
grant all on rx to authenticated, service_role;

-- ------------------------------------------------------------------ integração tagme
select teste.ok('tagme: parâmetros padrão', (select parametros from public.integracoes where id = 'e2000000-0000-4000-8000-000000000121')
  = '{"url_base": "", "restaurante_id": "", "dias_retroativos": 1, "dias_a_frente": 7}'::jsonb);
select teste.erro('tipo desconhecido continua recusado', $$insert into public.integracoes (empresa_id, tipo, nome) values ('e2000000-0000-4000-8000-00000000000a', 'opentable', 'x')$$, null, '23514');
select teste.como('b2.adm.a@teste.local');
select public.integracao_definir_segredos('e2000000-0000-4000-8000-000000000121', '{"token": "t", "cliente_id": "c", "cliente_segredo": "s"}');
select teste.ok('tagme: segredos permitidos', public.integracao_segredos_preenchidos('e2000000-0000-4000-8000-000000000121') = array['cliente_id', 'cliente_segredo', 'token']);
select teste.erro('tagme: segredo não permitido', $$select public.integracao_definir_segredos('e2000000-0000-4000-8000-000000000121', '{"senha": "x"}')$$, 'Segredo inválido para este tipo de integração');
select teste.ok('sync: escopo reservas só cria para tagme', public.sync_solicitar(null, 'reservas', '2026-10-06', '2026-10-13') = 1);
select teste.ok('sync: solicitação reservas da tagme', (select (integracao_id, escopo) = ('e2000000-0000-4000-8000-000000000121'::uuid, 'reservas'::text) from public.sync_solicitacoes where escopo = 'reservas'));
select teste.ok('sync: escopo tudo inclui tagme', public.sync_solicitar('e2000000-0000-4000-8000-000000000121', 'tudo') = 1);
select teste.erro('sync: vendas não serve para tagme', $$select public.sync_solicitar('e2000000-0000-4000-8000-000000000121', 'vendas')$$, 'Tipo de integração incompatível');
select teste.erro('sync: reservas não serve para zig', $$select public.sync_solicitar('e2000000-0000-4000-8000-000000000101', 'reservas')$$, 'Tipo de integração incompatível');
select teste.como_servico();
select teste.ok('ingestão: tagme entre as integrações ativas',
  exists (select 1 from public.ingestao_integracoes_ativas('tagme') where integracao_id = 'e2000000-0000-4000-8000-000000000121'));
select teste.ok('ingestão: config da tagme com segredos e dia de trabalho',
  (select (c ->> 'tipo', c -> 'segredos' ->> 'token', c ->> 'dia_trabalho_atual', c ? 'lojas')
     = ('tagme'::text, 't'::text, '2026-10-06'::text, false) from (select public.ingestao_integracao_config('e2000000-0000-4000-8000-000000000121') c) x));
select teste.passa('execução tagme_importar', $$select public.ingestao_sync_iniciar('tagme_importar', 'agendado', 'MDG · Tagme', null, 'e2000000-0000-4000-8000-000000000121')$$);

-- ------------------------------------------------------------------ manual
select teste.como('b2.ger.a@teste.local');
insert into rx select 'r1100', public.reserva_criar('2026-10-06', '11:00', 'Passado', 2);
insert into rx select 'r1145', public.reserva_criar('2026-10-06', '11:45', ' Maria Lima ', 4, '11999990000', 'Varanda', '12', 'Aniversário', 'confirmada', 'm@x.com');
insert into rx select 'r2000', public.reserva_criar('2026-10-06', '20:00', 'João', 3, '1188880000', null, null, null, 'pendente');
insert into rx select 'rsem', public.reserva_criar('2026-10-06', null, 'Sem horário', 2);
insert into rx select 'rcanc', public.reserva_criar('2026-10-06', '21:00', 'Cancela', 10);
insert into rx select 'rsent', public.reserva_criar('2026-10-06', '11:30', 'Sentados', 5, null, null, null, null, 'sentada');
insert into rx select 'ramanha', public.reserva_criar('2026-10-07', '20:00', 'Amanhã', 2);
select public.reserva_cancelar((select id from rx where nome = 'rcanc'));
select teste.ok('manual: origem, nome aparado e status', (select (origem, nome_cliente, status, criado_por) = ('manual'::text, 'Maria Lima'::text, 'confirmada'::text, 'e2000000-0000-4000-8000-000000000a02'::uuid)
  from public.reservas where id = (select id from rx where nome = 'r1145')));
select teste.erro('sem nome', $$select public.reserva_criar('2026-10-06', '20:00', ' ', 2)$$, 'Informe o nome do cliente', '22023');
select teste.erro('sem data', $$select public.reserva_criar(null, '20:00', 'x', 2)$$, 'Informe a data');
select teste.erro('pessoas 0', $$select public.reserva_criar('2026-10-06', '20:00', 'x', 0)$$, 'Número de pessoas inválido');
select teste.erro('status inválido', $$select public.reserva_criar('2026-10-06', '20:00', 'x', 2, null, null, null, null, 'no_show')$$, 'Status de reserva inválido');
select public.reserva_atualizar((select id from rx where nome = 'r2000'), '2026-10-06', '20:15', 'João Pereira', 3, '1188880000', 'Salão', '3', 'obs', 'confirmada', null);
select teste.ok('atualizar reserva manual', (select (horario, nome_cliente, area, status) = ('20:15'::time, 'João Pereira'::text, 'Salão'::text, 'confirmada'::text)
  from public.reservas where id = (select id from rx where nome = 'r2000')));
select public.reserva_mudar_status((select id from rx where nome = 'r2000'), 'pendente');
select teste.erro('mudar para status inválido', $$select public.reserva_mudar_status((select id from rx where nome = 'r2000'), 'x')$$, 'Status de reserva inválido');
select teste.erro('reserva inexistente', $$select public.reserva_cancelar(gen_random_uuid())$$, 'Reserva não encontrada', 'P0002');
select teste.ok('listar do dia: ordem por horário, nulos por último, telefone para G A M',
  (select array_agg(nome_cliente order by ordem) from (select nome_cliente, row_number() over () ordem from public.reservas_listar('2026-10-06')) x)
  = array['Passado', 'Sentados', 'Maria Lima', 'João Pereira', 'Cancela', 'Sem horário']
  and (select telefone from public.reservas_listar('2026-10-06') where nome_cliente = 'Maria Lima') = '11999990000');
select teste.ok('listar com filtro de status e período', (select count(*) from public.reservas_listar('2026-10-06', '2026-10-07', array['confirmada'])) = 4);
select teste.erro('listar: período máximo', $$select * from public.reservas_listar('2026-01-01', '2026-10-06')$$, 'Período máximo de 93 dias');

-- painel (gerente)
create temp table pg on commit drop as select public.painel_do_dia() -> 'reservas' as r;
grant select on pg to authenticated;
select teste.ok('painel: totais do dia (sem canceladas) e contagens por status',
  (select (r - 'proximas') = '{"total": 5, "pessoas": 16, "canceladas": 1, "nao_compareceu": 0, "sentadas": 1, "tem_tagme": true}'::jsonb from pg));
select teste.ok('painel: próximas = confirmadas/pendentes a partir de agora − 30 min, por horário, nulos no fim, com telefone',
  (select jsonb_agg(p ->> 'nome_cliente') from pg, jsonb_array_elements(r -> 'proximas') p) = '["Maria Lima", "João Pereira", "Sem horário"]'::jsonb
  and (select r -> 'proximas' -> 0 ->> 'telefone' from pg) = '11999990000'
  and (select array_agg(k order by k) from pg, jsonb_object_keys(r -> 'proximas' -> 0) k)
      = array['area', 'horario', 'id', 'mesa', 'nome_cliente', 'observacao', 'origem', 'pessoas', 'status', 'telefone']);

-- ------------------------------------------------------------------ importação CSV (front)
create temp table imp on commit drop as select public.reservas_importar($$[
  {"id_externo": "A-1", "data": "2026-10-06", "horario": "19:00", "nome": "Imp 1", "pessoas": 2, "telefone": "11", "status": "confirmada"},
  {"data": "06/10/2026", "horario": "", "nome": "Imp 2", "pessoas": "", "status": ""},
  {"data": "2026-02-31", "nome": "Data ruim"},
  {"data": "2026-10-06", "horario": "25:00", "nome": "Hora ruim"},
  {"data": "2026-10-06", "nome": " "},
  {"data": "2026-10-06", "nome": "Pessoas ruim", "pessoas": 0},
  {"data": "2026-10-06", "nome": "Status ruim", "status": "x"},
  {"id_externo": "A-1", "data": "2026-10-06", "nome": "Repetido"},
  "texto"
]$$::jsonb) as j;
grant select on imp to authenticated;
select teste.ok('importar: contagens e motivos por índice',
  (select j - 'erros' = '{"lidos": 9, "gravados": 2, "ignorados": 7, "inseridos": 2, "atualizados": 0}'::jsonb from imp)
  and (select jsonb_agg(e ->> 'motivo' order by (e ->> 'indice')::int) from imp, jsonb_array_elements(j -> 'erros') e)
      = '["data inválida", "horário inválido", "informe o nome", "pessoas inválido", "status inválido", "id repetido", "item inválido"]'::jsonb
  and (select (e ->> 'indice')::int from imp, jsonb_array_elements(j -> 'erros') e where e ->> 'motivo' = 'data inválida') = 2);
select teste.ok('importar: padrões (pessoas 1, confirmada, sem horário) e origem importacao',
  (select (origem, pessoas, status, horario) is not distinct from ('importacao'::text, 1, 'confirmada'::text, null::time) from public.reservas where nome_cliente = 'Imp 2'));
select teste.ok('importar de novo com o mesmo código atualiza',
  public.reservas_importar('[{"id_externo": "A-1", "data": "2026-10-06", "horario": "19:30", "nome": "Imp 1 novo", "pessoas": 3}]') - 'erros'
  = '{"lidos": 1, "gravados": 1, "ignorados": 0, "inseridos": 0, "atualizados": 1}'::jsonb);
select teste.ok('importar: continua uma só', (select count(*) from public.reservas where origem = 'importacao' and id_externo = 'A-1') = 1);
select teste.erro('importar: não-array', $$select public.reservas_importar('{}')$$, 'Lista de itens inválida');
select teste.erro('importar: lote grande', $$select public.reservas_importar((select jsonb_agg('{}'::jsonb) from generate_series(1, 2001)))$$, 'Lote maior que 2000 itens');

-- ------------------------------------------------------------------ ingestão (N8N)
select teste.como_servico();
create temp table ing on commit drop as select public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-06', '2026-10-13', $$[
  {"id_externo": "tg-1", "data": "2026-10-06", "hora": "12:15", "nome": "Tagme Um", "telefone": "11777", "email": null, "pessoas": 2,
   "status": "confirmada", "observacao": null, "origem": "tagme", "bruto": {"cpf": "não guardar"}},
  {"id_externo": "tg-2", "data": "2026-10-08", "hora": null, "nome": "Tagme Dois", "pessoas": null, "status": null},
  {"id_externo": "tg-3", "data": "2026-10-20", "hora": "20:00", "nome": "Fora da janela", "pessoas": 2, "status": "pendente"},
  {"data": "2026-10-06", "nome": "Sem id"},
  {"id_externo": "tg-1", "data": "2026-10-06", "nome": "Repetido"},
  {"id_externo": "tg-5", "data": "2026-10-06", "nome": "Status", "status": "seated"}
]$$::jsonb) as j;
grant select on ing to service_role;
select teste.ok('ingestão: contagens e motivos', (select j - 'erros' = '{"lidos": 6, "gravados": 3, "ignorados": 3, "inseridos": 3, "atualizados": 0, "removidos": 0}'::jsonb from ing)
  and (select jsonb_agg(e ->> 'motivo') from ing, jsonb_array_elements(j -> 'erros') e) = '["id_externo ausente", "id repetido", "status inválido"]'::jsonb);
select teste.ok('ingestão: grava origem tagme, integração, importado_em, padrões',
  (select (origem, integracao_id, pessoas, status, horario, importado_em is not null) is not distinct from
          ('tagme'::text, 'e2000000-0000-4000-8000-000000000121'::uuid, 1, 'confirmada'::text, null::time, true)
     from public.reservas where id_externo = 'tg-2'));
select teste.ok('ingestão: cursor da integração', (select cursor from public.integracoes where id = 'e2000000-0000-4000-8000-000000000121')
  = '{"ultimo_inicio": "2026-10-06", "ultimo_fim": "2026-10-13"}'::jsonb);
-- 2ª carga da mesma janela: tg-1 muda, tg-2 sumiu (removida), tg-3 fora da janela fica
select teste.ok('ingestão idempotente: atualiza e remove as da janela que não vieram',
  public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-06', '2026-10-13',
    '[{"id_externo": "tg-1", "data": "2026-10-06", "hora": "12:30", "nome": "Tagme Um", "pessoas": 3, "status": "sentada"}]') - 'erros'
  = '{"lidos": 1, "gravados": 1, "ignorados": 0, "inseridos": 0, "atualizados": 1, "removidos": 1}'::jsonb);
select teste.ok('ingestão idempotente: estado depois da 2ª carga', (select array_agg(id_externo order by id_externo) from public.reservas where origem = 'tagme') = array['tg-1', 'tg-3']
  and (select (horario, pessoas, status) = ('12:30'::time, 3, 'sentada'::text) from public.reservas where id_externo = 'tg-1'));
select teste.ok('ingestão: lote vazio limpa a janela (sem tocar manuais)',
  (public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-20', '2026-10-20', '[]') ->> 'removidos')::int = 1);
select teste.ok('ingestão: manuais intactas', (select count(*) from public.reservas where origem = 'manual' and empresa_id = 'e2000000-0000-4000-8000-00000000000a') = 7);
select teste.erro('ingestão: tipo errado', $$select public.ingestao_reservas('e2000000-0000-4000-8000-000000000101', '2026-10-06', '2026-10-06', '[]')$$, 'Tipo de integração incompatível');
select teste.erro('ingestão: integração inexistente', $$select public.ingestao_reservas(gen_random_uuid(), '2026-10-06', '2026-10-06', '[]')$$, 'Integração não encontrada');
select teste.erro('ingestão: janela máxima 62 dias', $$select public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-01', '2026-12-31', '[]')$$, 'Período máximo de 62 dias');
select teste.erro('ingestão: lista inválida', $$select public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-06', '2026-10-06', '{}')$$, 'Lista de itens inválida');
-- a carga de B não mexe em A
select public.ingestao_reservas('e2000000-0000-4000-8000-000000000122', '2026-10-06', '2026-10-06',
  '[{"id_externo": "tg-1", "data": "2026-10-06", "nome": "Cliente B", "pessoas": 2}]');
select teste.ok('ingestão por empresa: mesmo id_externo em B é outra reserva; A intacta',
  (select count(*) from public.reservas where id_externo = 'tg-1') = 2
  and (select nome_cliente from public.reservas where id_externo = 'tg-1' and empresa_id = 'e2000000-0000-4000-8000-00000000000a') = 'Tagme Um');
select teste.como_dono();
update public.integracoes set ativa = false where id = 'e2000000-0000-4000-8000-000000000122';
select teste.como_servico();
select teste.erro('ingestão: integração inativa', $$select public.ingestao_reservas('e2000000-0000-4000-8000-000000000122', '2026-10-06', '2026-10-06', '[]')$$, 'Integração inativa');
select teste.como('b2.ger.a@teste.local');
insert into rx select 'tg1', id from public.reservas where id_externo = 'tg-1' and empresa_id = 'e2000000-0000-4000-8000-00000000000a';
select teste.erro('reserva da Tagme não é editável', $$select public.reserva_atualizar((select id from rx where nome = 'tg1'), '2026-10-06', '12:00', 'x', 2, null, null, null, null, 'confirmada', null)$$,
  'Reserva da Tagme: só o status pode ser alterado');
select teste.erro('reserva da Tagme não é excluível', $$select public.reserva_excluir((select id from rx where nome = 'tg1'))$$, 'Reserva da Tagme não pode ser excluída');
select teste.passa('status de reserva da Tagme pode mudar', $$select public.reserva_mudar_status((select id from rx where nome = 'tg1'), 'concluida')$$);
select public.reserva_excluir((select id from rx where nome = 'ramanha'));
select teste.ok('excluir reserva manual', not exists (select 1 from public.reservas where id = (select id from rx where nome = 'ramanha')));
select teste.ok('bruto não é gravado (nenhuma coluna guarda o CPF)', not exists (select 1 from public.reservas r where to_jsonb(r)::text like '%não guardar%'));

-- ------------------------------------------------------------------ leitura
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura não lê a tabela (telefone protegido)', teste.contar('select * from public.reservas') = 0);
select teste.ok('leitura lista pelo RPC sem telefone nem e-mail',
  (select count(*) from public.reservas_listar('2026-10-06')) > 0
  and (select bool_and(telefone is null and email is null) from public.reservas_listar('2026-10-06')));
select teste.ok('leitura: painel sem telefone', (select bool_and(p -> 'telefone' = 'null'::jsonb)
  from jsonb_array_elements(public.painel_do_dia() -> 'reservas' -> 'proximas') p)
  and jsonb_array_length(public.painel_do_dia() -> 'reservas' -> 'proximas') > 0);
select teste.erro('leitura não cria', $$select public.reserva_criar('2026-10-06', '20:00', 'x', 2)$$, 'Sem permissão', '42501');
select teste.erro('leitura não muda status', $$select public.reserva_mudar_status((select id from rx where nome = 'r1145'), 'sentada')$$, 'Sem permissão', '42501');
select teste.erro('leitura não importa', $$select public.reservas_importar('[]')$$, 'Sem permissão', '42501');
select teste.erro('leitura não chama a ingestão', $$select public.ingestao_reservas('e2000000-0000-4000-8000-000000000121', '2026-10-06', '2026-10-06', '[]')$$, null, '42501');

-- ------------------------------------------------------------------ outra empresa
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B só vê as reservas de B', teste.contar('select * from public.reservas') = 1
  and (select array_agg(nome_cliente) from public.reservas_listar('2026-10-06')) = array['Cliente B']);
select teste.erro('admin B não lista reservas de A', $$select * from public.reservas_listar('2026-10-06', null, null, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.erro('admin B não cancela reserva de A', $$select public.reserva_cancelar((select id from rx where nome = 'r1145'))$$, 'Sem permissão');
select teste.erro('admin B não cria reserva em A', $$select public.reserva_criar('2026-10-06', '20:00', 'x', 2, null, null, null, null, 'confirmada', null, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.ok('admin B: painel com tem_tagme false (integração inativa)', (public.painel_do_dia() -> 'reservas' ->> 'tem_tagme')::boolean = false);
select teste.como_dono();
rollback;
