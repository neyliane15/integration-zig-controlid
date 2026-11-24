-- Meu Dia de Gerente — instalação do banco, PARTE 08 DE 21.
-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.
-- Gerado por ferramentas/dividir-instalar.py a partir de: 20261006000200_ponto.sql. Não edite à mão.

begin;
-- §7.2/§7.3. Não grava nada. Retorna 0 linhas se o funcionário não existe; fora_do_vinculo = true se D fora do vínculo.
create or replace function public.ponto_calcular_dia(p_funcionario uuid, p_data date)
returns table (
  funcionario_id      uuid,
  data                date,
  empresa_id          uuid,
  fora_do_vinculo     boolean,
  jornada_id          uuid,
  jornada_nome        text,
  abono_tipo          text,
  batidas_esperadas   smallint,
  batidas_validas     smallint,
  batidas_duplicadas  smallint,
  previsto_minutos    int,
  trabalhado_minutos  int,
  saldo_minutos       int,
  atraso_minutos      int,
  primeira_batida     timestamptz,
  ultima_batida       timestamptz,
  situacao            text,
  encerrado           boolean,
  batidas             jsonb,
  esperadas           jsonb,
  alarmes             jsonb
)
language plpgsql stable security definer set search_path = public, extensions, pg_temp as $$
declare
  f            record;
  e            record;
  j            record;
  jd           record;
  v_abono      text;
  v_slots      timestamptz[] := '{}';
  v_nomes      text[] := '{}';
  v_validas    timestamptz[] := '{}';
  v_ultima     timestamptz;
  v_dup        boolean;
  v_dups       int := 0;
  v_n          int;
  v_k          int;
  v_trab       int := 0;
  v_prev       int := 0;
  v_saldo      int := 0;
  v_atraso     int := 0;
  v_tol_dia    int := 0;
  v_tol_bat    int := 0;
  v_batidas    jsonb := '[]'::jsonb;
  v_esperadas  jsonb := '[]'::jsonb;
  v_alarmes    jsonb := '[]'::jsonb;
  v_encerrado  boolean;
  v_situacao   text;
  b            record;
  i            int;
  v_mask       int;
  v_idx        int[];
  v_custo      numeric;
  v_melhor     int[];
  v_melhor_c   numeric;
  v_esc        record;
  v_desloc     interval;
  v_falta      text;
  v_ext_prev   int;
  v_ext_hor    time[];
  v_ext_tol_e  int;
  v_ext_tol_f  int;
  v_ult_idx    int;
  v_tol_atraso int;
  v_chegada    timestamptz;
  v_alarme_ok  boolean;
  v_rotulos    constant jsonb := '{"entrada": "a entrada", "saida_intervalo": "a saída para o intervalo",
                                    "volta_intervalo": "a volta do intervalo", "saida": "a saída"}'::jsonb;
