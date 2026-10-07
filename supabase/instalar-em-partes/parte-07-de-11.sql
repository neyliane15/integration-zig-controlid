-- Meu Dia de Gerente — instalação do banco, PARTE 07 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000200_ponto.sql. Não edite à mão.

begin;
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

  -- Quais slots foram batidos (0 < n < k): menor Σ|batida − slot|; empate → combinação lexicograficamente menor (§7.3).
  -- Calculado também no dia em andamento, para o atraso abaixo.
  v_melhor := null;
  if v_n > 0 and v_n < v_k then
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
  end if;

  -- 6. Atraso: só se a 1ª batida corresponde à entrada (se a entrada faltou, o alarme é "batida faltando", não atraso).
  if v_k > 0 and v_n > 0 and (v_melhor is null or 1 = any (v_melhor)) then
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
        -- slots não batidos (v_melhor calculado acima): um alarme por batida faltante
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

commit;
select 'parte 07 de 11 instalada' as resultado;
