-- Meu Dia de Gerente — instalação do banco, PARTE 14 DE 19.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000260_extras.sql, 20261006000270_reservas.sql, 20261006000280_escala.sql. Não edite à mão.

begin;
comment on function public.gastos_periodo(date, date, uuid) is
  '[api] Gastos do período: diárias (extras e funcionários, pagas/a pagar) e comissões (fechadas/previstas), por pessoa e por dia (G A M).';-- =====================================================================================================
-- 20261006000270_reservas.sql — backend (adendo extras/ocorrências/reservas, seção R)
-- Reservas do dia: cadastro manual, importação de CSV (front) e ingestão genérica da Tagme (N8N, tipo de integração
-- 'tagme' ajustado em …0120). Telefone/e-mail são dados pessoais: só G A M (leitura lê por reservas_listar, sem eles).
-- Idempotente.
-- =====================================================================================================

create table if not exists public.reservas (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  integracao_id  uuid references public.integracoes (id) on delete set null,
  origem         text not null check (origem in ('tagme', 'manual', 'importacao')),
  id_externo     text,
  data           date not null,
  horario        time,
  nome_cliente   text not null check (btrim(nome_cliente) <> ''),
  pessoas        int not null default 1 check (pessoas between 1 and 500),
  status         text not null default 'confirmada'
                 check (status in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu')),
  area           text,
  mesa           text,
  observacao     text,
  telefone       text,
  email          text,
  criado_por     uuid references public.perfis (id) on delete set null,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  importado_em   timestamptz,
  constraint reservas_externa_uk unique (empresa_id, origem, id_externo),
  constraint reservas_tagme_id check (origem <> 'tagme' or id_externo is not null)
);
create index if not exists reservas_empresa_dia_idx on public.reservas (empresa_id, data, horario);
create index if not exists reservas_integracao_idx on public.reservas (integracao_id);
create index if not exists reservas_criado_por_idx on public.reservas (criado_por);
comment on table public.reservas is
  '[api:leitura] Reservas (Tagme, manuais, importadas). Select direto só G A M; leitura via reservas_listar (sem telefone/e-mail).';

alter table public.reservas enable row level security;
drop policy if exists reservas_ler on public.reservas;
create policy reservas_ler on public.reservas for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

drop trigger if exists tocar_atualizado_em on public.reservas;
create trigger tocar_atualizado_em before update on public.reservas
  for each row execute function public.tocar_atualizado_em();

-- ================================================================ auxiliares
create or replace function public.reserva_validar(p_data date, p_nome text, p_pessoas int, p_status text)
returns void language plpgsql immutable set search_path = public, extensions, pg_temp as $$
begin
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  if nullif(btrim(coalesce(p_nome, '')), '') is null then raise exception 'Informe o nome do cliente' using errcode = '22023'; end if;
  if p_pessoas is null or p_pessoas < 1 or p_pessoas > 500 then
    raise exception 'Número de pessoas inválido' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'Status de reserva inválido' using errcode = '22023';
  end if;
end $$;
comment on function public.reserva_validar(date, text, int, text) is '[interno] Validação de reserva (adendo R.3).';

create or replace function public.reserva_para_operar(p_reserva uuid)
returns public.reservas language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  select * into r from public.reservas where id = p_reserva;
  if not found then raise exception 'Reserva não encontrada' using errcode = 'P0002'; end if;
  if public.pode_operar(r.empresa_id) is not true then raise exception 'Sem permissão' using errcode = '42501'; end if;
  return r;
end $$;
comment on function public.reserva_para_operar(uuid) is '[interno] Reserva existente e operável (G A M).';

-- Data 'AAAA-MM-DD' ou 'DD/MM/AAAA' → date (null se inválida).
create or replace function public.reserva_ler_data(p_texto text)
returns date language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t ~ '^\d{4}-\d{2}-\d{2}$' then return to_date(t, 'YYYY-MM-DD')::date
    + case when to_char(to_date(t, 'YYYY-MM-DD'), 'YYYY-MM-DD') = t then 0 else null end;
  elsif t ~ '^\d{2}/\d{2}/\d{4}$' then return to_date(t, 'DD/MM/YYYY')::date
    + case when to_char(to_date(t, 'DD/MM/YYYY'), 'DD/MM/YYYY') = t then 0 else null end;
  end if;
  return null;
exception when others then return null;
end $$;
comment on function public.reserva_ler_data(text) is '[interno] Lê data AAAA-MM-DD ou DD/MM/AAAA.';

-- Horário 'HH:MM' ou 'HH:MM:SS' → time. Vazio → null; inválido → exceção 'horário inválido'.
create or replace function public.reserva_ler_horario(p_texto text)
returns time language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t = '' then return null; end if;
  if t !~ '^([01]?\d|2[0-3]):[0-5]\d(:[0-5]\d)?$' then raise exception 'horário inválido'; end if;
  return t::time;
end $$;
comment on function public.reserva_ler_horario(text) is '[interno] Lê horário HH:MM[:SS].';

-- Converte um item jsonb (importação/ingestão) em campos de reserva; erro → exceção com o motivo (texto curto).
create or replace function public.reserva_ler_item(p_item jsonb, p_chave_hora text,
                                                   out data date, out horario time, out nome text, out pessoas int,
                                                   out status text, out telefone text, out email text, out area text,
                                                   out mesa text, out observacao text, out id_externo text)
language plpgsql immutable set search_path = public, extensions, pg_temp as $$
declare v text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then raise exception 'item inválido'; end if;
  data := public.reserva_ler_data(p_item ->> 'data');
  if data is null then raise exception 'data inválida'; end if;
  horario := public.reserva_ler_horario(p_item ->> p_chave_hora);
  nome := nullif(btrim(coalesce(p_item ->> 'nome', p_item ->> 'nome_cliente', '')), '');
  if nome is null then raise exception 'informe o nome'; end if;
  v := btrim(coalesce(p_item ->> 'pessoas', ''));
  if v = '' then pessoas := 1;
  elsif v ~ '^\d{1,4}$' and v::int between 1 and 500 then pessoas := v::int;
  else raise exception 'pessoas inválido';
  end if;
  status := coalesce(nullif(btrim(p_item ->> 'status'), ''), 'confirmada');
  if status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'status inválido';
  end if;
  telefone := nullif(btrim(p_item ->> 'telefone'), '');
  email := nullif(btrim(p_item ->> 'email'), '');
  area := nullif(btrim(p_item ->> 'area'), '');
  mesa := nullif(btrim(p_item ->> 'mesa'), '');
  observacao := nullif(btrim(p_item ->> 'observacao'), '');
  id_externo := nullif(btrim(p_item ->> 'id_externo'), '');
end $$;
comment on function public.reserva_ler_item(jsonb, text) is '[interno] Item de importação/ingestão de reserva → campos.';

-- ================================================================ RPCs (front)
create or replace function public.reserva_criar(p_data date, p_horario time, p_nome_cliente text, p_pessoas int default 1,
                                                p_telefone text default null, p_area text default null, p_mesa text default null,
                                                p_observacao text default null, p_status text default 'confirmada',
                                                p_email text default null, p_empresa uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_id uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  perform public.reserva_validar(p_data, p_nome_cliente, coalesce(p_pessoas, 1), coalesce(p_status, 'confirmada'));
  insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                               telefone, email, criado_por)
  values (v_empresa, 'manual', p_data, p_horario, btrim(p_nome_cliente), coalesce(p_pessoas, 1), coalesce(p_status, 'confirmada'),
          nullif(btrim(p_area), ''), nullif(btrim(p_mesa), ''), nullif(btrim(p_observacao), ''),
          nullif(btrim(p_telefone), ''), nullif(btrim(p_email), ''), public.meu_perfil_id())
  returning id into v_id;
  return v_id;
end $$;
comment on function public.reserva_criar(date, time, text, int, text, text, text, text, text, text, uuid) is
  '[api] Cria uma reserva manual (G A M).';

create or replace function public.reserva_atualizar(p_reserva uuid, p_data date, p_horario time, p_nome_cliente text,
                                                    p_pessoas int, p_telefone text, p_area text, p_mesa text,
                                                    p_observacao text, p_status text, p_email text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if r.origem = 'tagme' then
    raise exception 'Reserva da Tagme: só o status pode ser alterado' using errcode = '22023';
  end if;
  perform public.reserva_validar(p_data, p_nome_cliente, p_pessoas, p_status);
  update public.reservas
     set data = p_data, horario = p_horario, nome_cliente = btrim(p_nome_cliente), pessoas = p_pessoas, status = p_status,
         area = nullif(btrim(p_area), ''), mesa = nullif(btrim(p_mesa), ''), observacao = nullif(btrim(p_observacao), ''),
         telefone = nullif(btrim(p_telefone), ''), email = nullif(btrim(p_email), '')
   where id = r.id;
end $$;
comment on function public.reserva_atualizar(uuid, date, time, text, int, text, text, text, text, text, text) is
  '[api] Edita uma reserva manual/importada (G A M).';

create or replace function public.reserva_mudar_status(p_reserva uuid, p_status text)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if p_status is null or p_status not in ('confirmada', 'pendente', 'cancelada', 'sentada', 'concluida', 'nao_compareceu') then
    raise exception 'Status de reserva inválido' using errcode = '22023';
  end if;
  update public.reservas set status = p_status where id = r.id and status is distinct from p_status;
end $$;
comment on function public.reserva_mudar_status(uuid, text) is '[api] Muda o status de uma reserva (G A M).';

create or replace function public.reserva_cancelar(p_reserva uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform public.reserva_mudar_status(p_reserva, 'cancelada');
end $$;
comment on function public.reserva_cancelar(uuid) is '[api] Cancela uma reserva (G A M).';

create or replace function public.reserva_excluir(p_reserva uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.reservas;
begin
  r := public.reserva_para_operar(p_reserva);
  if r.origem = 'tagme' then raise exception 'Reserva da Tagme não pode ser excluída' using errcode = '22023'; end if;
  delete from public.reservas where id = r.id;
end $$;
comment on function public.reserva_excluir(uuid) is '[api] Exclui uma reserva manual/importada (G A M).';

create or replace function public.reservas_listar(p_inicio date, p_fim date default null, p_status text[] default null,
                                                  p_empresa uuid default null)
returns table (id uuid, origem text, data date, horario time, nome_cliente text, pessoas int, status text, area text, mesa text,
               observacao text, telefone text, email text, criado_em timestamptz, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid; v_operar boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  perform public.ponto_validar_periodo(p_inicio, coalesce(p_fim, p_inicio), 93);
  v_operar := public.pode_operar(v_empresa) is true;
  return query
  select r.id, r.origem, r.data, r.horario, r.nome_cliente, r.pessoas, r.status, r.area, r.mesa, r.observacao,
         case when v_operar then r.telefone end, case when v_operar then r.email end, r.criado_em, r.atualizado_em
    from public.reservas r
   where r.empresa_id = v_empresa and r.data between p_inicio and coalesce(p_fim, p_inicio)
     and (p_status is null or r.status = any (p_status))
   order by r.data, r.horario nulls last, r.nome_cliente, r.id;
end $$;
comment on function public.reservas_listar(date, date, text[], uuid) is
  '[api] Reservas do período (L G A M; telefone/e-mail só para G A M).';

create or replace function public.reservas_importar(p_linhas jsonb, p_empresa uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa uuid; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_ids text[] := '{}'; v_novo boolean;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_linhas) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_linhas) with ordinality as e(valor, ord) loop
    begin
      select * into c from public.reserva_ler_item(it.valor, 'horario');
      if c.id_externo is not null then
        if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
        v_ids := v_ids || c.id_externo;
      end if;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    if c.id_externo is null then
      insert into public.reservas (empresa_id, origem, data, horario, nome_cliente, pessoas, status, area, mesa, observacao,
                                   telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa, c.observacao,
              c.telefone, c.email, public.meu_perfil_id(), public.agora());
      v_ins := v_ins + 1;
    else
      insert into public.reservas as r (empresa_id, origem, id_externo, data, horario, nome_cliente, pessoas, status, area, mesa,
                                        observacao, telefone, email, criado_por, importado_em)
      values (v_empresa, 'importacao', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
              c.observacao, c.telefone, c.email, public.meu_perfil_id(), public.agora())
      on conflict (empresa_id, origem, id_externo) do update
        set data = excluded.data, horario = excluded.horario, nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas,
            status = excluded.status, area = excluded.area, mesa = excluded.mesa, observacao = excluded.observacao,
            telefone = excluded.telefone, email = excluded.email, importado_em = excluded.importado_em
      returning (xmax = 0) into v_novo;
      if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('lidos', jsonb_array_length(p_linhas), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'erros', v_erros);
end $$;
comment on function public.reservas_importar(jsonb, uuid) is '[api] Importa reservas de um CSV lido pelo front (G A M).';

-- ================================================================ ingestão (N8N)
create or replace function public.ingestao_reservas(p_integracao uuid, p_inicio date, p_fim date, p_itens jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  ig public.integracoes; it record; c record; v_erros jsonb := '[]'::jsonb; v_ign int := 0; v_ins int := 0; v_atu int := 0;
  v_rem int := 0; v_ids text[] := '{}'; v_novo boolean;
begin
  ig := public.ingestao_integracao_validar(p_integracao, array['tagme']);
  perform public.ponto_validar_periodo(p_inicio, p_fim, 62);
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then raise exception 'Lista de itens inválida' using errcode = '22023'; end if;
  if jsonb_array_length(p_itens) > 2000 then raise exception 'Lote maior que 2000 itens' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('mdg:reservas:' || ig.empresa_id::text, 0));

  for it in select e.valor, (e.ord - 1)::int as indice from jsonb_array_elements(p_itens) with ordinality as e(valor, ord) loop
    begin
      if it.valor is null or jsonb_typeof(it.valor) <> 'object' then raise exception 'item inválido'; end if;
      if nullif(btrim(it.valor ->> 'id_externo'), '') is null then raise exception 'id_externo ausente'; end if;
      select * into c from public.reserva_ler_item(it.valor, 'hora');
      if c.id_externo = any (v_ids) then raise exception 'id repetido'; end if;
      v_ids := v_ids || c.id_externo;
    exception when others then
      v_ign := v_ign + 1;
      if jsonb_array_length(v_erros) < 20 then
        v_erros := v_erros || jsonb_build_object('indice', it.indice, 'motivo', sqlerrm);
      end if;
      continue;
    end;
    insert into public.reservas as r (empresa_id, integracao_id, origem, id_externo, data, horario, nome_cliente, pessoas, status,
                                      area, mesa, observacao, telefone, email, importado_em)
    values (ig.empresa_id, ig.id, 'tagme', c.id_externo, c.data, c.horario, c.nome, c.pessoas, c.status, c.area, c.mesa,
            c.observacao, c.telefone, c.email, public.agora())
    on conflict (empresa_id, origem, id_externo) do update
      set integracao_id = excluded.integracao_id, data = excluded.data, horario = excluded.horario,
          nome_cliente = excluded.nome_cliente, pessoas = excluded.pessoas, status = excluded.status, area = excluded.area,
          mesa = excluded.mesa, observacao = excluded.observacao, telefone = excluded.telefone, email = excluded.email,
          importado_em = excluded.importado_em
    returning (xmax = 0) into v_novo;
    if v_novo then v_ins := v_ins + 1; else v_atu := v_atu + 1; end if;
  end loop;

  delete from public.reservas r
   where r.empresa_id = ig.empresa_id and r.origem = 'tagme' and r.data between p_inicio and p_fim
     and not (r.id_externo = any (v_ids));
  get diagnostics v_rem = row_count;

  update public.integracoes
     set cursor = jsonb_build_object('ultimo_inicio', p_inicio, 'ultimo_fim', p_fim)
   where id = ig.id;

  return jsonb_build_object('lidos', jsonb_array_length(p_itens), 'gravados', v_ins + v_atu, 'ignorados', v_ign,
                            'inseridos', v_ins, 'atualizados', v_atu, 'removidos', v_rem, 'erros', v_erros);
end $$;
comment on function public.ingestao_reservas(uuid, date, date, jsonb) is
  '[servico] Reservas da Tagme (N8N): upsert por id_externo e remove as da janela que não vieram (adendo R.3).';

-- Bloco "reservas" do painel (sem checagem; o painel já resolveu a empresa).
create or replace function public.reservas_painel(p_empresa uuid, p_hoje date, p_telefone boolean)
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  with e as (select fuso from public.empresas where id = p_empresa),
       r as (select * from public.reservas where empresa_id = p_empresa and data = p_hoje)
  select jsonb_build_object(
    'total', (select count(*) from r where status <> 'cancelada'),
    'pessoas', (select coalesce(sum(pessoas), 0) from r where status <> 'cancelada'),
    'canceladas', (select count(*) from r where status = 'cancelada'),
    'nao_compareceu', (select count(*) from r where status = 'nao_compareceu'),
    'sentadas', (select count(*) from r where status = 'sentada'),
    'tem_tagme', exists (select 1 from public.integracoes i where i.empresa_id = p_empresa and i.tipo = 'tagme' and i.ativa),
    'proximas', coalesce((
       select jsonb_agg(jsonb_build_object('id', x.id, 'horario', x.horario, 'nome_cliente', x.nome_cliente, 'pessoas', x.pessoas,
                                           'status', x.status, 'area', x.area, 'mesa', x.mesa, 'observacao', x.observacao,
                                           'origem', x.origem, 'telefone', case when p_telefone then x.telefone end)
                        order by x.horario nulls last, x.nome_cliente, x.id)
         from (select r.* from r, e
                where r.status in ('confirmada', 'pendente')
                  and (r.horario is null or ((r.data + r.horario) at time zone e.fuso) >= public.agora() - interval '30 minutes')
                order by r.horario nulls last, r.nome_cliente, r.id
                limit 10) x), '[]'::jsonb))
$$;
comment on function public.reservas_painel(uuid, date, boolean) is '[interno] Bloco reservas do painel_do_dia (adendo R.4).';-- =====================================================================================================
-- 20261006000280_escala.sql — backend (docs/CONTRATO-ADENDO-escala.md)
-- Escala rotativa 5x2 (modelo Macaw): setores, membros (funcionários cadastrados) com folgas da semana base, caminhos
-- de rodízio contínuo a partir de uma data-âncora (segunda-feira) + fase, ajustes por dia (folga/trabalha/férias/chegada),
-- troca de folgas, férias → abono 'ferias' (ponto_abonos.escala_ajuste_id) e reapuração do ponto (máx. 62 dias).
-- A integração com a apuração está em ponto_calcular_dia (…0200), que chama escala_status_ponto (definida aqui).
-- Idempotente.
-- =====================================================================================================

-- ================================================================ tabelas
create table if not exists public.escala_config (
  empresa_id     uuid primary key references public.empresas (id) on delete cascade,
  ancora         date not null check (extract(isodow from ancora) = 1),
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table public.escala_config is '[api:leitura] Escala rotativa: data-âncora (segunda, semana 0) e fase por empresa.';

create table if not exists public.escala_setores (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas (id) on delete cascade,
  nome           text not null check (btrim(nome) <> ''),
  ordem          int  not null default 0,
  fase           int  not null default 0 check (fase between -1000 and 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create unique index if not exists escala_setores_nome_uk on public.escala_setores (empresa_id, lower(btrim(nome)));
create index if not exists escala_setores_empresa_idx on public.escala_setores (empresa_id, ordem);
comment on table public.escala_setores is '[api:leitura] Setores da escala (Salão, Bar, Cozinha...).';

create table if not exists public.escala_membros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  setor_id        uuid not null references public.escala_setores (id) on delete cascade,
  funcionario_id  uuid not null unique references public.funcionarios (id) on delete cascade,
  folgas_base     smallint[] not null default '{}',
  chegada_padrao  time,
  caminho         smallint check (caminho between 1 and 20),
  posicao         smallint check (posicao between 1 and 99),
  ordem           int not null default 0,
  modelo_posicao  text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint escala_membros_caminho check ((caminho is null) = (posicao is null)),
  constraint escala_membros_folgas check (folgas_base <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
                                          and coalesce(array_length(folgas_base, 1), 0) <= 6)
);
create index if not exists escala_membros_empresa_idx on public.escala_membros (empresa_id);
create index if not exists escala_membros_setor_idx on public.escala_membros (setor_id, ordem);
create unique index if not exists escala_membros_posicao_uk on public.escala_membros (setor_id, caminho, posicao)
  where caminho is not null;
create unique index if not exists escala_membros_modelo_uk on public.escala_membros (empresa_id, modelo_posicao)
  where modelo_posicao is not null;
comment on table public.escala_membros is
  '[api:leitura] Funcionários na escala: setor, folgas da semana base (0=SEG..6=DOM), chegada padrão, caminho/posição do rodízio.';

create table if not exists public.escala_ajustes (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  membro_id        uuid not null references public.escala_membros (id) on delete cascade,
  funcionario_id   uuid not null references public.funcionarios (id) on delete cascade,
  data             date not null,
  status           text check (status in ('trabalha', 'folga', 'ferias')),
  chegada          time,
  motivo           text,
  criado_por       uuid references public.perfis (id) on delete set null,
  criado_por_nome  text not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (funcionario_id, data),
  constraint escala_ajustes_algo check (status is not null or chegada is not null)
);
create index if not exists escala_ajustes_empresa_idx on public.escala_ajustes (empresa_id, data);
create index if not exists escala_ajustes_membro_idx on public.escala_ajustes (membro_id);
create index if not exists escala_ajustes_criado_por_idx on public.escala_ajustes (criado_por);
comment on table public.escala_ajustes is
  '[api:leitura] Ajustes da escala por dia (status e/ou chegada). Só G A M leem a tabela; leitura vê pela escala_mes.';

-- abono de férias gerado pela escala (coluna criada em …0200)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ponto_abonos_escala_ajuste_fk') then
    alter table public.ponto_abonos add constraint ponto_abonos_escala_ajuste_fk
      foreign key (escala_ajuste_id) references public.escala_ajustes (id) on delete cascade;
  end if;
end $$;

-- ================================================================ RLS
alter table public.escala_config enable row level security;
alter table public.escala_setores enable row level security;
alter table public.escala_membros enable row level security;
alter table public.escala_ajustes enable row level security;
drop policy if exists escala_config_ler on public.escala_config;
create policy escala_config_ler on public.escala_config for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_setores_ler on public.escala_setores;
create policy escala_setores_ler on public.escala_setores for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_membros_ler on public.escala_membros;
create policy escala_membros_ler on public.escala_membros for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_leitura()));
drop policy if exists escala_ajustes_ler on public.escala_ajustes;
create policy escala_ajustes_ler on public.escala_ajustes for select to authenticated
  using ((select public.eh_master()) or empresa_id = (select public.empresa_operacao()));

-- ================================================================ gatilhos
create or replace function public.escala_setores_antes()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'UPDATE' then
    new.empresa_id := old.empresa_id;
    new.criado_em := old.criado_em;
  end if;
  return new;
end $$;
comment on function public.escala_setores_antes() is '[interno] Gatilho: setor com nome aparado e empresa imutável.';
drop trigger if exists a_antes on public.escala_setores;
create trigger a_antes before insert or update on public.escala_setores
  for each row execute function public.escala_setores_antes();

commit;
select 'parte 14 de 19 instalada' as resultado;
