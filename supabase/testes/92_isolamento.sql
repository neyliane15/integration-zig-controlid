-- 92_isolamento.sql (revisão 1) — isolamento entre empresas em TODAS as tabelas de public, varrendo o catálogo.
-- Usa a carga de demonstração (empresa A "Bar Bossa Nova" e B "Cantina Roma"), completa as tabelas que a carga não
-- preenche e, para cada tabela com empresa_id (e para `empresas`), vestindo usuários de uma empresa:
--   * não enxerga nenhuma linha da outra;  * update/delete em linhas da outra afeta 0 linhas (ou é negado);
--   * não consegue inserir uma cópia de uma linha da outra (nem trocando o empresa_id para a própria).
-- Tabela nova entra no teste sozinha (o catálogo é varrido), então este arquivo protege as migrações futuras.
begin;
select teste.como_dono();

-- ------------------------------------------------------------------ completa A e B com linhas em todas as tabelas
do $$
declare
  a uuid := 'a0000000-0000-4000-8000-00000000000a';
  b uuid := 'b0000000-0000-4000-8000-00000000000b';
  ana uuid := 'a0000000-0000-4000-8000-000000000301';
  paolo uuid := 'b0000000-0000-4000-8000-000000000301';
  h uuid;
  ib uuid;
begin
  perform public.funcionario_definir_senha(ana, '1234');
  perform public.funcionario_definir_senha(paolo, '4321');
  perform public.funcionario_adicionar_cartao(ana, '1000001');
  perform public.funcionario_adicionar_cartao(paolo, '2000002');
  insert into storage.buckets (id, name) values ('funcionarios-fotos', 'funcionarios-fotos') on conflict do nothing;
  insert into storage.objects (bucket_id, name) values
    ('funcionarios-fotos', a || '/' || ana || '/f.jpg'), ('funcionarios-fotos', b || '/' || paolo || '/f.jpg');
  perform public.funcionario_definir_foto(ana, a || '/' || ana || '/f.jpg');
  perform public.funcionario_definir_foto(paolo, b || '/' || paolo || '/f.jpg');
  insert into public.controlid_horarios (empresa_id, nome) values (a, 'Iso A') returning id into h;
  insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim) values (h, 1, '08:00', '18:00');
  insert into public.funcionario_horarios (funcionario_id, horario_id) values (ana, h);
  insert into public.controlid_horarios (empresa_id, nome) values (b, 'Iso B') returning id into h;
  insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim) values (h, 1, '08:00', '18:00');
  insert into public.funcionario_horarios (funcionario_id, horario_id) values (paolo, h);
  update public.integracoes set parametros = parametros || '{"envio": {"ativo": true}}'
   where id = 'a0000000-0000-4000-8000-000000000102';
  insert into public.integracoes (empresa_id, tipo, nome, parametros) values (b, 'controlid_acesso', 'Iso B', '{"envio": {"ativo": true}}')
  returning id into ib;
  perform public.integracao_definir_segredos(ib, '{"url": "http://10.0.0.1", "login": "admin", "senha": "x"}');
  insert into public.controlid_usuarios (integracao_id, user_id_externo, nome) values (ib, '77', 'Paolo');
  perform public.sync_solicitar(ib, 'funcionarios', null, null, '{}', b);
  perform public.ingestao_sync_iniciar('controlid_usuarios', 'manual', 'teste', b, ib);
  perform public.ponto_incluir_batida(paolo, public.agora() - interval '1 hour', 'iso');
  perform public.ponto_abonar(public.dia_de_trabalho_atual(b) - 3, public.dia_de_trabalho_atual(b) - 3, 'folga', 'iso', paolo, b);
  perform public.banco_horas_lancar(paolo, public.dia_de_trabalho_atual(b) - 3, 'ajuste', 30, 'iso');
  insert into public.tarefas_rotinas (empresa_id, titulo) values (b, 'Iso B') returning id into h;
  insert into public.tarefas_rotina_itens (rotina_id, texto) values (h, 'item');
  perform public.tarefas_gerar_do_dia(null, b);
  -- o mesmo para A (a carga demo não gera estas linhas)
  insert into public.controlid_usuarios (integracao_id, user_id_externo, nome) values ('a0000000-0000-4000-8000-000000000102', '9001', 'Iso A');
  perform public.sync_solicitar('a0000000-0000-4000-8000-000000000101', 'vendas', null, null, '{}', a);
  perform public.ingestao_sync_iniciar('zig_importar', 'manual', 'teste', a, 'a0000000-0000-4000-8000-000000000101');
  perform public.ponto_incluir_batida(ana, public.agora() - interval '1 hour', 'iso');
  perform public.ponto_abonar(public.dia_de_trabalho_atual(a) - 3, public.dia_de_trabalho_atual(a) - 3, 'folga', 'iso', ana, a);
  perform public.banco_horas_lancar(ana, public.dia_de_trabalho_atual(a) - 3, 'ajuste', 30, 'iso');
  perform public.tarefas_gerar_do_dia(null, a);
  insert into public.jornadas (empresa_id, nome) values (b, 'Iso B') returning id into h;
  insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) values (h, 1, '08:00', '17:00');
  insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde) values (paolo, h, '2025-01-02');
