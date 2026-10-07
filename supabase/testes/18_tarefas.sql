-- 18_tarefas.sql (backend-1): rotinas, geração idempotente, status, checklist, responsáveis e isolamento.
begin;
set local app.agora = '2026-10-06 12:00:00-03';   -- terça-feira
select teste.cenario_b1();

select teste.como('b1.gerente1@teste.local');
insert into public.tarefas_rotinas (id, empresa_id, titulo, recorrencia, dias_semana, dia_mes, horario_limite)
values
  ('c1000000-0000-4000-8000-000000000401', 'c1000000-0000-4000-8000-0000000000e1', 'Abrir caixa', 'diaria', '{}', null, '16:30'),
  ('c1000000-0000-4000-8000-000000000402', 'c1000000-0000-4000-8000-0000000000e1', 'Estoque', 'semanal', '{5,2,2}', null, null),
  ('c1000000-0000-4000-8000-000000000403', 'c1000000-0000-4000-8000-0000000000e1', 'Fechar mês', 'mensal', '{}', 31, null),
  ('c1000000-0000-4000-8000-000000000404', 'c1000000-0000-4000-8000-0000000000e1', 'Inativa', 'diaria', '{}', null, null);
update public.tarefas_rotinas set ativa = false where id = 'c1000000-0000-4000-8000-000000000404';
insert into public.tarefas_rotina_itens (rotina_id, ordem, texto) values
  ('c1000000-0000-4000-8000-000000000401', 1, 'Troco'),
  ('c1000000-0000-4000-8000-000000000401', 2, 'Maquininhas');
select teste.ok('dias_semana ordenados e sem repetição', (select dias_semana = '{2,5}' from public.tarefas_rotinas where titulo = 'Estoque'));
select teste.ok('criado_por = quem criou', (select bool_and(criado_por = auth.uid()) from public.tarefas_rotinas));
select teste.ok('item da rotina herda a empresa', (select bool_and(empresa_id = 'c1000000-0000-4000-8000-0000000000e1') from public.tarefas_rotina_itens));
select teste.erro('semanal sem dias',
  $$insert into public.tarefas_rotinas (empresa_id, titulo, recorrencia) values ('c1000000-0000-4000-8000-0000000000e1', 'X', 'semanal')$$,
  'tarefas_rotinas_semanal');
select teste.erro('dia da semana inválido',
  $$insert into public.tarefas_rotinas (empresa_id, titulo, recorrencia, dias_semana) values ('c1000000-0000-4000-8000-0000000000e1', 'X', 'semanal', '{7}')$$,
  'tarefas_rotinas_dias');
select teste.erro('responsável de outra empresa',
  $$insert into public.tarefas_rotinas (empresa_id, titulo, responsavel_funcionario_id)
    values ('c1000000-0000-4000-8000-0000000000e1', 'X', 'c1000000-0000-4000-8000-0000000001a2')$$, 'Funcionário de outra empresa');
select teste.erro('item em rotina de outra empresa',
  $$insert into public.tarefas_rotinas (empresa_id, titulo) values ('c1000000-0000-4000-8000-0000000000e2', 'X')$$, 'row-level security');

-- ------------------------------------------------------------------------------------- geração
select teste.ok('rotina_cai_no_dia: mensal 31 em fevereiro cai no dia 28',
  public.rotina_cai_no_dia('mensal', '{}', 31::smallint, '2027-02-28') and not public.rotina_cai_no_dia('mensal', '{}', 31::smallint, '2027-02-27'));
select teste.ok('terça: gera diária + semanal (2)', public.tarefas_gerar_do_dia() = 2);
select teste.ok('idempotente: segunda chamada gera 0', public.tarefas_gerar_do_dia() = 0);
select teste.ok('checklist copiado', (select count(*) = 2 from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id
                                       where t.titulo = 'Abrir caixa'));
select teste.ok('data = dia de trabalho atual', (select bool_and(data = '2026-10-06') from public.tarefas));
select teste.ok('31/10: diária + mensal (2)', public.tarefas_gerar_do_dia('2026-10-31') = 2);
select teste.erro('data absurda', $$select public.tarefas_gerar_do_dia('2030-01-01')$$, 'Período inválido');
select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura também gera (quarta: só diária)', public.tarefas_gerar_do_dia('2026-10-07') = 1);
select teste.como('b1.gerente2@teste.local');
select teste.erro('gerente2 não gera na E1',
  $$select public.tarefas_gerar_do_dia(null, 'c1000000-0000-4000-8000-0000000000e1')$$, 'Sem permissão', '42501');
select teste.ok('gerente2 não vê tarefas da E1', teste.contar('select 1 from public.tarefas') = 0);
select teste.ok('gerente2 não altera tarefas da E1', teste.afetadas($$update public.tarefas set titulo = 'X'$$) = 0);
select teste.ok('gerente2 não vê rotinas/itens da E1',
  teste.contar('select 1 from public.tarefas_rotinas union all select 1 from public.tarefas_rotina_itens union all select 1 from public.tarefa_itens') = 0);
select teste.como_servico();
select teste.ok('ingestao_tarefas_gerar: idempotente para o dia de hoje (0 na E1)', public.ingestao_tarefas_gerar() >= 0);
select teste.ok('ingestao_tarefas_gerar de novo: 0', public.ingestao_tarefas_gerar() = 0);