begin
  select * into f from public.funcionarios fu where fu.id = p_funcionario;
  if not found then return; end if;
  select * into e from public.empresas em where em.id = f.empresa_id;

  funcionario_id := f.id;
  data := p_data;
  empresa_id := f.empresa_id;

  if not public.ponto_no_vinculo(f.data_admissao, f.data_desligamento, p_data) then
    fora_do_vinculo := true;
    batidas_esperadas := 0; batidas_validas := 0; batidas_duplicadas := 0;
    previsto_minutos := 0; trabalhado_minutos := 0; saldo_minutos := 0; atraso_minutos := 0;
    encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);
    batidas := '[]'; esperadas := '[]'; alarmes := '[]';
    return next;
    return;
  end if;
  fora_do_vinculo := false;
  v_encerrado := p_data < public.dia_de_trabalho(public.agora(), f.empresa_id);

  -- 2. Escala e abono
  select jo.id, jo.nome, jo.tolerancia_batida_minutos, jo.tolerancia_diaria_minutos into j
    from public.funcionario_jornadas fj
    join public.jornadas jo on jo.id = fj.jornada_id
   where fj.funcionario_id = f.id and fj.vigente_desde <= p_data
   order by fj.vigente_desde desc
   limit 1;
  if j.id is not null then
    v_tol_dia := j.tolerancia_diaria_minutos;
    v_tol_bat := j.tolerancia_batida_minutos;
  end if;

  select a.tipo into v_abono
    from public.ponto_abonos a
   where a.empresa_id = f.empresa_id and a.data = p_data
     and (a.funcionario_id = f.id or a.funcionario_id is null)
   order by a.funcionario_id nulls last
   limit 1;

  -- (adendo escala §S.5) status da escala rotativa: folga/férias = não escalado; trabalha = escalado com a jornada,
  -- deslocada para a chegada da escala. null = funcionário fora da escala (só a jornada vale).
  select * into v_esc from public.escala_status_ponto(f.id, p_data);

  -- (adendo extras v3, §E.7.2) falta registrada: prevalece sobre abono da empresa e escala. Justificada = como abono
  -- (previsto 0); injustificada = dia previsto normal (saldo −previsto sem batida), sem alarmes.
  v_falta := public.ponto_falta_do_dia(f.id, p_data);
  if v_falta is not null then v_abono := null; end if;

  v_k := 0;
  -- abono 'compensacao' (folga de banco de horas): o dia continua previsto — sem batida, o saldo fica −previsto (sai do
  -- banco de horas) —, mas sem batidas esperadas nem alarmes
  if (v_abono is null or v_abono = 'compensacao') and v_falta is distinct from 'justificada' and j.id is not null
     and v_esc.status is distinct from 'folga' and v_esc.status is distinct from 'ferias' then
    select * into jd from public.jornada_dias x
     where x.jornada_id = j.id and x.dia_semana = extract(dow from p_data)::smallint;
    if not found and v_esc.status = 'trabalha' then
      -- jornada sem este dia da semana: usa o primeiro dia cadastrado (SEG→DOM) como modelo de horários
      select * into jd from public.jornada_dias x
       where x.jornada_id = j.id order by (x.dia_semana + 6) % 7 limit 1;
    end if;
    if found then
      v_prev := jd.minutos_previstos;
      v_k := jd.batidas_esperadas;
      if v_k = 4 then
        v_nomes := array['entrada', 'saida_intervalo', 'volta_intervalo', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.volta_intervalo, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      else
        v_nomes := array['entrada', 'saida'];
        v_slots := array[
          public.ponto_instante_escala(p_data, jd.entrada, e.fuso, e.virada_dia),
          public.ponto_instante_escala(p_data, jd.saida, e.fuso, e.virada_dia)];
      end if;
      if v_esc.chegada is not null then
        v_desloc := public.ponto_instante_escala(p_data, v_esc.chegada, e.fuso, e.virada_dia) - v_slots[1];
        for i in 1 .. v_k loop
          v_slots[i] := v_slots[i] + v_desloc;
        end loop;
      end if;
      for i in 1 .. v_k loop
        v_esperadas := v_esperadas || jsonb_build_object('batida', v_nomes[i], 'instante', v_slots[i]);
      end loop;
    end if;
  end if;

  -- (adendo RHiD §R.9) previsto importado do RHiD (apuração do RHiD por dia: horário contratual, folga, feriado):
  -- prevalece sobre jornada e escala. Folga/feriado = previsto 0 (o trabalhado vira saldo positivo, como no RHiD).
  if (v_abono is null or v_abono = 'compensacao') and v_falta is distinct from 'justificada' then
    select x.previsto_minutos, x.horarios, x.tolerancia_extra_minutos, x.tolerancia_falta_minutos
      into v_ext_prev, v_ext_hor, v_ext_tol_e, v_ext_tol_f
      from public.ponto_previsto_externo_dia(f.id, p_data) x;
    if v_ext_prev is not null then
      v_prev := v_ext_prev;
      v_k := 0;
      v_slots := '{}';
      v_nomes := '{}';
      v_esperadas := '[]'::jsonb;
      if v_prev > 0 and coalesce(array_length(v_ext_hor, 1), 0) in (2, 4) then
        v_k := array_length(v_ext_hor, 1);
        v_nomes := case when v_k = 4 then array['entrada', 'saida_intervalo', 'volta_intervalo', 'saida']
                        else array['entrada', 'saida'] end;
        for i in 1 .. v_k loop
          v_slots := v_slots || public.ponto_instante_escala(p_data, v_ext_hor[i], e.fuso, e.virada_dia);
        end loop;
        -- horário de chegada da escala do dia: desloca os horários (o atraso é contado a partir dela)
        if v_esc.chegada is not null then
          v_desloc := public.ponto_instante_escala(p_data, v_esc.chegada, e.fuso, e.virada_dia) - v_slots[1];
          for i in 1 .. v_k loop
            v_slots[i] := v_slots[i] + v_desloc;
          end loop;
        end if;
        for i in 1 .. v_k loop
          v_esperadas := v_esperadas || jsonb_build_object('batida', v_nomes[i], 'instante', v_slots[i]);
        end loop;
      end if;
    end if;
  end if;

  if v_abono = 'compensacao' then
    v_k := 0;
    v_slots := '{}';
    v_nomes := '{}';
    v_esperadas := '[]'::jsonb;
  end if;

  -- 3. Batidas (duplicadas: a menos de N minutos da última válida; entrada repetida vale a 1ª, saída repetida vale a última)
  for b in
    select pb.id, pb.instante, pb.origem, pb.desconsiderada, pb.motivo
      from public.ponto_batidas pb
     where pb.funcionario_id = f.id and pb.data_trabalho = p_data
     order by pb.instante, pb.id
  loop
    v_dup := false;
    if not b.desconsiderada then
      if v_ultima is not null and b.instante - v_ultima < make_interval(mins => e.ponto_janela_duplicada_minutos) then
        v_dups := v_dups + 1;
        if array_length(v_validas, 1) % 2 = 0 then
          -- repetiu a SAÍDA (válidas em nº par): vale a última (como no RHiD); a anterior vira duplicada
          v_batidas := jsonb_set(v_batidas, array[v_ult_idx::text, 'duplicada'], 'true'::jsonb);
          v_validas[array_length(v_validas, 1)] := b.instante;
          v_ultima := b.instante;
          v_ult_idx := jsonb_array_length(v_batidas);
        else
          v_dup := true;   -- repetiu a ENTRADA: vale a primeira
        end if;
      else
        v_validas := v_validas || b.instante;
        v_ultima := b.instante;
        v_ult_idx := jsonb_array_length(v_batidas);
      end if;
    end if;
    v_batidas := v_batidas || jsonb_build_object('id', b.id, 'instante', b.instante, 'origem', b.origem,
                                                 'desconsiderada', b.desconsiderada, 'duplicada', v_dup, 'motivo', b.motivo);
  end loop;
  v_n := coalesce(array_length(v_validas, 1), 0);

  -- 4. Trabalhado
  i := 1;
  while i + 1 <= v_n loop
    v_trab := v_trab + floor(extract(epoch from (v_validas[i + 1] - v_validas[i])) / 60)::int;
    i := i + 2;
  end loop;

  -- 5. Saldo
  if not v_encerrado then
    v_saldo := 0;
  elsif v_prev > 0 then
    if v_n = 0 then
      v_saldo := -v_prev;
    elsif v_ext_prev is not null and v_trab >= v_prev and v_trab - v_prev <= coalesce(v_ext_tol_e, v_tol_dia) then
      v_saldo := 0;   -- tolerância do horário do RHiD (CLT: até 10 min/dia)
    elsif v_ext_prev is not null and v_trab < v_prev and v_prev - v_trab <= coalesce(v_ext_tol_f, v_tol_dia) then
      v_saldo := 0;
    elsif v_ext_prev is null and abs(v_trab - v_prev) <= v_tol_dia then
      v_saldo := 0;
    else
      v_saldo := v_trab - v_prev;
    end if;
  elsif j.id is null and v_ext_prev is null and v_esc.status is distinct from 'folga'
        and v_esc.status is distinct from 'ferias' then
    v_saldo := 0;   -- sem horário previsto (sem jornada nem horário do RHiD): não há como saber a hora extra
  else
    v_saldo := v_trab;   -- folga/feriado (ou dia fora da jornada) trabalhado: tudo extra
  end if;

  -- Quais slots foram batidos (0 < n < k): menor Σ|batida − slot|; empate → combinação lexicograficamente menor (§7.3).
  -- Calculado também no dia em andamento, para o atraso abaixo.
  v_melhor := null;
  if v_n > 0 and v_n < v_k then
    for v_mask in 0 .. (1 << v_k) - 1 loop
      v_idx := '{}';
      for i in 1 .. v_k loop
        if (v_mask >> (i - 1)) & 1 = 1 then v_idx := v_idx || i; end if;
      end loop;
      continue when coalesce(array_length(v_idx, 1), 0) <> v_n;
      v_custo := 0;
      for i in 1 .. v_n loop
        v_custo := v_custo + abs(extract(epoch from (v_validas[i] - v_slots[v_idx[i]])));
      end loop;
      if v_melhor is null or v_custo < v_melhor_c or (v_custo = v_melhor_c and v_idx < v_melhor) then
        v_melhor := v_idx;
        v_melhor_c := v_custo;
      end if;
    end loop;
  end if;

  -- 6. Atraso: só se a 1ª batida corresponde à entrada (se a entrada faltou, o alarme é "batida faltando", não atraso).
  -- Referência: a entrada prevista (jornada ou horário do RHiD, deslocada para a chegada da escala). Sem horários mas
  -- escalado com chegada: a chegada da escala. Tolerância: a do horário do RHiD (CLT 10) ou a da jornada; sem nenhuma, 5.
  v_tol_atraso := case when v_ext_prev is not null then coalesce(v_ext_tol_f, v_tol_bat)
                       when j.id is not null then v_tol_bat else 5 end;
  -- Quem é membro da escala rotativa só tem atraso no dia em que a escala informa a chegada — inclusive antes de a escala
  -- começar (o horário do RHiD costuma ser genérico, ex.: 08:00 para todos; sem a chegada do dia não dá para saber).
  if v_k > 0 and v_n > 0 and (v_melhor is null or 1 = any (v_melhor))
     and (v_esc.chegada is not null
          or not exists (select 1 from public.escala_membros em where em.funcionario_id = f.id)) then
    v_atraso := greatest(0, floor(extract(epoch from (v_validas[1] - v_slots[1])) / 60)::int);
    if v_atraso <= v_tol_atraso then v_atraso := 0; end if;
  elsif v_k = 0 and v_n > 0 and v_abono is null and v_esc.status = 'trabalha' and v_esc.chegada is not null then
    v_chegada := public.ponto_instante_escala(p_data, v_esc.chegada, e.fuso, e.virada_dia);
    v_atraso := greatest(0, floor(extract(epoch from (v_validas[1] - v_chegada)) / 60)::int);
    if v_atraso <= v_tol_atraso or v_atraso > 6 * 60 then v_atraso := 0; end if;   -- > 6 h: outra escala, não atraso
  end if;

  -- 7. Situação
  if v_falta is not null then v_situacao := 'falta_' || v_falta;
  elsif not v_encerrado then v_situacao := 'em_andamento';
  elsif v_abono = 'suspensao' then v_situacao := 'suspenso';
  elsif v_abono is not null then v_situacao := 'abonado';
  elsif v_k = 0 and v_n = 0 and v_prev = 0 then
    v_situacao := case when v_esc.status in ('folga', 'ferias') or j.id is not null or v_ext_prev is not null
                       then 'folga' else 'sem_escala' end;
  elsif v_n = 0 then v_situacao := 'ausente';
  elsif v_n >= v_k and v_n % 2 = 0 then v_situacao := 'completo';
  else v_situacao := 'incompleto';
  end if;

  -- 8. Alarmes (§7.3) — dia abonado ou com falta registrada não gera alarme; só os últimos ponto_alarme_prazo_dias
  -- (padrão 2): dias mais antigos não têm alarme aberto (o que havia é resolvido automaticamente)
  v_alarme_ok := p_data >= public.dia_de_trabalho(public.agora(), f.empresa_id) - e.ponto_alarme_prazo_dias;
  if v_abono is null and v_falta is null and v_alarme_ok then
    if v_encerrado then
      if v_k > 0 and v_n = 0 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'sem_batida_dia_escalado', 'batida_esperada', '', 'horario_previsto', v_slots[1], 'minutos', null,
          'detalhe', format('Nenhuma batida em dia de escala (%s–%s)',
                            to_char(v_slots[1] at time zone e.fuso, 'HH24:MI'),
                            to_char(v_slots[v_k] at time zone e.fuso, 'HH24:MI')));
      elsif v_n > 0 and v_n < v_k then
        -- slots não batidos (v_melhor calculado acima): um alarme por batida faltante
        for i in 1 .. v_k loop
          if not (i = any (v_melhor)) then
            v_alarmes := v_alarmes || jsonb_build_object(
              'tipo', 'batida_faltando', 'batida_esperada', v_nomes[i], 'horario_previsto', v_slots[i], 'minutos', null,
              'detalhe', format('Faltou %s (%s)', v_rotulos ->> v_nomes[i], to_char(v_slots[i] at time zone e.fuso, 'HH24:MI')));
          end if;
        end loop;
      elsif v_k = 0 and v_n > 0 and v_n < (case when j.id is not null and v_ext_prev is null
                                              then coalesce((select max(x.batidas_esperadas) from public.jornada_dias x
                                                              where x.jornada_id = j.id), e.ponto_batidas_minimas)
                                              else e.ponto_batidas_minimas end) then
        -- sem horário previsto no dia (folga, sem escala): alerta quem bateu menos que o mínimo — o da jornada (2 ou 4) ou,
        -- sem jornada, o da empresa (ponto_batidas_minimas, padrão 4; 0 desliga)
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'poucas_batidas', 'batida_esperada', '', 'horario_previsto', null, 'minutos', null,
          'detalhe', format('%s %s no dia (menos que o mínimo de batidas)', v_n, case when v_n = 1 then 'batida' else 'batidas' end));
      elsif v_n % 2 = 1 then
        v_alarmes := v_alarmes || jsonb_build_object(
          'tipo', 'batidas_impares', 'batida_esperada', '', 'horario_previsto', null, 'minutos', null,
          'detalhe', format('%s %s (número ímpar)', v_n, case when v_n = 1 then 'batida' else 'batidas' end));
      end if;
    end if;
    if e.ponto_alarme_atraso and v_atraso > 0 then
      v_alarmes := v_alarmes || jsonb_build_object(
        'tipo', 'atraso', 'batida_esperada', 'entrada', 'horario_previsto', coalesce(v_slots[1], v_chegada), 'minutos', v_atraso,
        'detalhe', format('Entrada %s (%s min de atraso)', to_char(v_validas[1] at time zone e.fuso, 'HH24:MI'), v_atraso));
    end if;
  end if;

  jornada_id := j.id;
  jornada_nome := j.nome;
  abono_tipo := v_abono;
  batidas_esperadas := v_k;
  batidas_validas := v_n;
  batidas_duplicadas := v_dups;
  previsto_minutos := v_prev;
  trabalhado_minutos := v_trab;
  saldo_minutos := v_saldo;
  atraso_minutos := v_atraso;
  primeira_batida := v_validas[1];
  ultima_batida := case when v_n > 0 then v_validas[v_n] end;
  situacao := v_situacao;
  encerrado := v_encerrado;
  batidas := v_batidas;
  esperadas := v_esperadas;
  alarmes := v_alarmes;
  return next;
