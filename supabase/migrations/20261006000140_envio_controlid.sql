-- =====================================================================================================
-- 20261006000140_envio_controlid.sql  (backend-1)
-- Envio de dados ao Control iD (sistema → equipamento): credenciais (senha/cartões), foto facial, horários de
-- acesso, fila/estado de envio por equipamento × funcionário. Especificação: docs/CONTRATO-ADENDO-envio-controlid.md.
-- Idempotente.
-- =====================================================================================================

-- ======================================================================================== tabelas
create table if not exists public.funcionario_credenciais (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  senha           text check (senha is null or senha ~ '^[0-9]{4,8}$'),
  versao          int not null default 1,
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_credenciais_empresa_idx on public.funcionario_credenciais (empresa_id);
comment on table public.funcionario_credenciais is
  '[api:nenhum] Senha de acesso (PIN) do funcionário nos equipamentos. Nunca legível pela API.';

create table if not exists public.funcionario_cartoes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  numero          text not null check (numero ~ '^[0-9]{1,20}$'),
  criado_por      uuid references public.perfis (id) on delete set null,
  criado_em       timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index if not exists funcionario_cartoes_funcionario_idx on public.funcionario_cartoes (funcionario_id);
create index if not exists funcionario_cartoes_criado_por_idx on public.funcionario_cartoes (criado_por);
comment on table public.funcionario_cartoes is '[api:nenhum] Cartões/crachás de acesso. Nunca legíveis pela API.';

create table if not exists public.funcionario_fotos (
  funcionario_id  uuid primary key references public.funcionarios (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  bucket          text not null default 'funcionarios-fotos',
  caminho         text not null,
  atualizado_por  uuid references public.perfis (id) on delete set null,
  atualizado_em   timestamptz not null default now()
);
create index if not exists funcionario_fotos_empresa_idx on public.funcionario_fotos (empresa_id);
create index if not exists funcionario_fotos_atualizado_por_idx on public.funcionario_fotos (atualizado_por);
comment on table public.funcionario_fotos is '[api:leitura] Foto facial do funcionário (arquivo no Storage, bucket privado).';

create table if not exists public.controlid_horarios (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (empresa_id, nome)
);
comment on table public.controlid_horarios is '[api:crud] Horários de acesso (faixas semanais) dos equipamentos de acesso.';

create table if not exists public.controlid_horario_faixas (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas (id) on delete cascade,
  horario_id   uuid not null references public.controlid_horarios (id) on delete cascade,
  dia_semana   smallint not null check (dia_semana between 0 and 6),
  inicio       time not null,
  fim          time not null,
  constraint controlid_horario_faixas_ordem check (fim > inicio)
);
create index if not exists controlid_horario_faixas_empresa_idx on public.controlid_horario_faixas (empresa_id);
create index if not exists controlid_horario_faixas_horario_idx on public.controlid_horario_faixas (horario_id, dia_semana);
comment on table public.controlid_horario_faixas is '[api:crud] Faixas (dia da semana, início, fim) de um horário de acesso.';

create table if not exists public.funcionario_horarios (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  funcionario_id  uuid not null references public.funcionarios (id) on delete cascade,
  horario_id      uuid not null references public.controlid_horarios (id) on delete cascade,
  criado_em       timestamptz not null default now(),
  unique (funcionario_id, horario_id)
);
create index if not exists funcionario_horarios_empresa_idx on public.funcionario_horarios (empresa_id);
create index if not exists funcionario_horarios_horario_idx on public.funcionario_horarios (horario_id);
comment on table public.funcionario_horarios is '[api:crud] Horários de acesso de cada funcionário.';

create table if not exists public.controlid_envios (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas (id) on delete cascade,
  integracao_id      uuid not null references public.integracoes (id) on delete cascade,
  alvo               text not null check (alvo in ('funcionario', 'horarios')),
  funcionario_id     uuid references public.funcionarios (id) on delete set null,
  funcionario_nome   text,
  operacao           text not null check (operacao in ('salvar', 'remover', 'bloquear')),
  status             text not null default 'pendente'
                     check (status in ('pendente', 'enviando', 'enviado', 'erro', 'aguardando')),
  versao             int not null default 1,
  assinatura         text not null,
  assinatura_enviada text,
  id_remoto          text,
  mapa_remoto        jsonb not null default '{}'::jsonb,
  tentativas         int not null default 0,
  erro               text,
  pendente_desde     timestamptz,
  pego_em            timestamptz,
  enviado_em         timestamptz,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index if not exists controlid_envios_empresa_idx on public.controlid_envios (empresa_id, status);
create index if not exists controlid_envios_funcionario_idx on public.controlid_envios (funcionario_id);
create unique index if not exists controlid_envios_func_uk on public.controlid_envios (integracao_id, funcionario_id)
  where alvo = 'funcionario' and funcionario_id is not null;
create unique index if not exists controlid_envios_horarios_uk on public.controlid_envios (integracao_id)
  where alvo = 'horarios';
create index if not exists controlid_envios_fila_idx on public.controlid_envios (integracao_id, status);
comment on table public.controlid_envios is '[api:leitura] Estado do envio de cadastros/horários a cada equipamento Control iD.';

-- ================================================================================ gatilhos simples
create or replace function public.empresa_do_funcionario() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid;
begin
  select empresa_id into v from public.funcionarios where id = new.funcionario_id;
  if v is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  new.empresa_id := v;
  return new;
end $$;
comment on function public.empresa_do_funcionario() is '[interno] Gatilho: empresa_id = empresa do funcionário.';

drop trigger if exists funcionario_credenciais_empresa on public.funcionario_credenciais;
create trigger funcionario_credenciais_empresa before insert or update on public.funcionario_credenciais
  for each row execute function public.empresa_do_funcionario();
drop trigger if exists funcionario_cartoes_empresa on public.funcionario_cartoes;
create trigger funcionario_cartoes_empresa before insert or update on public.funcionario_cartoes
  for each row execute function public.empresa_do_funcionario();
drop trigger if exists funcionario_fotos_empresa on public.funcionario_fotos;
create trigger funcionario_fotos_empresa before insert or update on public.funcionario_fotos
  for each row execute function public.empresa_do_funcionario();

create or replace function public.funcionario_horarios_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v uuid;
begin
  select empresa_id into new.empresa_id from public.funcionarios where id = new.funcionario_id;
  if new.empresa_id is null then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  select empresa_id into v from public.controlid_horarios where id = new.horario_id;
  if v is distinct from new.empresa_id then
    raise exception 'Horário de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.funcionario_horarios_antes_gravar() is '[interno] Gatilho: horário e funcionário da mesma empresa.';
drop trigger if exists funcionario_horarios_antes_gravar on public.funcionario_horarios;
create trigger funcionario_horarios_antes_gravar before insert or update on public.funcionario_horarios
  for each row execute function public.funcionario_horarios_antes_gravar();

create or replace function public.controlid_horarios_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.controlid_horarios_antes_gravar() is '[interno] Gatilho: horário com empresa imutável.';
drop trigger if exists controlid_horarios_antes_gravar on public.controlid_horarios;
create trigger controlid_horarios_antes_gravar before insert or update on public.controlid_horarios
  for each row execute function public.controlid_horarios_antes_gravar();
drop trigger if exists controlid_horarios_tocar on public.controlid_horarios;
create trigger controlid_horarios_tocar before update on public.controlid_horarios
  for each row execute function public.tocar_atualizado_em();

create or replace function public.controlid_horario_faixas_antes_gravar() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  select empresa_id into new.empresa_id from public.controlid_horarios where id = new.horario_id;
  if new.empresa_id is null then
    raise exception 'Horário não encontrado' using errcode = 'P0002';
  end if;
  return new;
end $$;
comment on function public.controlid_horario_faixas_antes_gravar() is '[interno] Gatilho: empresa do horário.';
drop trigger if exists controlid_horario_faixas_antes_gravar on public.controlid_horario_faixas;
create trigger controlid_horario_faixas_antes_gravar before insert or update on public.controlid_horario_faixas
  for each row execute function public.controlid_horario_faixas_antes_gravar();

drop trigger if exists controlid_envios_tocar on public.controlid_envios;
create trigger controlid_envios_tocar before update on public.controlid_envios
  for each row execute function public.tocar_atualizado_em();

-- =========================================================================================== RLS
alter table public.funcionario_credenciais enable row level security;   -- sem políticas
alter table public.funcionario_cartoes enable row level security;       -- sem políticas
alter table public.funcionario_fotos enable row level security;
alter table public.controlid_horarios enable row level security;
alter table public.controlid_horario_faixas enable row level security;
alter table public.funcionario_horarios enable row level security;
alter table public.controlid_envios enable row level security;

drop policy if exists funcionario_fotos_ler on public.funcionario_fotos;
create policy funcionario_fotos_ler on public.funcionario_fotos for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));

drop policy if exists controlid_envios_ler on public.controlid_envios;
create policy controlid_envios_ler on public.controlid_envios for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

do $$
declare
  t text;
begin
  foreach t in array array['controlid_horarios', 'controlid_horario_faixas', 'funcionario_horarios'] loop
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

-- ============================================================================ Storage (fotos)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('funcionarios-fotos', 'funcionarios-fotos', false, 2097152, array['image/jpeg', 'image/png'])
    on conflict (id) do update
      set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists mdg_fotos_ler on storage.objects';
    execute $p$create policy mdg_fotos_ler on storage.objects for select to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_leitura())::text))$p$;
    execute 'drop policy if exists mdg_fotos_inserir on storage.objects';
    execute $p$create policy mdg_fotos_inserir on storage.objects for insert to authenticated
      with check (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_fotos_alterar on storage.objects';
    execute $p$create policy mdg_fotos_alterar on storage.objects for update to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))
      with check (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
    execute 'drop policy if exists mdg_fotos_excluir on storage.objects';
    execute $p$create policy mdg_fotos_excluir on storage.objects for delete to authenticated
      using (bucket_id = 'funcionarios-fotos'
             and ((select public.eh_master()) or (storage.foldername(name))[1] = (select public.empresa_operacao())::text))$p$;
  end if;
end $$;

-- ============================================================================ estado desejado
-- Configuração de envio efetiva de uma integração (com as regras fixas do REP).
create or replace function public.controlid_envio_config(p_integracao public.integracoes) returns jsonb
language sql stable
set search_path = public, extensions, pg_temp
as $$
  select case when p_integracao.tipo = 'controlid_rep'
              then e || '{"horarios": false, "foto": false, "ao_desligar": "remover"}'::jsonb
              else e end
    from (select public.integracao_envio_padrao(p_integracao.tipo, p_integracao.parametros ->> 'modelo')
                 || coalesce(p_integracao.parametros -> 'envio', '{}'::jsonb) as e) x
$$;
comment on function public.controlid_envio_config(public.integracoes) is '[interno] parametros.envio efetivo da integração.';

create or replace function public.controlid_envio_ligado(p_integracao public.integracoes) returns boolean
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select p_integracao.tipo in ('controlid_acesso', 'controlid_rep')
     and p_integracao.ativa
     and coalesce((public.controlid_envio_config(p_integracao) ->> 'ativo')::boolean, false)
     and exists (select 1 from public.empresas e where e.id = p_integracao.empresa_id and e.ativa)
$$;
comment on function public.controlid_envio_ligado(public.integracoes) is '[interno] Envio ligado para a integração?';

-- Grava/atualiza a linha de envio a partir do estado desejado (assinatura e motivo de espera).
create or replace function public.controlid_envio_gravar(
  p_integracao public.integracoes, p_alvo text, p_funcionario uuid, p_nome text, p_operacao text,
  p_assinatura text, p_motivo text, p_id_remoto text
) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v public.controlid_envios;
  v_status text;
begin
  if p_alvo = 'horarios' then
    select * into v from public.controlid_envios
     where integracao_id = p_integracao.id and alvo = 'horarios' for update;
  else
    select * into v from public.controlid_envios
     where integracao_id = p_integracao.id and alvo = 'funcionario' and funcionario_id = p_funcionario for update;
  end if;

  if v.id is null then
    insert into public.controlid_envios (empresa_id, integracao_id, alvo, funcionario_id, funcionario_nome, operacao, status,
                                         versao, assinatura, id_remoto, erro, pendente_desde)
    values (p_integracao.empresa_id, p_integracao.id, p_alvo, p_funcionario, p_nome, p_operacao,
            case when p_motivo is not null then 'aguardando' else 'pendente' end,
            1, p_assinatura, p_id_remoto, p_motivo, public.agora());
    return;
  end if;

  if p_assinatura is distinct from v.assinatura
     or (p_id_remoto is not null and p_id_remoto is distinct from v.id_remoto) then
    -- Mudou o desejado (ou o usuário do equipamento ligado ao funcionário): nova versão.
    v_status := case when p_motivo is not null then 'aguardando'
                     when p_assinatura = v.assinatura_enviada and p_id_remoto is not distinct from v.id_remoto
                          and v.status = 'enviado' then 'enviado'
                     when v.status = 'enviando' then 'enviando'
                     else 'pendente' end;
    update public.controlid_envios
       set versao = versao + 1, assinatura = p_assinatura, operacao = p_operacao,
           funcionario_nome = coalesce(p_nome, funcionario_nome),
           id_remoto = coalesce(p_id_remoto, id_remoto),
           status = v_status, erro = case when v_status = 'aguardando' then p_motivo else null end,
           tentativas = 0, pendente_desde = public.agora()
     where id = v.id;
  elsif p_motivo is not null and v.status in ('pendente', 'erro') then
    update public.controlid_envios set status = 'aguardando', erro = p_motivo where id = v.id;
  elsif p_motivo is null and v.status = 'aguardando' then
    update public.controlid_envios set status = 'pendente', erro = null, tentativas = 0, pendente_desde = public.agora()
     where id = v.id;
  elsif p_nome is not null and p_nome is distinct from v.funcionario_nome then
    update public.controlid_envios set funcionario_nome = p_nome where id = v.id;
  end if;
end $$;
comment on function public.controlid_envio_gravar(public.integracoes, text, uuid, text, text, text, text, text) is
  '[interno] Upsert do estado de envio com controle de versão.';

-- Horários ativos da empresa no formato do payload.
create or replace function public.controlid_horarios_json(p_empresa uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'horario_id', h.id, 'nome', h.nome,
           'faixas', (select coalesce(jsonb_agg(jsonb_build_object(
                        'dia_semana', f.dia_semana,
                        'inicio', to_char(f.inicio, 'HH24:MI:SS'), 'fim', to_char(f.fim, 'HH24:MI:SS'),
                        'inicio_segundos', extract(epoch from f.inicio)::int,
                        'fim_segundos', extract(epoch from f.fim)::int)
                      order by f.dia_semana, f.inicio, f.fim), '[]'::jsonb)
                        from public.controlid_horario_faixas f where f.horario_id = h.id))
         order by h.nome, h.id), '[]'::jsonb)
    from public.controlid_horarios h
   where h.empresa_id = p_empresa and h.ativo
