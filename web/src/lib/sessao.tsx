/**
 * Sessão, perfil e empresa atual (contrato §14.2 e §14.6). Dono: frontend-1.
 *
 * - `useSessao()`: { carregando, sessao, perfil, empresa (a do próprio perfil), sair(), recarregar() }
 * - `usePerfil()`: perfil garantido (use só dentro de rota protegida)
 * - `useEmpresaAtual()`: empresa em que a tela opera. Para L/G/A é a do perfil; para o master é a escolhida no
 *   seletor da casca (lembrada em localStorage `mdg:empresa`; na falta, a primeira em ordem alfabética).
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { Empresa, Perfil } from '@/tipos/banco'
import { CHAVES_LOCAIS, gravarLocal, lerLocal } from './configuracao'
import { configuracaoAusente, exigir, supabase } from './supabase'

interface ValorSessao {
  carregando: boolean
  sessao: Session | null
  perfil: Perfil | null
  empresa: Empresa | null
  sair(): Promise<void>
  /** Relê perfil e empresa (ex.: depois de `criar_minha_empresa`). */
  recarregar(): Promise<void>
  /** Erro ao ler o perfil (rede/RLS), para a casca explicar. */
  erroPerfil: unknown
}

interface ValorEmpresaAtual {
  empresaId: string | null
  empresa: Empresa | null
  definirEmpresa(id: string | null): void
}

const ContextoSessao = createContext<ValorSessao | null>(null)
const ContextoEmpresa = createContext<ValorEmpresaAtual | null>(null)

async function lerPerfil(id: string): Promise<Perfil | null> {
  return exigir(await supabase.from('perfis').select('*').eq('id', id).maybeSingle<Perfil>())
}

async function lerEmpresa(id: string): Promise<Empresa | null> {
  return exigir(await supabase.from('empresas').select('*').eq('id', id).maybeSingle<Empresa>())
}

export function ProvedorDeSessao({ children }: { children: ReactNode }) {
  const qc = useQueryClient()
  const [sessao, setSessao] = useState<Session | null>(null)
  const [carregandoAuth, setCarregandoAuth] = useState(!configuracaoAusente)

  useEffect(() => {
    if (configuracaoAusente) return
    let vivo = true
    supabase.auth
      .getSession()
      .then(({ data }) => {
        if (vivo) setSessao(data.session)
      })
      .finally(() => vivo && setCarregandoAuth(false))
    const { data } = supabase.auth.onAuthStateChange((_evento, s) => {
      // não chamar o supabase aqui dentro (trava o cliente); só guardar o estado
      setSessao(s)
      setCarregandoAuth(false)
    })
    return () => {
      vivo = false
      data.subscription.unsubscribe()
    }
  }, [])

  const usuarioId = sessao?.user.id ?? null

  const consultaPerfil = useQuery({
    queryKey: ['perfil', usuarioId],
    queryFn: () => lerPerfil(usuarioId!),
    enabled: usuarioId != null,
    staleTime: 60_000,
  })
  const perfil = usuarioId ? (consultaPerfil.data ?? null) : null

  const empresaPropriaId = perfil?.empresa_id ?? null
  const consultaEmpresa = useQuery({
    queryKey: ['empresa', empresaPropriaId],
    queryFn: () => lerEmpresa(empresaPropriaId!),
    enabled: empresaPropriaId != null,
    staleTime: 60_000,
  })
  const empresa = empresaPropriaId ? (consultaEmpresa.data ?? null) : null

  // ------------------------------------------------ empresa atual (master escolhe)
  const ehMaster = perfil?.papel === 'master'
  const [escolhida, setEscolhida] = useState<string | null>(() => lerLocal(CHAVES_LOCAIS.empresaMaster))

  const definirEmpresa = useCallback((id: string | null) => {
    setEscolhida(id)
    gravarLocal(CHAVES_LOCAIS.empresaMaster, id)
  }, [])

  const consultaPrimeira = useQuery({
    queryKey: ['empresa-padrao-master', usuarioId],
    queryFn: async () => {
      const linhas = exigir(await supabase.from('empresas').select('id').order('nome').limit(1))
      return (linhas as { id: string }[])[0]?.id ?? null
    },
    enabled: ehMaster && !escolhida,
  })
  useEffect(() => {
    if (ehMaster && !escolhida && consultaPrimeira.data) definirEmpresa(consultaPrimeira.data)
  }, [ehMaster, escolhida, consultaPrimeira.data, definirEmpresa])

  const empresaAtualId = ehMaster ? escolhida : empresaPropriaId
  const consultaEmpresaAtual = useQuery({
    queryKey: ['empresa', empresaAtualId],
    queryFn: () => lerEmpresa(empresaAtualId!),
    enabled: ehMaster && empresaAtualId != null,
    staleTime: 60_000,
  })
  useEffect(() => {
    // empresa lembrada foi excluída: esquece e deixa escolher a primeira
    if (ehMaster && escolhida && consultaEmpresaAtual.isSuccess && consultaEmpresaAtual.data == null) definirEmpresa(null)
  }, [ehMaster, escolhida, consultaEmpresaAtual.isSuccess, consultaEmpresaAtual.data, definirEmpresa])

  const sair = useCallback(async () => {
    try {
      await supabase.auth.signOut()
    } finally {
      setSessao(null)
      qc.clear()
    }
  }, [qc])

  const recarregar = useCallback(async () => {
    await Promise.all([
      qc.invalidateQueries({ queryKey: ['perfil'] }),
      qc.invalidateQueries({ queryKey: ['empresa'] }),
    ])
  }, [qc])

  const carregando =
    carregandoAuth ||
    (usuarioId != null && consultaPerfil.isPending) ||
    (empresaPropriaId != null && consultaEmpresa.isPending)

  const valorSessao = useMemo<ValorSessao>(
    () => ({ carregando, sessao, perfil, empresa, sair, recarregar, erroPerfil: consultaPerfil.error }),
    [carregando, sessao, perfil, empresa, sair, recarregar, consultaPerfil.error],
  )

  const valorEmpresa = useMemo<ValorEmpresaAtual>(
    () => ({
      empresaId: empresaAtualId,
      empresa: ehMaster ? (consultaEmpresaAtual.data ?? null) : empresa,
      definirEmpresa,
    }),
    [empresaAtualId, ehMaster, consultaEmpresaAtual.data, empresa, definirEmpresa],
  )

  return (
    <ContextoSessao.Provider value={valorSessao}>
      <ContextoEmpresa.Provider value={valorEmpresa}>{children}</ContextoEmpresa.Provider>
    </ContextoSessao.Provider>
  )
}

export function useSessao(): ValorSessao {
  const c = useContext(ContextoSessao)
  if (!c) throw new Error('useSessao fora de <ProvedorDeSessao>')
  return c
}

/** Perfil do usuário logado. Lança se não houver (só use dentro de rota protegida). */
export function usePerfil(): Perfil {
  const { perfil } = useSessao()
  if (!perfil) throw new Error('usePerfil sem perfil carregado (use dentro de rota protegida)')
  return perfil
}

export function useEmpresaAtual(): ValorEmpresaAtual {
  const c = useContext(ContextoEmpresa)
  if (!c) throw new Error('useEmpresaAtual fora de <ProvedorDeSessao>')
  return c
}
