-- =====================================================================================================
-- 20261006000210_zig.sql — backend-2
-- Zig: lojas, itens vendidos (saída de produtos), faturamento, bandeiras, compradores e RPCs de vendas.
-- Contrato: §6 (DDL), §8 (regras), §10.5 (RPCs). Idempotente.
-- =====================================================================================================

-- ===================================================================== zig_lojas
create table if not exists public.zig_lojas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  integracao_id    uuid not null references public.integracoes (id) on delete cascade,
  loja_id_externo  text not null,
  nome             text not null,
  sincronizar      boolean not null default true,
  visto_em         timestamptz not null default now(),
  criado_em        timestamptz not null default now(),
  unique (empresa_id, loja_id_externo)
);
create index if not exists zig_lojas_integracao_idx on public.zig_lojas (integracao_id);
comment on table public.zig_lojas is '[api:crud] Lojas da Zig. authenticated (administrador) só altera `sincronizar`.';

-- ============================================================== zig_vendas_itens
create table if not exists public.zig_vendas_itens (
  id                 bigint generated always as identity primary key,
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo    text not null,
  data_operacao      date not null,
  transaction_id     text not null,
  transaction_date   timestamptz,
  event_id           text,
  event_date         date,
  invoice_id         text,
  product_id         text,
  product_sku        text,
  product_name       text,
  product_category   text,
  tipo               text not null check (tipo in ('Normal', 'Couvert', 'ZigCard', 'Entrance', 'Tip', 'Outro')),
  tipo_original      text,
  unit_value         bigint not null default 0,
  quantidade         numeric(14,3) not null default 0,
  fractional_amount  numeric(14,3),
  fraction_unit      text,
  discount_value     bigint not null default 0,
  valor_total        bigint not null,
  employee_name      text,
  additions          jsonb not null default '[]'::jsonb,
  importado_em       timestamptz not null default now()
);
create index if not exists zig_vendas_itens_dia_idx on public.zig_vendas_itens (empresa_id, data_operacao, loja_id_externo);
create index if not exists zig_vendas_itens_garcom_idx on public.zig_vendas_itens (empresa_id, lower(btrim(employee_name)));
comment on table public.zig_vendas_itens is '[api:leitura] Itens de /erp/saida-produtos (centavos). Tip = serviço.';

