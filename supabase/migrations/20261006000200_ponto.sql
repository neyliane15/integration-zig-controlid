-- =====================================================================================================
-- 20261006000200_ponto.sql — backend-2
-- Ponto: batidas, apuração diária, alarmes, ajustes manuais auditados, abonos e banco de horas.
-- Contrato: §6 (DDL), §7 (regras), §10.4 (RPCs). Idempotente (executar.sh aplica duas vezes).
-- =====================================================================================================

-- ================================================================= ponto_batidas
create table if not exists public.ponto_batidas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,
  integracao_id   uuid references public.integracoes (id) on delete set null,
  origem          text not null check (origem in ('controlid_acesso', 'controlid_rep', 'manual')),
  id_externo      text,
  pessoa_externa  text,
  instante        timestamptz not null,
  data_trabalho   date not null,
  desconsiderada  boolean not null default false,
  motivo          text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_batidas_externa_uk unique (integracao_id, id_externo)
);
-- A regra "ponto_batidas_origem" do contrato é validada no gatilho BEFORE INSERT (para não quebrar o on delete set null).
create index if not exists ponto_batidas_func_dia_idx on public.ponto_batidas (funcionario_id, data_trabalho);
create index if not exists ponto_batidas_empresa_dia_idx on public.ponto_batidas (empresa_id, data_trabalho);
create index if not exists ponto_batidas_sem_func_idx on public.ponto_batidas (empresa_id, integracao_id, pessoa_externa)
  where funcionario_id is null;
create index if not exists ponto_batidas_integracao_idx on public.ponto_batidas (integracao_id, pessoa_externa);
create index if not exists ponto_batidas_criado_por_idx on public.ponto_batidas (criado_por);
comment on table public.ponto_batidas is '[api:leitura] Batidas de ponto (Control iD acesso/REP e manuais). Importadas são imutáveis.';

-- =================================================================== ponto_dias
create table if not exists public.ponto_dias (
  funcionario_id      uuid not null references public.funcionarios (id) on delete cascade,
  data                date not null,
  empresa_id          uuid not null references public.empresas (id) on delete cascade,
  jornada_id          uuid references public.jornadas (id) on delete set null,
  abono_tipo          text,
  batidas_esperadas   smallint not null default 0,
  batidas_validas     smallint not null default 0,
  batidas_duplicadas  smallint not null default 0,
  previsto_minutos    int not null default 0,
  trabalhado_minutos  int not null default 0,
  saldo_minutos       int not null default 0,
  atraso_minutos      int not null default 0,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text not null check (situacao in ('completo', 'incompleto', 'ausente', 'folga',
                                                        'sem_escala', 'abonado', 'em_andamento')),
  encerrado           boolean not null,
  alarmes_abertos     smallint not null default 0,
  apurado_em          timestamptz not null default now(),
  primary key (funcionario_id, data)
);
create index if not exists ponto_dias_empresa_idx on public.ponto_dias (empresa_id, data);
create index if not exists ponto_dias_jornada_idx on public.ponto_dias (jornada_id);
comment on table public.ponto_dias is '[api:leitura] Resultado persistido da apuração (funcionário × dia de trabalho).';

-- ================================================================ ponto_alarmes
create table if not exists public.ponto_alarmes (
  id                         uuid primary key default gen_random_uuid(),
  empresa_id                 uuid not null references public.empresas (id) on delete cascade,
  funcionario_id             uuid not null references public.funcionarios (id) on delete cascade,
  data                       date not null,
  tipo                       text not null check (tipo in ('batida_faltando', 'batidas_impares',
                                                           'sem_batida_dia_escalado', 'atraso')),
  batida_esperada            text not null default ''
                             check (batida_esperada in ('', 'entrada', 'saida_intervalo', 'volta_intervalo', 'saida')),
  horario_previsto           timestamptz,
  minutos                    int,
  detalhe                    text not null,
  status                     text not null default 'aberto' check (status in ('aberto', 'justificado', 'resolvido')),
  justificativa              text,
  justificado_por            uuid references public.perfis (id) on delete set null,
  justificado_em             timestamptz,
  resolvido_em               timestamptz,
  resolvido_automaticamente  boolean not null default false,
  criado_em                  timestamptz not null default now(),
  atualizado_em              timestamptz not null default now(),
  unique (funcionario_id, data, tipo, batida_esperada)
);
create index if not exists ponto_alarmes_empresa_idx on public.ponto_alarmes (empresa_id, status, data desc);
create index if not exists ponto_alarmes_justificado_por_idx on public.ponto_alarmes (justificado_por);
comment on table public.ponto_alarmes is '[api:leitura] Alarmes de ponto (gerados pela apuração; justificar/reabrir por RPC).';

-- ================================================================= ponto_ajustes
create table if not exists public.ponto_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  batida_id        uuid references public.ponto_batidas (id) on delete set null,
  acao             text not null check (acao in ('incluir', 'desconsiderar', 'restaurar')),
  instante         timestamptz not null,
  motivo           text not null,
  feito_por        uuid references public.perfis (id) on delete set null,
  feito_por_nome   text not null,
  feito_em         timestamptz not null default now()
);
create index if not exists ponto_ajustes_empresa_idx on public.ponto_ajustes (empresa_id, feito_em desc);
create index if not exists ponto_ajustes_funcionario_idx on public.ponto_ajustes (funcionario_id);
create index if not exists ponto_ajustes_batida_idx on public.ponto_ajustes (batida_id);
create index if not exists ponto_ajustes_feito_por_idx on public.ponto_ajustes (feito_por);
comment on table public.ponto_ajustes is '[api:leitura] Auditoria de toda intervenção manual em batidas.';

