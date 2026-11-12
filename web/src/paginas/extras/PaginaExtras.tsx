/**
 * /extras (`?aba=pontos|diarias|gastos&de&ate`) — pontos extras de comissão, diárias e gastos do período (adendo E). G A M.
 */
import { useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Abas, CabecalhoPagina, Cartao, FiltroPeriodo } from '@/componentes/ui'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { diasDoPeriodo } from '@/lib/comissao'
import { AbaPontosExtras } from './AbaPontosExtras'
import { AbaDiarias } from './AbaDiarias'
import { AbaGastos } from './AbaGastos'

type Aba = 'pontos' | 'diarias' | 'gastos'
const ABAS: Aba[] = ['pontos', 'diarias', 'gastos']
const RE_DATA = /^\d{4}-\d{2}-\d{2}$/

export function PaginaExtras() {
  const { hoje } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const aba: Aba = ABAS.includes(params.get('aba') as Aba) ? (params.get('aba') as Aba) : 'pontos'
  const de = params.get('de')
  const ate = params.get('ate')
  const inicio = de && RE_DATA.test(de) ? de : `${hoje.slice(0, 7)}-01`
  const fim = ate && RE_DATA.test(ate) && ate >= inicio ? ate : hoje < inicio ? inicio : hoje
  const erroPeriodo = useMemo(() => (diasDoPeriodo(inicio, fim) > 366 ? 'Período máximo de 366 dias' : null), [inicio, fim])

  const mudar = (novo: Record<string, string>) => {
    const p = new URLSearchParams(params)
    for (const [k, v] of Object.entries(novo)) p.set(k, v)
    setParams(p, { replace: true })
  }

  return (
    <div className="mx-auto w-full max-w-7xl">
      <CabecalhoPagina
        sobrancelha="Equipe"
        titulo={
          <>
            Extras <span className="titulo-italico">e gastos</span>
          </>
        }
        subtitulo="Pontos extras de comissão, diárias de freelancers e o quanto a equipe custou no período."
      />
      <Cartao className="mb-5">
        <FiltroPeriodo inicio={inicio} fim={fim} hoje={hoje} aoMudar={(i, f) => mudar({ de: i, ate: f })} />
        {erroPeriodo && (
          <p role="alert" className="mt-3 text-sm text-perigo">
            {erroPeriodo}
          </p>
        )}
      </Cartao>
      <Abas<Aba>
        abas={[
          { id: 'pontos', rotulo: 'Pontos extras' },
          { id: 'diarias', rotulo: 'Diárias' },
          { id: 'gastos', rotulo: 'Gastos do período' },
        ]}
        ativa={aba}
        aoMudar={(a) => mudar({ aba: a })}
      />
      <div className="mt-5">
        {erroPeriodo ? null : aba === 'pontos' ? (
          <AbaPontosExtras inicio={inicio} fim={fim} />
        ) : aba === 'diarias' ? (
          <AbaDiarias inicio={inicio} fim={fim} />
        ) : (
          <AbaGastos inicio={inicio} fim={fim} />
        )}
      </div>
    </div>
  )
}
