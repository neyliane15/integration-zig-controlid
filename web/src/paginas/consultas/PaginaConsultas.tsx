/**
 * /consultas — "Consultas rápidas": perguntas prontas sobre a loja, respondidas com os dados do sistema (sem IA, sem custo).
 * Período escolhido no topo (atalhos: hoje, 7 dias, este mês, mês anterior). G A M.
 * Ponto: consultas_ponto_resumo (faltas, atrasos pela chegada da escala, horas). Vendas: vendas_faturamento_por_dia e
 * vendas_por_garcom (Zig). Escala: consultas_escala_dia (dia escolhido).
 */
import { useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import clsx from 'clsx'
import { AlarmClock, CalendarDays, CalendarX, Clock, Medal, Receipt, TrendingDown, TrendingUp } from 'lucide-react'
import { CabecalhoPagina, Carregando, Cartao, EntradaData, ErroCarga, FiltroPeriodo, FOCO } from '@/componentes/ui'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useConsultaEscala, useConsultaPonto } from '@/consultas/consultas'
import { useFaturamentoPorDia, useVendasPorGarcom } from '@/consultas/vendas'
import { formatarCentavos, formatarData, formatarMinutos } from '@/lib/formato'
import type { LinhaConsultaEscala, LinhaConsultaPonto } from '@/tipos/banco'

const primeiroDoMes = (iso: string) => `${iso.slice(0, 8)}01`
const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado']
const diaSemana = (iso: string) => DIAS[new Date(`${iso}T12:00:00Z`).getUTCDay()]
const juntarNomes = (n: string[]) => (n.length <= 1 ? n.join('') : `${n.slice(0, -1).join(', ')} e ${n[n.length - 1]}`)

interface Linha {
  chave: string
  nome: string
  valor: string
  detalhe?: string
  para?: string
}

/** Cartão de uma pergunta: a resposta em destaque e, embaixo, até 5 linhas de apoio. */
function Pergunta({
  pergunta,
  icone,
  carregando,
  erro,
  aoTentar,
  resposta,
  linhas = [],
  rodape,
}: {
  pergunta: string
  icone: ReactNode
  carregando?: boolean
  erro?: unknown
  aoTentar?(): void
  resposta: ReactNode
  linhas?: Linha[]
  rodape?: ReactNode
}) {
  return (
    <Cartao
      titulo={
        <span className="flex items-center gap-2.5">
          <span className="grid size-8 shrink-0 place-items-center rounded-full bg-ouro/12 text-ouro" aria-hidden>
            {icone}
          </span>
          {pergunta}
        </span>
      }
    >
      {erro ? (
        <ErroCarga erro={erro} aoTentar={aoTentar} />
      ) : carregando ? (
        <Carregando texto="Consultando…" />
      ) : (
        <>
          <p className="text-[15px] leading-relaxed text-creme" data-teste="resposta">
            {resposta}
          </p>
          {linhas.length > 0 && (
            <ol className="mt-3 flex flex-col divide-y divide-borda border-t border-borda">
              {linhas.slice(0, 5).map((l, i) => {
                const conteudo = (
                  <>
                    <span className="numero w-5 shrink-0 text-xs text-lavanda-escuro">{i + 1}</span>
                    <span className="min-w-0 flex-1 truncate text-sm text-creme">{l.nome}</span>
                    {l.detalhe && <span className="hidden text-xs text-lavanda sm:inline">{l.detalhe}</span>}
                    <span className="numero shrink-0 text-sm font-semibold text-creme">{l.valor}</span>
                  </>
                )
                return (
                  <li key={l.chave}>
                    {l.para ? (
                      <Link to={l.para} className={clsx('flex items-center gap-3 py-2 hover:bg-cartao-2/60', FOCO)}>
                        {conteudo}
                      </Link>
                    ) : (
                      <span className="flex items-center gap-3 py-2">{conteudo}</span>
                    )}
                  </li>
                )
              })}
            </ol>
          )}
          {rodape && <p className="mt-3 text-xs text-lavanda-escuro">{rodape}</p>}
        </>
      )}
    </Cartao>
  )
}

const ficha = (id: string) => `/funcionarios/${id}?aba=ocorrencias`