-- ================================================================== ponto_abonos
create table if not exists public.ponto_abonos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid references public.funcionarios (id) on delete cascade,
  data            date not null,
  tipo            text not null check (tipo in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro')),
  motivo          text,
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  constraint ponto_abonos_uk unique nulls not distinct (empresa_id, funcionario_id, data)
);
create index if not exists ponto_abonos_funcionario_idx on public.ponto_abonos (funcionario_id, data);
create index if not exists ponto_abonos_criado_por_idx on public.ponto_abonos (criado_por);
comment on table public.ponto_abonos is '[api:leitura] Abonos (folga, feriado, férias, atestado...). funcionario_id null = empresa toda.';

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
-- §7.2/§7.3. Não grava nada. Retorna 0 linhas se o funcionário não existe; fora_do_vinculo = true se D fora do vínculo.
create or replace function public.ponto_calcular_dia(p_funcionario uuid, p_data date)
returns table (
  funcionario_id      uuid,
  data                date,
  empresa_id          uuid,
  fora_do_vinculo     boolean,
  jornada_id          uuid,
  jornada_nome        text,
  abono_tipo          text,
  batidas_esperadas   smallint,
  batidas_validas     smallint,
  batidas_duplicadas  smallint,
  previsto_minutos    int,
  trabalhado_minutos  int,
  saldo_minutos       int,
  atraso_minutos      int,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text,
  encerrado           boolean,
  batidas             jsonb,
  esperadas           jsonb,
  alarmes             jsonb
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  f            record;
  e            record;
  j            record;
  jd           record;
  v_abono      text;
  v_slots      timestamptz[] := '{}';
  v_nomes      text[] := '{}';
  v_validas    timestamptz[] := '{}';
  v_ultima     timestamptz;
  v_dup        boolean;
  v_dups       int := 0;
  v_n          int;
  v_k          int;
  v_trab       int := 0;
  v_prev       int := 0;
  v_saldo      int := 0;
  v_atraso     int := 0;
  v_tol_dia    int := 0;
  v_tol_bat    int := 0;
  v_batidas    jsonb := '[]'::jsonb;
  v_esperadas  jsonb := '[]'::jsonb;
  v_alarmes    jsonb := '[]'::jsonb;
  v_encerrado  boolean;
  v_situacao   text;
  b            record;
  i            int;
  v_mask       int;
  v_idx        int[];
  v_custo      numeric;
  v_melhor     int[];
  v_melhor_c   numeric;
  v_rotulos    constant jsonb := '{"entrada": "a entrada", "saida_intervalo": "a saída para o intervalo",
                                    "volta_intervalo": "a volta do intervalo", "saida": "a saída"}'::jsonb;
