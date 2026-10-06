/**
 * Lista + CRUD de usuários de uma empresa (usado em /usuarios e no detalhe de empresa do master). Dono: frontend-1.
 */
import { useState, type FormEvent } from 'react'
import { KeyRound, Pencil, Plus, Trash2, UserPlus } from 'lucide-react'
import type { Papel, Perfil } from '@/tipos/banco'
import { Botao, Campo, Entrada, ErroCarga, Interruptor, Modal, Selecao, Selo, Tabela, Vazio, type Coluna } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useAtualizarUsuario, useCriarUsuario, useExcluirUsuario, useFuncionariosParaVinculo, useRedefinirSenha, useUsuarios } from '@/consultas/usuarios'
import { rotuloPapel } from '@/lib/rotulos'
import { usePerfil } from '@/lib/sessao'

const PAPEIS: Exclude<Papel, 'master'>[] = ['administrador', 'gerente', 'leitura']

const DESCRICAO_PAPEL: Record<Exclude<Papel, 'master'>, string> = {
  administrador: 'Tudo da empresa: usuários, integrações, configurações e fechar comissão.',
  gerente: 'Operação do dia: ponto, banco de horas, tarefas, sincronizar e comissões em rascunho.',
  leitura: 'Só consulta. Pode concluir as tarefas atribuídas a ele.',
}

type Edicao = { modo: 'novo' } | { modo: 'editar'; u: Perfil } | { modo: 'senha'; u: Perfil } | null

export function UsuariosDaEmpresa({ empresaId }: { empresaId: string }) {
  const eu = usePerfil()
  const usuarios = useUsuarios(empresaId)
  const funcionarios = useFuncionariosParaVinculo(empresaId)
  const excluir = useExcluirUsuario()
  const avisos = useAvisos()
  const [edicao, setEdicao] = useState<Edicao>(null)

  const nomeFuncionario = (id: string | null) => (id ? (funcionarios.data?.find((f) => f.id === id)?.nome ?? 'Funcionário') : null)

  async function apagar(u: Perfil) {
    const ok = await avisos.confirmar({
      titulo: `Excluir ${u.nome}?`,
      mensagem: `${u.email} perde o acesso imediatamente. Esta ação não pode ser desfeita.`,
      textoConfirmar: 'Excluir usuário',
      perigo: true,
    })
    if (ok) excluir.mutate(u.id, { onSuccess: () => avisos.sucesso('Usuário excluído.'), onError: avisos.erro })
  }

  const colunas: Coluna<Perfil>[] = [
    {
      id: 'nome',
      titulo: 'Usuário',
      render: (u) => (
        <span className="flex min-w-0 flex-col">
          <span className="font-semibold text-creme">
            {u.nome}
            {u.id === eu.id && <span className="ml-2 text-xs font-normal text-lavanda">(você)</span>}
          </span>
          <span className="truncate text-xs text-lavanda">{u.email}</span>
        </span>
      ),
    },
    { id: 'papel', titulo: 'Papel', render: (u) => <Selo tom={u.papel === 'administrador' ? 'ouro' : 'neutro'}>{rotuloPapel[u.papel]}</Selo> },
    { id: 'func', titulo: 'Funcionário', ocultarNoCelular: true, render: (u) => <span className="text-sm text-lavanda">{nomeFuncionario(u.funcionario_id) ?? '—'}</span> },
    { id: 'situacao', titulo: 'Situação', render: (u) => (u.ativo ? <Selo tom="sucesso">Ativo</Selo> : <Selo tom="perigo">Desativado</Selo>) },
    {
      id: 'acoes',
      titulo: <span className="sr-only">Ações</span>,
      alinhar: 'direita',
      render: (u) =>
        u.papel === 'master' ? null : (
          <span className="inline-flex gap-1">
            <Botao variante="fantasma" tamanho="p" aria-label={`Editar ${u.nome}`} title="Editar" icone={<Pencil aria-hidden />} onClick={() => setEdicao({ modo: 'editar', u })} />
            <Botao variante="fantasma" tamanho="p" aria-label={`Redefinir senha de ${u.nome}`} title="Redefinir senha" icone={<KeyRound aria-hidden />} onClick={() => setEdicao({ modo: 'senha', u })} />
            {u.id !== eu.id && (
              <Botao variante="fantasma" tamanho="p" aria-label={`Excluir ${u.nome}`} title="Excluir" icone={<Trash2 aria-hidden />} onClick={() => void apagar(u)} />
            )}
          </span>
        ),
    },
  ]

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Botao icone={<Plus aria-hidden />} onClick={() => setEdicao({ modo: 'novo' })}>
          Novo usuário
        </Botao>
      </div>
      {usuarios.isError ? (
        <ErroCarga erro={usuarios.error} aoTentar={() => void usuarios.refetch()} />
      ) : (
        <Tabela
          colunas={colunas}
          linhas={usuarios.data ?? []}
          chave={(u) => u.id}
          carregando={usuarios.isPending}
          vazio={<Vazio icone={<UserPlus aria-hidden />} titulo="Nenhum usuário" descricao="Convide a equipe para acompanhar o dia." />}
        />
      )}

      <Modal
        aberto={edicao?.modo === 'novo' || edicao?.modo === 'editar'}
        aoFechar={() => setEdicao(null)}
        titulo={edicao?.modo === 'editar' ? `Editar ${edicao.u.nome}` : 'Novo usuário'}
      >
        {(edicao?.modo === 'novo' || edicao?.modo === 'editar') && (
          <FormularioUsuario
            key={edicao.modo === 'editar' ? edicao.u.id : 'novo'}
            empresaId={empresaId}
            usuario={edicao.modo === 'editar' ? edicao.u : null}
            proprio={edicao.modo === 'editar' && edicao.u.id === eu.id}
            funcionarios={funcionarios.data ?? []}
            aoConcluir={() => setEdicao(null)}
          />
        )}
      </Modal>
      <Modal aberto={edicao?.modo === 'senha'} aoFechar={() => setEdicao(null)} titulo="Redefinir senha" largura="p">
        {edicao?.modo === 'senha' && <FormularioSenha usuario={edicao.u} aoConcluir={() => setEdicao(null)} />}
      </Modal>
    </div>
  )
}

