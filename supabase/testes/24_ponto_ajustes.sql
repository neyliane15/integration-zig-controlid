-- 24_ponto_ajustes.sql (b2) — ajustes manuais auditados: incluir, desconsiderar, restaurar, editar (= desconsiderar + incluir),
-- validações, imutabilidade das batidas importadas e permissões.
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

-- batidas importadas (REP) da Carla (303) no sáb 03/10
select teste.como_servico();
select public.ingestao_controlid_batidas('e2000000-0000-4000-8000-000000000103', $$[
  {"id_externo": "101", "nsr": 101, "instante": "2026-10-03T17:00:00-03:00", "cpf": "39053344705"},
  {"id_externo": "102", "nsr": 102, "instante": "2026-10-03T21:00:00-03:00", "cpf": "39053344705"},
  {"id_externo": "103", "nsr": 103, "instante": "2026-10-03T21:30:00-03:00", "cpf": "39053344705"}
]$$::jsonb);
select teste.como_dono();
select teste.ok('3 batidas importadas: incompleto, falta a saída', (select (situacao, batidas_validas) = ('incompleto'::text, 3::smallint)
   from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03')
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000303'
                and data = '2026-10-03' and batida_esperada = 'saida' and status = 'aberto'));

select teste.como('b2.ger.a@teste.local');
select teste.erro('incluir: motivo obrigatório', $$select public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000303', '2026-10-04 01:00-03', '')$$,
  'Informe o motivo', '22023');
select teste.erro('incluir: horário no futuro', $$select public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000303', '2026-10-06 12:00:01-03', 'x')$$,
  'Horário no futuro', '22023');
select teste.erro('incluir: funcionário inexistente', $$select public.ponto_incluir_batida(gen_random_uuid(), '2026-10-04 01:00-03', 'x')$$,
  'Funcionário não encontrado', 'P0002');
select teste.erro('incluir: funcionário de outra empresa', $$select public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000391', '2026-10-04 01:00-03', 'x')$$,
  'Sem permissão', '42501');

