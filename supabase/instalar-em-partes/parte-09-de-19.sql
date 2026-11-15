-- Meu Dia de Gerente — instalação do banco, PARTE 09 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000200_ponto.sql, 20261006000210_zig.sql, 20261006000220_comissoes.sql. Não edite à mão.

begin;
create or replace function public.banco_horas_extrato(p_funcionario uuid, p_inicio date, p_fim date)
returns table (data date, tipo text, descricao text, minutos int, saldo_acumulado bigint, referencia_id uuid)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid;
  v_saldo   bigint;
  r         record;
  v_rotulos constant jsonb := '{"completo":"Completo","incompleto":"Incompleto","ausente":"Ausente","folga":"Folga",
     "sem_escala":"Sem escala","abonado":"Abonado","suspenso":"Suspenso","em_andamento":"Em andamento",
     "falta_justificada":"Falta justificada","falta_injustificada":"Falta injustificada"}'::jsonb;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 366);

  v_saldo := public.banco_horas_calcular_saldo(p_funcionario, p_inicio - 1);
  data := p_inicio - 1; tipo := 'saldo_anterior'; descricao := 'Saldo anterior';
  minutos := v_saldo::int; saldo_acumulado := v_saldo; referencia_id := null;
  return next;

  for r in
    select x.* from (
      select d.data, 1 as ordem, 'dia'::text as tipo,
             (v_rotulos ->> d.situacao)
               || case when d.abono_tipo is not null then ' (' || d.abono_tipo || ')' else '' end
               || ' — trabalhado ' || public.ponto_fmt_minutos(d.trabalhado_minutos)
               || case when d.previsto_minutos > 0 then ' de ' || public.ponto_fmt_minutos(d.previsto_minutos) else '' end
               as descricao,
             d.saldo_minutos as minutos, null::uuid as referencia_id, null::timestamptz as criado_em
        from public.ponto_dias d
       where d.funcionario_id = p_funcionario and d.encerrado and d.data between p_inicio and p_fim
         and (d.saldo_minutos <> 0 or d.situacao <> 'folga')
      union all
      select l.data, case when l.tipo = 'saldo_inicial' then 0 else 2 end, l.tipo, l.motivo, l.minutos, l.id, l.criado_em
        from public.banco_horas_lancamentos l
       where l.funcionario_id = p_funcionario and l.data between p_inicio and p_fim
    ) x
    order by x.data, x.ordem, x.criado_em, x.referencia_id
  loop
    if r.tipo = 'saldo_inicial' then v_saldo := r.minutos; else v_saldo := v_saldo + r.minutos; end if;
    data := r.data; tipo := r.tipo; descricao := r.descricao; minutos := r.minutos;
    saldo_acumulado := v_saldo; referencia_id := r.referencia_id;
    return next;
  end loop;
end $$;
comment on function public.banco_horas_extrato(uuid, date, date) is '[api] Extrato do banco de horas (máx. 366 dias).';

