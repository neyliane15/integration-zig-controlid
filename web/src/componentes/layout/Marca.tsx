/** Monograma + nome do produto. Dono: frontend-1. */
import clsx from 'clsx'

export function Monograma({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" aria-hidden className={clsx('shrink-0', className)}>
      <rect x="1.5" y="1.5" width="61" height="61" rx="15" fill="var(--color-cartao)" stroke="var(--color-borda-forte)" strokeWidth="2" />
      <path d="M19 44V22l13 12.5L45 22v22" fill="none" stroke="var(--color-ouro)" strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function Marca({ compacta, className }: { compacta?: boolean; className?: string }) {
  return (
    <span className={clsx('inline-flex items-center gap-3', className)}>
      <Monograma className="size-9" />
      {!compacta && (
        <span className="flex flex-col leading-none">
          <span className="text-[10px] font-bold tracking-[0.24em] text-ouro uppercase">Meu dia de</span>
          <span className="mt-1 font-display text-[19px] text-creme">Gerente</span>
        </span>
      )}
    </span>
  )
}
