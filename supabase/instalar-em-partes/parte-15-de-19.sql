-- Meu Dia de Gerente — instalação do banco, PARTE 15 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000280_escala.sql. Não edite à mão.

begin;
create or replace function public.escala_membros_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  select s.empresa_id into v_empresa from public.escala_setores s where s.id = new.setor_id;
  if v_empresa is null then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  new.empresa_id := v_empresa;
  if not exists (select 1 from public.funcionarios f where f.id = new.funcionario_id and f.empresa_id = v_empresa) then
    raise exception 'Funcionário de outra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
comment on function public.escala_membros_antes() is '[interno] Gatilho: empresa do membro = do setor; funcionário da mesma empresa.';
drop trigger if exists a_antes on public.escala_membros;
create trigger a_antes before insert or update on public.escala_membros
  for each row execute function public.escala_membros_antes();

create or replace function public.escala_ajustes_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m record;
begin
  select x.empresa_id, x.funcionario_id into m from public.escala_membros x where x.id = new.membro_id;
  if m.empresa_id is null then raise exception 'Funcionário fora da escala' using errcode = '22023'; end if;
  new.empresa_id := m.empresa_id;
  new.funcionario_id := m.funcionario_id;
  return new;
end $$;
comment on function public.escala_ajustes_antes() is '[interno] Gatilho: empresa/funcionário do ajuste = do membro.';
drop trigger if exists a_antes on public.escala_ajustes;
create trigger a_antes before insert or update on public.escala_ajustes
  for each row execute function public.escala_ajustes_antes();

drop trigger if exists tocar_atualizado_em on public.escala_config;
create trigger tocar_atualizado_em before update on public.escala_config
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_setores;
create trigger tocar_atualizado_em before update on public.escala_setores
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_membros;
create trigger tocar_atualizado_em before update on public.escala_membros
  for each row execute function public.tocar_atualizado_em();
drop trigger if exists tocar_atualizado_em on public.escala_ajustes;
create trigger tocar_atualizado_em before update on public.escala_ajustes
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ regra do rodízio (§S.2)
-- Membros com a posição k (0-based) e o tamanho n do caminho; p_setor restringe a um setor (usado pelo ponto).
create or replace function public.escala_membros_rodizio(p_empresa uuid, p_setor uuid default null)
returns table (id uuid, funcionario_id uuid, setor_id uuid, caminho smallint, posicao smallint, k int, n int,
               folgas_base smallint[], chegada_padrao time, fase_setor int, data_admissao date, data_desligamento date)
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
  select m.id, m.funcionario_id, m.setor_id, m.caminho, m.posicao,
         (row_number() over (partition by m.setor_id, m.caminho order by m.posicao, m.id) - 1)::int,
         (count(*) over (partition by m.setor_id, m.caminho))::int,
         m.folgas_base, m.chegada_padrao, s.fase, f.data_admissao, f.data_desligamento
    from public.escala_membros m
    join public.escala_setores s on s.id = m.setor_id
    join public.funcionarios f on f.id = m.funcionario_id
   where m.empresa_id = p_empresa and (p_setor is null or m.setor_id = p_setor)
$$;
comment on function public.escala_membros_rodizio(uuid, uuid) is '[interno] Membros com posição (k) e tamanho (n) do caminho.';

-- Número da semana (w) do dia em relação à âncora.
create or replace function public.escala_semana_num(p_data date, p_ancora date)
returns int language sql immutable set search_path = public, extensions, pg_temp as $$
  select ((p_data - (extract(isodow from p_data)::int - 1)) - p_ancora) / 7
$$;
comment on function public.escala_semana_num(date, date) is '[interno] Semana do dia contada a partir da âncora (semana 0).';

-- Escala calculada (regra + ajustes) para o período; p_funcionario restringe a um funcionário.
create or replace function public.escala_calcular(p_empresa uuid, p_inicio date, p_fim date, p_funcionario uuid default null)
returns table (funcionario_id uuid, membro_id uuid, setor_id uuid, data date, status text, status_auto text, origem text,
               chegada time, ajustado boolean, ajuste_status text, ajuste_chegada time, motivo text)
