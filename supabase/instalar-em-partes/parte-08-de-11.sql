-- Meu Dia de Gerente — instalação do banco, PARTE 08 DE 11.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000200_ponto.sql, 20261006000210_zig.sql. Não edite à mão.

begin;
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

-- Revisão 1: passou a devolver `esperadas` (antes o front recalculava a partir da jornada e errava em dia abonado).
-- Mudança de tipo de retorno exige drop (idempotente; os privilégios voltam na …0900_permissoes.sql).
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'ponto_dia_empresa'
                and pg_get_function_result(p.oid) not like '%esperadas jsonb%') then
    drop function public.ponto_dia_empresa(date, uuid);
  end if;
end $$;
create or replace function public.ponto_dia_empresa(p_data date default null, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, situacao text, encerrado boolean,
               previsto_minutos int, trabalhado_minutos int, saldo_minutos int, atraso_minutos int,
               batidas jsonb, alarmes_abertos int, esperadas jsonb)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_data date;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.dia_de_trabalho(public.agora(), v_empresa));
  return query
  select f.id, f.nome, f.cargo, c.situacao, c.encerrado, c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos,
         c.atraso_minutos, c.batidas,
         (select count(*)::int from public.ponto_alarmes a
           where a.funcionario_id = f.id and a.data = v_data and a.status = 'aberto'),
         c.esperadas
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
  -- (revisão 2) batida de anos atrás (digitação errada, ex.: 1926) era aceita e gravada fora de qualquer apuração
  if p_instante < public.agora() - interval '366 days' then
    raise exception 'Horário muito antigo (máximo 1 ano)' using errcode = '22023';
  end if;

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

commit;
select 'parte 08 de 11 instalada' as resultado;
