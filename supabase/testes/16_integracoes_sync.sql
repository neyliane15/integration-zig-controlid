-- 16_integracoes_sync.sql (backend-1): integrações, segredos, usuários Control iD, fila e execuções.
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- ------------------------------------------------------------------------------ integracoes
select teste.ok('parâmetros padrão do acesso preenchidos',
  (select parametros @> '{"modelo":"iDFace","eventos_validos":[7],"relogio_em_hora_local":true,"dias_retroativos":2}'
     from public.integracoes where id = 'c1000000-0000-4000-8000-000000000101'));
select teste.como('b1.admin1@teste.local');
insert into public.integracoes (empresa_id, tipo, nome, parametros, cursor, ultimo_status)
values ('c1000000-0000-4000-8000-0000000000e1', 'zig', 'Zig', '{"rede":"r1"}', '{"ultimo_dia":"2026-01-01"}', 'sucesso');
select teste.ok('admin cria Zig; cursor/ultimo_* ignorados; padrão mesclado',
  (select cursor = '{}' and ultimo_status is null and parametros = '{"rede":"r1","dias_retroativos":2}'
     from public.integracoes where tipo = 'zig' and empresa_id = 'c1000000-0000-4000-8000-0000000000e1'));
select teste.erro('só uma Zig por empresa',
  $$insert into public.integracoes (empresa_id, tipo, nome) values ('c1000000-0000-4000-8000-0000000000e1', 'zig', 'Zig 2')$$,
  'integracoes_zig_uk');
update public.integracoes set nome = 'Porta da frente', tipo = 'zig', cursor = '{"ultimo_id":"999"}', ultimo_erro = 'x',
       intervalo_minutos = 30
 where id = 'c1000000-0000-4000-8000-000000000101';
select teste.ok('admin altera nome/intervalo; tipo, cursor e ultimo_* preservados',
  (select nome = 'Porta da frente' and tipo = 'controlid_acesso' and cursor = '{}' and ultimo_erro is null and intervalo_minutos = 30
     from public.integracoes where id = 'c1000000-0000-4000-8000-000000000101'));
select teste.erro('intervalo mínimo 15',
  $$update public.integracoes set intervalo_minutos = 5 where id = 'c1000000-0000-4000-8000-000000000101'$$, 'intervalo_minutos');
select teste.erro('admin não cria integração em outra empresa',
  $$insert into public.integracoes (empresa_id, tipo, nome) values ('c1000000-0000-4000-8000-0000000000e2', 'zig', 'Z')$$,
  'row-level security');
select teste.ok('admin1 vê só integrações da E1 (3)', teste.contar('select 1 from public.integracoes') = 3);

select teste.como('b1.gerente1@teste.local');
select teste.ok('gerente vê integrações', teste.contar('select 1 from public.integracoes') = 3);
select teste.ok('gerente não altera integração', teste.afetadas($$update public.integracoes set nome = 'X'$$) = 0);
select teste.erro('gerente não cria integração',
  $$insert into public.integracoes (empresa_id, tipo, nome) values ('c1000000-0000-4000-8000-0000000000e1', 'controlid_rep', 'R')$$,
  'row-level security');
select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura não vê integrações', teste.contar('select 1 from public.integracoes') = 0);
select teste.ok('leitura não vê controlid_usuarios', teste.contar('select 1 from public.controlid_usuarios') = 0);

-- --------------------------------------------------------------------------------- segredos
select teste.como('b1.admin1@teste.local');
select teste.erro('admin não lê integracoes_segredos', 'select * from public.integracoes_segredos', 'permission denied');
select teste.erro('admin não escreve integracoes_segredos direto',
  $$update public.integracoes_segredos set segredos = '{}'$$, 'permission denied');
select teste.erro('segredos não aparecem em ingestao_integracao_config para authenticated',
  $$select public.ingestao_integracao_config('c1000000-0000-4000-8000-000000000101')$$, 'permission denied');
