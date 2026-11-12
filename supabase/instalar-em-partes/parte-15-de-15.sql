-- Meu Dia de Gerente — instalação do banco, PARTE 15 DE 15.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000270_reservas.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
comment on function public.reservas_listar(date, date, text[], uuid) is
  '[api] Reservas do período (L G A M; telefone/e-mail só para G A M).';

create or replace function public.reservas_importar(p_linhas jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_ids text[] := '{}'; v_novo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_linhas) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_linhas) with ordinality as e(valor, ord) loop
    begin
      select * into c from public.reserva_ler_item(it.valor, 'horario');
      if c.id_externo is not null then
        if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
        v_ids := v_ids || c.id_externo;
      end if;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    if c.id_externo is null then
      insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                                   telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa, c.observacao,
              c.telefone, c.email, public.meu_perfil_id(), public.agora());
      v_ins := v_ins + 1;
    else
      insert into public.reservas as r (empresa_id, origem, id_externo, data, horario, nome_cliente, pessoas, status, area, mesa,
                                        observacao, telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
              c.observacao, c.telefone, c.email, public.meu_perfil_id(), public.agora())
      on conflict (empresa_id, origem, id_externo) do update
        set data = excluded.data, horario = excluded.horario, nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas,
            status = excluded.status, area = excluded.area, mesa = excluded.mesa, observacao = excluded.observacao,
            telefone = excluded.telefone, email = excluded.email, importado_em = excluded.importado_em
      returning (xmax = 0) into v_novo;
      if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('lidos', jsonb_array_length(p_linhas), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'erros', v_erros);
end $$;
comment on function public.reservas_importar(jsonb, uuid) is '[api] Importa reservas de um CSV lido pelo front (G A M).';

-- ================================================================ ingestão (N8N)
create or replace function public.ingestao_reservas(p_integracao uuid, p_inicio date, p_fim date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_rem int := 0; v_ids text[] := '{}'; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['tagme']);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_itens) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:reservas:' || ig.empresa_id::text, 0));

  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_itens) with ordinality as e(valor, ord) loop
    begin
      if it.valor is null or jsonb_typeof(it.valor) <> 'object' then raise exception 'item inválido'; end if;
      if nullif(btrim(it.valor ->> 'id_externo'), '') is null then raise exception 'id_externo ausente'; end if;
      select * into c from public.reserva_ler_item(it.valor, 'hora');
      if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
      v_ids := v_ids || c.id_externo;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    insert into public.reservas as r (empresa_id, integracao_id, origem, id_externo, data, horario, nome_cliente, pessoas, status,
                                      area, mesa, observacao, telefone, email, importado_em)
    values (ig.empresa_id, ig.id, 'tagme', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
            c.observacao, c.telefone, c.email, public.agora())
    on conflict (empresa_id, origem, id_externo) do update
      set integracao_id = excluded.integracao_id, data = excluded.data, horario = excluded.horario,
          nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas, status = excluded.status, area = excluded.area,
          mesa = excluded.mesa, observacao = excluded.observacao, telefone = excluded.telefone, email = excluded.email,
          importado_em = excluded.importado_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;

  delete from public.reservas r
   where r.empresa_id = ig.empresa_id and r.origem = 'tagme' and r.data between p_inicio and p_fim
     and not (r.id_externo = any (v_ids));
  get diagnostics v_rem = row_count;

  update public.integracoes
     set cursor = jsonb_build_object('ultimo_inicio', p_inicio, 'ultimo_fim', p_fim)
   where id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_itens), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'removidos', v_rem, 'erros', v_erros);
end $$;
comment on function public.ingestao_reservas(uuid, date, date, jsonb) is
  '[servico] Reservas da Tagme (N8N): upsert por id_externo e remove as da janela que não vieram (adendo R.3).';

-- Bloco "reservas" do painel (sem checagem; o painel já resolveu a empresa).
create or replace function public.reservas_painel(p_empresa uuid, p_hoje date, p_telefone boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with e as (select fuso from public.empresas where id = p_empresa),
       r as (select * from public.reservas where empresa_id = p_empresa and data = p_hoje)
  select jsonb_build_object(
    'total', (select count(*) from r where status <> 'cancelada'),
    'pessoas', (select coalesce(sum(pessoas), 0) from r where status <> 'cancelada'),
    'canceladas', (select count(*) from r where status = 'cancelada'),
    'nao_compareceu', (select count(*) from r where status = 'nao_compareceu'),
    'sentadas', (select count(*) from r where status = 'sentada'),
    'tem_tagme', exists (select 1 from public.integracoes i where i.empresa_id = p_empresa and i.tipo = 'tagme' and i.ativa),
    'proximas', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'horario', x.horario, 'nome_cliente', x.nome_cliente, 'pessoas', x.pessoas,
                                           'status', x.status, 'area', x.area, 'mesa', x.mesa, 'observacao', x.observacao,
                                           'origem', x.origem, 'telefone', case when p_telefone then x.telefone end)
                        order by x.horario nulls last, x.nome_cliente, x.id)
         from (select r.* from r, e
                where r.status in ('confirmada', 'pendente')
                  and (r.horario is null or ((r.data + r.horario) at time zone e.fuso) >= public.agora() - interval '30 minutes')
                order by r.horario nulls last, r.nome_cliente, r.id
                limit 10) x), '[]'::jsonb))
$$;
comment on function public.reservas_painel(uuid, date, boolean) is '[interno] Bloco reservas do painel_do_dia (adendo R.4).';-- =====================================================================================================
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
select 'parte 15 de 15 instalada' as resultado;
