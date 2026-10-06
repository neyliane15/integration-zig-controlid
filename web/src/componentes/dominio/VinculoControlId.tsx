/**
 * Vínculo entre usuários dos equipamentos Control iD (`controlid_usuarios`) e funcionários (contrato §14.5).
 * Dono: frontend-2. Usado na ficha do funcionário (`funcionarioId`) e na página da integração do f1 (`integracaoId`).
 */
import { useId, useMemo } from 'react'
import { Link2, Unlink } from 'lucide-react'
import type { ControlIdUsuario } from '@/tipos/banco'
import { Carregando, ErroCarga, Selecao, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useControlIdUsuarios, useEquipamentosControlId, useFuncionarios, useVincularControlId } from '@/consultas/funcionarios'
import { usePerfil } from '@/lib/sessao'
import { podeOperar } from '@/lib/permissoes'
import { rotuloTipoIntegracao, rotuloVinculoControlId } from '@/lib/rotulos'
import { normalizar } from '@/lib/formato'

function descreverUsuario(u: ControlIdUsuario): string {
  const partes = [u.nome?.trim() || '(sem nome)']
  if (u.registration) partes.push(`matrícula ${u.registration}`)
  else partes.push(`id ${u.user_id_externo}`)
  return partes.join(' · ')
}

export function VinculoControlId({ integracaoId, funcionarioId }: { integracaoId?: string; funcionarioId?: string }) {
  if (funcionarioId) return <VinculosDoFuncionario funcionarioId={funcionarioId} />
  if (integracaoId) return <UsuariosDoEquipamento integracaoId={integracaoId} />
  return null
}

