-- 82_ocorrencias_ponto.sql — faltas e atrasos nas ocorrências; atraso pela chegada da escala; alarme só dos últimos
-- 2 dias (ponto_alarme_prazo_dias) e "poucas batidas" (menos que ponto_batidas_minimas, padrão 4); escalados do painel.
begin;
set local app.agora = '2026-11-17 12:00:00-03';   -- terça
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e8200000-0000-4000-8000-00000000000a', 'Teste Ocorr. Ponto', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e8200000-0000-4000-8000-000000000a01', 'ocp.ger@teste.local', '{"nome":"Gerente"}'),
  ('e8200000-0000-4000-8000-000000000a02', 'ocp.leit@teste.local', '{"nome":"Leitura"}');
update public.perfis set papel = 'gerente', empresa_id = 'e8200000-0000-4000-8000-00000000000a' where id = 'e8200000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'leitura', empresa_id = 'e8200000-0000-4000-8000-00000000000a' where id = 'e8200000-0000-4000-8000-000000000a02';
insert into public.funcionarios (id, empresa_id, nome, cargo, data_admissao) values
  ('e8200000-0000-4000-8000-000000000301', 'e8200000-0000-4000-8000-00000000000a', 'Ana RHiD', 'Garçom', '2026-01-01'),
  ('e8200000-0000-4000-8000-000000000302', 'e8200000-0000-4000-8000-00000000000a', 'Bia Escala', 'Cumim', '2026-01-01'),
  ('e8200000-0000-4000-8000-000000000303', 'e8200000-0000-4000-8000-00000000000a', 'Caio Sem Nada', 'Bar', '2026-01-01');

-- escala: Ana chega às 10h, Bia às 11h, sem folga fixa (trabalham todos os dias)
insert into public.escala_config (empresa_id, ancora) values ('e8200000-0000-4000-8000-00000000000a', '2026-11-02');
insert into public.escala_setores (id, empresa_id, nome) values
  ('e8200000-0000-4000-8000-000000000501', 'e8200000-0000-4000-8000-00000000000a', 'Salão');
insert into public.escala_membros (empresa_id, setor_id, funcionario_id, folgas_base, chegada_padrao) values
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000501', 'e8200000-0000-4000-8000-000000000301', '{}', '10:00'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000501', 'e8200000-0000-4000-8000-000000000302', '{}', '11:00');
select teste.ok('escala: Bia trabalha hoje com chegada 11h',
  (select (status, chegada) = ('trabalha'::text, '11:00'::time) from public.escala_status_ponto('e8200000-0000-4000-8000-000000000302', '2026-11-17')));

-- Ana: horário do RHiD 08:00–13:00/13:30–15:50 (7h20, tolerância 10) em 11, 13 e 16/11
insert into public.ponto_previsto_externo (funcionario_id, data, empresa_id, previsto_minutos, horarios, tolerancia_extra_minutos, tolerancia_falta_minutos)
select 'e8200000-0000-4000-8000-000000000301', d, 'e8200000-0000-4000-8000-00000000000a', 440, '{08:00,13:00,13:30,15:50}', 10, 10
  from unnest(array['2026-11-11', '2026-11-13', '2026-11-16']::date[]) d;
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo) values
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000301', 'manual', '2026-11-16 10:25-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000301', 'manual', '2026-11-16 15:00-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000301', 'manual', '2026-11-16 15:30-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000301', 'manual', '2026-11-16 17:50-03', 't'),
  -- Bia (sem jornada nem RHiD): 16/11 chegou 11:30, saiu 15:00; 10/11 uma batida só
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000302', 'manual', '2026-11-16 11:30-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000302', 'manual', '2026-11-16 15:00-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000302', 'manual', '2026-11-10 11:00-03', 't'),
  -- Caio (fora da escala, sem horário): 16/11 duas batidas
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000303', 'manual', '2026-11-16 18:00-03', 't'),
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000303', 'manual', '2026-11-16 23:00-03', 't');
select teste.como('ocp.ger@teste.local');
select public.falta_registrar('e8200000-0000-4000-8000-000000000301', '2026-11-13', 'justificada', 'Atestado');
select teste.como_dono();
select public.ponto_apurar(f, '2026-11-09', '2026-11-17')
  from unnest(array['e8200000-0000-4000-8000-000000000301', 'e8200000-0000-4000-8000-000000000302',
                    'e8200000-0000-4000-8000-000000000303']::uuid[]) f;

