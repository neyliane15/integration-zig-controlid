-- 90_auditoria.sql (backend-1): auditoria do catálogo inteiro de public (vale para as migrações de todos).
-- Falha listando os objetos problemáticos.
begin;

create temp table _achados (regra text, objeto text);

-- 1. Tabela de public sem etiqueta [api:crud] / [api:leitura] / [api:nenhum]
insert into _achados
select 'tabela sem etiqueta', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and coalesce(substring(obj_description(c.oid, 'pg_class') from '^\s*(\[[a-z_:]+\])'), '')
       not in ('[api:crud]', '[api:leitura]', '[api:nenhum]');

-- 2. Tabela sem RLS
insert into _achados
select 'tabela sem RLS', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;

-- 3. Função security definer sem search_path fixo
insert into _achados
select 'security definer sem search_path', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%');

-- 4. FK sem índice cujas primeiras colunas sejam as da FK
insert into _achados
select 'FK sem índice', format('%s(%s)', c.conrelid::regclass, c.conname)
  from pg_constraint c join pg_namespace n on n.oid = c.connamespace
 where n.nspname = 'public' and c.contype = 'f'
   and not exists (
     select 1 from pg_index i
      where i.indrelid = c.conrelid
        and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] @> c.conkey
        and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] <@ c.conkey);

-- 5. Tabela de dados de empresa sem índice que comece por empresa_id
insert into _achados
select 'empresa_id sem índice inicial', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'empresa_id' and not a.attisdropped
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and not exists (select 1 from pg_index i where i.indrelid = c.oid and i.indkey[0] = a.attnum);

-- 6. anon não tem nenhum privilégio em tabela, sequência ou função de public
insert into _achados
select 'anon com privilégio em tabela', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'S')
   and (has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')
        or (c.relkind = 'S' and has_sequence_privilege('anon', c.oid, 'usage, select, update')));
insert into _achados
select 'anon executa função', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');

-- 7. Privilégios de authenticated conferem com a etiqueta
insert into _achados
select 'authenticated com acesso a tabela [api:nenhum]/sem etiqueta', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and coalesce(substring(obj_description(c.oid, 'pg_class') from '^\s*(\[[a-z_:]+\])'), '') not in ('[api:crud]', '[api:leitura]')
   and has_table_privilege('authenticated', c.oid, 'select, insert, update, delete, truncate');
insert into _achados
select 'authenticated escreve em tabela [api:leitura]', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and substring(obj_description(c.oid, 'pg_class') from '^\s*(\[[a-z_:]+\])') = '[api:leitura]'
   and has_table_privilege('authenticated', c.oid, 'insert, update, delete, truncate');
insert into _achados
select 'authenticated executa função [servico]/[interno]/sem etiqueta', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and coalesce(substring(obj_description(p.oid, 'pg_proc') from '^\s*(\[[a-z_:]+\])'), '') not in ('[api]', '[politica]')
   and has_function_privilege('authenticated', p.oid, 'execute');
insert into _achados
select 'função [api]/[politica] sem execute para authenticated', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and substring(obj_description(p.oid, 'pg_proc') from '^\s*(\[[a-z_:]+\])') in ('[api]', '[politica]')
   and not has_function_privilege('authenticated', p.oid, 'execute');

-- 8. service_role alcança tudo
insert into _achados
select 'service_role sem acesso a tabela', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and not has_table_privilege('service_role', c.oid, 'select, insert, update, delete');
insert into _achados
select 'service_role não executa função', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and not has_function_privilege('service_role', p.oid, 'execute');

-- 9. Tabelas sem acesso para authenticated precisam de RLS sem política para authenticated/public
insert into _achados
select 'tabela [api:nenhum] com política', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and substring(obj_description(c.oid, 'pg_class') from '^\s*(\[[a-z_:]+\])') = '[api:nenhum]'
   and exists (select 1 from pg_policies pp where pp.schemaname = 'public' and pp.tablename = c.relname);

-- 10. Etiquetas de função válidas (erro de digitação vira "sem etiqueta" e some da API)
insert into _achados
select 'etiqueta de função desconhecida', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and obj_description(p.oid, 'pg_proc') ~ '^\s*\['
   and substring(obj_description(p.oid, 'pg_proc') from '^\s*(\[[a-z_:]+\])') not in ('[api]', '[politica]', '[servico]', '[interno]');

do $$
declare
  v text;
begin
  select string_agg(format('  - %s: %s', regra, objeto), E'\n' order by regra, objeto) into v from _achados;
  if v is not null then
    raise exception E'FALHOU: auditoria do catálogo\n%', v;
  end if;
  raise notice 'ok: auditoria do catálogo (etiquetas, RLS, search_path, índices de FK, privilégios)';
end $$;

-- Sanidade: uma tabela de cada tipo
select teste.ok('integracoes_segredos sem acesso para authenticated',
  not has_table_privilege('authenticated', 'public.integracoes_segredos', 'select'));
select teste.ok('funcionarios [api:crud] para authenticated',
  has_table_privilege('authenticated', 'public.funcionarios', 'select, insert, update, delete'));
select teste.ok('perfis só leitura para authenticated',
  has_table_privilege('authenticated', 'public.perfis', 'select')
  and not has_table_privilege('authenticated', 'public.perfis', 'update'));
rollback;
