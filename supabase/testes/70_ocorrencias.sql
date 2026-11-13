-- 70_ocorrencias.sql — ocorrências disciplinares (adendo O): validações, suspensão → abono 'suspensao' (situação 'suspenso',
-- sem alarme nem saldo negativo), anexos no Storage, resumo/painel, permissões (leitura não vê) e isolamento.
begin;
-- ------------------------------------------------------------------ cenário comum b2 (dentro da transação)
-- Relógio fixo, duas empresas (A = SP, B = Manaus), usuários de todos os papéis, jornada "Salão noite" (só sábado).
set local app.agora = '2026-10-06 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e2000000-0000-4000-8000-00000000000a', 'Teste b2 A', 'America/Sao_Paulo', '05:00'),
  ('e2000000-0000-4000-8000-00000000000b', 'Teste b2 B', 'America/Manaus', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e2000000-0000-4000-8000-000000000a01', 'b2.adm.a@teste.local', '{"nome":"Adm A"}'),
  ('e2000000-0000-4000-8000-000000000a02', 'b2.ger.a@teste.local', '{"nome":"Gerente A"}'),
  ('e2000000-0000-4000-8000-000000000a03', 'b2.lei.a@teste.local', '{"nome":"Leitura A"}'),
  ('e2000000-0000-4000-8000-000000000b01', 'b2.adm.b@teste.local', '{"nome":"Adm B"}'),
  ('e2000000-0000-4000-8000-000000000f01', 'b2.master@teste.local', '{"nome":"Master b2"}');
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e2000000-0000-4000-8000-00000000000a' where id = 'e2000000-0000-4000-8000-000000000a03';
update public.perfis set papel = 'administrador', empresa_id = 'e2000000-0000-4000-8000-00000000000b' where id = 'e2000000-0000-4000-8000-000000000b01';
update public.perfis set papel = 'master', empresa_id = null where id = 'e2000000-0000-4000-8000-000000000f01';
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e2000000-0000-4000-8000-000000000201', 'e2000000-0000-4000-8000-00000000000a', 'Salão noite b2', 5, 10),
  ('e2000000-0000-4000-8000-000000000202', 'e2000000-0000-4000-8000-00000000000b', 'Turno B', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida) values
  ('e2000000-0000-4000-8000-000000000201', 6, '17:00', '21:00', '21:30', '01:00');
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida) select 'e2000000-0000-4000-8000-000000000202', d, '09:00', '17:00' from generate_series(1, 5) d;
insert into public.funcionarios (id, empresa_id, nome, cargo, cpf, pontos_comissao, data_admissao, zig_employee_name) values
  ('e2000000-0000-4000-8000-000000000301', 'e2000000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', '52998224725', 10, '2026-01-01', 'Ana Souza'),
  ('e2000000-0000-4000-8000-000000000302', 'e2000000-0000-4000-8000-00000000000a', 'Bruno Lima', 'Garçom', '11144477735', 10, '2026-01-01', 'Bruno Lima'),
  ('e2000000-0000-4000-8000-000000000303', 'e2000000-0000-4000-8000-00000000000a', 'Carla Dias', 'Cumim', '39053344705', 6, '2026-01-01', 'Carla Dias'),
  ('e2000000-0000-4000-8000-000000000304', 'e2000000-0000-4000-8000-00000000000a', 'Davi Rocha', 'Bartender', '15350946056', 8, '2026-01-01', 'Davi Rocha'),
  ('e2000000-0000-4000-8000-000000000305', 'e2000000-0000-4000-8000-00000000000a', 'Eva Martins', 'Cozinha', '71428793860', 4, '2026-01-01', null),
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-00000000000b', 'Paolo B2', 'Garçom', null, 5, '2026-01-01', 'Paolo');
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f, 'e2000000-0000-4000-8000-000000000201', '2026-09-01'
  from unnest(array['e2000000-0000-4000-8000-000000000301','e2000000-0000-4000-8000-000000000302',
                    'e2000000-0000-4000-8000-000000000303','e2000000-0000-4000-8000-000000000304',
                    'e2000000-0000-4000-8000-000000000305']::uuid[]) f;
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde) values
  ('e2000000-0000-4000-8000-000000000391', 'e2000000-0000-4000-8000-000000000202', '2026-09-01');
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e2000000-0000-4000-8000-000000000101', 'e2000000-0000-4000-8000-00000000000a', 'zig', 'Zig b2', '{"rede":"r"}'),
  ('e2000000-0000-4000-8000-000000000102', 'e2000000-0000-4000-8000-00000000000a', 'controlid_acesso', 'iDFace b2', '{}'),
  ('e2000000-0000-4000-8000-000000000103', 'e2000000-0000-4000-8000-00000000000a', 'controlid_rep', 'iDClass b2', '{}'),
  ('e2000000-0000-4000-8000-000000000111', 'e2000000-0000-4000-8000-00000000000b', 'zig', 'Zig B b2', '{}'),
  ('e2000000-0000-4000-8000-000000000112', 'e2000000-0000-4000-8000-00000000000b', 'controlid_rep', 'REP B b2', '{}');
