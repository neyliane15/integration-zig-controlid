-- 94_revisao2.sql (revisão 2) — achados da segunda revisão independente.
--   V2-03 dia_de_trabalho / dia_de_trabalho_instante deixaram de ser [api] (revelavam fuso/virada de outra empresa pelo id)
--   V2-05 envio ao Control iD: depois de enviar os horários, os funcionários liberados são reenviados por um pedido automático
--   V2-07 batida manual de anos atrás e lançamento de banco de horas absurdo são recusados
--   V2-02 cargas simultâneas da Zig no mesmo dia: trava consultiva por (tabela, empresa, loja, dia) — o teste de concorrência
--         de verdade está em n8n/cenario-revisao2.test.mjs (precisa de duas conexões); aqui conferimos a trava no código.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- ------------------------------------------------------------------- V2-03
select teste.como('b1.gerente1@teste.local');
select teste.erro('authenticated não chama dia_de_trabalho (fuso de outra empresa pelo id)',
  $$select public.dia_de_trabalho('2026-10-05 07:30:00Z', 'c1000000-0000-4000-8000-0000000000e2')$$, 'permission denied');
select teste.erro('authenticated não chama dia_de_trabalho_instante',
  $$select public.dia_de_trabalho_instante('2026-10-05', '01:00', 'c1000000-0000-4000-8000-0000000000e2')$$, 'permission denied');
select teste.ok('dia_de_trabalho_atual da própria empresa continua (front)', public.dia_de_trabalho_atual() = '2026-10-06');
select teste.erro('dia_de_trabalho_atual de outra empresa: sem permissão',
  $$select public.dia_de_trabalho_atual('c1000000-0000-4000-8000-0000000000e2')$$, 'Sem permissão', '42501');
-- os gatilhos que usam dia_de_trabalho continuam funcionando para o usuário (security definer)
select teste.passa('gerente inclui batida (gatilho calcula o dia de trabalho)',
  $$select public.ponto_incluir_batida('c1000000-0000-4000-8000-0000000001a1', '2026-10-06 01:30:00-03', 'teste')$$);
select teste.ok('batida da madrugada no dia anterior',
  (select data_trabalho = '2026-10-05' from public.ponto_batidas where funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'
     and instante = '2026-10-06 01:30:00-03'));
select teste.passa('gerente cadastra funcionário (gatilho de pontos usa o dia de trabalho)',
  $$insert into public.funcionarios (empresa_id, nome, pontos_comissao) values ('c1000000-0000-4000-8000-0000000000e1', 'Novo V2', 3)$$);

-- ------------------------------------------------------------------- V2-07
select teste.erro('batida manual de mais de 1 ano atrás é recusada',
  $$select public.ponto_incluir_batida('c1000000-0000-4000-8000-0000000001a1', '1926-10-05 20:00:00-03', 'digitou errado')$$,
  'Horário muito antigo', '22023');
select teste.passa('batida de 11 meses atrás ainda é aceita',
  $$select public.ponto_incluir_batida('c1000000-0000-4000-8000-0000000001a1', '2025-11-10 20:00:00-03', 'acerto antigo')$$);
select teste.erro('lançamento de banco de horas absurdo é recusado',
  $$select public.banco_horas_lancar('c1000000-0000-4000-8000-0000000001a1', '2026-10-01', 'ajuste', 2147483647, 'x')$$,
  'Minutos fora do limite', '22023');
select teste.erro('lançamento negativo absurdo também',
  $$select public.banco_horas_lancar('c1000000-0000-4000-8000-0000000001a1', '2026-10-01', 'ajuste', -100001, 'x')$$,
  'Minutos fora do limite', '22023');
select teste.passa('lançamento no limite é aceito',
  $$select public.banco_horas_lancar('c1000000-0000-4000-8000-0000000001a1', '2026-10-01', 'ajuste', -100000, 'x')$$);

-- ------------------------------------------------------------------- V2-05
select teste.como_dono();
update public.integracoes set parametros = parametros || '{"envio":{"ativo":true}}' where id = 'c1000000-0000-4000-8000-000000000101';
insert into public.controlid_horarios (id, empresa_id, nome) values
  ('c1000000-0000-4000-8000-000000000594', 'c1000000-0000-4000-8000-0000000000e1', 'Noite V2');
insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim) values
  ('c1000000-0000-4000-8000-000000000594', 1, '18:00', '23:59:59');
insert into public.funcionario_horarios (funcionario_id, horario_id) values
  ('c1000000-0000-4000-8000-0000000001a1', 'c1000000-0000-4000-8000-000000000594');
select teste.ok('com horário ainda não enviado o funcionário aguarda',
  (select status = 'aguardando' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
-- o N8N envia os horários e registra o resultado
select teste.como_servico();
select public.ingestao_controlid_envio_resultado(e.id, e.versao, 'enviado', null, null,
         jsonb_build_object('c1000000-0000-4000-8000-000000000594', jsonb_build_object('access_rule_id', 10, 'time_zone_id', 20)))
  from public.controlid_envios e where e.integracao_id = 'c1000000-0000-4000-8000-000000000101' and e.alvo = 'horarios';
select teste.ok('funcionário liberado (pendente) depois dos horários',
  (select status = 'pendente' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('pedido automático de envio na fila (próxima rodada em ~1 min, não no agendador)',
  (select count(*) = 1 from public.sync_solicitacoes
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and status = 'pendente' and escopo = 'exportar_funcionarios'));
-- registrar de novo (retentativa) não duplica o pedido
select public.ingestao_controlid_envio_resultado(e.id, e.versao, 'enviado', null, null, e.mapa_remoto)
  from public.controlid_envios e where e.integracao_id = 'c1000000-0000-4000-8000-000000000101' and e.alvo = 'horarios';
select teste.ok('sem pedido duplicado',
  (select count(*) = 1 from public.sync_solicitacoes
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and status = 'pendente'));

-- ------------------------------------------------------------------- V2-02
select teste.como_dono();
select teste.ok('ingestões da Zig que substituem o dia usam trava consultiva (4 funções)',
  (select count(*) = 4 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('ingestao_zig_saida_produtos', 'ingestao_zig_faturamento', 'ingestao_zig_faturamento_bandeiras', 'ingestao_zig_compradores')
      and p.prosrc ~ 'pg_advisory_xact_lock'
      and position('pg_advisory_xact_lock' in p.prosrc) < position('delete from' in p.prosrc)));
rollback;
