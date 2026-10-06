-- =====================================================================================================
-- 20261006000130_tarefas.sql  (backend-1)
-- tarefas_rotinas, tarefas_rotina_itens, tarefas, tarefa_itens, RPCs de tarefas, RLS. Idempotente.
-- =====================================================================================================

create table if not exists public.tarefas_rotinas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  recorrencia                 text not null default 'diaria' check (recorrencia in ('diaria', 'semanal', 'mensal')),
  dias_semana                 smallint[] not null default '{}',
  dia_mes                     smallint check (dia_mes between 1 and 31),
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  ativa                       boolean not null default true,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  constraint tarefas_rotinas_semanal check (recorrencia <> 'semanal' or cardinality(dias_semana) > 0),
  constraint tarefas_rotinas_mensal check (recorrencia <> 'mensal' or dia_mes is not null),
  constraint tarefas_rotinas_dias check (dias_semana <@ array[0,1,2,3,4,5,6]::smallint[])
);
create index if not exists tarefas_rotinas_empresa_idx on public.tarefas_rotinas (empresa_id);
create index if not exists tarefas_rotinas_resp_func_idx on public.tarefas_rotinas (responsavel_funcionario_id);
create index if not exists tarefas_rotinas_resp_perfil_idx on public.tarefas_rotinas (responsavel_perfil_id);
create index if not exists tarefas_rotinas_criado_por_idx on public.tarefas_rotinas (criado_por);
comment on table public.tarefas_rotinas is '[api:crud] Rotinas recorrentes que geram tarefas.';

create table if not exists public.tarefas_rotina_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,
  rotina_id   uuid not null references public.tarefas_rotinas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> '')
);
create index if not exists tarefas_rotina_itens_empresa_idx on public.tarefas_rotina_itens (empresa_id);
create index if not exists tarefas_rotina_itens_rotina_idx on public.tarefas_rotina_itens (rotina_id, ordem);
comment on table public.tarefas_rotina_itens is '[api:crud] Checklist das rotinas.';

