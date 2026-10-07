import { useId, useMemo, useState } from 'react'
import { ArrowLeft, CalendarClock, Copy, Pencil, Plus, Trash2 } from 'lucide-react'
import {
  Botao,
  CabecalhoPagina,
  Campo,
  Carregando,
  Cartao,
  Entrada,
  EntradaHora,
  ErroCarga,
  Interruptor,
  Modal,
  Selo,
  Vazio,
} from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { useExcluirJornada, useJornadas, useSalvarJornada, type JornadaComDias } from '@/consultas/funcionarios'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { formatarMinutos } from '@/lib/formato'
import { rotuloDiaSemana, rotuloDiaSemanaCurto } from '@/lib/rotulos'
import { batidasEsperadas, minutosPrevistos, validarHorariosDia } from '@/lib/ponto'

/** Ordem de exibição: segunda a domingo. */
const ORDEM_DIAS = [1, 2, 3, 4, 5, 6, 0]

interface DiaEdicao {
  trabalha: boolean
  intervalo: boolean
  entrada: string | null
  saida_intervalo: string | null
  volta_intervalo: string | null
  saida: string | null
}

interface Edicao {
  id: string | null
  nome: string
  tolerancia_batida_minutos: string
  tolerancia_diaria_minutos: string
  ativa: boolean
  dias: Record<number, DiaEdicao>
}

const DIA_PADRAO: DiaEdicao = { trabalha: false, intervalo: true, entrada: '17:00', saida_intervalo: '21:00', volta_intervalo: '21:30', saida: '01:00' }

function novaEdicao(j?: JornadaComDias): Edicao {
  const dias: Record<number, DiaEdicao> = {}
  for (let d = 0; d < 7; d++) {
    const jd = j?.jornada_dias.find((x) => x.dia_semana === d)
    dias[d] = jd
      ? {
          trabalha: true,
          intervalo: !!jd.saida_intervalo,
          entrada: jd.entrada.slice(0, 5),
          saida_intervalo: jd.saida_intervalo?.slice(0, 5) ?? '21:00',
          volta_intervalo: jd.volta_intervalo?.slice(0, 5) ?? '21:30',
          saida: jd.saida.slice(0, 5),
        }
      : { ...DIA_PADRAO }
  }
  return {
    id: j?.id ?? null,
    nome: j?.nome ?? '',
    tolerancia_batida_minutos: String(j?.tolerancia_batida_minutos ?? 5),
    tolerancia_diaria_minutos: String(j?.tolerancia_diaria_minutos ?? 10),
    ativa: j?.ativa ?? true,
    dias,
  }
}

function horariosDe(d: DiaEdicao) {
  return {
    entrada: d.entrada ?? '',
    saida_intervalo: d.intervalo ? d.saida_intervalo : null,
    volta_intervalo: d.intervalo ? d.volta_intervalo : null,
    saida: d.saida ?? '',
  }
}

function hhmm(h: string | null) {
  return h ? h.slice(0, 5) : ''
}

