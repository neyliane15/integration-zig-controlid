-- =====================================================================================================
-- 20261006000320_rhid_horarios.sql — horário previsto de cada dia vindo do RHiD (adendo RHiD §R.9)
-- O RHiD já sabe o horário contratual de cada pessoa, as folgas da escala e os feriados. O N8N ("MDG · RHiD · Importar")
-- lê a apuração do RHiD (GET /apuracao_ponto, uma pessoa por chamada) dos funcionários ligados e grava aqui, por dia:
--   previsto_minutos (0 em folga/feriado), horarios (entradas/saídas previstas), folga, feriado e o saldo do RHiD.
-- A apuração do ponto (ponto_calcular_dia, …0200) usa este previsto no lugar da jornada/escala, então o saldo do dia é
-- trabalhado − previsto, como no RHiD (folga/feriado trabalhado = tudo positivo).
-- Idempotente.
-- =====================================================================================================

create table if not exists public.ponto_previsto_externo (
  funcionario_id         uuid not null references public.funcionarios (id) on delete cascade,
  data                   date not null,
  empresa_id             uuid not null references public.empresas (id) on delete cascade,
  integracao_id          uuid references public.integracoes (id) on delete cascade,
  previsto_minutos       int not null check (previsto_minutos between 0 and 1440),
  horarios               time[] not null default '{}',
  folga                  boolean not null default false,
  feriado                text,
  saldo_externo_minutos  int,
  atualizado_em          timestamptz not null default now(),
  primary key (funcionario_id, data)
);
create index if not exists ponto_previsto_externo_empresa_idx on public.ponto_previsto_externo (empresa_id, data);
create index if not exists ponto_previsto_externo_integracao_idx on public.ponto_previsto_externo (integracao_id);
comment on table public.ponto_previsto_externo is
  '[api:leitura] Previsto do dia vindo do RHiD (horário contratual, folga, feriado); prevalece sobre jornada e escala.';

alter table public.ponto_previsto_externo enable row level security;
drop policy if exists ponto_previsto_externo_ler on public.ponto_previsto_externo;
create policy ponto_previsto_externo_ler on public.ponto_previsto_externo for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

-- tipo de execução novo (a lista também está na …0120, para a reaplicação das migrações)
alter table public.sync_execucoes drop constraint if exists sync_execucoes_tipo_check;
alter table public.sync_execucoes add constraint sync_execucoes_tipo_check
  check (tipo in ('zig_lojas', 'zig_faturamento', 'zig_vendas', 'zig_compradores',
                  'zig_importar', 'controlid_usuarios', 'controlid_batidas', 'controlid_exportar_usuarios',
                  'apurar_ponto', 'tarefas_gerar', 'exportar_fechamento', 'tagme_importar',
                  'rhid_pessoas', 'rhid_batidas', 'rhid_horarios'));

-- Usado por ponto_calcular_dia (…0200). Sem linha → nulls (vale a jornada/escala).
create or replace function public.ponto_previsto_externo_dia(p_funcionario uuid, p_data date,
  out previsto_minutos int, out horarios time[])
language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select x.previsto_minutos, x.horarios
    from public.ponto_previsto_externo x
   where x.funcionario_id = p_funcionario and x.data = p_data
$$;
comment on function public.ponto_previsto_externo_dia(uuid, date) is
  '[interno] Previsto do dia vindo do RHiD (minutos e horários) — null se não houver.';

-- CPFs do RHiD ligados a funcionário (o N8N só pede a apuração desses).
create or replace function public.ingestao_rhid_vinculados(p_integracao uuid) returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
begin
  return coalesce((
    select jsonb_agg(c.user_id_externo order by c.user_id_externo)
      from public.controlid_usuarios c
      join public.funcionarios f on f.id = c.funcionario_id
     where c.integracao_id = ig.id and c.funcionario_id is not null and f.ativo), '[]'::jsonb);
end $$;
comment on function public.ingestao_rhid_vinculados(uuid) is
  '[servico] CPFs (user_id_externo) do RHiD ligados a funcionário ativo.';

