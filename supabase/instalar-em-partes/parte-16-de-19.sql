-- Meu Dia de Gerente — instalação do banco, PARTE 16 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000280_escala.sql, 20261006000290_comissao_presenca.sql. Não edite à mão.

begin;
create or replace function public.escala_definir_membros(p_setor uuid, p_membros jsonb)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_afetados uuid[]; v_lista uuid[]; x jsonb; i int := 0;
  v_func uuid; v_folgas smallint[]; v_cheg time; v_cam smallint; v_pos smallint;
begin
  s := public.escala_setor_para_operar(p_setor);
  if p_membros is null or jsonb_typeof(p_membros) <> 'array' then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg((e ->> 'funcionario_id')::uuid), '{}') into v_lista from jsonb_array_elements(p_membros) e;
  exception when others then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end;
  if exists (select 1 from unnest(v_lista) u where u is null) then
    raise exception 'Lista de membros inválida' using errcode = '22023';
  end if;
  if (select count(distinct u) from unnest(v_lista) u) <> coalesce(array_length(v_lista, 1), 0) then
    raise exception 'Funcionário repetido na lista' using errcode = '22023';
  end if;
  v_afetados := public.escala_funcionarios_dos_setores(array[p_setor])
             || public.escala_funcionarios_dos_setores(
                  (select coalesce(array_agg(distinct m.setor_id), '{}') from public.escala_membros m where m.funcionario_id = any (v_lista)))
             || v_lista;
  delete from public.escala_membros where setor_id = p_setor and not (funcionario_id = any (v_lista));
  update public.escala_membros set caminho = null, posicao = null where setor_id = p_setor;
  for x in select * from jsonb_array_elements(p_membros) loop
    i := i + 1;
    begin
      v_func := (x ->> 'funcionario_id')::uuid;
      v_folgas := case when jsonb_typeof(x -> 'folgas_base') = 'array'
                       then array(select jsonb_array_elements_text(x -> 'folgas_base')::smallint) else '{}'::smallint[] end;
      v_cheg := nullif(x ->> 'chegada_padrao', '')::time;
      v_cam := (x ->> 'caminho')::smallint;
      v_pos := (x ->> 'posicao')::smallint;
    exception when others then
      raise exception 'Lista de membros inválida' using errcode = '22023';
    end;
    perform public.escala_gravar_membro(p_setor, v_func, v_folgas, v_cheg, v_cam, v_pos, i);
  end loop;
  perform public.escala_reapurar(s.empresa_id, v_afetados, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return i;
end $$;
comment on function public.escala_definir_membros(uuid, jsonb) is '[api] Substitui a lista de membros do setor (ordem e caminhos) e reapura.';

create or replace function public.escala_remover_membro(p_funcionario uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_func uuid[];
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_func := public.escala_funcionarios_dos_setores(array[m.setor_id]);
  delete from public.escala_membros where id = m.id;
  perform public.escala_reapurar(m.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = m.empresa_id));
end $$;
comment on function public.escala_remover_membro(uuid) is '[api] Tira o funcionário da escala (apaga seus ajustes) e reapura.';

create or replace function public.escala_adicionar_funcionario(p_setor uuid, p_nome text, p_cargo text default null,
                                                               p_folgas_base smallint[] default '{}', p_chegada_padrao time default null,
                                                               p_caminho smallint default null, p_posicao smallint default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_nome text; v_func uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao)
  values (s.empresa_id, v_nome, nullif(btrim(coalesce(p_cargo, '')), ''), 0)
  returning id into v_func;
  perform public.escala_gravar_membro(p_setor, v_func, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, null);
  perform public.escala_reapurar(s.empresa_id, public.escala_funcionarios_dos_setores(array[p_setor]),
                                 (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_func;
end $$;
comment on function public.escala_adicionar_funcionario(uuid, text, text, smallint[], time, smallint, smallint) is
  '[api] Cadastra um funcionário e o põe num setor da escala; retorna o id do funcionário.';

-- Modelo do cliente (docs/referencias/escala-macaw-v3.html), §S.7.8.
create or replace function public.escala_aplicar_modelo_macaw(p_empresa uuid default null, p_ancora date default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; v_cfg public.escala_config; r record; v_setor uuid; v_func uuid; v_membro uuid;
  v_setores int := 0; v_membros int := 0; v_criados int := 0; v_pos smallint; v_chave text; v_setores_ids uuid[] := '{}';
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is not null then
    perform public.escala_configurar(p_ancora, coalesce((select c.fase from public.escala_config c where c.empresa_id = v_empresa), 0),
                                     v_empresa);
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);

  for r in
    select * from (values
      ('Salão', 1, 1, 'Garçom 1', 'Garçom', '{2,3}', 1, 1), ('Salão', 1, 2, 'Garçom 2', 'Garçom', '{2,3}', 1, 2),
      ('Salão', 1, 3, 'Garçom 3', 'Garçom', '{2,3}', 1, 3), ('Salão', 1, 4, 'Cumim 2', 'Cumim', '{2,6}', 1, 4),
      ('Salão', 1, 5, 'Garçom 4', 'Garçom', '{0,1}', 2, 1), ('Salão', 1, 6, 'Garçom 5', 'Garçom', '{0,1}', 2, 2),
      ('Salão', 1, 7, 'Garçom 6', 'Garçom', '{0,1}', 2, 3), ('Salão', 1, 8, 'Cumim 1', 'Cumim', '{1,6}', 2, 4),
      ('Maître', 2, 1, 'Maître 1', 'Maître', '{0,1}', 1, 2), ('Maître', 2, 2, 'Maître 2', 'Maître', '{1,3}', 1, 1),
      ('Maître', 2, 3, 'Maître 3', 'Maître', '{2,3}', 1, 4), ('Maître', 2, 4, 'Gerente', 'Gerente', '{2}', null, null),
      ('Maître', 2, 5, 'Recepção', 'Recepção', '{0,6}', 1, 3),
      ('Areia', 3, 1, 'Areia 1', 'Areia', '{0,6}', 1, 2), ('Areia', 3, 2, 'Areia 2', 'Areia', '{0,1}', 1, 1),
      ('Areia', 3, 3, 'Areia 3', 'Areia', '{2,3}', 1, 3), ('Areia', 3, 4, 'Areia 4', 'Areia', '{2,3}', 1, 4),
      ('Areia', 3, 5, 'Areia 5', 'Areia', '{1,4}', 1, 5),
      ('Bar', 4, 1, 'Bar 1', 'Bar', '{0,6}', 1, 1), ('Bar', 4, 2, 'Bar 2', 'Bar', '{0,1}', 1, 4),
      ('Bar', 4, 3, 'Bar 3', 'Bar', '{2,3}', 1, 3), ('Bar', 4, 4, 'Bar 4', 'Bar', '{2,3}', 1, 2),
      ('ASG', 5, 1, 'ASG 1', 'ASG', '{0,6}', 1, 1), ('ASG', 5, 2, 'ASG 2', 'ASG', '{1,2}', 1, 2),
      ('ASG', 5, 3, 'ASG 3', 'ASG', '{3,4}', 1, 3),
      ('Cozinha', 6, 1, 'Chef', 'Chef', '{3}', null, null), ('Cozinha', 6, 2, 'Cozinha 1', 'Cozinha', '{0,1}', 1, 3),
      ('Cozinha', 6, 3, 'Cozinha 2', 'Cozinha', '{0,1}', 1, 2), ('Cozinha', 6, 4, 'Cozinha 3', 'Cozinha', '{0,6}', 1, 1),
      ('Cozinha', 6, 5, 'Cozinha 4', 'Cozinha', '{1,2}', 2, 1), ('Cozinha', 6, 6, 'Cozinha 5', 'Cozinha', '{2,3}', 2, 2),
      ('Cozinha', 6, 7, 'Cozinha 6', 'Cozinha', '{3,6}', 2, 3), ('Cozinha', 6, 8, 'Cozinha 7', 'Cozinha', '{2,4}', 2, 4)
    ) as t(setor, ordem_setor, ordem, nome, cargo, folgas, caminho, posicao)
    order by ordem_setor, ordem
  loop
    select x.id into v_setor from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(r.setor);
    if v_setor is null then
      insert into public.escala_setores (empresa_id, nome, ordem) values (v_empresa, r.setor, r.ordem_setor) returning id into v_setor;
      v_setores := v_setores + 1;
    end if;
    if not (v_setor = any (v_setores_ids)) then v_setores_ids := v_setores_ids || v_setor; end if;
    v_chave := r.setor || '|' || r.nome;
    continue when exists (select 1 from public.escala_membros m where m.empresa_id = v_empresa and m.modelo_posicao = v_chave);
    -- funcionário de mesmo nome: já na escala → só marca a posição do modelo; fora da escala → entra nela
    select f.id, m.id into v_func, v_membro
      from public.funcionarios f left join public.escala_membros m on m.funcionario_id = f.id
     where f.empresa_id = v_empresa and lower(btrim(f.nome)) = lower(r.nome)
     order by (m.id is null) desc, f.criado_em, f.id
     limit 1;
    if v_membro is not null then
      update public.escala_membros set modelo_posicao = v_chave where id = v_membro and modelo_posicao is null;
      continue;
    end if;
    if v_func is null then
      insert into public.funcionarios (empresa_id, nome, cargo, pontos_comissao) values (v_empresa, r.nome, r.cargo, 0)
      returning id into v_func;
      v_criados := v_criados + 1;
    end if;
    v_pos := r.posicao;
    if r.caminho is not null and exists (select 1 from public.escala_membros m
                                          where m.setor_id = v_setor and m.caminho = r.caminho and m.posicao = v_pos) then
      v_pos := null;    -- posição ocupada → próxima livre do caminho
    end if;
    perform public.escala_gravar_membro(v_setor, v_func, r.folgas::smallint[], null, r.caminho::smallint, v_pos, r.ordem, v_chave);
    v_membros := v_membros + 1;
  end loop;

  perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(v_setores_ids), v_cfg.ancora);
  return jsonb_build_object('ancora', (select c.ancora from public.escala_config c where c.empresa_id = v_empresa),
                            'setores', v_setores, 'membros', v_membros, 'funcionarios_criados', v_criados);
end $$;
comment on function public.escala_aplicar_modelo_macaw(uuid, date) is
  '[api] Monta setores, caminhos e posições do modelo Macaw (cria funcionários provisórios); idempotente.';

-- (adendo extras v3, §S.11) dia com falta registrada não aceita ajuste/troca da escala
create or replace function public.escala_checar_falta(p_funcionario uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
begin
  if p_funcionario is not null and p_data is not null and public.ponto_falta_do_dia(p_funcionario, p_data) is not null then
    raise exception 'Dia com falta em %: remova a falta antes', to_char(p_data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
end $$;
comment on function public.escala_checar_falta(uuid, date) is '[interno] Recusa ajuste/troca da escala em dia com falta.';

-- ================================================================ RPCs de ajuste
create or replace function public.escala_ajustar(p_funcionario uuid, p_data date, p_status text default null,
                                                 p_chegada time default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  -- (v3, §S.11) status de falta = atalho para falta_registrar (o ajuste do dia não muda)
  if p_status in ('falta_justificada', 'falta_injustificada') then
    perform public.falta_registrar(p_funcionario, p_data, substr(p_status, 7), p_motivo);
    return public.escala_dia_json(m.empresa_id, p_funcionario, p_data, true);
  end if;
  v_status := public.escala_status_param(p_status);
  perform public.escala_validar_data(m.empresa_id, p_data);
  select * into c from public.escala_calcular(m.empresa_id, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
  perform public.escala_checar_falta(p_funcionario, p_data);
  perform public.escala_gravar_dia(m.id, p_data, v_status, p_chegada, p_motivo);
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_data, p_data);
  return public.escala_dia_json(m.empresa_id, p_funcionario, p_data, true);
end $$;
comment on function public.escala_ajustar(uuid, date, text, time, text) is '[api] Define o estado de um dia da escala (status/chegada) e reapura.';

create or replace function public.escala_ajustar_periodo(p_funcionario uuid, p_inicio date, p_fim date, p_status text,
                                                         p_motivo text default null)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record; v_n int := 0;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_status := public.escala_status_param(p_status);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  perform public.escala_validar_data(m.empresa_id, p_inicio);
  perform public.escala_validar_data(m.empresa_id, p_fim);
  for c in select * from public.escala_calcular(m.empresa_id, p_inicio, p_fim, p_funcionario) x order by x.data loop
    continue when c.status = 'fora';
    perform public.escala_checar_falta(p_funcionario, c.data);
  end loop;
  for c in select * from public.escala_calcular(m.empresa_id, p_inicio, p_fim, p_funcionario) x order by x.data loop
    continue when c.status = 'fora';
    perform public.escala_gravar_dia(m.id, c.data, v_status, c.ajuste_chegada, p_motivo);
    v_n := v_n + 1;
  end loop;
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_inicio, p_fim);
  return v_n;
end $$;
comment on function public.escala_ajustar_periodo(uuid, date, date, text, text) is
  '[api] Mesmo status em vários dias (ex.: férias), mantendo a chegada ajustada; reapura.';

create or replace function public.escala_trocar(p_funcionario_a uuid, p_data_a date, p_funcionario_b uuid default null,
                                                p_data_b date default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ma public.escala_membros; mb public.escala_membros; v_motivo text; v_datas date[]; v_d date;
  ca record; cb record; v_out jsonb := '[]';
begin
  ma := public.escala_membro_para_operar(p_funcionario_a);
  if (p_funcionario_b is null and p_data_b is null) or p_funcionario_b = p_funcionario_a and p_data_b is null then
    raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023';
  end if;
  if p_funcionario_b is not null and p_funcionario_b <> p_funcionario_a then
    mb := public.escala_membro_para_operar(p_funcionario_b);
    if mb.empresa_id <> ma.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  end if;
  v_motivo := coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Troca de folga');
  perform public.escala_validar_data(ma.empresa_id, p_data_a);
  if p_data_b is not null then perform public.escala_validar_data(ma.empresa_id, p_data_b); end if;

  if mb.id is null then
    -- A troca o próprio status entre os dois dias
    if p_data_b = p_data_a then raise exception 'Informe o outro funcionário ou o outro dia' using errcode = '22023'; end if;
    select * into ca from public.escala_calcular(ma.empresa_id, p_data_a, p_data_a, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, p_data_b, p_data_b, p_funcionario_a) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_checar_falta(p_funcionario_a, least(p_data_a, p_data_b));
    perform public.escala_checar_falta(p_funcionario_a, greatest(p_data_a, p_data_b));
    perform public.escala_gravar_dia(ma.id, p_data_a, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(ma.id, p_data_b, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], least(p_data_a, p_data_b), least(p_data_a, p_data_b));
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a], greatest(p_data_a, p_data_b), greatest(p_data_a, p_data_b));
    select jsonb_agg(public.escala_dia_json(ma.empresa_id, p_funcionario_a, d, true) order by d) into v_out
      from unnest(array[p_data_a, p_data_b]) d;
    return v_out;
  end if;

  -- A e B trocam o status em cada dia
  v_datas := array[p_data_a];
  if p_data_b is not null and p_data_b <> p_data_a then v_datas := v_datas || p_data_b; end if;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    if ca.status = 'fora' or cb.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
    if 'ferias' in (ca.status, cb.status) then raise exception 'Não é possível trocar dia de férias' using errcode = '22023'; end if;
    perform public.escala_checar_falta(p_funcionario_a, v_d);
    perform public.escala_checar_falta(p_funcionario_b, v_d);
  end loop;
  foreach v_d in array v_datas loop
    select * into ca from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_a) x;
    select * into cb from public.escala_calcular(ma.empresa_id, v_d, v_d, p_funcionario_b) x;
    perform public.escala_gravar_dia(ma.id, v_d, nullif(cb.status, ca.status_auto), ca.ajuste_chegada,
                                     case when cb.status <> ca.status_auto then v_motivo end);
    perform public.escala_gravar_dia(mb.id, v_d, nullif(ca.status, cb.status_auto), cb.ajuste_chegada,
                                     case when ca.status <> cb.status_auto then v_motivo end);
    perform public.escala_reapurar(ma.empresa_id, array[p_funcionario_a, p_funcionario_b], v_d, v_d);
  end loop;
  select jsonb_agg(public.escala_dia_json(ma.empresa_id, f, d, true) order by o, d) into v_out
    from unnest(array[p_funcionario_a, p_funcionario_b]) with ordinality as u(f, o)
    cross join unnest(v_datas) d;
  return v_out;
end $$;
comment on function public.escala_trocar(uuid, date, uuid, date, text) is
  '[api] Troca de folga: A↔B num dia (ou em dois dias) ou A entre dois dias; reapura.';

-- ================================================================ RPCs de leitura
create or replace function public.escala_mes(p_ano_mes text, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_ini date; v_fim date; v_cfg public.escala_config; v_motivo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_ano_mes is null or p_ano_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Mês inválido (use AAAA-MM)' using errcode = '22023';
  end if;
  v_ini := (p_ano_mes || '-01')::date;
  v_fim := (v_ini + interval '1 month')::date - 1;
  v_motivo := public.pode_operar(v_empresa) is true;
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;

  return (
    with calc as materialized (select * from public.escala_calcular(v_empresa, v_ini, v_fim)),
    dias as (select g::date as d from generate_series(v_ini, v_fim, interval '1 day') g),
    -- (v3, §S.11) faltas do mês (FJ/FI); tabela da …0290 (função plpgsql: resolvida na execução)
    fal as (select fl.funcionario_id, fl.data, fl.tipo from public.funcionario_faltas fl
             where fl.empresa_id = v_empresa and fl.data between v_ini and v_fim),
    mem as (
      select m.*, f.nome, f.cargo from public.escala_membros m join public.funcionarios f on f.id = m.funcionario_id
       where m.empresa_id = v_empresa
    )
    select jsonb_build_object(
      'empresa_id', v_empresa, 'ano_mes', p_ano_mes, 'inicio', v_ini, 'fim', v_fim,
      'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'pode_editar', v_motivo, 'hoje', public.escala_hoje(v_empresa),
      'dias', (select jsonb_agg(jsonb_build_object('data', d, 'dia_semana', extract(isodow from d)::int - 1,
                                                   'semana', case when v_cfg.ancora is not null then public.escala_semana_num(d, v_cfg.ancora) end)
                                order by d) from dias),
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs) order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'membro_id', m.id, 'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                            'chegada_padrao', public.escala_hora(m.chegada_padrao), 'folgas_base', to_jsonb(m.folgas_base),
                            'caminho', m.caminho, 'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                            'trabalha', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'trabalha'),
                            'folgas', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'folga'),
                            'ferias', (select count(*) from calc c where c.funcionario_id = m.funcionario_id and c.status = 'ferias'),
                            'faltas', (select count(*) from fal where fal.funcionario_id = m.funcionario_id),
                            'dias', coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'data', dd.d, 'status', coalesce(c.status, 'fora'), 'origem', coalesce(c.origem, 'auto'),
                                       'chegada', public.escala_hora(c.chegada), 'ajustado', coalesce(c.ajustado, false),
                                       'motivo', case when v_motivo then c.motivo end, 'falta', fal.tipo) order by dd.d)
                                from dias dd left join calc c on c.funcionario_id = m.funcionario_id and c.data = dd.d
                                left join fal on fal.funcionario_id = m.funcionario_id and fal.data = dd.d), '[]'))
                          order by m.ordem, m.nome collate "C", m.id)
                     from mem m where m.setor_id = s.id), '[]'),
                 'na_escala', (select jsonb_agg((select count(*) from calc c where c.setor_id = s.id and c.data = dd.d and c.status = 'trabalha')
                                                order by dd.d) from dias dd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala', (select jsonb_agg((select count(*) from calc c where c.data = dd.d and c.status = 'trabalha') order by dd.d)
                      from dias dd))
  );
