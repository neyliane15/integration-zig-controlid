-- Meu Dia de Gerente — instalação do banco, PARTE 19 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000290_comissao_presenca.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
create or replace function public.extras_importar(p_itens jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_linha jsonb; v_n int := 0; v_criados int := 0; v_atualizados int := 0; v_dias int := 0;
  v_erros jsonb := '[]'; v_pend uuid[] := '{}'; v_nome text; v_doc text; v_pontos numeric; v_valor numeric; v_extra uuid;
  v_qtd int; v_dia jsonb; v_data date; v_dpontos numeric; v_dvalor numeric; x public.extras; v_dias_linha int;
  v_criou boolean; v_diaria public.diarias; v_tem_pontos boolean; v_pend_dia boolean; v_msg text;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'Lista de extras inválida' using errcode = '22023';
  end if;
  if jsonb_array_length(p_itens) > 1000 then
    raise exception 'Máximo de 1000 linhas por importação' using errcode = '22023';
  end if;

  for v_linha in select e from jsonb_array_elements(p_itens) e loop
    v_n := v_n + 1;
    begin
      if jsonb_typeof(v_linha) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
      v_nome := nullif(btrim(coalesce(v_linha ->> 'nome', '')), '');
      if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
      v_doc := nullif(btrim(coalesce(v_linha ->> 'documento', '')), '');
      v_tem_pontos := v_linha ? 'pontos' and v_linha -> 'pontos' <> 'null'::jsonb;
      v_pontos := public.extras_imp_num(v_linha -> 'pontos', 'Pontos inválidos');
      if v_pontos is not null and (v_pontos < 0 or v_pontos > 9999.99 or v_pontos <> round(v_pontos, 2)) then
        raise exception 'Pontos inválidos' using errcode = '22023';
      end if;
      v_tem_pontos := v_pontos is not null;
      v_valor := public.extras_imp_num(v_linha -> 'valor_diaria_centavos', 'Valor inválido');
      if v_valor is not null and (v_valor < 0 or v_valor > 100000000 or v_valor <> round(v_valor)) then
        raise exception 'Valor inválido' using errcode = '22023';
      end if;
      if v_linha ? 'dias_trabalhados' and v_linha -> 'dias_trabalhados' <> 'null'::jsonb
         and jsonb_typeof(v_linha -> 'dias_trabalhados') <> 'array' then
        raise exception 'Linha inválida' using errcode = '22023';
      end if;

      -- casamento: documento normalizado; senão nome normalizado (entre os sem documento, quando há documento)
      v_extra := null;
      if v_doc is not null then
        select x2.id into v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_documento(x2.documento) = public.extras_normalizar_documento(v_doc)
         order by x2.criado_em, x2.id limit 1;
      end if;
      if v_extra is null then
        select count(*), min(x2.id::text)::uuid into v_qtd, v_extra from public.extras x2
         where x2.empresa_id = v_empresa
           and public.extras_normalizar_nome(x2.nome) = public.extras_normalizar_nome(v_nome)
           and (v_doc is null or x2.documento is null);
        if v_qtd > 1 then
          raise exception 'Mais de um extra com este nome: informe o documento' using errcode = '22023';
        end if;
      end if;

      v_criou := v_extra is null;
      if v_criou then
        insert into public.extras (empresa_id, nome, funcao, telefone, documento, pontos_padrao, pontos_pendente,
                                   valor_diaria_centavos, criado_por)
        values (v_empresa, v_nome, nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''),
                nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), v_doc, coalesce(v_pontos, 0), not v_tem_pontos,
                v_valor::bigint, public.meu_perfil_id())
        returning id into v_extra;
      else
        update public.extras e
           set funcao = coalesce(nullif(btrim(coalesce(v_linha ->> 'funcao', '')), ''), e.funcao),
               telefone = coalesce(nullif(btrim(coalesce(v_linha ->> 'telefone', '')), ''), e.telefone),
               documento = coalesce(v_doc, e.documento),
               valor_diaria_centavos = coalesce(v_valor::bigint, e.valor_diaria_centavos),
               ativo = true
         where e.id = v_extra;
        if v_tem_pontos then perform public.extra_definir_pontuacao(v_extra, v_pontos); end if;
      end if;
      select * into x from public.extras where id = v_extra;

      v_dias_linha := 0;
      for v_dia in select d from jsonb_array_elements(coalesce(nullif(v_linha -> 'dias_trabalhados', 'null'::jsonb), '[]')) d loop
        if jsonb_typeof(v_dia) <> 'object' then raise exception 'Linha inválida' using errcode = '22023'; end if;
        v_data := public.extras_imp_data(v_dia -> 'data');
        if v_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
        v_dpontos := public.extras_imp_num(v_dia -> 'pontos', 'Pontos inválidos');
        v_dvalor := public.extras_imp_num(v_dia -> 'valor_centavos', 'Valor inválido');
        if v_dvalor is not null and v_dvalor <> round(v_dvalor) then raise exception 'Valor inválido' using errcode = '22023'; end if;
        v_pend_dia := v_dpontos is null and x.pontos_pendente;
        v_dpontos := case when v_pend_dia then 0 else coalesce(v_dpontos, x.pontos_padrao) end;
        v_dvalor := coalesce(v_dvalor, x.valor_diaria_centavos);
        perform public.diaria_validar_valores(v_empresa, v_data, v_dpontos, v_dvalor::bigint, true);
        perform public.diaria_checar_trava(v_empresa, v_data);
        select * into v_diaria from public.diarias where extra_id = x.id and data = v_data;
        if v_diaria.id is null then
          insert into public.diarias (empresa_id, tipo, extra_id, pessoa_nome, data, funcao, pontos, pontos_pendente,
                                      valor_centavos, criado_por, criado_por_nome)
          values (v_empresa, 'extra', x.id, x.nome, v_data, x.funcao, v_dpontos, v_pend_dia, v_dvalor::bigint,
                  public.meu_perfil_id(), public.ponto_nome_autor());
        else
          update public.diarias set pontos = v_dpontos, pontos_pendente = v_pend_dia, valor_centavos = v_dvalor::bigint
           where id = v_diaria.id;
        end if;
        v_dias_linha := v_dias_linha + 1;
      end loop;

      v_dias := v_dias + v_dias_linha;
      if v_criou then v_criados := v_criados + 1; else v_atualizados := v_atualizados + 1; end if;
      select * into x from public.extras where id = v_extra;
      if x.pontos_pendente and not (x.id = any (v_pend)) then v_pend := v_pend || x.id; end if;
      if not x.pontos_pendente then v_pend := array_remove(v_pend, x.id); end if;
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v_erros := v_erros || jsonb_build_object('linha', v_n, 'mensagem', v_msg);
    end;
  end loop;

  return jsonb_build_object('lidos', v_n, 'criados', v_criados, 'atualizados', v_atualizados, 'dias_lancados', v_dias,
                            'pendentes_pontuacao', coalesce(array_length(v_pend, 1), 0), 'erros', v_erros);
end $$;
comment on function public.extras_importar(jsonb, uuid) is
  '[api] Importa extras em lote (upsert por documento ou nome) com dias trabalhados; sem pontos = pontuação pendente (G A M).';-- =====================================================================================================
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
select 'parte 19 de 19 instalada' as resultado;
