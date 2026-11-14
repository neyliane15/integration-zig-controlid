-- 58_comissao_presenca.sql — adendo extras v3 §E.7: presença do dia (ponto → escala → fallback individual; falta, suspensão,
-- férias, atestado e fora do vínculo nunca), faltas (validações, ponto, escala, anexo, trava), desligamento recalcula rascunho,
-- extras sem pontuação (importação, fechar recusado, extra_definir_pontuacao), vetores V7/V7b/V8/V8b e fechado imutável.
begin;
set local app.agora = '2026-09-10 12:00:00-03';
select teste.como_dono();
insert into public.empresas (id, nome, fuso, virada_dia) values
  ('e5800000-0000-4000-8000-00000000000a', 'Presença A', 'America/Sao_Paulo', '05:00');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e5800000-0000-4000-8000-000000000a01', 'cp.adm@teste.local', '{"nome":"Adm P"}'),
  ('e5800000-0000-4000-8000-000000000a02', 'cp.ger@teste.local', '{"nome":"Gerente P"}'),
  ('e5800000-0000-4000-8000-000000000a03', 'cp.lei@teste.local', '{"nome":"Leitura P"}');
update public.perfis set papel = 'administrador', empresa_id = 'e5800000-0000-4000-8000-00000000000a' where id = 'e5800000-0000-4000-8000-000000000a01';
update public.perfis set papel = 'gerente', empresa_id = 'e5800000-0000-4000-8000-00000000000a' where id = 'e5800000-0000-4000-8000-000000000a02';
update public.perfis set papel = 'leitura', empresa_id = 'e5800000-0000-4000-8000-00000000000a' where id = 'e5800000-0000-4000-8000-000000000a03';
insert into public.funcionarios (id, empresa_id, nome, cargo, pontos_comissao, data_admissao) values
  ('e5800000-0000-4000-8000-000000000301', 'e5800000-0000-4000-8000-00000000000a', 'Ana Souza', 'Garçom', 10, '2026-01-01'),
  ('e5800000-0000-4000-8000-000000000302', 'e5800000-0000-4000-8000-00000000000a', 'Bruno Lima', 'Garçom', 10, '2026-01-01'),
  ('e5800000-0000-4000-8000-000000000303', 'e5800000-0000-4000-8000-00000000000a', 'Carla Dias', 'Cumim', 6, '2026-01-01'),
  ('e5800000-0000-4000-8000-000000000304', 'e5800000-0000-4000-8000-00000000000a', 'Davi Rocha', 'Bartender', 8, '2026-01-01'),
  ('e5800000-0000-4000-8000-000000000305', 'e5800000-0000-4000-8000-00000000000a', 'Eva Martins', 'Cozinha', 4, '2026-01-01');
-- jornada ter–dom 18:00–23:00 (300 min)
insert into public.jornadas (id, empresa_id, nome, tolerancia_batida_minutos, tolerancia_diaria_minutos) values
  ('e5800000-0000-4000-8000-000000000201', 'e5800000-0000-4000-8000-00000000000a', 'Noite', 5, 10);
insert into public.jornada_dias (jornada_id, dia_semana, entrada, saida)
select 'e5800000-0000-4000-8000-000000000201', d, '18:00', '23:00' from unnest(array[0, 2, 3, 4, 5, 6]) d;
insert into public.funcionario_jornadas (funcionario_id, jornada_id, vigente_desde)
select f.id, 'e5800000-0000-4000-8000-000000000201', '2026-08-01' from public.funcionarios f
 where f.empresa_id = 'e5800000-0000-4000-8000-00000000000a';
-- Eva está no relógio (Control iD), mas não bate; Ana, Bruno e Carla batem em 01/09
insert into public.integracoes (id, empresa_id, tipo, nome, parametros) values
  ('e5800000-0000-4000-8000-000000000101', 'e5800000-0000-4000-8000-00000000000a', 'controlid_rep', 'REP P', '{}'),
  ('e5800000-0000-4000-8000-000000000102', 'e5800000-0000-4000-8000-00000000000a', 'zig', 'Zig P', '{}');
insert into public.controlid_usuarios (empresa_id, integracao_id, user_id_externo, nome, funcionario_id, vinculo) values
  ('e5800000-0000-4000-8000-00000000000a', 'e5800000-0000-4000-8000-000000000101', '5', 'Eva', 'e5800000-0000-4000-8000-000000000305', 'manual');