function FormularioUsuario({
  empresaId,
  usuario,
  proprio,
  funcionarios,
  aoConcluir,
}: {
  empresaId: string
  usuario: Perfil | null
  proprio: boolean
  funcionarios: { id: string; nome: string; cargo: string | null }[]
  aoConcluir(): void
}) {
  const avisos = useAvisos()
  const criar = useCriarUsuario()
  const atualizar = useAtualizarUsuario()
  const [nome, setNome] = useState(usuario?.nome ?? '')
  const [email, setEmail] = useState(usuario?.email ?? '')
  const [senha, setSenha] = useState('')
  const [papel, setPapel] = useState<Papel>(usuario?.papel ?? 'gerente')
  const [ativo, setAtivo] = useState(usuario?.ativo ?? true)
  const [funcionarioId, setFuncionarioId] = useState<string>(usuario?.funcionario_id ?? '')
  const [erro, setErro] = useState<string | null>(null)

  function enviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!nome.trim()) return setErro('Informe o nome')
    const opcoes = {
      onSuccess: () => {
        avisos.sucesso(usuario ? 'Usuário atualizado.' : 'Usuário criado. Passe a senha para ele entrar.')
        aoConcluir()
      },
      onError: avisos.erro,
    }
    if (usuario) {
      atualizar.mutate({ id: usuario.id, nome: nome.trim(), papel, ativo, funcionarioId: funcionarioId || null }, opcoes)
    } else {
      if (!/^\S+@\S+\.\S+$/.test(email.trim())) return setErro('E-mail inválido')
      if (senha.length < 6) return setErro('A senha deve ter pelo menos 6 caracteres')
      criar.mutate({ email: email.trim(), senha, nome: nome.trim(), papel, empresaId, funcionarioId: funcionarioId || null }, opcoes)
    }
  }

  return (
    <form onSubmit={enviar} noValidate className="flex flex-col gap-5">
      {erro && (
        <p role="alert" className="rounded-entrada border border-perigo/40 bg-perigo/10 px-4 py-3 text-sm text-creme">
          {erro}
        </p>
      )}
      <Campo rotulo="Nome" htmlFor="u-nome" obrigatorio>
        <Entrada id="u-nome" value={nome} onChange={(e) => setNome(e.target.value)} />
      </Campo>
      <Campo rotulo="E-mail" htmlFor="u-email" obrigatorio={!usuario}>
        <Entrada id="u-email" type="email" autoComplete="off" value={email} onChange={(e) => setEmail(e.target.value)} disabled={!!usuario} />
      </Campo>
      {!usuario && (
        <Campo rotulo="Senha inicial" htmlFor="u-senha" obrigatorio ajuda="Pelo menos 6 caracteres. A pessoa pode trocar depois em “Recuperar senha”.">
          <Entrada id="u-senha" type="text" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
        </Campo>
      )}
      <Campo rotulo="Papel" htmlFor="u-papel" ajuda={papel !== 'master' ? DESCRICAO_PAPEL[papel] : undefined}>
        <Selecao id="u-papel" value={papel} onChange={(e) => setPapel(e.target.value as Papel)} disabled={proprio}>
          {PAPEIS.map((p) => (
            <option key={p} value={p}>
              {rotuloPapel[p]}
            </option>
          ))}
        </Selecao>
      </Campo>
      <Campo rotulo="Funcionário vinculado" htmlFor="u-func" ajuda="Opcional. Liga o usuário às tarefas atribuídas a esse funcionário.">
        <Selecao id="u-func" value={funcionarioId} onChange={(e) => setFuncionarioId(e.target.value)}>
          <option value="">Nenhum</option>
          {funcionarios.map((f) => (
            <option key={f.id} value={f.id}>
              {f.nome}
              {f.cargo ? ` · ${f.cargo}` : ''}
            </option>
          ))}
        </Selecao>
      </Campo>
      {usuario && !proprio && <Interruptor rotulo="Acesso ativo" marcado={ativo} aoMudar={setAtivo} />}
      {proprio && <p className="text-xs text-lavanda">Você não pode alterar o próprio papel ou situação.</p>}
      <div className="flex justify-end gap-2 border-t border-borda pt-5">
        <Botao variante="secundario" onClick={aoConcluir}>
          Cancelar
        </Botao>
        <Botao type="submit" carregando={criar.isPending || atualizar.isPending}>
          {usuario ? 'Salvar' : 'Criar usuário'}
        </Botao>
      </div>
    </form>
  )
}

function FormularioSenha({ usuario, aoConcluir }: { usuario: Perfil; aoConcluir(): void }) {
  const redefinir = useRedefinirSenha()
  const avisos = useAvisos()
  const [senha, setSenha] = useState('')
  return (
    <form
      noValidate
      className="flex flex-col gap-5"
      onSubmit={(e) => {
        e.preventDefault()
        if (senha.length < 6) return avisos.erro('A senha deve ter pelo menos 6 caracteres')
        redefinir.mutate(
          { id: usuario.id, senha },
          {
            onSuccess: () => {
              avisos.sucesso(`Senha de ${usuario.nome} redefinida.`)
              aoConcluir()
            },
            onError: avisos.erro,
          },
        )
      }}
    >
      <p className="text-sm text-lavanda">
        Nova senha para <strong className="text-creme">{usuario.email}</strong>.
      </p>
      <Campo rotulo="Nova senha" htmlFor="u-nova-senha">
        <Entrada id="u-nova-senha" type="text" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
      </Campo>
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoConcluir}>
          Cancelar
        </Botao>
        <Botao type="submit" carregando={redefinir.isPending}>
          Redefinir
        </Botao>
      </div>
    </form>
  )
}
