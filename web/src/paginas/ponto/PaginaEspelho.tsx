import { useMemo, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import clsx from 'clsx'
import { AlertTriangle, ArrowLeft, CalendarOff, ChevronLeft, ChevronRight, Download, History, Plus, RefreshCw, RotateCcw } from 'lucide-react'
import type { AlarmeEspelho, BatidaEspelho, LinhaEspelho } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Carregando, Cartao, ErroCarga, Indicador, Selo, Tabela, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BatidasDia } from '@/componentes/dominio/BatidasDia'
import { BotaoLink } from '@/componentes/dominio/BotaoLink'
import { SeletorFuncionario } from '@/componentes/dominio/SeletorFuncionario'
import { ContagemBatidas, SeloAlarme, SeloSituacaoDia, SeloStatusAlarme, TextoSaldo } from '@/componentes/dominio/Selos'
import { useContextoEmpresa, useFuncionario } from '@/consultas/funcionarios'
import { useAbonos, useAjustes, useEspelho, useReabrirAlarme, useReapurar, useRemoverAbono } from '@/consultas/ponto'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { formatarData, formatarDataCurta, formatarDataHora, formatarHora, formatarMinutos } from '@/lib/formato'
import { baixarCsv, dataCsv, gerarCsv, minutosCsv, nomeArquivoCsv } from '@/lib/csv'
import { rotuloAcaoAjuste, rotuloDiaSemanaCurto, rotuloSituacaoDia, rotuloTipoAbono, rotuloTipoAlarme } from '@/lib/rotulos'
import { batidasValidas, identificarFaltantes, mesValido, nomeDoMes, periodoDoMes, somarMeses, totaisDoEspelho } from '@/lib/ponto'
import { ModalAbonar, ModalBatida, ModalIncluirBatida, ModalJustificar } from './ModaisPonto'