begin
  select * into f from public.funcionarios fu where fu.id = p_funcionario;
  if not found then return; end if;
  select * into e from public.empresas em where em.id = f.empresa_id;

  funcionario_id := f.id;
  data := p_data;
  empresa_id := f.empresa_id;

  if not public.ponto_no_vinculo(f.data_admissao, f.data_desligamento, p_data) then
    fora_do_vinculo := true;
    batidas_esperadas := 0; batidas_validas := 0; batidas_duplicadas := 0;
    previsto_minutos := 0; trabalhado_minutos := 0; saldo_minutos := 0; atraso_minutos := 0;
    encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);
    batidas := '[]'; esperadas := '[]'; alarmes := '[]';
    return next;
    return;
  end if;
  fora_do_vinculo := false;
  v_encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);

  -- 2. Escala e abono
  select jo.id, jo.nome, jo.tolerancia_batida_minutos, jo.tolerancia_diaria_minutos into j
    from public.funcionario_jornadas fj
    join public.jornadas jo on jo.id = fj.jornada_id
   where fj.funcionario_id = f.id and fj.vigente_desde <= p_data
   order by fj.vigente_desde desc
   limit 1;
  if j.id is not null then
    v_tol_dia := j.tolerancia_diaria_minutos;
    v_tol_bat := j.tolerancia_batida_minutos;
  end if;

  select a.tipo into v_abono
    from public.ponto_abonos a
   where a.empresa_id = f.empresa_id and a.data = p_data
     and (a.funcionario_id = f.id or a.funcionario_id is null)
   order by a.funcionario_id nulls last
   limit 1;

  v_k := 0;
  if v_abono is null and j.id is not null then
    select * into jd from public.jornada_dias x
     where x.jornada_id = j.id and x.dia_semana = extract(dow from p_data)::smallint;
    if found then
      v_prev := jd.minutos_previstos;
      v_k := jd.batidas_esperadas;
      if v_k = 4 then
        v_nomes := array['entrada', 'saida_intervalo', 'volta_intervalo', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.volta_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      else
        v_nomes := array['entrada', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      end if;
      for i in 1 .. v_k loop
        v_esperadas := v_esperadas || jsonb_build_object('batida', v_nomes[i], 'instante', v_slots[i]);
      end loop;
    end if;
  end if;

  -- 3. Batidas (duplicadas: a menos de N minutos da última válida)
  for b in
    select pb.id, pb.instante, pb.origem, pb.desconsiderada, pb.motivo
      from public.ponto_batidas pb
     where pb.funcionario_id = f.id and pb.data_trabalho = p_data
     order by pb.instante, pb.id
  loop
    v_dup := false;
    if not b.desconsiderada then
      if v_ultima is not null and b.instante - v_ultima < make_interval(mins => e.ponto_janela_duplicada_minutos) then
        v_dup := true;
        v_dups := v_dups + 1;
      else
        v_validas := v_validas || b.instante;
        v_ultima := b.instante;
      end if;
    end if;
    v_batidas := v_batidas || jsonb_build_object('id', b.id, 'instante', b.instante, 'origem', b.origem,
                                                 'desconsiderada', b.desconsiderada, 'duplicada', v_dup, 'motivo', b.motivo);
  end loop;
  v_n := coalesce(array_length(v_validas, 1), 0);

  -- 4. Trabalhado
  i := 1;
  while i + 1 <= v_n loop
    v_trab := v_trab + floor(extract(epoch from (v_validas[i + 1] - v_validas[i])) / 60)::int;
    i := i + 2;
  end loop;

  -- 5. Saldo
  if not v_encerrado then
    v_saldo := 0;
  elsif v_prev > 0 then
    if v_n = 0 then
      v_saldo := -v_prev;
    elsif abs(v_trab - v_prev) <= v_tol_dia then
      v_saldo := 0;
    else
      v_saldo := v_trab - v_prev;
    end if;
  else
    v_saldo := v_trab;
  end if;

  -- 6. Atraso
  if v_k > 0 and v_n > 0 then
    v_atraso := greatest(0, floor(extract(epoch from (v_validas[1] - v_slots[1])) / 60)::int);
    if v_atraso <= v_tol_bat then v_atraso := 0; end if;
  end if;

  -- 7. Situação
  if not v_encerrado then v_situacao := 'em_andamento';
  elsif v_abono is not null then v_situacao := 'abonado';
  elsif v_k = 0 and v_n = 0 then v_situacao := case when j.id is null then 'sem_escala' else 'folga' end;
  elsif v_n = 0 then v_situacao := 'ausente';
  elsif v_n >= v_k and v_n % 2 = 0 then v_situacao := 'completo';
  else v_situacao := 'incompleto';
  end if;

  -- 8. Alarmes (§7.3)
  if v_abono is null then
    if v_encerrado then
      if v_k > 0 and v_n = 0 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'sem_batida_dia_escalado', 'batida_esperada', '', 'horario_previsto', v_slots[1], 'minutos', null,
          'detalhe', format('Nenhuma batida em dia de escala (%s–%s)',
                            to_char(v_slots[1] at time zone e.fuso, 'HH24:MI'),
                            to_char(v_slots[v_k] at time zone e.fuso, 'HH24:MI')));
      elsif v_n > 0 and v_n < v_k then
        -- escolhe quais slots foram batidos: menor Σ|batida − slot|; empate → combinação lexicograficamente menor
        v_melhor := null;
        for v_mask in 0 .. (1 << v_k) - 1 loop
          v_idx := '{}';
          for i in 1 .. v_k loop
            if (v_mask >> (i - 1)) & 1 = 1 then v_idx := v_idx || i; end if;
          end loop;
          continue when coalesce(array_length(v_idx, 1), 0) <> v_n;
          v_custo := 0;
          for i in 1 .. v_n loop
            v_custo := v_custo + abs(extract(epoch from (v_validas[i] - v_slots[v_idx[i]])));
          end loop;
          if v_melhor is null or v_custo < v_melhor_c or (v_custo = v_melhor_c and v_idx < v_melhor) then
            v_melhor := v_idx;
            v_melhor_c := v_custo;
          end if;
        end loop;
        for i in 1 .. v_k loop
          if not (i = any (v_melhor)) then
            v_alarmes := v_alarmes || jsonb_build_object(
              'tipo', 'batida_faltando', 'batida_esperada', v_nomes[i], 'horario_previsto', v_slots[i], 'minutos', null,
              'detalhe', format('Faltou %s (%s)', v_rotulos ->> v_nomes[i], to_char(v_slots[i] at time zone e.fuso, 'HH24:MI')));
          end if;
        end loop;
      elsif v_n % 2 = 1 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'batidas_impares', 'batida_esperada', '', 'horario_previsto', null, 'minutos', null,
          'detalhe', format('%s %s (número ímpar)', v_n, case when v_n = 1 then 'batida' else 'batidas' end));
      end if;
    end if;
    if e.ponto_alarme_atraso and v_atraso > 0 then
      v_alarmes := v_alarmes || jsonb_build_object(
        'tipo', 'atraso', 'batida_esperada', 'entrada', 'horario_previsto', v_slots[1], 'minutos', v_atraso,
        'detalhe', format('Entrada %s (%s min de atraso)', to_char(v_validas[1] at time zone e.fuso, 'HH24:MI'), v_atraso));
    end if;
  end if;

  jornada_id := j.id;
  jornada_nome := j.nome;
  abono_tipo := v_abono;
  batidas_esperadas := v_k;
  batidas_validas := v_n;
  batidas_duplicadas := v_dups;
  previsto_minutos := v_prev;
  trabalhado_minutos := v_trab;
  saldo_minutos := v_saldo;
  atraso_minutos := v_atraso;
  primeira_batida := v_validas[1];
  ultima_batida := case when v_n > 0 then v_validas[v_n] end;
  situacao := v_situacao;
  encerrado := v_encerrado;
  batidas := v_batidas;
  esperadas := v_esperadas;
  alarmes := v_alarmes;
  return next;
