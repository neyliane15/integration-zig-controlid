import { Link } from 'react-router-dom'
import { Download, PiggyBank } from 'lucide-react'
import type { GastosPessoa } from '@/tipos/banco'
import { Botao, Cartao, ErroCarga, Esqueleto, FOCO, Indicador, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { GraficoBarrasDias, type SerieBarras } from '@/componentes/dominio/GraficoBarras'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useGastosPeriodo } from '@/consultas/extras'
import { csvGastos } from '@/lib/extras'
import { baixarCsv } from '@/lib/csv'
import { formatarCentavos, formatarData } from '@/lib/formato'
import { rotuloModoRateio, rotuloStatusFechamento } from '@/lib/rotulos'

const SERIES: SerieBarras[] = [
  { id: 'diarias_pagas', rotulo: 'Diárias pagas', cor: 'bg-sucesso/80' },
  { id: 'diarias_a_pagar', rotulo: 'Diárias a pagar', cor: 'bg-alerta/80' },
  { id: 'comissoes_fechadas', rotulo: 'Comissões fechadas', cor: 'bg-ouro/85' },
]

const moeda = (c: number) => <span className="numero">{c ? formatarCentavos(c) : '—'}</span>

export function AbaGastos({ inicio, fim }: { inicio: string; fim: string }) {
  const { empresa } = useContextoEmpresa()
  const gastos = useGastosPeriodo(inicio, fim)
  const g = gastos.data

  if (gastos.error) return <ErroCarga erro={gastos.error} aoTentar={() => gastos.refetch()} />
  if (!g)
    return (
      <div className="flex flex-col gap-5" aria-busy="true">
        <span className="sr-only">Carregando gastos…</span>
        <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 2xl:grid-cols-5">
          {[0, 1, 2, 3, 4].map((i) => (
            <Esqueleto key={i} className="h-[112px] rounded-cartao" />
          ))}
        </div>
        <Esqueleto className="h-64 rounded-cartao" />
      </div>
    )

  const t = g.totais
  const colunas: Coluna<GastosPessoa>[] = [
    {
      id: 'nome',
      titulo: 'Pessoa',
      render: (p) => (
        <span className="flex flex-wrap items-center gap-2 font-semibold text-creme">
          {p.funcionario_id ? (
            <Link to={`/funcionarios/${p.funcionario_id}`} className={`truncate hover:underline ${FOCO}`}>
              {p.nome}
            </Link>
          ) : (
            <span className="truncate">{p.nome}</span>
          )}
          {p.tipo === 'extra' && <Selo tom="info">Extra</Selo>}
        </span>
      ),
    },
    { id: 'qtd', titulo: 'Diárias', alinhar: 'direita', render: (p) => <span className="numero">{p.diarias_qtd || '—'}</span> },
    { id: 'pagas', titulo: 'Pagas', alinhar: 'direita', render: (p) => moeda(p.diarias_pagas) },
    { id: 'apagar', titulo: 'A pagar', alinhar: 'direita', render: (p) => moeda(p.diarias_a_pagar) },
    { id: 'com', titulo: 'Comissão', alinhar: 'direita', render: (p) => moeda(p.comissoes_fechadas) },
    { id: 'prev', titulo: 'Prevista', alinhar: 'direita', ocultarNoCelular: true, render: (p) => <span className="text-lavanda">{moeda(p.comissoes_previstas)}</span> },
    { id: 'total', titulo: 'Total', alinhar: 'direita', render: (p) => <span className="numero font-semibold text-ouro-claro">{formatarCentavos(p.total)}</span> },
  ]

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 2xl:grid-cols-5">
        <Indicador
          rotulo="Diárias"
          valor={formatarCentavos(t.diarias)}
          tom="sucesso"
          detalhe={`${t.diarias_qtd} dia(s) · extras ${formatarCentavos(t.diarias_extras)} · funcionários ${formatarCentavos(t.diarias_funcionarios)}`}
        />
        <Indicador
          rotulo="Diárias a pagar"
          valor={formatarCentavos(t.diarias_a_pagar)}
          tom={t.diarias_a_pagar > 0 ? 'alerta' : undefined}
          detalhe={`${formatarCentavos(t.diarias_pagas)} já pago`}
        />
        <Indicador rotulo="Comissões fechadas" valor={formatarCentavos(t.comissoes_fechadas)} />
        <Indicador rotulo="Comissões previstas" valor={formatarCentavos(t.comissoes_previstas)} detalhe="Rascunhos (não somam no total)" tom="info" />
        <div className="col-span-2 lg:col-span-1 2xl:col-span-1">
          <Indicador
            rotulo="Total geral"
            valor={formatarCentavos(t.total)}
            tom="ouro"
            detalhe={t.comissoes_previstas > 0 ? `${formatarCentavos(t.total_com_previsto)} com o previsto` : 'Diárias + comissões fechadas'}
          />
        </div>
      </div>

      <Cartao titulo="Gastos por dia" sobrancelha={`${formatarData(g.inicio)} a ${formatarData(g.fim)}`}>
        {t.total === 0 ? (
          <Vazio icone={<PiggyBank aria-hidden />} titulo="Nenhum gasto no período" descricao="Diárias lançadas e comissões fechadas aparecem aqui." />
        ) : (
          <>
            <GraficoBarrasDias
              titulo="Gastos por dia"
              series={SERIES}
              pontos={g.por_dia.map((d) => ({
                data: d.data,
                valores: { diarias_pagas: d.diarias_pagas, diarias_a_pagar: d.diarias_a_pagar, comissoes_fechadas: d.comissoes_fechadas },
              }))}
            />
            <p className="mt-3 text-xs text-lavanda">
              Rateio diário: a comissão cai no próprio dia trabalhado. Rateio por período: entra inteira no último dia do fechamento.
            </p>
          </>
        )}
      </Cartao>

      <Cartao
        titulo="Por pessoa"
        acoes={
          <Botao
            variante="secundario"
            tamanho="p"
            icone={<Download aria-hidden />}
            onClick={() => {
              const { nome, conteudo } = csvGastos(g, empresa?.nome ?? 'empresa')
              baixarCsv(nome, conteudo)
            }}
          >
            Exportar CSV
          </Botao>
        }
      >
        <Tabela colunas={colunas} linhas={g.por_pessoa} chave={(p) => p.chave} vazio={<Vazio titulo="Ninguém com gastos no período" />} />
      </Cartao>

      {g.fechamentos.length > 0 && (
        <Cartao titulo="Fechamentos considerados" sobrancelha="Comissões que caem no período">
          <ul className="flex flex-col divide-y divide-borda">
            {g.fechamentos.map((f) => (
              <li key={f.id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 last:pb-0">
                <Link to={`/comissoes/${f.id}`} className={`min-w-0 truncate font-semibold text-creme hover:underline ${FOCO}`}>
                  {f.titulo}
                </Link>
                <span className="flex flex-wrap items-center gap-3">
                  <span className="text-xs text-lavanda">{rotuloModoRateio[f.modo_rateio]}</span>
                  <Selo tom={f.status === 'fechado' ? 'sucesso' : 'ouro'}>{rotuloStatusFechamento[f.status]}</Selo>
                  <span className="numero text-right text-sm">
                    {formatarCentavos(f.valor_no_periodo_centavos)}
                    {f.valor_no_periodo_centavos !== f.base_distribuivel_centavos && (
                      <span className="block text-[11px] text-lavanda">de {formatarCentavos(f.base_distribuivel_centavos)}</span>
                    )}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </Cartao>
      )}
    </div>
  )
}
