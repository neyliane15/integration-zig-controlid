/** /entrar — tela de login (identidade visual de referência do cliente). Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import { Link, Navigate, useLocation } from 'react-router-dom'
import { Botao, Caixa, Campo, Entrada } from '@/componentes/ui'
import { AlertaAcesso, EntradaSenha, IconeGoogle, LayoutAcesso, LINK_OURO, LINK_SECUNDARIO } from '@/componentes/acesso/LayoutAcesso'
import { CHAVES_LOCAIS, configuracao, gravarLocal, lerLocal } from '@/lib/configuracao'
import { useSessao } from '@/lib/sessao'
import { configuracaoAusente, mensagemDeErro, supabase } from '@/lib/supabase'

export function PaginaEntrar() {
  const { sessao, carregando } = useSessao()
  const local = useLocation()
  const destino = (local.state as { de?: string } | null)?.de ?? '/'

  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [lembrar, setLembrar] = useState(() => lerLocal(CHAVES_LOCAIS.lembrar) !== '0')
  const [enviando, setEnviando] = useState<'senha' | 'google' | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  if (!carregando && sessao) return <Navigate to={destino} replace />

  async function entrar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!email.trim() || !senha) {
      setErro('Informe e-mail e senha.')
      return
    }
    gravarLocal(CHAVES_LOCAIS.lembrar, lembrar ? '1' : '0')
    setEnviando('senha')
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha })
    setEnviando(null)
    if (error) setErro(mensagemDeErro(error))
  }

  async function entrarComGoogle() {
    setErro(null)
    gravarLocal(CHAVES_LOCAIS.lembrar, lembrar ? '1' : '0')
    setEnviando('google')
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: `${window.location.origin}/` },
    })
    if (error) {
      setEnviando(null)
      setErro(mensagemDeErro(error))
    }
  }

  return (
    <LayoutAcesso
      titulo="Organize seu dia."
      italico="Não esqueça nada."
      subtitulo="Seu assistente diário de rotina na loja."
      rodape={
        <>
          <Link to="/recuperar-senha" className={LINK_SECUNDARIO}>
            Recuperar senha
          </Link>
          <Link to="/criar-conta" className={LINK_OURO}>
            Criar conta
          </Link>
        </>
      }
    >
      {configuracaoAusente && (
        <AlertaAcesso tom="info">
          Configure <code className="numero text-xs">VITE_SUPABASE_URL</code> e{' '}
          <code className="numero text-xs">VITE_SUPABASE_ANON_KEY</code> no arquivo <code className="numero text-xs">.env</code> para entrar.
        </AlertaAcesso>
      )}
      {erro && <AlertaAcesso>{erro}</AlertaAcesso>}

      <form onSubmit={entrar} noValidate className="flex flex-col gap-5">
        <Campo rotulo="E-mail" htmlFor="email">
          <Entrada
            id="email"
            type="email"
            autoComplete="email"
            inputMode="email"
            placeholder="voce@seubar.com.br"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            invalido={!!erro && !email.trim()}
            required
          />
        </Campo>
        <Campo rotulo="Senha" htmlFor="senha">
          <EntradaSenha
            id="senha"
            autoComplete="current-password"
            placeholder="Sua senha"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            invalido={!!erro && !senha}
            required
          />
        </Campo>

        <div className="-mt-0.5">
          <Caixa rotulo="Manter-me conectado" marcado={lembrar} aoMudar={setLembrar} />
        </div>

        <div className="mt-1 flex flex-col gap-3">
          <Botao type="submit" tamanho="g" className="w-full" carregando={enviando === 'senha'} disabled={configuracaoAusente || enviando != null}>
            Entrar
          </Botao>
          {configuracao.loginGoogle && (
            <Botao
              variante="secundario"
              tamanho="g"
              className="w-full"
              onClick={entrarComGoogle}
              carregando={enviando === 'google'}
              disabled={configuracaoAusente || enviando != null}
              icone={<IconeGoogle />}
            >
              Entrar com Google
            </Botao>
          )}
        </div>
      </form>
    </LayoutAcesso>
  )
}
