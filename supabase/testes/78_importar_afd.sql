-- 78_importar_afd.sql — importação do AFD pelo site (RHiD/arquivo): relógio por arquivo sem segredos, ponto_importar_afd
-- (mesma regra da ingestão do N8N), empregados do registro tipo 5, "Ligar funcionários" (provisórios da escala), permissões.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
-- testes com datas antigas: alarmes sem o prazo de 2 dias da empresa (revertido no rollback)
alter table public.empresas alter column ponto_alarme_prazo_dias set default 31;
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e7800000-0000-4000-8000-00000000000a', 'Teste AFD A', 'America/Sao_Paulo', '05:00'),
  ('e7800000-0000-4000-8000-00000000000b', 'Teste AFD B', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e7800000-0000-4000-8000-000000000a01', 'afd.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e7800000-0000-4000-8000-000000000a02', 'afd.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e7800000-0000-4000-8000-000000000a03', 'afd.lei.a@teste.local', '{"nome":"Leitura A"}'),
  ('e7800000-0000-4000-8000-000000000b01', 'afd.adm.b@teste.local', '{"nome":"Adm B"}');
update public.perfis set papel = 'administrador', empresa_id = 'e7800000-0000-4000-8000-00000000000a' where id = 'e7800000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e7800000-0000-4000-8000-00000000000a' where id = 'e7800000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e7800000-0000-4000-8000-00000000000a' where id = 'e7800000-0000-4000-8000-000000000a03';
update public.perfis set papel = 'administrador', empresa_id = 'e7800000-0000-4000-8000-00000000000b' where id = 'e7800000-0000-4000-8000-000000000b01';
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e7800000-0000-4000-8000-000000000201', 'e7800000-0000-4000-8000-00000000000a', 'Salão noite AFD', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values
  ('e7800000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
-- Ana tem CPF na ficha; "Garçom 1" e "Garçom 2" são provisórios da escala (sem CPF)
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, pontos_comissao, data_admissao) values
  ('e7800000-0000-4000-8000-000000000301', 'e7800000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', '52998224725', 10, '2026-01-01'),
  ('e7800000-0000-4000-8000-000000000302', 'e7800000-0000-4000-8000-00000000000a', 'Garçom 1', 'Garçom', null, 0, '2026-01-01'),
  ('e7800000-0000-4000-8000-000000000303', 'e7800000-0000-4000-8000-00000000000a', 'Garçom 2', 'Garçom', null, 0, '2026-01-01');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e7800000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e7800000-0000-4000-8000-000000000301', 'e7800000-0000-4000-8000-000000000302',
                    'e7800000-0000-4000-8000-000000000303']::uuid[]) f;
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e7800000-0000-4000-8000-000000000101', 'e7800000-0000-4000-8000-00000000000a', 'zig', 'Zig AFD', '{"rede":"r"}');
select public.ponto_apurar(f, '2026-10-03', '2026-10-03')
  from unnest(array['e7800000-0000-4000-8000-000000000302', 'e7800000-0000-4000-8000-000000000303']::uuid[]) f;

select teste.ok('nome_proprio: maiúsculas do AFD → nome próprio',
  public.nome_proprio(' MARIA  DA SILVA E SOUZA ') = 'Maria da Silva e Souza' and public.nome_proprio('') is null
  and public.nome_proprio('DE LIMA') = 'De Lima');

-- ------------------------------------------------------------------ relógio por arquivo
select teste.como('afd.lei.a@teste.local');
select teste.erro('leitura não cria o relógio por arquivo', $$select public.ponto_integracao_arquivo()$$, 'Sem permissão', '42501');
select teste.como('afd.ger.a@teste.local');
create temp table rel on commit drop as select public.ponto_integracao_arquivo() as id;
grant select on rel to authenticated, service_role, anon;
select teste.ok('gerente cria o relógio por arquivo (sem segredos, fonte arquivo, RHiD)',
  (select (i.tipo, i.nome, i.parametros ->> 'fonte', i.parametros ->> 'modelo', i.ativa)
          = ('controlid_rep'::text, 'Relógio de ponto (RHiD/arquivo)'::text, 'arquivo'::text, 'RHiD'::text, true)
     from public.integracoes i where i.id = (select id from rel))
  and public.integracao_segredos_preenchidos((select id from rel)) = '{}');
