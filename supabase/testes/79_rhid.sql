-- 79_rhid.sql — integração RHiD (nuvem da Control iD): tipo 'rhid' (parâmetros, segredos, escopos, execuções),
-- pessoas → usuários do relógio por CPF (vínculo automático), AFD por equipamento (id_externo equip|NSR, cursor por
-- equipamento que não regride, deduplicação com o AFD enviado pelo site), troca de um controlid_rep por RHiD.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e7900000-0000-4000-8000-00000000000a', 'Teste RHiD A', 'America/Sao_Paulo', '05:00'),
  ('e7900000-0000-4000-8000-00000000000b', 'Teste RHiD B', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e7900000-0000-4000-8000-000000000a01', 'rhid.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e7900000-0000-4000-8000-000000000a02', 'rhid.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e7900000-0000-4000-8000-000000000b01', 'rhid.adm.b@teste.local', '{"nome":"Adm B"}');
update public.perfis set papel = 'administrador', empresa_id = 'e7900000-0000-4000-8000-00000000000a' where id = 'e7900000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e7900000-0000-4000-8000-00000000000a' where id = 'e7900000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'administrador', empresa_id = 'e7900000-0000-4000-8000-00000000000b' where id = 'e7900000-0000-4000-8000-000000000b01';
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e7900000-0000-4000-8000-000000000201', 'e7900000-0000-4000-8000-00000000000a', 'Salão RHiD', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values
  ('e7900000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
-- Ana: CPF na ficha (matrícula 10 ≠ registration do RHiD); Bruno: sem CPF, liga pela matrícula 2;
-- Carla: CPF com zero à esquerda (o RHiD manda número); Davi: cadastrado depois (batida pendente volta a ele)
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, matricula, pontos_comissao, data_admissao) values
  ('e7900000-0000-4000-8000-000000000301', 'e7900000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', '52998224725', '10', 10, '2026-01-01'),
  ('e7900000-0000-4000-8000-000000000302', 'e7900000-0000-4000-8000-00000000000a', 'Bruno Lima', 'Garçom', null, '2', 10, '2026-01-01'),
  ('e7900000-0000-4000-8000-000000000303', 'e7900000-0000-4000-8000-00000000000a', 'Carla Dias', 'Cumim', '04567891230', '3', 5, '2026-01-01'),
  ('e7900000-0000-4000-8000-000000000304', 'e7900000-0000-4000-8000-00000000000a', 'Outro 1', 'Cozinha', null, '1', 0, '2026-01-01');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e7900000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e7900000-0000-4000-8000-000000000301', 'e7900000-0000-4000-8000-000000000302',
                    'e7900000-0000-4000-8000-000000000303']::uuid[]) f;

-- ------------------------------------------------------------------ tipo, parâmetros e segredos
select teste.como('rhid.ger.a@teste.local');
select teste.erro('gerente não cria a integração RHiD',
  $$insert into public.integracoes (empresa_id, tipo, nome) values ('e7900000-0000-4000-8000-00000000000a', 'rhid', 'R')$$,
  'row-level security');
select teste.como('rhid.adm.a@teste.local');
insert into public.integracoes (id, empresa_id, tipo, nome, parametros, cursor)
values ('e7900000-0000-4000-8000-000000000101', 'e7900000-0000-4000-8000-00000000000a', 'rhid', 'Relógio de ponto (RHiD)',
        '{"dias_retroativos": 3}', '{"nsr_por_equipamento": {"55": 999}}');
select teste.ok('admin cria RHiD: padrões mesclados (equipamentos [], REP-P, pessoas), cursor do usuário ignorado',
  (select parametros = '{"equipamentos": [], "incluir_rep_p": true, "dias_retroativos": 3, "importar_pessoas": true}'
          and cursor = '{}' and not (parametros ? 'envio')
     from public.integracoes where id = 'e7900000-0000-4000-8000-000000000101'));