-- atraso pela chegada da escala
select teste.ok('Ana 16/11: entrada prevista deslocada para a chegada da escala (10:00) → 25 min de atraso',
  (select atraso_minutos = 25 and previsto_minutos = 440
     from public.ponto_dias where funcionario_id = 'e8200000-0000-4000-8000-000000000301' and data = '2026-11-16'));
select teste.ok('Ana 16/11: batidas esperadas a partir das 10:00',
  (select (c.esperadas -> 0 ->> 'instante')::timestamptz = '2026-11-16 10:00-03'
     from public.ponto_calcular_dia('e8200000-0000-4000-8000-000000000301', '2026-11-16') c));
select teste.ok('Bia 16/11 (sem horário, escalada às 11h): 30 min de atraso pela chegada da escala',
  (select atraso_minutos = 30 from public.ponto_dias where funcionario_id = 'e8200000-0000-4000-8000-000000000302' and data = '2026-11-16'));
select teste.ok('Caio (fora da escala): sem atraso', (select atraso_minutos = 0 from public.ponto_dias
   where funcionario_id = 'e8200000-0000-4000-8000-000000000303' and data = '2026-11-16'));

-- alarmes: só dos últimos 2 dias; poucas batidas (< 4) sem horário previsto
select teste.ok('alarmes abertos: só 15 a 17/11 (prazo de 2 dias); Bia e Caio com poucas batidas em 16/11',
  (select array_agg(f.nome || ' ' || a.data || ' ' || a.tipo order by f.nome, a.data, a.tipo)
     from public.ponto_alarmes a join public.funcionarios f on f.id = a.funcionario_id
    where a.empresa_id = 'e8200000-0000-4000-8000-00000000000a' and a.status = 'aberto')
  = array['Bia Escala 2026-11-16 poucas_batidas', 'Caio Sem Nada 2026-11-16 poucas_batidas']);
select teste.ok('Bia 10/11 (uma batida, fora do prazo): nenhum alarme',
  not exists (select 1 from public.ponto_alarmes where funcionario_id = 'e8200000-0000-4000-8000-000000000302' and data = '2026-11-10'));
update public.empresas set ponto_batidas_minimas = 2 where id = 'e8200000-0000-4000-8000-00000000000a';
select teste.ok('mínimo 2: poucas batidas resolvidas automaticamente',
  not exists (select 1 from public.ponto_alarmes where empresa_id = 'e8200000-0000-4000-8000-00000000000a'
                 and status = 'aberto' and tipo = 'poucas_batidas'));
update public.empresas set ponto_alarme_prazo_dias = 31, ponto_batidas_minimas = 4 where id = 'e8200000-0000-4000-8000-00000000000a';
select teste.ok('prazo 31: 10/11 (Bia, 1 batida) e 11/11 (Ana, ausente) voltam a ter alarme',
  exists (select 1 from public.ponto_alarmes where funcionario_id = 'e8200000-0000-4000-8000-000000000302' and data = '2026-11-10' and status = 'aberto')
  and exists (select 1 from public.ponto_alarmes where funcionario_id = 'e8200000-0000-4000-8000-000000000301' and data = '2026-11-11'
                 and tipo = 'sem_batida_dia_escalado' and status = 'aberto'));