select teste.ok('segunda chamada devolve o mesmo relógio', public.ponto_integracao_arquivo() = (select id from rel));
select teste.erro('"Sincronizar agora" no relógio por arquivo', $$select public.sync_solicitar((select id from rel), 'batidas')$$,
  'Relógio por arquivo: use Importar AFD', '22023');
select teste.ok('"Sincronizar tudo" da empresa não enfileira o relógio por arquivo',
  public.sync_solicitar(null, 'batidas', null, null, '{}', 'e7800000-0000-4000-8000-00000000000a') = 0);
select teste.como_servico();
select teste.ok('agendador do N8N não vê o relógio por arquivo',
  not exists (select 1 from public.ingestao_integracoes_ativas('controlid_rep') x where x.integracao_id = (select id from rel)));

-- ------------------------------------------------------------------ importar
create temp table afd (marcacoes jsonb, empregados jsonb) on commit drop;
grant select on afd to authenticated, service_role, anon;
insert into afd values ($$[
  {"id_externo": "101", "nsr": 101, "instante": "2026-10-03T16:58:00-03:00", "cpf": "52998224725"},
  {"id_externo": "102", "nsr": 102, "instante": "2026-10-03T21:01:00-03:00", "cpf": "52998224725"},
  {"id_externo": "103", "nsr": 103, "instante": "2026-10-03T21:29:00-03:00", "cpf": "52998224725"},
  {"id_externo": "104", "nsr": 104, "instante": "2026-10-04T01:02:00-03:00", "cpf": "52998224725"},
  {"id_externo": "105", "nsr": 105, "instante": "2026-10-03T17:05:00-03:00", "cpf": "11144477735"},
  {"id_externo": "106", "nsr": 106, "instante": "2026-10-04T01:00:00-03:00", "cpf": "11144477735"},
  {"id_externo": "107", "nsr": 107, "instante": "2026-10-03T17:10:00-03:00", "cpf": "39053344705"},
  {"id_externo": "108", "nsr": 108, "instante": "2026-10-03T17:10:00-03:00"}
]$$, $$[
  {"cpf": "111.444.777-35", "nome": "BRUNO  LIMA", "operacao": "I"},
  {"cpf": "52998224725", "nome": "ANA SOUZA"},
  {"cpf": "abc", "nome": "LIXO"}
]$$);

select teste.como('afd.lei.a@teste.local');
select teste.erro('leitura não importa', $$select public.ponto_importar_afd((select id from rel), '[]')$$, 'Sem permissão', '42501');
select teste.como('afd.adm.b@teste.local');
select teste.erro('admin de outra empresa não importa', $$select public.ponto_importar_afd((select id from rel), '[]')$$, 'Sem permissão', '42501');
select teste.como('afd.ger.a@teste.local');
select teste.erro('Zig não recebe AFD', $$select public.ponto_importar_afd('e7800000-0000-4000-8000-000000000101', '[]')$$,
  'Tipo de integração incompatível', '22023');
select teste.erro('limite de 5000 marcações por chamada', $$select public.ponto_importar_afd((select id from rel),
  (select jsonb_agg(jsonb_build_object('nsr', g, 'instante', '2026-10-01T10:00:00-03:00', 'cpf', '52998224725')) from generate_series(1, 5001) g))$$,
  'Lote maior que 5000 marcações', '22023');

create temp table r1 on commit drop as
  select public.ponto_importar_afd((select id from rel), (select marcacoes from afd), (select empregados from afd), 'AFD_rhid.txt') as r;