select teste.ok('chaves de segredo do RHiD', public.integracao_chaves_segredo('rhid') = array['email', 'senha', 'dominio']);
select teste.passa('admin grava e-mail, senha e domínio',
  $$select public.integracao_definir_segredos('e7900000-0000-4000-8000-000000000101',
      '{"email": "integracao@macaw.com.br", "senha": "s3nh4", "dominio": ""}')$$);
select teste.ok('preenchidos: email e senha (domínio vazio não grava)',
  public.integracao_segredos_preenchidos('e7900000-0000-4000-8000-000000000101') = array['email', 'senha']);
select teste.erro('segredo de outro tipo recusado',
  $$select public.integracao_definir_segredos('e7900000-0000-4000-8000-000000000101', '{"url": "http://x"}')$$,
  'Segredo inválido para este tipo de integração', '22023');
select teste.ok('escopos do RHiD: tudo, funcionarios, batidas (não vendas/exportar)',
  public.sync_escopo_compativel('tudo', 'rhid') and public.sync_escopo_compativel('funcionarios', 'rhid')
  and public.sync_escopo_compativel('batidas', 'rhid') and not public.sync_escopo_compativel('vendas', 'rhid')
  and not public.sync_escopo_compativel('exportar_funcionarios', 'rhid'));
select teste.como('rhid.ger.a@teste.local');
select teste.ok('gerente pede "Sincronizar agora" (batidas) do RHiD',
  public.sync_solicitar('e7900000-0000-4000-8000-000000000101', 'batidas') = 1);
select teste.erro('escopo incompatível', $$select public.sync_solicitar('e7900000-0000-4000-8000-000000000101', 'vendas')$$,
  'Tipo de integração incompatível', '22023');
select teste.como_servico();
select teste.ok('agendador do N8N vê a integração RHiD',
  exists (select 1 from public.ingestao_integracoes_ativas('rhid') x where x.integracao_id = 'e7900000-0000-4000-8000-000000000101'));
select teste.ok('fila entrega o tipo rhid',
  (select integracao_tipo = 'rhid' and escopo = 'batidas' from public.ingestao_sync_pegar_solicitacoes(5) limit 1));
select teste.ok('config para o N8N traz os segredos e o cursor',
  (select c -> 'segredos' ->> 'email' = 'integracao@macaw.com.br' and c ->> 'tipo' = 'rhid' and c -> 'cursor' = '{}'
     from (select public.ingestao_integracao_config('e7900000-0000-4000-8000-000000000101') c) x));
select teste.passa('execuções rhid_pessoas e rhid_batidas aceitas',
  $$select public.ingestao_sync_finalizar(public.ingestao_sync_iniciar('rhid_pessoas', 'agendado', 'MDG · RHiD · Importar',
      null, 'e7900000-0000-4000-8000-000000000101'), 'sucesso'),
           public.ingestao_sync_finalizar(public.ingestao_sync_iniciar('rhid_batidas', 'agendado', 'MDG · RHiD · Importar',
      null, 'e7900000-0000-4000-8000-000000000101'), 'sucesso')$$);

-- ------------------------------------------------------------------ pessoas
select teste.como('rhid.adm.a@teste.local');
select teste.erro('authenticated não chama a ingestão de pessoas',
  $$select public.ingestao_rhid_pessoas('e7900000-0000-4000-8000-000000000101', '[]')$$, 'permission denied');