insert into public.ponto_batidas (empresa_id, funcionario_id, origem, instante, motivo)
select 'e5800000-0000-4000-8000-00000000000a', f, 'manual', t::timestamptz, 'teste'
  from unnest(array['e5800000-0000-4000-8000-000000000301', 'e5800000-0000-4000-8000-000000000302',
                    'e5800000-0000-4000-8000-000000000303']::uuid[]) f,
       unnest(array['2026-09-01 18:00:00-03', '2026-09-01 23:00:00-03']) t;
select public.ponto_apurar(f.id, '2026-08-25', '2026-09-10') from public.funcionarios f
 where f.empresa_id = 'e5800000-0000-4000-8000-00000000000a';
insert into public.zig_lojas (empresa_id, integracao_id, loja_id_externo, nome) values
  ('e5800000-0000-4000-8000-00000000000a', 'e5800000-0000-4000-8000-000000000102', 'lp', 'Salão');
insert into public.zig_vendas_itens (empresa_id, loja_id_externo, data_operacao, transaction_id, tipo, unit_value, quantidade, valor_total) values
  ('e5800000-0000-4000-8000-00000000000a', 'lp', '2026-09-01', 'p1', 'Tip', 100000, 1, 100000),
  ('e5800000-0000-4000-8000-00000000000a', 'lp', '2026-09-02', 'p2', 'Tip', 50000, 1, 50000),
  ('e5800000-0000-4000-8000-00000000000a', 'lp', '2026-09-03', 'p3', 'Tip', 30000, 1, 30000),
  ('e5800000-0000-4000-8000-00000000000a', 'lp', '2026-09-04', 'p4', 'Tip', 20001, 1, 20001);
insert into storage.buckets (id, name) values ('funcionarios-documentos', 'funcionarios-documentos') on conflict do nothing;
insert into storage.objects (bucket_id, name) values
  ('funcionarios-documentos', 'e5800000-0000-4000-8000-00000000000a/faltas/e5800000-0000-4000-8000-000000000303/a.pdf'),
  ('funcionarios-documentos', 'e5800000-0000-4000-8000-00000000000a/faltas/e5800000-0000-4000-8000-000000000303/b.jpg');

create temp table fp (nome text primary key, id uuid) on commit drop;
grant all on fp to authenticated;
create function pg_temp.pd(p_func uuid, p_data date) returns text language sql as $$
  select situacao || '/' || previsto_minutos || '/' || saldo_minutos || '/' || alarmes_abertos
    from public.ponto_dias where funcionario_id = p_func and data = p_data $$;
grant execute on function pg_temp.pd(uuid, date) to authenticated;

-- ------------------------------------------------------------------ escala: âncora 31/08, Bruno folga fixa QUA
select teste.como('cp.ger@teste.local');
select public.escala_configurar('2026-08-31');
insert into fp select 'setor', public.escala_salvar_setor('Salão');
select public.escala_salvar_membro((select id from fp where nome = 'setor'), f, case when f = 'e5800000-0000-4000-8000-000000000302'::uuid then '{2}'::smallint[] else '{}' end)
  from unnest(array['e5800000-0000-4000-8000-000000000301', 'e5800000-0000-4000-8000-000000000302',
                    'e5800000-0000-4000-8000-000000000303', 'e5800000-0000-4000-8000-000000000304']::uuid[]) f;