-- p_dias: [{cpf, data, previsto_minutos, horarios: ["08:00", …], folga, feriado, saldo_minutos}]
-- Grava só o que mudou e reapura os dias alterados. Atualiza cursor.horarios_em.
create or replace function public.ingestao_rhid_horarios(p_integracao uuid, p_dias jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions, pg_temp as $$
declare
  ig        public.integracoes := public.integracao_validar(p_integracao, array['rhid']);
  x         jsonb;
  v_cpf     text;
  v_func    uuid;
  v_data    date;
  v_prev    int;
  v_hor     time[];
  v_folga   boolean;
  v_feriado text;
  v_saldo   int;
  v_mudou   boolean;
  v_grav    int := 0;
  v_iguais  int := 0;
  v_sem     int := 0;
  v_inval   int := 0;
  r         record;
begin
  p_dias := public.ingestao_lista(p_dias);
  if jsonb_array_length(p_dias) > 20000 then
    raise exception 'Lista maior que 20000 dias' using errcode = '22023';
  end if;
  create temp table if not exists pg_temp.rhid_horarios_alterados (funcionario_id uuid, data date) on commit drop;
  delete from pg_temp.rhid_horarios_alterados where true;  -- Supabase (pg_safeupdate) recusa DELETE sem WHERE

  for x in select value from jsonb_array_elements(p_dias) loop
    begin
      if jsonb_typeof(x) <> 'object' then raise exception 'item'; end if;
      v_cpf := public.rhid_documento(x -> 'cpf');
      v_data := (x ->> 'data')::date;
      v_prev := (x ->> 'previsto_minutos')::int;
      v_folga := coalesce((x ->> 'folga')::boolean, false);
      v_feriado := nullif(btrim(coalesce(x ->> 'feriado', '')), '');
      v_saldo := (x ->> 'saldo_minutos')::int;
      v_hor := coalesce((select array_agg(h::time order by o)
                           from jsonb_array_elements_text(case when jsonb_typeof(x -> 'horarios') = 'array'
                                                               then x -> 'horarios' else '[]'::jsonb end)
                                with ordinality t(h, o)), '{}');
      if v_cpf is null or v_data is null or v_prev is null or v_prev < 0 or v_prev > 1440 then raise exception 'item'; end if;
      if v_folga or v_feriado is not null then v_prev := 0; end if;
    exception when others then
      v_inval := v_inval + 1;
      continue;
    end;

    select c.funcionario_id into v_func
      from public.controlid_usuarios c
     where c.integracao_id = ig.id and c.user_id_externo = v_cpf and c.funcionario_id is not null;
    if v_func is null then
      v_sem := v_sem + 1;
      continue;
    end if;

    select (p.previsto_minutos, p.horarios, p.folga, p.feriado, p.saldo_externo_minutos)
           is distinct from (v_prev, v_hor, v_folga, v_feriado, v_saldo)
      into v_mudou
      from public.ponto_previsto_externo p
     where p.funcionario_id = v_func and p.data = v_data;
    if v_mudou is false then
      v_iguais := v_iguais + 1;
      continue;
    end if;

    insert into public.ponto_previsto_externo as p (
      funcionario_id, data, empresa_id, integracao_id, previsto_minutos, horarios, folga, feriado, saldo_externo_minutos)
    values (v_func, v_data, ig.empresa_id, ig.id, v_prev, v_hor, v_folga, v_feriado, v_saldo)
    on conflict (funcionario_id, data) do update set
      integracao_id = excluded.integracao_id, previsto_minutos = excluded.previsto_minutos, horarios = excluded.horarios,
      folga = excluded.folga, feriado = excluded.feriado, saldo_externo_minutos = excluded.saldo_externo_minutos,
      atualizado_em = now();
    insert into pg_temp.rhid_horarios_alterados values (v_func, v_data);
    v_grav := v_grav + 1;
  end loop;

  for r in select a.funcionario_id, min(a.data) as ini, max(a.data) as fim
             from pg_temp.rhid_horarios_alterados a group by a.funcionario_id loop
    perform public.ponto_apurar(r.funcionario_id, r.ini, r.fim);
  end loop;

  update public.integracoes i set cursor = i.cursor || jsonb_build_object('horarios_em', now()) where i.id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_dias), 'gravados', v_grav, 'iguais', v_iguais,
                            'sem_funcionario', v_sem, 'invalidos', v_inval,
                            'ignorados', v_sem + v_inval,
                            'funcionarios_reapurados', (select count(distinct a.funcionario_id) from pg_temp.rhid_horarios_alterados a));
end $$;
comment on function public.ingestao_rhid_horarios(uuid, jsonb) is
  '[servico] Previsto por dia da apuração do RHiD (horário, folga, feriado) → ponto_previsto_externo + reapuração.';