language sql stable security definer rows 40 set search_path = public, extensions, pg_temp set jit = off as $$
  with cfg as (select c.ancora, c.fase from public.escala_config c where c.empresa_id = p_empresa),
  mem as materialized (
    select r.* from public.escala_membros_rodizio(p_empresa,
             case when p_funcionario is not null
                  then (select x.setor_id from public.escala_membros x where x.funcionario_id = p_funcionario) end) r
     where p_funcionario is null
        or exists (select 1 from public.escala_membros x where x.funcionario_id = p_funcionario)
  ),
  base as (
    select b.*, g::date as d, cfg.ancora, cfg.fase as fase_emp
      from mem b cross join cfg cross join generate_series(p_inicio, p_fim, interval '1 day') g
     where p_funcionario is null or b.funcionario_id = p_funcionario
  ),
  calc as (
    select b.*,
           case when b.d < b.ancora or not public.ponto_no_vinculo(b.data_admissao, b.data_desligamento, b.d) then 'fora'
                when (extract(isodow from b.d)::int - 1)::smallint = any (alvo.folgas_base) then 'folga'
                else 'trabalha' end as st_auto
      from base b
      left join lateral (
        select a.folgas_base from mem a
         where (b.caminho is null and a.id = b.id)
            or (b.caminho is not null and a.setor_id = b.setor_id and a.caminho = b.caminho
                and a.k = (((b.k + public.escala_semana_num(b.d, b.ancora) + b.fase_emp + b.fase_setor) % b.n) + b.n) % b.n)
        limit 1
      ) alvo on true
  )
  select c.funcionario_id, c.id, c.setor_id, c.d,
         case when c.st_auto = 'fora' then 'fora' else coalesce(aj.status, c.st_auto) end,
         c.st_auto,
         case when c.st_auto <> 'fora' and aj.status is not null then 'ajuste' else 'auto' end,
         case when c.st_auto <> 'fora' and coalesce(aj.status, c.st_auto) = 'trabalha' then coalesce(aj.chegada, c.chegada_padrao) end,
         c.st_auto <> 'fora' and aj.id is not null,
         aj.status, aj.chegada, aj.motivo
    from calc c
    left join public.escala_ajustes aj on aj.funcionario_id = c.funcionario_id and aj.data = c.d
$$;
comment on function public.escala_calcular(uuid, date, date, uuid) is '[interno] Escala calculada (rodízio + ajustes) por funcionário × dia (§S.2).';

-- Usada por ponto_calcular_dia (…0200): status da escala no dia (null = fora da escala) e chegada.
create or replace function public.escala_status_ponto(p_funcionario uuid, p_data date, out status text, out chegada time)
language plpgsql stable security definer set search_path = public, extensions, pg_temp set jit = off as $$
declare v_empresa uuid; c record;
begin
  select m.empresa_id into v_empresa from public.escala_membros m where m.funcionario_id = p_funcionario;
  if v_empresa is null then return; end if;
  select * into c from public.escala_calcular(v_empresa, p_data, p_data, p_funcionario) x;
  if c.status is null or c.status = 'fora' then return; end if;
  status := c.status;
  chegada := c.chegada;
end $$;
comment on function public.escala_status_ponto(uuid, date) is '[interno] Status da escala no dia para a apuração (adendo escala §S.5).';

-- ================================================================ auxiliares
create or replace function public.escala_hoje(p_empresa uuid)
returns date language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select public.dia_de_trabalho(public.agora(), p_empresa)
$$;
comment on function public.escala_hoje(uuid) is '[interno] Dia de trabalho atual da empresa.';