update public.empresas set ponto_alarme_prazo_dias = 2 where id = 'e8200000-0000-4000-8000-00000000000a';
select teste.ok('prazo 2 de novo: só os dos últimos 2 dias ficam abertos',
  not exists (select 1 from public.ponto_alarmes where empresa_id = 'e8200000-0000-4000-8000-00000000000a'
                 and status = 'aberto' and data < '2026-11-15'));

-- rotina diária resolve o que passou do prazo
select teste.como_dono();
insert into public.ponto_alarmes (empresa_id, funcionario_id, data, tipo, detalhe) values
  ('e8200000-0000-4000-8000-00000000000a', 'e8200000-0000-4000-8000-000000000303', '2026-11-01', 'batidas_impares', 'antigo');
select teste.como_servico();
select public.ingestao_apurar_ponto('e8200000-0000-4000-8000-00000000000a');
select teste.ok('rotina diária: alarme antigo resolvido automaticamente',
  (select (status, resolvido_automaticamente) = ('resolvido'::text, true) from public.ponto_alarmes
    where funcionario_id = 'e8200000-0000-4000-8000-000000000303' and data = '2026-11-01'));

-- ocorrências: faltas (registradas e dias ausentes) e atrasos
select teste.como('ocp.ger@teste.local');
select teste.ok('ocorrências do ponto da Ana: atraso 16/11, falta justificada 13/11 (registrada), falta 11/11 (ponto)',
  (select array_agg(x ->> 'data' || ' ' || (x ->> 'tipo') || ' ' || coalesce(x ->> 'minutos', '-') || ' ' || (x ->> 'origem')
                    order by x ->> 'data' desc)
     from jsonb_array_elements(public.ocorrencias_ponto('2026-11-01', '2026-11-17', 'e8200000-0000-4000-8000-000000000301')) x)
  = array['2026-11-16 atraso 25 ponto', '2026-11-13 falta_justificada - registrada', '2026-11-11 falta - ponto']);
select teste.ok('atraso traz chegada e horário previsto',
  (select (x ->> 'chegada', x ->> 'previsto') = ('10:25', '10:00')
     from jsonb_array_elements(public.ocorrencias_ponto('2026-11-16', '2026-11-16', 'e8200000-0000-4000-8000-000000000301')) x));
select teste.ok('falta do ponto traz o previsto do dia',
  (select x ->> 'previsto' = '7h20' from jsonb_array_elements(public.ocorrencias_ponto('2026-11-11', '2026-11-11', 'e8200000-0000-4000-8000-000000000301')) x));
select teste.ok('empresa toda: 4 itens (2 atrasos, 2 faltas)',
  jsonb_array_length(public.ocorrencias_ponto('2026-11-01', '2026-11-17')) = 4);
select teste.ok('resumo de 30 dias: 2 faltas, 2 atrasos (55 min)',
  (select (r ->> 'faltas', r ->> 'atrasos', r ->> 'minutos_atraso') = ('2', '2', '55') and jsonb_array_length(r -> 'ponto_recentes') = 4
     from (select public.ocorrencias_resumo(30) r) x));
select teste.erro('período inválido', $$select public.ocorrencias_ponto('2026-11-10', '2026-11-01')$$, 'Período inválido (máximo de 366 dias)', '22023');
select teste.como('ocp.leit@teste.local');
select teste.erro('leitura não vê ocorrências do ponto',
  $$select public.ocorrencias_ponto('2026-11-01', '2026-11-17', 'e8200000-0000-4000-8000-000000000301')$$, 'Sem permissão', '42501');

-- painel: escalados contam a escala rotativa (sem jornada)
select teste.como('ocp.ger@teste.local');
select teste.ok('painel: 2 escalados hoje (Ana e Bia pela escala), 0 presentes',
  (select (p -> 'ponto' ->> 'escalados_hoje', p -> 'ponto' ->> 'presentes_agora') = ('2', '0') from (select public.painel_do_dia() p) x));
rollback;
