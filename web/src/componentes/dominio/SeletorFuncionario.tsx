/**
 * Seleção de funcionário (contrato §14.5). Dono: frontend-2.
 */
import { useId } from 'react'
import { Selecao } from '@/componentes/ui'
import { useFuncionarios } from '@/consultas/funcionarios'

export function SeletorFuncionario({
  valor,
  aoMudar,
  permitirTodos,
  somenteAtivos,
  id,
  rotuloTodos = 'Todos os funcionários',
  rotuloAcessivel = 'Funcionário',
  desabilitado,
}: {
  valor: string | null
  aoMudar(id: string | null): void
  permitirTodos?: boolean
  somenteAtivos?: boolean
  id?: string
  rotuloTodos?: string
  /** aria-label quando não houver <label> externo */
  rotuloAcessivel?: string
  desabilitado?: boolean
}) {
  const gerado = useId()
  const { data, isLoading } = useFuncionarios()
  const lista = (data ?? []).filter((f) => !somenteAtivos || f.ativo || f.id === valor)
  return (
    <Selecao
      id={id ?? gerado}
      aria-label={id ? undefined : rotuloAcessivel}
      value={valor ?? ''}
      disabled={desabilitado || isLoading}
      onChange={(e) => aoMudar(e.target.value || null)}
    >
      {(permitirTodos || !valor) && <option value="">{isLoading ? 'Carregando…' : permitirTodos ? rotuloTodos : 'Escolha…'}</option>}
      {lista.map((f) => (
        <option key={f.id} value={f.id}>
          {f.nome}
          {f.cargo ? ` — ${f.cargo}` : ''}
          {f.ativo ? '' : ' (inativo)'}
        </option>
      ))}
    </Selecao>
  )
}
