/**
 * Link com aparência de botão (evita <button> dentro de <a>). Dono: frontend-2.
 * Visual alinhado ao `Botao` do ui.tsx.
 */
import type { ReactNode } from 'react'
import { Link, type LinkProps } from 'react-router-dom'
import clsx from 'clsx'
import { FOCO } from '@/componentes/ui'

const VARIANTES = {
  primario: 'bg-ouro text-tinta-ouro font-bold hover:bg-ouro-claro active:bg-ouro-escuro',
  secundario: 'border border-borda bg-entrada text-creme font-semibold hover:border-borda-forte hover:bg-cartao-2',
  fantasma: 'bg-transparent text-lavanda font-semibold hover:bg-cartao-2 hover:text-creme',
} as const
const TAMANHOS = { p: 'h-9 px-3 text-sm', m: 'h-11 px-4 text-sm' } as const

export function BotaoLink({
  variante = 'secundario',
  tamanho = 'm',
  icone,
  className,
  children,
  ...resto
}: LinkProps & { variante?: keyof typeof VARIANTES; tamanho?: keyof typeof TAMANHOS; icone?: ReactNode }) {
  return (
    <Link
      className={clsx(
        'inline-flex items-center justify-center gap-2 rounded-entrada whitespace-nowrap transition-colors [&_svg]:size-4',
        VARIANTES[variante],
        TAMANHOS[tamanho],
        FOCO,
        className,
      )}
      {...resto}
    >
      {icone}
      {children}
    </Link>
  )
}