select teste.como_servico();
create temp table r_pes on commit drop as
select public.ingestao_rhid_pessoas('e7900000-0000-4000-8000-000000000101', $$[
  {"id": 1, "cpf": 52998224725, "name": "ANA SOUZA", "registration": "1", "status": 1, "idCompany": 1},
  {"id": 2, "cpf": 11144477735, "name": "BRUNO LIMA", "registration": "2", "status": 1, "idCompany": 1},
  {"id": 3, "cpf": 4567891230, "pis": 0, "name": "CARLA DIAS", "registration": "", "status": 1, "idCompany": 1},
  {"id": 4, "cpf": 15350946056, "name": "DAVI ROCHA", "registration": null, "status": 1, "idCompany": 1},
  {"id": 5, "cpf": null, "name": "SEM CPF", "registration": "99", "status": 1, "idCompany": 1},
  {"id": 6, "cpf": 52998224725, "name": "ANA REPETIDA", "status": 0, "idCompany": 1}
]$$) as r;
select teste.ok('pessoas: 6 lidas, 4 gravadas, 1 sem CPF e 1 repetida ignoradas, 3 ligadas (Davi sem ficha)',
  (select (r ->> 'lidos')::int = 6 and (r ->> 'gravados')::int = 4 and (r ->> 'sem_cpf')::int = 1
          and (r ->> 'ignorados')::int = 2 and (r ->> 'vinculados_automaticamente')::int = 3 and (r ->> 'sem_vinculo')::int = 1
     from r_pes));
select teste.ok('id do usuário = CPF com 11 dígitos (zero à esquerda restaurado)',
  (select array_agg(user_id_externo order by user_id_externo) = array['04567891230', '11144477735', '15350946056', '52998224725']
     from public.controlid_usuarios where integracao_id = 'e7900000-0000-4000-8000-000000000101'));
select teste.ok('vínculo: Ana pelo CPF (mesmo com registration "1" = matrícula de outro), Bruno pela matrícula, Carla pelo CPF',
  (select bool_and(case user_id_externo
                     when '52998224725' then funcionario_id = 'e7900000-0000-4000-8000-000000000301'
                     when '11144477735' then funcionario_id = 'e7900000-0000-4000-8000-000000000302'
                     when '04567891230' then funcionario_id = 'e7900000-0000-4000-8000-000000000303'
                     else funcionario_id is null end and (funcionario_id is null or vinculo = 'automatico'))
     from public.controlid_usuarios where integracao_id = 'e7900000-0000-4000-8000-000000000101'));

-- ------------------------------------------------------------------ batidas (AFD 671)
create temp table r_bat (n int, r jsonb) on commit drop;
insert into r_bat select 1, public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000101', '55', $$[
  {"id_externo": "101", "nsr": 101, "instante": "2026-10-03T16:58:00-03:00", "cpf": "52998224725"},
  {"id_externo": "102", "nsr": 102, "instante": "2026-10-03T21:01:00-03:00", "cpf": "52998224725"},
  {"id_externo": "103", "nsr": 103, "instante": "2026-10-03T21:29:00-03:00", "cpf": "52998224725"},
  {"id_externo": "104", "nsr": 104, "instante": "2026-10-04T01:02:00-03:00", "cpf": "52998224725"},
  {"id_externo": "105", "nsr": 105, "instante": "2026-10-03T17:03:00-03:00", "cpf": "04567891230"},
  {"id_externo": "106", "nsr": 106, "instante": "2026-10-03T17:04:00-03:00", "cpf": "15350946056"},
  {"id_externo": "107", "nsr": 107, "instante": "2026-10-03T17:05:00-03:00"}
]$$);
select teste.ok('batidas: 7 lidas, 6 gravadas, 1 sem CPF ignorada, 1 sem funcionário (Davi)',
  (select (r ->> 'lidos')::int = 7 and (r ->> 'gravados')::int = 6 and (r ->> 'ignorados')::int = 1
          and (r ->> 'sem_funcionario')::int = 1 and r ->> 'equipamento' = '55' and (r ->> 'ultimo_nsr')::int = 107
     from r_bat where n = 1));
select teste.ok('id_externo equip|NSR, origem controlid_rep, instante com fuso',
  (select count(*) = 6 and bool_and(b.id_externo ~ '^55\|10[1-6]$' and b.origem = 'controlid_rep')
          and min(b.instante) = '2026-10-03 16:58:00-03'::timestamptz
     from public.ponto_batidas b where b.integracao_id = 'e7900000-0000-4000-8000-000000000101'));
