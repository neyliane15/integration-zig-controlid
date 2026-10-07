import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Download, Hourglass, Plus, Search } from 'lucide-react'
import type { LinhaBancoHorasResumo } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Campo, Entrada, EntradaData, ErroCarga, Indicador, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { TextoSaldo } from '@/componentes/dominio/Selos'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { useBancoHorasResumo } from '@/consultas/bancoHoras'
import { usePerfil } from '@/lib/sessao'
import { podeAdministrar, podeOperar } from '@/lib/permissoes'
import { formatarData, formatarMinutos, normalizar, somarDias } from '@/lib/formato'
import { baixarCsv, gerarCsv, minutosCsv, nomeArquivoCsv } from '@/lib/csv'
import { dataValida } from '@/lib/ponto'
import { ModalLancamento } from './ModalLancamento'

export function PaginaBancoHoras() {
  const perfil = usePerfil()
  const operar = podeOperar(perfil.papel)
  const navegar = useNavigate()
  const { hoje, empresa } = useContextoEmpresa()
  const ontem = somarDias(hoje, -1)
  const [params, setParams] = useSearchParams()
  const ateParam = params.get('ate')
  const ate = dataValida(ateParam) ? ateParam : null
  const referencia = ate ?? ontem
  const [busca, setBusca] = useState('')
  const [lancar, setLancar] = useState(false)

  const resumo = useBancoHorasResumo(ate)

  const linhas = useMemo(() => {
    const termo = normalizar(busca)
    return (resumo.data ?? [])
      .filter((l) => !termo || normalizar(`${l.funcionario_nome} ${l.cargo ?? ''}`).includes(termo))
      .sort((a, b) => a.funcionario_nome.localeCompare(b.funcionario_nome, 'pt-BR'))
  }, [resumo.data, busca])

  const totais = useMemo(() => {
    const t = { credito: 0, debito: 0, negativos: 0 }
    for (const l of resumo.data ?? []) {
      if (l.saldo_minutos > 0) t.credito += l.saldo_minutos
      else if (l.saldo_minutos < 0) {
        t.debito += l.saldo_minutos
        t.negativos += 1
      }
    }
    return t
  }, [resumo.data])

  const exportar = () => {
    const conteudo = gerarCsv(
      ['Funcionário', 'Cargo', 'Saldo (hh:mm)', 'Saldo do mês (hh:mm)'],
      linhas.map((l) => [l.funcionario_nome, l.cargo ?? '', minutosCsv(l.saldo_minutos), minutosCsv(l.saldo_mes_minutos)]),
    )
    baixarCsv(nomeArquivoCsv('banco-horas', empresa?.nome ?? 'empresa', referencia), conteudo)
  }

  const colunas: Coluna<LinhaBancoHorasResumo>[] = [
    {
      id: 'nome',
      titulo: 'Funcionário',
      render: (l) => (
        <div className="min-w-0">
          <p className="truncate font-semibold text-creme">{l.funcionario_nome}</p>
          {l.cargo && <p className="text-xs text-lavanda">{l.cargo}</p>}
        </div>
      ),
    },
    { id: 'saldo', titulo: 'Saldo', alinhar: 'direita', render: (l) => <TextoSaldo minutos={l.saldo_minutos} className="text-base font-semibold" /> },
    { id: 'mes', titulo: 'No mês', alinhar: 'direita', render: (l) => <TextoSaldo minutos={l.saldo_mes_minutos} /> },
    {
      id: 'ultimo',
      titulo: 'Último dia apurado',
      ocultarNoCelular: true,
      render: (l) => <span className="numero text-lavanda">{l.ultimo_dia_apurado ? formatarData(l.ultimo_dia_apurado) : '—'}</span>,
    },
  ]

  return (
    <div className="mx-auto w-full max-w-6xl">
      <CabecalhoPagina
        sobrancelha="Ponto"
        titulo={
          <>
            Banco <span className="titulo-italico">de horas</span>
          </>
        }
        subtitulo={`Saldo calculado pelas batidas e pela jornada, até ${formatarData(referencia)} (dias encerrados) + lançamentos manuais.`}
        acoes={
          <>
            <Botao variante="secundario" icone={<Download aria-hidden className="size-4" />} onClick={exportar} disabled={!linhas.length}>
              Exportar CSV
            </Botao>
            {operar && (
              <Botao icone={<Plus aria-hidden className="size-4" />} onClick={() => setLancar(true)}>
                Lançamento
              </Botao>
            )}
          </>
        }
      />

      <div className="mb-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Indicador rotulo="Horas a favor da equipe" valor={formatarMinutos(totais.credito, { sinal: true })} tom="sucesso" detalhe="soma dos saldos positivos" />
        <Indicador rotulo="Horas devidas" valor={formatarMinutos(totais.debito)} tom={totais.debito ? 'perigo' : undefined} detalhe="soma dos saldos negativos" />
        <Indicador rotulo="Funcionários negativos" valor={totais.negativos} tom={totais.negativos ? 'alerta' : undefined} />
      </div>

      <div className="mb-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_200px]">
        <Campo rotulo="Buscar" htmlFor="busca-bh">
          <div className="relative">
            <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-lavanda" />
            <Entrada id="busca-bh" type="search" className="pl-9" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou cargo" />
          </div>
        </Campo>
        <Campo rotulo="Saldo até" htmlFor="bh-ate">
          <EntradaData
            id="bh-ate"
            valor={referencia}
            max={ontem}
            aoMudar={(v) => {
              const p = new URLSearchParams(params)
              if (v && v !== ontem) p.set('ate', v)
              else p.delete('ate')
              setParams(p, { replace: true })
            }}
          />
        </Campo>
      </div>

      {resumo.error ? (
        <ErroCarga erro={resumo.error} aoTentar={() => resumo.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={linhas}
          chave={(l) => l.funcionario_id}
          carregando={resumo.isLoading}
          aoClicarLinha={(l) => navegar(`/banco-de-horas/${l.funcionario_id}`)}
          vazio={<Vazio icone={<Hourglass className="size-8" />} titulo={busca ? 'Ninguém encontrado' : 'Sem funcionários ativos'} />}
        />
      )}

      {lancar && (
        <ModalLancamento aberto aoFechar={() => setLancar(false)} dataPadrao={ontem} permitirSaldoInicial={podeAdministrar(perfil.papel)} />
      )}
    </div>
  )
}