$$;
comment on function public.controlid_horarios_json(uuid) is '[interno] Horários ativos da empresa (payload de envio).';

-- Regras de acesso (horários ativos do funcionário + ids remotos do equipamento).
create or replace function public.controlid_regras_funcionario(p_integracao uuid, p_funcionario uuid) returns jsonb
language sql stable security definer
set search_path = public, extensions, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'horario_id', h.id,
           'access_rule_id', (select (e.mapa_remoto -> h.id::text ->> 'access_rule_id')::bigint
                                from public.controlid_envios e
                               where e.integracao_id = p_integracao and e.alvo = 'horarios'))
         order by h.nome, h.id), '[]'::jsonb)
    from public.funcionario_horarios fh
    join public.controlid_horarios h on h.id = fh.horario_id and h.ativo
   where fh.funcionario_id = p_funcionario
$$;
comment on function public.controlid_regras_funcionario(uuid, uuid) is '[interno] Regras de acesso do funcionário no equipamento.';

-- Recalcula o estado desejado (adendo A.3). Filtros opcionais por funcionário e integração.
create or replace function public.controlid_envio_atualizar(
  p_empresa uuid, p_funcionario uuid default null, p_integracao uuid default null
) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  i public.integracoes;
  f public.funcionarios;
  v_cfg jsonb;
  v_acesso boolean;
  v_hoje date;
  v_horarios jsonb;
  v_envio_h public.controlid_envios;
  v_link text;
  v_existente public.controlid_envios;
  v_id_remoto text;
  v_no_vinculo boolean;
  v_operacao text;
  v_motivo text;
  v_estado jsonb;
  v_cred public.funcionario_credenciais;
  v_tem_horario boolean;
  v_n int := 0;
