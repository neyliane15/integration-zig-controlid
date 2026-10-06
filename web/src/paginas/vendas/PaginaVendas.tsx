import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import clsx from 'clsx'
import { Download, Medal, ShoppingBag } from 'lucide-react'
import { Abas, Botao, CabecalhoPagina, Campo, Carregando, Cartao, ErroCarga, FiltroPeriodo, Indicador, Selecao, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { buscarFaturamentoDetalhado, useFaturamentoPorDia, useFaturamentoPorForma, useLojasZig, useVendasPorGarcom, useVendasResumo } from '@/consultas/vendas'
import { diaSemanaCurto, formatarCentavos, formatarData, formatarDataCurta } from '@/lib/formato'
import { baixarCsv, centavosCsv, dataCsv, gerarCsv, nomeArquivoCsv } from '@/lib/csv'
import { dataValida } from '@/lib/ponto'
import {
  escalaBarras,
  estatisticasDias,
  faturamentoDiaForma,
  indicadores,
  participacaoPorForma,
  preencherDias,
  rankingGarcons,
  validarPeriodoVendas,
  type LinhaRanking,
} from '@/lib/vendas'

type Aba = 'faturamento' | 'garcons'

function quantidadeTexto(q: number): string {
  return q.toLocaleString('pt-BR', { maximumFractionDigits: 3 })
}

export function PaginaVendas() {
  const avisos = useAvisos()
  const { hoje, empresaId, empresa } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const inicio = dataValida(params.get('de')) ? (params.get('de') as string) : `${hoje.slice(0, 7)}-01`
  const fim = dataValida(params.get('ate')) ? (params.get('ate') as string) : hoje
  const loja = params.get('loja') || null
  const aba: Aba = params.get('aba') === 'garcons' ? 'garcons' : 'faturamento'
  const erroPeriodo = validarPeriodoVendas(inicio, fim)
  const ok = !erroPeriodo
  const [exportando, setExportando] = useState(false)

  const definir = (m: Record<string, string | null>) => {
    const p = new URLSearchParams(params)
    for (const [k, v] of Object.entries(m)) {
      if (v) p.set(k, v)
      else p.delete(k)
    }
    setParams(p, { replace: true })
  }

  const lojas = useLojasZig()
  const resumo = useVendasResumo(inicio, fim, loja, ok)
  const porDia = useFaturamentoPorDia(inicio, fim, loja, ok && aba === 'faturamento')
  const porForma = useFaturamentoPorForma(inicio, fim, loja, ok && aba === 'faturamento')
  const garcons = useVendasPorGarcom(inicio, fim, loja, ok && aba === 'garcons')

  const ind = indicadores(resumo.data)
  const dias = useMemo(() => preencherDias(inicio, fim, porDia.data ?? []), [inicio, fim, porDia.data])
  const barras = useMemo(() => escalaBarras(dias), [dias])
  const estat = useMemo(() => estatisticasDias(dias), [dias])
  const formas = useMemo(() => participacaoPorForma(porForma.data ?? []), [porForma.data])
  const ranking = useMemo(() => rankingGarcons(garcons.data ?? []), [garcons.data])
  const semZig = !lojas.isLoading && (lojas.data ?? []).length === 0 && !resumo.isLoading && ind.faturamento === 0 && ind.vendas === 0
  const nomeEmpresa = empresa?.nome ?? 'empresa'

  const exportarFaturamento = async () => {
    if (!empresaId) return
    setExportando(true)
    try {
      const registros = await buscarFaturamentoDetalhado(empresaId, inicio, fim, loja)
      const linhas = faturamentoDiaForma(registros).map((l) => [dataCsv(l.data), l.forma, centavosCsv(l.valor)])
      baixarCsv(nomeArquivoCsv('faturamento', nomeEmpresa, inicio, fim), gerarCsv(['Data', 'Forma de pagamento', 'Valor (R$)'], linhas))
    } catch (e) {
      avisos.erro(e)
    } finally {
      setExportando(false)
    }
  }

  const exportarGarcons = () => {
    const linhas = ranking.map((l) => [
      l.employee_name ?? '(sem garçom)',
      l.funcionario_nome ?? '',
      quantidadeTexto(l.quantidade).replace(/\./g, ''),
      centavosCsv(l.valor_vendas),
      centavosCsv(l.valor_servico),
      l.transacoes,
    ])
    baixarCsv(
      nomeArquivoCsv('vendas-garcom', nomeEmpresa, inicio, fim),
      gerarCsv(['Garçom', 'Funcionário', 'Quantidade', 'Vendas (R$)', 'Serviço (R$)', 'Transações'], linhas),
    )
  }

  const colunasGarcons: Coluna<LinhaRanking>[] = [
    {
      id: 'garcom',
      titulo: 'Garçom',
      render: (l) => (
        <div className="flex min-w-0 items-center gap-3">
          <span
            className={clsx(
              'numero grid size-8 shrink-0 place-items-center rounded-full text-sm font-bold',
              l.posicao === 1 ? 'bg-ouro text-tinta-ouro' : l.posicao > 0 && l.posicao <= 3 ? 'bg-ouro/20 text-ouro-claro' : 'bg-cartao-2 text-lavanda',
            )}
            aria-label={l.posicao ? `${l.posicao}º lugar` : 'sem posição'}
          >
            {l.posicao || '–'}
          </span>
          <div className="min-w-0">
            <p className="truncate font-semibold text-creme">{l.nomeExibido}</p>
            {l.funcionario_id ? (
              <Link to={`/funcionarios/${l.funcionario_id}`} className="text-xs text-ouro-claro underline-offset-4 hover:underline" onClick={(e) => e.stopPropagation()}>
                {l.funcionario_nome}
              </Link>
            ) : l.employee_name ? (
              <span className="text-xs text-alerta">sem funcionário vinculado</span>
            ) : null}
          </div>
        </div>
      ),
    },
    { id: 'vendas', titulo: 'Vendas', alinhar: 'direita', render: (l) => <span className="numero font-semibold">{formatarCentavos(l.valor_vendas)}</span> },
    { id: 'servico', titulo: 'Serviço', alinhar: 'direita', render: (l) => <span className="numero text-ouro-claro">{formatarCentavos(l.valor_servico)}</span> },
    { id: 'transacoes', titulo: 'Transações', alinhar: 'direita', ocultarNoCelular: true, render: (l) => <span className="numero">{l.transacoes}</span> },
    { id: 'ticket', titulo: 'Ticket médio', alinhar: 'direita', ocultarNoCelular: true, render: (l) => <span className="numero">{formatarCentavos(l.ticketMedio)}</span> },
    {
      id: 'part',
      titulo: 'Participação',
      render: (l) => (
        <div className="flex min-w-24 items-center gap-2">
          <div className="h-2 flex-1 overflow-hidden rounded-pilula bg-entrada" aria-hidden>
            <div className="h-full rounded-pilula bg-ouro" style={{ width: `${l.percentual}%` }} />
          </div>
          <span className="numero w-12 text-right text-xs text-lavanda">{l.percentual.toLocaleString('pt-BR')}%</span>
        </div>
      ),
    },
  ]

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Zig"
        titulo={
          <>
            Vendas <span className="titulo-italico">e faturamento</span>
          </>
        }
        subtitulo={`${formatarData(inicio)} a ${formatarData(fim)}${loja ? ` · ${(lojas.data ?? []).find((l) => l.loja_id_externo === loja)?.nome ?? loja}` : ''}`}
        acoes={
          aba === 'faturamento' ? (
            <Botao variante="secundario" icone={<Download aria-hidden className="size-4" />} carregando={exportando} onClick={exportarFaturamento} disabled={!ok || semZig}>
              Exportar CSV
            </Botao>
          ) : (
            <Botao variante="secundario" icone={<Download aria-hidden className="size-4" />} onClick={exportarGarcons} disabled={!ranking.length}>
              Exportar CSV
            </Botao>
          )
        }
      />

      <div className="mb-5 flex flex-wrap items-start gap-4">
        <FiltroPeriodo inicio={inicio} fim={fim} aoMudar={(de, ate) => definir({ de, ate })} />
        {(lojas.data ?? []).length > 1 && (
          <div className="w-full sm:w-60">
            <Campo rotulo="Loja" htmlFor="f-loja">
              <Selecao id="f-loja" value={loja ?? ''} onChange={(e) => definir({ loja: e.target.value || null })}>
                <option value="">Todas as lojas</option>
                {(lojas.data ?? []).map((l) => (
                  <option key={l.id} value={l.loja_id_externo}>
                    {l.nome}
                  </option>
                ))}
              </Selecao>
            </Campo>
          </div>
        )}
      </div>

      {erroPeriodo ? (
        <ErroCarga erro={erroPeriodo} />
      ) : semZig ? (
        <Vazio
          icone={<ShoppingBag className="size-8" />}
          titulo="Nenhum dado da Zig"
          descricao="Configure a integração com a Zig em Integrações e sincronize para ver faturamento e vendas por garçom."
        />
      ) : (
        <>
          {resumo.error ? (
            <div className="mb-5">
              <ErroCarga erro={resumo.error} aoTentar={() => resumo.refetch()} />
            </div>
          ) : (
            <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
              <Indicador rotulo="Faturamento" valor={resumo.isLoading ? '…' : formatarCentavos(ind.faturamento)} tom="ouro" />
              <Indicador rotulo="Vendas" valor={resumo.isLoading ? '…' : formatarCentavos(ind.vendas)} detalhe="itens, sem serviço" />
              <Indicador
                rotulo="Serviço (10%)"
                valor={resumo.isLoading ? '…' : formatarCentavos(ind.servico)}
                detalhe={
                  ind.divergenciaServico !== 0 && !resumo.isLoading
                    ? `${ind.percentualServico.toLocaleString('pt-BR')}% · conferência: ${formatarCentavos(ind.divergenciaServico, { sinal: true })}`
                    : `${ind.percentualServico.toLocaleString('pt-BR')}% das vendas`
                }
              />
              <Indicador rotulo="Descontos" valor={resumo.isLoading ? '…' : formatarCentavos(ind.descontos)} tom={ind.descontos ? 'alerta' : undefined} />
              <Indicador rotulo="Transações" valor={resumo.isLoading ? '…' : ind.transacoes.toLocaleString('pt-BR')} detalhe={`ticket médio ${formatarCentavos(ind.ticketMedio)}`} />
            </div>
          )}

          <Abas<Aba>
            abas={[
              { id: 'faturamento', rotulo: 'Faturamento' },
              { id: 'garcons', rotulo: 'Garçons', contador: garcons.data ? ranking.filter((r) => r.posicao > 0).length : undefined },
            ]}
            ativa={aba}
            aoMudar={(a) => definir({ aba: a === 'faturamento' ? null : a })}
          />

          <div className="mt-5">
            {aba === 'faturamento' ? (
              <div className="grid gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
                <Cartao
                  sobrancelha="Por dia"
                  titulo="Faturamento diário"
                  acoes={
                    estat.melhor && (
                      <span className="text-xs text-lavanda">
                        média {formatarCentavos(estat.mediaPorDiaComMovimento)} · melhor {formatarDataCurta(estat.melhor.data)}
                      </span>
                    )
                  }
                >
                  {porDia.isLoading ? (
                    <Carregando />
                  ) : porDia.error ? (
                    <ErroCarga erro={porDia.error} aoTentar={() => porDia.refetch()} />
                  ) : estat.total === 0 ? (
                    <Vazio titulo="Sem faturamento no período" />
                  ) : (
                    <GraficoDias barras={barras.barras} maximo={barras.maximo} />
                  )}
                </Cartao>
                <Cartao sobrancelha="Por forma de pagamento" titulo={formatarCentavos(formas.total)}>
                  {porForma.isLoading ? (
                    <Carregando />
                  ) : porForma.error ? (
                    <ErroCarga erro={porForma.error} aoTentar={() => porForma.refetch()} />
                  ) : formas.formas.length === 0 ? (
                    <Vazio titulo="Sem pagamentos no período" />
                  ) : (
                    <ul className="flex flex-col gap-3">
                      {formas.formas.map((f) => (
                        <li key={`${f.payment_id}-${f.payment_name}`}>
                          <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
                            <span className="truncate text-creme">{f.payment_name}</span>
                            <span className="numero whitespace-nowrap text-creme">
                              {formatarCentavos(f.valor)} <span className="text-xs text-lavanda">{f.percentual.toLocaleString('pt-BR')}%</span>
                            </span>
                          </div>
                          <div className="h-2 overflow-hidden rounded-pilula bg-entrada" aria-hidden>
                            <div className="h-full rounded-pilula bg-ouro" style={{ width: `${f.percentual}%` }} />
                          </div>
                        </li>
                      ))}
                    </ul>
                  )}
                </Cartao>
              </div>
            ) : garcons.error ? (
              <ErroCarga erro={garcons.error} aoTentar={() => garcons.refetch()} />
            ) : (
              <>
                {ranking.some((r) => r.employee_name && !r.funcionario_id) && (
                  <p className="mb-3 flex items-center gap-2 text-sm text-alerta">
                    <Medal aria-hidden className="size-4" />
                    Há garçons da Zig sem funcionário vinculado: ajuste o “Nome na Zig” no cadastro do funcionário.
                  </p>
                )}
                <Tabela
                  colunas={colunasGarcons}
                  linhas={ranking}
                  chave={(l) => l.employee_name ?? '(sem)'}
                  carregando={garcons.isLoading}
                  vazio={<Vazio titulo="Sem vendas por garçom no período" />}
                />
                {ranking.length > 0 && (
                  <p className="mt-3 text-xs text-lavanda">
                    <Selo tom="ouro">Serviço</Selo> é a soma dos itens de gorjeta (Tip) lançados por cada garçom.
                  </p>
                )}
              </>
            )}
          </div>
        </>
      )}
    </div>
  )
}