export function PaginaJornadas() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const jornadas = useJornadas()
  const excluir = useExcluirJornada()
  const [edicao, setEdicao] = useState<Edicao | null>(null)

  return (
    <div className="mx-auto w-full max-w-7xl">
      <BotaoLink to="/funcionarios" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Funcionários
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Escalas"
        titulo={
          <>
            Jornadas <span className="titulo-italico">de trabalho</span>
          </>
        }
        subtitulo="Horários previstos por dia da semana. Dia sem horário = folga. Saída depois da meia-noite conta no mesmo dia de trabalho."
        acoes={
          operar && (
            <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setEdicao(novaEdicao())}>
              Nova jornada
            </Botao>
          )
        }
      />

      {jornadas.isLoading ? (
        <Carregando />
      ) : jornadas.error ? (
        <ErroCarga erro={jornadas.error} aoTentar={() => jornadas.refetch()} />
      ) : (jornadas.data ?? []).length === 0 ? (
        <Vazio
          icone={<CalendarClock className="size-8" />}
          titulo="Nenhuma jornada"
          descricao="Cadastre a escala (ex.: Salão noite, Cozinha) para o ponto calcular faltas, atrasos e banco de horas."
          acao={operar && <Botao onClick={() => setEdicao(novaEdicao())}>Criar jornada</Botao>}
        />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {(jornadas.data ?? []).map((j) => {
            const semanal = j.jornada_dias.reduce((s, d) => s + d.minutos_previstos, 0)
            return (
              <Cartao
                key={j.id}
                sobrancelha={`${j.jornada_dias.length} dia(s) · ${formatarMinutos(semanal)} por semana`}
                titulo={
                  <span className="flex flex-wrap items-center gap-2">
                    {j.nome} {!j.ativa && <Selo>Inativa</Selo>}
                  </span>
                }
                acoes={
                  operar && (
                    <>
                      <Botao variante="fantasma" tamanho="p" icone={<Pencil aria-hidden className="size-4" />} onClick={() => setEdicao(novaEdicao(j))} aria-label={`Editar ${j.nome}`}>
                        Editar
                      </Botao>
                      <Botao
                        variante="fantasma"
                        tamanho="p"
                        aria-label={`Excluir ${j.nome}`}
                        icone={<Trash2 aria-hidden className="size-4" />}
                        onClick={async () => {
                          if (!(await avisos.confirmar({ titulo: `Excluir a jornada ${j.nome}?`, mensagem: 'Só é possível se nenhum funcionário a usa (ou usou).', perigo: true, textoConfirmar: 'Excluir' }))) return
                          try {
                            await excluir.mutateAsync(j.id)
                            avisos.sucesso('Jornada excluída')
                          } catch (e) {
                            avisos.erro(/foreign key|violates/i.test(String((e as Error)?.message)) ? 'Esta jornada está em uso por algum funcionário. Desative-a em vez de excluir.' : e)
                          }
                        }}
                      />
                    </>
                  )
                }
              >
                <dl className="grid grid-cols-1 gap-1.5 text-sm">
                  {ORDEM_DIAS.map((d) => {
                    const jd = j.jornada_dias.find((x) => x.dia_semana === d)
                    return (
                      <div key={d} className="grid grid-cols-[3rem_1fr_auto] items-center gap-3 rounded-entrada px-2 py-1 odd:bg-cartao-2/40">
                        <dt className="font-semibold text-lavanda">{rotuloDiaSemanaCurto[d]}</dt>
                        <dd className="numero min-w-0 truncate text-creme">
                          {jd ? (
                            <>
                              {hhmm(jd.entrada)}
                              {jd.saida_intervalo && (
                                <span className="text-lavanda">
                                  {' '}
                                  · {hhmm(jd.saida_intervalo)}–{hhmm(jd.volta_intervalo)}
                                </span>
                              )}{' '}
                              → {hhmm(jd.saida)}
                            </>
                          ) : (
                            <span className="font-sans text-lavanda-escuro">folga</span>
                          )}
                        </dd>
                        <dd className="numero text-right text-lavanda">{jd ? formatarMinutos(jd.minutos_previstos) : ''}</dd>
                      </div>
                    )
                  })}
                </dl>
                <p className="mt-3 text-xs text-lavanda">
                  Tolerância de atraso {j.tolerancia_batida_minutos} min · tolerância diária {j.tolerancia_diaria_minutos} min
                </p>
              </Cartao>
            )
          })}
        </div>
      )}

      {edicao && <EditorJornada edicao={edicao} aoFechar={() => setEdicao(null)} />}
    </div>
  )
}