-- incluir a saída às 01:00 de domingo → pertence ao sábado
create temp table ids (nome text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
insert into ids select 'manual1', public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000303', '2026-10-04 01:00-03', '  Esqueceu de bater a saída ');
select teste.ok('batida manual: origem, data de trabalho do sábado, motivo aparado, autor',
  (select (origem, data_trabalho, motivo, criado_por, integracao_id, id_externo)
     is not distinct from ('manual'::text, '2026-10-03'::date, 'Esqueceu de bater a saída'::text,
                           'e2000000-0000-4000-8000-000000000a02'::uuid, null::uuid, null::text)
     from public.ponto_batidas where id = (select id from ids where nome = 'manual1')));
select teste.ok('ajuste "incluir" auditado com nome do perfil', (select (acao, instante, motivo, feito_por, feito_por_nome, feito_em)
   = ('incluir'::text, '2026-10-04 01:00-03'::timestamptz, 'Esqueceu de bater a saída'::text,
      'e2000000-0000-4000-8000-000000000a02'::uuid, 'Gerente A'::text, '2026-10-06 12:00-03'::timestamptz)
   from public.ponto_ajustes where batida_id = (select id from ids where nome = 'manual1')));
select teste.ok('dia reapurado: completo (17:00–21:00 + 21:30–01:00 = 450) e alarme resolvido',
  (select (situacao, trabalhado_minutos, saldo_minutos) = ('completo'::text, 450, 0) from public.ponto_dias
    where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03')
  and (select status from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000303'
         and data = '2026-10-03' and batida_esperada = 'saida') = 'resolvido');

-- editar a manual = desconsiderar + incluir
select public.ponto_desconsiderar_batida((select id from ids where nome = 'manual1'), 'Horário errado');
insert into ids select 'manual2', public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000303', '2026-10-04 01:20-03', 'Horário correto da saída');
select teste.ok('edição: antiga desconsiderada (motivo atualizado), nova válida; trabalhado 470 → saldo +20',
  (select (desconsiderada, motivo) = (true, 'Horário errado'::text) from public.ponto_batidas where id = (select id from ids where nome = 'manual1'))
  and (select (trabalhado_minutos, saldo_minutos) = (470, 20) from public.ponto_dias
         where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03'));
select teste.ok('trilha de auditoria completa (incluir, desconsiderar, incluir)',
  (select array_agg(acao order by acao) from public.ponto_ajustes where funcionario_id = 'e2000000-0000-4000-8000-000000000303')
  = array['desconsiderar', 'incluir', 'incluir']);

-- desconsiderar/restaurar batida importada
select teste.erro('desconsiderar: motivo obrigatório', $$select public.ponto_desconsiderar_batida((select id from public.ponto_batidas where id_externo = '102'), null)$$,
  'Informe o motivo', '22023');
select teste.erro('desconsiderar: batida inexistente', $$select public.ponto_desconsiderar_batida(gen_random_uuid(), 'x')$$,
  'Batida não encontrada', 'P0002');
select public.ponto_desconsiderar_batida((select id from public.ponto_batidas where id_externo = '102'), 'Leitura dupla do equipamento');
select teste.ok('importada desconsiderada: 3 válidas, alarme de falta reaparece',
  (select batidas_validas from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03') = 3
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000303'
                and data = '2026-10-03' and tipo = 'batida_faltando' and status = 'aberto'));
select public.ponto_restaurar_batida((select id from public.ponto_batidas where id_externo = '102'), 'Era válida');
select teste.ok('restaurada: motivo limpo na importada, 4 válidas',
  (select (desconsiderada, motivo) is not distinct from (false, null::text) from public.ponto_batidas where id_externo = '102')
  and (select batidas_validas from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000303' and data = '2026-10-03') = 4);
select public.ponto_desconsiderar_batida((select id from ids where nome = 'manual2'), 'teste');
select public.ponto_restaurar_batida((select id from ids where nome = 'manual2'), 'teste de volta');
select teste.ok('manual restaurada mantém o motivo original', (select motivo from public.ponto_batidas
   where id = (select id from ids where nome = 'manual2')) = 'Horário correto da saída');
select teste.ok('ajuste de restaurar gravado com o instante da batida', (select count(*) from public.ponto_ajustes
   where acao = 'restaurar' and funcionario_id = 'e2000000-0000-4000-8000-000000000303') = 2);

-- leitura e outras empresas
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura não vê ponto_ajustes (G A)', teste.contar('select * from public.ponto_ajustes') = 0);
select teste.ok('leitura vê as batidas', teste.contar('select * from public.ponto_batidas') >= 5);
select teste.erro('leitura não inclui batida', $$select public.ponto_incluir_batida('e2000000-0000-4000-8000-000000000303', '2026-10-04 01:00-03', 'x')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não desconsidera', $$select public.ponto_desconsiderar_batida((select id from public.ponto_batidas limit 1), 'x')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não insere batida direto', $$insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
  values ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', now(), 'x')$$, null, '42501');
select teste.como('b2.adm.a@teste.local');
select teste.ok('administrador vê os ajustes', teste.contar('select * from public.ponto_ajustes') = 7);
select teste.como('b2.adm.b@teste.local');
select teste.ok('admin B não vê ajustes nem batidas de A', teste.contar('select * from public.ponto_ajustes') = 0
  and teste.contar('select * from public.ponto_batidas') = 0);
select teste.erro('admin B não desconsidera batida de A', $$select public.ponto_desconsiderar_batida((select id from ids where nome = 'manual2'), 'x')$$,
  'Sem permissão', '42501');
select teste.como('b2.master@teste.local');
select public.ponto_desconsiderar_batida((select id from public.ponto_batidas where id_externo = '101'), 'Master testando');
select teste.ok('master ajusta qualquer empresa (nome do master na auditoria)', (select feito_por_nome from public.ponto_ajustes
   where acao = 'desconsiderar' and motivo = 'Master testando') = 'Master b2');

-- sistema (sem JWT) aparece como 'Sistema'
select teste.como_dono();
select public.ponto_restaurar_batida((select id from public.ponto_batidas where id_externo = '101'), 'Rotina');
select teste.ok('sem JWT: feito_por_nome = Sistema', (select (feito_por_nome, feito_por) is not distinct from ('Sistema'::text, null::uuid)
   from public.ponto_ajustes where motivo = 'Rotina'));

-- imutabilidade das batidas
select teste.erro('instante de batida importada é imutável', $$update public.ponto_batidas set instante = instante + interval '1 minute' where id_externo = '103'$$,
  'não pode ser alterada', '22023');
select teste.erro('origem é imutável', $$update public.ponto_batidas set origem = 'manual' where id_externo = '103'$$, 'não pode ser alterada');
select teste.erro('batida manual sem motivo é recusada', $$insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante)
  values ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000303', 'manual', now())$$, 'Batida inválida');
select teste.erro('batida importada sem id_externo é recusada', $$insert into public.ponto_batidas (empresa_id, integracao_id, origem, instante)
  values ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000103', 'controlid_rep', now())$$, 'Batida inválida');
select teste.erro('batida com funcionário de outra empresa é recusada', $$insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
  values ('e2000000-0000-4000-8000-00000000000a', 'e2000000-0000-4000-8000-000000000391', 'manual', now(), 'x')$$, 'Funcionário de outra empresa');
-- excluir a integração: integracao_id vira null e a batida continua
delete from public.integracoes where id = 'e2000000-0000-4000-8000-000000000103';
select teste.ok('integração excluída: batidas preservadas com integracao_id null',
  (select count(*) from public.ponto_batidas where id_externo in ('101', '102', '103') and integracao_id is null) = 3);

rollback;