export function PaginaEspelho() {
  const { id = '' } = useParams()
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const navegar = useNavigate()
  const { hoje, fuso, virada, empresa } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const mesParam = params.get('mes')
  const mes = mesValido(mesParam) ? mesParam : hoje.slice(0, 7)
  const periodo = periodoDoMes(mes)
  const fim = periodo.fim > hoje ? hoje : periodo.fim
  const futuro = periodo.inicio > hoje

  const funcionario = useFuncionario(id)
  const espelho = useEspelho(futuro ? null : id, periodo.inicio, fim)
  const abonos = useAbonos(operar ? id : null, periodo.inicio, fim)
  const ajustes = useAjustes(operar ? id : null, periodo.inicio, fim)
  const reapurar = useReapurar()
  const reabrir = useReabrirAlarme()
  const removerAbono = useRemoverAbono()

  const [batida, setBatida] = useState<{ b: BatidaEspelho; data: string } | null>(null)
  const [incluir, setIncluir] = useState<{ data: string; hora: string | null } | null>(null)
  const [justificar, setJustificar] = useState<string[]>([])
  const [abonar, setAbonar] = useState<string | null>(null)
  const [verAjustes, setVerAjustes] = useState(false)

  const linhas = useMemo(() => [...(espelho.data ?? [])].sort((a, b) => b.data.localeCompare(a.data)), [espelho.data])
  const totais = useMemo(() => totaisDoEspelho(espelho.data ?? []), [espelho.data])
  const abertos = useMemo(
    () => linhas.flatMap((l) => l.alarmes.filter((a) => a.status === 'aberto').map((a) => ({ ...a, data: l.data }))),
    [linhas],
  )
  const nome = funcionario.data?.nome ?? 'Funcionário'

  const irMes = (m: string) => {
    const p = new URLSearchParams(params)
    p.set('mes', m)
    setParams(p, { replace: true })
  }

  const exportar = () => {
    const cab = ['Data', 'Dia', 'Batidas', 'Previsto', 'Trabalhado', 'Saldo', 'Situação', 'Alarmes']
    const corpo = [...(espelho.data ?? [])]
      .sort((a, b) => a.data.localeCompare(b.data))
      .map((l) => [
        dataCsv(l.data),
        rotuloDiaSemanaCurto[l.dia_semana] ?? '',
        batidasValidas(l.batidas)
          .map((b) => formatarHora(b.instante, fuso))
          .join(' '),
        minutosCsv(l.previsto_minutos),
        minutosCsv(l.trabalhado_minutos),
        minutosCsv(l.saldo_minutos),
        rotuloSituacaoDia[l.situacao],
        l.alarmes.map((a) => `${a.detalhe} (${a.status})`).join(' | '),
      ])
    const conteudo = gerarCsv(cab, corpo, [
      ['Funcionário', nome],
      ['Período', `${formatarData(periodo.inicio)} a ${formatarData(fim)}`],
      ['Saldo do período', minutosCsv(totais.saldo)],
    ])
    baixarCsv(nomeArquivoCsv('ponto', `${empresa?.nome ?? 'empresa'}-${nome}`, periodo.inicio, fim), conteudo)
  }

  const recalcular = async () => {
    try {
      const n = await reapurar.mutateAsync({ inicio: periodo.inicio, fim, funcionarioId: id })
      avisos.sucesso(`${n} dia(s) recalculado(s)`)
    } catch (e) {
      avisos.erro(e)
    }
  }

  if (funcionario.error) return <ErroCarga erro={funcionario.error} aoTentar={() => funcionario.refetch()} />

  return (
    <div className="mx-auto w-full max-w-7xl">
      <BotaoLink to="/ponto" variante="fantasma" tamanho="p" icone={<ArrowLeft aria-hidden />} className="mb-3 -ml-3">
        Ponto do dia
      </BotaoLink>
      <CabecalhoPagina
        sobrancelha="Espelho de ponto"
        titulo={
          <>
            {nome} <span className="titulo-italico">{nomeDoMes(mes)}</span>
          </>
        }
        subtitulo={funcionario.data?.cargo ?? undefined}
        acoes={
          <>
            <Botao variante="secundario" icone={<Download aria-hidden className="size-4" />} onClick={exportar} disabled={!espelho.data?.length}>
              Exportar CSV
            </Botao>
            {operar && (
              <>
                <Botao variante="secundario" icone={<CalendarOff aria-hidden className="size-4" />} onClick={() => setAbonar(hoje < periodo.fim ? hoje : periodo.fim)}>
                  Abonar
                </Botao>
                <Botao variante="secundario" icone={<RefreshCw aria-hidden className="size-4" />} carregando={reapurar.isPending} onClick={recalcular}>
                  Recalcular
                </Botao>
              </>
            )}
          </>
        }
      />

      <div className="mb-5 flex flex-wrap items-end gap-3">
        <nav aria-label="Escolher mês" className="flex items-center gap-2">
          <Botao variante="secundario" aria-label="Mês anterior" icone={<ChevronLeft aria-hidden className="size-4" />} onClick={() => irMes(somarMeses(mes, -1))} />
          <span className="min-w-36 text-center font-display text-lg text-creme">{nomeDoMes(mes)}</span>
          <Botao variante="secundario" aria-label="Próximo mês" icone={<ChevronRight aria-hidden className="size-4" />} disabled={mes >= hoje.slice(0, 7)} onClick={() => irMes(somarMeses(mes, 1))} />
        </nav>
        <div className="w-full sm:ml-auto sm:w-72">
          <SeletorFuncionario valor={id} aoMudar={(f) => f && navegar(`/ponto/funcionario/${f}?mes=${mes}`)} rotuloAcessivel="Trocar funcionário" />
        </div>
      </div>

      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Indicador rotulo="Saldo do mês" valor={<TextoSaldo minutos={totais.saldo} />} detalhe="dias encerrados" />
        <Indicador rotulo="Trabalhado" valor={formatarMinutos(totais.trabalhado)} detalhe={`previsto ${formatarMinutos(totais.previsto)}`} />
        <Indicador rotulo="Dias trabalhados" valor={totais.diasTrabalhados} />
        <Indicador rotulo="Faltas / incompletos" valor={`${totais.faltas} / ${totais.incompletos}`} tom={totais.faltas ? 'perigo' : totais.incompletos ? 'alerta' : undefined} />
        <Indicador rotulo="Alarmes abertos" valor={totais.alarmesAbertos} tom={totais.alarmesAbertos ? 'alerta' : 'sucesso'} />
      </div>

      {abertos.length > 0 && (
        <section role="alert" aria-label="Alarmes abertos" className="mb-5 rounded-cartao border border-alerta/50 bg-alerta/10 p-5">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h2 className="flex items-center gap-2 font-display text-xl text-alerta">
              <AlertTriangle aria-hidden className="size-5" /> {abertos.length} alarme(s) aberto(s)
            </h2>
            {operar && abertos.length > 1 && (
              <Botao variante="secundario" tamanho="p" onClick={() => setJustificar(abertos.map((a) => a.id))}>
                Justificar todos
              </Botao>
            )}
          </div>
          <ul className="flex flex-col gap-2">
            {abertos.map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-2 rounded-entrada bg-noite/40 px-3 py-2 text-sm">
                <span className="numero font-semibold text-creme">{formatarDataCurta(a.data)}</span>
                <SeloAlarme tipo={a.tipo} batidaEsperada={a.batida_esperada} />
                <span className="min-w-0 flex-1 text-creme">{a.detalhe}</span>
                {operar && (
                  <Botao variante="fantasma" tamanho="p" onClick={() => setJustificar([a.id])}>
                    Justificar
                  </Botao>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {futuro ? (
        <Vazio titulo="Mês no futuro" />
      ) : espelho.isLoading ? (
        <Carregando texto="Montando o espelho…" />
      ) : espelho.error ? (
        <ErroCarga erro={espelho.error} aoTentar={() => espelho.refetch()} />
      ) : linhas.length === 0 ? (
        <Vazio titulo="Sem dias neste mês" descricao="O funcionário não estava no vínculo (admissão/desligamento) neste período." />
      ) : (
        <ol className="flex flex-col gap-2" aria-label="Dias do mês">
          {linhas.map((l) => (
            <DiaEspelho
              key={l.data}
              linha={l}
              fuso={fuso}
              operar={operar}
              ehHoje={l.data === hoje}
              temAbono={(abonos.data ?? []).some((x) => x.data === l.data)}
              aoClicarBatida={(b) => setBatida({ b, data: l.data })}
              aoIncluir={(hora) => setIncluir({ data: l.data, hora })}
              aoJustificar={(ids) => setJustificar(ids)}
              aoReabrir={async (a) => {
                try {
                  await reabrir.mutateAsync(a.id)
                  avisos.sucesso('Alarme reaberto')
                } catch (e) {
                  avisos.erro(e)
                }
              }}
              aoAbonar={() => setAbonar(l.data)}
              aoRemoverAbono={async () => {
                const abono = (abonos.data ?? []).find((x) => x.data === l.data && x.funcionario_id === id) ?? (abonos.data ?? []).find((x) => x.data === l.data)
                if (!abono) return
                const daEmpresa = !abono.funcionario_id
                if (
                  !(await avisos.confirmar({
                    titulo: `Remover o abono de ${formatarData(l.data)}?`,
                    mensagem: daEmpresa ? 'Este abono vale para a empresa toda (todos os funcionários).' : undefined,
                    textoConfirmar: 'Remover abono',
                    perigo: true,
                  }))
                )
                  return
                try {
                  await removerAbono.mutateAsync(abono.id)
                  avisos.sucesso('Abono removido')
                } catch (e) {
                  avisos.erro(e)
                }
              }}
            />
          ))}
        </ol>
      )}

      {operar && (
        <Cartao
          className="mt-6"
          sobrancelha="Auditoria"
          titulo="Ajustes manuais"
          acoes={
            <Botao variante="fantasma" tamanho="p" icone={<History aria-hidden className="size-4" />} onClick={() => setVerAjustes((v) => !v)} aria-expanded={verAjustes}>
              {verAjustes ? 'Esconder' : `Ver (${ajustes.data?.length ?? 0})`}
            </Botao>
          }
        >
          {verAjustes &&
            (ajustes.error ? (
              <ErroCarga erro={ajustes.error} />
            ) : (
              <Tabela
                colunas={[
                  { id: 'quando', titulo: 'Quando', render: (a) => <span className="numero">{formatarDataHora(a.feito_em, fuso)}</span> },
                  { id: 'acao', titulo: 'Ação', render: (a) => <Selo tom={a.acao === 'desconsiderar' ? 'perigo' : 'info'}>{rotuloAcaoAjuste[a.acao]}</Selo> },
                  { id: 'batida', titulo: 'Batida', render: (a) => <span className="numero">{formatarDataHora(a.instante, fuso)}</span> },
                  { id: 'motivo', titulo: 'Motivo', render: (a) => a.motivo },
                  { id: 'quem', titulo: 'Por', ocultarNoCelular: true, render: (a) => a.feito_por_nome },
                ]}
                linhas={ajustes.data ?? []}
                chave={(a) => a.id}
                carregando={ajustes.isLoading}
                vazio={<p className="text-sm text-lavanda">Nenhum ajuste neste mês.</p>}
              />
            ))}
        </Cartao>
      )}

      {batida && (
        <ModalBatida key={batida.b.id} batida={batida.b} aoFechar={() => setBatida(null)} funcionarioId={id} data={batida.data} fuso={fuso} virada={virada} />
      )}
      {incluir && (
        <ModalIncluirBatida
          key={`${incluir.data}-${incluir.hora}`}
          aberto
          aoFechar={() => setIncluir(null)}
          funcionarioId={id}
          funcionarioNome={nome}
          data={incluir.data}
          horaSugerida={incluir.hora}
          fuso={fuso}
          virada={virada}
        />
      )}
      {justificar.length > 0 && <ModalJustificar ids={justificar} aoFechar={() => setJustificar([])} />}
      {abonar && <ModalAbonar key={abonar} aberto aoFechar={() => setAbonar(null)} funcionarioId={id} funcionarioNome={nome} inicio={abonar} />}
    </div>
  )
}

function DiaEspelho({
  linha: l,
  fuso,
  operar,
  ehHoje,
  temAbono,
  aoClicarBatida,
  aoIncluir,
  aoJustificar,
  aoReabrir,
  aoAbonar,
  aoRemoverAbono,
}: {
  linha: LinhaEspelho
  fuso: string
  operar: boolean
  ehHoje: boolean
  temAbono: boolean
  aoClicarBatida(b: BatidaEspelho): void
  aoIncluir(hora: string | null): void
  aoJustificar(ids: string[]): void
  aoReabrir(a: AlarmeEspelho): void
  aoAbonar(): void
  aoRemoverAbono(): void
}) {
  const validas = batidasValidas(l.batidas)
  const agora = Date.now()
  const faltantes = (l.esperadas.length && validas.length < l.esperadas.length ? identificarFaltantes(validas.map((b) => b.instante), l.esperadas) : []).filter(
    (f) => l.encerrado || new Date(l.esperadas.find((e) => e.batida === f)?.instante ?? 0).getTime() < agora,
  )
  const abertos = l.alarmes.filter((a) => a.status === 'aberto')
  const fimDeSemana = l.dia_semana === 0 || l.dia_semana === 6

  return (
    <li
      className={clsx(
        'rounded-entrada border bg-cartao p-4',
        abertos.length ? 'border-alerta/50 border-l-4 border-l-alerta' : 'border-borda',
        ehHoje && 'ring-1 ring-ouro/40',
      )}
      aria-label={`${formatarData(l.data)}${abertos.length ? `, ${abertos.length} alarme(s) aberto(s)` : ''}`}
    >
      <div className="grid gap-3 lg:grid-cols-[7.5rem_minmax(0,1fr)_auto] lg:items-start">
        <div className="flex items-baseline gap-2 lg:block">
          <p className="numero text-lg font-semibold text-creme">{formatarDataCurta(l.data)}</p>
          <p className={clsx('text-sm', fimDeSemana ? 'text-ouro-claro' : 'text-lavanda')}>
            {rotuloDiaSemanaCurto[l.dia_semana]}
            {ehHoje && ' · hoje'}
          </p>
        </div>

        <div className="flex min-w-0 flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <SeloSituacaoDia situacao={l.situacao} />
            {l.abono_tipo && <Selo tom="info">{rotuloTipoAbono[l.abono_tipo]}</Selo>}
            {l.jornada_nome && <span className="text-xs text-lavanda">{l.jornada_nome}</span>}
            {l.esperadas.length > 0 && (
              <span className="text-xs text-lavanda">
                · previsto{' '}
                <span className="numero">
                  {l.esperadas.map((e) => formatarHora(e.instante, fuso)).join(' · ')}
                </span>
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <ContagemBatidas validas={validas.length} esperadas={l.esperadas.length} encerrado={l.encerrado} />
            <BatidasDia
              batidas={l.batidas}
              fuso={fuso}
              esperadas={l.esperadas}
              faltantes={faltantes}
              aoClicarBatida={operar ? aoClicarBatida : undefined}
              aoClicarFaltante={operar ? (e) => aoIncluir(formatarHora(e.instante, fuso)) : undefined}
            />
          </div>
          {l.alarmes.length > 0 && (
            <ul className="flex flex-col gap-1.5">
              {l.alarmes.map((a) => (
                <li key={a.id} className="flex flex-wrap items-center gap-2 text-sm">
                  <SeloAlarme tipo={a.tipo} batidaEsperada={a.batida_esperada} status={a.status} />
                  <span className={a.status === 'aberto' ? 'text-creme' : 'text-lavanda'}>{a.detalhe}</span>
                  {a.status !== 'aberto' && <SeloStatusAlarme status={a.status} />}
                  {a.justificativa && <span className="text-xs italic text-lavanda">“{a.justificativa}”</span>}
                  {operar && a.status === 'aberto' && (
                    <Botao variante="fantasma" tamanho="p" onClick={() => aoJustificar([a.id])} aria-label={`Justificar ${rotuloTipoAlarme[a.tipo]} de ${formatarData(l.data)}`}>
                      Justificar
                    </Botao>
                  )}
                  {operar && a.status === 'justificado' && (
                    <Botao variante="fantasma" tamanho="p" icone={<RotateCcw aria-hidden className="size-3.5" />} onClick={() => aoReabrir(a)}>
                      Reabrir
                    </Botao>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 lg:flex-col lg:items-end">
          <dl className="grid grid-cols-3 gap-4 text-right text-sm">
            <div>
              <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">Previsto</dt>
              <dd className="numero text-creme">{formatarMinutos(l.previsto_minutos)}</dd>
            </div>
            <div>
              <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">Trabalhado</dt>
              <dd className="numero text-creme">{formatarMinutos(l.trabalhado_minutos)}</dd>
            </div>
            <div>
              <dt className="text-[10px] font-bold tracking-[0.14em] text-lavanda uppercase">Saldo</dt>
              <dd>
                <TextoSaldo minutos={l.saldo_minutos} provisorio={!l.encerrado} />
              </dd>
            </div>
          </dl>
          {operar && (
            <div className="flex flex-wrap gap-1">
              <Botao variante="fantasma" tamanho="p" icone={<Plus aria-hidden className="size-4" />} onClick={() => aoIncluir(null)} aria-label={`Incluir batida em ${formatarData(l.data)}`}>
                Batida
              </Botao>
              {l.abono_tipo && temAbono ? (
                <Botao variante="fantasma" tamanho="p" onClick={aoRemoverAbono}>
                  Remover abono
                </Botao>
              ) : (
                !l.abono_tipo && (
                  <Botao variante="fantasma" tamanho="p" onClick={aoAbonar} aria-label={`Abonar ${formatarData(l.data)}`}>
                    Abonar
                  </Botao>
                )
              )}
            </div>
          )}
        </div>
      </div>
    </li>
  )
}