-- Reapura os funcionários no período, limitado a [hoje − 61, hoje] (adendo §S.5).
create or replace function public.escala_reapurar(p_empresa uuid, p_funcionarios uuid[], p_inicio date default null,
                                                  p_fim date default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_hoje date; v_ini date; v_fim date; v_f uuid;
begin
  if p_funcionarios is null then return; end if;
  v_hoje := public.escala_hoje(p_empresa);
  v_ini := greatest(coalesce(p_inicio, v_hoje - 61), v_hoje - 61);
  v_fim := least(coalesce(p_fim, v_hoje), v_hoje);
  if v_ini > v_fim then return; end if;
  for v_f in select distinct x from unnest(p_funcionarios) x where x is not null order by 1 loop
    perform public.ponto_apurar(v_f, v_ini, v_fim);
  end loop;
end $$;
comment on function public.escala_reapurar(uuid, uuid[], date, date) is '[interno] Reapura funcionários afetados pela escala (máx. 62 dias).';

create or replace function public.escala_funcionarios_dos_setores(p_setores uuid[])
returns uuid[] language sql stable security definer set search_path = public, extensions, pg_temp as $$
  select coalesce(array_agg(m.funcionario_id), '{}') from public.escala_membros m where m.setor_id = any (p_setores)
$$;
comment on function public.escala_funcionarios_dos_setores(uuid[]) is '[interno] Funcionários dos setores.';

-- Configuração da empresa (cria com âncora = segunda da semana atual, se não existir).
create or replace function public.escala_garantir_config(p_empresa uuid)
returns public.escala_config language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.escala_config; v_hoje date;
begin
  select * into c from public.escala_config where empresa_id = p_empresa;
  if found then return c; end if;
  v_hoje := public.escala_hoje(p_empresa);
  insert into public.escala_config (empresa_id, ancora, fase)
  values (p_empresa, v_hoje - (extract(isodow from v_hoje)::int - 1), 0)
  on conflict (empresa_id) do nothing;
  select * into c from public.escala_config where empresa_id = p_empresa;
  return c;
end $$;
comment on function public.escala_garantir_config(uuid) is '[interno] Garante a configuração da escala (âncora padrão = segunda atual).';

create or replace function public.escala_validar_fase(p_fase int)
returns int language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_fase is null then return 0; end if;
  if p_fase < -1000 or p_fase > 1000 then raise exception 'Fase inválida' using errcode = '22023'; end if;
  return p_fase;
end $$;
comment on function public.escala_validar_fase(int) is '[interno] Valida a fase (−1000..1000).';

create or replace function public.escala_validar_folgas(p_folgas smallint[])
returns smallint[] language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare v smallint[];
begin
  if p_folgas is null then return '{}'; end if;
  if exists (select 1 from unnest(p_folgas) x where x is null or x < 0 or x > 6) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v from unnest(p_folgas) x;
  if coalesce(array_length(v, 1), 0) > 6 or coalesce(array_length(v, 1), 0) <> coalesce(array_length(p_folgas, 1), 0) then
    raise exception 'Folgas inválidas' using errcode = '22023';
  end if;
  return v;
end $$;
comment on function public.escala_validar_folgas(smallint[]) is '[interno] Folgas da semana base: 0..6 sem repetição, até 6 dias; ordena.';

create or replace function public.escala_status_param(p_status text)
returns text language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_status is null or p_status in ('auto', 'automatico') then return null; end if;
  if p_status not in ('trabalha', 'folga', 'ferias') then
    raise exception 'Status inválido' using errcode = '22023';
  end if;
  return p_status;
end $$;
comment on function public.escala_status_param(text) is '[interno] Status do ajuste: trabalha/folga/ferias; null ou auto = automático.';

create or replace function public.escala_setor_para_operar(p_setor uuid)
returns public.escala_setores language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare s public.escala_setores;
begin
  select * into s from public.escala_setores where id = p_setor;
  if not found then raise exception 'Setor não encontrado' using errcode = 'P0002'; end if;
  if public.pode_operar(s.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return s;
end $$;
comment on function public.escala_setor_para_operar(uuid) is '[interno] Setor existente e operável (G A M).';

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
                            'motivo', case when p_motivo then c.motivo end,
                            'falta', public.ponto_falta_do_dia(c.funcionario_id, c.data))
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

commit;
select 'parte 15 de 19 instalada' as resultado;