end $$;

-- ------------------------------------------------------------------ catálogo: tabelas com empresa_id (+ empresas)
create temp table _tabs on commit drop as
select c.relname::text as t, case when c.relname = 'empresas' then 'id' else 'empresa_id' end as col,
       coalesce(substring(obj_description(c.oid, 'pg_class') from '^\s*(\[[a-z_:]+\])'), '') as etiqueta
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
   and (c.relname = 'empresas'
        or exists (select 1 from pg_attribute at where at.attrelid = c.oid and at.attname = 'empresa_id' and not at.attisdropped));
-- colunas FK (fora empresa_id) que apontam para outra tabela com dados de empresa: uma cópia com o empresa_id trocado
-- só é "vazamento" se carregar uma dessas referências para a outra empresa (copiar uma linha-raiz é só cadastrar algo igual)
alter table _tabs add column fks text[], add column cols text;
-- colunas inseríveis (sem geradas nem identity always)
update _tabs t set cols = (
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) from pg_attribute a
   where a.attrelid = ('public.' || t.t)::regclass and a.attnum > 0 and not a.attisdropped
     and a.attgenerated = '' and a.attidentity <> 'a');
update _tabs t set fks = coalesce((
  select array_agg(distinct a.attname::text)
    from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
   where k.conrelid = ('public.' || t.t)::regclass and k.contype = 'f' and a.attname <> 'empresa_id'
     and k.confrelid in (select ('public.' || t2.t)::regclass from _tabs t2 where t2.t <> 'empresas')), '{}');

-- uma linha de cada empresa por tabela (como dono, que enxerga tudo)
create temp table _amostras (t text, empresa uuid, linha jsonb) on commit drop;
do $$
declare r record; v jsonb; e uuid;
begin
  for r in select * from _tabs loop
    foreach e in array array['a0000000-0000-4000-8000-00000000000a', 'b0000000-0000-4000-8000-00000000000b']::uuid[] loop
      execute format('select to_jsonb(x) from public.%I x where %I = $1 limit 1', r.t, r.col) into v using e;
      if v is not null then insert into _amostras values (r.t, e, v); end if;
    end loop;
  end loop;
end $$;

select teste.ok('toda tabela com empresa_id tem dados da empresa A para o teste ' || (select coalesce(string_agg(t, ', '), '') from _tabs where t not in (select t from _amostras where empresa = 'a0000000-0000-4000-8000-00000000000a')),
  (select coalesce(string_agg(t, ', '), '') from _tabs where t not in (select t from _amostras where empresa = 'a0000000-0000-4000-8000-00000000000a')) = '');
select teste.ok('e quase todas têm dados da empresa B (exceto as da Zig/comissão, que B não usa)',
  (select count(*) from _amostras where empresa = 'b0000000-0000-4000-8000-00000000000b') >= (select count(*) from _tabs) - 10);

create temp table _falhas (quem text, t text, problema text) on commit drop;
grant select on _tabs, _amostras to authenticated;
grant insert, select on _falhas to authenticated;

-- ------------------------------------------------------------------ verificação (roda vestido de cada usuário)
create temp table _ctx (quem text, propria uuid, alheia uuid) on commit drop;
grant select on _ctx to authenticated;

create or replace function pg_temp.verificar_isolamento() returns void language plpgsql as $f$
declare
  r record; c record; n bigint; v_estado text; v_msg text; v_linha jsonb;
begin
  select * into c from _ctx;
  for r in select * from _tabs loop
    -- leitura
    begin
      execute format('select count(*) from public.%I where %I = $1', r.t, r.col) into n using c.alheia;
    exception when insufficient_privilege then n := 0;
    end;
    if n > 0 then insert into _falhas values (c.quem, r.t, format('enxerga %s linha(s) da outra empresa', n)); end if;
    -- update
    begin
      execute format('update public.%I set %I = %I where %I = $1', r.t, r.col, r.col, r.col) using c.alheia;
      get diagnostics n = row_count;
    exception when others then n := 0;
    end;
    if n > 0 then insert into _falhas values (c.quem, r.t, format('alterou %s linha(s) da outra empresa', n)); end if;
    -- delete
    begin
      execute format('delete from public.%I where %I = $1', r.t, r.col) using c.alheia;
      get diagnostics n = row_count;
    exception when others then n := 0;
    end;
    if n > 0 then insert into _falhas values (c.quem, r.t, format('apagou %s linha(s) da outra empresa', n)); end if;
    -- insert: cópia de uma linha da outra empresa (como está e com o empresa_id trocado para a própria)
    for v_linha in
      select a.linha || jsonb_build_object('id', gen_random_uuid()) from _amostras a where a.t = r.t and a.empresa = c.alheia
      union all
      select a.linha || jsonb_build_object('id', gen_random_uuid(), r.col, c.propria) from _amostras a
       where a.t = r.t and a.empresa = c.alheia and r.t <> 'empresas'
         and exists (select 1 from unnest(r.fks) k where a.linha ->> k is not null)
    loop
      begin
        execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
                       r.t, r.cols, r.cols, r.t) using v_linha;
        insert into _falhas values (c.quem, r.t, 'inseriu cópia de linha da outra empresa');
      exception when others then
        get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
        if v_estado = '23505' then   -- duplicidade não prova a proteção (a RLS é checada antes, mas registra para análise)
          insert into _falhas values (c.quem, r.t, 'inserção barrada só por duplicidade: ' || v_msg);
        end if;
      end;
    end loop;
  end loop;
