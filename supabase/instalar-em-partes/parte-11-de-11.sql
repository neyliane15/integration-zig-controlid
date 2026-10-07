-- Meu Dia de Gerente — instalação do banco, PARTE 11 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000230_ingestao.sql, 20261006000240_painel.sql, 20261006000900_permissoes.sql. Não edite à mão.

begin;
create or replace function public.ingestao_fechamento_exportar(p_fechamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_fech jsonb; v_itens jsonb;
begin
  select to_jsonb(fc) || jsonb_build_object('empresa_nome', e.nome) into v_fech
    from public.comissao_fechamentos fc join public.empresas e on e.id = fc.empresa_id
   where fc.id = p_fechamento;
  if v_fech is null then raise exception 'Fechamento não encontrado' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(it) order by it.funcionario_nome, it.funcionario_id), '[]'::jsonb) into v_itens
    from public.comissao_itens it where it.fechamento_id = p_fechamento;
  return jsonb_build_object('fechamento', v_fech, 'itens', v_itens);
end $$;
comment on function public.ingestao_fechamento_exportar(uuid) is '[servico] Fechamento + itens (por nome) para o CSV do N8N.';-- =====================================================================================================
-- 20261006000240_painel.sql — backend-2
-- painel_do_dia: resumo do dia de trabalho (faturamento, serviço, ponto, tarefas, sincronização). Contrato §10.7.
-- =====================================================================================================

create or replace function public.painel_do_dia(p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa   uuid;
  v_hoje      date;
  v_ontem     date;
  v_mes       date;
  v_fat       jsonb;
  v_serv      jsonb;
  v_ponto     jsonb;
  v_tarefas   jsonb;
  v_sync      jsonb;
  v_fuso      text;
  v_virada    time;
  v_presentes int := 0;
  v_escalados int := 0;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  select e.fuso, e.virada_dia into v_fuso, v_virada from public.empresas e where e.id = v_empresa;
  v_hoje := public.dia_de_trabalho(public.agora(), v_empresa);
  v_ontem := v_hoje - 1;
  v_mes := date_trunc('month', v_hoje)::date;

  -- faturamento e serviço
  select jsonb_build_object(
           'hoje', coalesce(sum(z.valor) filter (where z.data_operacao = v_hoje), 0),
           'ontem', coalesce(sum(z.valor) filter (where z.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(z.valor) filter (where z.data_operacao >= v_mes), 0),
           'tem_zig', exists (select 1 from public.integracoes i where i.empresa_id = v_empresa and i.tipo = 'zig' and i.ativa))
    into v_fat
    from public.zig_faturamento z
   where z.empresa_id = v_empresa and z.data_operacao between least(v_mes, v_ontem) and v_hoje;

  select jsonb_build_object(
           'ontem', coalesce(sum(i.valor_total) filter (where i.data_operacao = v_ontem), 0),
           'mes', coalesce(sum(i.valor_total) filter (where i.data_operacao >= v_mes), 0))
    into v_serv
    from public.zig_vendas_itens i
   where i.empresa_id = v_empresa and i.tipo = 'Tip' and i.data_operacao between least(v_mes, v_ontem) and v_hoje;

  -- ponto (ao vivo para hoje)
  select count(*) filter (where c.batidas_validas % 2 = 1),
         count(*) filter (where c.batidas_esperadas > 0)
    into v_presentes, v_escalados
    from public.funcionarios f
    cross join lateral public.ponto_calcular_dia(f.id, v_hoje) c
   where f.empresa_id = v_empresa and f.ativo and not c.fora_do_vinculo;

  select jsonb_build_object(
    'alarmes_abertos', (select count(*) from public.ponto_alarmes a where a.empresa_id = v_empresa and a.status = 'aberto'),
    'alarmes', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'funcionario_id', x.funcionario_id, 'funcionario_nome', x.nome,
                                           'data', x.data, 'tipo', x.tipo, 'batida_esperada', x.batida_esperada,
                                           'detalhe', x.detalhe) order by x.data desc, x.criado_em desc, x.id)
         from (select a.id, a.funcionario_id, f.nome, a.data, a.tipo, a.batida_esperada, a.detalhe, a.criado_em
                 from public.ponto_alarmes a
                 join public.funcionarios f on f.id = a.funcionario_id
                where a.empresa_id = v_empresa and a.status = 'aberto'
                order by a.data desc, a.criado_em desc, a.id
                limit 5) x), '[]'::jsonb),
    'presentes_agora', v_presentes,
    'escalados_hoje', v_escalados,
    'batidas_sem_funcionario', (select count(*) from public.ponto_batidas b
                                 where b.empresa_id = v_empresa and b.funcionario_id is null))
    into v_ponto;

  -- tarefas do dia (atrasadas: abertas de hoje ou de dias anteriores cujo prazo já passou)
  select jsonb_build_object(
           'total', count(*) filter (where t.data = v_hoje and t.status <> 'cancelada'),
           'concluidas', count(*) filter (where t.data = v_hoje and t.status = 'concluida'),
           'pendentes', count(*) filter (where t.data = v_hoje and t.status in ('pendente', 'em_andamento')),
           'atrasadas', count(*) filter (where t.status in ('pendente', 'em_andamento')
                                          and (t.data < v_hoje
                                               or (t.data = v_hoje and t.horario_limite is not null
                                                   and public.ponto_instante_escala(t.data, t.horario_limite, v_fuso, v_virada)
                                                       < public.agora()))))
    into v_tarefas
    from public.tarefas t
   where t.empresa_id = v_empresa and t.data between v_hoje - 31 and v_hoje;

  -- sincronização (só status, nunca segredos)
  select coalesce(jsonb_agg(jsonb_build_object(
           'integracao_id', i.id, 'tipo', i.tipo, 'nome', i.nome, 'ativa', i.ativa,
           'ultimo_sucesso_em', i.ultimo_sucesso_em, 'ultimo_status', i.ultimo_status, 'ultimo_erro', i.ultimo_erro,
           'executando', exists (select 1 from public.sync_execucoes s where s.integracao_id = i.id and s.status = 'executando')
                      or exists (select 1 from public.sync_solicitacoes s
                                  where s.integracao_id = i.id and s.status in ('pendente', 'em_andamento')))
           order by i.tipo, i.nome, i.id), '[]'::jsonb)
    into v_sync
    from public.integracoes i
   where i.empresa_id = v_empresa;

  return jsonb_build_object(
    'empresa_id', v_empresa, 'dia_trabalho', v_hoje, 'ontem', v_ontem,
    'faturamento', v_fat, 'servico', v_serv, 'ponto', v_ponto, 'tarefas', v_tarefas, 'sincronizacao', v_sync);
end $$;
comment on function public.painel_do_dia(uuid) is '[api] Painel do dia de trabalho (§10.7).';-- =====================================================================================================
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
select 'parte 11 de 11 instalada' as resultado;