end $$;
comment on function public.ponto_calcular_dia(uuid, date) is '[interno] Cálculo de um dia de ponto (§7.2/§7.3). Não grava.';

-- ============================================================ persistência
create or replace function public.ponto_contar_alarmes(p_funcionario uuid, p_data date)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  update public.ponto_dias d
     set alarmes_abertos = (select count(*) from public.ponto_alarmes a
                             where a.funcionario_id = p_funcionario and a.data = p_data and a.status = 'aberto')
   where d.funcionario_id = p_funcionario and d.data = p_data
$$;
comment on function public.ponto_contar_alarmes(uuid, date) is '[interno] Atualiza ponto_dias.alarmes_abertos.';

create or replace function public.ponto_apurar(p_funcionario uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa  uuid;
  v_atual    date;
  v_dia      date;
  c          record;
  a          jsonb;
  v_chaves   text[];
  v_total    int := 0;
begin
  if p_funcionario is null or p_inicio is null or p_fim is null then return 0; end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then return 0; end if;     -- funcionário excluído (cascata) → nada a fazer
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);

  for v_dia in select g::date from generate_series(p_inicio, least(p_fim, v_atual), interval '1 day') g loop
    select * into c from public.ponto_calcular_dia(p_funcionario, v_dia);

    if c.fora_do_vinculo then
      delete from public.ponto_dias where funcionario_id = p_funcionario and data = v_dia;
      update public.ponto_alarmes
         set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
       where funcionario_id = p_funcionario and data = v_dia and status = 'aberto';
      continue;
    end if;

    insert into public.ponto_dias as d (
      funcionario_id, data, empresa_id, jornada_id, abono_tipo, batidas_esperadas, batidas_validas, batidas_duplicadas,
      previsto_minutos, trabalhado_minutos, saldo_minutos, atraso_minutos, primeira_batida, ultima_batida,
      situacao, encerrado, apurado_em)
    values (
      p_funcionario, v_dia, v_empresa, c.jornada_id, c.abono_tipo, c.batidas_esperadas, c.batidas_validas, c.batidas_duplicadas,
      c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos, c.atraso_minutos, c.primeira_batida, c.ultima_batida,
      c.situacao, c.encerrado, public.agora())
    on conflict (funcionario_id, data) do update set
      jornada_id = excluded.jornada_id, abono_tipo = excluded.abono_tipo,
      batidas_esperadas = excluded.batidas_esperadas, batidas_validas = excluded.batidas_validas,
      batidas_duplicadas = excluded.batidas_duplicadas, previsto_minutos = excluded.previsto_minutos,
      trabalhado_minutos = excluded.trabalhado_minutos, saldo_minutos = excluded.saldo_minutos,
      atraso_minutos = excluded.atraso_minutos, primeira_batida = excluded.primeira_batida,
      ultima_batida = excluded.ultima_batida, situacao = excluded.situacao, encerrado = excluded.encerrado,
      apurado_em = excluded.apurado_em;

    v_chaves := '{}';
    for a in select * from jsonb_array_elements(c.alarmes) loop
      v_chaves := v_chaves || ((a ->> 'tipo') || '|' || (a ->> 'batida_esperada'));
      insert into public.ponto_alarmes as pa (
        empresa_id, funcionario_id, data, tipo, batida_esperada, horario_previsto, minutos, detalhe, status)
      values (
        v_empresa, p_funcionario, v_dia, a ->> 'tipo', a ->> 'batida_esperada',
        (a ->> 'horario_previsto')::timestamptz, (a ->> 'minutos')::int, a ->> 'detalhe', 'aberto')
      on conflict (funcionario_id, data, tipo, batida_esperada) do update set
        detalhe = excluded.detalhe,
        horario_previsto = excluded.horario_previsto,
        minutos = excluded.minutos,
        status = case when pa.status = 'resolvido' then 'aberto' else pa.status end,
        resolvido_em = case when pa.status = 'resolvido' then null else pa.resolvido_em end,
        resolvido_automaticamente = case when pa.status = 'resolvido' then false else pa.resolvido_automaticamente end
      where pa.status = 'resolvido'
         or (pa.detalhe, pa.horario_previsto, pa.minutos)
            is distinct from (excluded.detalhe, excluded.horario_previsto, excluded.minutos);
    end loop;

    update public.ponto_alarmes
       set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
     where funcionario_id = p_funcionario and data = v_dia and status = 'aberto'
       and not ((tipo || '|' || batida_esperada) = any (v_chaves));

    perform public.ponto_contar_alarmes(p_funcionario, v_dia);
    v_total := v_total + 1;
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar(uuid, date, date) is '[interno] Apura e persiste ponto_dias/ponto_alarmes (§7.4). Retorna dias apurados.';