end $f$;
grant execute on function pg_temp.verificar_isolamento() to authenticated;

insert into _ctx values ('admin B', 'b0000000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-00000000000a');
select teste.como('admin@cantinaroma.com.br');
select pg_temp.verificar_isolamento();
select teste.como_dono();
update _ctx set quem = 'admin A', propria = 'a0000000-0000-4000-8000-00000000000a', alheia = 'b0000000-0000-4000-8000-00000000000b';
select teste.como('admin@barbossanova.com.br');
select pg_temp.verificar_isolamento();
select teste.como_dono();
update _ctx set quem = 'gerente A';
select teste.como('gerente@barbossanova.com.br');
select pg_temp.verificar_isolamento();
select teste.como_dono();
update _ctx set quem = 'leitura A';
select teste.como('leitura@barbossanova.com.br');
select pg_temp.verificar_isolamento();
select teste.como_dono();

select teste.ok('isolamento entre empresas em todas as tabelas: ' ||
  coalesce((select string_agg(format('[%s] %s: %s', quem, t, problema), '; ' order by quem, t) from _falhas), 'nenhuma falha'),
  not exists (select 1 from _falhas));
select teste.ok('varreu ao menos 35 tabelas', (select count(*) from _tabs) >= 35);

-- referências cruzadas: filho da própria empresa apontando para pai da outra
create temp table _ids on commit drop as
select (select id from public.controlid_horarios where nome = 'Iso A') as horario_a,
       (select id from public.controlid_usuarios where integracao_id = 'a0000000-0000-4000-8000-000000000102' limit 1) as cu_a;
grant select on _ids to authenticated;
select teste.como('admin@cantinaroma.com.br');
select teste.erro('B não liga funcionário de B a jornada de A',
  $$insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
    values ('b0000000-0000-4000-8000-000000000301', 'a0000000-0000-4000-8000-000000000201', '2026-01-01')$$);
select teste.erro('B não liga funcionário de B a horário de acesso de A',
  $$insert into public.funcionario_horarios (funcionario_id, horario_id)
    values ('b0000000-0000-4000-8000-000000000301', (select horario_a from _ids))$$);
select teste.erro('B não cria tarefa com responsável de A',
  $$insert into public.tarefas (empresa_id, data, titulo, responsavel_funcionario_id)
    values ('b0000000-0000-4000-8000-00000000000b', '2026-10-06', 'x', 'a0000000-0000-4000-8000-000000000301')$$);
select teste.erro('B não vincula usuário Control iD de A', $$select public.funcionario_vincular_controlid(
    (select cu_a from _ids),
    'b0000000-0000-4000-8000-000000000301')$$);
select teste.erro('B não lê espelho de funcionário de A', $$select * from public.ponto_espelho(
    'a0000000-0000-4000-8000-000000000301', '2026-10-01', '2026-10-05')$$, 'Sem permissão');
select teste.erro('B não lê credenciais de funcionário de A',
  $$select public.funcionario_credenciais('a0000000-0000-4000-8000-000000000301')$$, 'Sem permissão');
select teste.erro('B não pede sincronização de integração de A',
  $$select public.sync_solicitar('a0000000-0000-4000-8000-000000000101', 'vendas')$$, 'Sem permissão');
select teste.erro('B não lê vendas de A', $$select * from public.vendas_resumo('2026-09-01', '2026-09-30', null,
    'a0000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.erro('B não lê painel de A', $$select public.painel_do_dia('a0000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');
select teste.ok('B não lê fotos (Storage) de A',
  teste.contar($$select 1 from storage.objects where name like 'a0000000-0000-4000-8000-00000000000a/%'$$) = 0);
select teste.erro('B não grava foto na pasta de A no Storage',
  $$insert into storage.objects (bucket_id, name) values ('funcionarios-fotos',
    'a0000000-0000-4000-8000-00000000000a/a0000000-0000-4000-8000-000000000301/x.jpg')$$);
rollback;
