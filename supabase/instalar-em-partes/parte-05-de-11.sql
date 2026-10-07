-- Meu Dia de Gerente — instalação do banco, PARTE 05 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000140_envio_controlid.sql. Não edite à mão.

begin;
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

commit;
select 'parte 05 de 11 instalada' as resultado;