create table if not exists public.tarefas (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  rotina_id                   uuid references public.tarefas_rotinas (id) on delete set null,
  data                        date not null,
  titulo                      text not null check (btrim(titulo) <> ''),
  descricao                   text,
  horario_limite              time,
  prioridade                  text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  status                      text not null default 'pendente'
                              check (status in ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  responsavel_funcionario_id  uuid references public.funcionarios (id) on delete set null,
  responsavel_perfil_id       uuid references public.perfis (id) on delete set null,
  concluida_por               uuid references public.perfis (id) on delete set null,
  concluida_em                timestamptz,
  criado_por                  uuid references public.perfis (id) on delete set null default auth.uid(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  unique (rotina_id, data)
);
create index if not exists tarefas_empresa_data_idx on public.tarefas (empresa_id, data);
create index if not exists tarefas_resp_func_idx on public.tarefas (responsavel_funcionario_id);
create index if not exists tarefas_resp_perfil_idx on public.tarefas (responsavel_perfil_id);
create index if not exists tarefas_concluida_por_idx on public.tarefas (concluida_por);
create index if not exists tarefas_criado_por_idx on public.tarefas (criado_por);
comment on table public.tarefas is '[api:crud] Tarefas do dia de trabalho (avulsas ou geradas por rotina).';

create table if not exists public.tarefa_itens (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete cascade,
  tarefa_id   uuid not null references public.tarefas (id) on delete cascade,
  ordem       int not null default 0,
  texto       text not null check (btrim(texto) <> ''),
  feito       boolean not null default false,
  feito_por   uuid references public.perfis (id) on delete set null,
  feito_em    timestamptz
);
create index if not exists tarefa_itens_empresa_idx on public.tarefa_itens (empresa_id);
create index if not exists tarefa_itens_tarefa_idx on public.tarefa_itens (tarefa_id, ordem);
create index if not exists tarefa_itens_feito_por_idx on public.tarefa_itens (feito_por);
comment on table public.tarefa_itens is '[api:crud] Checklist das tarefas.';

-- ====================================================================================== gatilhos
-- Responsáveis da mesma empresa.
create or replace function public.tarefa_validar_responsaveis(p_empresa uuid, p_funcionario uuid, p_perfil uuid) returns void
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_funcionario is not null
     and not exists (select 1 from public.funcionarios where id = p_funcionario and empresa_id = p_empresa) then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  if p_perfil is not null
     and not exists (select 1 from public.perfis where id = p_perfil and empresa_id = p_empresa) then
    raise exception 'Usuário de outra empresa' using errcode = '22023';
  end if;
end $$;
comment on function public.tarefa_validar_responsaveis(uuid, uuid, uuid) is '[interno] Responsáveis da mesma empresa.';

create or replace function public.tarefas_rotinas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
  else
    new.criado_por := public.meu_perfil_id();
  end if;
  new.titulo := btrim(new.titulo);
  select coalesce(array_agg(distinct d order by d), '{}') into new.dias_semana from unnest(new.dias_semana) d;
  perform public.tarefa_validar_responsaveis(new.empresa_id, new.responsavel_funcionario_id, new.responsavel_perfil_id);
  return new;
end $$;
comment on function public.tarefas_rotinas_antes_gravar() is '[interno] Gatilho de tarefas_rotinas.';

drop trigger if exists tarefas_rotinas_antes_gravar on public.tarefas_rotinas;
create trigger tarefas_rotinas_antes_gravar before insert or update on public.tarefas_rotinas
  for each row execute function public.tarefas_rotinas_antes_gravar();
drop trigger if exists tarefas_rotinas_tocar on public.tarefas_rotinas;
create trigger tarefas_rotinas_tocar before update on public.tarefas_rotinas
  for each row execute function public.tocar_atualizado_em();

create or replace function public.tarefas_rotina_itens_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.tarefas_rotinas where id = new.rotina_id;
  if new.empresa_id is null then
    raise exception 'Rotina não encontrada' using errcode = 'P0002';
  end if;
  new.texto := btrim(new.texto);
  return new;
end $$;
comment on function public.tarefas_rotina_itens_antes_gravar() is '[interno] Gatilho: empresa da rotina.';

drop trigger if exists tarefas_rotina_itens_antes_gravar on public.tarefas_rotina_itens;
create trigger tarefas_rotina_itens_antes_gravar before insert or update on public.tarefas_rotina_itens
  for each row execute function public.tarefas_rotina_itens_antes_gravar();

create or replace function public.tarefas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
    new.criado_por := old.criado_por;
  else
    new.criado_por := public.meu_perfil_id();
  end if;
  new.titulo := btrim(new.titulo);
  if new.rotina_id is not null
     and (tg_op = 'INSERT' or new.rotina_id is distinct from old.rotina_id)
     and not exists (select 1 from public.tarefas_rotinas where id = new.rotina_id and empresa_id = new.empresa_id) then
    raise exception 'Rotina não encontrada' using errcode = 'P0002';
  end if;
  perform public.tarefa_validar_responsaveis(new.empresa_id, new.responsavel_funcionario_id, new.responsavel_perfil_id);
  if new.status = 'concluida' and (tg_op = 'INSERT' or old.status is distinct from 'concluida') then
    new.concluida_por := public.meu_perfil_id();
    new.concluida_em := public.agora();
  elsif new.status <> 'concluida' then
    new.concluida_por := null;
    new.concluida_em := null;
  elsif tg_op = 'UPDATE' then
    new.concluida_por := old.concluida_por;
    new.concluida_em := old.concluida_em;
  end if;
  return new;
end $$;
comment on function public.tarefas_antes_gravar() is '[interno] Gatilho de tarefas: conclusão, responsáveis, empresa.';

drop trigger if exists tarefas_antes_gravar on public.tarefas;
create trigger tarefas_antes_gravar before insert or update on public.tarefas
  for each row execute function public.tarefas_antes_gravar();
drop trigger if exists tarefas_tocar on public.tarefas;
create trigger tarefas_tocar before update on public.tarefas
  for each row execute function public.tocar_atualizado_em();

create or replace function public.tarefa_itens_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.tarefas where id = new.tarefa_id;
  if new.empresa_id is null then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  new.texto := btrim(new.texto);
  if new.feito and (tg_op = 'INSERT' or not old.feito) then
    new.feito_por := public.meu_perfil_id();
    new.feito_em := public.agora();
  elsif not new.feito then
    new.feito_por := null;
    new.feito_em := null;
  elsif tg_op = 'UPDATE' then
    new.feito_por := old.feito_por;
    new.feito_em := old.feito_em;
  end if;
  return new;
end $$;
comment on function public.tarefa_itens_antes_gravar() is '[interno] Gatilho de tarefa_itens: empresa e feito_por/em.';

drop trigger if exists tarefa_itens_antes_gravar on public.tarefa_itens;
create trigger tarefa_itens_antes_gravar before insert or update on public.tarefa_itens
  for each row execute function public.tarefa_itens_antes_gravar();

-- =========================================================================================== RLS
do $$
declare
  t text;
begin
  foreach t in array array['tarefas_rotinas', 'tarefas_rotina_itens', 'tarefas', 'tarefa_itens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_ler on public.%1$s', t);
    execute format('create policy %1$s_ler on public.%1$s for select to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()))', t);
    execute format('drop policy if exists %1$s_inserir on public.%1$s', t);
    execute format('create policy %1$s_inserir on public.%1$s for insert to authenticated
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_alterar on public.%1$s', t);
    execute format('create policy %1$s_alterar on public.%1$s for update to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))
      with check ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
    execute format('drop policy if exists %1$s_excluir on public.%1$s', t);
    execute format('create policy %1$s_excluir on public.%1$s for delete to authenticated
      using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()))', t);
  end loop;
end $$;

-- ========================================================================================= RPCs
-- Rotina cai no dia D?
create or replace function public.rotina_cai_no_dia(p_recorrencia text, p_dias_semana smallint[], p_dia_mes smallint, p_data date)
returns boolean
language sql immutable
set search_path = public, extensions, pg_temp
as $$
  select case p_recorrencia
    when 'diaria' then true
    when 'semanal' then extract(dow from p_data)::smallint = any (p_dias_semana)
    when 'mensal' then extract(day from p_data)::int
                       = least(p_dia_mes::int,
                               extract(day from (date_trunc('month', p_data) + interval '1 month - 1 day'))::int)
    else false
  end
$$;
comment on function public.rotina_cai_no_dia(text, smallint[], smallint, date) is
  '[api] A rotina (recorrência, dias da semana, dia do mês) cai na data? Mês curto → último dia.';

create or replace function public.tarefas_gerar_empresa(p_empresa uuid, p_data date) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_criadas int := 0;
  r record;
  v_tarefa uuid;
begin
  for r in
    select * from public.tarefas_rotinas t
     where t.empresa_id = p_empresa and t.ativa
       and public.rotina_cai_no_dia(t.recorrencia, t.dias_semana, t.dia_mes, p_data)
     order by t.horario_limite nulls last, t.titulo
  loop
    insert into public.tarefas (empresa_id, rotina_id, data, titulo, descricao, horario_limite, prioridade,
                                responsavel_funcionario_id, responsavel_perfil_id)
    values (p_empresa, r.id, p_data, r.titulo, r.descricao, r.horario_limite, r.prioridade,
            r.responsavel_funcionario_id, r.responsavel_perfil_id)
    on conflict (rotina_id, data) do nothing
    returning id into v_tarefa;
    if v_tarefa is not null then
      insert into public.tarefa_itens (empresa_id, tarefa_id, ordem, texto)
      select p_empresa, v_tarefa, i.ordem, i.texto from public.tarefas_rotina_itens i
       where i.rotina_id = r.id order by i.ordem, i.id;
      v_criadas := v_criadas + 1;
    end if;
    v_tarefa := null;
  end loop;
  return v_criadas;
end $$;
comment on function public.tarefas_gerar_empresa(uuid, date) is '[interno] Materializa as rotinas da empresa numa data.';

create or replace function public.tarefas_gerar_do_dia(p_data date default null, p_empresa uuid default null) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid := public.resolver_empresa(p_empresa, 'ler');
  v_hoje date := public.dia_de_trabalho(public.agora(), v_empresa);
  v_data date := coalesce(p_data, v_hoje);
begin
  if abs(v_data - v_hoje) > 366 then
    raise exception 'Período inválido' using errcode = '22023';
  end if;
  return public.tarefas_gerar_empresa(v_empresa, v_data);
end $$;
comment on function public.tarefas_gerar_do_dia(date, uuid) is
  '[api] Gera as tarefas das rotinas para a data (padrão: dia de trabalho atual). Idempotente (L G A M).';

create or replace function public.ingestao_tarefas_gerar(p_data date default null) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_total int := 0;
  e record;
begin
  for e in select id from public.empresas where ativa order by id loop
    v_total := v_total + public.tarefas_gerar_empresa(e.id, coalesce(p_data, public.dia_de_trabalho(public.agora(), e.id)));
  end loop;
  return v_total;
end $$;
comment on function public.ingestao_tarefas_gerar(date) is '[servico] Gera as tarefas do dia para todas as empresas ativas.';

-- Pode mexer na tarefa? G A M da empresa, ou L responsável por ela.
create or replace function public.tarefa_pode_mexer(p_tarefa public.tarefas) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select public.pode_operar(p_tarefa.empresa_id)
      or (public.pode_ler(p_tarefa.empresa_id)
          and (p_tarefa.responsavel_perfil_id = auth.uid()
               or (p_tarefa.responsavel_funcionario_id is not null
                   and p_tarefa.responsavel_funcionario_id = public.meu_funcionario())))
$$;
comment on function public.tarefa_pode_mexer(public.tarefas) is '[interno] G A M ou responsável (leitura).';

create or replace function public.tarefa_mudar_status(p_tarefa uuid, p_status text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.tarefas;
begin
  select * into v from public.tarefas where id = p_tarefa;
  if not found or not public.pode_ler(v.empresa_id) then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  if not public.tarefa_pode_mexer(v) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('pendente', 'em_andamento', 'concluida', 'cancelada') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  update public.tarefas set status = p_status where id = p_tarefa;
end $$;
comment on function public.tarefa_mudar_status(uuid, text) is '[api] Muda o status da tarefa (G A M; L se responsável).';

create or replace function public.tarefa_marcar_item(p_item uuid, p_feito boolean) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.tarefas;
begin
  select t.* into v from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id where i.id = p_item;
  if not found or not public.pode_ler(v.empresa_id) then
    raise exception 'Tarefa não encontrada' using errcode = 'P0002';
  end if;
  if not public.tarefa_pode_mexer(v) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  update public.tarefa_itens set feito = coalesce(p_feito, false) where id = p_item;
end $$;
comment on function public.tarefa_marcar_item(uuid, boolean) is '[api] Marca/desmarca item do checklist (G A M; L se responsável).';