-- ------------------------------------------------------------------ fim do cenário comum

create temp table ox (nome text primary key, id uuid) on commit drop;
grant all on ox to authenticated;
-- Ana (sem batidas) no sáb 03/10 está ausente com alarme sem_batida_dia_escalado
select teste.ok('pré: Ana ausente em 03/10 com alarme aberto',
  (select (situacao, saldo_minutos, alarmes_abertos) = ('ausente'::text, -450, 1::smallint) from public.ponto_dias
    where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03'));
create temp table saldo0 on commit drop as select public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-10-05') as s;
grant select on saldo0 to authenticated;

select teste.como('b2.ger.a@teste.local');
-- validações
select teste.erro('tipo inválido', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'multa', '2026-10-01', 'x')$$, 'Tipo de ocorrência inválido', '22023');
select teste.erro('data no futuro', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'advertencia', '2026-10-07', 'x')$$, 'Data no futuro', '22023');
select teste.erro('sem motivo', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'advertencia', '2026-10-01', '  ')$$, 'Informe o motivo');
select teste.erro('sem data', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'advertencia', null, 'x')$$, 'Informe a data');
select teste.erro('suspensão sem dias', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'suspensao', '2026-10-01', 'x')$$, 'Dias de suspensão inválidos (1 a 30)');
select teste.erro('suspensão 31 dias', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'suspensao', '2026-10-01', 'x', null, 31)$$, 'Dias de suspensão inválidos (1 a 30)');
select teste.erro('início antes da data', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'suspensao', '2026-10-01', 'x', null, 1, '2026-09-30')$$, 'Início da suspensão inválido');
select teste.erro('funcionário inexistente', $$select public.ocorrencia_criar(gen_random_uuid(), 'advertencia', '2026-10-01', 'x')$$, 'Funcionário não encontrado', 'P0002');

-- advertência (campos de suspensão ignorados)
insert into ox select 'adv', public.ocorrencia_criar('e2000000-0000-4000-8000-000000000304', 'advertencia', '2026-10-01', ' Atraso ', 'detalhe', 3, '2026-10-02');
select teste.ok('advertência gravada sem campos de suspensão, autor registrado',
  (select (tipo, motivo, descricao, dias_suspensao, suspensao_inicio, criado_por_nome, empresa_id)
     is not distinct from ('advertencia'::text, 'Atraso'::text, 'detalhe'::text, null::int, null::date, 'Gerente A'::text, 'e2000000-0000-4000-8000-00000000000a'::uuid)
     from public.funcionario_ocorrencias where id = (select id from ox where nome = 'adv')));

-- suspensão da Ana: 2 dias a partir de 03/10 (sáb escalado e dom folga)
insert into ox select 'susp', public.ocorrencia_criar('e2000000-0000-4000-8000-000000000301', 'suspensao', '2026-10-02', 'Falta sem aviso', null, 2, '2026-10-03');
select teste.ok('suspensão: fim calculado', (select (dias_suspensao, suspensao_inicio, suspensao_fim) = (2, '2026-10-03'::date, '2026-10-04'::date)
  from public.funcionario_ocorrencias where id = (select id from ox where nome = 'susp')));
select teste.ok('suspensão gera um abono ''suspensao'' por dia, ligado à ocorrência',
  (select array_agg(data || '/' || tipo order by data) from public.ponto_abonos where ocorrencia_id = (select id from ox where nome = 'susp'))
  = array['2026-10-03/suspensao', '2026-10-04/suspensao']);
