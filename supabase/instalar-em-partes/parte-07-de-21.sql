-- Meu Dia de Gerente — instalação do banco, PARTE 07 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000200_ponto.sql. Não edite à mão.

begin;
alter table public.ponto_dias add constraint ponto_dias_situacao_check
  check (situacao in ('completo', 'incompleto', 'ausente', 'folga', 'sem_escala', 'abonado', 'suspenso', 'em_andamento',
                      'falta_justificada', 'falta_injustificada'));

-- ======================================================= banco_horas_lancamentos
create table if not exists public.banco_horas_lancamentos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  tipo             text not null check (tipo in ('saldo_inicial', 'ajuste', 'compensacao', 'pagamento')),
  minutos          int not null,
  motivo           text not null check (btrim(motivo) <> ''),
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now()
);
create unique index if not exists banco_horas_saldo_inicial_uk on public.banco_horas_lancamentos (funcionario_id, data)
  where tipo = 'saldo_inicial';
create index if not exists banco_horas_empresa_idx on public.banco_horas_lancamentos (empresa_id, data);
create index if not exists banco_horas_funcionario_idx on public.banco_horas_lancamentos (funcionario_id, data);
create index if not exists banco_horas_criado_por_idx on public.banco_horas_lancamentos (criado_por);
comment on table public.banco_horas_lancamentos is '[api:leitura] Lançamentos manuais do banco de horas (saldo inicial, ajustes, compensações, pagamentos).';

-- ========================================================================= RLS
alter table public.ponto_batidas enable row level security;
alter table public.ponto_dias enable row level security;
alter table public.ponto_alarmes enable row level security;
alter table public.ponto_ajustes enable row level security;
alter table public.ponto_abonos enable row level security;
alter table public.banco_horas_lancamentos enable row level security;

drop policy if exists ponto_batidas_ler on public.ponto_batidas;
create policy ponto_batidas_ler on public.ponto_batidas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_dias_ler on public.ponto_dias;
create policy ponto_dias_ler on public.ponto_dias for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_alarmes_ler on public.ponto_alarmes;
create policy ponto_alarmes_ler on public.ponto_alarmes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists ponto_ajustes_ler on public.ponto_ajustes;
create policy ponto_ajustes_ler on public.ponto_ajustes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));
drop policy if exists ponto_abonos_ler on public.ponto_abonos;
create policy ponto_abonos_ler on public.ponto_abonos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists banco_horas_ler on public.banco_horas_lancamentos;
create policy banco_horas_ler on public.banco_horas_lancamentos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

-- ================================================================ auxiliares
create or replace function public.ponto_validar_periodo(p_inicio date, p_fim date, p_max_dias int)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido' using errcode = '22023';
  end if;
  if p_fim - p_inicio + 1 > p_max_dias then
    raise exception 'Período máximo de % dias', p_max_dias using errcode = '22023';
  end if;
end $$;
comment on function public.ponto_validar_periodo(date, date, int) is '[interno] Valida período (Período inválido / Período máximo de N dias).';

create or replace function public.ponto_nome_autor()
returns text language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce((select p.nome from public.perfis p where p.id = auth.uid()), 'Sistema')
$$;
comment on function public.ponto_nome_autor() is '[interno] Nome do perfil logado ou ''Sistema''.';

-- resolver_empresa (b1) + checagem nula-segura do nível (defesa em profundidade).
create or replace function public.ponto_resolver_empresa(p_empresa uuid, p_nivel text)
returns uuid language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v uuid;
begin
  v := public.resolver_empresa(p_empresa, p_nivel);
  if (case p_nivel when 'ler' then public.pode_ler(v) when 'operar' then public.pode_operar(v)
                   when 'administrar' then public.pode_administrar(v) end) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return v;
end $$;
comment on function public.ponto_resolver_empresa(uuid, text) is '[interno] resolver_empresa com checagem nula-segura do nível.';

-- Instante do horário de escala t no dia de trabalho D (§2.4).
create or replace function public.ponto_instante_escala(p_data date, p_hora time, p_fuso text, p_virada time)
returns timestamptz language sql stable set search_path = public, extensions, pg_temp as $$
  select ((p_data + p_hora) + (case when p_hora < p_virada then interval '1 day' else interval '0' end)) at time zone p_fuso
$$;
comment on function public.ponto_instante_escala(date, time, text, time) is '[interno] Instante de um horário de escala no dia de trabalho (§2.4).';

create or replace function public.ponto_fmt_minutos(p_minutos bigint)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select case when p_minutos < 0 then '-' else '' end
      || (abs(p_minutos) / 60)::text || 'h' || lpad((abs(p_minutos) % 60)::text, 2, '0')
$$;
comment on function public.ponto_fmt_minutos(bigint) is '[interno] Minutos como 7h30 / -3h26.';

-- Funcionário dentro do vínculo na data?
create or replace function public.ponto_no_vinculo(p_admissao date, p_desligamento date, p_data date)
returns boolean language sql immutable set search_path = public, extensions, pg_temp as $$
  select (p_admissao is null or p_data >= p_admissao) and (p_desligamento is null or p_data <= p_desligamento)
$$;
comment on function public.ponto_no_vinculo(date, date, date) is '[interno] Data dentro do vínculo (admissão/desligamento).';

-- ============================================== gatilhos das tabelas de ponto
create or replace function public.ponto_empresa_do_funcionario()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if new.funcionario_id is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
    if tg_table_name = 'ponto_abonos' and new.empresa_id is not null and new.empresa_id <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
    new.empresa_id := v_empresa;
  end if;
  return new;