begin
  if p_empresa is null then
    return 0;
  end if;
  v_hoje := public.dia_de_trabalho(public.agora(), p_empresa);

  for i in
    select * from public.integracoes
     where empresa_id = p_empresa and tipo in ('controlid_acesso', 'controlid_rep')
       and (p_integracao is null or id = p_integracao)
     order by id
  loop
    continue when not public.controlid_envio_ligado(i);
    v_cfg := public.controlid_envio_config(i);
    v_acesso := i.tipo = 'controlid_acesso';

    -- --------------------------------------------------------------------- horários
    if p_funcionario is null and v_acesso and (v_cfg ->> 'horarios')::boolean then
      v_horarios := public.controlid_horarios_json(p_empresa);
      select * into v_envio_h from public.controlid_envios where integracao_id = i.id and alvo = 'horarios';
      if jsonb_array_length(v_horarios) > 0 or coalesce(v_envio_h.mapa_remoto, '{}'::jsonb) <> '{}'::jsonb then
        perform public.controlid_envio_gravar(i, 'horarios', null, null, 'salvar',
                                              md5(jsonb_build_object('horarios', v_horarios)::text), null, null);
      elsif v_envio_h.id is not null and v_envio_h.status <> 'enviando' then
        delete from public.controlid_envios where id = v_envio_h.id;
      end if;
    end if;
    select * into v_envio_h from public.controlid_envios where integracao_id = i.id and alvo = 'horarios';

    -- ------------------------------------------------------------------ funcionários
    for f in
      select * from public.funcionarios
       where empresa_id = p_empresa and (p_funcionario is null or id = p_funcionario)
       order by id
    loop
      v_link := null;
      select c.user_id_externo into v_link from public.controlid_usuarios c
       where c.integracao_id = i.id and c.funcionario_id = f.id and not c.removido_no_equipamento;
      select * into v_existente from public.controlid_envios
       where integracao_id = i.id and alvo = 'funcionario' and funcionario_id = f.id;
      v_id_remoto := coalesce(v_link, v_existente.id_remoto);
      v_no_vinculo := f.ativo and (f.data_admissao is null or f.data_admissao <= v_hoje)
                      and (f.data_desligamento is null or f.data_desligamento >= v_hoje);
      v_motivo := null;

      if v_no_vinculo then
        v_operacao := 'salvar';
      elsif v_id_remoto is not null then
        v_operacao := case when v_acesso and v_cfg ->> 'ao_desligar' = 'bloquear' then 'bloquear' else 'remover' end;
      else
        -- fora do vínculo e nada no equipamento: nada a fazer
        if v_existente.id is not null and v_existente.operacao = 'salvar' and v_existente.status <> 'enviando' then
          delete from public.controlid_envios where id = v_existente.id;
        end if;
        continue;
      end if;

      if v_operacao = 'salvar' then
        select * into v_cred from public.funcionario_credenciais where funcionario_id = f.id;
        v_tem_horario := exists (select 1 from public.funcionario_horarios fh
                                   join public.controlid_horarios h on h.id = fh.horario_id and h.ativo
                                  where fh.funcionario_id = f.id);
        v_estado := jsonb_build_object(
          'operacao', 'salvar',
          'usuario', jsonb_build_object('nome', f.nome, 'matricula', f.matricula, 'cpf', f.cpf, 'pis', f.pis),
          'senha', case when (v_cfg ->> 'senha')::boolean
                        then to_jsonb(case when v_cred.senha is not null then v_cred.versao else 0 end) end,
          'cartoes', case when (v_cfg ->> 'cartao')::boolean
                          then (select coalesce(jsonb_agg(c.id order by c.criado_em, c.id), '[]'::jsonb)
                                  from public.funcionario_cartoes c where c.funcionario_id = f.id) end,
          'foto', case when v_acesso and (v_cfg ->> 'foto')::boolean
                       then (select jsonb_build_object('caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
                               from public.funcionario_fotos ft where ft.funcionario_id = f.id) end,
          'regras', case when v_acesso and (v_cfg ->> 'horarios')::boolean
                         then public.controlid_regras_funcionario(i.id, f.id) end);
        if not v_acesso then
          if coalesce(i.parametros ->> 'identificador', 'cpf') = 'pis' and f.pis is null then
            v_motivo := 'PIS obrigatório no REP';
          elsif coalesce(i.parametros ->> 'identificador', 'cpf') <> 'pis' and f.cpf is null then
            v_motivo := 'CPF obrigatório no REP';
          end if;
        elsif (v_cfg ->> 'horarios')::boolean and v_tem_horario
              and coalesce(v_envio_h.status, '') <> 'enviado' then
          v_motivo := 'Aguardando envio dos horários';
        end if;
      else
        v_estado := jsonb_build_object('operacao', v_operacao, 'id_remoto', v_id_remoto);
      end if;

      perform public.controlid_envio_gravar(i, 'funcionario', f.id, f.nome, v_operacao, md5(v_estado::text),
                                            v_motivo, v_link);
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_n;
end $$;
comment on function public.controlid_envio_atualizar(uuid, uuid, uuid) is
  '[interno] Recalcula o estado desejado de envio ao Control iD (empresa, funcionário e/ou integração).';

-- ================================================================== gatilhos que disparam o recálculo
create or replace function public.controlid_envio_gatilho_funcionario() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.controlid_envio_atualizar(old.empresa_id, old.funcionario_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.controlid_envio_atualizar(new.empresa_id, new.funcionario_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_funcionario() is
  '[interno] Gatilho: dado do funcionário mudou → recalcula o envio dele.';

do $$
declare
  t text;
begin
  foreach t in array array['funcionario_credenciais', 'funcionario_cartoes', 'funcionario_fotos', 'funcionario_horarios'] loop
    execute format('drop trigger if exists controlid_envio on public.%I', t);
    execute format('create trigger controlid_envio after insert or update or delete on public.%I
                    for each row execute function public.controlid_envio_gatilho_funcionario()', t);
  end loop;
end $$;

create or replace function public.controlid_envio_gatilho_cadastro() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'INSERT' or (old.nome, old.matricula, old.cpf, old.pis, old.ativo, old.data_admissao, old.data_desligamento)
                         is distinct from
                         (new.nome, new.matricula, new.cpf, new.pis, new.ativo, new.data_admissao, new.data_desligamento) then
    perform public.controlid_envio_atualizar(new.empresa_id, new.id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_cadastro() is '[interno] Gatilho: cadastro do funcionário mudou.';
drop trigger if exists controlid_envio on public.funcionarios;
create trigger controlid_envio after insert or update on public.funcionarios
  for each row execute function public.controlid_envio_gatilho_cadastro();

-- Exclusão do funcionário: o que está no equipamento vira "remover" sem funcionário.
create or replace function public.controlid_envio_gatilho_exclusao() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  update public.controlid_envios e
     set operacao = 'remover', status = 'pendente', versao = e.versao + 1, tentativas = 0, erro = null,
         assinatura = md5('remover:' || e.id::text || ':' || clock_timestamp()::text),
         funcionario_nome = old.nome, pendente_desde = public.agora(),
         id_remoto = coalesce((select c.user_id_externo from public.controlid_usuarios c
                                where c.integracao_id = e.integracao_id and c.funcionario_id = old.id
                                  and not c.removido_no_equipamento limit 1), e.id_remoto)
   where e.alvo = 'funcionario' and e.funcionario_id = old.id
     and (e.id_remoto is not null
          or exists (select 1 from public.controlid_usuarios c
                      where c.integracao_id = e.integracao_id and c.funcionario_id = old.id and not c.removido_no_equipamento));
  delete from public.controlid_envios e
   where e.alvo = 'funcionario' and e.funcionario_id = old.id and e.operacao = 'salvar';
  -- equipamento com usuário ligado mas sem linha de envio (importado): também remover, se o envio está ligado
  insert into public.controlid_envios (empresa_id, integracao_id, alvo, funcionario_id, funcionario_nome, operacao, status,
                                       assinatura, id_remoto, pendente_desde)
  select i.empresa_id, i.id, 'funcionario', old.id, old.nome, 'remover', 'pendente',
         md5('remover:' || c.id::text), c.user_id_externo, public.agora()
    from public.controlid_usuarios c
    join public.integracoes i on i.id = c.integracao_id
   where c.funcionario_id = old.id and not c.removido_no_equipamento
     and public.controlid_envio_ligado(i)
     and not exists (select 1 from public.controlid_envios e where e.integracao_id = i.id and e.funcionario_id = old.id);
  return old;
end $$;
comment on function public.controlid_envio_gatilho_exclusao() is '[interno] Gatilho: funcionário excluído → remover no equipamento.';
drop trigger if exists controlid_envio_exclusao on public.funcionarios;
create trigger controlid_envio_exclusao before delete on public.funcionarios
  for each row execute function public.controlid_envio_gatilho_exclusao();

create or replace function public.controlid_envio_gatilho_empresa() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.controlid_envio_atualizar(old.empresa_id);
  else
    perform public.controlid_envio_atualizar(new.empresa_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_empresa() is '[interno] Gatilho: horários mudaram → recalcula a empresa.';
drop trigger if exists controlid_envio on public.controlid_horarios;
create trigger controlid_envio after insert or update or delete on public.controlid_horarios
  for each row execute function public.controlid_envio_gatilho_empresa();
drop trigger if exists controlid_envio on public.controlid_horario_faixas;
create trigger controlid_envio after insert or update or delete on public.controlid_horario_faixas
  for each row execute function public.controlid_envio_gatilho_empresa();

create or replace function public.controlid_envio_gatilho_integracao() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'INSERT' or old.parametros is distinct from new.parametros or old.ativa is distinct from new.ativa then
    perform public.controlid_envio_atualizar(new.empresa_id, null, new.id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_integracao() is '[interno] Gatilho: parâmetros/situação da integração mudaram.';
drop trigger if exists controlid_envio on public.integracoes;
create trigger controlid_envio after insert or update on public.integracoes
  for each row execute function public.controlid_envio_gatilho_integracao();

create or replace function public.controlid_envio_gatilho_usuarios() returns trigger
language plpgsql security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if tg_op = 'UPDATE' and old.funcionario_id is not null and old.funcionario_id is distinct from new.funcionario_id then
    perform public.controlid_envio_atualizar(old.empresa_id, old.funcionario_id, old.integracao_id);
  end if;
  if new.funcionario_id is not null and (tg_op = 'INSERT' or old.funcionario_id is distinct from new.funcionario_id
                                         or old.removido_no_equipamento is distinct from new.removido_no_equipamento) then
    perform public.controlid_envio_atualizar(new.empresa_id, new.funcionario_id, new.integracao_id);
  end if;
  return null;
end $$;
comment on function public.controlid_envio_gatilho_usuarios() is '[interno] Gatilho: vínculo com o equipamento mudou.';
drop trigger if exists controlid_envio on public.controlid_usuarios;
create trigger controlid_envio after insert or update on public.controlid_usuarios
  for each row execute function public.controlid_envio_gatilho_usuarios();

-- ==================================================================================== RPCs do front
create or replace function public.funcionario_para_operar(p_funcionario uuid) returns public.funcionarios
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios;
begin
  select * into f from public.funcionarios where id = p_funcionario;
  if not found then
    raise exception 'Funcionário não encontrado' using errcode = 'P0002';
  end if;
  if public.pode_operar(f.empresa_id) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  return f;
end $$;
comment on function public.funcionario_para_operar(uuid) is '[interno] Funcionário existente e operável (G A M).';

create or replace function public.funcionario_definir_senha(p_funcionario uuid, p_senha text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := nullif(btrim(coalesce(p_senha, '')), '');
begin
  if v is not null and v !~ '^[0-9]{4,8}$' then
    raise exception 'Senha de acesso inválida' using errcode = '22023';
  end if;
  insert into public.funcionario_credenciais (funcionario_id, empresa_id, senha, versao, atualizado_em)
  values (f.id, f.empresa_id, v, 1, now())
  on conflict (funcionario_id) do update
    set senha = excluded.senha,
        versao = funcionario_credenciais.versao + 1,
        atualizado_em = now()
  where funcionario_credenciais.senha is distinct from excluded.senha;
end $$;
comment on function public.funcionario_definir_senha(uuid, text) is
  '[api] Define (4 a 8 dígitos) ou remove (null/vazio) a senha de acesso do funcionário (G A M).';

create or replace function public.funcionario_adicionar_cartao(p_funcionario uuid, p_numero text) returns uuid
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := regexp_replace(coalesce(p_numero, ''), '[^0-9]', '', 'g');
  v_id uuid;
begin
  v := nullif(ltrim(v, '0'), '');
  v := coalesce(v, case when regexp_replace(coalesce(p_numero, ''), '[^0-9]', '', 'g') <> '' then '0' end);
  if v is null or length(v) > 20 then
    raise exception 'Número de cartão inválido' using errcode = '22023';
  end if;
  if exists (select 1 from public.funcionario_cartoes where empresa_id = f.empresa_id and numero = v) then
    raise exception 'Cartão já cadastrado' using errcode = '23505';
  end if;
  insert into public.funcionario_cartoes (empresa_id, funcionario_id, numero, criado_por)
  values (f.empresa_id, f.id, v, public.meu_perfil_id())
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'Cartão já cadastrado' using errcode = '23505';
end $$;
comment on function public.funcionario_adicionar_cartao(uuid, text) is '[api] Adiciona cartão/crachá ao funcionário (G A M).';

create or replace function public.funcionario_remover_cartao(p_cartao uuid) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
begin
  select empresa_id into v_empresa from public.funcionario_cartoes where id = p_cartao;
  if v_empresa is null then
    raise exception 'Cartão não encontrado' using errcode = 'P0002';
  end if;
  if public.pode_operar(v_empresa) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  delete from public.funcionario_cartoes where id = p_cartao;
end $$;
comment on function public.funcionario_remover_cartao(uuid) is '[api] Remove um cartão (G A M).';

create or replace function public.funcionario_definir_foto(p_funcionario uuid, p_caminho text) returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
  v text := nullif(btrim(coalesce(p_caminho, '')), '');
  v_existe boolean := true;
begin
  if v is null then
    delete from public.funcionario_fotos where funcionario_id = f.id;
    return;
  end if;
  if position(f.empresa_id::text || '/' || f.id::text || '/' in v) <> 1
     or v !~* ('^' || f.empresa_id::text || '/' || f.id::text || '/[^/]+\.(jpg|jpeg|png)$') then
    raise exception 'Foto inválida' using errcode = '22023';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)'
      into v_existe using 'funcionarios-fotos', v;
  end if;
  if not v_existe then
    raise exception 'Foto não encontrada' using errcode = 'P0002';
  end if;
  insert into public.funcionario_fotos (funcionario_id, empresa_id, bucket, caminho, atualizado_por, atualizado_em)
  values (f.id, f.empresa_id, 'funcionarios-fotos', v, public.meu_perfil_id(), public.agora())
  on conflict (funcionario_id) do update
    set caminho = excluded.caminho, atualizado_por = excluded.atualizado_por, atualizado_em = excluded.atualizado_em;
end $$;
comment on function public.funcionario_definir_foto(uuid, text) is
  '[api] Registra (ou remove, null) a foto facial já enviada ao Storage (G A M).';

create or replace function public.funcionario_credenciais(p_funcionario uuid) returns jsonb
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f public.funcionarios := public.funcionario_para_operar(p_funcionario);
begin
  return jsonb_build_object(
    'senha_definida', exists (select 1 from public.funcionario_credenciais c where c.funcionario_id = f.id and c.senha is not null),
    'cartoes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'final', right(c.numero, 4), 'criado_em', c.criado_em)
                                          order by c.criado_em, c.id), '[]'::jsonb)
                  from public.funcionario_cartoes c where c.funcionario_id = f.id),
    'foto', (select jsonb_build_object('caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
               from public.funcionario_fotos ft where ft.funcionario_id = f.id));
end $$;
comment on function public.funcionario_credenciais(uuid) is
  '[api] Resumo das credenciais (sem a senha nem o número completo dos cartões) (G A M).';

create or replace function public.controlid_envio_reenviar(
  p_integracao uuid default null, p_funcionario uuid default null, p_empresa uuid default null
) returns integer
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa uuid;
  v_n int;
begin
  if p_integracao is not null then
    select empresa_id into v_empresa from public.integracoes where id = p_integracao;
    if v_empresa is null then
      raise exception 'Integração não encontrada' using errcode = 'P0002';
    end if;
  elsif p_funcionario is not null then
    select empresa_id into v_empresa from public.funcionarios where id = p_funcionario;
    if v_empresa is null then
      raise exception 'Funcionário não encontrado' using errcode = 'P0002';
    end if;
  else
    v_empresa := public.resolver_empresa(p_empresa, 'operar');
  end if;
  if public.pode_operar(v_empresa) is not true then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  perform public.controlid_envio_atualizar(v_empresa, p_funcionario, p_integracao);
  update public.controlid_envios
     set status = 'pendente', tentativas = 0, erro = null, pendente_desde = public.agora()
   where empresa_id = v_empresa
     and (p_integracao is null or integracao_id = p_integracao)
     and (p_funcionario is null or funcionario_id = p_funcionario)
     and (status = 'erro' or (p_funcionario is not null and status = 'enviado'));
  get diagnostics v_n = row_count;
  return v_n;
end $$;
comment on function public.controlid_envio_reenviar(uuid, uuid, uuid) is
  '[api] Volta a pendente os envios com erro (e os já enviados, se informar o funcionário) (G A M).';

-- ================================================================================ RPCs do N8N
create or replace function public.controlid_envio_payload(p_envio public.controlid_envios, p_integracao public.integracoes)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_cfg jsonb := public.controlid_envio_config(p_integracao);
  v_acesso boolean := p_integracao.tipo = 'controlid_acesso';
  f public.funcionarios;
begin
  if p_envio.alvo = 'horarios' then
    return jsonb_build_object('envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'horarios', 'operacao', 'salvar',
                              'mapa_anterior', p_envio.mapa_remoto,
                              'horarios', public.controlid_horarios_json(p_envio.empresa_id));
  end if;
  select * into f from public.funcionarios where id = p_envio.funcionario_id;
  if p_envio.operacao <> 'salvar' or f.id is null then
    return jsonb_build_object(
      'envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'funcionario', 'operacao', p_envio.operacao,
      'funcionario_id', f.id, 'id_remoto', p_envio.id_remoto,
      'usuario', jsonb_build_object('nome', coalesce(f.nome, p_envio.funcionario_nome), 'matricula', f.matricula,
                                    'cpf', f.cpf, 'pis', f.pis),
      'senha', null, 'cartoes', '[]'::jsonb, 'foto', null, 'regras_acesso', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'envio_id', p_envio.id, 'versao', p_envio.versao, 'alvo', 'funcionario', 'operacao', 'salvar',
    'funcionario_id', f.id, 'id_remoto', p_envio.id_remoto,
    'usuario', jsonb_build_object('nome', f.nome, 'matricula', f.matricula, 'cpf', f.cpf, 'pis', f.pis),
    'senha', case when (v_cfg ->> 'senha')::boolean
                  then (select to_jsonb(c.senha) from public.funcionario_credenciais c where c.funcionario_id = f.id) end,
    'cartoes', case when (v_cfg ->> 'cartao')::boolean
                    then (select coalesce(jsonb_agg(c.numero order by c.criado_em, c.id), '[]'::jsonb)
                            from public.funcionario_cartoes c where c.funcionario_id = f.id) end,
    'foto', case when v_acesso and (v_cfg ->> 'foto')::boolean
                 then (select jsonb_build_object('bucket', ft.bucket, 'caminho', ft.caminho, 'atualizado_em', ft.atualizado_em)
                         from public.funcionario_fotos ft where ft.funcionario_id = f.id) end,
    'regras_acesso', case when v_acesso and (v_cfg ->> 'horarios')::boolean
                          then public.controlid_regras_funcionario(p_integracao.id, f.id) end);
end $$;
comment on function public.controlid_envio_payload(public.controlid_envios, public.integracoes) is
  '[interno] Payload completo (com segredos) de um item de envio.';

create or replace function public.ingestao_controlid_envios_pendentes(p_integracao uuid, p_limite int default 50) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  i public.integracoes := public.integracao_validar(p_integracao, array['controlid_acesso', 'controlid_rep']);
  v_cfg jsonb := public.controlid_envio_config(i);
  v_itens jsonb := '[]'::jsonb;
  e public.controlid_envios;
begin
  if public.controlid_envio_ligado(i) then
    perform public.controlid_envio_atualizar(i.empresa_id, null, i.id);
    update public.controlid_envios
       set status = 'pendente'
     where integracao_id = i.id and status = 'enviando' and pego_em < public.agora() - interval '30 minutes';
    for e in
      with alvo as (
        select id from public.controlid_envios
         where integracao_id = i.id
           and (status = 'pendente' or (status = 'erro' and tentativas < 5))
         order by (alvo = 'horarios') desc, (operacao <> 'salvar') desc, pendente_desde, id
         limit greatest(coalesce(p_limite, 50), 1)
         for update skip locked
      )
      update public.controlid_envios c
         set status = 'enviando', pego_em = public.agora(), tentativas = c.tentativas + 1
        from alvo where c.id = alvo.id
      returning c.*
    loop
      v_itens := v_itens || public.controlid_envio_payload(e, i);
    end loop;
    select coalesce(jsonb_agg(x order by (x ->> 'alvo' = 'horarios') desc, (x ->> 'operacao' <> 'salvar') desc), '[]'::jsonb)
      into v_itens from jsonb_array_elements(v_itens) x;
  end if;
  return jsonb_build_object(
    'integracao_id', i.id, 'tipo', i.tipo, 'modelo', i.parametros ->> 'modelo', 'envio', v_cfg,
    'identificador', case when i.tipo = 'controlid_rep' then coalesce(i.parametros ->> 'identificador', 'cpf') end,
    'itens', v_itens);
end $$;
comment on function public.ingestao_controlid_envios_pendentes(uuid, int) is
  '[servico] Recalcula e pega as pendências de envio do equipamento, com payload pronto (adendo A.5).';

create or replace function public.ingestao_controlid_envio_resultado(
  p_envio uuid, p_versao int, p_status text, p_id_remoto text default null, p_erro text default null,
  p_mapa_remoto jsonb default null
) returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  e public.controlid_envios;
  f public.funcionarios;
  v_id_remoto text;
  v_status text;
begin
  if p_status is null or p_status not in ('enviado', 'erro') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  select * into e from public.controlid_envios where id = p_envio for update;
  if not found then
    raise exception 'Envio não encontrado' using errcode = 'P0002';
  end if;

  if p_status = 'erro' then
    update public.controlid_envios
       set status = 'erro', erro = coalesce(nullif(btrim(p_erro), ''), 'Erro sem mensagem')
     where id = e.id;
    return jsonb_build_object('status', 'erro', 'versao', e.versao);
  end if;

  v_id_remoto := case when e.operacao = 'remover' then null
                      else coalesce(nullif(btrim(p_id_remoto), ''), e.id_remoto) end;
  v_status := case when p_versao = e.versao then 'enviado' else 'pendente' end;

  if e.alvo = 'funcionario' and e.operacao = 'remover' and e.funcionario_id is null and v_status = 'enviado' then
    update public.controlid_usuarios set removido_no_equipamento = true
     where integracao_id = e.integracao_id and user_id_externo = e.id_remoto;
    delete from public.controlid_envios where id = e.id;
    return jsonb_build_object('status', 'enviado', 'versao', e.versao);
  end if;

  update public.controlid_envios
     set status = v_status, id_remoto = v_id_remoto, enviado_em = public.agora(), erro = null,
         assinatura_enviada = case when v_status = 'enviado' then assinatura else assinatura_enviada end,
         mapa_remoto = case when alvo = 'horarios' and p_mapa_remoto is not null
                                 and jsonb_typeof(p_mapa_remoto) = 'object' then p_mapa_remoto else mapa_remoto end
   where id = e.id;

  if e.alvo = 'funcionario' and e.funcionario_id is not null then
    select * into f from public.funcionarios where id = e.funcionario_id;
    if e.operacao = 'remover' and e.id_remoto is not null then
      update public.controlid_usuarios set removido_no_equipamento = true
       where integracao_id = e.integracao_id and user_id_externo = e.id_remoto;
    elsif e.operacao = 'salvar' and v_id_remoto is not null then
      -- O usuário criado/atualizado no equipamento fica ligado ao funcionário (sem desfazer vínculo manual).
      if not exists (select 1 from public.controlid_usuarios
                      where integracao_id = e.integracao_id and user_id_externo = v_id_remoto
                        and (funcionario_id is distinct from f.id) and (funcionario_id is not null or vinculo = 'manual')) then
        update public.controlid_usuarios set funcionario_id = null, vinculo = null
         where integracao_id = e.integracao_id and funcionario_id = f.id and user_id_externo <> v_id_remoto
           and coalesce(vinculo, '') <> 'manual';
        if not exists (select 1 from public.controlid_usuarios
                        where integracao_id = e.integracao_id and funcionario_id = f.id and user_id_externo <> v_id_remoto) then
          insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, registration, nome, cpf, pis,
                                                 funcionario_id, vinculo, removido_no_equipamento, visto_em)
          values (e.empresa_id, e.integracao_id, v_id_remoto, f.matricula, f.nome, f.cpf, f.pis, f.id, 'automatico', false,
                  public.agora())
          on conflict (integracao_id, user_id_externo) do update
            set funcionario_id = excluded.funcionario_id,
                vinculo = coalesce(controlid_usuarios.vinculo, 'automatico'),
                removido_no_equipamento = false, registration = excluded.registration, nome = excluded.nome,
                cpf = excluded.cpf, pis = excluded.pis;
        end if;
      end if;
    end if;
  end if;

  if e.alvo = 'horarios' then
    perform public.controlid_envio_atualizar(e.empresa_id, null, e.integracao_id);
    -- (revisão 2) Os funcionários que aguardavam os horários viram 'pendente' só agora, depois que o N8N já leu as
    -- pendências desta rodada: sem um novo pedido, ficavam esperando o agendador (até 1 h). Enfileira um envio.
    if v_status = 'enviado'
       and exists (select 1 from public.controlid_envios
                    where integracao_id = e.integracao_id and alvo = 'funcionario' and status = 'pendente')
       and not exists (select 1 from public.sync_solicitacoes
                        where integracao_id = e.integracao_id and status = 'pendente'
                          and escopo in ('exportar_funcionarios', 'tudo')) then
      insert into public.sync_solicitacoes (empresa_id, integracao_id, escopo, mensagem)
      values (e.empresa_id, e.integracao_id, 'exportar_funcionarios', 'Automático: envio dos funcionários após os horários');
    end if;
  end if;
  return jsonb_build_object('status', v_status, 'versao', e.versao);
end $$;
comment on function public.ingestao_controlid_envio_resultado(uuid, int, text, text, text, jsonb) is
  '[servico] Registra o resultado de um item de envio ao Control iD (adendo A.5).';
