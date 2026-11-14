-- Meu Dia de Gerente — instalação do banco, PARTE 17 DE 17.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000280_escala.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
create or replace function public.escala_trocar(p_funcionario_a uuid, p_data_a date, p_funcionario_b uuid default null,
                                                p_data_b date default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ma public.escala_membros; mb public.escala_membros; v_motivo text; v_datas date[]; v_d date;
  ca record; cb record; v_out jsonb := '[]';
begin
  ma := public.escala_membro_para_operar(p_funcionario_a);
  if (p_funcionario_b is null and p_data_b is null) or p_funcionario_b = p_funcionario_a and p_data_b is null then
    raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023';
  end if;
  if p_funcionario_b is not null and p_funcionario_b <> p_funcionario_a then
    mb := public.escala_membro_para_operar(p_funcionario_b);
    if mb.empresa_id <> ma.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  end if;
  v_motivo := coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Troca de folga');
  perform public.escala_validar_data(ma.empresa_id, p_data_a);
  if p_data_b is not null then perform public.escala_validar_data(ma.empresa_id, p_data_b); end if;

  if mb.id is null then
    -- A troca o próprio status entre os dois dias
    if p_data_b = p_data_a then raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023'; end if;
    select * into ca from public.escala_calcular(ma.empresa_id, p_data_a, p_data_a, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, p_data_b, p_data_b, p_funcionario_a) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_gravar_dia(ma.id, p_data_a, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(ma.id, p_data_b, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], least(p_data_a, p_data_b), least(p_data_a, p_data_b));
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], greatest(p_data_a, p_data_b), greatest(p_data_a, p_data_b));
    select jsonb_agg(public.escala_dia_json(ma.empresa_id, p_funcionario_a, d, true) order by d) into v_out
      from unnest(array[p_data_a, p_data_b]) d;
    return v_out;
  end if;

  -- A e B trocam o status em cada dia
  v_datas := array[p_data_a];
  if p_data_b is not null and p_data_b <> p_data_a then v_datas := v_datas || p_data_b; end if;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
  end loop;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    perform public.escala_gravar_dia(ma.id, v_d, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(mb.id, v_d, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a, p_funcionario_b], v_d, v_d);
  end loop;
  select jsonb_agg(public.escala_dia_json(ma.empresa_id, f, d, true) order by o, d) into v_out
    from unnest(array[p_funcionario_a, p_funcionario_b]) with ordinality as u(f, o)
    cross join unnest(v_datas) d;
  return v_out;
end $$;
comment on function public.escala_trocar(uuid, date, uuid, date, text) is
  '[api] Troca de folga: A↔B num dia (ou em dois dias) ou A entre dois dias; reapura.';

-- ================================================================ RPCs de leitura
create or replace function public.escala_mes(p_ano_mes text, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_ini date; v_fim date; v_cfg public.escala_config; v_motivo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_ano_mes is null or p_ano_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Mês inválido (use AAAA-MM)' using errcode = '22023';
  end if;
  v_ini := (p_ano_mes || '-01')::date;
  v_fim := (v_ini + interval '1 month')::date - 1;
  v_motivo := public.pode_operar(v_empresa) is true;
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;

  return (
    with calc as materialized (select * from public.escala_calcular(v_empresa, v_ini, v_fim)),
    dias as (select g::date as d from generate_series(v_ini, v_fim, interval '1 day') g),
    mem as (
      select m.*, f.nome, f.cargo from public.escala_membros m join public.funcionarios f on f.id = m.funcionario_id
       where m.empresa_id = v_empresa
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'ano_mes', p_ano_mes, 'inicio', v_ini, 'fim', v_fim,
      'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'pode_editar', v_motivo, 'hoje', public.escala_hoje(v_empresa),
      'dias', (select jsonb_agg(jsonb_build_object('data', d, 'dia_semana', extract(isodow from d)::int - 1,
                                                   'semana', case when v_cfg.ancora is not null then public.escala_semana_num(d, v_cfg.ancora) end)
                                order by d) from dias),
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs) order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'membro_id', m.id, 'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                            'chegada_padrao', public.escala_hora(m.chegada_padrao), 'folgas_base', to_jsonb(m.folgas_base),
                            'caminho', m.caminho, 'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                            'trabalha', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'trabalha'),
                            'folgas', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'folga'),
                            'ferias', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'ferias'),
                            'dias', coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'data', dd.d, 'status', coalesce(c.status, 'fora'), 'origem', coalesce(c.origem, 'auto'),
                                       'chegada', public.escala_hora(c.chegada), 'ajustado', coalesce(c.ajustado, false),
                                       'motivo', case when v_motivo then c.motivo end) order by dd.d)
                                from dias dd left join calc c on c.funcionario_id = m.funcionario_id and c.data = dd.d), '[]'))
                          order by m.ordem, m.nome collate "C", m.id)
                     from mem m where m.setor_id = s.id), '[]'),
                 'na_escala', (select jsonb_agg((select count(*) from calc c where c.setor_id = s.id and c.data = dd.d and c.status = 'trabalha')
                                                order by dd.d) from dias dd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala', (select jsonb_agg((select count(*) from calc c where c.data = dd.d and c.status = 'trabalha') order by dd.d)
                      from dias dd))
  );
end $$;
comment on function public.escala_mes(text, uuid) is '[api] Escala do mês (AAAA-MM): setores, membros e dias (leitura vê, sem motivos).';

