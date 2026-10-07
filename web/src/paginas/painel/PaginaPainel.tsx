/** / — Painel do dia (contrato §14.4). Dono: frontend-1. */
import { Link } from 'react-router-dom'
import clsx from 'clsx'
import { AlertTriangle, ArrowRight, Check, ListChecks, PlugZap, Users } from 'lucide-react'
import type { PainelDoDia } from '@/tipos/banco'
import { Cartao, CabecalhoPagina, ErroCarga, Esqueleto, FOCO, Indicador, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { BotaoSincronizar, IconeIntegracao, SeloStatusIntegracao } from '@/componentes/integracoes/comum'
import { useMudarStatusTarefa, usePainel, useTarefasDoPainel, type TarefaPainel } from '@/consultas/painel'
import { formatarCentavos, formatarDataCurta, formatarRelativo } from '@/lib/formato'
import { podeOperar } from '@/lib/permissoes'
import { rotuloBatidaEsperada, rotuloPrioridade, rotuloTipoAlarme } from '@/lib/rotulos'
import { useEmpresaAtual, usePerfil } from '@/lib/sessao'

function saudacao(agora = new Date()): string {
  const h = agora.getHours()
  return h >= 5 && h < 12 ? 'Bom dia' : h >= 12 && h < 18 ? 'Boa tarde' : 'Boa noite'
}

function dataPorExtenso(iso: string): string {
  const [a, m, d] = iso.split('-').map(Number)
  const texto = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(
    new Date(Date.UTC(a!, m! - 1, d!)),
  )
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

export function PaginaPainel() {
  const perfil = usePerfil()
  const { empresaId, empresa } = useEmpresaAtual()
  const painel = usePainel(empresaId)
  const primeiroNome = perfil.nome.split(' ')[0] ?? perfil.nome
  const p = painel.data

  return (
    <div className="surgir">
      <CabecalhoPagina
        sobrancelha={p ? dataPorExtenso(p.dia_trabalho) : 'Painel do dia'}
        titulo={
          <>
            {saudacao()}, <span className="titulo-italico">{primeiroNome}.</span>
          </>
        }
        subtitulo={empresa ? `Tudo o que importa hoje no ${empresa.nome}.` : 'Tudo o que importa hoje na sua loja.'}
      />

      {painel.isError ? (
        <ErroCarga erro={painel.error} aoTentar={() => void painel.refetch()} />
      ) : !p ? (
        <EsqueletoPainel />
      ) : (
        <div className="flex flex-col gap-5">
          <Indicadores p={p} />
          <div className="grid gap-5 lg:grid-cols-[1.25fr_1fr]">
            <div className="flex min-w-0 flex-col gap-5">
              <CartaoAlarmes p={p} />
              <CartaoTarefas empresaId={empresaId} p={p} />
            </div>
            <div className="flex min-w-0 flex-col gap-5">
              <CartaoPresenca p={p} />
              <CartaoSincronizacao empresaId={empresaId} p={p} podeSincronizar={podeOperar(perfil.papel)} />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function EsqueletoPainel() {
  return (
    <div className="flex flex-col gap-5" aria-busy="true">
      <span className="sr-only">Carregando painel…</span>
      <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <Esqueleto key={i} className="h-[112px] rounded-cartao" />
        ))}
      </div>
      <div className="grid gap-5 lg:grid-cols-[1.25fr_1fr]">
        <Esqueleto className="h-72 rounded-cartao" />
        <Esqueleto className="h-72 rounded-cartao" />
      </div>
    </div>
  )
}

function Indicadores({ p }: { p: PainelDoDia }) {
  const semZig = !p.faturamento.tem_zig
  const v = (c: number) => (semZig ? '—' : formatarCentavos(c))
  return (
    <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-4">
      <Indicador rotulo="Faturamento hoje" valor={v(p.faturamento.hoje)} tom="ouro" detalhe={semZig ? 'Conecte a Zig' : 'Até agora'} />
      <Indicador rotulo="Ontem" valor={v(p.faturamento.ontem)} detalhe={formatarDataCurta(p.ontem)} />
      <Indicador rotulo="No mês" valor={v(p.faturamento.mes)} detalhe="Faturamento acumulado" />
      <Indicador rotulo="Serviço ontem" valor={v(p.servico.ontem)} detalhe={semZig ? undefined : `${formatarCentavos(p.servico.mes)} no mês`} />
    </div>
  )
}

function LinkCartao({ para, children }: { para: string; children: React.ReactNode }) {
  return (
    <Link
      to={para}
      className={clsx('inline-flex items-center gap-1.5 rounded text-sm font-semibold text-ouro hover:text-ouro-claro', FOCO)}
    >
      {children}
      <ArrowRight aria-hidden className="size-4" />
    </Link>
  )
}

function CartaoAlarmes({ p }: { p: PainelDoDia }) {
  const { alarmes, alarmes_abertos } = p.ponto
  return (
    <Cartao
      sobrancelha="Ponto"
      titulo={
        <span className="flex items-center gap-3">
          Alarmes de ponto
          {alarmes_abertos > 0 && <Selo tom="alerta">{alarmes_abertos} em aberto</Selo>}
        </span>
      }
      acoes={<LinkCartao para="/ponto/alarmes?status=aberto">Ver todos</LinkCartao>}
    >
      {alarmes.length === 0 ? (
        <p className="flex items-center gap-2.5 rounded-entrada border border-sucesso/25 bg-sucesso/5 px-4 py-3 text-sm text-creme">
          <Check aria-hidden className="size-4 text-sucesso" /> Nenhum alarme em aberto. Equipe em dia.
        </p>
      ) : (
        <ul className="-mx-2 flex flex-col">
          {alarmes.map((a) => (
            <li key={a.id}>
              <Link
                to={`/ponto/funcionario/${a.funcionario_id}?mes=${a.data.slice(0, 7)}`}
                className={clsx('flex items-start gap-3 rounded-entrada px-2 py-2.5 transition-colors hover:bg-cartao-2', FOCO)}
              >
                <span className="mt-0.5 grid size-8 shrink-0 place-items-center rounded-full bg-alerta/10 text-alerta">
                  <AlertTriangle aria-hidden className="size-4" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="flex flex-wrap items-baseline justify-between gap-x-3">
                    <span className="truncate font-semibold text-creme">{a.funcionario_nome}</span>
                    <span className="numero text-xs text-lavanda">{formatarDataCurta(a.data)}</span>
                  </span>
                  <span className="mt-0.5 block text-sm text-lavanda">
                    {a.detalhe ||
                      `${rotuloTipoAlarme[a.tipo]}${a.batida_esperada ? ` · ${rotuloBatidaEsperada[a.batida_esperada]}` : ''}`}
                  </span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      {p.ponto.batidas_sem_funcionario > 0 && (
        <p className="mt-4 text-xs text-lavanda">
          {p.ponto.batidas_sem_funcionario} batida(s) sem funcionário vinculado —{' '}
          <Link to="/integracoes" className="font-semibold text-ouro hover:underline">
            revise os vínculos do Control iD
          </Link>
          .
        </p>
      )}
    </Cartao>
  )
}

function CartaoPresenca({ p }: { p: PainelDoDia }) {
  const { presentes_agora: presentes, escalados_hoje: escalados } = p.ponto
  const pct = escalados > 0 ? Math.min(100, Math.round((presentes / escalados) * 100)) : 0
  return (
    <Cartao sobrancelha="Equipe" titulo="Presentes agora" acoes={<LinkCartao para="/ponto">Ponto do dia</LinkCartao>}>
      <div className="flex items-end gap-3">
        <p className="numero text-[44px] leading-none text-creme">{presentes}</p>
        <p className="pb-1 text-sm text-lavanda">
          de <span className="numero text-creme">{escalados}</span> escalados hoje
        </p>
        <Users aria-hidden className="mb-1 ml-auto size-6 text-lavanda-escuro" />
      </div>
      <div
        className="mt-4 h-2 overflow-hidden rounded-pilula bg-cartao-2"
        role="progressbar"
        aria-label="Presentes em relação aos escalados"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={pct}
      >
        <div className="h-full rounded-pilula bg-ouro transition-all" style={{ width: `${pct}%` }} />
      </div>
    </Cartao>
  )
}

function CartaoTarefas({ empresaId, p }: { empresaId: string | null; p: PainelDoDia }) {
  const tarefas = useTarefasDoPainel(empresaId, p.dia_trabalho)
  const mudar = useMudarStatusTarefa()
  const avisos = useAvisos()
  const { total, concluidas, atrasadas } = p.tarefas
  const pct = total > 0 ? Math.round((concluidas / total) * 100) : 0
  const lista = (tarefas.data ?? []).slice(0, 6)

  function alternar(t: TarefaPainel) {
    mudar.mutate(
      { tarefa: t.id, status: t.status === 'concluida' ? 'pendente' : 'concluida' },
      { onError: avisos.erro },
    )
  }

  return (
    <Cartao
      sobrancelha="Rotina"
      titulo={
        <span className="flex items-center gap-3">
          Tarefas de hoje
          {atrasadas > 0 && <Selo tom="perigo">{atrasadas} atrasada{atrasadas > 1 ? 's' : ''}</Selo>}
        </span>
      }
      acoes={<LinkCartao para="/tarefas">Abrir tarefas</LinkCartao>}
    >
      <div className="mb-4 flex items-center gap-4">
        <div className="h-2 flex-1 overflow-hidden rounded-pilula bg-cartao-2" role="progressbar" aria-label="Tarefas concluídas" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
          <div className="h-full rounded-pilula bg-ouro transition-all" style={{ width: `${pct}%` }} />
        </div>
        <p className="numero shrink-0 text-sm text-lavanda">
          <span className="text-creme">{concluidas}</span>/{total}
        </p>
      </div>
      {tarefas.isPending ? (
        <div className="flex flex-col gap-2">
          <Esqueleto className="h-10" />
          <Esqueleto className="h-10" />
        </div>
      ) : lista.length === 0 ? (
        <Vazio icone={<ListChecks aria-hidden />} titulo="Nada para hoje" descricao="Crie rotinas para que as tarefas apareçam aqui todo dia." />
      ) : (
        <ul className="flex flex-col gap-1">
          {lista.map((t) => {
            const feita = t.status === 'concluida'
            return (
              <li key={t.id} className="flex items-center gap-3 rounded-entrada px-1 py-1.5">
                <button
                  type="button"
                  role="checkbox"
                  aria-checked={feita}
                  aria-label={`${feita ? 'Reabrir' : 'Concluir'}: ${t.titulo}`}
                  disabled={mudar.isPending && mudar.variables?.tarefa === t.id}
                  onClick={() => alternar(t)}
                  className={clsx(
                    'grid size-[22px] shrink-0 place-items-center rounded-md border transition-colors',
                    feita ? 'border-ouro bg-ouro text-tinta-ouro' : 'border-borda-forte bg-entrada hover:border-ouro/70',
                    FOCO,
                  )}
                >
                  {feita && <Check aria-hidden strokeWidth={3} className="size-3.5" />}
                </button>
                <span className={clsx('min-w-0 flex-1 truncate text-sm', feita ? 'text-lavanda-escuro line-through' : 'text-creme')}>
                  {t.titulo}
                </span>
                {t.horario_limite && <span className="numero text-xs text-lavanda">{t.horario_limite.slice(0, 5)}</span>}
                {t.prioridade === 'alta' && !feita && <Selo tom="alerta">{rotuloPrioridade.alta}</Selo>}
              </li>
            )
          })}
        </ul>
      )}
    </Cartao>
  )
}

function CartaoSincronizacao({ empresaId, p, podeSincronizar }: { empresaId: string | null; p: PainelDoDia; podeSincronizar: boolean }) {
  return (
    <Cartao
      sobrancelha="Integrações"
      titulo="Sincronização"
      acoes={podeSincronizar && p.sincronizacao.length > 0 ? <BotaoSincronizar empresaId={empresaId} rotulo="Sincronizar tudo" /> : undefined}
    >
      {p.sincronizacao.length === 0 ? (
        <Vazio
          icone={<PlugZap aria-hidden />}
          titulo="Nenhuma integração"
          descricao="Conecte a Zig e o Control iD para ver vendas e ponto aqui."
          acao={podeSincronizar ? <LinkCartao para="/integracoes">Configurar</LinkCartao> : undefined}
        />
      ) : (
        <ul className="flex flex-col divide-y divide-borda">
          {p.sincronizacao.map((s) => (
            <li key={s.integracao_id} className="flex items-start gap-3 py-3.5 first:pt-0 last:pb-0">
              <IconeIntegracao tipo={s.tipo} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <p className="min-w-0 truncate font-semibold text-creme">{s.nome}</p>
                  <SeloStatusIntegracao ativa={s.ativa} status={s.ultimo_status} executando={s.executando} />
                </div>
                <div className="mt-0.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
                  <p className="min-w-0 text-xs text-lavanda">
                    {s.ultimo_sucesso_em ? `Último sucesso ${formatarRelativo(s.ultimo_sucesso_em)}` : 'Ainda sem sucesso'}
                  </p>
                  {podeSincronizar && s.ativa && (
                    <BotaoSincronizar empresaId={empresaId} integracaoId={s.integracao_id} rotulo="Sincronizar" variante="fantasma" desabilitado={s.executando} />
                  )}
                </div>
                {s.ultimo_status === 'erro' && s.ultimo_erro && <p className="mt-1 line-clamp-2 text-xs text-perigo">{s.ultimo_erro}</p>}
              </div>
            </li>
          ))}
        </ul>
      )}
    </Cartao>
  )
}