// --------------------------------------------------------- por funcionário
function VinculosDoFuncionario({ funcionarioId }: { funcionarioId: string }) {
  const perfil = usePerfil()
  const editavel = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const equipamentos = useEquipamentosControlId()
  const usuarios = useControlIdUsuarios()
  const vincular = useVincularControlId()
  const idBase = useId()

  if (equipamentos.isLoading || usuarios.isLoading) return <Carregando texto="Carregando equipamentos…" />
  if (equipamentos.error) return <ErroCarga erro={equipamentos.error} aoTentar={() => equipamentos.refetch()} />
  if (usuarios.error) return <ErroCarga erro={usuarios.error} aoTentar={() => usuarios.refetch()} />
  const lista = equipamentos.data ?? []
  if (lista.length === 0)
    return <Vazio titulo="Nenhum equipamento Control iD" descricao="Cadastre o relógio ou leitor facial em Integrações para vincular." />

  const alterar = async (atual: ControlIdUsuario | undefined, novoId: string) => {
    try {
      if (novoId) await vincular.mutateAsync({ controlidUsuarioId: novoId, funcionarioId })
      else if (atual) await vincular.mutateAsync({ controlidUsuarioId: atual.id, funcionarioId: null })
      avisos.sucesso(novoId ? 'Vínculo salvo' : 'Vínculo removido')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <ul className="flex flex-col gap-3">
      {lista.map((eq) => {
        const doEquipamento = (usuarios.data ?? []).filter((u) => u.integracao_id === eq.id)
        const atual = doEquipamento.find((u) => u.funcionario_id === funcionarioId)
        const opcoes = doEquipamento
          .filter((u) => (!u.funcionario_id || u.funcionario_id === funcionarioId) && !u.removido_no_equipamento)
          .sort((a, b) => (a.nome ?? '').localeCompare(b.nome ?? '', 'pt-BR'))
        const id = `${idBase}-${eq.id}`
        return (
          <li key={eq.id} className="rounded-entrada border border-borda bg-entrada/60 p-4">
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <div className="min-w-0">
                <label htmlFor={id} className="font-semibold text-creme">
                  {eq.nome}
                </label>
                <p className="text-xs text-lavanda">{rotuloTipoIntegracao[eq.tipo]}</p>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {atual ? (
                  <Selo tom="sucesso">
                    <Link2 aria-hidden />
                    {atual.vinculo ? rotuloVinculoControlId[atual.vinculo] : 'Vinculado'}
                  </Selo>
                ) : (
                  <Selo tom="alerta">
                    <Unlink aria-hidden />
                    Sem vínculo
                  </Selo>
                )}
                {atual?.removido_no_equipamento && <Selo tom="perigo">Removido no equipamento</Selo>}
                {!eq.ativa && <Selo>Integração inativa</Selo>}
              </div>
            </div>
            {editavel ? (
              <Selecao id={id} value={atual?.id ?? ''} disabled={vincular.isPending} onChange={(e) => alterar(atual, e.target.value)}>
                <option value="">{doEquipamento.length ? '— sem vínculo —' : 'Nenhum usuário importado deste equipamento'}</option>
                {atual?.removido_no_equipamento && <option value={atual.id}>{descreverUsuario(atual)}</option>}
                {opcoes.map((u) => (
                  <option key={u.id} value={u.id}>
                    {descreverUsuario(u)}
                  </option>
                ))}
              </Selecao>
            ) : (
              <p id={id} className="text-sm text-creme">
                {atual ? descreverUsuario(atual) : '—'}
              </p>
            )}
          </li>
        )
      })}
    </ul>
  )
}

// --------------------------------------------------------- por equipamento
function UsuariosDoEquipamento({ integracaoId }: { integracaoId: string }) {
  const perfil = usePerfil()
  const editavel = podeOperar(perfil.papel)
  const avisos = useAvisos()
  const usuarios = useControlIdUsuarios()
  const funcionarios = useFuncionarios()
  const vincular = useVincularControlId()

  const linhas = useMemo(
    () =>
      (usuarios.data ?? [])
        .filter((u) => u.integracao_id === integracaoId)
        .sort((a, b) => Number(!!a.funcionario_id) - Number(!!b.funcionario_id) || normalizar(a.nome ?? '').localeCompare(normalizar(b.nome ?? ''))),
    [usuarios.data, integracaoId],
  )
  const nomes = useMemo(() => new Map((funcionarios.data ?? []).map((f) => [f.id, f.nome])), [funcionarios.data])

  if (usuarios.error) return <ErroCarga erro={usuarios.error} aoTentar={() => usuarios.refetch()} />

  const colunas: Coluna<ControlIdUsuario>[] = [
    {
      id: 'usuario',
      titulo: 'Usuário no equipamento',
      render: (u) => (
        <div className="min-w-0">
          <p className="font-semibold text-creme">{u.nome?.trim() || '(sem nome)'}</p>
          <p className="numero text-xs text-lavanda">
            id {u.user_id_externo}
            {u.registration ? ` · matrícula ${u.registration}` : ''}
          </p>
        </div>
      ),
    },
    {
      id: 'situacao',
      titulo: 'Situação',
      render: (u) => (
        <div className="flex flex-wrap gap-1">
          {u.funcionario_id ? (
            <Selo tom="sucesso">{u.vinculo ? rotuloVinculoControlId[u.vinculo] : 'Vinculado'}</Selo>
          ) : (
            <Selo tom="alerta">Sem vínculo</Selo>
          )}
          {u.removido_no_equipamento && <Selo tom="perigo">Removido</Selo>}
        </div>
      ),
    },
    {
      id: 'funcionario',
      titulo: 'Funcionário',
      render: (u) =>
        editavel ? (
          <div onClick={(e) => e.stopPropagation()} className="min-w-48">
            <Selecao
              aria-label={`Funcionário vinculado a ${u.nome ?? u.user_id_externo}`}
              value={u.funcionario_id ?? ''}
              disabled={vincular.isPending}
              onChange={async (e) => {
                try {
                  await vincular.mutateAsync({ controlidUsuarioId: u.id, funcionarioId: e.target.value || null })
                  avisos.sucesso(e.target.value ? 'Vínculo salvo' : 'Vínculo removido')
                } catch (erro) {
                  avisos.erro(erro)
                }
              }}
            >
              <option value="">— sem vínculo —</option>
              {(funcionarios.data ?? [])
                .filter((f) => f.ativo || f.id === u.funcionario_id)
                .map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.nome}
                  </option>
                ))}
            </Selecao>
          </div>
        ) : (
          <span>{u.funcionario_id ? (nomes.get(u.funcionario_id) ?? '—') : '—'}</span>
        ),
    },
  ]

  return (
    <div className="flex flex-col gap-3">
      <Tabela
        colunas={colunas}
        linhas={linhas}
        chave={(u) => u.id}
        carregando={usuarios.isLoading}
        vazio={
          <Vazio
            titulo="Nenhum usuário importado"
            descricao="Use “Sincronizar agora” para importar os usuários cadastrados no equipamento."
          />
        }
      />
      {editavel && linhas.some((u) => !u.funcionario_id && !u.removido_no_equipamento) && (
        <p className="text-xs text-lavanda">
          Dica: o vínculo automático usa a matrícula (registration), o CPF ou o PIS. Os que sobraram você liga aqui.
        </p>
      )}
      {!editavel && <p className="text-xs text-lavanda">Somente leitura.</p>}
    </div>
  )
}
