/**
 * Peças compartilhadas das telas de tarefas e rotinas. Dono: frontend-2.
 */
import { useMemo } from 'react'
import type { Prioridade } from '@/tipos/banco'
import { Selecao, Selo, type Tom } from '@/componentes/ui'
import { useFuncionarios, usePerfisEmpresa } from '@/consultas/funcionarios'
import { rotuloPrioridade } from '@/lib/rotulos'

export const TOM_PRIORIDADE: Record<Prioridade, Tom> = { alta: 'perigo', normal: 'neutro', baixa: 'info' }

export function SeloPrioridade({ prioridade }: { prioridade: Prioridade }) {
  if (prioridade === 'normal') return null
  return <Selo tom={TOM_PRIORIDADE[prioridade]}>{rotuloPrioridade[prioridade]}</Selo>
}

export interface Responsavel {
  responsavel_funcionario_id: string | null
  responsavel_perfil_id: string | null
}

function codificar(r: Responsavel): string {
  if (r.responsavel_perfil_id) return `p:${r.responsavel_perfil_id}`
  if (r.responsavel_funcionario_id) return `f:${r.responsavel_funcionario_id}`
  return ''
}

function decodificar(v: string): Responsavel {
  if (v.startsWith('p:')) return { responsavel_perfil_id: v.slice(2), responsavel_funcionario_id: null }
  if (v.startsWith('f:')) return { responsavel_funcionario_id: v.slice(2), responsavel_perfil_id: null }
  return { responsavel_funcionario_id: null, responsavel_perfil_id: null }
}

/** Seleção de responsável: um funcionário ou um usuário do sistema. */
export function SeletorResponsavel({ id, valor, aoMudar }: { id: string; valor: Responsavel; aoMudar(r: Responsavel): void }) {
  const funcionarios = useFuncionarios()
  const perfis = usePerfisEmpresa()
  return (
    <Selecao id={id} value={codificar(valor)} onChange={(e) => aoMudar(decodificar(e.target.value))}>
      <option value="">Ninguém (equipe)</option>
      {(perfis.data ?? []).filter((p) => p.ativo).length > 0 && (
        <optgroup label="Usuários do sistema">
          {(perfis.data ?? [])
            .filter((p) => p.ativo)
            .map((p) => (
              <option key={p.id} value={`p:${p.id}`}>
                {p.nome}
              </option>
            ))}
        </optgroup>
      )}
      <optgroup label="Funcionários">
        {(funcionarios.data ?? [])
          .filter((f) => f.ativo || f.id === valor.responsavel_funcionario_id)
          .map((f) => (
            <option key={f.id} value={`f:${f.id}`}>
              {f.nome}
              {f.cargo ? ` — ${f.cargo}` : ''}
            </option>
          ))}
      </optgroup>
    </Selecao>
  )
}

/** Nome do responsável para exibir. */
export function useNomeResponsavel() {
  const funcionarios = useFuncionarios()
  const perfis = usePerfisEmpresa()
  return useMemo(() => {
    const f = new Map((funcionarios.data ?? []).map((x) => [x.id, x.nome]))
    const p = new Map((perfis.data ?? []).map((x) => [x.id, x.nome]))
    return (r: Responsavel): string | null =>
      (r.responsavel_perfil_id && p.get(r.responsavel_perfil_id)) || (r.responsavel_funcionario_id && f.get(r.responsavel_funcionario_id)) || null
  }, [funcionarios.data, perfis.data])
}