-- =============================================================== zig_faturamento
create table if not exists public.zig_faturamento (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  event_date       date,
  payment_id       int not null,
  payment_name     text not null,
  valor            bigint not null,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_faturamento_dia_idx on public.zig_faturamento (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_faturamento is '[api:leitura] Faturamento por forma de pagamento (/erp/faturamento), centavos.';

create table if not exists public.zig_faturamento_bandeiras (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  event_id         text,
  payment_id       int not null,
  payment_name     text,
  card_brand       text,
  valor            bigint not null,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_bandeiras_dia_idx on public.zig_faturamento_bandeiras (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_faturamento_bandeiras is '[api:leitura] Faturamento por bandeira (/erp/faturamento/detalhesMaquinaIntegrada).';

create table if not exists public.zig_compradores (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  loja_id_externo  text not null,
  data_operacao    date not null,
  transaction_id   text not null,
  products_value   bigint not null default 0,
  tip_value        bigint not null default 0,
  importado_em     timestamptz not null default now()
);
create index if not exists zig_compradores_dia_idx on public.zig_compradores (empresa_id, data_operacao, loja_id_externo);
comment on table public.zig_compradores is '[api:leitura] /erp/compradores sem dados pessoais (LGPD): só valores por transação.';

-- ========================================================================= RLS
alter table public.zig_lojas enable row level security;
alter table public.zig_vendas_itens enable row level security;
alter table public.zig_faturamento enable row level security;
alter table public.zig_faturamento_bandeiras enable row level security;
alter table public.zig_compradores enable row level security;

drop policy if exists zig_lojas_ler on public.zig_lojas;
create policy zig_lojas_ler on public.zig_lojas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_lojas_alterar on public.zig_lojas;
create policy zig_lojas_alterar on public.zig_lojas for update to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()))
  with check ((select public.eh_master()) or empresa_id = (select public.empresa_administracao()));
drop policy if exists zig_vendas_itens_ler on public.zig_vendas_itens;
create policy zig_vendas_itens_ler on public.zig_vendas_itens for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_faturamento_ler on public.zig_faturamento;
create policy zig_faturamento_ler on public.zig_faturamento for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_bandeiras_ler on public.zig_faturamento_bandeiras;
create policy zig_bandeiras_ler on public.zig_faturamento_bandeiras for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists zig_compradores_ler on public.zig_compradores;
create policy zig_compradores_ler on public.zig_compradores for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
create or replace function public.zig_lojas_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_tipo text;
begin
  if tg_op = 'INSERT' then
    select i.empresa_id, i.tipo into v_empresa, v_tipo from public.integracoes i where i.id = new.integracao_id;
    if v_empresa is null then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
    if v_tipo <> 'zig' then raise exception 'Tipo de integração incompatível' using errcode = '22023'; end if;
    new.empresa_id := v_empresa;
    return new;
  end if;
  -- UPDATE vindo do front (papel authenticated): só `sincronizar` muda.
  if current_user = 'authenticated' then
    new.id := old.id; new.empresa_id := old.empresa_id; new.integracao_id := old.integracao_id;
    new.loja_id_externo := old.loja_id_externo; new.nome := old.nome; new.visto_em := old.visto_em;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.zig_lojas_antes() is '[interno] Gatilho de zig_lojas: empresa da integração; authenticated só muda sincronizar.';

drop trigger if exists a_antes on public.zig_lojas;
create trigger a_antes before insert or update on public.zig_lojas
  for each row execute function public.zig_lojas_antes();

-- ================================================================ RPCs de vendas
create or replace function public.vendas_resumo(p_inicio date, p_fim date, p_loja text default null,
                                                p_empresa uuid default null)
returns table (faturamento bigint, vendas bigint, servico bigint, descontos bigint, transacoes bigint,
               servico_compradores bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select
    coalesce((select sum(z.valor) from public.zig_faturamento z
               where z.empresa_id = v_empresa and z.data_operacao between p_inicio and p_fim
                 and (p_loja is null or z.loja_id_externo = p_loja)), 0)::bigint,
    coalesce(sum(i.valor_total) filter (where i.tipo <> 'Tip'), 0)::bigint,
    coalesce(sum(i.valor_total) filter (where i.tipo = 'Tip'), 0)::bigint,
    coalesce(sum(i.discount_value), 0)::bigint,
    count(distinct i.transaction_id)::bigint,
    coalesce((select sum(c.tip_value) from public.zig_compradores c
               where c.empresa_id = v_empresa and c.data_operacao between p_inicio and p_fim
                 and (p_loja is null or c.loja_id_externo = p_loja)), 0)::bigint
    from public.zig_vendas_itens i
   where i.empresa_id = v_empresa and i.data_operacao between p_inicio and p_fim
     and (p_loja is null or i.loja_id_externo = p_loja);
end $$;
comment on function public.vendas_resumo(date, date, text, uuid) is '[api] Resumo de vendas do período (centavos).';

create or replace function public.vendas_faturamento_por_dia(p_inicio date, p_fim date, p_loja text default null,
                                                             p_empresa uuid default null)
returns table (data date, valor bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select g::date,
         coalesce((select sum(z.valor) from public.zig_faturamento z
                    where z.empresa_id = v_empresa and z.data_operacao = g::date
                      and (p_loja is null or z.loja_id_externo = p_loja)), 0)::bigint
    from generate_series(p_inicio, p_fim, interval '1 day') g
   order by 1;
end $$;
comment on function public.vendas_faturamento_por_dia(date, date, text, uuid) is '[api] Faturamento por dia (dias sem dado = 0).';

create or replace function public.vendas_faturamento_por_forma(p_inicio date, p_fim date, p_loja text default null,
                                                               p_empresa uuid default null)
returns table (payment_id int, payment_name text, valor bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  select z.payment_id, mode() within group (order by z.payment_name), sum(z.valor)::bigint
    from public.zig_faturamento z
   where z.empresa_id = v_empresa and z.data_operacao between p_inicio and p_fim
     and (p_loja is null or z.loja_id_externo = p_loja)
   group by z.payment_id
   order by 3 desc, 1;
end $$;
comment on function public.vendas_faturamento_por_forma(date, date, text, uuid) is '[api] Faturamento por forma de pagamento.';

create or replace function public.vendas_por_garcom(p_inicio date, p_fim date, p_loja text default null,
                                                    p_empresa uuid default null)
returns table (employee_name text, funcionario_id uuid, funcionario_nome text, quantidade numeric, valor_vendas bigint,
               valor_servico bigint, transacoes bigint)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);
  return query
  with g as (
    select nullif(lower(btrim(i.employee_name)), '') as chave,
           mode() within group (order by nullif(btrim(i.employee_name), '')) as nome,
           coalesce(sum(i.quantidade) filter (where i.tipo <> 'Tip'), 0) as qtd,
           coalesce(sum(i.valor_total) filter (where i.tipo <> 'Tip'), 0)::bigint as vendas,
           coalesce(sum(i.valor_total) filter (where i.tipo = 'Tip'), 0)::bigint as servico,
           count(distinct i.transaction_id)::bigint as trans
      from public.zig_vendas_itens i
     where i.empresa_id = v_empresa and i.data_operacao between p_inicio and p_fim
       and (p_loja is null or i.loja_id_externo = p_loja)
     group by 1
  )
  select g.nome, f.id, f.nome, g.qtd, g.vendas, g.servico, g.trans
    from g
    left join public.funcionarios f
      on g.chave is not null and f.empresa_id = v_empresa and lower(btrim(f.zig_employee_name)) = g.chave
   order by g.vendas desc, g.nome nulls last;
end $$;
comment on function public.vendas_por_garcom(date, date, text, uuid) is '[api] Vendas e serviço por garçom (employeeName da Zig).';