create or replace function public.banco_horas_lancar(p_funcionario uuid, p_data date, p_tipo text, p_minutos integer,
                                                     p_motivo text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('saldo_inicial', 'ajuste', 'compensacao', 'pagamento') then
    raise exception 'Tipo de lançamento inválido' using errcode = '22023';
  end if;
  if p_tipo = 'saldo_inicial' and not public.pode_administrar(v_empresa) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if p_minutos is null then raise exception 'Informe os minutos' using errcode = '22023'; end if;
  -- (revisão 2) limite de sanidade: ±100.000 min (≈ 1.666 h); 2.147.483.647 min era aceito e distorcia o saldo
  if abs(p_minutos::bigint) > 100000 then
    raise exception 'Minutos fora do limite (máximo 100.000)' using errcode = '22023';
  end if;
  if p_tipo = 'saldo_inicial'
     and exists (select 1 from public.banco_horas_lancamentos
                  where funcionario_id = p_funcionario and data = p_data and tipo = 'saldo_inicial') then
    raise exception 'Já existe saldo inicial nesta data' using errcode = '23505';
  end if;

  insert into public.banco_horas_lancamentos (empresa_id, funcionario_id, data, tipo, minutos, motivo, criado_por, criado_por_nome)
  values (v_empresa, p_funcionario, p_data, p_tipo, p_minutos, btrim(p_motivo), auth.uid(), public.ponto_nome_autor())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.banco_horas_lancar(uuid, date, text, integer, text) is '[api] Lança ajuste/compensação/pagamento (saldo inicial só administrador).';

create or replace function public.banco_horas_excluir_lancamento(p_lancamento uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select l.empresa_id into v_empresa from public.banco_horas_lancamentos l where l.id = p_lancamento;
  if v_empresa is null then raise exception 'Lançamento não encontrado' using errcode = 'P0002'; end if;
  if public.pode_administrar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  delete from public.banco_horas_lancamentos where id = p_lancamento;
end $$;
comment on function public.banco_horas_excluir_lancamento(uuid) is '[api] Exclui lançamento do banco de horas (administrador).';-- =====================================================================================================
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
  if coalesce(nullif(current_setting('role', true), ''), 'none') = 'authenticated' or auth.uid() is not null then
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
comment on function public.vendas_por_garcom(date, date, text, uuid) is '[api] Vendas e serviço por garçom (employeeName da Zig).';-- =====================================================================================================
-- 20261006000220_comissoes.sql — backend-2
-- Comissão: serviço (Tips da Zig) − retenção = base; rateio por pontos com maior resto; rascunho → fechado (imutável).
-- Contrato: §6 (DDL), §9 (regras), §10.6 (RPCs); adendo extras v2 §E.3 (rateio diário, extras). Idempotente.
-- (v3) comissao_calcular, comissao_fechar e comissao_detalhe foram para …0290_comissao_presenca.sql.
-- =====================================================================================================

create table if not exists public.comissao_fechamentos (
  id                          uuid primary key default gen_random_uuid(),
  empresa_id                  uuid not null references public.empresas (id) on delete cascade,
  titulo                      text not null,
  data_inicio                 date not null,
  data_fim                    date not null,
  loja_id_externo             text,
  status                      text not null default 'rascunho' check (status in ('rascunho', 'fechado')),
  servico_zig_centavos        bigint not null default 0,
  servico_ajuste_centavos     bigint not null default 0,
  servico_bruto_centavos      bigint not null default 0,
  percentual_retencao         numeric(5,2) not null check (percentual_retencao between 0 and 100),
  retencao_centavos           bigint not null default 0,
  base_distribuivel_centavos  bigint not null default 0,
  proporcional_dias           boolean not null default false,
  dias_periodo                int not null default 0,
  soma_pontos_efetivos        numeric(18,6) not null default 0,
  valor_ponto_centavos        numeric(18,6),
  observacoes                 text,
  criado_por                  uuid references public.perfis (id) on delete set null,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  calculado_em                timestamptz,
  fechado_por                 uuid references public.perfis (id) on delete set null,
  fechado_em                  timestamptz,
  constraint comissao_periodo check (data_fim >= data_inicio and data_fim - data_inicio <= 92)
);
create index if not exists comissao_fechamentos_empresa_idx on public.comissao_fechamentos (empresa_id, data_inicio desc);
create index if not exists comissao_fechamentos_criado_por_idx on public.comissao_fechamentos (criado_por);
create index if not exists comissao_fechamentos_fechado_por_idx on public.comissao_fechamentos (fechado_por);
comment on table public.comissao_fechamentos is '[api:leitura] Fechamentos de comissão (rascunho → fechado, imutável).';

create table if not exists public.comissao_itens (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas (id) on delete cascade,
  fechamento_id     uuid not null references public.comissao_fechamentos (id) on delete cascade,
  funcionario_id    uuid references public.funcionarios (id) on delete set null,
  funcionario_nome  text not null,
  cargo             text,
  incluido          boolean not null default true,
  pontos            numeric(8,2) not null check (pontos >= 0),
  dias_trabalhados  int not null default 0,
  pontos_efetivos   numeric(18,6) not null default 0,
  valor_centavos    bigint not null default 0,
  criado_em         timestamptz not null default now(),
  unique (fechamento_id, funcionario_id)
);
create index if not exists comissao_itens_empresa_idx on public.comissao_itens (empresa_id);
create index if not exists comissao_itens_funcionario_idx on public.comissao_itens (funcionario_id);
comment on table public.comissao_itens is '[api:leitura] Itens (participantes) de um fechamento de comissão.';

-- ================================================================ adendo extras v2 (E.3): rateio diário
-- Fechamentos existentes ficam 'periodo' (coluna criada com esse default); novos nascem 'diario'.
alter table public.comissao_fechamentos add column if not exists modo_rateio text not null default 'periodo';
alter table public.comissao_fechamentos alter column modo_rateio set default 'diario';
alter table public.comissao_fechamentos drop constraint if exists comissao_fechamentos_modo_rateio_check;
alter table public.comissao_fechamentos add constraint comissao_fechamentos_modo_rateio_check
  check (modo_rateio in ('diario', 'periodo'));
alter table public.comissao_fechamentos add column if not exists dias_sem_presenca int not null default 0;
alter table public.comissao_fechamentos add column if not exists dias_sem_participantes int not null default 0;

-- Participante = funcionário OU extra (freela). Nome/cargo do participante: snapshot em funcionario_nome/cargo.
-- FK de extra_id → extras e o check de participante ficam em …0260_extras.sql (a tabela extras nasce lá).
alter table public.comissao_itens add column if not exists tipo text not null default 'funcionario';
alter table public.comissao_itens drop constraint if exists comissao_itens_tipo_check;
alter table public.comissao_itens add constraint comissao_itens_tipo_check check (tipo in ('funcionario', 'extra'));
alter table public.comissao_itens add column if not exists extra_id uuid;
alter table public.comissao_itens add column if not exists dias_presentes int not null default 0;
alter table public.comissao_itens add column if not exists pontos_manual boolean not null default false;
create unique index if not exists comissao_itens_extra_uk on public.comissao_itens (fechamento_id, extra_id);
create index if not exists comissao_itens_extra_idx on public.comissao_itens (extra_id);

-- v1 (removido): pontos extras de comissão. DROPs idempotentes para quem já rodou a v1.
drop table if exists public.comissao_pontos_extras cascade;
alter table public.comissao_itens drop column if exists pontos_extras;

-- Detalhe do rateio diário (só no modo 'diario'; recalcular o rascunho apaga e regrava).
create table if not exists public.comissao_rateio_dias (
  fechamento_id           uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id              uuid not null references public.empresas (id) on delete cascade,
  data                    date not null,
  servico_zig_centavos    bigint not null default 0,
  ajuste_centavos         bigint not null default 0,
  servico_bruto_centavos  bigint not null default 0,
  retencao_centavos       bigint not null default 0,
  base_centavos           bigint not null default 0,
  soma_pontos             numeric(18,2) not null default 0,
  participantes           int not null default 0,
  sem_presenca            boolean not null default false,
  sem_participantes       boolean not null default false,
  primary key (fechamento_id, data)
);
create index if not exists comissao_rateio_dias_empresa_idx on public.comissao_rateio_dias (empresa_id, data);
comment on table public.comissao_rateio_dias is '[api:leitura] Rateio diário da comissão: serviço, ajuste, retenção e base de cada dia.';

create table if not exists public.comissao_rateio_itens_dia (
  item_id         uuid not null references public.comissao_itens (id) on delete cascade,
  fechamento_id   uuid not null references public.comissao_fechamentos (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  data            date not null,
  pontos          numeric(8,2) not null,
  valor_centavos  bigint not null default 0,
  fallback        boolean not null default false,
  primary key (item_id, data)
);
create index if not exists comissao_rateio_itens_dia_fechamento_idx on public.comissao_rateio_itens_dia (fechamento_id, data);
create index if not exists comissao_rateio_itens_dia_empresa_idx on public.comissao_rateio_itens_dia (empresa_id, data);
comment on table public.comissao_rateio_itens_dia is '[api:leitura] Rateio diário da comissão: pontos e valor de cada participante em cada dia.';

alter table public.comissao_fechamentos enable row level security;
alter table public.comissao_itens enable row level security;
drop policy if exists comissao_fechamentos_ler on public.comissao_fechamentos;
create policy comissao_fechamentos_ler on public.comissao_fechamentos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists comissao_itens_ler on public.comissao_itens;
create policy comissao_itens_ler on public.comissao_itens for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
alter table public.comissao_rateio_dias enable row level security;
alter table public.comissao_rateio_itens_dia enable row level security;
drop policy if exists comissao_rateio_dias_ler on public.comissao_rateio_dias;
create policy comissao_rateio_dias_ler on public.comissao_rateio_dias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists comissao_rateio_itens_dia_ler on public.comissao_rateio_itens_dia;
create policy comissao_rateio_itens_dia_ler on public.comissao_rateio_itens_dia for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
-- Em cascata (pg_trigger_depth() > 1) só passa: exclusão quando a empresa/fechamento já não existe,
-- ou UPDATE que apenas anula FKs (funcionário/perfil excluído → on delete set null).
create or replace function public.comissao_so_anula_fks(p_old jsonb, p_new jsonb, p_fks text[])
returns boolean language sql immutable set search_path = public, extensions, pg_temp as $$
  select not exists (
    select 1 from jsonb_each(p_new) n
     where n.key <> 'atualizado_em'
       and n.value is distinct from p_old -> n.key
       and not (n.key = any (p_fks) and n.value = 'null'::jsonb))
$$;
comment on function public.comissao_so_anula_fks(jsonb, jsonb, text[]) is '[interno] UPDATE só anula FKs?';

commit;
select 'parte 09 de 19 instalada' as resultado;