end $$;
comment on function public.ponto_empresa_do_funcionario() is '[interno] Gatilho: empresa_id preenchido a partir do funcionário.';

drop trigger if exists a_empresa on public.ponto_dias;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_dias
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_alarmes;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_alarmes
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_ajustes;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_ajustes
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.ponto_abonos;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.ponto_abonos
  for each row execute function public.ponto_empresa_do_funcionario();
drop trigger if exists a_empresa on public.banco_horas_lancamentos;
create trigger a_empresa before insert or update of funcionario_id, empresa_id on public.banco_horas_lancamentos
  for each row execute function public.ponto_empresa_do_funcionario();

drop trigger if exists tocar_atualizado_em on public.ponto_alarmes;
create trigger tocar_atualizado_em before update on public.ponto_alarmes
  for each row execute function public.tocar_atualizado_em();

create or replace function public.ponto_batidas_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if tg_op = 'INSERT' then
    if new.funcionario_id is not null then
      select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
      if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
      if new.empresa_id is null then new.empresa_id := v_empresa;
      elsif new.empresa_id <> v_empresa then raise exception 'Funcionário de outra empresa' using errcode = '22023';
      end if;
    end if;
    if new.integracao_id is not null then
      select i.empresa_id into v_empresa from public.integracoes i where i.id = new.integracao_id;
      if v_empresa is null then raise exception 'Integração não encontrada' using errcode = 'P0002'; end if;
      if new.empresa_id is null then new.empresa_id := v_empresa;
      elsif new.empresa_id <> v_empresa then raise exception 'Integração de outra empresa' using errcode = '22023';
      end if;
    end if;
    -- regra ponto_batidas_origem (§6)
    if not ((new.origem = 'manual' and new.funcionario_id is not null and new.motivo is not null and new.id_externo is null)
         or (new.origem <> 'manual' and new.id_externo is not null and new.integracao_id is not null)) then
      raise exception 'Batida inválida para a origem %', new.origem using errcode = '23514';
    end if;
    new.data_trabalho := public.dia_de_trabalho(new.instante, new.empresa_id);
    return new;
  end if;

  -- UPDATE: batidas são imutáveis; só desconsiderada/motivo (RPC), funcionario_id (vínculo, §7.8)
  -- e integracao_id → null (exclusão da integração) podem mudar.
  if new.origem is distinct from old.origem or new.id_externo is distinct from old.id_externo
     or new.pessoa_externa is distinct from old.pessoa_externa or new.empresa_id is distinct from old.empresa_id
     or (new.instante is distinct from old.instante and old.origem <> 'manual')
     or (new.integracao_id is distinct from old.integracao_id and new.integracao_id is not null) then
    raise exception 'Batida importada não pode ser alterada' using errcode = '22023';
  end if;
  if new.funcionario_id is not null and new.funcionario_id is distinct from old.funcionario_id then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = new.funcionario_id;
    if v_empresa is distinct from new.empresa_id then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  end if;
  -- sempre derivada (também quando fuso/virada da empresa mudam)
  new.data_trabalho := public.dia_de_trabalho(new.instante, new.empresa_id);
  return new;
end $$;
comment on function public.ponto_batidas_antes() is '[interno] Gatilho de ponto_batidas: empresa, regra de origem, data_trabalho e imutabilidade.';

drop trigger if exists a_antes on public.ponto_batidas;
create trigger a_antes before insert or update on public.ponto_batidas
  for each row execute function public.ponto_batidas_antes();

-- ============================================================ cálculo de um dia
-- (adendo escala) Status da escala rotativa no dia: a função real é definida em …0280_escala.sql. Aqui só um esqueleto
-- (criado se ainda não existir) para que a apuração funcione antes da …0280 numa instalação/atualização em andamento.
do $$
begin
  if to_regprocedure('public.escala_status_ponto(uuid, date)') is null then
    execute $f$create function public.escala_status_ponto(p_funcionario uuid, p_data date, out status text, out chegada time)
      language sql stable security definer set search_path = public, extensions, pg_temp as
      'select null::text, null::time'$f$;
    execute $c$comment on function public.escala_status_ponto(uuid, date) is '[interno] Status da escala no dia (esqueleto; ver …0280).'$c$;
  end if;
  -- (adendo RHiD §R.9) horário previsto importado do RHiD: a função real é definida em …0320_rhid_horarios.sql.
  if to_regprocedure('public.ponto_previsto_externo_dia(uuid, date)') is null then
    execute $f$create function public.ponto_previsto_externo_dia(p_funcionario uuid, p_data date,
      out previsto_minutos int, out horarios time[], out tolerancia_extra_minutos int, out tolerancia_falta_minutos int)
      language sql stable security definer set search_path = public, extensions, pg_temp as
      'select null::int, null::time[], null::int, null::int'$f$;
    execute $c$comment on function public.ponto_previsto_externo_dia(uuid, date) is '[interno] Previsto externo do dia (esqueleto; ver …0320).'$c$;
  end if;
  -- (adendo extras v3, §E.7.2) falta do funcionário no dia: a função real é definida em …0290_comissao_presenca.sql.
  if to_regprocedure('public.ponto_falta_do_dia(uuid, date)') is null then
    execute $f$create function public.ponto_falta_do_dia(p_funcionario uuid, p_data date) returns text
      language sql stable security definer set search_path = public, extensions, pg_temp as 'select null::text'$f$;
    execute $c$comment on function public.ponto_falta_do_dia(uuid, date) is '[interno] Falta do funcionário no dia (esqueleto; ver …0290).'$c$;
  end if;
end $$;

commit;
select 'parte 07 de 21 instalada' as resultado;