-- Apura todos os funcionários de uma empresa (os que têm algum dia de vínculo no período).
create or replace function public.ponto_apurar_empresa(p_empresa uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_total int := 0; f record;
begin
  for f in
    select fu.id from public.funcionarios fu
     where fu.empresa_id = p_empresa
       and (fu.data_admissao is null or fu.data_admissao <= p_fim)
       and (fu.data_desligamento is null or fu.data_desligamento >= p_inicio)
     order by fu.id
  loop
    v_total := v_total + public.ponto_apurar(f.id, p_inicio, p_fim);
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar_empresa(uuid, date, date) is '[interno] Apura todos os funcionários da empresa no período.';

-- ======================================================= gatilhos em tabelas do backend-1 (§7.8)
create or replace function public.ponto_gatilho_controlid_usuario()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_antigo uuid := case when tg_op = 'UPDATE' then old.funcionario_id end;
  v_datas  date[];
  v_dia    date;
begin
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = new.funcionario_id
     where b.integracao_id = new.integracao_id
       and b.pessoa_externa = new.user_id_externo
       and b.origem = 'controlid_acesso'
       and (b.funcionario_id is null or b.funcionario_id = v_antigo)
       and b.funcionario_id is distinct from new.funcionario_id
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;

  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(v_antigo, v_dia, v_dia);
      perform public.ponto_apurar(new.funcionario_id, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_controlid_usuario() is '[interno] §7.8: vínculo Control iD → batidas de acesso e reapuração.';

drop trigger if exists ponto_vinculo_batidas on public.controlid_usuarios;
create trigger ponto_vinculo_batidas after update of funcionario_id on public.controlid_usuarios
  for each row when (old.funcionario_id is distinct from new.funcionario_id)
  execute function public.ponto_gatilho_controlid_usuario();
drop trigger if exists ponto_vinculo_batidas_ins on public.controlid_usuarios;
create trigger ponto_vinculo_batidas_ins after insert on public.controlid_usuarios
  for each row when (new.funcionario_id is not null)
  execute function public.ponto_gatilho_controlid_usuario();

create or replace function public.ponto_gatilho_funcionario_documentos()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_datas date[]; v_dia date;
begin
  if new.cpf is null and new.pis is null then return null; end if;
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = new.id
     where b.empresa_id = new.empresa_id
       and b.origem = 'controlid_rep'
       and b.funcionario_id is null
       and b.pessoa_externa is not null
       and b.pessoa_externa in (new.cpf, new.pis)
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;
  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(new.id, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_documentos() is '[interno] §7.8: CPF/PIS do funcionário → batidas REP sem vínculo.';

drop trigger if exists ponto_documentos on public.funcionarios;
create trigger ponto_documentos after insert or update of cpf, pis on public.funcionarios
  for each row execute function public.ponto_gatilho_funcionario_documentos();

create or replace function public.ponto_gatilho_funcionario_vinculo()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_atual date;
begin
  v_atual := public.dia_de_trabalho(public.agora(), new.empresa_id);
  perform public.ponto_apurar(new.id, v_atual - 93, v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_vinculo() is '[interno] §7.8: mudança de admissão/desligamento/ativo → reapura 93 dias.';

drop trigger if exists ponto_vinculo on public.funcionarios;
create trigger ponto_vinculo after update of data_admissao, data_desligamento, ativo on public.funcionarios
  for each row
  when (old.data_admissao is distinct from new.data_admissao
        or old.data_desligamento is distinct from new.data_desligamento
        or old.ativo is distinct from new.ativo)
  execute function public.ponto_gatilho_funcionario_vinculo();

create or replace function public.ponto_gatilho_funcionario_jornada()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_func   uuid;
  v_desde  date;
  v_empresa uuid;
  v_atual  date;
begin
  if tg_op = 'DELETE' then
    v_func := old.funcionario_id; v_desde := old.vigente_desde;
  elsif tg_op = 'UPDATE' then
    v_func := new.funcionario_id; v_desde := least(old.vigente_desde, new.vigente_desde);
    if old.funcionario_id is distinct from new.funcionario_id then
      select f.empresa_id into v_empresa from public.funcionarios f where f.id = old.funcionario_id;
      if v_empresa is not null then
        v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
        perform public.ponto_apurar(old.funcionario_id, greatest(old.vigente_desde, v_atual - 93), v_atual);
      end if;
    end if;
  else
    v_func := new.funcionario_id; v_desde := new.vigente_desde;
  end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = v_func;
  if v_empresa is null then return null; end if;
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
  perform public.ponto_apurar(v_func, greatest(v_desde, v_atual - 93), v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_jornada() is '[interno] §7.8: escala do funcionário mudou → reapura desde vigente_desde (máx. 93 dias).';

drop trigger if exists ponto_reapurar on public.funcionario_jornadas;
create trigger ponto_reapurar after insert or update or delete on public.funcionario_jornadas
  for each row execute function public.ponto_gatilho_funcionario_jornada();

create or replace function public.ponto_gatilho_jornada()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_jornada uuid;
  v_empresa uuid;
  v_atual   date;
  f         record;
begin
  if tg_table_name = 'jornadas' then
    v_jornada := coalesce(new.id, old.id);
  else
    v_jornada := coalesce(new.jornada_id, old.jornada_id);
  end if;
  select j.empresa_id into v_empresa from public.jornadas j where j.id = v_jornada;
  if v_empresa is null then return null; end if;
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
  for f in
    select distinct fj.funcionario_id from public.funcionario_jornadas fj
     where fj.jornada_id = v_jornada
  loop
    perform public.ponto_apurar(f.funcionario_id, v_atual - 31, v_atual);
  end loop;
  return null;
end $$;
comment on function public.ponto_gatilho_jornada() is '[interno] §7.8: jornada/jornada_dias mudou → reapura 31 dias dos funcionários dessa jornada.';

drop trigger if exists ponto_reapurar on public.jornada_dias;
create trigger ponto_reapurar after insert or update or delete on public.jornada_dias
  for each row execute function public.ponto_gatilho_jornada();
drop trigger if exists ponto_reapurar on public.jornadas;
create trigger ponto_reapurar after update of tolerancia_batida_minutos, tolerancia_diaria_minutos on public.jornadas
  for each row execute function public.ponto_gatilho_jornada();

-- Empresa: mudar fuso/virada/janela/alarme de atraso → reapura 31 dias.
create or replace function public.ponto_gatilho_empresa()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_atual date;
begin
  v_atual := public.dia_de_trabalho(public.agora(), new.id);
  perform public.ponto_apurar_empresa(new.id, v_atual - 31, v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_empresa() is '[interno] Parâmetros de ponto da empresa mudaram → reapura 31 dias.';

drop trigger if exists ponto_reapurar on public.empresas;
create trigger ponto_reapurar after update of fuso, virada_dia, ponto_janela_duplicada_minutos, ponto_alarme_atraso on public.empresas
  for each row
  when (old.fuso is distinct from new.fuso or old.virada_dia is distinct from new.virada_dia
        or old.ponto_janela_duplicada_minutos is distinct from new.ponto_janela_duplicada_minutos
        or old.ponto_alarme_atraso is distinct from new.ponto_alarme_atraso)
  execute function public.ponto_gatilho_empresa();

-- Fuso/virada mudou → data_trabalho das batidas precisa ser recalculada (antes da reapuração acima).
create or replace function public.ponto_gatilho_empresa_datas()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  -- o gatilho a_antes de ponto_batidas recalcula data_trabalho a partir da empresa já atualizada
  update public.ponto_batidas b
     set data_trabalho = b.data_trabalho
   where b.empresa_id = new.id
     and b.data_trabalho is distinct from ((b.instante at time zone new.fuso) - new.virada_dia)::date;
  return null;
end $$;
comment on function public.ponto_gatilho_empresa_datas() is '[interno] Recalcula data_trabalho das batidas quando fuso/virada mudam.';

drop trigger if exists a_ponto_datas on public.empresas;
create trigger a_ponto_datas after update of fuso, virada_dia on public.empresas
  for each row when (old.fuso is distinct from new.fuso or old.virada_dia is distinct from new.virada_dia)
  execute function public.ponto_gatilho_empresa_datas();

-- ============================================================ RPCs de leitura
create or replace function public.ponto_espelho(p_funcionario uuid, p_inicio date, p_fim date)
returns table (data date, dia_semana smallint, situacao text, encerrado boolean, abono_tipo text, jornada_nome text,
               previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int,
               batidas jsonb, alarmes jsonb, esperadas jsonb)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);

  return query
  select c.data, extract(dow from c.data)::smallint, c.situacao, c.encerrado, c.abono_tipo, c.jornada_nome,
         c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos, c.atraso_minutos, c.batidas,
         coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'tipo', a.tipo, 'batida_esperada', a.batida_esperada,
                                                       'status', a.status, 'detalhe', a.detalhe, 'justificativa', a.justificativa)
                                    order by a.horario_previsto nulls last, a.tipo, a.batida_esperada)
                     from public.ponto_alarmes a
                    where a.funcionario_id = p_funcionario and a.data = c.data
                      and a.status <> 'resolvido'), '[]'::jsonb),
         c.esperadas
    from generate_series(p_inicio, p_fim, interval '1 day') g
    cross join lateral public.ponto_calcular_dia(p_funcionario, g::date) c
   where not c.fora_do_vinculo
   order by c.data;
end $$;
comment on function public.ponto_espelho(uuid, date, date) is '[api] Espelho de ponto calculado ao vivo (máx. 62 dias). alarmes: abertos e justificados.';

create or replace function public.ponto_dia_empresa(p_data date default null, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, situacao text, encerrado boolean,
               previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int,
               batidas jsonb, alarmes_abertos int)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_data date;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.dia_de_trabalho(public.agora(), v_empresa));
  return query
  select f.id, f.nome, f.cargo, c.situacao, c.encerrado, c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos,
         c.atraso_minutos, c.batidas,
         (select count(*)::int from public.ponto_alarmes a
           where a.funcionario_id = f.id and a.data = v_data and a.status = 'aberto')
    from public.funcionarios f
    cross join lateral public.ponto_calcular_dia(f.id, v_data) c
   where f.empresa_id = v_empresa
     and not c.fora_do_vinculo
     and (f.ativo or jsonb_array_length(c.batidas) > 0)
   order by f.nome, f.id;
