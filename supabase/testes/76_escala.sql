-- 76_escala.sql — escala rotativa (docs/CONTRATO-ADENDO-escala.md): rodízio contínuo entre meses, fase, ajustes, troca,
-- férias → abono, integração com o ponto (folga sem alarme, atraso pela chegada, batida faltante, reapuração), modelo Macaw,
-- adicionar funcionário, isolamento entre empresas e papel leitura.
begin;
set local app.agora = '2026-11-13 12:00:00-03';   -- sexta; âncora dos testes = seg 02/11/2026
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia, ponto_alarme_atraso) values
  ('e7600000-0000-4000-8000-00000000000a', 'Escala A', 'America/Sao_Paulo', '05:00', true),
  ('e7600000-0000-4000-8000-00000000000b', 'Escala B', 'America/Manaus', '05:00', false);
insert into auth.users (id, email, raw_user_meta_data) values
  ('e7600000-0000-4000-8000-000000000a01', 'es.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e7600000-0000-4000-8000-000000000a02', 'es.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e7600000-0000-4000-8000-000000000a03', 'es.lei.a@teste.local', '{"nome":"Leitura A"}'),
  ('e7600000-0000-4000-8000-000000000b01', 'es.adm.b@teste.local', '{"nome":"Adm B"}');
update public.perfis set papel = 'administrador', empresa_id = 'e7600000-0000-4000-8000-00000000000a' where id = 'e7600000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e7600000-0000-4000-8000-00000000000a' where id = 'e7600000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e7600000-0000-4000-8000-00000000000a' where id = 'e7600000-0000-4000-8000-000000000a03';
update public.perfis set papel = 'administrador', empresa_id = 'e7600000-0000-4000-8000-00000000000b' where id = 'e7600000-0000-4000-8000-000000000b01';
-- jornada "Salão" ter–dom 17:00/21:00/21:30/01:00 (sem segunda-feira)
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e7600000-0000-4000-8000-000000000201', 'e7600000-0000-4000-8000-00000000000a', 'Salão', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
select 'e7600000-0000-4000-8000-000000000201', d, '17:00', '21:00', '21:30', '01:00' from unnest(array[0, 2, 3, 4, 5, 6]) d;
insert into public.funcionarios (id, empresa_id, nome, cargo, data_admissao) values
  ('e7600000-0000-4000-8000-000000000301', 'e7600000-0000-4000-8000-00000000000a', 'Garçom 1', 'Garçom', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000302', 'e7600000-0000-4000-8000-00000000000a', 'Garçom 2', 'Garçom', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000303', 'e7600000-0000-4000-8000-00000000000a', 'Garçom 3', 'Garçom', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000304', 'e7600000-0000-4000-8000-00000000000a', 'Cumim 2', 'Cumim', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000305', 'e7600000-0000-4000-8000-00000000000a', 'Chef', 'Chef', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000391', 'e7600000-0000-4000-8000-00000000000b', 'Paolo', 'Garçom', '2026-01-01'),
  ('e7600000-0000-4000-8000-000000000392', 'e7600000-0000-4000-8000-00000000000b', 'Chef', 'Chef', '2026-01-01');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e7600000-0000-4000-8000-000000000201', '2026-10-01'
  from unnest(array['e7600000-0000-4000-8000-000000000301', 'e7600000-0000-4000-8000-000000000302',
                    'e7600000-0000-4000-8000-000000000303', 'e7600000-0000-4000-8000-000000000304']::uuid[]) f;

create temp table ex (nome text primary key, id uuid) on commit drop;
grant all on ex to authenticated;
create function pg_temp.dias(p_func uuid, p_mes text) returns jsonb language sql as $$
  select m -> 'dias' from jsonb_array_elements(public.escala_mes(p_mes, 'e7600000-0000-4000-8000-00000000000a') -> 'setores') s,
         jsonb_array_elements(s -> 'membros') m where (m ->> 'funcionario_id')::uuid = p_func $$;
create function pg_temp.folgas(p_func uuid, p_mes text) returns text language sql as $$
  select string_agg(right(d ->> 'data', 2), ',' order by d ->> 'data') from jsonb_array_elements(pg_temp.dias(p_func, p_mes)) d
   where d ->> 'status' = 'folga' $$;
create function pg_temp.dia(p_func uuid, p_data date) returns jsonb language sql as $$
  select d from jsonb_array_elements(pg_temp.dias(p_func, to_char(p_data, 'YYYY-MM'))) d where d ->> 'data' = p_data::text $$;
create function pg_temp.pd(p_func uuid, p_data date) returns text language sql as $$
  select situacao || '/' || previsto_minutos || '/' || alarmes_abertos from public.ponto_dias where funcionario_id = p_func and data = p_data $$;
grant execute on function pg_temp.dias(uuid, text), pg_temp.folgas(uuid, text), pg_temp.dia(uuid, date), pg_temp.pd(uuid, date) to authenticated;

select teste.ok('pré: Garçom 1 ausente na qua 11/11 (jornada) com alarme',
  pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-11') = 'ausente/450/1');
select teste.ok('pré: segunda 09/11 é folga pela jornada', pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-09') = 'folga/0/0');

-- ------------------------------------------------------------------ permissões e validações
select teste.como('es.lei.a@teste.local');
select teste.erro('leitura não configura', $$select public.escala_configurar('2026-11-02')$$, 'Sem permissão', '42501');
select teste.erro('leitura não cria setor', $$select public.escala_salvar_setor('Salão')$$, 'Sem permissão', '42501');
select teste.erro('leitura não aplica modelo', $$select public.escala_aplicar_modelo_macaw()$$, 'Sem permissão', '42501');
select teste.como('es.ger.a@teste.local');
select teste.erro('âncora não é segunda', $$select public.escala_configurar('2026-11-03')$$, 'A data-âncora deve ser uma segunda-feira', '22023');
select teste.erro('fase inválida', $$select public.escala_configurar('2026-11-02', 5000)$$, 'Fase inválida', '22023');
select public.escala_configurar('2026-11-02', 0);
insert into ex select 'salao', public.escala_salvar_setor(' Salão ', 1);
insert into ex select 'cozinha', public.escala_salvar_setor('Cozinha', 2);
select teste.erro('setor repetido', $$select public.escala_salvar_setor('salão')$$, 'Setor já existe', '23505');
select teste.erro('setor sem nome', $$select public.escala_salvar_setor('  ')$$, 'Informe o nome');
select teste.erro('folgas inválidas', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000301', '{7}')$$, 'Folgas inválidas', '22023');
select teste.erro('folgas repetidas', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000301', '{2,2}')$$, 'Folgas inválidas');
select teste.erro('caminho inválido', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000301', '{2}', null, 30::smallint)$$, 'Caminho inválido');
select teste.erro('funcionário de outra empresa', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000391', '{2}')$$, 'Funcionário de outra empresa');
select teste.erro('lista com repetido', $$select public.escala_definir_membros((select id from ex where nome = 'salao'),
  '[{"funcionario_id":"e7600000-0000-4000-8000-000000000301"},{"funcionario_id":"e7600000-0000-4000-8000-000000000301"}]')$$, 'Funcionário repetido na lista');
select teste.erro('lista inválida', $$select public.escala_definir_membros((select id from ex where nome = 'salao'), '{"x":1}')$$, 'Lista de membros inválida');

-- Salão: caminho 1 = Garçom 1 (QUA,QUI) → Garçom 2 (QUA,QUI) → Garçom 3 (QUA,QUI, chegada 18:00) → Cumim 2 (QUA,DOM)
select teste.ok('definir membros retorna 4', public.escala_definir_membros((select id from ex where nome = 'salao'), '[
  {"funcionario_id":"e7600000-0000-4000-8000-000000000301","folgas_base":[3,2],"caminho":1,"posicao":1},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000302","folgas_base":[2,3],"caminho":1,"posicao":2},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000303","folgas_base":[2,3],"chegada_padrao":"18:00","caminho":1,"posicao":3},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000304","folgas_base":[2,6],"caminho":1,"posicao":4}]') = 4);
select teste.ok('folgas ordenadas', (select folgas_base from public.escala_membros where funcionario_id = 'e7600000-0000-4000-8000-000000000301') = '{2,3}');
select teste.erro('posição ocupada', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000305', '{3}', null, 1::smallint, 2::smallint)$$,
  'Posição já ocupada no caminho', '23505');
select public.escala_salvar_membro((select id from ex where nome = 'cozinha'), 'e7600000-0000-4000-8000-000000000305', '{3}');

-- ------------------------------------------------------------------ rodízio (exemplo do adendo §S.2)
select teste.ok('Garçom 1 em nov/2026: 04,05 · 11,12 · 18,19 · 25,29', pg_temp.folgas('e7600000-0000-4000-8000-000000000301', '2026-11') = '04,05,11,12,18,19,25,29');
select teste.ok('Cumim 2 em nov/2026: 04,08 · 11,12 · 18,19 · 25,26', pg_temp.folgas('e7600000-0000-4000-8000-000000000304', '2026-11') = '04,08,11,12,18,19,25,26');
select teste.ok('01/11 (antes da âncora) = fora', pg_temp.dia('e7600000-0000-4000-8000-000000000301', '2026-11-01') ->> 'status' = 'fora');
select teste.ok('dezembro continua o rodízio (semana 4 ≡ 0, 5 ≡ 1)', pg_temp.folgas('e7600000-0000-4000-8000-000000000304', '2026-12') like '02,06,09,10,%');
select teste.ok('fev/2027: semana de 01/02 é a 13 (≡ 1) — Cumim 2 folga QUA 03 e QUI 04, trabalha DOM 07',
  pg_temp.dia('e7600000-0000-4000-8000-000000000304', '2027-02-04') ->> 'status' = 'folga'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000304', '2027-02-07') ->> 'status' = 'trabalha'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000304', '2027-02-28') ->> 'status' = 'folga');
select teste.ok('folga fixa (Chef, QUI) toda semana', pg_temp.folgas('e7600000-0000-4000-8000-000000000305', '2026-11') = '05,12,19,26');
select teste.ok('chegada padrão no dia de trabalho', pg_temp.dia('e7600000-0000-4000-8000-000000000303', '2026-11-02') ->> 'chegada' = '18:00'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000303', '2026-11-04') -> 'chegada' = 'null'::jsonb);
select teste.ok('na escala: qua 04/11 Salão 0, total 1 (Chef); seg 02/11 Salão 4',
  (select (s -> 'na_escala' ->> 3)::int from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s where s ->> 'nome' = 'Salão') = 0
  and (public.escala_mes('2026-11') -> 'na_escala' ->> 3)::int = 1
  and (select (s -> 'na_escala' ->> 1)::int from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s where s ->> 'nome' = 'Salão') = 4);
select teste.ok('escala_mes: cabeçalho e dias', (select (x ->> 'configurada', x ->> 'ancora', jsonb_array_length(x -> 'dias'), x -> 'dias' -> 1 ->> 'dia_semana', x -> 'dias' -> 0 ->> 'semana', x ->> 'pode_editar')
  = ('true', '2026-11-02', 30, '0', '-1', 'true') from public.escala_mes('2026-11') x));
select teste.ok('escala_mes: caminho na ordem das posições', (select s -> 'caminhos' -> 0 -> 'funcionarios' ->> 3 from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s where s ->> 'nome' = 'Salão')
  = 'e7600000-0000-4000-8000-000000000304');
select teste.ok('escala_mes: contagens do mês do Chef', (select (m ->> 'trabalha', m ->> 'folgas', m ->> 'folga_fixa') = ('25', '4', 'true')
  from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s, jsonb_array_elements(s -> 'membros') m where s ->> 'nome' = 'Cozinha'));
select teste.erro('mês inválido', $$select public.escala_mes('2026-13')$$, 'Mês inválido (use AAAA-MM)', '22023');
select teste.ok('escala_semana 23/11 (w3): Garçom 1 folga QUA,DOM; base QUA,QUI', (select (x ->> 'semana', m -> 'folgas_semana', m -> 'folgas_base') = ('3', '[2,6]'::jsonb, '[2,3]'::jsonb)
  from public.escala_semana('2026-11-25') x, jsonb_array_elements(x -> 'setores') s, jsonb_array_elements(s -> 'membros') m
  where m ->> 'funcionario_id' = 'e7600000-0000-4000-8000-000000000301'));
select teste.ok('escala_semana: na escala base e da semana (QUA)', (select (x -> 'na_escala_base' ->> 2, x -> 'na_escala_semana' ->> 6) = ('1', '4') from public.escala_semana('2026-11-25') x));
-- fase 1: cada semana anda uma posição a mais (semana 2 → Cumim 2: QUA 18, DOM 22; semana 3 ≡ 0: QUA 25, QUI 26)
select public.escala_configurar('2026-11-02', 1);
select teste.ok('fase 1 desloca o rodízio', pg_temp.folgas('e7600000-0000-4000-8000-000000000301', '2026-11') = '04,05,11,12,18,22,25,26');
select public.escala_salvar_setor('Salão', 1, -1, (select id from ex where nome = 'salao'));
select teste.ok('fase do setor soma com a da empresa (1 − 1 = 0)', pg_temp.folgas('e7600000-0000-4000-8000-000000000301', '2026-11') = '04,05,11,12,18,19,25,29');
select public.escala_salvar_setor('Salão', 1, 0, (select id from ex where nome = 'salao'));
select public.escala_configurar('2026-11-02', 0);

-- ------------------------------------------------------------------ ponto
select teste.ok('folga da escala (qua 11/11): não escalado, alarme resolvido', pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-11') = 'folga/0/0'
  and (select status from public.ponto_alarmes where funcionario_id = 'e7600000-0000-4000-8000-000000000301' and data = '2026-11-11' and tipo = 'sem_batida_dia_escalado') = 'resolvido');
select teste.ok('seg 09/11 trabalha pela escala: escalado com o modelo da jornada (ter), alarme sem batida',
  pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-09') = 'ausente/450/1');
-- atraso pela chegada do dia (Garçom 2, ter 10/11, chegada 18:00)
select public.escala_ajustar('e7600000-0000-4000-8000-000000000302', '2026-11-10', null, '18:00', 'chega tarde');
select public.ponto_incluir_batida('e7600000-0000-4000-8000-000000000302', t, 'teste')
  from unnest(array['2026-11-10 18:20-03', '2026-11-10 22:00-03', '2026-11-10 22:30-03', '2026-11-11 02:00-03']::timestamptz[]) t;
select teste.ok('atraso medido contra a chegada da escala (20 min)', (select (minutos, detalhe, horario_previsto) = (20, 'Entrada 18:20 (20 min de atraso)', '2026-11-10 18:00-03'::timestamptz)
  from public.ponto_alarmes where funcionario_id = 'e7600000-0000-4000-8000-000000000302' and data = '2026-11-10' and tipo = 'atraso'));
select teste.ok('dia completo, saldo pela duração da jornada', pg_temp.pd('e7600000-0000-4000-8000-000000000302', '2026-11-10') = 'completo/450/1'
  and (select saldo_minutos from public.ponto_dias where funcionario_id = 'e7600000-0000-4000-8000-000000000302' and data = '2026-11-10') = -20);
-- batida faltante com a chegada padrão (Garçom 3, ter 10/11, 18:00)
select public.ponto_incluir_batida('e7600000-0000-4000-8000-000000000303', t, 'teste')
  from unnest(array['2026-11-10 18:01-03', '2026-11-10 22:02-03', '2026-11-11 02:05-03']::timestamptz[]) t;
select teste.ok('batida faltante identificada pelos horários deslocados (volta 22:30)', (select array_agg(batida_esperada || ' ' || detalhe) from public.ponto_alarmes
  where funcionario_id = 'e7600000-0000-4000-8000-000000000303' and data = '2026-11-10' and status = 'aberto') = array['volta_intervalo Faltou a volta do intervalo (22:30)']);
select teste.ok('espelho: esperadas deslocadas para 18:00', (select esperadas -> 0 ->> 'instante' from public.ponto_espelho('e7600000-0000-4000-8000-000000000303', '2026-11-10', '2026-11-10'))::timestamptz
  = '2026-11-10 18:00-03');
select teste.ok('Chef (sem jornada) na escala: sem_escala em dia de trabalho, folga no dia de folga',
  pg_temp.pd('e7600000-0000-4000-8000-000000000305', '2026-11-11') = 'sem_escala/0/0' and pg_temp.pd('e7600000-0000-4000-8000-000000000305', '2026-11-12') = 'folga/0/0');

-- ------------------------------------------------------------------ ajustes
select teste.erro('status inválido', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-11', 'falta')$$, 'Status inválido', '22023');
select teste.erro('dia fora da escala', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-01', 'folga')$$, 'Dia fora da escala', '22023');
select teste.erro('data fora do limite', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-09-01', 'folga')$$, 'Data fora do limite', '22023');
select teste.erro('funcionário de outra empresa', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000391', '2026-11-11', 'folga')$$, 'Sem permissão', '42501');
select teste.ok('ajustar trabalha num dia de folga: objeto-dia', (select (x ->> 'status', x ->> 'origem', x ->> 'ajustado', x ->> 'motivo') = ('trabalha', 'ajuste', 'true', 'cobrir')
  from public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-11', 'trabalha', null, 'cobrir') x));
select teste.ok('reapura: 11/11 volta a ausente com o alarme reaberto', pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-11') = 'ausente/450/1'
  and (select status from public.ponto_alarmes where funcionario_id = 'e7600000-0000-4000-8000-000000000301' and data = '2026-11-11' and tipo = 'sem_batida_dia_escalado') = 'aberto');
select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-11', 'auto');
select teste.ok('automático apaga o ajuste e volta a folga', pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-11') = 'folga/0/0'
  and not exists (select 1 from public.escala_ajustes where funcionario_id = 'e7600000-0000-4000-8000-000000000301' and data = '2026-11-11'));
select teste.ok('ajuste de folga na seg 09/11 tira o alarme', (public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-09', 'folga') ->> 'status') = 'folga'
  and pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-09') = 'folga/0/0');

-- ------------------------------------------------------------------ férias → abono
select teste.ok('férias em período (Cumim 2, 09–10/11)', public.escala_ajustar_periodo('e7600000-0000-4000-8000-000000000304', '2026-11-09', '2026-11-10', 'ferias', 'Férias de 2 dias') = 2);
select teste.ok('um abono ferias por dia, ligado ao ajuste', (select array_agg(data || '/' || tipo || '/' || motivo order by data) from public.ponto_abonos
  where funcionario_id = 'e7600000-0000-4000-8000-000000000304' and escala_ajuste_id is not null)
  = array['2026-11-09/ferias/Férias (escala): Férias de 2 dias', '2026-11-10/ferias/Férias (escala): Férias de 2 dias']);
select teste.ok('dia de férias: abonado, sem alarme', pg_temp.pd('e7600000-0000-4000-8000-000000000304', '2026-11-09') = 'abonado/0/0'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000304', '2026-11-09') ->> 'status' = 'ferias');
select teste.erro('abonar dia de férias da escala', $$select public.ponto_abonar('2026-11-10', '2026-11-10', 'folga', null, 'e7600000-0000-4000-8000-000000000304')$$,
  'Dia com férias na escala: altere pela escala', '22023');
select teste.erro('remover abono da escala', $$select public.ponto_remover_abono((select id from public.ponto_abonos where funcionario_id = 'e7600000-0000-4000-8000-000000000304' and data = '2026-11-10'))$$,
  'Dia com férias na escala: altere pela escala');
select teste.erro('suspensão em dia de férias da escala', $$select public.ocorrencia_criar('e7600000-0000-4000-8000-000000000304', 'suspensao', '2026-11-09', 'x', null, 1)$$,
  'Já existe abono para o funcionário em 09/11/2026');
select public.ponto_abonar('2026-11-12', '2026-11-12', 'atestado', 'médico', 'e7600000-0000-4000-8000-000000000302');
select teste.erro('férias em dia com abono manual', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000302', '2026-11-12', 'ferias')$$,
  'Já existe abono para o funcionário em 12/11/2026', '22023');
select public.escala_ajustar('e7600000-0000-4000-8000-000000000304', '2026-11-10', null);
select teste.ok('voltar a automático remove o abono e reapura', (select count(*) from public.ponto_abonos where funcionario_id = 'e7600000-0000-4000-8000-000000000304') = 1
  and pg_temp.pd('e7600000-0000-4000-8000-000000000304', '2026-11-10') = 'ausente/450/1');
select teste.ok('escala_mes conta férias', (select (m ->> 'ferias')::int from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s, jsonb_array_elements(s -> 'membros') m
  where m ->> 'funcionario_id' = 'e7600000-0000-4000-8000-000000000304') = 1);

-- ------------------------------------------------------------------ troca
select teste.erro('troca sem o outro', $$select public.escala_trocar('e7600000-0000-4000-8000-000000000301', '2026-11-22')$$, 'Informe o outro funcionário ou o outro dia', '22023');
select teste.erro('troca com férias', $$select public.escala_trocar('e7600000-0000-4000-8000-000000000304', '2026-11-09', 'e7600000-0000-4000-8000-000000000301')$$, 'Não é possível trocar dia de férias');
-- dom 22/11: Garçom 1 trabalha, Garçom 2 folga → trocam
select teste.ok('troca A↔B no mesmo dia', (select jsonb_agg(x ->> 'status' order by x ->> 'funcionario_id') from jsonb_array_elements(
  public.escala_trocar('e7600000-0000-4000-8000-000000000301', '2026-11-22', 'e7600000-0000-4000-8000-000000000302')) x) = '["folga", "trabalha"]'::jsonb);
select teste.ok('troca grava ajustes com motivo padrão', (select array_agg(status || '/' || motivo order by funcionario_id) from public.escala_ajustes where data = '2026-11-22')
  = array['folga/Troca de folga', 'trabalha/Troca de folga']);
select public.escala_trocar('e7600000-0000-4000-8000-000000000302', '2026-11-22', 'e7600000-0000-4000-8000-000000000301');
select teste.ok('trocar de volta = automático (ajustes apagados)', not exists (select 1 from public.escala_ajustes where data = '2026-11-22'));
-- dois dias entre duas pessoas: qua 25/11 (os dois folgam) e qui 26/11 (G1 trabalha, G3 folga)
select public.escala_trocar('e7600000-0000-4000-8000-000000000301', '2026-11-25', 'e7600000-0000-4000-8000-000000000303', '2026-11-26', 'combinado');
select teste.ok('troca em dois dias', true  and pg_temp.dia('e7600000-0000-4000-8000-000000000301', '2026-11-25') ->> 'status' = 'folga'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000303', '2026-11-25') ->> 'status' = 'folga'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000301', '2026-11-26') ->> 'status' = 'folga'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000303', '2026-11-26') ->> 'status' = 'trabalha'
  and pg_temp.dia('e7600000-0000-4000-8000-000000000303', '2026-11-26') ->> 'motivo' = 'combinado'
  and not exists (select 1 from public.escala_ajustes where data = '2026-11-25'));
-- a mesma pessoa muda a folga de dia (dom 29 → sex 27)
select public.escala_trocar('e7600000-0000-4000-8000-000000000301', '2026-11-29', null, '2026-11-27');
select teste.ok('mover a própria folga', pg_temp.folgas('e7600000-0000-4000-8000-000000000301', '2026-11') = '04,05,09,11,12,18,19,25,26,27');

-- ------------------------------------------------------------------ leitura e isolamento
select teste.como('es.lei.a@teste.local');
select teste.ok('leitura vê a escala do mês, sem motivo e sem editar', (select (x ->> 'pode_editar') = 'false' from public.escala_mes('2026-11') x)
  and pg_temp.dia('e7600000-0000-4000-8000-000000000301', '2026-11-27') -> 'motivo' = 'null'::jsonb
  and pg_temp.dia('e7600000-0000-4000-8000-000000000301', '2026-11-27') ->> 'status' = 'folga');
select teste.ok('leitura vê setores/membros mas não a tabela de ajustes',
  teste.contar('select 1 from public.escala_membros') = 5 and teste.contar('select 1 from public.escala_ajustes') = 0);
select teste.ok('leitura vê a semana', (public.escala_semana() ->> 'semana') = '1');
select teste.erro('leitura não ajusta', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-20', 'folga')$$, 'Sem permissão', '42501');
select teste.erro('leitura não troca', $$select public.escala_trocar('e7600000-0000-4000-8000-000000000301', '2026-11-20', 'e7600000-0000-4000-8000-000000000302')$$, 'Sem permissão');
select teste.como('es.adm.b@teste.local');
select teste.erro('B não lê a escala de A', $$select public.escala_mes('2026-11', 'e7600000-0000-4000-8000-00000000000a')$$, 'Sem permissão', '42501');
select teste.erro('B não ajusta funcionário de A', $$select public.escala_ajustar('e7600000-0000-4000-8000-000000000301', '2026-11-20', 'folga')$$, 'Sem permissão');
select teste.erro('B não põe funcionário no setor de A', $$select public.escala_salvar_membro((select id from ex where nome = 'salao'), 'e7600000-0000-4000-8000-000000000391')$$, 'Sem permissão');
select teste.erro('B não exclui setor de A', $$select public.escala_excluir_setor((select id from ex where nome = 'salao'))$$, 'Sem permissão');
select teste.ok('B não enxerga linhas de A', teste.contar('select 1 from public.escala_membros') = 0 and teste.contar('select 1 from public.escala_setores') = 0
  and teste.contar('select 1 from public.escala_config') = 0);
select teste.ok('escala de B ainda não configurada', (select (x ->> 'configurada', jsonb_array_length(x -> 'setores')) = ('false', 0) from public.escala_mes('2026-11') x));

-- ------------------------------------------------------------------ modelo Macaw (empresa B vazia, sem ponto) e adicionar funcionário
select teste.erro('modelo: âncora não é segunda', $$select public.escala_aplicar_modelo_macaw(null, '2026-11-04')$$, 'A data-âncora deve ser uma segunda-feira');
select teste.ok('modelo Macaw: 6 setores, 33 posições, 32 funcionários criados (o Chef já existia)',
  public.escala_aplicar_modelo_macaw(null, '2026-11-02') = '{"ancora": "2026-11-02", "setores": 6, "membros": 33, "funcionarios_criados": 32}'::jsonb);
select teste.ok('modelo é idempotente', public.escala_aplicar_modelo_macaw() = '{"ancora": "2026-11-02", "setores": 0, "membros": 0, "funcionarios_criados": 0}'::jsonb);
select teste.ok('Chef existente reaproveitado com folga fixa QUI', (select (m.caminho, m.folgas_base) is not distinct from (null::smallint, '{3}'::smallint[])
  from public.escala_membros m where m.funcionario_id = 'e7600000-0000-4000-8000-000000000392'));
select teste.ok('setores na ordem do modelo', (select array_agg(nome order by ordem) from public.escala_setores) = array['Salão', 'Maître', 'Areia', 'Bar', 'ASG', 'Cozinha']);
select teste.ok('caminho do Maître: Maître 2 → Maître 1 → Recepção → Maître 3; Gerente folga fixa',
  (select s -> 'caminhos' -> 0 -> 'nomes' from jsonb_array_elements(public.escala_semana('2026-11-02') -> 'setores') s where s ->> 'nome' = 'Maître')
    = '["Maître 2", "Maître 1", "Recepção", "Maître 3"]'::jsonb
  and (select m ->> 'folga_fixa' from jsonb_array_elements(public.escala_semana('2026-11-02') -> 'setores') s, jsonb_array_elements(s -> 'membros') m
        where m ->> 'nome' = 'Gerente') = 'true');
select teste.ok('dois caminhos na Cozinha e no Salão', (select count(*) from jsonb_array_elements(public.escala_semana() -> 'setores') s, jsonb_array_elements(s -> 'caminhos') c) = 8);
select teste.ok('funcionário provisório: cargo = função, 0 pontos, sem jornada',
  (select (cargo, pontos_comissao) = ('Cumim'::text, 0::numeric) from public.funcionarios where nome = 'Cumim 2')
  and not exists (select 1 from public.funcionario_jornadas fj join public.funcionarios f on f.id = fj.funcionario_id where f.nome = 'Cumim 2'));
select teste.ok('mês da Macaw funciona sem batidas: na escala do sáb 07/11 = 33 − folgas', (public.escala_mes('2026-11') -> 'na_escala' ->> 6)::int > 20);
update public.funcionarios set nome = 'João Garçom' where nome = 'Garçom 1';
select teste.ok('renomear e reaplicar não duplica', (public.escala_aplicar_modelo_macaw() ->> 'funcionarios_criados') = '0'
  and teste.contar('select 1 from public.funcionarios') = 34);
select teste.ok('sem ponto: nenhum alarme para os provisórios', teste.contar('select 1 from public.ponto_alarmes') = 0);
insert into ex select 'bar5', public.escala_adicionar_funcionario((select id from public.escala_setores where nome = 'Bar'), ' Bar 5 ', 'Bar', '{2,1}', '19:00', 1::smallint);
select teste.ok('adicionar funcionário direto no setor', (select (f.nome, f.cargo, m.folgas_base, m.chegada_padrao, m.caminho) is not distinct from
  ('Bar 5'::text, 'Bar'::text, '{1,2}'::smallint[], '19:00'::time, 1::smallint)
  from public.funcionarios f join public.escala_membros m on m.funcionario_id = f.id
  where f.id = (select id from ex where nome = 'bar5')));
select teste.ok('adicionado vai para a próxima posição do caminho', (select posicao from public.escala_membros m join public.funcionarios f on f.id = m.funcionario_id where f.nome = 'Bar 5') = 5);
select teste.erro('adicionar sem nome', $$select public.escala_adicionar_funcionario((select id from public.escala_setores where nome = 'Bar'), '')$$, 'Informe o nome');

-- empresa recém-criada e VAZIA (criar_minha_empresa, sem funcionários nem ponto) — caso real Macaw Camboinhas.
-- statement_timeout curto: uma regressão de desempenho (ex.: JIT a cada apuração) falha aqui em vez de travar.
select teste.como_dono();
insert into auth.users (id, email, raw_user_meta_data) values ('e7600000-0000-4000-8000-000000000c01', 'es.nova@teste.local', '{"nome":"Dona Macaw"}');
select teste.como('es.nova@teste.local');
select public.criar_minha_empresa('Macaw Teste');
set local statement_timeout = '20s';
select teste.ok('empresa vazia: modelo Macaw cria tudo e retorna', (public.escala_aplicar_modelo_macaw() - 'ancora')
  = '{"setores": 6, "membros": 33, "funcionarios_criados": 33}'::jsonb);
select teste.ok('empresa vazia: reaplicar com âncora antiga (reapura 62 dias) retorna', (public.escala_aplicar_modelo_macaw(null, '2026-09-14') ->> 'membros') = '0');
select teste.ok('empresa vazia: escala do mês com 33 membros', (select sum(jsonb_array_length(s -> 'membros')) from jsonb_array_elements(public.escala_mes('2026-11') -> 'setores') s) = 33);
set local statement_timeout = 0;

-- ------------------------------------------------------------------ remover membro / reordenar
select teste.como('es.ger.a@teste.local');
select public.escala_definir_membros((select id from ex where nome = 'salao'), '[
  {"funcionario_id":"e7600000-0000-4000-8000-000000000302","folgas_base":[2,3],"caminho":1,"posicao":1},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000301","folgas_base":[2,3],"caminho":1,"posicao":2},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000303","folgas_base":[2,3],"chegada_padrao":"18:00","caminho":1,"posicao":3},
  {"funcionario_id":"e7600000-0000-4000-8000-000000000304","folgas_base":[2,6],"caminho":1,"posicao":4}]');
select teste.ok('reordenar posições sem conflito (ajustes mantidos)', (select posicao from public.escala_membros where funcionario_id = 'e7600000-0000-4000-8000-000000000301') = 2
  and exists (select 1 from public.escala_ajustes where funcionario_id = 'e7600000-0000-4000-8000-000000000301' and data = '2026-11-27'));
select public.escala_remover_membro('e7600000-0000-4000-8000-000000000301');
select teste.ok('remover da escala: ajustes apagados e ponto volta à jornada', not exists (select 1 from public.escala_ajustes where funcionario_id = 'e7600000-0000-4000-8000-000000000301')
  and pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-11') = 'ausente/450/1'
  and pg_temp.pd('e7600000-0000-4000-8000-000000000301', '2026-11-09') = 'folga/0/0');
select teste.erro('remover quem não está', $$select public.escala_remover_membro('e7600000-0000-4000-8000-000000000301')$$, 'Funcionário fora da escala', '22023');
select public.escala_configurar('2026-11-16');
select teste.ok('mudar a âncora apaga ajustes anteriores (e o abono de férias)', not exists (select 1 from public.ponto_abonos where escala_ajuste_id is not null)
  and pg_temp.dia('e7600000-0000-4000-8000-000000000304', '2026-11-15') ->> 'status' = 'fora'
  and pg_temp.pd('e7600000-0000-4000-8000-000000000304', '2026-11-09') = 'folga/0/0');
select public.escala_excluir_setor((select id from ex where nome = 'salao'));
select teste.ok('excluir setor tira todos da escala', teste.contar('select 1 from public.escala_membros') = 1);
rollback;