-- ------------------------------------------------------------------ faltas: validações
select teste.erro('falta: tipo inválido', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-01', 'x')$$, 'Tipo de falta inválido', '22023');
select teste.erro('falta justificada exige motivo', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-01', 'justificada', '  ')$$, 'Informe o motivo', '22023');
select teste.erro('falta no futuro', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-11', 'injustificada')$$, 'Data no futuro', '22023');
select teste.erro('falta em dia com batidas é recusada', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000301', '2026-09-01', 'injustificada')$$,
  'Funcionário com batidas em 01/09/2026: desconsidere as batidas antes de registrar a falta', '22023');
select teste.erro('falta em folga da escala', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000302', '2026-09-02', 'injustificada')$$,
  'Funcionário de folga na escala em 02/09/2026', '22023');
select teste.como('cp.lei@teste.local');
select teste.erro('leitura não registra falta', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-01', 'injustificada')$$, 'Sem permissão', '42501');
select teste.ok('leitura não vê a tabela de faltas', teste.contar('select * from public.funcionario_faltas') = 0);
select teste.como('cp.ger@teste.local');

-- ------------------------------------------------------------------ cenário V7
select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-01', 'injustificada');
select teste.ok('falta registrada devolve o objeto',
  (select (j ->> 'tipo', j ->> 'funcionario_nome', j ->> 'anexo_anterior') is not distinct from ('justificada'::text, 'Carla Dias'::text, null::text)
     from (select public.falta_registrar('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'justificada', 'Consulta',
                                         'e5800000-0000-4000-8000-00000000000a/faltas/e5800000-0000-4000-8000-000000000303/a.pdf', 'atestado.pdf') j) x));
select public.ocorrencia_criar('e5800000-0000-4000-8000-000000000304', 'suspensao', '2026-09-02', 'Briga', null, 1, '2026-09-02');
select public.escala_ajustar('e5800000-0000-4000-8000-000000000301', '2026-09-03', 'ferias');
select public.ponto_abonar('2026-09-04', '2026-09-04', 'atestado', 'Médico', 'e5800000-0000-4000-8000-000000000303');

select teste.ok('ponto: falta injustificada = previsto, saldo negativo, sem alarme',
  pg_temp.pd('e5800000-0000-4000-8000-000000000304', '2026-09-01') = 'falta_injustificada/300/-300/0');
select teste.ok('ponto: falta justificada = previsto 0, saldo 0, sem alarme',
  pg_temp.pd('e5800000-0000-4000-8000-000000000303', '2026-09-02') = 'falta_justificada/0/0/0');
select teste.ok('ponto: Eva ausente em 01/09 com alarme (sem mudança)',
  pg_temp.pd('e5800000-0000-4000-8000-000000000305', '2026-09-01') = 'ausente/300/-300/1');
select teste.ok('extrato do banco de horas rotula a falta',
  exists (select 1 from public.banco_horas_extrato('e5800000-0000-4000-8000-000000000304', '2026-09-01', '2026-09-01')
           where descricao like 'Falta injustificada%' and minutos = -300));

select teste.erro('abono em dia com falta', $$select public.ponto_abonar('2026-09-02', '2026-09-02', 'folga', null, 'e5800000-0000-4000-8000-000000000303')$$,
  'Dia com falta em 02/09/2026: remova a falta antes', '22023');
select teste.erro('ajuste da escala em dia com falta', $$select public.escala_ajustar('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'folga')$$,
  'Dia com falta em 02/09/2026: remova a falta antes', '22023');
select teste.erro('férias no período com falta', $$select public.escala_ajustar_periodo('e5800000-0000-4000-8000-000000000303', '2026-09-01', '2026-09-03', 'ferias')$$,
  'Dia com falta em 02/09/2026: remova a falta antes', '22023');
select teste.erro('troca em dia com falta', $$select public.escala_trocar('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'e5800000-0000-4000-8000-000000000301')$$,
  'Dia com falta em 02/09/2026: remova a falta antes', '22023');
select teste.erro('suspensão em dia com falta', $$select public.ocorrencia_criar('e5800000-0000-4000-8000-000000000303', 'suspensao', '2026-09-02', 'x', null, 1, '2026-09-02')$$,
  'Dia com falta em 02/09/2026: remova a falta antes', '22023');
select teste.erro('falta em dia de férias (abono da escala)', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000301', '2026-09-03', 'injustificada')$$,
  'Já existe abono para o funcionário em 03/09/2026', '22023');
select teste.erro('falta de status no período da escala é inválida', $$select public.escala_ajustar_periodo('e5800000-0000-4000-8000-000000000301', '2026-09-05', '2026-09-06', 'falta_injustificada')$$,
  'Status inválido', '22023');

-- atalho pela escala e código na escala do mês
select teste.ok('escala_ajustar com status de falta troca o tipo',
  (select x ->> 'falta' from public.escala_ajustar('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'falta_injustificada') x) = 'injustificada');
select public.escala_ajustar('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'falta_justificada', null, 'Consulta');
select teste.ok('escala_mes: célula com falta (FJ) e contagem do membro',
  (select (m -> 'faltas', d ->> 'falta', d ->> 'status') = ('1'::jsonb, 'justificada', 'trabalha')
     from jsonb_array_elements(public.escala_mes('2026-09') -> 'setores') s, jsonb_array_elements(s -> 'membros') m,
          jsonb_array_elements(m -> 'dias') d
    where m ->> 'nome' = 'Carla Dias' and d ->> 'data' = '2026-09-02'));
select teste.ok('falta: anexo mantido no upsert pela escala',
  (select anexo_caminho like '%/a.pdf' from public.funcionario_faltas where funcionario_id = 'e5800000-0000-4000-8000-000000000303'));
select teste.ok('falta_definir_anexo devolve o caminho antigo',
  public.falta_definir_anexo('e5800000-0000-4000-8000-000000000303', '2026-09-02',
    'e5800000-0000-4000-8000-00000000000a/faltas/e5800000-0000-4000-8000-000000000303/b.jpg') like '%/a.pdf');
select teste.erro('anexo fora do padrão', $$select public.falta_definir_anexo('e5800000-0000-4000-8000-000000000303', '2026-09-02', 'x/y.pdf')$$, 'Anexo inválido', '22023');
select teste.erro('anexo inexistente no Storage', $$select public.falta_definir_anexo('e5800000-0000-4000-8000-000000000303', '2026-09-02',
  'e5800000-0000-4000-8000-00000000000a/faltas/e5800000-0000-4000-8000-000000000303/z.pdf')$$, 'Anexo não encontrado no armazenamento', 'P0002');
select teste.ok('faltas_listar', jsonb_array_length(public.faltas_listar('2026-09-01', '2026-09-30')) = 2
  and (public.faltas_listar('2026-09-01', '2026-09-30') -> 0 ->> 'funcionario_nome') = 'Carla Dias');

-- extras: Marcos cadastrado; Zé importado sem pontuação
insert into fp select 'marcos', public.extra_criar('Marcos Freitas', 'Garçom', 5, 18000);
create temp table imp on commit drop as select public.extras_importar($$[
  {"nome": "Zé Pereira", "funcao": "Cumim", "telefone": "21999990000", "documento": null, "valor_diaria_centavos": 15000, "pontos": null,
   "dias_trabalhados": [{"data": "2026-09-03"}]},
  {"nome": "marcos  freitas ", "telefone": "21988887777", "dias_trabalhados": [{"data": "2026-09-03", "valor_centavos": 20000}]},
  {"nome": "  "},
  {"nome": "Rita Gomes", "documento": "123.456.789-00", "pontos": 2.5, "valor_diaria_centavos": 12000, "dias_trabalhados": [{"data": "2026-08-20", "pontos": 3}]},
  {"nome": "Rita G.", "documento": "12345678900", "funcao": "Bar"},
  {"nome": "X", "dias_trabalhados": [{"data": "2020-01-01"}]}
]$$::jsonb) as j;
grant select on imp to authenticated;
select teste.ok('extras_importar: contagens e erros por linha',
  (select j from imp) = '{"lidos": 6, "criados": 2, "atualizados": 2, "dias_lancados": 3, "pendentes_pontuacao": 1,
    "erros": [{"linha": 3, "mensagem": "Informe o nome"}, {"linha": 6, "mensagem": "Data fora do limite"}]}'::jsonb);
select teste.ok('importação: Rita casada pelo documento (um cadastro, função atualizada); X não criado',
  (select count(*) from public.extras where empresa_id = 'e5800000-0000-4000-8000-00000000000a' and nome like 'Rita%') = 1
  and (select (funcao, pontos_padrao, pontos_pendente) = ('Bar'::text, 2.50, false) from public.extras where nome = 'Rita Gomes')
  and not exists (select 1 from public.extras where nome = 'X' and empresa_id = 'e5800000-0000-4000-8000-00000000000a'));
select teste.ok('importação: Marcos atualizado (telefone, dia com pontos do cadastro e valor da linha)',
  (select (telefone, pontos_pendente) = ('21988887777'::text, false) from public.extras where id = (select id from fp where nome = 'marcos'))
  and (select (pontos, valor_centavos, pontos_pendente) = (5.00, 20000::bigint, false) from public.diarias where extra_id = (select id from fp where nome = 'marcos')));
insert into fp select 'ze', id from public.extras where nome = 'Zé Pereira';
select teste.ok('extras_listar destaca a pontuação pendente',
  (select (pontos_pendente, dias_pendentes) = (true, 1) from public.extras_listar() where nome = 'Zé Pereira')
  and (select (pontos, pontos_pendente, valor_centavos) = (0.00, true, 15000::bigint) from public.diarias_listar('2026-09-01', '2026-09-30', p_extra => (select id from fp where nome = 'ze'))));
select teste.erro('importação: lista inválida', $$select public.extras_importar('{"a":1}')$$, 'Lista de extras inválida', '22023');
select teste.ok('importação idempotente: reimportar o dia não duplica',
  (select (public.extras_importar('[{"nome": "Zé Pereira", "dias_trabalhados": [{"data": "2026-09-03"}]}]') ->> 'atualizados')::int = 1)
  and (select count(*) from public.diarias where extra_id = (select id from fp where nome = 'ze')) = 1);

-- ------------------------------------------------------------------ fechamento diário (antes do desligamento)
insert into fp select 'v7', public.comissao_criar_fechamento('2026-09-01', '2026-09-04');
create temp view vfc as select * from public.comissao_fechamentos where id = (select id from fp where nome = 'v7');
create temp view vit as select * from public.comissao_itens where fechamento_id = (select id from fp where nome = 'v7');
create temp view vri as select ri.*, it.funcionario_nome from public.comissao_rateio_itens_dia ri join public.comissao_itens it on it.id = ri.item_id
  where ri.fechamento_id = (select id from fp where nome = 'v7');
grant select on vfc, vit, vri to authenticated;
select teste.ok('antes do desligamento Davi entra em 03 e 04 pela escala',
  (select array_agg(to_char(data, 'DD') order by data) from vri where funcionario_nome = 'Davi Rocha') = array['03', '04']);

-- falta temporária recalcula o rascunho; remover volta
select public.falta_registrar('e5800000-0000-4000-8000-000000000302', '2026-09-04', 'injustificada');
select teste.ok('falta recalcula o rascunho (Bruno sai de 04/09)',
  not exists (select 1 from vri where funcionario_nome = 'Bruno Lima' and data = '2026-09-04'));
select teste.ok('falta_remover devolve o anexo (null)', public.falta_remover('e5800000-0000-4000-8000-000000000302', '2026-09-04') is null);
select teste.ok('falta removida: rascunho recalculado', exists (select 1 from vri where funcionario_nome = 'Bruno Lima' and data = '2026-09-04'));
select teste.erro('remover falta inexistente', $$select public.falta_remover('e5800000-0000-4000-8000-000000000302', '2026-09-04')$$, 'Falta não encontrada', 'P0002');

-- desligamento de Davi em 02/09 (pela tabela, como o front) → rascunho recalculado
update public.funcionarios set data_desligamento = '2026-09-02' where id = 'e5800000-0000-4000-8000-000000000304';
select teste.erro('falta após o desligamento', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000304', '2026-09-03', 'injustificada')$$,
  'Dia fora do vínculo do funcionário', '22023');

select teste.ok('V7: valores por dia',
  (select array_agg(to_char(data, 'DD') || ':' || funcionario_nome || '=' || valor_centavos || case when fallback then '*' else '' end
                    order by data, funcionario_nome) from vri)
  = array['01:Ana Souza=30769', '01:Bruno Lima=30769', '01:Carla Dias=18462',
          '02:Ana Souza=28571', '02:Eva Martins=11429*',
          '03:Bruno Lima=9600', '03:Carla Dias=5760', '03:Eva Martins=3840*', '03:Marcos Freitas=4800',
          '04:Ana Souza=6667', '04:Bruno Lima=6667', '04:Eva Martins=2667*']);
select teste.ok('V7: totais, dias presentes e pendência',
  (select array_agg(funcionario_nome || '=' || valor_centavos || '/' || dias_presentes || '/' || pontos_pendente order by funcionario_nome) from vit)
  = array['Ana Souza=66007/3/false', 'Bruno Lima=47036/3/false', 'Carla Dias=24222/2/false', 'Davi Rocha=0/0/false',
          'Eva Martins=17936/0/false', 'Marcos Freitas=4800/1/false', 'Zé Pereira=0/1/true']
  and (select (base_distribuivel_centavos, dias_sem_presenca, dias_sem_participantes, extras_sem_pontuacao)
         = (160001::bigint, 3, 0, 1) from vfc)
  and (select sum(valor_centavos) from vit) = 160001);

create temp table det on commit drop as select public.comissao_detalhe((select id from fp where nome = 'v7')) as j;
grant select on det to authenticated;
select teste.ok('detalhe: entradas com presença v3 (Davi, Eva, Ana) e extra pendente',
  (select jsonb_path_query_array(i, '$.entrada[*].motivo') from det, jsonb_array_elements(j -> 'itens') i where i ->> 'nome' = 'Davi Rocha')
    = '["falta_injustificada", "suspensao", "fora_vinculo", "fora_vinculo"]'
  and (select jsonb_path_query_array(i, '$.entrada[*].motivo') from det, jsonb_array_elements(j -> 'itens') i where i ->> 'nome' = 'Eva Martins')
    = '["sem_batida", "sem_registro", "sem_registro", "sem_registro"]'
  and (select jsonb_path_query_array(i, '$.entrada[*].origem') from det, jsonb_array_elements(j -> 'itens') i where i ->> 'nome' = 'Ana Souza')
    = '["ponto", "escala", null, "escala"]'
  and (select jsonb_path_query_array(i, '$.entrada[*].bloqueado') from det, jsonb_array_elements(j -> 'itens') i where i ->> 'nome' = 'Carla Dias')
    = '[false, true, false, true]'
  and (select i -> 'entrada' -> 0 ->> 'pendente' from det, jsonb_array_elements(j -> 'itens') i where i ->> 'nome' = 'Zé Pereira') = 'true'
  and (select (j -> 'fechamento' ->> 'extras_sem_pontuacao')::int from det) = 1);

select teste.como('cp.adm@teste.local');
select teste.erro('fechar com extra sem pontuação', $$select public.comissao_fechar((select id from fp where nome = 'v7'))$$,
  'Há extras sem pontuação: preencha antes de fechar', '22023');
select teste.ok('extra_definir_pontuacao aplica aos dias pendentes', public.extra_definir_pontuacao((select id from fp where nome = 'ze'), 3) = 1);
select teste.ok('V7b: 03/09 com Zé 3 pontos',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from vri where data = '2026-09-03')
  = array['Bruno Lima=8571', 'Carla Dias=5143', 'Eva Martins=3429', 'Marcos Freitas=4286', 'Zé Pereira=2571']
  and (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from vit)
  = array['Ana Souza=66007', 'Bruno Lima=46007', 'Carla Dias=23605', 'Davi Rocha=0', 'Eva Martins=17525', 'Marcos Freitas=4286', 'Zé Pereira=2571']
  and (select extras_sem_pontuacao from vfc) = 0);

-- V8: modo período, proporcional
insert into fp select 'v8', public.comissao_criar_fechamento('2026-09-01', '2026-09-04', null, null, true, null, 'periodo');
create temp view pit as select * from public.comissao_itens where fechamento_id = (select id from fp where nome = 'v8');
grant select on pit to authenticated;
select teste.ok('V8: período proporcional pelas mesmas regras de presença',
  (select array_agg(funcionario_nome || '=' || dias_trabalhados || '/' || pontos_efetivos::numeric(10,2) || '/' || valor_centavos order by funcionario_nome) from pit)
  = array['Ana Souza=3/7.50/52174', 'Bruno Lima=3/7.50/52174', 'Carla Dias=2/3.00/20870', 'Davi Rocha=0/0.00/0',
          'Eva Martins=3/3.00/20870', 'Marcos Freitas=1/1.25/8696', 'Zé Pereira=1/0.75/5217']
  and (select sum(valor_centavos) from pit) = 160001);
select public.comissao_atualizar_fechamento((select id from fp where nome = 'v8'), null, null, null, false, null);
select teste.ok('V8b: não proporcional — Davi (todos os dias bloqueados) fica com 0',
  (select array_agg(funcionario_nome || '=' || valor_centavos order by funcionario_nome) from pit)
  = array['Ana Souza=50001', 'Bruno Lima=50000', 'Carla Dias=30000', 'Davi Rocha=0', 'Eva Martins=20000', 'Marcos Freitas=6250', 'Zé Pereira=3750']);

-- fechar e imutabilidade
select public.comissao_fechar((select id from fp where nome = 'v7'));
create temp table antes on commit drop as select id, valor_centavos from public.comissao_itens where fechamento_id = (select id from fp where nome = 'v7');
grant select on antes to authenticated;
select teste.erro('fechado: falta no período', $$select public.falta_registrar('e5800000-0000-4000-8000-000000000302', '2026-09-04', 'injustificada')$$,
  'Período de comissão já fechado', '22023');
select teste.erro('fechado: remover falta do período', $$select public.falta_remover('e5800000-0000-4000-8000-000000000303', '2026-09-02')$$,
  'Período de comissão já fechado', '22023');
update public.funcionarios set data_desligamento = '2026-09-02' where id = 'e5800000-0000-4000-8000-000000000301';
select teste.ok('desligar depois de fechado: fechado não muda; rascunho do período recalcula',
  not exists (select 1 from vit v join antes a on a.id = v.id where v.valor_centavos <> a.valor_centavos)
  and (select dias_trabalhados from pit where funcionario_nome = 'Ana Souza') = 2);

rollback;