end $$;
comment on function public.ponto_dia_empresa(date, uuid) is '[api] Ponto do dia de todos os funcionários da empresa (ao vivo).';

-- ============================================================ RPCs de ação
create or replace function public.ponto_reapurar(p_inicio date, p_fim date, p_funcionario uuid default null,
                                                 p_empresa uuid default null)
returns integer language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  if p_funcionario is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
    if p_empresa is not null and p_empresa <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 93);
  if p_funcionario is not null then
    return public.ponto_apurar(p_funcionario, p_inicio, p_fim);
  end if;
  return public.ponto_apurar_empresa(v_empresa, p_inicio, p_fim);
end $$;
comment on function public.ponto_reapurar(date, date, uuid, uuid) is '[api] Recalcula o ponto (máx. 93 dias).';

create or replace function public.ponto_incluir_batida(p_funcionario uuid, p_instante timestamptz, p_motivo text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid; v_dia date;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if p_instante is null then raise exception 'Horário inválido' using errcode = '22023'; end if;
  if p_instante > public.agora() then raise exception 'Horário no futuro' using errcode = '22023'; end if;

  insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo, criado_por)
  values (v_empresa, p_funcionario, 'manual', p_instante, btrim(p_motivo), auth.uid())
  returning id, data_trabalho into v_id, v_dia;

  insert into public.ponto_ajustes (empresa_id, funcionario_id, batida_id, acao, instante, motivo, feito_por, feito_por_nome, feito_em)
  values (v_empresa, p_funcionario, v_id, 'incluir', p_instante, btrim(p_motivo), auth.uid(), public.ponto_nome_autor(), public.agora());

  perform public.ponto_apurar(p_funcionario, v_dia, v_dia);
  return v_id;