select teste.ok('dia suspenso: situação suspenso, saldo 0, sem alarmes abertos',
  (select (situacao, saldo_minutos, previsto_minutos, alarmes_abertos, abono_tipo) = ('suspenso'::text, 0, 0, 0::smallint, 'suspensao'::text)
     from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03'));
select teste.ok('alarme sem_batida_dia_escalado resolvido automaticamente',
  (select (status, resolvido_automaticamente) = ('resolvido'::text, true) from public.ponto_alarmes
    where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03' and tipo = 'sem_batida_dia_escalado'));
select teste.ok('banco de horas: o dia suspenso deixa de descontar 450 min',
  public.banco_horas_saldo('e2000000-0000-4000-8000-000000000301', '2026-10-05') = (select s from saldo0) + 450);
select teste.ok('espelho mostra suspenso', (select situacao from public.ponto_espelho('e2000000-0000-4000-8000-000000000301', '2026-10-03', '2026-10-03')) = 'suspenso');
select teste.ok('extrato do banco de horas rotula Suspenso',
  (select descricao like 'Suspenso (suspensao)%' from public.banco_horas_extrato('e2000000-0000-4000-8000-000000000301', '2026-10-03', '2026-10-03') where tipo = 'dia'));
select teste.erro('abonar dia suspenso', $$select public.ponto_abonar('2026-10-03', '2026-10-03', 'folga', null, 'e2000000-0000-4000-8000-000000000301')$$,
  'Dia com suspensão: altere pela ocorrência', '22023');
select teste.erro('remover abono de suspensão', $$select public.ponto_remover_abono((select id from public.ponto_abonos where ocorrencia_id = (select id from ox where nome = 'susp') limit 1))$$,
  'Dia com suspensão: altere pela ocorrência');
select teste.erro('abono manual do tipo suspensao', $$select public.ponto_abonar('2026-09-26', '2026-09-26', 'suspensao', null, 'e2000000-0000-4000-8000-000000000302')$$, 'Tipo de abono inválido');
select teste.passa('feriado da empresa toda no dia suspenso continua possível', $$select public.ponto_abonar('2026-10-04', '2026-10-04', 'feriado', 'f')$$);
select teste.ok('abono do funcionário (suspensão) prevalece sobre o feriado', (select situacao from public.ponto_dias
  where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-04') = 'suspenso');

-- conflito com abono manual
select public.ponto_abonar('2026-09-26', '2026-09-26', 'folga', null, 'e2000000-0000-4000-8000-000000000302');
select teste.erro('suspensão em dia com abono manual', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000302', 'suspensao', '2026-09-25', 'x', null, 3)$$,
  'Já existe abono para o funcionário em 26/09/2026', '22023');

-- editar: muda o período → abonos e apuração acompanham
select public.ocorrencia_atualizar((select id from ox where nome = 'susp'), 'suspensao', '2026-09-26', 'Falta sem aviso', 'editado', 1, null);
select teste.ok('editar: abonos movidos para 26/09', (select array_agg(data order by data) from public.ponto_abonos where ocorrencia_id = (select id from ox where nome = 'susp'))
  = array['2026-09-26'::date]);
select teste.ok('editar: 03/10 volta a ausente com o alarme reaberto, 26/09 suspenso',
  (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03') = 'ausente'
  and (select status from public.ponto_alarmes where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03' and tipo = 'sem_batida_dia_escalado') = 'aberto'
  and (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-26') = 'suspenso');
select public.ocorrencia_atualizar((select id from ox where nome = 'susp'), 'advertencia', '2026-09-26', 'Falta sem aviso', null);
select teste.ok('virar advertência remove os abonos', not exists (select 1 from public.ponto_abonos where ocorrencia_id = (select id from ox where nome = 'susp'))
  and (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-09-26') = 'ausente');
select public.ocorrencia_atualizar((select id from ox where nome = 'susp'), 'suspensao', '2026-10-02', 'Falta sem aviso', null, 2, '2026-10-03');
select teste.erro('ocorrência inexistente', $$select public.ocorrencia_atualizar(gen_random_uuid(), 'advertencia', '2026-10-01', 'x', null)$$, 'Ocorrência não encontrada', 'P0002');

-- anexos (Storage)
select teste.como_dono();
select teste.ok('bucket funcionarios-documentos privado, 5 MB, imagens e PDF',
  (select (public, file_size_limit, allowed_mime_types) = (false, 5242880::bigint, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
     from storage.buckets where id = 'funcionarios-documentos'));
select teste.como('b2.ger.a@teste.local');
create temp view cam as select 'e2000000-0000-4000-8000-00000000000a/ocorrencias/' || (select id from ox where nome = 'susp') || '/' as p;
grant select on cam to authenticated;
select teste.passa('gerente envia arquivo ao bucket da própria empresa',
  $$insert into storage.objects (bucket_id, name) select 'funcionarios-documentos', p || 'assinada.jpg' from cam$$);
select teste.erro('gerente não envia arquivo na pasta de outra empresa',
  $$insert into storage.objects (bucket_id, name) values ('funcionarios-documentos', 'e2000000-0000-4000-8000-00000000000b/ocorrencias/x/a.jpg')$$);
select teste.erro('anexo com caminho fora do padrão', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), 'e2000000-0000-4000-8000-00000000000a/outra/a.jpg')$$, 'Anexo inválido', '22023');
select teste.erro('anexo de extensão não permitida', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'a.exe')$$, 'Anexo inválido');
select teste.erro('anexo inexistente no Storage', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'nao.pdf')$$, 'Anexo não encontrado no armazenamento', 'P0002');
insert into ox select 'anexo', public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'assinada.jpg', 'Documento assinado.jpg');
select teste.erro('anexo repetido', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'assinada.jpg')$$, 'Anexo já registrado', '23505');
select teste.ok('listar: ocorrências por data desc com anexos',
  (select jsonb_agg(o ->> 'tipo') from jsonb_array_elements(public.ocorrencias_listar('e2000000-0000-4000-8000-000000000301')) o) = '["suspensao"]'::jsonb
  and (public.ocorrencias_listar('e2000000-0000-4000-8000-000000000301') -> 0 -> 'anexos' -> 0 ->> 'nome_arquivo') = 'Documento assinado.jpg'
  and (public.ocorrencias_listar('e2000000-0000-4000-8000-000000000301') -> 0) ?& array['id', 'funcionario_id', 'tipo', 'data', 'motivo', 'descricao',
       'dias_suspensao', 'suspensao_inicio', 'suspensao_fim', 'criado_por_nome', 'criado_em', 'atualizado_em', 'anexos']);
do $$ begin
  for i in 1..9 loop
    insert into storage.objects (bucket_id, name) select 'funcionarios-documentos', p || 'f' || i || '.png' from cam;
    perform public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'f' || i || '.png');
  end loop;
end $$;
insert into storage.objects (bucket_id, name) select 'funcionarios-documentos', p || 'f10.pdf' from cam;
select teste.erro('limite de 10 anexos', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'susp'), (select p from cam) || 'f10.pdf')$$, 'Limite de 10 anexos por ocorrência');
select teste.ok('remover anexo devolve o caminho', public.ocorrencia_remover_anexo((select id from ox where nome = 'anexo')) = (select p from cam) || 'assinada.jpg');
select teste.erro('anexo inexistente', $$select public.ocorrencia_remover_anexo(gen_random_uuid())$$, 'Anexo não encontrado', 'P0002');

-- contagem e resumo
select teste.ok('contagem por funcionário',
  (select array_agg(funcionario_id || '/' || advertencias || '/' || suspensoes || '/' || dias_suspensao || '/' || ultima_data order by funcionario_id) from public.ocorrencias_contagem())
  = array['e2000000-0000-4000-8000-000000000301/0/1/2/2026-10-02', 'e2000000-0000-4000-8000-000000000304/1/0/0/2026-10-01']);
select teste.ok('contagem de um funcionário', (select count(*) from public.ocorrencias_contagem('e2000000-0000-4000-8000-000000000304')) = 1
  and (select count(*) from public.ocorrencias_contagem('e2000000-0000-4000-8000-000000000302')) = 0);
select teste.ok('resumo 30 dias', (public.ocorrencias_resumo() - 'recentes')
  = '{"desde": "2026-09-07", "ate": "2026-10-06", "advertencias": 1, "suspensoes": 1, "suspensos_hoje": 0}'::jsonb
  and jsonb_array_length(public.ocorrencias_resumo() -> 'recentes') = 2
  and (public.ocorrencias_resumo() -> 'recentes' -> 0 ->> 'funcionario_nome') = 'Ana Souza');
select teste.ok('painel do gerente traz o resumo de ocorrências', (public.painel_do_dia() -> 'ocorrencias') = public.ocorrencias_resumo(30));
select teste.erro('resumo com dias inválidos', $$select public.ocorrencias_resumo(0)$$, 'Período máximo de 366 dias');

-- leitura não vê nada
select teste.como('b2.lei.a@teste.local');
select teste.ok('leitura não enxerga ocorrências nem anexos',
  teste.contar('select * from public.funcionario_ocorrencias') = 0 and teste.contar('select * from public.funcionario_ocorrencia_anexos') = 0);
select teste.ok('leitura não enxerga os arquivos no Storage', teste.contar($$select * from storage.objects where bucket_id = 'funcionarios-documentos'$$) = 0);
select teste.erro('leitura não envia arquivo', $$insert into storage.objects (bucket_id, name) values ('funcionarios-documentos', 'e2000000-0000-4000-8000-00000000000a/ocorrencias/x/a.jpg')$$);
select teste.erro('leitura não lista', $$select public.ocorrencias_listar('e2000000-0000-4000-8000-000000000301')$$, 'Sem permissão', '42501');
select teste.erro('leitura não registra', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000301', 'advertencia', '2026-10-01', 'x')$$, 'Sem permissão', '42501');
select teste.erro('leitura não conta', $$select * from public.ocorrencias_contagem()$$, 'Sem permissão', '42501');
select teste.erro('leitura não vê resumo', $$select public.ocorrencias_resumo()$$, 'Sem permissão', '42501');
select teste.ok('leitura: painel com ocorrencias null', (public.painel_do_dia() -> 'ocorrencias') = 'null'::jsonb);
select teste.ok('leitura vê a situação suspenso no ponto (sem o motivo)',
  (select situacao from public.ponto_dia_empresa('2026-10-03') where funcionario_id = 'e2000000-0000-4000-8000-000000000301') = 'suspenso');

-- outra empresa
select teste.como('b2.adm.b@teste.local');
select teste.erro('admin B não registra em funcionário de A', $$select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000301', 'advertencia', '2026-10-01', 'x')$$, 'Sem permissão');
select teste.erro('admin B não exclui ocorrência de A', $$select public.ocorrencia_excluir((select id from ox where nome = 'adv'))$$, 'Sem permissão');
select teste.erro('admin B não anexa em ocorrência de A', $$select public.ocorrencia_adicionar_anexo((select id from ox where nome = 'adv'), 'x')$$, 'Sem permissão');
select teste.ok('admin B não vê nada de A', teste.contar('select * from public.funcionario_ocorrencias') = 0
  and teste.contar($$select * from storage.objects where bucket_id = 'funcionarios-documentos'$$) = 0
  and (select count(*) from public.ocorrencias_contagem()) = 0);
select teste.erro('admin B não lê resumo de A', $$select public.ocorrencias_resumo(30, 'e2000000-0000-4000-8000-00000000000a')$$, 'Sem permissão');

-- excluir: devolve caminhos, cascata nos anexos e abonos, reapura
select teste.como('b2.adm.a@teste.local');
select teste.ok('excluir devolve os caminhos dos anexos',
  cardinality(public.ocorrencia_excluir((select id from ox where nome = 'susp'))) = 9);
select teste.ok('excluir: anexos e abonos apagados, dia volta a ausente',
  not exists (select 1 from public.funcionario_ocorrencia_anexos where ocorrencia_id = (select id from ox where nome = 'susp'))
  and not exists (select 1 from public.ponto_abonos where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and tipo = 'suspensao')
  and (select situacao from public.ponto_dias where funcionario_id = 'e2000000-0000-4000-8000-000000000301' and data = '2026-10-03') = 'ausente');
select public.ocorrencia_criar('e2000000-0000-4000-8000-000000000303', 'suspensao', '2026-10-06', 'x', null, 3);
select teste.ok('suspensão cobrindo hoje conta em suspensos_hoje', (public.ocorrencias_resumo() ->> 'suspensos_hoje')::int = 1);
select teste.como_dono();
rollback;
