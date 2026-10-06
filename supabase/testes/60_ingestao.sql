-- 60_ingestao.sql (b2) — ingestão Control iD (acesso e REP), idempotência, cursor, vínculos tardios (§7.8),
-- rotina de apuração e exportação de fechamento.
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

insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, nome, funcionario_id, vinculo) values
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000102', '12', 'ANA', 'e2000000-0000-4000-8000-000000000301', 'manual'),
  ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000102', '99', 'DESCONHECIDO', null, null);

create temp table lote (j jsonb) on commit drop;
grant select on lote to service_role;
insert into lote values ($$[
  {"id_externo": "98123", "instante_local": "2026-10-03T16:58:00", "user_id": "12", "evento": 7},
  {"id_externo": "98124", "instante": "2026-10-04T00:02:00Z", "user_id": "12", "evento": 7},
  {"id_externo": "98125", "instante_local": "2026-10-03T21:29:00", "user_id": "12", "evento": 7},
  {"id_externo": "98126", "instante_local": "2026-10-04T01:04:00", "user_id": "12"},
  {"id_externo": "98127", "instante_local": "2026-10-03T18:00:00", "user_id": "12", "evento": 6},
  {"id_externo": "98128", "instante_local": "2026-10-03T18:00:00", "user_id": "0", "evento": 7},
  {"id_externo": "98129", "instante_local": "2026-10-03T18:00:00", "user_id": "99", "evento": 7},
  {"id_externo": "98130", "instante": "2026-10-03T18:00:00", "user_id": "12"},
  {"id_externo": "98131", "instante_local": "2026-10-03T18:00:00", "instante": "2026-10-03T18:00:00Z", "user_id": "12"},
  {"instante_local": "2026-10-03T18:00:00", "user_id": "12"},
  {"id_externo": "98132", "instante_local": "ontem", "user_id": "12"}
]$$);

select teste.como_servico();
create temp table r1 on commit drop as
  select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102', j) as r from lote;
select teste.ok('acesso: contagens', (select r @> '{"lidos": 11, "gravados": 5, "ignorados": 6, "duplicados": 0, "sem_funcionario": 1, "dias_apurados": 1}' from r1));
select teste.ok('acesso: erros listados com índice', (select jsonb_path_query_array(r, '$.erros[*].indice') = '[7, 8, 9, 10]'::jsonb from r1));
select teste.ok('acesso: cursor = máximo id e instante dos itens bem formados',
  (select (r -> 'cursor' ->> 'ultimo_id', (r -> 'cursor' ->> 'ultimo_instante')::timestamptz) = ('98129'::text, '2026-10-04 01:04-03'::timestamptz) from r1)
  and (select cursor ->> 'ultimo_id' from public.integracoes where id = 'e2000000-0000-4000-8000-000000000102') = '98129');
select teste.ok('instante_local no fuso da empresa e instante UTC como veio',
  (select array_agg(instante order by instante) from public.ponto_batidas where pessoa_externa = '12')
  = array['2026-10-03 16:58-03', '2026-10-03 21:02-03', '2026-10-03 21:29-03', '2026-10-04 01:04-03']::timestamptz[]);
select teste.ok('apurado: Ana 03/10 completo, 459 min', (select (situacao, trabalhado_minutos) = ('completo'::text, 459)
   from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03'));
select teste.ok('batida sem vínculo gravada com funcionario_id null', (select (funcionario_id, origem, data_trabalho)
   is not distinct from (null::uuid, 'controlid_acesso'::text, '2026-10-03'::date) from public.ponto_batidas where id_externo = '98129'));

-- reimportar o mesmo lote: nada muda
create temp table r2 on commit drop as
  select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102', j) as r from lote;
select teste.ok('reimportação idempotente: 0 gravados, 5 duplicados, 0 dias apurados',
  (select r @> '{"lidos": 11, "gravados": 0, "duplicados": 5, "ignorados": 6, "dias_apurados": 0}' from r2)
  and (select count(*) from public.ponto_batidas where integracao_id = 'e2000000-0000-4000-8000-000000000102') = 5);
-- cursor não volta atrás com lote antigo
select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102',
  '[{"id_externo": "500", "instante_local": "2026-09-01T10:00:00", "user_id": "12"}]');
select teste.ok('cursor não regride', (select (cursor ->> 'ultimo_id', (cursor ->> 'ultimo_instante')::timestamptz)
   = ('98129'::text, '2026-10-04 01:04-03'::timestamptz) from public.integracoes where id = 'e2000000-0000-4000-8000-000000000102'));
select teste.erro('lote acima de 2000', $$select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102',
  (select jsonb_agg(jsonb_build_object('id_externo', g::text, 'instante_local', '2026-10-01T10:00:00', 'user_id', '12')) from generate_series(1, 2001) g))$$,
  'Lote maior que 2000 itens', '22023');
