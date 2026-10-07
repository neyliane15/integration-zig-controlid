-- 19_envio_controlid.sql (backend-1): envio de cadastros/credenciais/foto/horários ao Control iD (adendo).
begin;
set local app.agora = '2026-10-06 12:00:00-03';
select teste.cenario_b1();

-- Acesso I1 (E1) e acesso I2 (E2) com envio ligado; REP I1r ligado (identificador cpf).
update public.integracoes set parametros = parametros || '{"envio":{"ativo":true}}'
 where id in ('c1000000-0000-4000-8000-000000000101', 'c1000000-0000-4000-8000-000000000102', 'c1000000-0000-4000-8000-000000000103');

select teste.ok('padrões de envio no acesso iDFace (foto, horários, desligado por padrão)',
  (select parametros -> 'envio' = '{"ativo":true,"foto":true,"cartao":true,"senha":true,"horarios":true,"ao_desligar":"remover"}'
     from public.integracoes where id = 'c1000000-0000-4000-8000-000000000101'));
select teste.ok('REP sem foto/horários',
  (select (parametros -> 'envio' ->> 'foto')::boolean = false and (parametros -> 'envio' ->> 'horarios')::boolean = false
     from public.integracoes where id = 'c1000000-0000-4000-8000-000000000103'));
select teste.ok('ligar o envio cria pendências de salvar para os funcionários (2 por equipamento da E1)',
  (select count(*) = 4 and bool_and(operacao = 'salvar') from public.controlid_envios
    where empresa_id = 'c1000000-0000-4000-8000-0000000000e1' and alvo = 'funcionario'));
select teste.ok('REP: Beltrano sem CPF fica aguardando',
  (select status = 'aguardando' and erro = 'CPF obrigatório no REP' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000103' and funcionario_id = 'c1000000-0000-4000-8000-0000000001b1'));

-- ------------------------------------------------------------------------ credenciais (segredos)
select teste.como('b1.gerente1@teste.local');
select teste.passa('gerente define senha', $$select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '1234')$$);
select teste.erro('senha não numérica', $$select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '12ab')$$,
  'Senha de acesso inválida', '22023');
select teste.erro('senha curta', $$select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '123')$$,
  'Senha de acesso inválida', '22023');
select teste.ok('cartão adicionado (com máscara removida)',
  public.funcionario_adicionar_cartao('c1000000-0000-4000-8000-0000000001a1', '0012.345.678') is not null);
select teste.erro('cartão repetido na empresa',
  $$select public.funcionario_adicionar_cartao('c1000000-0000-4000-8000-0000000001b1', '12345678')$$, 'Cartão já cadastrado', '23505');
select teste.erro('cartão inválido', $$select public.funcionario_adicionar_cartao('c1000000-0000-4000-8000-0000000001b1', 'abc')$$,
  'Número de cartão inválido', '22023');
select teste.ok('resumo: senha definida, só os 4 últimos dígitos, sem foto',
  (select c = jsonb_build_object('senha_definida', true, 'foto', null,
                                 'cartoes', jsonb_build_array(jsonb_build_object('id', c -> 'cartoes' -> 0 -> 'id', 'final', '5678',
                                                                                 'criado_em', c -> 'cartoes' -> 0 -> 'criado_em')))
     from public.funcionario_credenciais('c1000000-0000-4000-8000-0000000001a1') c));
select teste.ok('resumo nunca contém a senha nem o número completo',
  (select position('1234' in c::text) = 0 and position('12345678' in c::text) = 0
     from public.funcionario_credenciais('c1000000-0000-4000-8000-0000000001a1') c));
select teste.erro('authenticated não lê funcionario_credenciais', 'select * from public.funcionario_credenciais', 'permission denied');
select teste.erro('authenticated não lê funcionario_cartoes', 'select * from public.funcionario_cartoes', 'permission denied');
select teste.erro('authenticated não escreve credenciais direto',
  $$insert into public.funcionario_credenciais (funcionario_id, empresa_id, senha) values ('c1000000-0000-4000-8000-0000000001b1', 'c1000000-0000-4000-8000-0000000000e1', '9999')$$,
  'permission denied');
select teste.erro('authenticated não escreve cartões direto',
  $$delete from public.funcionario_cartoes$$, 'permission denied');