select teste.passa('admin define segredos (merge)',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000101', '{"senha":"nova","login":null}')$$);
select teste.ok('preenchidos: url, senha (login removido)',
  public.integracao_segredos_preenchidos('c1000000-0000-4000-8000-000000000101') = array['senha', 'url']);
select teste.passa('string vazia remove', $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000101', '{"senha":""}')$$);
select teste.ok('preenchidos: só url', public.integracao_segredos_preenchidos('c1000000-0000-4000-8000-000000000101') = array['url']);
select teste.erro('chave não permitida para o tipo',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000101', '{"token":"x"}')$$,
  'Segredo inválido para este tipo de integração', '22023');
select teste.erro('valor não-string',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000101', '{"url":123}')$$,
  'Segredo inválido para este tipo de integração', '22023');
select teste.passa('segredos de integração sem linha ainda',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000103', '{"url":"https://10.0.0.9","login":"a","senha":"b"}')$$);
select teste.erro('admin não define segredos na E2',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000102', '{"senha":"x"}')$$, 'Sem permissão', '42501');
select teste.erro('admin não consulta preenchidos da E2',
  $$select public.integracao_segredos_preenchidos('c1000000-0000-4000-8000-000000000102')$$, 'Sem permissão', '42501');
select teste.como('b1.gerente1@teste.local');
select teste.erro('gerente não define segredos',
  $$select public.integracao_definir_segredos('c1000000-0000-4000-8000-000000000101', '{"senha":"x"}')$$, 'Sem permissão', '42501');
select teste.ok('gerente consulta preenchidos', array_length(public.integracao_segredos_preenchidos('c1000000-0000-4000-8000-000000000103'), 1) = 3);
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não consulta preenchidos',
  $$select public.integracao_segredos_preenchidos('c1000000-0000-4000-8000-000000000101')$$, 'Sem permissão', '42501');
select teste.como('b1.master@teste.local');
select teste.erro('nem o master lê segredos pela API', 'select * from public.integracoes_segredos', 'permission denied');
select teste.como(null);
select teste.erro('anon não lê segredos', 'select * from public.integracoes_segredos', 'permission denied');
select teste.erro('anon não lê integrações', 'select * from public.integracoes', 'permission denied');
select teste.como_servico();
select teste.ok('serviço lê a config completa com segredos',
  (select c -> 'segredos' ->> 'url' = 'http://10.0.0.1' and c ->> 'tipo' = 'controlid_acesso' and c ->> 'fuso' = 'America/Sao_Paulo'
          and c ->> 'virada_dia' = '05:00:00' and c ->> 'dia_trabalho_atual' = '2026-10-06' and not c ? 'lojas'
     from public.ingestao_integracao_config('c1000000-0000-4000-8000-000000000101') c));
select teste.ok('config da Zig traz lojas (lista)',
  (select jsonb_typeof(c -> 'lojas') = 'array'
     from public.ingestao_integracao_config((select id from public.integracoes where tipo = 'zig'
                                              and empresa_id = 'c1000000-0000-4000-8000-0000000000e1')) c));
select teste.erro('config de integração inexistente',
  $$select public.ingestao_integracao_config('c1000000-0000-4000-8000-000000000999')$$, 'Integração não encontrada', 'P0002');

-- ---------------------------------------------------------------- ingestão de usuários Control iD
select teste.como('b1.admin1@teste.local');
select teste.erro('[servico] negada a authenticated',
  $$select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101', '[]')$$, 'permission denied');
select teste.como_servico();
select teste.ok('1ª importação: 3 inseridos, 1 ignorado, vínculo por matrícula',
  (select r @> '{"lidos":4,"gravados":3,"ignorados":1,"inseridos":3,"atualizados":0,"removidos":0,"vinculados_automaticamente":1,"sem_vinculo":2}'
          and jsonb_array_length(r -> 'erros') = 1
     from public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101',
       '[{"id":"10","registration":"1","name":"FULANO"},
         {"id":11,"registration":"99","name":"BELTRANO","cpf":null},
         {"id":"12","registration":"","name":"DESCONHECIDO"},
         {"id":"","name":"SEM ID"}]') r));
select teste.ok('vínculo automático: id 10 → Fulano (matrícula 1)',
  (select funcionario_id = 'c1000000-0000-4000-8000-0000000001a1' and vinculo = 'automatico'
     from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '10'));
select teste.ok('id numérico vira texto; sem vínculo quando não casa',
  (select funcionario_id is null and nome = 'BELTRANO' from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'));
select teste.ok('id 12: registration vazia → null, Beltrano (mat. 2) não casou por matrícula',
  (select registration is null from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '12'));
select teste.ok('2ª importação idêntica: idempotente (0 inseridos, 3 atualizados)',
  (select r @> '{"inseridos":0,"atualizados":3,"removidos":0,"vinculados_automaticamente":0}'
     from public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101',
       '[{"id":"10","registration":"1","name":"FULANO"},{"id":11,"registration":"99","name":"BELTRANO"},
         {"id":"12","registration":"","name":"DESCONHECIDO"},{"id":"","name":"SEM ID"}]') r));
select teste.ok('mesmo estado após a 2ª importação',
  (select count(*) = 3 and count(funcionario_id) = 1 from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101'));
select teste.ok('quem não veio é marcado removido',
  (select (r ->> 'removidos')::int = 2
     from public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101', '[{"id":"10","registration":"1","name":"FULANO"}]') r));
select teste.ok('removido mantém o vínculo',
  (select removido_no_equipamento and funcionario_id is null from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'));
select teste.erro('integração de outro tipo',
  $$select public.ingestao_controlid_usuarios((select id from public.integracoes where tipo = 'zig' limit 1), '[]')$$,
  'Tipo de integração incompatível', '22023');
select teste.erro('integração inexistente',
  $$select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000999', '[]')$$, 'Integração não encontrada', 'P0002');
select teste.erro('lista que não é array',
  $$select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101', '{}')$$, 'Lista de usuários inválida');
-- REP: id = CPF; vínculo por CPF
select teste.ok('REP: id = CPF, vínculo por CPF',
  (select (r ->> 'vinculados_automaticamente')::int = 1
     from public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000103',
       '[{"id":"529.982.247-25","name":"FULANO"}]') r));
select teste.ok('REP: usuário gravado com CPF e ligado',
  (select cpf = '52998224725' and user_id_externo = '52998224725' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'
         from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000103'));
select teste.como_dono();
update public.integracoes set ativa = false where id = 'c1000000-0000-4000-8000-000000000102';
select teste.como_servico();
select teste.erro('integração inativa',
  $$select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000102', '[]')$$, 'Integração inativa', '22023');
select teste.como_dono();
update public.integracoes set ativa = true where id = 'c1000000-0000-4000-8000-000000000102';

-- -------------------------------------------------------------- funcionario_vincular_controlid
select teste.como('b1.gerente1@teste.local');
select teste.passa('gerente vincula manualmente',
  $$select public.funcionario_vincular_controlid(
      (select id from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'),
      'c1000000-0000-4000-8000-0000000001b1')$$);
select teste.ok('vínculo manual gravado',
  (select vinculo = 'manual' and funcionario_id = 'c1000000-0000-4000-8000-0000000001b1' from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'));
select teste.passa('religar o mesmo funcionário a outro usuário do equipamento remove o antigo',
  $$select public.funcionario_vincular_controlid(
      (select id from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '12'),
      'c1000000-0000-4000-8000-0000000001b1')$$);
select teste.ok('antigo ficou sem funcionário',
  (select funcionario_id is null from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'));
select teste.erro('funcionário de outra empresa',
  $$select public.funcionario_vincular_controlid(
      (select id from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '11'),
      'c1000000-0000-4000-8000-0000000001a2')$$, 'Funcionário de outra empresa', '22023');
select teste.passa('desvincular (null)',
  $$select public.funcionario_vincular_controlid(
      (select id from public.controlid_usuarios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '10'), null)$$);
select teste.como_servico();
select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101',
  '[{"id":"10","registration":"1","name":"FULANO"},{"id":"11","registration":"99"},{"id":"12"}]');
select teste.ok('importação não religa desvínculo manual nem desfaz vínculo manual',
  (select funcionario_id is null and vinculo = 'manual' from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '10')
  and (select funcionario_id = 'c1000000-0000-4000-8000-0000000001b1' and vinculo = 'manual' from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '12'));
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não vincula',
  $$select public.funcionario_vincular_controlid((select id from public.controlid_usuarios limit 1), null)$$,
  'Usuário do equipamento não encontrado');
select teste.como('b1.gerente2@teste.local');
select teste.erro('gerente2 não vincula usuário da E1',
  $$select public.funcionario_vincular_controlid(
      (select c.id from public.controlid_usuarios c where c.user_id_externo = '11' and c.integracao_id = 'c1000000-0000-4000-8000-000000000101'),
      null)$$, 'Usuário do equipamento não encontrado');
select teste.como_servico();
select teste.ok('exportar: só funcionários sem usuário ligado nesse equipamento (Fulano Um)',
  (select array_agg(nome order by nome) = array['Fulano Um']
     from public.ingestao_funcionarios_para_exportar('c1000000-0000-4000-8000-000000000101')));

-- -------------------------------------------------------------------------------- sync_solicitar
select teste.como('b1.gerente1@teste.local');
select teste.ok('tudo: uma solicitação por integração ativa (2 Control iD + Zig = 3)', public.sync_solicitar() = 3);
select teste.ok('repetir não duplica (pendentes)', public.sync_solicitar() = 0);
select teste.ok('batidas: só Control iD com outro escopo (2)', public.sync_solicitar(null, 'batidas') = 2);
select teste.ok('vendas na Zig (1)', public.sync_solicitar(null, 'vendas', '2026-10-01', '2026-10-05') = 1);
select teste.ok('apurar_ponto sem integração (1)', public.sync_solicitar(null, 'apurar_ponto') = 1);
select teste.ok('solicitado_por = perfil',
  (select bool_and(solicitado_por = auth.uid()) from public.sync_solicitacoes));
select teste.erro('integração incompatível com escopo',
  $$select public.sync_solicitar('c1000000-0000-4000-8000-000000000101', 'vendas')$$, 'Tipo de integração incompatível', '22023');
select teste.erro('período invertido',
  $$select public.sync_solicitar(null, 'vendas', '2026-10-05', '2026-10-01')$$, 'Período inválido', '22023');
select teste.erro('período > 31 dias',
  $$select public.sync_solicitar(null, 'batidas', '2026-08-01', '2026-10-01')$$, 'Período máximo de 31 dias', '22023');
select teste.erro('escopo inválido', $$select public.sync_solicitar(null, 'xyz')$$, 'Escopo inválido');
select teste.erro('exportar_fechamento sem fechamento',
  $$select public.sync_solicitar(null, 'exportar_fechamento')$$, 'Fechamento não encontrado', 'P0002');
select teste.erro('integração de outra empresa',
  $$select public.sync_solicitar('c1000000-0000-4000-8000-000000000102')$$, 'Sem permissão', '42501');
select teste.erro('p_empresa de outra empresa',
  $$select public.sync_solicitar(null, 'tudo', null, null, '{}', 'c1000000-0000-4000-8000-0000000000e2')$$, 'Sem permissão', '42501');
select teste.erro('gerente não insere direto na fila',
  $$insert into public.sync_solicitacoes (empresa_id, escopo) values ('c1000000-0000-4000-8000-0000000000e1', 'tudo')$$, 'permission denied');
select teste.ok('gerente vê a fila da própria empresa (7)', teste.contar('select 1 from public.sync_solicitacoes') = 7);
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não solicita', $$select public.sync_solicitar()$$, 'Sem permissão', '42501');
select teste.ok('leitura não vê a fila', teste.contar('select 1 from public.sync_solicitacoes') = 0);
select teste.como('b1.gerente2@teste.local');
select teste.ok('gerente2 não vê a fila da E1', teste.contar('select 1 from public.sync_solicitacoes') = 0);
select teste.ok('gerente2 solicita a própria (1)', public.sync_solicitar() = 1);
select teste.como('b1.master@teste.local');
select teste.erro('master sem empresa', $$select public.sync_solicitar()$$, 'Informe a empresa', '22023');
select teste.ok('master com p_empresa', public.sync_solicitar(null, 'apurar_ponto', null, null, '{}', 'c1000000-0000-4000-8000-0000000000e2') = 1);

-- ----------------------------------------------------------------------------- fila (serviço)
select teste.como('b1.admin1@teste.local');
select teste.erro('pegar_solicitacoes negada a authenticated', $$select * from public.ingestao_sync_pegar_solicitacoes()$$, 'permission denied');
select teste.como_servico();
select teste.ok('pega as 5 mais antigas', teste.contar('select * from public.ingestao_sync_pegar_solicitacoes(5)') = 5);
select teste.ok('5 em andamento', (select count(*) = 5 from public.sync_solicitacoes where status = 'em_andamento'));
select teste.ok('pega o resto (4)', teste.contar('select * from public.ingestao_sync_pegar_solicitacoes(50)') = 4);
select teste.ok('fila vazia', teste.contar('select * from public.ingestao_sync_pegar_solicitacoes()') = 0);
select public.ingestao_sync_concluir_solicitacao((select id from public.sync_solicitacoes where escopo = 'vendas'), 'concluida', 'ok');
select teste.ok('concluída', (select status = 'concluida' and concluido_em is not null from public.sync_solicitacoes where escopo = 'vendas'));
select teste.erro('status inválido na conclusão',
  $$select public.ingestao_sync_concluir_solicitacao((select id from public.sync_solicitacoes where escopo = 'vendas'), 'ok')$$, 'Status inválido');
-- expiração: 31 min depois as em_andamento viram erro
set local app.agora = '2026-10-06 12:31:00-03';
select teste.como('b1.gerente1@teste.local');
select public.sync_solicitar(null, 'funcionarios');
select teste.ok('solicitações presas expiram (Expirada)',
  (select count(*) > 0 and bool_and(mensagem = 'Expirada') from public.sync_solicitacoes where status = 'erro'));
-- integração inativa: pendência cancelada ao pegar
select teste.como_dono();
update public.integracoes set ativa = false where id = 'c1000000-0000-4000-8000-000000000103';
select teste.como_servico();
select teste.ok('pendência de integração inativa é cancelada, não pega',
  teste.contar($$select * from public.ingestao_sync_pegar_solicitacoes(50) where integracao_id = 'c1000000-0000-4000-8000-000000000103'$$) = 0
);
select teste.ok('cancelada com mensagem',
  (select bool_or(status = 'cancelada' and mensagem = 'Integração inativa') from public.sync_solicitacoes
    where integracao_id = 'c1000000-0000-4000-8000-000000000103'));

-- -------------------------------------------------------------------------- execuções (serviço)
set local app.agora = '2026-10-06 13:00:00-03';
select public.ingestao_sync_iniciar('controlid_batidas', 'manual', 'MDG · Control iD · Importar batidas',
                                    null, 'c1000000-0000-4000-8000-000000000101');
select teste.ok('iniciar execução: empresa derivada da integração e ultima_execucao_em',
  (select e.empresa_id = 'c1000000-0000-4000-8000-0000000000e1' and e.status = 'executando'
          and (select ultima_execucao_em = '2026-10-06 13:00:00-03' from public.integracoes where id = 'c1000000-0000-4000-8000-000000000101')
     from public.sync_execucoes e where e.tipo = 'controlid_batidas'));
select public.ingestao_sync_finalizar((select id from public.sync_execucoes where tipo = 'controlid_batidas'),
  'parcial', 10, 8, 2, 'falhou um lote', '{"lotes":2}', 2);
select teste.ok('finalizar: contadores e status da integração',
  (select e.status = 'parcial' and e.registros_lidos = 10 and e.registros_gravados = 8 and e.tentativas = 2
          and i.ultimo_status = 'parcial' and i.ultimo_erro = 'falhou um lote' and i.ultimo_sucesso_em is not null
     from public.sync_execucoes e join public.integracoes i on i.id = e.integracao_id where e.tipo = 'controlid_batidas'));
select public.ingestao_sync_iniciar('controlid_usuarios', 'agendado', 'MDG · X', null, 'c1000000-0000-4000-8000-000000000101');
set local app.agora = '2026-10-06 13:45:00-03';
select public.ingestao_sync_iniciar('controlid_usuarios', 'agendado', 'MDG · X', null, 'c1000000-0000-4000-8000-000000000101');
select teste.ok('execução presa > 30 min da mesma integração+tipo expira',
  (select count(*) filter (where status = 'erro' and erro = 'Expirada') = 1 and count(*) filter (where status = 'executando') = 1
     from public.sync_execucoes where tipo = 'controlid_usuarios'));
select public.ingestao_sync_finalizar((select id from public.sync_execucoes where tipo = 'controlid_usuarios' and status = 'executando'),
  'erro', 0, 0, 0, 'timeout');
select teste.ok('erro não mexe em ultimo_sucesso_em',
  (select ultimo_status = 'erro' and ultimo_erro = 'timeout' and ultimo_sucesso_em = '2026-10-06 13:00:00-03'
     from public.integracoes where id = 'c1000000-0000-4000-8000-000000000101'));
select public.ingestao_sync_iniciar('tarefas_gerar', 'agendado', 'MDG · Rotina diária');
select teste.ok('execução global (sem empresa)',
  (select empresa_id is null from public.sync_execucoes where tipo = 'tarefas_gerar'));
select teste.erro('status inválido ao finalizar',
  $$select public.ingestao_sync_finalizar((select id from public.sync_execucoes limit 1), 'ok')$$, 'Status inválido');

select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê execuções da E1 (não a global)', teste.contar('select 1 from public.sync_execucoes') = 3);
select teste.erro('authenticated não inicia execução',
  $$select public.ingestao_sync_iniciar('tarefas_gerar', 'manual', 'x')$$, 'permission denied');
select teste.como('b1.leitura2@teste.local');
select teste.ok('leitura2 não vê execuções da E1', teste.contar('select 1 from public.sync_execucoes') = 0);
select teste.como('b1.master@teste.local');
select teste.ok('master vê inclusive a global', teste.contar('select 1 from public.sync_execucoes') = 4);

-- ------------------------------------------------------------------------- integracoes_ativas
select teste.como_servico();
set local app.agora = '2026-10-06 14:00:00-03';
select teste.ok('ativas: todas as ativas de empresas ativas',
  teste.contar($$select * from public.ingestao_integracoes_ativas() where empresa_id::text like 'c1%'$$) = 3);
select teste.ok('vencidas: a 101 rodou às 13:45 (intervalo 30) → não vencida',
  not exists (select 1 from public.ingestao_integracoes_ativas(null, true) where integracao_id = 'c1000000-0000-4000-8000-000000000101'));
select teste.ok('filtro por tipo', teste.contar($$select * from public.ingestao_integracoes_ativas('zig') where empresa_id::text like 'c1%'$$) = 1);
select teste.como_dono();
update public.empresas set ativa = false where id = 'c1000000-0000-4000-8000-0000000000e2';
select teste.como_servico();
select teste.ok('empresa inativa sai da lista',
  not exists (select 1 from public.ingestao_integracoes_ativas() where empresa_id = 'c1000000-0000-4000-8000-0000000000e2'));
rollback;
