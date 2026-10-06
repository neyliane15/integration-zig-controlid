/**
 * Regras de papel no front (contrato §3). Dono: frontend-1.
 * Só controlam o que aparece na tela — quem decide de verdade é a RLS/RPC no banco.
 */
import type { Papel } from '@/tipos/banco'

/** Master. */
export function ehMaster(p: Papel): boolean {
  return p === 'master'
}

/** Gerente, administrador ou master: operação do dia (ponto, tarefas, sincronizar, comissão em rascunho). */
export function podeOperar(p: Papel): boolean {
  return p === 'gerente' || p === 'administrador' || p === 'master'
}

/** Administrador ou master: usuários, integrações (inclusive segredos), configurações, fechar comissão. */
export function podeAdministrar(p: Papel): boolean {
  return p === 'administrador' || p === 'master'
}

/** Comissões: gerente, administrador, master (leitura não vê). */
export function podeVerComissoes(p: Papel): boolean {
  return podeOperar(p)
}

/** Integrações (status/histórico): gerente, administrador, master. */
export function podeVerIntegracoes(p: Papel): boolean {
  return podeOperar(p)
}