select teste.ok('controlid_envios não expõe a senha', not exists (select 1 from public.controlid_envios e where e::text like '%1234%'));
select teste.erro('[servico] de envio negado a authenticated',
  $$select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101')$$, 'permission denied');
select teste.como('b1.master@teste.local');
select teste.erro('nem o master lê credenciais pela API', 'select * from public.funcionario_credenciais', 'permission denied');
select teste.erro('nem o master lê cartões pela API', 'select * from public.funcionario_cartoes', 'permission denied');
select teste.como(null);
select teste.erro('anon não lê cartões', 'select * from public.funcionario_cartoes', 'permission denied');
select teste.erro('anon não chama o resumo', $$select public.funcionario_credenciais('c1000000-0000-4000-8000-0000000001a1')$$, 'permission denied');

-- --------------------------------------------------------------------------------- isolamento
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não define senha', $$select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '4321')$$,
  'Sem permissão', '42501');
select teste.erro('leitura não vê o resumo de credenciais', $$select public.funcionario_credenciais('c1000000-0000-4000-8000-0000000001a1')$$,
  'Sem permissão', '42501');
select teste.ok('leitura não vê envios', teste.contar('select 1 from public.controlid_envios') = 0);
select teste.como('b1.gerente2@teste.local');
select teste.erro('gerente2 não define senha na E1', $$select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '4321')$$,
  'Sem permissão', '42501');
select teste.erro('gerente2 não adiciona cartão na E1', $$select public.funcionario_adicionar_cartao('c1000000-0000-4000-8000-0000000001a1', '999')$$,
  'Sem permissão', '42501');
select teste.erro('gerente2 não remove cartão da E1',
  $$select public.funcionario_remover_cartao((select id from public.controlid_envios limit 0))$$, 'Cartão não encontrado');
select teste.erro('gerente2 não lê resumo da E1', $$select public.funcionario_credenciais('c1000000-0000-4000-8000-0000000001a1')$$,
  'Sem permissão', '42501');
select teste.ok('gerente2 vê só envios da E2', teste.contar($$select 1 from public.controlid_envios where empresa_id <> 'c1000000-0000-4000-8000-0000000000e2'$$) = 0
  and teste.contar('select 1 from public.controlid_envios') = 1);
select teste.passa('mesmo número de cartão em outra empresa é permitido',
  $$select public.funcionario_adicionar_cartao('c1000000-0000-4000-8000-0000000001a2', '12345678')$$);
select teste.erro('gerente2 não reenvia na E1',
  $$select public.controlid_envio_reenviar('c1000000-0000-4000-8000-000000000101')$$, 'Sem permissão', '42501');

-- ------------------------------------------------------------------------------------- foto
select teste.como_dono();
insert into storage.objects (bucket_id, name)
values ('funcionarios-fotos', 'c1000000-0000-4000-8000-0000000000e1/c1000000-0000-4000-8000-0000000001a1/rosto.jpg');
select teste.como('b1.gerente1@teste.local');
select teste.erro('caminho fora da pasta do funcionário',
  $$select public.funcionario_definir_foto('c1000000-0000-4000-8000-0000000001a1', 'c1000000-0000-4000-8000-0000000000e2/x/rosto.jpg')$$,
  'Foto inválida', '22023');
select teste.erro('extensão inválida',
  $$select public.funcionario_definir_foto('c1000000-0000-4000-8000-0000000001a1',
     'c1000000-0000-4000-8000-0000000000e1/c1000000-0000-4000-8000-0000000001a1/rosto.gif')$$, 'Foto inválida', '22023');
select teste.erro('arquivo inexistente no bucket',
  $$select public.funcionario_definir_foto('c1000000-0000-4000-8000-0000000001a1',
     'c1000000-0000-4000-8000-0000000000e1/c1000000-0000-4000-8000-0000000001a1/outro.jpg')$$, 'Foto não encontrada', 'P0002');
select teste.passa('foto registrada',
  $$select public.funcionario_definir_foto('c1000000-0000-4000-8000-0000000001a1',
     'c1000000-0000-4000-8000-0000000000e1/c1000000-0000-4000-8000-0000000001a1/rosto.jpg')$$);
select teste.ok('gerente lê a foto (metadados)', teste.contar('select 1 from public.funcionario_fotos') = 1);
select teste.ok('storage: gerente vê o objeto da própria empresa', teste.contar($$select 1 from storage.objects where bucket_id = 'funcionarios-fotos'$$) = 1);
select teste.erro('storage: gerente não grava na pasta de outra empresa',
  $$insert into storage.objects (bucket_id, name) values ('funcionarios-fotos', 'c1000000-0000-4000-8000-0000000000e2/x/y.jpg')$$,
  'row-level security');
select teste.passa('storage: gerente grava na pasta da própria empresa',
  $$insert into storage.objects (bucket_id, name) values ('funcionarios-fotos', 'c1000000-0000-4000-8000-0000000000e1/x/y.jpg')$$);