end $$;
comment on function public.ponto_incluir_batida(uuid, timestamptz, text) is '[api] Inclui batida manual (auditada) e reapura o dia.';

create or replace function public.ponto_marcar_batida(p_batida uuid, p_motivo text, p_desconsiderar boolean)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare b record;
begin
  select * into b from public.ponto_batidas where id = p_batida;
  if not found then raise exception 'Batida não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(b.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_motivo is null or btrim(p_motivo) = '' then raise exception 'Informe o motivo' using errcode = '22023'; end if;
  if b.funcionario_id is null then
    raise exception 'Batida sem funcionário vinculado' using errcode = '22023';
  end if;

  update public.ponto_batidas
     set desconsiderada = p_desconsiderar,
         motivo = case when p_desconsiderar then btrim(p_motivo)
                       when origem = 'manual' then coalesce(
                         (select aj.motivo from public.ponto_ajustes aj
                           where aj.batida_id = p_batida and aj.acao = 'incluir' order by aj.feito_em limit 1), motivo)
                       else null end
   where id = p_batida;

  insert into public.ponto_ajustes (empresa_id, funcionario_id, batida_id, acao, instante, motivo, feito_por, feito_por_nome, feito_em)
  values (b.empresa_id, b.funcionario_id, b.id, case when p_desconsiderar then 'desconsiderar' else 'restaurar' end,
          b.instante, btrim(p_motivo), auth.uid(), public.ponto_nome_autor(), public.agora());

  perform public.ponto_apurar(b.funcionario_id, b.data_trabalho, b.data_trabalho);
end $$;
comment on function public.ponto_marcar_batida(uuid, text, boolean) is '[interno] Desconsidera/restaura batida com auditoria.';

create or replace function public.ponto_desconsiderar_batida(p_batida uuid, p_motivo text)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  select public.ponto_marcar_batida(p_batida, p_motivo, true)
$$;
comment on function public.ponto_desconsiderar_batida(uuid, text) is '[api] Desconsidera uma batida (auditado) e reapura.';

create or replace function public.ponto_restaurar_batida(p_batida uuid, p_motivo text)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  select public.ponto_marcar_batida(p_batida, p_motivo, false)
$$;
comment on function public.ponto_restaurar_batida(uuid, text) is '[api] Restaura uma batida desconsiderada (auditado) e reapura.';

