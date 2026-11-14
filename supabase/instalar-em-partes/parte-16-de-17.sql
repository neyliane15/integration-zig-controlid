-- Meu Dia de Gerente — instalação do banco, PARTE 16 DE 17.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000280_escala.sql. Não edite à mão.

begin;
create or replace function public.escala_membro_para_operar(p_funcionario uuid)
returns public.escala_membros language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; m public.escala_membros;
begin
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(v_empresa) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  select * into m from public.escala_membros where funcionario_id = p_funcionario;
  if not found then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  return m;
end $$;
comment on function public.escala_membro_para_operar(uuid) is '[interno] Membro da escala operável (G A M).';

-- Grava (upsert por funcionário) um membro, sem reapurar. Retorna o id do membro.
create or replace function public.escala_gravar_membro(p_setor uuid, p_funcionario uuid, p_folgas smallint[], p_chegada time,
                                                       p_caminho smallint, p_posicao smallint, p_ordem int,
                                                       p_modelo_posicao text default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  s public.escala_setores; v_emp_f uuid; v_folgas smallint[]; v_pos smallint; v_ordem int; v_id uuid; v_atual public.escala_membros;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  select f.empresa_id into v_emp_f from public.funcionarios f where f.id = p_funcionario;
  if v_emp_f is null then raise exception 'Funcionário não encontrado' using errcode = 'P0002'; end if;
  if v_emp_f <> s.empresa_id then raise exception 'Funcionário de outra empresa' using errcode = '22023'; end if;
  v_folgas := public.escala_validar_folgas(p_folgas);
  if p_caminho is not null and (p_caminho < 1 or p_caminho > 20) then
    raise exception 'Caminho inválido' using errcode = '22023';
  end if;
  select * into v_atual from public.escala_membros where funcionario_id = p_funcionario;
  v_pos := null;
  if p_caminho is not null then
    v_pos := p_posicao;
    if v_pos is null then
      select coalesce(max(m.posicao), 0) + 1 into v_pos from public.escala_membros m
       where m.setor_id = p_setor and m.caminho = p_caminho and m.funcionario_id <> p_funcionario;
    end if;
    if v_pos < 1 or v_pos > 99 then raise exception 'Posição inválida' using errcode = '22023'; end if;
    if exists (select 1 from public.escala_membros m
                where m.setor_id = p_setor and m.caminho = p_caminho and m.posicao = v_pos and m.funcionario_id <> p_funcionario) then
      raise exception 'Posição já ocupada no caminho' using errcode = '23505';
    end if;
  end if;
  v_ordem := p_ordem;
  if v_ordem is null then
    if v_atual.id is not null and v_atual.setor_id = p_setor then
      v_ordem := v_atual.ordem;
    else
      select coalesce(max(m.ordem), 0) + 1 into v_ordem from public.escala_membros m where m.setor_id = p_setor;
    end if;
  end if;
  insert into public.escala_membros as m (empresa_id, setor_id, funcionario_id, folgas_base, chegada_padrao, caminho, posicao,
                                          ordem, modelo_posicao)
  values (s.empresa_id, p_setor, p_funcionario, v_folgas, p_chegada, p_caminho, v_pos, v_ordem, p_modelo_posicao)
  on conflict (funcionario_id) do update set
    setor_id = excluded.setor_id, folgas_base = excluded.folgas_base, chegada_padrao = excluded.chegada_padrao,
    caminho = excluded.caminho, posicao = excluded.posicao, ordem = excluded.ordem,
    modelo_posicao = coalesce(excluded.modelo_posicao, m.modelo_posicao)
  returning m.id into v_id;
  return v_id;
end $$;
comment on function public.escala_gravar_membro(uuid, uuid, smallint[], time, smallint, smallint, int, text) is
  '[interno] Grava membro da escala (validações §S.7 nº 4), sem reapurar.';

-- Abono 'ferias' do ajuste (§S.4).
create or replace function public.escala_sincronizar_abono(p_ajuste uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare aj public.escala_ajustes; v_motivo text;
begin
  select * into aj from public.escala_ajustes where id = p_ajuste;
  if not found then return; end if;
  if aj.status is distinct from 'ferias' then
    delete from public.ponto_abonos where escala_ajuste_id = aj.id;
    return;
  end if;
  v_motivo := left(case when aj.motivo is null then 'Férias (escala)' else 'Férias (escala): ' || aj.motivo end, 500);
  if exists (select 1 from public.ponto_abonos a where a.escala_ajuste_id = aj.id) then
    update public.ponto_abonos set motivo = v_motivo where escala_ajuste_id = aj.id and motivo is distinct from v_motivo;
    return;
  end if;
  if exists (select 1 from public.ponto_abonos a where a.funcionario_id = aj.funcionario_id and a.data = aj.data) then
    raise exception 'Já existe abono para o funcionário em %', to_char(aj.data, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  insert into public.ponto_abonos (empresa_id, funcionario_id, data, tipo, motivo, criado_por, escala_ajuste_id)
  values (aj.empresa_id, aj.funcionario_id, aj.data, 'ferias', v_motivo, public.meu_perfil_id(), aj.id);
end $$;
comment on function public.escala_sincronizar_abono(uuid) is '[interno] Mantém o abono ''ferias'' de um ajuste de férias da escala.';

-- Grava o estado de um dia (status null = automático; chegada null = padrão; os dois null apagam o ajuste). Sem reapurar.
create or replace function public.escala_gravar_dia(p_membro uuid, p_data date, p_status text, p_chegada time, p_motivo text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_id uuid;
begin
  select * into m from public.escala_membros where id = p_membro;
  if p_status is null and p_chegada is null then
    delete from public.escala_ajustes where funcionario_id = m.funcionario_id and data = p_data;
    return;
  end if;
  insert into public.escala_ajustes as a (empresa_id, membro_id, funcionario_id, data, status, chegada, motivo,
                                          criado_por, criado_por_nome)
  values (m.empresa_id, m.id, m.funcionario_id, p_data, p_status, p_chegada, nullif(btrim(coalesce(p_motivo, '')), ''),
          public.meu_perfil_id(), public.ponto_nome_autor())
  on conflict (funcionario_id, data) do update set
    membro_id = excluded.membro_id, status = excluded.status, chegada = excluded.chegada, motivo = excluded.motivo,
    criado_por = excluded.criado_por, criado_por_nome = excluded.criado_por_nome
  returning a.id into v_id;
  perform public.escala_sincronizar_abono(v_id);
end $$;
comment on function public.escala_gravar_dia(uuid, date, text, time, text) is '[interno] Grava/apaga o ajuste de um dia e sincroniza o abono.';

create or replace function public.escala_validar_data(p_empresa uuid, p_data date)
returns void language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date;
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  v_hoje := public.escala_hoje(p_empresa);
  if p_data < v_hoje - 62 or p_data > v_hoje + 366 then
    raise exception 'Data fora do limite' using errcode = '22023';
  end if;
end $$;
comment on function public.escala_validar_data(uuid, date) is '[interno] Data de ajuste em [hoje − 62, hoje + 366].';

create or replace function public.escala_hora(p_hora time)
returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select to_char(p_hora, 'HH24:MI')
$$;
comment on function public.escala_hora(time) is '[interno] Hora como HH:MM.';

-- Objeto-dia (§S.8) de um funcionário; p_motivo = incluir o motivo (G A M).
create or replace function public.escala_dia_json(p_empresa uuid, p_funcionario uuid, p_data date, p_motivo boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select jsonb_build_object('funcionario_id', c.funcionario_id, 'data', c.data, 'status', c.status, 'origem', c.origem,
                            'chegada', public.escala_hora(c.chegada), 'ajustado', c.ajustado,
                            'motivo', case when p_motivo then c.motivo end)
    from public.escala_calcular(p_empresa, p_data, p_data, p_funcionario) c
$$;
comment on function public.escala_dia_json(uuid, uuid, date, boolean) is '[interno] Objeto-dia da escala (adendo §S.8).';

-- ================================================================ RPCs de configuração
create or replace function public.escala_configurar(p_ancora date, p_fase int default 0, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_antiga date; v_fase int;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_ancora is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if extract(isodow from p_ancora) <> 1 then
    raise exception 'A data-âncora deve ser uma segunda-feira' using errcode = '22023';
  end if;
  v_fase := public.escala_validar_fase(p_fase);
  select c.ancora into v_antiga from public.escala_config c where c.empresa_id = v_empresa;
  insert into public.escala_config as c (empresa_id, ancora, fase) values (v_empresa, p_ancora, v_fase)
  on conflict (empresa_id) do update set ancora = excluded.ancora, fase = excluded.fase;
  delete from public.escala_ajustes where empresa_id = v_empresa and data < p_ancora;
  perform public.escala_reapurar(v_empresa,
    (select array_agg(m.funcionario_id) from public.escala_membros m where m.empresa_id = v_empresa),
    least(coalesce(v_antiga, p_ancora), p_ancora));
  return jsonb_build_object('empresa_id', v_empresa, 'ancora', p_ancora, 'fase', v_fase);
end $$;
comment on function public.escala_configurar(date, int, uuid) is '[api] Define a data-âncora (segunda) e a fase da escala; reapura.';

create or replace function public.escala_salvar_setor(p_nome text, p_ordem int default null, p_fase int default 0,
                                                      p_setor uuid default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; s public.escala_setores; v_id uuid; v_nome text; v_fase int; v_cfg public.escala_config;
begin
  if p_setor is not null then
    s := public.escala_setor_para_operar(p_setor);
    v_empresa := s.empresa_id;
    if p_empresa is not null and p_empresa <> v_empresa then raise exception 'Sem permissão' using errcode = '42501'; end if;
  else
    v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  end if;
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  if v_nome is null then raise exception 'Informe o nome' using errcode = '22023'; end if;
  v_fase := public.escala_validar_fase(p_fase);
  if exists (select 1 from public.escala_setores x where x.empresa_id = v_empresa and lower(btrim(x.nome)) = lower(v_nome)
                and x.id is distinct from p_setor) then
    raise exception 'Setor já existe' using errcode = '23505';
  end if;
  v_cfg := public.escala_garantir_config(v_empresa);
  if p_setor is null then
    insert into public.escala_setores (empresa_id, nome, ordem, fase)
    values (v_empresa, v_nome,
            coalesce(p_ordem, (select coalesce(max(x.ordem), 0) + 1 from public.escala_setores x where x.empresa_id = v_empresa)),
            v_fase)
    returning id into v_id;
  else
    update public.escala_setores set nome = v_nome, ordem = coalesce(p_ordem, ordem), fase = v_fase where id = p_setor;
    v_id := p_setor;
    if s.fase <> v_fase then
      perform public.escala_reapurar(v_empresa, public.escala_funcionarios_dos_setores(array[p_setor]), v_cfg.ancora);
    end if;
  end if;
  return v_id;
end $$;
comment on function public.escala_salvar_setor(text, int, int, uuid, uuid) is '[api] Cria ou altera um setor da escala.';

create or replace function public.escala_excluir_setor(p_setor uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_func uuid[];
begin
  s := public.escala_setor_para_operar(p_setor);
  v_func := public.escala_funcionarios_dos_setores(array[p_setor]);
  delete from public.escala_setores where id = p_setor;
  perform public.escala_reapurar(s.empresa_id, v_func, (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
end $$;
comment on function public.escala_excluir_setor(uuid) is '[api] Exclui o setor (membros e ajustes) e reapura.';

create or replace function public.escala_salvar_membro(p_setor uuid, p_funcionario uuid, p_folgas_base smallint[] default '{}',
                                                       p_chegada_padrao time default null, p_caminho smallint default null,
                                                       p_posicao smallint default null, p_ordem int default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores; v_antigo uuid; v_id uuid;
begin
  s := public.escala_setor_para_operar(p_setor);
  select m.setor_id into v_antigo from public.escala_membros m where m.funcionario_id = p_funcionario;
  v_id := public.escala_gravar_membro(p_setor, p_funcionario, p_folgas_base, p_chegada_padrao, p_caminho, p_posicao, p_ordem);
  perform public.escala_reapurar(s.empresa_id,
    public.escala_funcionarios_dos_setores(array[p_setor, v_antigo]) || p_funcionario,
    (select c.ancora from public.escala_config c where c.empresa_id = s.empresa_id));
  return v_id;
end $$;
comment on function public.escala_salvar_membro(uuid, uuid, smallint[], time, smallint, smallint, int) is
  '[api] Põe/atualiza um funcionário num setor da escala (upsert por funcionário) e reapura.';

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

-- ================================================================ RPCs de ajuste
create or replace function public.escala_ajustar(p_funcionario uuid, p_data date, p_status text default null,
                                                 p_chegada time default null, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.escala_membros; v_status text; c record;
begin
  m := public.escala_membro_para_operar(p_funcionario);
  v_status := public.escala_status_param(p_status);
  perform public.escala_validar_data(m.empresa_id, p_data);
  select * into c from public.escala_calcular(m.empresa_id, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then raise exception 'Dia fora da escala' using errcode = '22023'; end if;
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
    perform public.escala_gravar_dia(m.id, c.data, v_status, c.ajuste_chegada, p_motivo);
    v_n := v_n + 1;
  end loop;
  perform public.escala_reapurar(m.empresa_id, array[p_funcionario], p_inicio, p_fim);
  return v_n;
end $$;
comment on function public.escala_ajustar_periodo(uuid, date, date, text, text) is
  '[api] Mesmo status em vários dias (ex.: férias), mantendo a chegada ajustada; reapura.';

commit;
select 'parte 16 de 17 instalada' as resultado;
