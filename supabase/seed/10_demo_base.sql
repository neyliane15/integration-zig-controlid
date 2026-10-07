-- =====================================================================================================
-- Carga de demonstração — base (backend-1). Senha de todos os usuários: gerente123.
-- Idempotente. Rodar como dono do banco (SQL Editor / psql), depois das migrações.
-- Empresas A "Bar Bossa Nova" e B "Cantina Roma", usuários, integrações (apontando para os mocks locais),
-- jornadas, funcionários e rotinas de tarefa (§15.3).
-- =====================================================================================================

update public.configuracao set master_email = 'master@meudiadegerente.app' where id = 1 and master_email is null;

-- --------------------------------------------------------------------------------------- empresas
insert into public.empresas (id, nome, cnpj, cidade, uf, fuso, virada_dia)
values ('a0000000-0000-4000-8000-00000000000a', 'Bar Bossa Nova', '12345678000195', 'São Paulo', 'SP',
        'America/Sao_Paulo', '05:00'),
       ('b0000000-0000-4000-8000-00000000000b', 'Cantina Roma', '98765432000198', 'Campinas', 'SP',
        'America/Sao_Paulo', '05:00')
on conflict (id) do nothing;

-- --------------------------------------------------------------------------------------- jornadas
insert into public.jornadas (id, empresa_id, nome)
values ('a0000000-0000-4000-8000-000000000201', 'a0000000-0000-4000-8000-00000000000a', 'Salão noite'),
       ('a0000000-0000-4000-8000-000000000202', 'a0000000-0000-4000-8000-00000000000a', 'Cozinha')
on conflict (id) do nothing;

insert into public.jornada_dias (jornada_id, empresa_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
select 'a0000000-0000-4000-8000-000000000201', 'a0000000-0000-4000-8000-00000000000a', d, '17:00', '21:00', '21:30', '01:00'
  from unnest(array[0, 2, 3, 4, 5, 6]) d
on conflict (jornada_id, dia_semana) do nothing;

insert into public.jornada_dias (jornada_id, empresa_id, dia_semana, entrada, saida_intervalo, volta_intervalo, saida)
select 'a0000000-0000-4000-8000-000000000202', 'a0000000-0000-4000-8000-00000000000a', d, '10:00', '14:00', '15:00', '18:00'
  from unnest(array[1, 2, 3, 4, 5, 6]) d
on conflict (jornada_id, dia_semana) do nothing;

-- ----------------------------------------------------------------------------------- funcionários
insert into public.funcionarios (id, empresa_id, nome, matricula, cpf, cargo, zig_employee_name, pontos_comissao, data_admissao)
values
  ('a0000000-0000-4000-8000-000000000301', 'a0000000-0000-4000-8000-00000000000a', 'Ana Souza',   '1', '52998224725', 'Garçom',    'Ana Souza',   10, '2025-01-02'),
  ('a0000000-0000-4000-8000-000000000302', 'a0000000-0000-4000-8000-00000000000a', 'Bruno Lima',  '2', '11144477735', 'Garçom',    'Bruno Lima',  10, '2025-01-02'),
  ('a0000000-0000-4000-8000-000000000303', 'a0000000-0000-4000-8000-00000000000a', 'Carla Dias',  '3', '39053344705', 'Cumim',     'Carla Dias',   6, '2025-01-02'),
  ('a0000000-0000-4000-8000-000000000304', 'a0000000-0000-4000-8000-00000000000a', 'Davi Rocha',  '4', '15350946056', 'Bartender', 'Davi Rocha',   8, '2025-01-02'),
  ('a0000000-0000-4000-8000-000000000305', 'a0000000-0000-4000-8000-00000000000a', 'Eva Martins', '5', '71428793860', 'Cozinha',   'Eva Martins',  4, '2025-01-02'),
  ('b0000000-0000-4000-8000-000000000301', 'b0000000-0000-4000-8000-00000000000b', 'Paolo Bianchi', '1', null,       'Garçom',    'Paolo Bianchi', 5, '2025-01-02')
on conflict (id) do nothing;

insert into public.funcionario_jornadas (funcionario_id, empresa_id, jornada_id, vigente_desde)
select f.id, f.empresa_id,
       case when f.id = 'a0000000-0000-4000-8000-000000000305'
            then 'a0000000-0000-4000-8000-000000000202'::uuid
            else 'a0000000-0000-4000-8000-000000000201'::uuid end,
       '2025-01-02'
  from public.funcionarios f
 where f.id in ('a0000000-0000-4000-8000-000000000301', 'a0000000-0000-4000-8000-000000000302',
                'a0000000-0000-4000-8000-000000000303', 'a0000000-0000-4000-8000-000000000304',
                'a0000000-0000-4000-8000-000000000305')
on conflict (funcionario_id, vigente_desde) do nothing;

-- ---------------------------------------------------------------------------------------- usuários
do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('master@meudiadegerente.app',  'Master da Plataforma', 'master',        null::uuid, null::uuid),
      ('admin@barbossanova.com.br',   'Administrador Bossa',  'administrador', 'a0000000-0000-4000-8000-00000000000a'::uuid, null::uuid),
      ('gerente@barbossanova.com.br', 'Gerente Bossa',        'gerente',       'a0000000-0000-4000-8000-00000000000a'::uuid, null::uuid),
      ('leitura@barbossanova.com.br', 'Ana Souza (leitura)',  'leitura',       'a0000000-0000-4000-8000-00000000000a'::uuid,
                                                                               'a0000000-0000-4000-8000-000000000301'::uuid),
      ('admin@cantinaroma.com.br',    'Administrador Roma',   'administrador', 'b0000000-0000-4000-8000-00000000000b'::uuid, null::uuid)
    ) as t(email, nome, papel, empresa, funcionario)
  loop
    if not exists (select 1 from auth.users where lower(email) = u.email) then
      perform public.admin_criar_usuario(u.email, 'gerente123', u.nome, u.papel, u.empresa, u.funcionario);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------------------------------- integrações