create or replace function public.ponto_justificar_alarme(p_alarme uuid, p_justificativa text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_alarmes where id = p_alarme;
  if not found then raise exception 'Alarme não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  if p_justificativa is null or btrim(p_justificativa) = '' then
    raise exception 'Informe a justificativa' using errcode = '22023';
  end if;
  update public.ponto_alarmes
     set status = 'justificado', justificativa = btrim(p_justificativa),
         justificado_por = auth.uid(), justificado_em = public.agora(),
         resolvido_em = null, resolvido_automaticamente = false
   where id = p_alarme;
  perform public.ponto_contar_alarmes(a.funcionario_id, a.data);
end $$;
comment on function public.ponto_justificar_alarme(uuid, text) is '[api] Justifica um alarme (não altera saldo).';

create or replace function public.ponto_reabrir_alarme(p_alarme uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_alarmes where id = p_alarme;
  if not found then raise exception 'Alarme não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  update public.ponto_alarmes
     set status = 'aberto', justificativa = null, justificado_por = null, justificado_em = null,
         resolvido_em = null, resolvido_automaticamente = false
   where id = p_alarme;
  -- se o alarme não é mais esperado, a apuração o resolve de novo automaticamente
  perform public.ponto_apurar(a.funcionario_id, a.data, a.data);
  perform public.ponto_contar_alarmes(a.funcionario_id, a.data);
end $$;
comment on function public.ponto_reabrir_alarme(uuid) is '[api] Reabre um alarme justificado.';

create or replace function public.ponto_abonar(p_inicio date, p_fim date, p_tipo text, p_motivo text default null,
                                               p_funcionario uuid default null, p_empresa uuid default null)
returns integer language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_dias int;
begin
  if p_funcionario is not null then
    select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
    if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
    if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
    if p_empresa is not null and p_empresa <> v_empresa then
      raise exception 'Funcionário de outra empresa' using errcode = '22023';
    end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_tipo is null or p_tipo not in ('folga', 'feriado', 'ferias', 'atestado', 'compensacao', 'outro') then
    raise exception 'Tipo de abono inválido' using errcode = '22023';
  end if;

  insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por)
  select v_empresa, p_funcionario, g::date, p_tipo, nullif(btrim(p_motivo), ''), auth.uid()
    from generate_series(p_inicio, p_fim, interval '1 day') g
  on conflict on constraint ponto_abonos_uk do update
    set tipo = excluded.tipo, motivo = excluded.motivo, criado_por = excluded.criado_por, criado_em = now();
  v_dias := p_fim - p_inicio + 1;

  if p_funcionario is not null then
    perform public.ponto_apurar(p_funcionario, p_inicio, p_fim);
  else
    perform public.ponto_apurar_empresa(v_empresa, p_inicio, p_fim);
  end if;
  return v_dias;
end $$;
comment on function public.ponto_abonar(date, date, text, text, uuid, uuid) is '[api] Abona dias (upsert por dia) e reapura.';

create or replace function public.ponto_remover_abono(p_abono uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a record;
begin
  select * into a from public.ponto_abonos where id = p_abono;
  if not found then raise exception 'Abono não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(a.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  delete from public.ponto_abonos where id = p_abono;
  if a.funcionario_id is not null then
    perform public.ponto_apurar(a.funcionario_id, a.data, a.data);
  else
    perform public.ponto_apurar_empresa(a.empresa_id, a.data, a.data);
  end if;
end $$;
comment on function public.ponto_remover_abono(uuid) is '[api] Remove um abono e reapura.';

-- ============================================================ banco de horas (§7.5)
create or replace function public.banco_horas_calcular_saldo(p_funcionario uuid, p_ate date)
returns bigint language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_base bigint := 0; v_inicio date := '-infinity'; b record;
begin
  select l.data, l.minutos into b
    from public.banco_horas_lancamentos l
   where l.funcionario_id = p_funcionario and l.tipo = 'saldo_inicial' and l.data <= p_ate
   order by l.data desc
   limit 1;
  if found then v_base := b.minutos; v_inicio := b.data; end if;
  return v_base
    + coalesce((select sum(d.saldo_minutos) from public.ponto_dias d
                 where d.funcionario_id = p_funcionario and d.encerrado and d.data between v_inicio and p_ate), 0)
    + coalesce((select sum(l.minutos) from public.banco_horas_lancamentos l
                 where l.funcionario_id = p_funcionario and l.tipo <> 'saldo_inicial' and l.data between v_inicio and p_ate), 0);
end $$;
comment on function public.banco_horas_calcular_saldo(uuid, date) is '[interno] Saldo do banco de horas até a data (§7.5).';

create or replace function public.banco_horas_saldo(p_funcionario uuid, p_ate date default null)
returns bigint language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_ler(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return public.banco_horas_calcular_saldo(p_funcionario,
           coalesce(p_ate, public.dia_de_trabalho(public.agora(), v_empresa) - 1));
end $$;
comment on function public.banco_horas_saldo(uuid, date) is '[api] Saldo do banco de horas (padrão: até ontem).';

create or replace function public.banco_horas_resumo(p_ate date default null, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, saldo_minutos bigint, saldo_mes_minutos bigint,
               ultimo_dia_apurado date)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_ate date; v_mes date;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_ate := coalesce(p_ate, public.dia_de_trabalho(public.agora(), v_empresa) - 1);
  v_mes := date_trunc('month', v_ate)::date;
  return query
  select f.id, f.nome, f.cargo,
         public.banco_horas_calcular_saldo(f.id, v_ate),
         (select coalesce(sum(d.saldo_minutos), 0) from public.ponto_dias d
           where d.funcionario_id = f.id and d.encerrado and d.data between greatest(v_mes, r.inicio) and v_ate)
         + (select coalesce(sum(l.minutos), 0) from public.banco_horas_lancamentos l
             where l.funcionario_id = f.id and l.tipo <> 'saldo_inicial' and l.data between greatest(v_mes, r.inicio) and v_ate),
         (select max(d.data) from public.ponto_dias d where d.funcionario_id = f.id and d.encerrado)
    from public.funcionarios f
    cross join lateral (
      select coalesce((select max(l.data) from public.banco_horas_lancamentos l
                        where l.funcionario_id = f.id and l.tipo = 'saldo_inicial' and l.data <= v_ate),
                      '-infinity'::date) as inicio) r
   where f.empresa_id = v_empresa and f.ativo
   order by f.nome, f.id;
end $$;
comment on function public.banco_horas_resumo(date, uuid) is '[api] Saldo do banco de horas por funcionário ativo.';

create or replace function public.banco_horas_extrato(p_funcionario uuid, p_inicio date, p_fim date)
returns table (data date, tipo text, descricao text, minutos int, saldo_acumulado bigint, referencia_id uuid)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid;
  v_saldo   bigint;
  r         record;
  v_rotulos constant jsonb := '{"completo":"Completo","incompleto":"Incompleto","ausente":"Ausente","folga":"Folga",
     "sem_escala":"Sem escala","abonado":"Abonado","em_andamento":"Em andamento"}'::jsonb;
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
comment on function public.banco_horas_excluir_lancamento(uuid) is '[api] Exclui lançamento do banco de horas (administrador).';
