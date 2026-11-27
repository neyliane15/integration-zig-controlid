-- =====================================================================================================
-- 20261006000340_consultas.sql — "Consultas rápidas" (perguntas prontas, sem IA)
-- Duas consultas novas para a tela /consultas (as outras perguntas usam RPCs que o site já tem: vendas_*,
-- ocorrencias_ponto):
--   · consultas_ponto_resumo — por funcionário no período: dias com batida, faltas, atrasos, horas, saldo (G A M)
--   · consultas_escala_dia   — quem trabalha / folga num dia, com a chegada da escala (G A M L)
-- Idempotente.
-- =====================================================================================================

-- (nomes provisórios de um rascunho que nunca foi instalado — removidos se existirem)
drop function if exists public.assistente_ponto_resumo(date, date, uuid);
drop function if exists public.assistente_escala_dia(date, uuid);

create or replace function public.consultas_ponto_resumo(p_inicio date, p_fim date, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, cargo text, dias_com_batida int, faltas int,
               faltas_justificadas int, atrasos int, minutos_atraso int, trabalhado_minutos int, saldo_minutos int)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'operar');
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 366 then
    raise exception 'Período inválido (máximo de 366 dias)' using errcode = '22023';
  end if;
  return query
  select f.id, f.nome, f.cargo,
         count(*) filter (where d.batidas_validas > 0)::int,
         (count(*) filter (where d.encerrado and d.situacao = 'ausente'
                             and not exists (select 1 from public.funcionario_faltas x
                                              where x.funcionario_id = f.id and x.data = d.data))
          + (select count(*) from public.funcionario_faltas x
              where x.funcionario_id = f.id and x.data between p_inicio and p_fim and x.tipo = 'injustificada'))::int,
         (select count(*) from public.funcionario_faltas x
           where x.funcionario_id = f.id and x.data between p_inicio and p_fim and x.tipo = 'justificada')::int,
         count(*) filter (where d.atraso_minutos > 0)::int,
         coalesce(sum(d.atraso_minutos), 0)::int,
         coalesce(sum(d.trabalhado_minutos), 0)::int,
         coalesce(sum(d.saldo_minutos) filter (where d.encerrado), 0)::int
    from public.funcionarios f
    left join public.ponto_dias d on d.funcionario_id = f.id and d.data between p_inicio and p_fim
   where f.empresa_id = v_empresa
     and (f.data_admissao is null or f.data_admissao <= p_fim)
     and (f.data_desligamento is null or f.data_desligamento >= p_inicio)
   group by f.id, f.nome, f.cargo
   order by f.nome;
end $$;
comment on function public.consultas_ponto_resumo(date, date, uuid) is
  '[api] Consultas: ponto por funcionário no período (dias com batida, faltas, atrasos, horas, saldo) (G A M).';

create or replace function public.consultas_escala_dia(p_data date, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, setor text, status text, chegada text, ajustado boolean)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_data is null then raise exception 'Informe a data' using errcode = '22023'; end if;
  return query
  select c.funcionario_id, f.nome, s.nome, c.status, public.escala_hora(c.chegada), c.ajustado
    from public.escala_calcular(v_empresa, p_data, p_data) c
    join public.funcionarios f on f.id = c.funcionario_id
    join public.escala_setores s on s.id = c.setor_id
   order by s.ordem, s.nome, f.nome;
end $$;
comment on function public.consultas_escala_dia(date, uuid) is
  '[api] Consultas: escala de um dia (status trabalha/folga/ferias/banco_horas/fora e chegada) (G A M L).';

-- Escala do período por funcionário: dias trabalhando, folgas, folgas de BH e férias (G A M L).
create or replace function public.consultas_escala_periodo(p_inicio date, p_fim date, p_empresa uuid default null)
returns table (funcionario_id uuid, funcionario_nome text, setor text, trabalha int, folgas int, banco_horas int, ferias int)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare v_empresa uuid;
begin
  v_empresa := public.ponto_resolver_empresa(p_empresa, 'ler');
  if p_inicio is null or p_fim is null or p_fim < p_inicio or p_fim - p_inicio > 92 then
    raise exception 'Período inválido (máximo de 93 dias)' using errcode = '22023';
  end if;
  return query
  select c.funcionario_id, f.nome, s.nome,
         count(*) filter (where c.status = 'trabalha')::int,
         count(*) filter (where c.status = 'folga')::int,
         count(*) filter (where c.status = 'banco_horas')::int,
         count(*) filter (where c.status = 'ferias')::int
    from public.escala_calcular(v_empresa, p_inicio, p_fim) c
    join public.funcionarios f on f.id = c.funcionario_id
    join public.escala_setores s on s.id = c.setor_id
   group by c.funcionario_id, f.nome, s.nome, s.ordem
   order by s.ordem, s.nome, f.nome;
end $$;
comment on function public.consultas_escala_periodo(date, date, uuid) is
  '[api] Consultas: escala do período por funcionário (dias trabalhando, folgas, folgas de BH, férias) (G A M L).';