select teste.ok('Ana apurada no dia 03/10 com as 4 batidas',
  (select batidas_validas = 4 from public.ponto_dias where funcionario_id = 'e7900000-0000-4000-8000-000000000301' and data = '2026-10-03'));
select teste.ok('cursor por equipamento: {"55": 107}',
  (select cursor -> 'nsr_por_equipamento' = '{"55": 107}' and cursor ? 'ultimo_instante'
     from public.integracoes where id = 'e7900000-0000-4000-8000-000000000101'));
insert into r_bat select 2, public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000101', '55', $$[
  {"nsr": 101, "instante": "2026-10-03T16:58:00-03:00", "cpf": "52998224725"},
  {"nsr": 7, "instante": "2026-10-01T10:00:00-03:00", "cpf": "52998224725"}
]$$);
select teste.ok('reimportar: duplicada não grava; NSR menor grava mas o cursor não regride',
  (select (r ->> 'duplicados')::int = 1 and (r ->> 'gravados')::int = 1 from r_bat where n = 2)
  and (select cursor -> 'nsr_por_equipamento' = '{"55": 107}' from public.integracoes where id = 'e7900000-0000-4000-8000-000000000101'));
insert into r_bat select 3, public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000101', '99000001', $$[
  {"nsr": 101, "instante": "2026-10-03T17:20:00-03:00", "cpf": "11144477735"}
]$$);
select teste.ok('REP-P (idCompany + 99000000): mesmo NSR em outro equipamento é outra batida; cursor separado',
  (select (r ->> 'gravados')::int = 1 from r_bat where n = 3)
  and (select cursor -> 'nsr_por_equipamento' = '{"55": 107, "99000001": 101}'
         from public.integracoes where id = 'e7900000-0000-4000-8000-000000000101')
  and exists (select 1 from public.ponto_batidas where id_externo = '99000001|101'
                and funcionario_id = 'e7900000-0000-4000-8000-000000000302'));
select teste.erro('equipamento inválido',
  $$select public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000101', 'abc', '[]')$$, 'Equipamento inválido', '22023');

-- Davi entra na ficha com o CPF → a batida pendente passa a ele (gatilho de documentos) e a próxima importação de pessoas liga
select teste.como_dono();
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, matricula, pontos_comissao, data_admissao) values
  ('e7900000-0000-4000-8000-000000000305', 'e7900000-0000-4000-8000-00000000000a', 'Davi Rocha', 'Bartender', '15350946056', '4', 0, '2026-01-01');
select teste.ok('batida pendente do Davi foi para a ficha nova',
  (select funcionario_id = 'e7900000-0000-4000-8000-000000000305' from public.ponto_batidas where id_externo = '55|106'));
select teste.como_servico();
select public.ingestao_rhid_pessoas('e7900000-0000-4000-8000-000000000101', $$[
  {"cpf": 52998224725, "name": "ANA SOUZA"}, {"cpf": 11144477735, "name": "BRUNO LIMA", "registration": "2"},
  {"cpf": 4567891230, "name": "CARLA DIAS"}, {"cpf": 15350946056, "name": "DAVI ROCHA"}
]$$);
select teste.ok('Davi ligado automaticamente na 2ª importação de pessoas',
  (select funcionario_id = 'e7900000-0000-4000-8000-000000000305' and vinculo = 'automatico'
     from public.controlid_usuarios where integracao_id = 'e7900000-0000-4000-8000-000000000101' and user_id_externo = '15350946056'));

-- ------------------------------------------------ deduplicação com o AFD enviado pelo site + troca para RHiD
select teste.como_dono();
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e7900000-0000-4000-8000-000000000102', 'e7900000-0000-4000-8000-00000000000a', 'controlid_rep', 'REP MACAW',
   '{"modelo": "iDClass", "identificador": "cpf"}');
insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, nome, cpf, funcionario_id, vinculo) values
  ('e7900000-0000-4000-8000-00000000000a', 'e7900000-0000-4000-8000-000000000102', '52998224725', 'ANA SOUZA', '52998224725',
   'e7900000-0000-4000-8000-000000000301', 'manual'),
  ('e7900000-0000-4000-8000-00000000000a', 'e7900000-0000-4000-8000-000000000102', '99999999999', 'SEM FICHA', '99999999999', null, null);
select teste.como_servico();
select public.ingestao_controlid_batidas('e7900000-0000-4000-8000-000000000102',
  '[{"nsr": 500, "instante": "2026-10-05T17:00:00-03:00", "cpf": "52998224725"}]');
insert into r_bat select 4, public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000101', '55', $$[
  {"nsr": 200, "instante": "2026-10-05T17:00:00-03:00", "cpf": "52998224725"},
  {"nsr": 201, "instante": "2026-10-05T21:00:00-03:00", "cpf": "52998224725"}
]$$);
select teste.ok('marcação já importada pelo REP/arquivo (mesmo CPF e instante) conta como duplicada; cursor avança',
  (select (r ->> 'ja_importadas_por_outra_fonte')::int = 1 and (r ->> 'duplicados')::int = 1 and (r ->> 'gravados')::int = 1
          and (r ->> 'ultimo_nsr')::int = 201 from r_bat where n = 4));
select teste.erro('ingestão RHiD recusa integração de outro tipo',
  $$select public.ingestao_rhid_batidas('e7900000-0000-4000-8000-000000000102', '55', '[]')$$,
  'Tipo de integração incompatível', '22023');

select teste.como('rhid.ger.a@teste.local');
select teste.erro('gerente não troca o relógio', $$select public.integracao_trocar_para_rhid('e7900000-0000-4000-8000-000000000102')$$,
  'Sem permissão', '42501');
select teste.como('rhid.adm.b@teste.local');
select teste.erro('admin de outra empresa não troca', $$select public.integracao_trocar_para_rhid('e7900000-0000-4000-8000-000000000102')$$,
  'Sem permissão', '42501');
select teste.como('rhid.adm.a@teste.local');
select teste.erro('só controlid_rep pode ser trocado', $$select public.integracao_trocar_para_rhid('e7900000-0000-4000-8000-000000000101')$$,
  'Tipo de integração incompatível', '22023');
create temp table troca on commit drop as select public.integracao_trocar_para_rhid('e7900000-0000-4000-8000-000000000102') as id;
grant select on troca to authenticated, service_role, anon;
select teste.ok('troca: nova integração RHiD ativa com padrões; a antiga fica inativa',
  (select i.tipo = 'rhid' and i.ativa and i.parametros @> '{"incluir_rep_p": true, "importar_pessoas": true}'
          and i.parametros ->> 'substitui' = 'e7900000-0000-4000-8000-000000000102'
     from public.integracoes i where i.id = (select id from troca))
  and (select not ativa from public.integracoes where id = 'e7900000-0000-4000-8000-000000000102'));
select teste.ok('troca mantém os vínculos (manual inclusive) e os CPFs sem ficha',
  (select count(*) = 2 and bool_or(user_id_externo = '52998224725' and funcionario_id = 'e7900000-0000-4000-8000-000000000301'
                                   and vinculo = 'manual')
     from public.controlid_usuarios where integracao_id = (select id from troca)));
select teste.ok('trocar de novo devolve a mesma integração', public.integracao_trocar_para_rhid('e7900000-0000-4000-8000-000000000102') = (select id from troca));
select teste.ok('batidas antigas continuam no ponto (integração inativa)',
  exists (select 1 from public.ponto_batidas where integracao_id = 'e7900000-0000-4000-8000-000000000102'
            and funcionario_id = 'e7900000-0000-4000-8000-000000000301'));

-- ------------------------------------------------------------------ painel
select teste.ok('painel mostra a integração RHiD na sincronização',
  (select bool_or(x ->> 'tipo' = 'rhid')
     from jsonb_array_elements(public.painel_do_dia('e7900000-0000-4000-8000-00000000000a') -> 'sincronizacao') x));
rollback;