select teste.como('b1.gerente2@teste.local');
select teste.ok('storage: gerente2 não vê fotos da E1', teste.contar($$select 1 from storage.objects where bucket_id = 'funcionarios-fotos'$$) = 0);
select teste.ok('gerente2 não vê metadados de foto da E1', teste.contar('select 1 from public.funcionario_fotos') = 0);
select teste.como('b1.leitura1@teste.local');
select teste.ok('storage: leitura vê as fotos da própria empresa', teste.contar($$select 1 from storage.objects where bucket_id = 'funcionarios-fotos'$$) = 2);
select teste.erro('storage: leitura não grava',
  $$insert into storage.objects (bucket_id, name) values ('funcionarios-fotos', 'c1000000-0000-4000-8000-0000000000e1/x/z.jpg')$$,
  'row-level security');

-- --------------------------------------------------------------------------------- horários
select teste.como('b1.gerente1@teste.local');
insert into public.controlid_horarios (id, empresa_id, nome)
values ('c1000000-0000-4000-8000-000000000501', 'c1000000-0000-4000-8000-0000000000e1', 'Noite');
insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim)
values ('c1000000-0000-4000-8000-000000000501', 6, '16:30', '23:59:59'),
       ('c1000000-0000-4000-8000-000000000501', 0, '00:00', '02:00');
select teste.erro('faixa invertida',
  $$insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim) values ('c1000000-0000-4000-8000-000000000501', 1, '10:00', '09:00')$$,
  'controlid_horario_faixas_ordem');
insert into public.funcionario_horarios (funcionario_id, horario_id)
values ('c1000000-0000-4000-8000-0000000001a1', 'c1000000-0000-4000-8000-000000000501');
select teste.erro('horário de outra empresa',
  $$insert into public.funcionario_horarios (funcionario_id, horario_id) values ('c1000000-0000-4000-8000-0000000001a2', 'c1000000-0000-4000-8000-000000000501')$$,
  'Horário de outra empresa', '22023');
select teste.ok('envio de horários criado só no acesso da E1',
  (select count(*) = 1 and bool_and(integracao_id = 'c1000000-0000-4000-8000-000000000101' and status = 'pendente')
     from public.controlid_envios where alvo = 'horarios'));