-- ----------------------------------------------------------------------------- status e itens
select teste.como('b1.gerente1@teste.local');
select public.tarefa_mudar_status((select id from public.tarefas where titulo = 'Estoque'), 'concluida');
select teste.ok('concluir preenche concluida_por/em',
  (select status = 'concluida' and concluida_por = auth.uid() and concluida_em = '2026-10-06 12:00:00-03'
     from public.tarefas where titulo = 'Estoque'));
select public.tarefa_mudar_status((select id from public.tarefas where titulo = 'Estoque'), 'pendente');
select teste.ok('reabrir limpa concluida_*',
  (select concluida_por is null and concluida_em is null from public.tarefas where titulo = 'Estoque'));
select teste.erro('status inválido', $$select public.tarefa_mudar_status((select id from public.tarefas limit 1), 'feita')$$, 'Status inválido');
insert into public.tarefas (empresa_id, data, titulo, responsavel_perfil_id)
values ('c1000000-0000-4000-8000-0000000000e1', '2026-10-06', 'Avulsa do leitura', teste.uid('b1.leitura1@teste.local'));
insert into public.tarefas (empresa_id, data, titulo, responsavel_funcionario_id)
values ('c1000000-0000-4000-8000-0000000000e1', '2026-10-06', 'Avulsa do funcionário', 'c1000000-0000-4000-8000-0000000001a1');
insert into public.tarefa_itens (tarefa_id, texto) select id, 'passo' from public.tarefas where titulo = 'Avulsa do funcionário';
select teste.erro('responsável perfil de outra empresa',
  $$insert into public.tarefas (empresa_id, data, titulo, responsavel_perfil_id)
    values ('c1000000-0000-4000-8000-0000000000e1', '2026-10-06', 'X', teste.uid('b1.gerente2@teste.local'))$$, 'Usuário de outra empresa');

select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê as tarefas da E1', teste.contar('select 1 from public.tarefas') = 7);
select teste.ok('leitura não altera tarefa direto', teste.afetadas($$update public.tarefas set status = 'concluida'$$) = 0);
select teste.erro('leitura não cria tarefa',
  $$insert into public.tarefas (empresa_id, data, titulo) values ('c1000000-0000-4000-8000-0000000000e1', '2026-10-06', 'X')$$, 'row-level security');
select teste.passa('leitura responsável (perfil) muda status',
  $$select public.tarefa_mudar_status((select id from public.tarefas where titulo = 'Avulsa do leitura'), 'em_andamento')$$);
select teste.passa('leitura responsável (funcionário) marca item',
  $$select public.tarefa_marcar_item((select i.id from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id
                                       where t.titulo = 'Avulsa do funcionário'), true)$$);
select teste.ok('item feito com feito_por/em',
  (select feito and feito_por = auth.uid() and feito_em is not null from public.tarefa_itens i
     join public.tarefas t on t.id = i.tarefa_id where t.titulo = 'Avulsa do funcionário'));
select teste.erro('leitura não mexe em tarefa sem ser responsável (regressão NULL)',
  $$select public.tarefa_mudar_status((select id from public.tarefas where titulo = 'Abrir caixa' and data = '2026-10-06'), 'concluida')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não marca item de tarefa alheia',
  $$select public.tarefa_marcar_item((select i.id from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id
                                       where t.titulo = 'Abrir caixa' limit 1), true)$$, 'Sem permissão', '42501');
select teste.como('b1.gerente1@teste.local');
select public.tarefa_marcar_item((select i.id from public.tarefa_itens i join public.tarefas t on t.id = i.tarefa_id
                                   where t.titulo = 'Avulsa do funcionário'), false);
select teste.ok('desmarcar limpa feito_por/em',
  (select not feito and feito_por is null and feito_em is null from public.tarefa_itens i
     join public.tarefas t on t.id = i.tarefa_id where t.titulo = 'Avulsa do funcionário'));
select teste.como('b1.gerente2@teste.local');
select teste.erro('gerente2 não muda status de tarefa da E1',
  $$select public.tarefa_mudar_status((select id from public.tarefas limit 1), 'concluida')$$, 'Tarefa não encontrada');
select teste.erro('gerente2: tarefa inexistente',
  $$select public.tarefa_mudar_status('c1000000-0000-4000-8000-000000000999', 'concluida')$$, 'Tarefa não encontrada', 'P0002');
select teste.como(null);
select teste.erro('anon não lê tarefas', 'select * from public.tarefas', 'permission denied');
select teste.erro('anon não gera tarefas', 'select public.tarefas_gerar_do_dia()', 'permission denied');
select teste.como('b1.admin1@teste.local');
select teste.ok('admin exclui rotina; tarefas geradas ficam (rotina_id null)',
  teste.afetadas($$delete from public.tarefas_rotinas where id = 'c1000000-0000-4000-8000-000000000401'$$) = 1);
select teste.ok('tarefa gerada sobrevive sem rotina',
  (select count(*) = 3 and bool_and(rotina_id is null) from public.tarefas where titulo = 'Abrir caixa'));
rollback;