end $$;
comment on function public.escala_mes(text, uuid) is '[api] Escala do mês (AAAA-MM): setores, membros e dias (leitura vê, sem motivos).';

create or replace function public.escala_semana(p_data date default null, p_empresa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; v_cfg public.escala_config; v_data date; v_seg date; v_w int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  v_data := coalesce(p_data, public.escala_hoje(v_empresa));
  v_seg := v_data - (extract(isodow from v_data)::int - 1);
  select * into v_cfg from public.escala_config where empresa_id = v_empresa;
  v_w := case when v_cfg.ancora is not null then public.escala_semana_num(v_seg, v_cfg.ancora) end;

  return (
    with r as materialized (select * from public.escala_membros_rodizio(v_empresa)),
    mem as (
      select r.*, f.nome, f.cargo, m.ordem,
             coalesce(case when v_w is null or r.caminho is null then r.folgas_base
                           else (select a.folgas_base from r a
                                  where a.setor_id = r.setor_id and a.caminho = r.caminho
                                    and a.k = (((r.k + v_w + coalesce(v_cfg.fase, 0) + r.fase_setor) % r.n) + r.n) % r.n) end,
                      r.folgas_base) as folgas_semana
        from r join public.funcionarios f on f.id = r.funcionario_id join public.escala_membros m on m.id = r.id
    ),
    wd as (select generate_series(0, 6) as d)
    select jsonb_build_object(
      'empresa_id', v_empresa, 'configurada', v_cfg.empresa_id is not null, 'ancora', v_cfg.ancora, 'fase', v_cfg.fase,
      'semana_inicio', v_seg, 'semana', v_w,
      'setores', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'nome', s.nome, 'ordem', s.ordem, 'fase', s.fase,
                 'total', (select count(*) from mem m where m.setor_id = s.id),
                 'caminhos', coalesce((select jsonb_agg(jsonb_build_object('caminho', cm.caminho, 'funcionarios', cm.funcs, 'nomes', cm.nomes)
                                                        order by cm.caminho)
                                         from (select m.caminho, jsonb_agg(m.funcionario_id order by m.posicao, m.id) as funcs,
                                                      jsonb_agg(m.nome order by m.posicao, m.id) as nomes
                                                 from mem m where m.setor_id = s.id and m.caminho is not null group by m.caminho) cm), '[]'),
                 'membros', coalesce((select jsonb_agg(jsonb_build_object(
                                               'funcionario_id', m.funcionario_id, 'nome', m.nome, 'cargo', m.cargo,
                                               'chegada_padrao', public.escala_hora(m.chegada_padrao), 'caminho', m.caminho,
                                               'posicao', m.posicao, 'folga_fixa', m.caminho is null,
                                               'folgas_base', to_jsonb(m.folgas_base), 'folgas_semana', to_jsonb(m.folgas_semana))
                                             order by m.ordem, m.nome collate "C", m.id)
                                        from mem m where m.setor_id = s.id), '[]'),
                 'na_escala_base', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_base)))
                                                     order by wd.d) from wd),
                 'na_escala_semana', (select jsonb_agg((select count(*) from mem m where m.setor_id = s.id and not (wd.d::smallint = any (m.folgas_semana)))
                                                       order by wd.d) from wd))
               order by s.ordem, s.nome collate "C", s.id)
          from public.escala_setores s where s.empresa_id = v_empresa), '[]'),
      'na_escala_base', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_base))) order by wd.d) from wd),
      'na_escala_semana', (select jsonb_agg((select count(*) from mem m where not (wd.d::smallint = any (m.folgas_semana))) order by wd.d) from wd))
  );
end $$;
comment on function public.escala_semana(date, uuid) is '[api] Semana base e semana de p_data pela regra do rodízio (sem ajustes).';-- =====================================================================================================
-- 20261006000290_comissao_presenca.sql — backend (adendo extras/ocorrências/reservas v3, §E.7; adendo escala §S.11)
-- Presença do dia na comissão (ponto → escala → fallback individual; falta, suspensão, férias, atestado, abono individual
-- e fora do vínculo nunca), faltas (justificada/injustificada) com anexo, recálculo de rascunhos (faltas, desligamento),
-- extras com pontuação pendente e importação de extras em lote. Aqui ficam comissao_calcular, comissao_fechar e
-- comissao_detalhe (vieram da …0220). Fechamento FECHADO nunca muda. Idempotente.
-- =====================================================================================================

-- ================================================================ colunas novas
alter table public.comissao_fechamentos add column if not exists extras_sem_pontuacao int not null default 0;
alter table public.comissao_itens add column if not exists pontos_pendente boolean not null default false;

commit;
select 'parte 16 de 19 instalada' as resultado;
