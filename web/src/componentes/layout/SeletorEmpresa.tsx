/**
 * Seletor de empresa do master (contrato §14.3). Dono: frontend-1.
 * Troca a empresa de `useEmpresaAtual()`; as telas reconsultam pelas query keys com empresaId.
 */
import { useId } from 'react'
import { useNavigate } from 'react-router-dom'
import { Building2, ChevronsUpDown } from 'lucide-react'
import { useEmpresas } from '@/consultas/empresas'
import { useEmpresaAtual } from '@/lib/sessao'

export function SeletorEmpresa({ aoTrocar }: { aoTrocar?(): void }) {
  const id = useId()
  const { empresaId, definirEmpresa } = useEmpresaAtual()
  const { data: empresas, isPending } = useEmpresas()
  const navegar = useNavigate()

  return (
    <div className="min-w-0">
      <label htmlFor={id} className="mb-1.5 block px-1 text-[10px] font-bold tracking-[0.22em] text-ouro uppercase">
        Empresa (master)
      </label>
      <div className="relative">
        <Building2 aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-lavanda" />
        <select
          id={id}
          data-teste="seletor-empresa"
          value={empresaId ?? ''}
          disabled={isPending}
          onChange={(e) => {
            definirEmpresa(e.target.value || null)
            aoTrocar?.()
            // detalhes de registro de outra empresa não fazem sentido: volta ao painel
            if (/\/[0-9a-f-]{36}$/.test(window.location.pathname)) navegar('/')
          }}
          className="h-10 w-full cursor-pointer appearance-none truncate rounded-entrada border border-borda bg-entrada pr-9 pl-9 text-sm font-semibold text-creme hover:border-borda-forte focus:border-ouro/70 focus:outline-none focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ouro"
        >
          {!empresaId && <option value="">{isPending ? 'Carregando…' : 'Escolha a empresa'}</option>}
          {(empresas ?? []).map((e) => (
            <option key={e.id} value={e.id}>
              {e.nome}
              {e.ativa ? '' : ' (inativa)'}
            </option>
          ))}
        </select>
        <ChevronsUpDown aria-hidden className="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-lavanda" />
      </div>
    </div>
  )
}