end $$;
comment on function public.ponto_calcular_dia(uuid, date) is '[interno] Cálculo de um dia de ponto (§7.2/§7.3). Não grava.';

-- ============================================================ persistência
create or replace function public.ponto_contar_alarmes(p_funcionario uuid, p_data date)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  update public.ponto_dias d
     set alarmes_abertos = (select count(*) from public.ponto_alarmes a
                             where a.funcionario_id = p_funcionario and a.data = p_data and a.status = 'aberto')
   where d.funcionario_id = p_funcionario and d.data = p_data
$$;
comment on function public.ponto_contar_alarmes(uuid, date) is '[interno] Atualiza ponto_dias.alarmes_abertos.';

create or replace function public.ponto_apurar(p_funcionario uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_empresa  uuid;
  v_atual    date;
  v_dia      date;
  c          record;
  a          jsonb;
  v_chaves   text[];
  v_total    int := 0;
begin
  if p_funcionario is null or p_inicio is null or p_fim is null then return 0; end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = p_funcionario;
  if v_empresa is null then return 0; end if;     -- funcionário excluído (cascata) → nada a fazer
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);

  for v_dia in select g::date from generate_series(p_inicio, least(p_fim, v_atual), interval '1 day') g loop
    select * into c from public.ponto_calcular_dia(p_funcionario, v_dia);

    if c.fora_do_vinculo then
      delete from public.ponto_dias where funcionario_id = p_funcionario and data = v_dia;
      update public.ponto_alarmes
         set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
       where funcionario_id = p_funcionario and data = v_dia and status = 'aberto';
      continue;
    end if;

    insert into public.ponto_dias as d (
      funcionario_id, data, empresa_id, jornada_id, abono_tipo, batidas_esperadas, batidas_validas, batidas_duplicadas,
      previsto_minutos, trabalhado_minutos, saldo_minutos, atraso_minutos, primeira_batida, ultima_batida,
      situacao, encerrado, apurado_em)
    values (
      p_funcionario, v_dia, v_empresa, c.jornada_id, c.abono_tipo, c.batidas_esperadas, c.batidas_validas, c.batidas_duplicadas,
      c.previsto_minutos, c.trabalhado_minutos, c.saldo_minutos, c.atraso_minutos, c.primeira_batida, c.ultima_batida,
      c.situacao, c.encerrado, public.agora())
    on conflict (funcionario_id, data) do update set
      jornada_id = excluded.jornada_id, abono_tipo = excluded.abono_tipo,
      batidas_esperadas = excluded.batidas_esperadas, batidas_validas = excluded.batidas_validas,
      batidas_duplicadas = excluded.batidas_duplicadas, previsto_minutos = excluded.previsto_minutos,
      trabalhado_minutos = excluded.trabalhado_minutos, saldo_minutos = excluded.saldo_minutos,
      atraso_minutos = excluded.atraso_minutos, primeira_batida = excluded.primeira_batida,
      ultima_batida = excluded.ultima_batida, situacao = excluded.situacao, encerrado = excluded.encerrado,
      apurado_em = excluded.apurado_em;

    v_chaves := '{}';
    for a in select * from jsonb_array_elements(c.alarmes) loop
      v_chaves := v_chaves || ((a ->> 'tipo') || '|' || (a ->> 'batida_esperada'));
      insert into public.ponto_alarmes as pa (
        empresa_id, funcionario_id, data, tipo, batida_esperada, horario_previsto, minutos, detalhe, status)
      values (
        v_empresa, p_funcionario, v_dia, a ->> 'tipo', a ->> 'batida_esperada',
        (a ->> 'horario_previsto')::timestamptz, (a ->> 'minutos')::int, a ->> 'detalhe', 'aberto')
      on conflict (funcionario_id, data, tipo, batida_esperada) do update set
        detalhe = excluded.detalhe,
        horario_previsto = excluded.horario_previsto,
        minutos = excluded.minutos,
        status = case when pa.status = 'resolvido' then 'aberto' else pa.status end,
        resolvido_em = case when pa.status = 'resolvido' then null else pa.resolvido_em end,
        resolvido_automaticamente = case when pa.status = 'resolvido' then false else pa.resolvido_automaticamente end
      where pa.status = 'resolvido'
         or (pa.detalhe, pa.horario_previsto, pa.minutos)
            is distinct from (excluded.detalhe, excluded.horario_previsto, excluded.minutos);
    end loop;

    update public.ponto_alarmes
       set status = 'resolvido', resolvido_automaticamente = true, resolvido_em = public.agora()
     where funcionario_id = p_funcionario and data = v_dia and status = 'aberto'
       and not ((tipo || '|' || batida_esperada) = any (v_chaves));

    perform public.ponto_contar_alarmes(p_funcionario, v_dia);
    v_total := v_total + 1;
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar(uuid, date, date) is '[interno] Apura e persiste ponto_dias/ponto_alarmes (§7.4). Retorna dias apurados.';

