/**
 * /extras (`?aba=extras|dias|gastos&de&ate`) — adendo E v2: cadastro de extras (freelas/diaristas), dias trabalhados
 * (com pontos que entram na comissão do dia) e gastos do período. G A M.
 */
import { useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Abas, CabecalhoPagina, Cartao, FiltroPeriodo } from '@/componentes/ui'
import { useContextoEmpresa } from '@/consultas/funcionarios'
import { diasDoPeriodo } from '@/lib/comissao'
import { AbaExtras } from './AbaExtras'
import { AbaDias } from './AbaDias'
import { AbaGastos } from './AbaGastos'

type Aba = 'extras' | 'dias' | 'gastos'
const ABAS: Aba[] = ['extras', 'dias', 'gastos']
const RE_DATA = /^\d{4}-\d{2}-\d{2}$/

export function PaginaExtras() {
  const { hoje } = useContextoEmpresa()
  const [params, setParams] = useSearchParams()
  const aba: Aba = ABAS.includes(params.get('aba') as Aba) ? (params.get('aba') as Aba) : 'extras'
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
        subtitulo="Freelas e diaristas: cadastro, dias trabalhados (que entram na comissão do dia) e o quanto a equipe custou no período."
      />
      <Abas<Aba>
        abas={[
          { id: 'extras', rotulo: 'Extras' },
          { id: 'dias', rotulo: 'Dias trabalhados' },
          { id: 'gastos', rotulo: 'Gastos do período' },
        ]}
        ativa={aba}
        aoMudar={(a) => mudar({ aba: a })}
      />
      <div className="mt-5">
        {aba === 'extras' ? (
          <AbaExtras aoLancarDia={(extraId) => mudar({ aba: 'dias', lancar: extraId })} />
        ) : (
          <>
            <Cartao className="mb-5">
              <FiltroPeriodo inicio={inicio} fim={fim} hoje={hoje} aoMudar={(i, f) => mudar({ de: i, ate: f })} />
              {erroPeriodo && (
                <p role="alert" className="mt-3 text-sm text-perigo">
                  {erroPeriodo}
                </p>
              )}
            </Cartao>
            {erroPeriodo ? null : aba === 'dias' ? (
              <AbaDias
                inicio={inicio}
                fim={fim}
                lancarPara={params.get('lancar')}
                aoConsumirLancar={() => {
                  const p = new URLSearchParams(params)
                  p.delete('lancar')
                  setParams(p, { replace: true })
                }}
              />
            ) : (
              <AbaGastos inicio={inicio} fim={fim} />
            )}
          </>
        )}
      </div>
    </div>
  )
}