insert into public.integracoes (id, empresa_id, tipo, nome, parametros, intervalo_minutos)
values
  ('a0000000-0000-4000-8000-000000000101', 'a0000000-0000-4000-8000-00000000000a', 'zig', 'Zig',
   '{"rede": "rede-mock", "dias_retroativos": 2}', 60),
  ('a0000000-0000-4000-8000-000000000102', 'a0000000-0000-4000-8000-00000000000a', 'controlid_acesso', 'iDFace porta dos fundos',
   '{"modelo": "iDFace", "dias_retroativos": 2, "eventos_validos": [7], "relogio_em_hora_local": true,
     "envio": {"ativo": true}}', 15),
  ('a0000000-0000-4000-8000-000000000103', 'a0000000-0000-4000-8000-00000000000a', 'controlid_rep', 'iDClass salão',
   '{"modelo": "iDClass", "dias_retroativos": 2, "identificador": "cpf", "envio": {"ativo": false}}', 60)
on conflict (id) do nothing;

insert into public.integracoes_segredos (integracao_id, empresa_id, segredos)
values
  ('a0000000-0000-4000-8000-000000000101', 'a0000000-0000-4000-8000-00000000000a',
   '{"token": "token-mock"}'),
  ('a0000000-0000-4000-8000-000000000102', 'a0000000-0000-4000-8000-00000000000a',
   '{"url": "http://127.0.0.1:54341", "login": "admin", "senha": "admin"}'),
  ('a0000000-0000-4000-8000-000000000103', 'a0000000-0000-4000-8000-00000000000a',
   '{"url": "http://127.0.0.1:54342", "login": "admin", "senha": "admin"}')
on conflict (integracao_id) do nothing;

-- ---------------------------------------------------------------------------------- rotinas de tarefa
insert into public.tarefas_rotinas (id, empresa_id, titulo, descricao, recorrencia, dias_semana, horario_limite, prioridade)
values
  ('a0000000-0000-4000-8000-000000000401', 'a0000000-0000-4000-8000-00000000000a', 'Abrir caixa',
   'Conferir troco, ligar maquininhas e abrir o caixa no Zig.', 'diaria', '{}', '16:30', 'alta'),
  ('a0000000-0000-4000-8000-000000000402', 'a0000000-0000-4000-8000-00000000000a', 'Conferir estoque do bar',
   'Contagem de destilados, cervejas e insumos de drinks.', 'semanal', '{2,5}', '18:00', 'normal')
on conflict (id) do nothing;

insert into public.tarefas_rotina_itens (id, rotina_id, empresa_id, ordem, texto)
values
  ('a0000000-0000-4000-8000-000000000411', 'a0000000-0000-4000-8000-000000000401', 'a0000000-0000-4000-8000-00000000000a', 1, 'Conferir fundo de troco'),
  ('a0000000-0000-4000-8000-000000000412', 'a0000000-0000-4000-8000-000000000401', 'a0000000-0000-4000-8000-00000000000a', 2, 'Ligar e testar as maquininhas'),
  ('a0000000-0000-4000-8000-000000000413', 'a0000000-0000-4000-8000-000000000401', 'a0000000-0000-4000-8000-00000000000a', 3, 'Abrir o caixa no Zig')
on conflict (id) do nothing;