grant select on r1 to authenticated, service_role, anon;
select teste.ok('contagens: 8 lidas, 7 gravadas, 1 ignorada, 0 duplicadas, 1 dia reapurado',
  (select r @> '{"lidas": 8, "gravadas": 7, "ignoradas": 1, "duplicadas": 0, "dias_reapurados": 1}' from r1));
select teste.ok('erro por item com o índice do arquivo', (select r -> 'erros' = '[{"indice": 7, "motivo": "sem CPF/PIS"}]' from r1));
select teste.ok('período lido (dia de trabalho)', (select r -> 'periodo' = '{"inicio": "2026-10-03", "fim": "2026-10-03"}' from r1));
select teste.ok('empregados: 2 lidos, 2 novos, Ana ligada automaticamente pelo CPF da ficha',
  (select r -> 'empregados' = '{"lidos": 2, "novos": 2, "atualizados": 0, "vinculados_automaticamente": 1}' from r1));
select teste.ok('sem funcionário: CPF + nome do AFD + quantidade (o mais frequente primeiro)',
  (select jsonb_path_query_array(r, '$.sem_funcionario[*].cpf') = '["11144477735", "39053344705"]'
      and jsonb_path_query_array(r, '$.sem_funcionario[*].nome') = '["BRUNO LIMA", null]'
      and jsonb_path_query_array(r, '$.sem_funcionario[*].quantidade') = '[2, 1]' from r1));
select teste.ok('Ana apurada: 03/10 completo', (select situacao from public.ponto_dias
   where funcionario_id = 'e7800000-0000-4000-8000-000000000301' and data = '2026-10-03') = 'completo');
select teste.ok('usuários do relógio: 3 CPFs (Ana automático; Bruno com nome; o outro sem nome)',
  (select array_agg((user_id_externo, coalesce(nome, '-'), coalesce(vinculo, '-'))::text order by user_id_externo)
     from public.controlid_usuarios where integracao_id = (select id from rel))
  = array['(11144477735,"BRUNO LIMA",-)', '(39053344705,-,-)', '(52998224725,"ANA SOUZA",automatico)']);
select teste.ok('execução registrada: controlid_batidas, manual, origem arquivo, parcial, contagens',
  (select (tipo, gatilho, status, registros_lidos, registros_gravados, registros_ignorados, detalhes ->> 'origem', detalhes ->> 'arquivo',
           periodo_inicio, periodo_fim)
          = ('controlid_batidas'::text, 'manual'::text, 'parcial'::text, 8, 7, 1, 'arquivo'::text, 'AFD_rhid.txt'::text,
             '2026-10-03'::date, '2026-10-03'::date)
     from public.sync_execucoes where id = (select (r ->> 'execucao_id')::uuid from r1)));
select teste.ok('integração: cursor por NSR e último status gravados (em nome do usuário)',
  (select ((cursor ->> 'ultimo_nsr')::int, ultimo_status, ultimo_sucesso_em is not null)
          = (107, 'parcial'::text, true) from public.integracoes where id = (select id from rel)));
select teste.ok('flag de ingestão por arquivo não vaza para o resto da transação',
  coalesce(current_setting('app.ingestao_arquivo', true), '') = '');

-- reimportar: idempotente; cursor não regride com um arquivo mais antigo
create temp table r2 on commit drop as
  select public.ponto_importar_afd((select id from rel), (select marcacoes from afd), (select empregados from afd)) as r;
select teste.ok('reimportar o mesmo AFD: 0 gravadas, 7 duplicadas, 0 dias, empregados atualizados',
  (select r @> '{"lidas": 8, "gravadas": 0, "duplicadas": 7, "dias_reapurados": 0}'
      and r -> 'empregados' @> '{"novos": 0, "atualizados": 2}' from r2)
  and (select count(*) from public.ponto_batidas where integracao_id = (select id from rel)) = 7);