create or replace function public.escala_semana(p_data date default null, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_cfg public.escala_config; v_data date; v_seg date; v_w int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.escala_hoje(v_empresa));
  v_seg := v_data - (extract(isodow from v_data)::int - 1);
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;
  v_w := case when v_cfg.ancora is not null then public.escala_semana_num(v_seg, v_cfg.ancora) end;

  return (
    with r as materialized (select * from public.escala_membros_rodizio(v_empresa)),
    mem as (
      select r.*, f.nome, f.cargo, m.ordem,
             coalesce(case when v_w is null or r.caminho is null then r.folgas_base
                           else (select a.folgas_base from r a
                                  where a.setor_id = r.setor_id and a.caminho = r.caminho
                                    and a.k = (((r.k + v_w + coalesce(v_cfg.fase, 0) + r.fase_setor) % r.n) + r.n) % r.n) end,
                      r.folgas_base) as folgas_semana
        from r join public.funcionarios f on f.id = r.funcionario_id join public.escala_membros m on m.id = r.id
    ),
    wd as (select generate_series(0, 6) as d)
    select jsonb_build_object(
      'empresa_id', v_empresa, 'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'semana_inicio', v_seg, 'semana', v_w,
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'total', (select count(*) from mem m where m.setor_id = s.id),
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs, 'nomes', cm.nomes)
                                                        order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs,
                                                      jsonb_agg(m.nome order by m.posicao, m.id) as nomes
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((select jsonb_agg(jsonb_build_object(
                                               'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                                               'chegada_padrao', public.escala_hora(m.chegada_padrao), 'caminho', m.caminho,
                                               'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                                               'folgas_base', to_jsonb(m.folgas_base), 'folgas_semana', to_jsonb(m.folgas_semana))
                                             order by m.ordem, m.nome collate "C", m.id)
                                        from mem m where m.setor_id = s.id), '[]'),
                 'na_escala_base', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_base)))
                                                     order by wd.d) from wd),
                 'na_escala_semana', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_semana)))
                                                       order by wd.d) from wd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala_base', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_base))) order by wd.d) from wd),
      'na_escala_semana', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_semana))) order by wd.d) from wd))
  );
end $$;
comment on function public.escala_semana(date, uuid) is '[api] Semana base e semana de p_data pela regra do rodízio (sem ajustes).';-- =====================================================================================================
-- 20261006000900_permissoes.sql  (backend-1) — SEMPRE A ÚLTIMA MIGRAÇÃO.
-- Varre o catálogo de public e concede privilégios pela etiqueta no início do comment (§2.2):
--   tabela  [api:crud] → authenticated: select, insert, update, delete
--           [api:leitura] → authenticated: select
--           [api:nenhum] / sem etiqueta → nada
--   função  [api] / [politica] → execute para authenticated (+ service_role)
--           [servico] / [interno] / sem etiqueta → só service_role (e o dono)
-- anon não recebe nada em public. service_role recebe tudo. Idempotente (revoga antes de conceder).
-- =====================================================================================================

-- Objetos novos criados pelo dono (postgres) em public não ficam abertos por padrão: só esta varredura concede.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

grant usage on schema public to anon, authenticated, service_role;

do $$
declare
  r record;
  v_etiqueta text;
begin
  -- -------------------------------------------------------------- tabelas, views e afins
  for r in
    select c.oid, c.relkind, format('%I.%I', n.nspname, c.relname) as nome,
           obj_description(c.oid, 'pg_class') as comentario
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p', 'v', 'm', 'f')
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on table %s from public, anon, authenticated', r.nome);
    execute format('grant all on table %s to service_role', r.nome);
    v_etiqueta := substring(coalesce(r.comentario, '') from '^\s*(\[[a-z_:]+\])');
    if v_etiqueta = '[api:crud]' then
      execute format('grant select, insert, update, delete on table %s to authenticated', r.nome);
    elsif v_etiqueta = '[api:leitura]' then
      execute format('grant select on table %s to authenticated', r.nome);
    end if;
  end loop;

  -- ------------------------------------------------------------------------ sequências
  for r in
    select format('%I.%I', n.nspname, c.relname) as nome,
           (select obj_description(t.oid, 'pg_class')
              from pg_depend d join pg_class t on t.oid = d.refobjid
             where d.objid = c.oid and d.deptype in ('a', 'i') and d.refclassid = 'pg_class'::regclass
             limit 1) as comentario_dono
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'S'
       and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('revoke all on sequence %s from public, anon, authenticated', r.nome);
    execute format('grant all on sequence %s to service_role', r.nome);
    if substring(coalesce(r.comentario_dono, '') from '^\s*(\[[a-z_:]+\])') = '[api:crud]' then
      execute format('grant usage, select on sequence %s to authenticated', r.nome);
    end if;
  end loop;

  -- ------------------------------------------------------------- funções e procedimentos
  for r in
    select p.oid::regprocedure::text as assinatura, p.prokind,
           obj_description(p.oid, 'pg_proc') as comentario
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p', 'w')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on %s %s from public, anon, authenticated',
                   case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    execute format('grant execute on %s %s to service_role',
                   case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    v_etiqueta := substring(coalesce(r.comentario, '') from '^\s*(\[[a-z_:]+\])');
    if v_etiqueta in ('[api]', '[politica]') then
      execute format('grant execute on %s %s to authenticated',
                     case r.prokind when 'p' then 'procedure' else 'function' end, r.assinatura);
    end if;
  end loop;
end $$;

commit;
select 'parte 17 de 17 instalada' as resultado;