export function PaginaConsultas() {
  const { hoje, empresa } = useContextoEmpresa()
  const [inicio, setInicio] = useState(() => primeiroDoMes(hoje))
  const [fim, setFim] = useState(hoje)
  const [dia, setDia] = useState(hoje)

  const ponto = useConsultaPonto(inicio, fim)
  const vendasDia = useFaturamentoPorDia(inicio, fim, null)
  const garcons = useVendasPorGarcom(inicio, fim, null)
  const escala = useConsultaEscala(dia)

  const p = useMemo(() => {
    const todos = (ponto.data ?? []) as LinhaConsultaPonto[]
    const comPonto = todos.filter((l) => l.dias_com_batida > 0)
    const menosAtraso = [...comPonto].sort((a, b) => a.atrasos - b.atrasos || a.minutos_atraso - b.minutos_atraso || a.funcionario_nome.localeCompare(b.funcionario_nome))
    const maisAtraso = [...comPonto].filter((l) => l.atrasos > 0).sort((a, b) => b.minutos_atraso - a.minutos_atraso || b.atrasos - a.atrasos)
    const faltas = [...todos].filter((l) => l.faltas + l.faltas_justificadas > 0).sort((a, b) => b.faltas - a.faltas || b.faltas_justificadas - a.faltas_justificadas)
    const horas = [...comPonto].sort((a, b) => b.trabalhado_minutos - a.trabalhado_minutos)
    return { comPonto, menosAtraso, maisAtraso, faltas, horas }
  }, [ponto.data])

  const v = useMemo(() => {
    const dias = (vendasDia.data ?? []).filter((d) => d.valor > 0)
    const ordem = [...dias].sort((a, b) => b.valor - a.valor)
    const total = dias.reduce((s, d) => s + d.valor, 0)
    return { dias, ordem, media: dias.length ? Math.round(total / dias.length) : 0, total }
  }, [vendasDia.data])

  const e = useMemo(() => {
    const l = (escala.data ?? []) as LinhaConsultaEscala[]
    const por = (s: string) => l.filter((x) => x.status === s)
    return { trabalha: por('trabalha'), folga: por('folga'), bh: por('banco_horas'), ferias: por('ferias'), total: l.length }
  }, [escala.data])

  const periodo = inicio === fim ? formatarData(inicio) : `${formatarData(inicio)} a ${formatarData(fim)}`
  const linhaPonto = (l: LinhaConsultaPonto, valor: string, detalhe?: string): Linha => ({
    chave: l.funcionario_id,
    nome: l.funcionario_nome,
    valor,
    detalhe,
    para: ficha(l.funcionario_id),
  })
  const atrasoTxt = (l: LinhaConsultaPonto) => (l.atrasos ? `${l.atrasos} atraso${l.atrasos > 1 ? 's' : ''} · ${formatarMinutos(l.minutos_atraso)}` : 'nenhum atraso')
  const semPonto = 'Ninguém bateu ponto no período (ou o relógio ainda não foi sincronizado).'

  // menos atrasos: todos os empatados no melhor resultado
  const melhores = p.menosAtraso.length
    ? p.menosAtraso.filter((l) => l.atrasos === p.menosAtraso[0]!.atrasos && l.minutos_atraso === p.menosAtraso[0]!.minutos_atraso)
    : []

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Perguntas prontas"
        titulo={
          <>
            Consultas <span className="titulo-italico">rápidas</span>
          </>
        }
        subtitulo={`${empresa?.nome ?? 'Loja'} · ${periodo}`}
      />
      <div className="mb-5">
        <FiltroPeriodo
          hoje={hoje}
          inicio={inicio}
          fim={fim}
          aoMudar={(de, ate) => {
            setInicio(de)
            setFim(ate)
          }}
        />
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <Pergunta
          pergunta="Quem teve menos atrasos?"
          icone={<Medal className="size-4" />}
          carregando={ponto.isLoading}
          erro={ponto.error}
          aoTentar={() => void ponto.refetch()}
          resposta={
            !melhores.length ? (
              semPonto
            ) : melhores[0]!.atrasos === 0 ? (
              <>
                <b>{juntarNomes(melhores.map((l) => l.funcionario_nome))}</b>: nenhum atraso no período.
              </>
            ) : (
              <>
                <b>{juntarNomes(melhores.map((l) => l.funcionario_nome))}</b>: {atrasoTxt(melhores[0]!)}.
              </>
            )
          }
          linhas={p.menosAtraso.map((l) => linhaPonto(l, l.atrasos ? formatarMinutos(l.minutos_atraso) : '0', l.atrasos ? `${l.atrasos}×` : undefined))}
          rodape="Atraso = 1ª batida depois da chegada da escala do dia, além da tolerância. Só conta quem bateu ponto no período."
        />

        <Pergunta
          pergunta="Quem mais atrasou?"
          icone={<AlarmClock className="size-4" />}
          carregando={ponto.isLoading}
          erro={ponto.error}
          aoTentar={() => void ponto.refetch()}
          resposta={
            !p.comPonto.length ? (
              semPonto
            ) : !p.maisAtraso.length ? (
              'Ninguém atrasou no período.'
            ) : (
              <>
                <b>{p.maisAtraso[0]!.funcionario_nome}</b>: {atrasoTxt(p.maisAtraso[0]!)}.
              </>
            )
          }
          linhas={p.maisAtraso.map((l) => linhaPonto(l, formatarMinutos(l.minutos_atraso), `${l.atrasos}×`))}
        />

        <Pergunta
          pergunta="Quem mais faltou?"
          icone={<CalendarX className="size-4" />}
          carregando={ponto.isLoading}
          erro={ponto.error}
          aoTentar={() => void ponto.refetch()}
          resposta={
            !p.faltas.length ? (
              'Ninguém faltou no período.'
            ) : (
              <>
                <b>{p.faltas[0]!.funcionario_nome}</b>: {p.faltas[0]!.faltas} falta{p.faltas[0]!.faltas === 1 ? '' : 's'}
                {p.faltas[0]!.faltas_justificadas > 0 && ` + ${p.faltas[0]!.faltas_justificadas} justificada${p.faltas[0]!.faltas_justificadas > 1 ? 's' : ''}`}.
              </>
            )
          }
          linhas={p.faltas.map((l) =>
            linhaPonto(l, String(l.faltas), l.faltas_justificadas ? `+${l.faltas_justificadas} justificada${l.faltas_justificadas > 1 ? 's' : ''}` : undefined),
          )}
          rodape="Falta = dia com horário previsto e nenhuma batida, ou falta lançada no sistema (as justificadas aparecem à parte)."
        />

        <Pergunta
          pergunta="Quem trabalhou mais horas?"
          icone={<Clock className="size-4" />}
          carregando={ponto.isLoading}
          erro={ponto.error}
          aoTentar={() => void ponto.refetch()}
          resposta={
            !p.horas.length ? (
              semPonto
            ) : (
              <>
                <b>{p.horas[0]!.funcionario_nome}</b>: {formatarMinutos(p.horas[0]!.trabalhado_minutos)} em {p.horas[0]!.dias_com_batida} dia
                {p.horas[0]!.dias_com_batida === 1 ? '' : 's'}.
              </>
            )
          }
          linhas={p.horas.map((l) => linhaPonto(l, formatarMinutos(l.trabalhado_minutos), `${l.dias_com_batida} dias · saldo ${formatarMinutos(l.saldo_minutos, { sinal: true })}`))}
        />

        <Pergunta
          pergunta="Qual dia mais vendeu?"
          icone={<TrendingUp className="size-4" />}
          carregando={vendasDia.isLoading}
          erro={vendasDia.error}
          aoTentar={() => void vendasDia.refetch()}
          resposta={
            !v.ordem.length ? (
              'Sem vendas da Zig no período.'
            ) : (
              <>
                <b>
                  {formatarData(v.ordem[0]!.data)} ({diaSemana(v.ordem[0]!.data)})
                </b>
                : {formatarCentavos(v.ordem[0]!.valor)}. Média de {formatarCentavos(v.media)} por dia com venda.
              </>
            )
          }
          linhas={v.ordem.map((d) => ({ chave: d.data, nome: `${formatarData(d.data)} · ${diaSemana(d.data)}`, valor: formatarCentavos(d.valor) }))}
        />

        <Pergunta
          pergunta="Qual dia menos vendeu?"
          icone={<TrendingDown className="size-4" />}
          carregando={vendasDia.isLoading}
          erro={vendasDia.error}
          aoTentar={() => void vendasDia.refetch()}
          resposta={
            !v.ordem.length ? (
              'Sem vendas da Zig no período.'
            ) : (
              <>
                <b>
                  {formatarData(v.ordem[v.ordem.length - 1]!.data)} ({diaSemana(v.ordem[v.ordem.length - 1]!.data)})
                </b>
                : {formatarCentavos(v.ordem[v.ordem.length - 1]!.valor)}. Total do período: {formatarCentavos(v.total)}.
              </>
            )
          }
          linhas={[...v.ordem].reverse().map((d) => ({ chave: d.data, nome: `${formatarData(d.data)} · ${diaSemana(d.data)}`, valor: formatarCentavos(d.valor) }))}
          rodape="Só dias com venda. Dias sem nenhuma venda (casa fechada) ficam de fora."
        />

        <Pergunta
          pergunta="Qual garçom mais vendeu?"
          icone={<Receipt className="size-4" />}
          carregando={garcons.isLoading}
          erro={garcons.error}
          aoTentar={() => void garcons.refetch()}
          resposta={
            !(garcons.data ?? []).length ? (
              'Sem vendas por garçom no período.'
            ) : (
              <>
                <b>{garcons.data![0]!.funcionario_nome ?? garcons.data![0]!.employee_name ?? 'Sem nome'}</b>: {formatarCentavos(garcons.data![0]!.valor_vendas)} vendidos (
                {formatarCentavos(garcons.data![0]!.valor_servico)} de serviço).
              </>
            )
          }
          linhas={(garcons.data ?? []).map((g, i) => ({
            chave: `${g.funcionario_id ?? g.employee_name ?? i}`,
            nome: g.funcionario_nome ?? g.employee_name ?? 'Sem nome',
            valor: formatarCentavos(g.valor_vendas),
            detalhe: `${g.transacoes} vendas`,
          }))}
        />

        <Cartao
          titulo={
            <span className="flex items-center gap-2.5">
              <span className="grid size-8 shrink-0 place-items-center rounded-full bg-ouro/12 text-ouro" aria-hidden>
                <CalendarDays className="size-4" />
              </span>
              Quem trabalha e quem folga?
            </span>
          }
          acoes={
            <div className="w-44">
              <EntradaData id="consulta-dia" valor={dia} aoMudar={(d) => d && setDia(d)} />
            </div>
          }
        >
          {escala.error ? (
            <ErroCarga erro={escala.error} aoTentar={() => void escala.refetch()} />
          ) : escala.isLoading ? (
            <Carregando texto="Consultando…" />
          ) : !e.total ? (
            <p className="text-[15px] text-creme">Ninguém na escala neste dia.</p>
          ) : (
            <div className="flex flex-col gap-3 text-sm" data-teste="resposta-escala">
              <p className="text-[15px] text-creme">
                {formatarData(dia)} ({diaSemana(dia)}): <b>{e.trabalha.length}</b> trabalhando, <b>{e.folga.length + e.bh.length}</b> de folga
                {e.ferias.length > 0 && (
                  <>
                    , <b>{e.ferias.length}</b> de férias
                  </>
                )}
                .
              </p>
              {e.trabalha.length > 0 && (
                <p className="text-lavanda">
                  <span className="font-semibold text-creme">Trabalham: </span>
                  {e.trabalha.map((x) => `${x.funcionario_nome}${x.chegada ? ` (${x.chegada.replace(':00', 'h').replace(':', 'h')})` : ''}`).join(', ')}
                </p>
              )}
              {e.folga.length > 0 && (
                <p className="text-lavanda">
                  <span className="font-semibold text-creme">Folga: </span>
                  {e.folga.map((x) => x.funcionario_nome).join(', ')}
                </p>
              )}
              {e.bh.length > 0 && (
                <p className="text-lavanda">
                  <span className="font-semibold text-creme">Folga de banco de horas: </span>
                  {e.bh.map((x) => x.funcionario_nome).join(', ')}
                </p>
              )}
              {e.ferias.length > 0 && (
                <p className="text-lavanda">
                  <span className="font-semibold text-creme">Férias: </span>
                  {e.ferias.map((x) => x.funcionario_nome).join(', ')}
                </p>
              )}
            </div>
          )}
        </Cartao>
      </div>
    </div>
  )
}