select public.ponto_importar_afd((select id from rel),
  '[{"nsr": 5, "instante": "2026-09-01T10:00:00-03:00", "cpf": "52998224725"}]');
select teste.ok('cursor não regride', (select (cursor ->> 'ultimo_nsr')::int from public.integracoes where id = (select id from rel)) = 107);

-- AFD do RHiD só com cadastro (registro tipo 5, sem marcações): os empregados entram para o vínculo
create temp table r4 on commit drop as select public.ponto_importar_afd((select id from rel), '[]',
  '[{"cpf": "71428793860", "nome": "FUNCIONÁRIO JÚNIOR", "operacao": "A"}]', 'AFD_cadastro.txt') as r;
select teste.ok('só empregados: 0 marcações, 1 empregado novo, execução com sucesso',
  (select r @> '{"lidas": 0, "gravadas": 0, "empregados": {"lidos": 1, "novos": 1}}' and r -> 'periodo' = '{"inicio": null, "fim": null}' from r4)
  and (select (status, registros_lidos) = ('sucesso'::text, 0) from public.sync_execucoes where id = (select (r ->> 'execucao_id')::uuid from r4)));
select teste.ok('… e aparece nos pendentes (sem batida) com o nome sugerido',
  exists (select 1 from public.ponto_afd_pendentes((select id from rel)) x
           where x.cpf = '71428793860' and x.quantidade = 0 and x.nome_sugerido = 'Funcionário Júnior'));
select teste.como_dono();
delete from public.controlid_usuarios where integracao_id = (select id from rel) and user_id_externo = '71428793860';
select teste.como('afd.ger.a@teste.local');

-- ------------------------------------------------------------------ ligar funcionários
create temp table pend on commit drop as select * from public.ponto_afd_pendentes((select id from rel));
grant select on pend to authenticated, service_role, anon;
select teste.ok('pendentes: Bruno (2 batidas, nome sugerido) e o CPF sem nome (1)',
  (select array_agg((coalesce(cpf, '-'), coalesce(nome_sugerido, '-'), quantidade, primeira)::text order by quantidade desc) from pend)
  = array['(11144477735,"Bruno Lima",2,2026-10-03)', '(39053344705,-,1,2026-10-03)']);
select teste.ok('antes de ligar: Garçom 1 ausente em 03/10 com alarme de dia escalado sem batida',
  (select situacao from public.ponto_dias where funcionario_id = 'e7800000-0000-4000-8000-000000000302' and data = '2026-10-03') = 'ausente'
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e7800000-0000-4000-8000-000000000302'
                and data = '2026-10-03' and tipo = 'sem_batida_dia_escalado' and status = 'aberto'));

create temp table l1 on commit drop as
  select public.ponto_afd_ligar((select controlid_usuario_id from pend where cpf = '11144477735'),
                                'e7800000-0000-4000-8000-000000000302', true, true) as r;
select teste.ok('ligar Bruno ao provisório "Garçom 1", renomeando e gravando o CPF',
  (select r @> '{"nome": "Bruno Lima", "renomeado": true, "documento_cadastrado": true, "batidas": 2}' from l1)
  and (select (nome, cpf) = ('Bruno Lima'::text, '11144477735'::text) from public.funcionarios where id = 'e7800000-0000-4000-8000-000000000302')
  and (select (funcionario_id, vinculo) = ('e7800000-0000-4000-8000-000000000302'::uuid, 'manual'::text)
         from public.controlid_usuarios where integracao_id = (select id from rel) and user_id_externo = '11144477735'));
