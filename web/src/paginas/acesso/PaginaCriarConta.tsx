/** /criar-conta — cadastro aberto (depois vai a /comecar criar o estabelecimento). Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import { Botao, Campo, Entrada } from '@/componentes/ui'
import { AlertaAcesso, EntradaSenha, IconeGoogle, LayoutAcesso, LINK_OURO, LINK_SECUNDARIO } from '@/componentes/acesso/LayoutAcesso'
import { configuracao } from '@/lib/configuracao'
import { useSessao } from '@/lib/sessao'
import { configuracaoAusente, mensagemDeErro, supabase } from '@/lib/supabase'

export function PaginaCriarConta() {
  const { sessao, carregando } = useSessao()
  const navegar = useNavigate()
  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [confirmar, setConfirmar] = useState(false)

  if (!carregando && sessao && !enviando) return <Navigate to="/" replace />

  async function criar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!nome.trim()) return setErro('Informe o nome')
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) return setErro('E-mail inválido')
    if (senha.length < 6) return setErro('A senha deve ter pelo menos 6 caracteres')
    setEnviando(true)
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password: senha,
      options: { data: { nome: nome.trim() }, emailRedirectTo: `${window.location.origin}/comecar` },
    })
    setEnviando(false)
    if (error) return setErro(mensagemDeErro(error))
    if (data.session) navegar('/comecar', { replace: true })
    else setConfirmar(true)
  }

  return (
    <LayoutAcesso
      titulo="Comece hoje."
      italico="Leve só alguns minutos."
      subtitulo="Crie sua conta e cadastre seu estabelecimento em seguida."
      rodape={
        <>
          <span className="text-lavanda">Já tem conta?</span>
          <Link to="/entrar" className={LINK_OURO}>
            Entrar
          </Link>
        </>
      }
    >
      {erro && <AlertaAcesso>{erro}</AlertaAcesso>}
      {confirmar ? (
        <AlertaAcesso tom="sucesso">
          Conta criada! Enviamos um link de confirmação para <strong>{email.trim()}</strong>. Abra o e-mail para ativar e continuar.
        </AlertaAcesso>
      ) : (
        <form onSubmit={criar} noValidate className="flex flex-col gap-5">
          <Campo rotulo="Seu nome" htmlFor="nome">
            <Entrada id="nome" autoComplete="name" placeholder="Como quer ser chamado" value={nome} onChange={(e) => setNome(e.target.value)} />
          </Campo>
          <Campo rotulo="E-mail" htmlFor="email">
            <Entrada
              id="email"
              type="email"
              autoComplete="email"
              inputMode="email"
              placeholder="voce@seubar.com.br"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </Campo>
          <Campo rotulo="Senha" htmlFor="senha" ajuda="Pelo menos 6 caracteres.">
            <EntradaSenha id="senha" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
          </Campo>
          <div className="mt-1 flex flex-col gap-3">
            <Botao type="submit" tamanho="g" className="w-full" carregando={enviando} disabled={configuracaoAusente}>
              Criar conta
            </Botao>
            {configuracao.loginGoogle && (
              <Botao
                variante="secundario"
                tamanho="g"
                className="w-full"
                icone={<IconeGoogle />}
                disabled={configuracaoAusente || enviando}
                onClick={async () => {
                  const { error } = await supabase.auth.signInWithOAuth({
                    provider: 'google',
                    options: { redirectTo: `${window.location.origin}/` },
                  })
                  if (error) setErro(mensagemDeErro(error))
                }}
              >
                Continuar com Google
              </Botao>
            )}
          </div>
          <p className="text-center text-xs text-lavanda-escuro">
            Esqueceu a senha de uma conta antiga?{' '}
            <Link to="/recuperar-senha" className={LINK_SECUNDARIO}>
              Recuperar senha
            </Link>
          </p>
        </form>
      )}
    </LayoutAcesso>
  )
}