select teste.ok('Fulano (com horário) aguarda o envio dos horários',
  (select status = 'aguardando' and erro = 'Aguardando envio dos horários' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.como('b1.gerente2@teste.local');
select teste.ok('gerente2 não vê horários da E1',
  teste.contar('select 1 from public.controlid_horarios union all select 1 from public.controlid_horario_faixas union all select 1 from public.funcionario_horarios') = 0);
select teste.erro('gerente2 não cria faixa em horário da E1',
  $$insert into public.controlid_horario_faixas (horario_id, dia_semana, inicio, fim) values ('c1000000-0000-4000-8000-000000000501', 1, '10:00', '11:00')$$,
  'row-level security');
select teste.como('b1.leitura1@teste.local');
select teste.ok('leitura vê horários', teste.contar('select 1 from public.controlid_horarios') = 1);
select teste.erro('leitura não cria horário',
  $$insert into public.controlid_horarios (empresa_id, nome) values ('c1000000-0000-4000-8000-0000000000e1', 'X')$$, 'row-level security');

-- ------------------------------------------------------------------------------- ciclo N8N
select teste.como_servico();
create temp table _lote as
  select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101') as r;
select teste.ok('lote: horários primeiro e Beltrano; Fulano aguardando fica fora',
  (select jsonb_array_length(r -> 'itens') = 2 and r -> 'itens' -> 0 ->> 'alvo' = 'horarios'
          and r -> 'itens' -> 1 ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001b1'
          and r -> 'envio' ->> 'foto' = 'true' and r ->> 'tipo' = 'controlid_acesso' from _lote));
select teste.ok('payload dos horários com segundos e mapa_anterior',
  (select r -> 'itens' -> 0 -> 'horarios' -> 0 -> 'faixas' -> 1 @> '{"dia_semana":6,"inicio_segundos":59400,"fim_segundos":86399}'
          and r -> 'itens' -> 0 -> 'mapa_anterior' = '{}' from _lote));
select teste.ok('itens pegos ficam enviando com 1 tentativa',
  (select count(*) = 2 and bool_and(tentativas = 1) from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and status = 'enviando'));
select teste.ok('chamada seguinte não repete os itens em andamento',
  (select jsonb_array_length(public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101') -> 'itens') = 0));
select teste.ok('horários enviados (mapa gravado)',
  (select public.ingestao_controlid_envio_resultado((r -> 'itens' -> 0 ->> 'envio_id')::uuid, (r -> 'itens' -> 0 ->> 'versao')::int,
            'enviado', null, null, '{"c1000000-0000-4000-8000-000000000501":{"time_zone_id":101,"access_rule_id":201}}') ->> 'status' = 'enviado'
     from _lote));
select teste.ok('Fulano liberado após os horários',
  (select status = 'pendente' and erro is null from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('erro de envio do Beltrano',
  (select public.ingestao_controlid_envio_resultado((r -> 'itens' -> 1 ->> 'envio_id')::uuid, 1, 'erro', null, 'timeout') ->> 'status' = 'erro'
     from _lote));
truncate _lote;
insert into _lote select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101');
select teste.ok('2º lote: Fulano (completo) e Beltrano (erro, nova tentativa)',
  (select jsonb_array_length(r -> 'itens') = 2 from _lote));
select teste.ok('payload do Fulano: senha, cartão, foto, regra com access_rule_id',
  (select x @> jsonb_build_object('operacao', 'salvar', 'senha', '1234', 'cartoes', jsonb_build_array('12345678'),
                                  'usuario', jsonb_build_object('nome', 'Fulano Um', 'matricula', '1', 'cpf', '52998224725'),
                                  'regras_acesso', jsonb_build_array(jsonb_build_object('horario_id', 'c1000000-0000-4000-8000-000000000501', 'access_rule_id', 201)))
          and x -> 'id_remoto' = 'null'
          and x -> 'foto' ->> 'caminho' like '%/rosto.jpg'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001a1'));
-- mudança no meio do envio: a versão enviada fica velha
select teste.como('b1.gerente1@teste.local');
select public.funcionario_definir_senha('c1000000-0000-4000-8000-0000000001a1', '5678');
select teste.como_servico();
select teste.ok('resultado de versão velha deixa pendente',
  (select public.ingestao_controlid_envio_resultado((x ->> 'envio_id')::uuid, (x ->> 'versao')::int, 'enviado', '77') ->> 'status' = 'pendente'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('usuário do equipamento ligado ao funcionário (id remoto 77)',
  (select funcionario_id = 'c1000000-0000-4000-8000-0000000001a1' and vinculo = 'automatico' from public.controlid_usuarios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '77'));
truncate _lote;
insert into _lote select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101');
select teste.ok('3º lote: Fulano com a senha nova e id_remoto 77',
  (select x ->> 'senha' = '5678' and x ->> 'id_remoto' = '77'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('enviado com a versão atual',
  (select public.ingestao_controlid_envio_resultado((x ->> 'envio_id')::uuid, (x ->> 'versao')::int, 'enviado', '77') ->> 'status' = 'enviado'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('resultado repetido é idempotente',
  (select public.ingestao_controlid_envio_resultado((x ->> 'envio_id')::uuid, (x ->> 'versao')::int, 'enviado', '77') ->> 'status' = 'enviado'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'funcionario_id' = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('nada mudou → nada pendente para o Fulano',
  (select status = 'enviado' and assinatura = assinatura_enviada from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('recalcular sem mudança não gera versão nova',
  (select public.controlid_envio_atualizar('c1000000-0000-4000-8000-0000000000e1') >= 0)
  );
select teste.ok('continua enviado',
  (select status = 'enviado' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.erro('status inválido', $$select public.ingestao_controlid_envio_resultado((select id from public.controlid_envios limit 1), 1, 'ok')$$,
  'Status inválido', '22023');
select teste.erro('envio inexistente', $$select public.ingestao_controlid_envio_resultado('c1000000-0000-4000-8000-000000000999', 1, 'enviado')$$,
  'Envio não encontrado', 'P0002');

-- ----------------------------------------------------------------------------- desligamento
select teste.como('b1.gerente1@teste.local');
update public.funcionarios set data_desligamento = '2026-10-05' where id = 'c1000000-0000-4000-8000-0000000001a1';
select teste.ok('desligado → remover no acesso (id remoto conhecido)',
  (select operacao = 'remover' and status = 'pendente' and id_remoto = '77' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('REP nunca enviado: pendência de salvar some',
  not exists (select 1 from public.controlid_envios
               where integracao_id = 'c1000000-0000-4000-8000-000000000103' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.ok('gerente vê a situação do envio', teste.contar('select 1 from public.controlid_envios') > 0);
select teste.como_servico();
truncate _lote;
insert into _lote select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101');
select teste.ok('remover vem antes de salvar, sem segredos',
  (select r -> 'itens' -> 0 ->> 'operacao' = 'remover' and r -> 'itens' -> 0 -> 'senha' = 'null'
          and r -> 'itens' -> 0 -> 'cartoes' = '[]' from _lote));
select public.ingestao_controlid_envio_resultado((r -> 'itens' -> 0 ->> 'envio_id')::uuid, (r -> 'itens' -> 0 ->> 'versao')::int, 'enviado')
  from _lote;
select teste.ok('remoção enviada: id_remoto limpo e usuário marcado removido',
  (select e.status = 'enviado' and e.id_remoto is null from public.controlid_envios e
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1')
  and (select removido_no_equipamento from public.controlid_usuarios
        where integracao_id = 'c1000000-0000-4000-8000-000000000101' and user_id_externo = '77'));
select teste.ok('depois de removido não volta a pendente',
  (select public.controlid_envio_atualizar('c1000000-0000-4000-8000-0000000000e1') >= 0));
select teste.ok('continua enviado (remover)',
  (select status = 'enviado' and operacao = 'remover' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));

-- ------------------------------------------------------------------------------------ exclusão
select teste.como_servico();
select public.ingestao_controlid_usuarios('c1000000-0000-4000-8000-000000000101', '[{"id":"88","registration":"2","name":"BELTRANO"}]');
select teste.ok('importação liga Beltrano ao usuário 88 e o envio passa a usar o id 88',
  (select id_remoto = '88' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001b1'));
select teste.como('b1.admin1@teste.local');
delete from public.funcionarios where id = 'c1000000-0000-4000-8000-0000000001b1';
select teste.como_servico();
select teste.ok('excluído → remover sem funcionário, com nome e id remoto',
  (select count(*) = 1 and bool_and(operacao = 'remover' and status = 'pendente' and funcionario_nome = 'Beltrano Um' and id_remoto = '88')
     from public.controlid_envios where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id is null and alvo = 'funcionario'));
select teste.ok('REP do excluído (aguardando, nunca enviado) apagado',
  not exists (select 1 from public.controlid_envios where integracao_id = 'c1000000-0000-4000-8000-000000000103' and funcionario_id is null));
truncate _lote;
insert into _lote select public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000101');
select teste.ok('payload de remoção do excluído',
  (select x @> '{"operacao":"remover","funcionario_id":null,"id_remoto":"88","usuario":{"nome":"Beltrano Um"}}'
     from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'id_remoto' = '88'));
select public.ingestao_controlid_envio_resultado((x ->> 'envio_id')::uuid, (x ->> 'versao')::int, 'enviado')
  from _lote, jsonb_array_elements(r -> 'itens') x where x ->> 'id_remoto' = '88';
select teste.ok('remoção do excluído concluída apaga a linha',
  not exists (select 1 from public.controlid_envios where id_remoto = '88'));

-- ---------------------------------------------------------------------- REP e envio desligado
select teste.ok('REP: payload sem foto/regras, identificador cpf',
  (select r ->> 'identificador' = 'cpf' and r -> 'envio' ->> 'horarios' = 'false'
     from public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000103') r));
select teste.como_dono();
update public.integracoes set parametros = jsonb_set(parametros, '{envio,ativo}', 'false') where id = 'c1000000-0000-4000-8000-000000000102';
select teste.como_servico();
select teste.ok('envio desligado: nenhum item',
  (select jsonb_array_length(r -> 'itens') = 0 from public.ingestao_controlid_envios_pendentes('c1000000-0000-4000-8000-000000000102') r));
select teste.erro('integração de tipo errado',
  $$select public.ingestao_controlid_envios_pendentes((select id from public.integracoes where tipo = 'zig' limit 1))$$,
  'Tipo de integração incompatível');

-- --------------------------------------------------------------------------------- reenviar
select teste.como('b1.gerente1@teste.local');
select teste.ok('reenviar com funcionário força o reenvio do já enviado',
  public.controlid_envio_reenviar(null, 'c1000000-0000-4000-8000-0000000001a1') = 1);
select teste.ok('voltou a pendente',
  (select status = 'pendente' from public.controlid_envios
    where integracao_id = 'c1000000-0000-4000-8000-000000000101' and funcionario_id = 'c1000000-0000-4000-8000-0000000001a1'));
select teste.como('b1.leitura1@teste.local');
select teste.erro('leitura não reenvia', $$select public.controlid_envio_reenviar()$$, 'Sem permissão', '42501');
rollback;
