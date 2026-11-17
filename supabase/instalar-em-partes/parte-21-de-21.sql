-- Meu Dia de Gerente — instalação do banco, PARTE 21 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000330_ocorrencias_ponto.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
-- Faltas e atrasos de uma empresa no período (opcional: um funcionário). Sem checagem (uso interno).
create or replace function public.ocorrencias_ponto_empresa(p_empresa uuid, p_inicio date, p_fim date,
                                                            p_funcionario uuid default null)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with e as (select em.fuso from public.empresas em where em.id = p_empresa),
  faltas as (
    select x.data, x.funcionario_id, f.nome as funcionario_nome,
           case x.tipo when 'justificada' then 'falta_justificada' else 'falta_injustificada' end as tipo,
           null::int as minutos, null::text as chegada, null::text as previsto, x.motivo, 'registrada'::text as origem
      from public.funcionario_faltas x
      join public.funcionarios f on f.id = x.funcionario_id
     where x.empresa_id = p_empresa and x.data between p_inicio and p_fim
       and (p_funcionario is null or x.funcionario_id = p_funcionario)
  ),
  ausencias as (
    select d.data, d.funcionario_id, f.nome, 'falta'::text, null::int, null::text,
           public.minutos_em_horas(d.previsto_minutos), null::text, 'ponto'::text
      from public.ponto_dias d
      join public.funcionarios f on f.id = d.funcionario_id
     where d.empresa_id = p_empresa and d.data between p_inicio and p_fim and d.encerrado and d.situacao = 'ausente'
       and (p_funcionario is null or d.funcionario_id = p_funcionario)
       and not exists (select 1 from public.funcionario_faltas x where x.funcionario_id = d.funcionario_id and x.data = d.data)
  ),
  atrasos as (
    select d.data, d.funcionario_id, f.nome, 'atraso'::text, d.atraso_minutos,
           to_char(d.primeira_batida at time zone e.fuso, 'HH24:MI'),
           to_char((d.primeira_batida - make_interval(mins => d.atraso_minutos)) at time zone e.fuso, 'HH24:MI'),
           null::text, 'ponto'::text
      from public.ponto_dias d
      join public.funcionarios f on f.id = d.funcionario_id
      cross join e
     where d.empresa_id = p_empresa and d.data between p_inicio and p_fim and d.atraso_minutos > 0
       and d.primeira_batida is not null
       and (p_funcionario is null or d.funcionario_id = p_funcionario)
  ),
  tudo as (select * from faltas union all select * from ausencias union all select * from atrasos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', t.data, 'funcionario_id', t.funcionario_id, 'funcionario_nome', t.funcionario_nome, 'tipo', t.tipo,
           'minutos', t.minutos, 'chegada', t.chegada, 'previsto', t.previsto, 'motivo', t.motivo, 'origem', t.origem)
           order by t.data desc, t.funcionario_nome, t.tipo), '[]'::jsonb)
    from tudo t
$$;
comment on function public.ocorrencias_ponto_empresa(uuid, date, date, uuid) is
  '[interno] Faltas (registradas e dias ausentes do ponto) e atrasos de uma empresa no período, sem checagem.';


-- API: faltas e atrasos (G A M). Com p_funcionario: a empresa é a do funcionário.
create or replace function public.ocorrencias_ponto(p_inicio date, p_fim date, p_funcionario uuid default null,
                                                    p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 366 then
    raise exception 'Período inválido (máximo de 366 dias)' using errcode = '22023';
  end if;
  if p_funcionario is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if not public.pode_operar(v_empresa) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  return public.ocorrencias_ponto_empresa(v_empresa, p_inicio, p_fim, p_funcionario);
end $$;
comment on function public.ocorrencias_ponto(date, date, uuid, uuid) is
  '[api] Faltas (registradas e dias ausentes do ponto) e atrasos no período (G A M).';

-- Resumo (painel e aba): advertências/suspensões + faltas e atrasos (adendo O.4).
create or replace function public.ocorrencias_resumo_empresa(p_empresa uuid, p_dias int)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with h as (select public.dia_de_trabalho(public.agora(), p_empresa) as hoje),
       o as (select x.*, f.nome as funcionario_nome
               from public.funcionario_ocorrencias x
               join public.funcionarios f on f.id = x.funcionario_id, h
              where x.empresa_id = p_empresa and x.data between h.hoje - p_dias + 1 and h.hoje),
       pt as (select value as v
                from h, jsonb_array_elements(public.ocorrencias_ponto_empresa(p_empresa, h.hoje - p_dias + 1, h.hoje)))
  select jsonb_build_object(
    'desde', h.hoje - p_dias + 1, 'ate', h.hoje,
    'advertencias', (select count(*) from o where o.tipo = 'advertencia'),
    'suspensoes', (select count(*) from o where o.tipo = 'suspensao'),
    'suspensos_hoje', (select count(distinct s.funcionario_id) from public.funcionario_ocorrencias s
                        where s.empresa_id = p_empresa and s.tipo = 'suspensao'
                          and h.hoje between s.suspensao_inicio and s.suspensao_fim),
    'faltas', (select count(*) from pt where pt.v ->> 'tipo' like 'falta%'),
    'atrasos', (select count(*) from pt where pt.v ->> 'tipo' = 'atraso'),
    'minutos_atraso', (select coalesce(sum((pt.v ->> 'minutos')::int), 0) from pt where pt.v ->> 'tipo' = 'atraso'),
    'recentes', coalesce((select jsonb_agg(jsonb_build_object(
                    'id', r.id, 'funcionario_id', r.funcionario_id, 'funcionario_nome', r.funcionario_nome, 'tipo', r.tipo,
                    'data', r.data, 'motivo', r.motivo, 'dias_suspensao', r.dias_suspensao,
                    'suspensao_inicio', r.suspensao_inicio, 'suspensao_fim', r.suspensao_fim)
                  order by r.data desc, r.criado_em desc, r.id)
                  from (select * from o order by o.data desc, o.criado_em desc, o.id limit 10) r), '[]'::jsonb),
    'ponto_recentes', coalesce((select jsonb_agg(q.v) from (select pt.v from pt limit 10) q), '[]'::jsonb))
  from h
$$;
comment on function public.ocorrencias_resumo_empresa(uuid, int) is
  '[interno] Resumo de ocorrências (adendo O.4) com faltas e atrasos do ponto, sem checagem.';

-- alarmes abertos de dias fora do prazo da empresa (padrão 2 dias): resolvidos automaticamente
update public.ponto_alarmes a
   set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
  from public.empresas em
 where em.id = a.empresa_id and a.status = 'aberto'
   and a.data < public.dia_de_trabalho(public.agora(), em.id) - em.ponto_alarme_prazo_dias;-- =====================================================================================================
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
select 'parte 21 de 21 instalada' as resultado;