select teste.ok('batidas pendentes passam ao funcionário e o dia é reapurado (alarmes de batida faltando)',
  (select count(*) from public.ponto_batidas where integracao_id = (select id from rel) and pessoa_externa = '11144477735'
     and funcionario_id = 'e7800000-0000-4000-8000-000000000302') = 2
  and (select (batidas_validas, situacao) = (2::smallint, 'incompleto'::text) from public.ponto_dias
         where funcionario_id = 'e7800000-0000-4000-8000-000000000302' and data = '2026-10-03')
  and not exists (select 1 from public.ponto_alarmes where funcionario_id = 'e7800000-0000-4000-8000-000000000302'
                    and data = '2026-10-03' and tipo = 'sem_batida_dia_escalado' and status = 'aberto')
  and (select count(*) from public.ponto_alarmes where funcionario_id = 'e7800000-0000-4000-8000-000000000302'
         and data = '2026-10-03' and tipo = 'batida_faltando' and status = 'aberto') = 2);
select teste.erro('CPF já cadastrado em outro funcionário', $$select public.ponto_afd_ligar(
    (select controlid_usuario_id from pend where cpf = '11144477735'), 'e7800000-0000-4000-8000-000000000303', false, true)$$,
  'CPF já cadastrado em outro funcionário', '23505');

-- só o vínculo (sem renomear nem CPF na ficha): a próxima importação já cai no funcionário
select teste.ok('ligar o outro CPF ao "Garçom 2" sem mexer na ficha',
  public.ponto_afd_ligar((select controlid_usuario_id from pend where cpf = '39053344705'), 'e7800000-0000-4000-8000-000000000303')
    @> '{"renomeado": false, "documento_cadastrado": false, "batidas": 1}'
  and (select (nome, cpf) is not distinct from ('Garçom 2'::text, null::text) from public.funcionarios where id = 'e7800000-0000-4000-8000-000000000303'));
create temp table r3 on commit drop as select public.ponto_importar_afd((select id from rel),
  '[{"nsr": 109, "instante": "2026-10-03T21:00:00-03:00", "cpf": "39053344705"}]') as r;
select teste.ok('nova marcação do CPF ligado vai direto ao funcionário (vínculo do relógio)',
  (select r @> '{"gravadas": 1, "dias_reapurados": 1}' and r -> 'sem_funcionario' = '[]' from r3)
  and (select funcionario_id from public.ponto_batidas where integracao_id = (select id from rel) and id_externo = '109')
      = 'e7800000-0000-4000-8000-000000000303');
select teste.ok('pendentes: lista vazia depois de ligar', not exists (select 1 from public.ponto_afd_pendentes((select id from rel))));
select public.funcionario_vincular_controlid(
  (select id from public.controlid_usuarios where integracao_id = (select id from rel) and user_id_externo = '39053344705'), null);
select teste.ok('desvincular (REP): as batidas voltam a ficar sem funcionário e o dia é reapurado',
  (select count(*) from public.ponto_batidas where integracao_id = (select id from rel) and pessoa_externa = '39053344705'
     and funcionario_id is null) = 2
  and (select batidas_validas from public.ponto_dias where funcionario_id = 'e7800000-0000-4000-8000-000000000303' and data = '2026-10-03') = 0);

select teste.como('afd.lei.a@teste.local');
select teste.erro('leitura não liga funcionários', $$select public.ponto_afd_ligar(
  (select controlid_usuario_id from pend where cpf = '39053344705'), 'e7800000-0000-4000-8000-000000000303')$$, 'Sem permissão', '42501');
select teste.erro('leitura não lista pendentes', $$select * from public.ponto_afd_pendentes((select id from rel))$$, 'Sem permissão', '42501');
select teste.como('afd.adm.a@teste.local');
update public.integracoes set ativa = false where id = (select id from rel);
select teste.erro('relógio inativo não importa', $$select public.ponto_importar_afd((select id from rel), '[]')$$, 'Integração inativa', '22023');
select teste.ok('pedir o relógio por arquivo devolve o existente', public.ponto_integracao_arquivo() = (select id from rel));
select teste.ok('… e o reativa', (select ativa from public.integracoes where id = (select id from rel)));
select teste.como(null);
select teste.erro('anon não importa', $$select public.ponto_importar_afd(gen_random_uuid(), '[]')$$, null, '42501');
select teste.como_dono();

rollback;
