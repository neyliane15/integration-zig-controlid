-- Meu Dia de Gerente — instalação do banco, PARTE 20 DE 20.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000310_rhid.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
-- ---------------------------------------------------------------- pessoas (GET /person)
-- p_pessoas: os PersonDTO do RHiD como vieram ({id, cpf, pis, name, registration, status, ...}). Snapshot completo:
-- quem não vier é marcado removido_no_equipamento (a ingestão do Control iD faz isso). Pessoa sem CPF é ignorada
-- (Portaria 671: o REP identifica pelo CPF).
create or replace function public.ingestao_rhid_pessoas(p_integracao uuid, p_pessoas jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig       public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  v_itens  jsonb := '[]'::jsonb;
  x        jsonb;
  v_cpf    text;
  v_sem    int := 0;
  v_res    jsonb;
begin
  p_pessoas := public.ingestao_lista(p_pessoas);
  if jsonb_array_length(p_pessoas) > 20000 then
    raise exception 'Lista maior que 20000 pessoas' using errcode = '22023';
  end if;
  for x in select value from jsonb_array_elements(p_pessoas) loop
    v_cpf := case when jsonb_typeof(x) = 'object' then public.rhid_documento(x -> 'cpf') end;
    if v_cpf is null then
      v_sem := v_sem + 1;
      continue;
    end if;
    v_itens := v_itens || jsonb_build_object(
      'id', v_cpf, 'cpf', v_cpf, 'pis', public.rhid_documento(x -> 'pis'),
      'name', coalesce(public.ingestao_texto(x -> 'name'), public.ingestao_texto(x -> 'socialName')),
      'registration', public.ingestao_texto(x -> 'registration'));
  end loop;
  v_res := public.ingestao_controlid_usuarios(ig.id, v_itens);
  return v_res || jsonb_build_object('lidos', jsonb_array_length(p_pessoas), 'sem_cpf', v_sem,
                                     'ignorados', coalesce((v_res ->> 'ignorados')::int, 0) + v_sem);
end $$;
comment on function public.ingestao_rhid_pessoas(uuid, jsonb) is
  '[servico] Pessoas do RHiD (GET /person) → usuários do relógio por CPF + vínculo automático (reaproveita a do Control iD).';

-- ----------------------------------------------------- batidas (AFD 671 de um equipamento)
-- p_equipamento: id do equipamento no RHiD (REP-P: idCompany + 99000000; coletor REP-P: "c<id>" para não colidir NSR).
-- p_marcacoes: saída de lerAfd (n8n/controlid/lib/afd.mjs): [{nsr, instante (com fuso -03:00), cpf | pis}].
-- Marcação já importada por outra fonte (mesmo CPF e instante: AFD enviado pelo site, REP por rede, ou o mesmo registro
-- no AFD do REP-P e no do coletor) conta como duplicada.
create or replace function public.ingestao_rhid_batidas(p_integracao uuid, p_equipamento text, p_marcacoes jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig        public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  v_equip   text := btrim(coalesce(p_equipamento, ''));
  v_itens   jsonb := '[]'::jsonb;
  x         jsonb;
  v_nsr     text;
  v_max     numeric;
  v_doc     text;
  v_inst    timestamptz;
  v_fuso    text;
  v_outra   int := 0;
  v_res     jsonb;
  v_atual   numeric;
begin
  if v_equip !~ '^c?[0-9]{1,12}$' then
    raise exception 'Equipamento inválido' using errcode = '22023';
  end if;
  p_marcacoes := public.ingestao_lista(p_marcacoes);
  if jsonb_array_length(p_marcacoes) > 2000 then
    raise exception 'Lote maior que 2000 itens' using errcode = '22023';
  end if;
  select e.fuso into v_fuso from public.empresas e where e.id = ig.empresa_id;
  for x in select value from jsonb_array_elements(p_marcacoes) loop
    if jsonb_typeof(x) <> 'object' then
      v_itens := v_itens || jsonb_build_array(x);  -- a ingestão conta como inválido
      continue;
    end if;
    v_nsr := regexp_replace(coalesce(public.ingestao_texto(x -> 'nsr'), public.ingestao_texto(x -> 'id_externo'), ''), '[^0-9]', '', 'g');
    v_nsr := case when v_nsr = '' then null else coalesce(nullif(ltrim(v_nsr, '0'), ''), '0') end;
    if v_nsr is not null and (v_max is null or v_nsr::numeric > v_max) then v_max := v_nsr::numeric; end if;
    -- já veio por outra fonte (mesmo CPF/PIS e instante, origem REP, outra integração da empresa)?
    v_doc := coalesce(public.rhid_documento(x -> 'cpf'), public.rhid_documento(x -> 'pis'));
    begin
      v_inst := case when x ? 'instante' then public.ingestao_ler_instante(x ->> 'instante', v_fuso, 'com_fuso')
                     else public.ingestao_ler_instante(x ->> 'instante_local', v_fuso, 'sem_fuso') end;
    exception when others then
      v_inst := null;
    end;
    if v_doc is not null and v_inst is not null and exists (
         select 1 from public.ponto_batidas b
          where b.empresa_id = ig.empresa_id and b.origem = 'controlid_rep'
            and b.pessoa_externa = v_doc and b.instante = v_inst
            and not (b.integracao_id = ig.id and b.id_externo = v_equip || '|' || v_nsr)) then
      v_outra := v_outra + 1;
      continue;
    end if;
    v_itens := v_itens || ((x - 'id_externo' - 'nsr')
                           || jsonb_build_object('id_externo', case when v_nsr is null then null else v_equip || '|' || v_nsr end));
  end loop;

  v_res := public.ingestao_controlid_batidas(ig.id, v_itens);

  -- cursor por equipamento: nunca regride
  if v_max is not null then
    select (i.cursor -> 'nsr_por_equipamento' ->> v_equip)::numeric into v_atual from public.integracoes i where i.id = ig.id;
    if v_atual is null or v_max > v_atual then
      update public.integracoes i
         set cursor = i.cursor || jsonb_build_object('nsr_por_equipamento',
                        coalesce(case when jsonb_typeof(i.cursor -> 'nsr_por_equipamento') = 'object'
                                      then i.cursor -> 'nsr_por_equipamento' end, '{}'::jsonb)
                        || jsonb_build_object(v_equip, v_max))
       where i.id = ig.id;
    end if;
  end if;

  return v_res || jsonb_build_object(
    'lidos', jsonb_array_length(p_marcacoes),
    'duplicados', coalesce((v_res ->> 'duplicados')::int, 0) + v_outra,
    'ja_importadas_por_outra_fonte', v_outra,
    'equipamento', v_equip,
    'ultimo_nsr', (select i.cursor -> 'nsr_por_equipamento' -> v_equip from public.integracoes i where i.id = ig.id),
    'cursor', (select i.cursor from public.integracoes i where i.id = ig.id));
end $$;
comment on function public.ingestao_rhid_batidas(uuid, text, jsonb) is
  '[servico] Marcações do AFD 671 de um equipamento do RHiD (id_externo equipamento|NSR) + cursor por equipamento.';

-- ------------------------------------------------- trocar um relógio controlid_rep por RHiD
-- O tipo da integração é imutável: cria a integração 'rhid', copia os usuários do relógio (CPF) com os vínculos
-- (automáticos e manuais) e desativa a antiga. As batidas já importadas ficam na antiga e continuam valendo no ponto.
create or replace function public.integracao_trocar_para_rhid(p_integracao uuid, p_nome text default null) returns uuid
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  v    public.integracoes;
  v_id uuid;
begin
  select * into v from public.integracoes where id = p_integracao;
  if not found then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
  if not public.pode_administrar(v.empresa_id) then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if v.tipo <> 'controlid_rep' then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:trocar_rhid:' || v.id::text, 0));
  -- já trocada antes? devolve a mesma
  select i.id into v_id from public.integracoes i
   where i.empresa_id = v.empresa_id and i.tipo = 'rhid' and i.parametros ->> 'substitui' = v.id::text
   order by i.criado_em limit 1;
  if v_id is null then
    insert into public.integracoes (empresa_id, tipo, nome, ativa, parametros, intervalo_minutos)
    values (v.empresa_id, 'rhid', coalesce(nullif(btrim(p_nome), ''), 'Relógio de ponto (RHiD)'), true,
            jsonb_build_object('substitui', v.id::text), greatest(v.intervalo_minutos, 60))
    returning id into v_id;
  end if;
  insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, registration, nome, cpf, pis,
                                         funcionario_id, vinculo, removido_no_equipamento, visto_em)
  select c.empresa_id, v_id, c.user_id_externo, c.registration, c.nome, c.cpf, c.pis,
         c.funcionario_id, c.vinculo, c.removido_no_equipamento, c.visto_em
    from public.controlid_usuarios c
   where c.integracao_id = v.id and c.user_id_externo ~ '^[0-9]{11}$'
  on conflict (integracao_id, user_id_externo) do nothing;
  update public.integracoes set ativa = false where id = v.id and ativa;
  return v_id;
end $$;
comment on function public.integracao_trocar_para_rhid(uuid, text) is
  '[api] Troca um relógio Control iD REP (rede ou arquivo) por uma integração RHiD, mantendo os vínculos (A M).';-- =====================================================================================================
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
select 'parte 20 de 20 instalada' as resultado;