-- Apura todos os funcionários de uma empresa (os que têm algum dia de vínculo no período).
create or replace function public.ponto_apurar_empresa(p_empresa uuid, p_inicio date, p_fim date)
returns int language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_total int := 0; f record;
begin
  for f in
    select fu.id from public.funcionarios fu
     where fu.empresa_id = p_empresa
       and (fu.data_admissao is null or fu.data_admissao <= p_fim)
       and (fu.data_desligamento is null or fu.data_desligamento >= p_inicio)
     order by fu.id
  loop
    v_total := v_total + public.ponto_apurar(f.id, p_inicio, p_fim);
  end loop;
  return v_total;
end $$;
comment on function public.ponto_apurar_empresa(uuid, date, date) is '[interno] Apura todos os funcionários da empresa no período.';

-- ======================================================= gatilhos em tabelas do backend-1 (§7.8)
create or replace function public.ponto_gatilho_controlid_usuario()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_antigo uuid := case when tg_op = 'UPDATE' then old.funcionario_id end;
  v_alvo   uuid := new.funcionario_id;
  v_origem text;
  v_datas  date[];
  v_dia    date;
begin
  select case when i.tipo in ('controlid_rep', 'rhid') then 'controlid_rep' else 'controlid_acesso' end into v_origem
    from public.integracoes i where i.id = new.integracao_id;
  -- REP (user_id_externo = CPF/PIS): sem vínculo, a batida volta ao funcionário com esse CPF/PIS na ficha (como na ingestão)
  if v_origem = 'controlid_rep' and v_alvo is null then
    select f.id into v_alvo from public.funcionarios f
     where f.empresa_id = new.empresa_id and (f.cpf = new.user_id_externo or f.pis = new.user_id_externo)
     order by f.id limit 1;
  end if;
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = v_alvo
     where b.integracao_id = new.integracao_id
       and b.pessoa_externa = new.user_id_externo
       and b.origem = v_origem
       and (b.funcionario_id is null or b.funcionario_id = v_antigo)
       and b.funcionario_id is distinct from v_alvo
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;

  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(v_antigo, v_dia, v_dia);
      perform public.ponto_apurar(v_alvo, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_controlid_usuario() is
  '[interno] §7.8: vínculo Control iD → batidas (acesso pelo id do usuário; REP pelo CPF/PIS) e reapuração.';

drop trigger if exists ponto_vinculo_batidas on public.controlid_usuarios;
create trigger ponto_vinculo_batidas after update of funcionario_id on public.controlid_usuarios
  for each row when (old.funcionario_id is distinct from new.funcionario_id)
  execute function public.ponto_gatilho_controlid_usuario();
drop trigger if exists ponto_vinculo_batidas_ins on public.controlid_usuarios;
create trigger ponto_vinculo_batidas_ins after insert on public.controlid_usuarios
  for each row when (new.funcionario_id is not null)
  execute function public.ponto_gatilho_controlid_usuario();

create or replace function public.ponto_gatilho_funcionario_documentos()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_datas date[]; v_dia date;
begin
  if new.cpf is null and new.pis is null then return null; end if;
  with alt as (
    update public.ponto_batidas b
       set funcionario_id = new.id
     where b.empresa_id = new.empresa_id
       and b.origem = 'controlid_rep'
       and b.funcionario_id is null
       and b.pessoa_externa is not null
       and b.pessoa_externa in (new.cpf, new.pis)
    returning b.data_trabalho)
  select array_agg(distinct alt.data_trabalho) into v_datas from alt;
  if v_datas is not null then
    foreach v_dia in array v_datas loop
      perform public.ponto_apurar(new.id, v_dia, v_dia);
    end loop;
  end if;
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_documentos() is '[interno] §7.8: CPF/PIS do funcionário → batidas REP sem vínculo.';

drop trigger if exists ponto_documentos on public.funcionarios;
create trigger ponto_documentos after insert or update of cpf, pis on public.funcionarios
  for each row execute function public.ponto_gatilho_funcionario_documentos();

create or replace function public.ponto_gatilho_funcionario_vinculo()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_atual date;
begin
  v_atual := public.dia_de_trabalho(public.agora(), new.empresa_id);
  perform public.ponto_apurar(new.id, v_atual - 93, v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_vinculo() is '[interno] §7.8: mudança de admissão/desligamento/ativo → reapura 93 dias.';

drop trigger if exists ponto_vinculo on public.funcionarios;
create trigger ponto_vinculo after update of data_admissao, data_desligamento, ativo on public.funcionarios
  for each row
  when (old.data_admissao is distinct from new.data_admissao
        or old.data_desligamento is distinct from new.data_desligamento
        or old.ativo is distinct from new.ativo)
  execute function public.ponto_gatilho_funcionario_vinculo();

create or replace function public.ponto_gatilho_funcionario_jornada()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_func   uuid;
  v_desde  date;
  v_empresa uuid;
  v_atual  date;
begin
  if tg_op = 'DELETE' then
    v_func := old.funcionario_id; v_desde := old.vigente_desde;
  elsif tg_op = 'UPDATE' then
    v_func := new.funcionario_id; v_desde := least(old.vigente_desde, new.vigente_desde);
    if old.funcionario_id is distinct from new.funcionario_id then
      select f.empresa_id into v_empresa from public.funcionarios f where f.id = old.funcionario_id;
      if v_empresa is not null then
        v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
        perform public.ponto_apurar(old.funcionario_id, greatest(old.vigente_desde, v_atual - 93), v_atual);
      end if;
    end if;
  else
    v_func := new.funcionario_id; v_desde := new.vigente_desde;
  end if;
  select f.empresa_id into v_empresa from public.funcionarios f where f.id = v_func;
  if v_empresa is null then return null; end if;
  v_atual := public.dia_de_trabalho(public.agora(), v_empresa);
  perform public.ponto_apurar(v_func, greatest(v_desde, v_atual - 93), v_atual);
  return null;
end $$;
comment on function public.ponto_gatilho_funcionario_jornada() is '[interno] §7.8: escala do funcionário mudou → reapura desde vigente_desde (máx. 93 dias).';

drop trigger if exists ponto_reapurar on public.funcionario_jornadas;
create trigger ponto_reapurar after insert or update or delete on public.funcionario_jornadas
  for each row execute function public.ponto_gatilho_funcionario_jornada();

commit;
select 'parte 08 de 21 instalada' as resultado;
