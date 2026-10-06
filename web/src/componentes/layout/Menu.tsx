/**
 * Itens do menu (contrato §14.3, ordem fixa) e navegação lateral. Dono: frontend-1.
 */
import { NavLink } from 'react-router-dom'
import clsx from 'clsx'
import {
  Building2,
  type LucideIcon,
  Clock,
  Coins,
  Hourglass,
  LayoutDashboard,
  ListChecks,
  PlugZap,
  Receipt,
  Settings,
  UserCog,
  Users,
} from 'lucide-react'
import type { Papel } from '@/tipos/banco'
import { ehMaster, podeAdministrar, podeOperar, podeVerComissoes } from '@/lib/permissoes'

export interface ItemMenu {
  rotulo: string
  para: string
  icone: LucideIcon
  grupo: 'Dia a dia' | 'Loja' | 'Ajustes' | 'Plataforma'
  permitir(p: Papel): boolean
  /** aparece na barra inferior do celular */
  atalho?: boolean
}

const todos = () => true

export const ITENS_MENU: ItemMenu[] = [
  { rotulo: 'Painel', para: '/', icone: LayoutDashboard, grupo: 'Dia a dia', permitir: todos, atalho: true },
  { rotulo: 'Ponto', para: '/ponto', icone: Clock, grupo: 'Dia a dia', permitir: todos, atalho: true },
  { rotulo: 'Banco de horas', para: '/banco-de-horas', icone: Hourglass, grupo: 'Dia a dia', permitir: todos },
  { rotulo: 'Funcionários', para: '/funcionarios', icone: Users, grupo: 'Dia a dia', permitir: todos },
  { rotulo: 'Vendas', para: '/vendas', icone: Receipt, grupo: 'Loja', permitir: todos, atalho: true },
  { rotulo: 'Comissões', para: '/comissoes', icone: Coins, grupo: 'Loja', permitir: podeVerComissoes },
  { rotulo: 'Tarefas', para: '/tarefas', icone: ListChecks, grupo: 'Loja', permitir: todos, atalho: true },
  { rotulo: 'Integrações', para: '/integracoes', icone: PlugZap, grupo: 'Ajustes', permitir: podeOperar },
  { rotulo: 'Configurações', para: '/configuracoes', icone: Settings, grupo: 'Ajustes', permitir: podeOperar },
  { rotulo: 'Usuários', para: '/usuarios', icone: UserCog, grupo: 'Ajustes', permitir: podeAdministrar },
  { rotulo: 'Empresas', para: '/master/empresas', icone: Building2, grupo: 'Plataforma', permitir: ehMaster },
]

export function itensDoPapel(papel: Papel): ItemMenu[] {
  return ITENS_MENU.filter((i) => i.permitir(papel))
}

export function MenuLateral({ papel, aoNavegar }: { papel: Papel; aoNavegar?(): void }) {
  const itens = itensDoPapel(papel)
  const grupos = [...new Set(itens.map((i) => i.grupo))]
  return (
    <nav aria-label="Menu principal" className="flex flex-col gap-6">
      {grupos.map((g) => (
        <div key={g}>
          <p className="mb-2 px-3 text-[10px] font-bold tracking-[0.22em] text-lavanda-escuro uppercase">{g}</p>
          <ul className="flex flex-col gap-0.5">
            {itens
              .filter((i) => i.grupo === g)
              .map((i) => (
                <li key={i.para}>
                  <NavLink
                    to={i.para}
                    end={i.para === '/'}
                    onClick={aoNavegar}
                    className={({ isActive }) =>
                      clsx(
                        'group relative flex h-10 items-center gap-3 rounded-entrada px-3 text-sm font-semibold transition-colors',
                        'focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-ouro',
                        isActive ? 'bg-ouro/10 text-ouro-claro' : 'text-lavanda hover:bg-cartao hover:text-creme',
                      )
                    }
                  >
                    {({ isActive }) => (
                      <>
                        <span
                          aria-hidden
                          className={clsx(
                            'absolute top-2 bottom-2 left-0 w-[3px] rounded-r-full bg-ouro transition-opacity',
                            isActive ? 'opacity-100' : 'opacity-0',
                          )}
                        />
                        <i.icone aria-hidden className={clsx('size-[18px]', isActive ? 'text-ouro' : 'text-lavanda-escuro group-hover:text-lavanda')} />
                        {i.rotulo}
                      </>
                    )}
                  </NavLink>
                </li>
              ))}
          </ul>
        </div>
      ))}
    </nav>
  )
}