select teste.erro('integração Zig não aceita batidas', $$select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000101', '[]')$$,
  'Tipo de integração incompatível');
select teste.como_dono();
update public.integracoes set ativa = false where id = 'e2000000-0000-4000-8000-000000000112';
select teste.como_servico();
select teste.erro('integração inativa', $$select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000112', '[]')$$, 'Integração inativa');
select teste.como_dono();
update public.integracoes set ativa = true where id = 'e2000000-0000-4000-8000-000000000112';
-- eventos válidos configuráveis
update public.integracoes set parametros = '{"eventos_validos": [7, 8]}' where id = 'e2000000-0000-4000-8000-000000000102';
select teste.como_servico();
select teste.ok('eventos_validos configurável', public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102',
  '[{"id_externo": "98140", "instante_local": "2026-10-05T10:00:00", "user_id": "12", "evento": 8},
    {"id_externo": "98141", "instante_local": "2026-10-05T10:05:00", "user_id": "12", "evento": "7"},
    {"id_externo": "98142", "instante_local": "2026-10-05T10:10:00", "user_id": "12", "evento": 1}]') @> '{"gravados": 2, "ignorados": 1}');

-- vínculo tardio (§7.8): usuário 99 ligado ao Bruno, depois trocado para a Carla, depois desvinculado
select teste.como('b2.ger.a@teste.local');
select teste.como_dono();
update public.controlid_usuarios set funcionario_id = 'e2000000-0000-4000-8000-000000000302', vinculo = 'manual' where user_id_externo = '99';
select teste.ok('vincular: batida passa ao Bruno e o dia é reapurado', (select funcionario_id from public.ponto_batidas where id_externo = '98129')
  = 'e2000000-0000-4000-8000-000000000302'
  and (select (batidas_validas, situacao) = (1::smallint, 'incompleto'::text) from public.ponto_dias
         where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03'));
update public.controlid_usuarios set funcionario_id = 'e2000000-0000-4000-8000-000000000303' where user_id_externo = '99';
select teste.ok('trocar vínculo: batida vai para a Carla; dia do Bruno volta a ausente',
  (select funcionario_id from public.ponto_batidas where id_externo = '98129') = 'e2000000-0000-4000-8000-000000000303'
  and (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000302' and data = '2026-10-03') = 'ausente'
  and (select batidas_validas from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03') = 1);
update public.controlid_usuarios set funcionario_id = null where user_id_externo = '99';
select teste.ok('desvincular: batida volta a null', (select funcionario_id from public.ponto_batidas where id_externo = '98129') is null
  and (select batidas_validas from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03') = 0);

-- REP: CPF/PIS, NSR sem zeros à esquerda, vínculo tardio pelo PIS
select teste.como_servico();
create temp table r3 on commit drop as select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000103',
  '[{"id_externo": "000123", "nsr": 123, "instante": "2026-10-05T17:02:00-03:00", "cpf": "390.533.447-05"},
    {"id_externo": "124", "nsr": 124, "instante_local": "2026-10-05T21:30:00", "pis": "12345678901"},
    {"id_externo": "125", "nsr": 125, "instante_local": "2026-10-05T21:31:00"}]') as r;
select teste.ok('REP: contagens e cursor por NSR', (select r @> '{"lidos": 3, "gravados": 2, "ignorados": 1, "sem_funcionario": 1}'
   and (r -> 'cursor' ->> 'ultimo_nsr')::int = 124 from r3));
select teste.ok('REP: NSR sem zeros à esquerda, CPF só dígitos, funcionário pelo CPF',
  (select (pessoa_externa, funcionario_id, origem) = ('39053344705'::text, 'e2000000-0000-4000-8000-000000000303'::uuid, 'controlid_rep'::text)
     from public.ponto_batidas where integracao_id = 'e2000000-0000-4000-8000-000000000103' and id_externo = '123'));
select teste.ok('REP: reimportar com zeros à esquerda é duplicado', public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000103',
  '[{"id_externo": "0000123", "nsr": 123, "instante": "2026-10-05T17:02:00-03:00", "cpf": "39053344705"}]') @> '{"gravados": 0, "duplicados": 1}');
select teste.como('b2.ger.a@teste.local');
update public.funcionarios set pis = '123.45678.90-1' where id = 'e2000000-0000-4000-8000-000000000304';
select teste.como_dono();
select teste.ok('REP: cadastrar o PIS vincula a batida pendente e apura', (select funcionario_id from public.ponto_batidas
   where integracao_id = 'e2000000-0000-4000-8000-000000000103' and id_externo = '124') = 'e2000000-0000-4000-8000-000000000304'
  and exists (select 1 from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000304' and data = '2026-10-05' and batidas_validas = 1));
-- isolamento: a mesma CPF numa integração de outra empresa não acha o funcionário de A
select teste.como_servico();
select teste.ok('REP de B não vincula funcionário de A pelo CPF', public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000112',
  '[{"id_externo": "1", "nsr": 1, "instante": "2026-10-05T17:00:00-04:00", "cpf": "39053344705"}]') @> '{"gravados": 1, "sem_funcionario": 1}');

-- rotina de apuração
select teste.ok('ingestao_apurar_ponto (empresa B, 7 dias)', public.ingestao_apurar_ponto('e2000000-0000-4000-8000-00000000000b', '2026-09-28', '2026-10-04')
  = '{"empresas": 1, "funcionarios": 1, "dias": 7}');
select teste.ok('rotina cria os dias sem batida e os alarmes sem_batida dos dias úteis', (select count(*) from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000391' and tipo = 'sem_batida_dia_escalado' and data between '2026-09-28' and '2026-10-04') = 5);
select teste.ok('rotina idempotente', public.ingestao_apurar_ponto('e2000000-0000-4000-8000-00000000000b', '2026-09-28', '2026-10-04')
  = '{"empresas": 1, "funcionarios": 1, "dias": 7}' and (select count(*) from public.ponto_alarmes
   where funcionario_id = 'e2000000-0000-4000-8000-000000000391' and data between '2026-09-28' and '2026-10-04') = 5);
select teste.ok('rotina padrão: todas as empresas ativas, dia atual − 2 até hoje', (public.ingestao_apurar_ponto() ->> 'empresas')::int >= 2);
select teste.erro('rotina: empresa inexistente', $$select public.ingestao_apurar_ponto(gen_random_uuid())$$, 'Empresa não encontrada', 'P0002');

-- exportação do fechamento
select teste.como('b2.ger.a@teste.local');
create temp table fx on commit drop as select public.comissao_criar_fechamento('2026-09-01', '2026-09-30', 'Exportar') as id;
grant select on fx to service_role, anon;
select teste.como_servico();
create temp table ex on commit drop as select public.ingestao_fechamento_exportar((select id from fx)) as r;
select teste.ok('exportar: fechamento com empresa_nome e itens por nome',
  (select (r -> 'fechamento' ->> 'titulo', r -> 'fechamento' ->> 'empresa_nome', r -> 'fechamento' ->> 'status',
           jsonb_path_query_array(r, '$.itens[*].funcionario_nome'))
     = ('Exportar'::text, 'Teste b2 A'::text, 'rascunho'::text, '["Ana Souza", "Bruno Lima", "Carla Dias", "Davi Rocha", "Eva Martins"]'::jsonb) from ex)
  and (select r -> 'fechamento' ? 'base_distribuivel_centavos' and r -> 'itens' -> 0 ? 'valor_centavos' from ex));
select teste.erro('exportar: inexistente', $$select public.ingestao_fechamento_exportar(gen_random_uuid())$$, 'Fechamento não encontrado', 'P0002');

-- [servico] negado a authenticated e anon
select teste.como('b2.adm.a@teste.local');
select teste.erro('authenticated não chama ingestao_controlid_batidas', $$select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000102', '[]')$$, null, '42501');
select teste.erro('authenticated não chama ingestao_apurar_ponto', $$select public.ingestao_apurar_ponto()$$, null, '42501');
select teste.erro('authenticated não chama ingestao_fechamento_exportar', $$select public.ingestao_fechamento_exportar((select id from fx))$$, null, '42501');
select teste.erro('authenticated não chama ingestao_zig_saida_produtos', $$select public.ingestao_zig_saida_produtos('e2000000-0000-4000-8000-000000000101', 'x', '2026-10-01', '[]')$$, null, '42501');
select teste.erro('authenticated não chama ponto_apurar ([interno])', $$select public.ponto_apurar('e2000000-0000-4000-8000-000000000301', '2026-10-01', '2026-10-01')$$, null, '42501');
select teste.erro('authenticated não chama ponto_calcular_dia ([interno])', $$select * from public.ponto_calcular_dia('e2000000-0000-4000-8000-000000000301', '2026-10-01')$$, null, '42501');
select teste.erro('authenticated não chama comissao_calcular ([interno])', $$select public.comissao_calcular((select id from fx))$$, null, '42501');
select teste.como(null);
select teste.erro('anon não chama ingestão', $$select public.ingestao_apurar_ponto()$$, null, '42501');
select teste.como_dono();

rollback;