function GraficoDias({ barras, maximo }: { barras: { item: { data: string; valor: number }; percentual: number }[]; maximo: number }) {
  const muitos = barras.length > 31
  const passoRotulo = barras.length <= 14 ? 1 : barras.length <= 31 ? 3 : Math.ceil(barras.length / 10)
  return (
    <figure>
      <figcaption className="sr-only">Faturamento por dia, máximo de {formatarCentavos(maximo)}</figcaption>
      <div className="flex h-44 items-end gap-px sm:gap-1" role="list">
        {barras.map((b) => (
          <div
            key={b.item.data}
            role="listitem"
            className="group flex h-full min-w-0 flex-1 flex-col justify-end"
            title={`${formatarData(b.item.data)} (${diaSemanaCurto(b.item.data)}): ${formatarCentavos(b.item.valor)}`}
            aria-label={`${formatarData(b.item.data)}: ${formatarCentavos(b.item.valor)}`}
          >
            <div
              className={clsx(
                'w-full transition-colors',
                muitos ? 'rounded-t-[2px]' : 'rounded-t-[4px]',
                b.item.valor > 0 ? 'bg-ouro/80 group-hover:bg-ouro-claro' : 'bg-borda',
              )}
              style={{ height: b.item.valor > 0 ? `${b.percentual}%` : '2px' }}
            />
          </div>
        ))}
      </div>
      <div className="mt-1 flex gap-px overflow-hidden sm:gap-1" aria-hidden>
        {barras.map((b, i) => (
          <span key={b.item.data} className="numero min-w-0 flex-1 overflow-visible text-center text-[10px] whitespace-nowrap text-lavanda">
            {i % passoRotulo === 0 ? formatarDataCurta(b.item.data) : ''}
          </span>
        ))}
      </div>
    </figure>
  )
}