function EditorJornada({ edicao: inicial, aoFechar }: { edicao: Edicao; aoFechar(): void }) {
  const avisos = useAvisos()
  const salvar = useSalvarJornada()
  const [e, setE] = useState<Edicao>(inicial)
  const id = useId()

  const problemas = useMemo(() => {
    const p: Record<number, string> = {}
    for (const d of ORDEM_DIAS) {
      const dia = e.dias[d] as DiaEdicao
      if (!dia.trabalha) continue
      const erro = validarHorariosDia(horariosDe(dia))
      if (erro) p[d] = erro
    }
    return p
  }, [e])

  const mudarDia = (d: number, parcial: Partial<DiaEdicao>) => setE((x) => ({ ...x, dias: { ...x.dias, [d]: { ...(x.dias[d] as DiaEdicao), ...parcial } } }))

  const copiarParaTodos = (origem: number) => {
    const base = e.dias[origem] as DiaEdicao
    setE((x) => {
      const dias = { ...x.dias }
      for (const d of ORDEM_DIAS) if ((dias[d] as DiaEdicao).trabalha) dias[d] = { ...base, trabalha: true }
      return { ...x, dias }
    })
  }

  const semanal = ORDEM_DIAS.reduce((s, d) => {
    const dia = e.dias[d] as DiaEdicao
    return dia.trabalha && !problemas[d] ? s + minutosPrevistos(horariosDe(dia)) : s
  }, 0)

  const tolBatida = Number(e.tolerancia_batida_minutos)
  const tolDiaria = Number(e.tolerancia_diaria_minutos)
  const erroNome = !e.nome.trim() ? 'Informe o nome' : null
  const erroTolB = !Number.isInteger(tolBatida) || tolBatida < 0 || tolBatida > 60 ? 'Entre 0 e 60' : null
  const erroTolD = !Number.isInteger(tolDiaria) || tolDiaria < 0 || tolDiaria > 120 ? 'Entre 0 e 120' : null

  const enviar = async () => {
    if (erroNome || erroTolB || erroTolD || Object.keys(problemas).length) {
      avisos.erro(erroNome ?? Object.values(problemas)[0] ?? 'Revise as tolerâncias')
      return
    }
    try {
      await salvar.mutateAsync({
        id: e.id,
        nome: e.nome,
        tolerancia_batida_minutos: tolBatida,
        tolerancia_diaria_minutos: tolDiaria,
        ativa: e.ativa,
        dias: ORDEM_DIAS.filter((d) => (e.dias[d] as DiaEdicao).trabalha).map((d) => {
          const h = horariosDe(e.dias[d] as DiaEdicao)
          return { dia_semana: d, ...h }
        }),
      })
      avisos.sucesso('Jornada salva. O ponto dos últimos 31 dias será recalculado.')
      aoFechar()
    } catch (erro) {
      avisos.erro(erro)
    }
  }

  return (
    <Modal
      aberto
      aoFechar={aoFechar}
      largura="g"
      titulo={e.id ? `Editar jornada` : 'Nova jornada'}
      rodape={
        <>
          <span className="mr-auto self-center text-sm text-lavanda">
            Total semanal: <span className="numero text-creme">{formatarMinutos(semanal)}</span>
          </span>
          <Botao variante="secundario" onClick={aoFechar}>
            Cancelar
          </Botao>
          <Botao carregando={salvar.isPending} onClick={enviar}>
            Salvar
          </Botao>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-[minmax(0,2fr)_1fr_1fr]">
        <Campo rotulo="Nome" htmlFor={`${id}-nome`} obrigatorio erro={erroNome && e.nome !== inicial.nome ? erroNome : null}>
          <Entrada id={`${id}-nome`} value={e.nome} onChange={(ev) => setE({ ...e, nome: ev.target.value })} placeholder="Ex.: Salão noite" />
        </Campo>
        <Campo rotulo="Tolerância de atraso (min)" htmlFor={`${id}-tb`} erro={erroTolB}>
          <Entrada id={`${id}-tb`} className="numero" inputMode="numeric" value={e.tolerancia_batida_minutos} onChange={(ev) => setE({ ...e, tolerancia_batida_minutos: ev.target.value.replace(/\D/g, '') })} />
        </Campo>
        <Campo rotulo="Tolerância diária (min)" htmlFor={`${id}-td`} erro={erroTolD} ajuda="Saldo dentro disso conta como zero.">
          <Entrada id={`${id}-td`} className="numero" inputMode="numeric" value={e.tolerancia_diaria_minutos} onChange={(ev) => setE({ ...e, tolerancia_diaria_minutos: ev.target.value.replace(/\D/g, '') })} />
        </Campo>
      </div>
      <div className="mt-3">
        <Interruptor rotulo="Jornada ativa" marcado={e.ativa} aoMudar={(v) => setE({ ...e, ativa: v })} />
      </div>

      <div className="mt-5 flex flex-col gap-2">
        {ORDEM_DIAS.map((d) => {
          const dia = e.dias[d] as DiaEdicao
          const erro = problemas[d]
          return (
            <fieldset key={d} className="rounded-entrada border border-borda bg-entrada/50 p-3">
              <legend className="sr-only">{rotuloDiaSemana[d]}</legend>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Interruptor rotulo={<span className="font-semibold">{rotuloDiaSemana[d]}</span>} marcado={dia.trabalha} aoMudar={(v) => mudarDia(d, { trabalha: v })} />
                {dia.trabalha && (
                  <div className="flex items-center gap-3 text-sm">
                    {!erro && (
                      <span className="numero text-lavanda">
                        {formatarMinutos(minutosPrevistos(horariosDe(dia)))} · {batidasEsperadas(horariosDe(dia))} batidas
                      </span>
                    )}
                    <Botao variante="fantasma" tamanho="p" icone={<Copy aria-hidden className="size-4" />} onClick={() => copiarParaTodos(d)} title="Copiar estes horários para os outros dias de trabalho">
                      <span className="hidden sm:inline">Copiar p/ todos</span>
                    </Botao>
                  </div>
                )}
              </div>
              {dia.trabalha && (
                <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-[1fr_auto_1fr_1fr_1fr] sm:items-end">
                  <Campo rotulo="Entrada" htmlFor={`${id}-${d}-e`}>
                    <EntradaHora id={`${id}-${d}-e`} valor={dia.entrada} aoMudar={(v) => mudarDia(d, { entrada: v })} />
                  </Campo>
                  <div className="col-span-2 sm:col-span-1 sm:pb-2.5">
                    <Interruptor rotulo="Intervalo" marcado={dia.intervalo} aoMudar={(v) => mudarDia(d, { intervalo: v })} />
                  </div>
                  {dia.intervalo ? (
                    <>
                      <Campo rotulo="Saída p/ intervalo" htmlFor={`${id}-${d}-si`}>
                        <EntradaHora id={`${id}-${d}-si`} valor={dia.saida_intervalo} aoMudar={(v) => mudarDia(d, { saida_intervalo: v })} />
                      </Campo>
                      <Campo rotulo="Volta do intervalo" htmlFor={`${id}-${d}-vi`}>
                        <EntradaHora id={`${id}-${d}-vi`} valor={dia.volta_intervalo} aoMudar={(v) => mudarDia(d, { volta_intervalo: v })} />
                      </Campo>
                    </>
                  ) : (
                    <div className="hidden sm:col-span-2 sm:block" />
                  )}
                  <Campo rotulo="Saída" htmlFor={`${id}-${d}-s`}>
                    <EntradaHora id={`${id}-${d}-s`} valor={dia.saida} aoMudar={(v) => mudarDia(d, { saida: v })} />
                  </Campo>
                </div>
              )}
              {erro && (
                <p role="alert" className="mt-2 text-sm text-perigo">
                  {erro}
                </p>
              )}
            </fieldset>
          )
        })}
      </div>
    </Modal>
  )
}
