/**
 * Envio do cadastro ao Control iD (adendo): credenciais (foto, cartões, senha) e estado do envio por equipamento.
 * Dono: frontend-2.
 */
import { useId, useState } from 'react'
import { Link } from 'react-router-dom'
import { CreditCard, KeyRound, RefreshCw, Send, Trash2 } from 'lucide-react'
import type { ControlIdEnvio } from '@/tipos/banco'
import { Botao, Campo, Carregando, Entrada, ErroCarga, Modal, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import {
  envioAtivo,
  useAdicionarCartao,
  useCredenciais,
  useDefinirSenhaAcesso,
  useEnviarControlIdAgora,
  useEnviosFuncionario,
  useEquipamentosControlId,
  useRemoverCartao,
  type EquipamentoControlId,
} from '@/consultas/funcionarios'
import { formatarDataHora, formatarRelativo } from '@/lib/formato'
import { rotuloOperacaoEnvio, rotuloTipoIntegracao } from '@/lib/rotulos'
import { FotoFacial } from './FotoFacial'
import { SeloStatusEnvio } from './Selos'

/** Cartão Wiegand (área + código) → número decimal lido pelo equipamento: área × 2^32 + código. */
export function numeroWiegand(area: string, codigo: string): string | null {
  if (!/^\d+$/.test(area.trim()) || !/^\d+$/.test(codigo.trim())) return null
  return (BigInt(area.trim()) * 4294967296n + BigInt(codigo.trim())).toString()
}

// ------------------------------------------------------------ credenciais
export function CredenciaisControlId({ funcionarioId, nome, editavel }: { funcionarioId: string; nome: string; editavel: boolean }) {
  const avisos = useAvisos()
  const cred = useCredenciais(funcionarioId)
  const adicionar = useAdicionarCartao()
  const removerCartao = useRemoverCartao()
  const senha = useDefinirSenhaAcesso()
  const [numero, setNumero] = useState('')
  const [wiegand, setWiegand] = useState<{ area: string; codigo: string } | null>(null)
  const [modalSenha, setModalSenha] = useState(false)
  const [novaSenha, setNovaSenha] = useState('')
  const idCartao = useId()
  const idSenha = useId()

  if (cred.isLoading) return <Carregando texto="Carregando credenciais…" />
  if (cred.error) return <ErroCarga erro={cred.error} aoTentar={() => cred.refetch()} />
  const c = cred.data ?? { senha_definida: false, cartoes: [], foto: null }

  const incluirCartao = async () => {
    const n = numero.replace(/\D/g, '')
    if (!n) return avisos.erro('Número de cartão inválido')
    try {
      await adicionar.mutateAsync({ funcionarioId, numero: n })
      setNumero('')
      avisos.sucesso('Cartão cadastrado')
    } catch (e) {
      avisos.erro(e)
    }
  }

  const salvarSenha = async (valor: string | null) => {
    if (valor != null && !/^\d{4,8}$/.test(valor)) return avisos.erro('Senha de acesso inválida')
    try {
      await senha.mutateAsync({ funcionarioId, senha: valor })
      setModalSenha(false)
      setNovaSenha('')
      avisos.sucesso(valor ? 'Senha de acesso definida' : 'Senha de acesso removida')
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby={`${idCartao}-foto`}>
        <h3 id={`${idCartao}-foto`} className="mb-3 font-display text-lg text-creme">
          Foto facial
        </h3>
        <FotoFacial funcionarioId={funcionarioId} caminho={c.foto?.caminho ?? null} editavel={editavel} nome={nome} />
      </section>

      <section aria-labelledby={`${idCartao}-titulo`}>
        <h3 id={`${idCartao}-titulo`} className="mb-3 flex items-center gap-2 font-display text-lg text-creme">
          <CreditCard aria-hidden className="size-5 text-ouro" /> Cartões / crachás
        </h3>
        {c.cartoes.length === 0 ? (
          <p className="mb-3 text-sm text-lavanda">Nenhum cartão cadastrado.</p>
        ) : (
          <ul className="mb-3 flex flex-col gap-2">
            {c.cartoes.map((k) => (
              <li key={k.id} className="flex items-center justify-between gap-3 rounded-entrada border border-borda bg-entrada/60 px-3 py-2">
                <span className="numero text-creme">•••• {k.final}</span>
                <span className="ml-auto text-xs text-lavanda">desde {formatarDataHora(k.criado_em)}</span>
                {editavel && (
                  <Botao
                    variante="fantasma"
                    tamanho="p"
                    aria-label={`Remover cartão final ${k.final}`}
                    icone={<Trash2 aria-hidden className="size-4" />}
                    carregando={removerCartao.isPending && removerCartao.variables === k.id}
                    onClick={async () => {
                      if (!(await avisos.confirmar({ titulo: `Remover o cartão final ${k.final}?`, textoConfirmar: 'Remover', perigo: true }))) return
                      try {
                        await removerCartao.mutateAsync(k.id)
                        avisos.sucesso('Cartão removido')
                      } catch (e) {
                        avisos.erro(e)
                      }
                    }}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
        {editavel && (
          <div className="flex flex-col gap-2">
            <Campo rotulo="Número do cartão" htmlFor={idCartao} ajuda="Como o equipamento lê (decimal). No REP só o 1º cartão é usado.">
              <div className="flex gap-2">
                <Entrada
                  id={idCartao}
                  inputMode="numeric"
                  autoComplete="off"
                  value={numero}
                  maxLength={20}
                  onChange={(e) => setNumero(e.target.value.replace(/\D/g, ''))}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), incluirCartao())}
                />
                <Botao variante="secundario" carregando={adicionar.isPending} onClick={incluirCartao} disabled={!numero}>
                  Adicionar
                </Botao>
              </div>
            </Campo>
            {wiegand ? (
              <div className="grid grid-cols-[1fr_1fr_auto] items-end gap-2">
                <Campo rotulo="Área (facility)" htmlFor={`${idCartao}-a`}>
                  <Entrada id={`${idCartao}-a`} inputMode="numeric" value={wiegand.area} onChange={(e) => setWiegand({ ...wiegand, area: e.target.value.replace(/\D/g, '') })} />
                </Campo>
                <Campo rotulo="Código" htmlFor={`${idCartao}-c`}>
                  <Entrada id={`${idCartao}-c`} inputMode="numeric" value={wiegand.codigo} onChange={(e) => setWiegand({ ...wiegand, codigo: e.target.value.replace(/\D/g, '') })} />
                </Campo>
                <Botao
                  variante="secundario"
                  onClick={() => {
                    const n = numeroWiegand(wiegand.area, wiegand.codigo)
                    if (!n) return avisos.erro('Informe área e código (só números)')
                    setNumero(n)
                    setWiegand(null)
                  }}
                >
                  Calcular
                </Botao>
              </div>
            ) : (
              <button type="button" className="self-start text-xs font-semibold text-ouro-claro underline-offset-4 hover:underline" onClick={() => setWiegand({ area: '', codigo: '' })}>
                Cartão impresso com área e código (Wiegand)? Calcular o número
              </button>
            )}
          </div>
        )}
      </section>

      <section aria-labelledby={`${idSenha}-titulo`}>
        <h3 id={`${idSenha}-titulo`} className="mb-3 flex items-center gap-2 font-display text-lg text-creme">
          <KeyRound aria-hidden className="size-5 text-ouro" /> Senha de acesso
        </h3>
        <div className="flex flex-wrap items-center gap-3">
          {c.senha_definida ? <Selo tom="sucesso">Definida</Selo> : <Selo>Não definida</Selo>}
          <span className="text-xs text-lavanda">A senha nunca é exibida. Só números, de 4 a 8 dígitos.</span>
          {editavel && (
            <div className="flex gap-2">
              <Botao variante="secundario" tamanho="p" onClick={() => setModalSenha(true)}>
                {c.senha_definida ? 'Trocar senha' : 'Definir senha'}
              </Botao>
              {c.senha_definida && (
                <Botao
                  variante="fantasma"
                  tamanho="p"
                  carregando={senha.isPending}
                  onClick={async () => {
                    if (await avisos.confirmar({ titulo: 'Remover a senha de acesso?', textoConfirmar: 'Remover', perigo: true })) await salvarSenha(null)
                  }}
                >
                  Remover
                </Botao>
              )}
            </div>
          )}
        </div>
        <Modal
          aberto={modalSenha}
          aoFechar={() => {
            setModalSenha(false)
            setNovaSenha('')
          }}
          titulo="Senha de acesso"
          largura="p"
          rodape={
            <>
              <Botao variante="secundario" onClick={() => setModalSenha(false)}>
                Cancelar
              </Botao>
              <Botao carregando={senha.isPending} disabled={!/^\d{4,8}$/.test(novaSenha)} onClick={() => salvarSenha(novaSenha)}>
                Salvar
              </Botao>
            </>
          }
        >
          <Campo rotulo="Nova senha (4 a 8 dígitos)" htmlFor={idSenha} erro={novaSenha && !/^\d{4,8}$/.test(novaSenha) ? 'Use de 4 a 8 números' : null}>
            <Entrada
              id={idSenha}
              type="password"
              inputMode="numeric"
              autoComplete="new-password"
              maxLength={8}
              value={novaSenha}
              onChange={(e) => setNovaSenha(e.target.value.replace(/\D/g, ''))}
            />
          </Campo>
        </Modal>
      </section>
    </div>
  )
}

// ------------------------------------------------------ estado do envio
function descricaoEnvio(eq: EquipamentoControlId, envio: ControlIdEnvio | undefined) {
  if (!envioAtivo(eq)) return { status: 'desligado' as const, texto: null }
  if (!envio) return { status: 'sem_envio' as const, texto: 'Nada pendente para este equipamento (ex.: fora do vínculo e sem cadastro no aparelho).' }
  return { status: envio.status, texto: envio.erro }
}

export function EstadoEnvioControlId({ funcionarioId, editavel }: { funcionarioId: string; editavel: boolean }) {
  const avisos = useAvisos()
  const equipamentos = useEquipamentosControlId()
  const envios = useEnviosFuncionario(funcionarioId)
  const enviar = useEnviarControlIdAgora()

  if (equipamentos.isLoading || envios.isLoading) return <Carregando texto="Carregando estado do envio…" />
  if (equipamentos.error) return <ErroCarga erro={equipamentos.error} aoTentar={() => equipamentos.refetch()} />
  if (envios.error) return <ErroCarga erro={envios.error} aoTentar={() => envios.refetch()} />
  const lista = equipamentos.data ?? []
  if (lista.length === 0)
    return <Vazio titulo="Nenhum equipamento Control iD" descricao="Cadastre o equipamento em Integrações para enviar funcionários a ele." />

  const ligados = lista.filter(envioAtivo)

  const enviarAgora = async () => {
    try {
      const r = await enviar.mutateAsync({ funcionarioId, integracaoIds: ligados.map((e) => e.id) })
      avisos.sucesso(
        r.solicitacoes > 0
          ? 'Envio colocado na fila. Os equipamentos recebem em até 1 minuto.'
          : 'Já existe um envio na fila para estes equipamentos.',
      )
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <ul className="flex flex-col gap-2.5" aria-live="polite">
        {lista.map((eq) => {
          const envio = (envios.data ?? []).find((x) => x.integracao_id === eq.id)
          const d = descricaoEnvio(eq, envio)
          return (
            <li key={eq.id} className="rounded-entrada border border-borda bg-entrada/60 p-4">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-semibold text-creme">{eq.nome}</p>
                  <p className="text-xs text-lavanda">{rotuloTipoIntegracao[eq.tipo]}</p>
                </div>
                <div className="flex flex-wrap gap-1.5">
                  <SeloStatusEnvio status={d.status} />
                  {envio && envio.operacao !== 'salvar' && <Selo tom="alerta">{rotuloOperacaoEnvio[envio.operacao]}</Selo>}
                </div>
              </div>
              {d.status === 'desligado' ? (
                <p className="mt-2 text-sm text-lavanda">
                  O envio para este equipamento está desligado.{' '}
                  {eq.ativa ? 'Um administrador pode ativá-lo em ' : 'A integração está inativa. Reative-a em '}
                  <Link to={`/integracoes/${eq.id}`} className="font-semibold text-ouro-claro underline-offset-4 hover:underline">
                    Integrações › {eq.nome}
                  </Link>
                  .
                </p>
              ) : (
                <>
                  {d.texto && (
                    <p className={`mt-2 text-sm ${envio?.status === 'erro' ? 'text-perigo' : envio?.status === 'aguardando' ? 'text-alerta' : 'text-lavanda'}`}>
                      {d.texto}
                    </p>
                  )}
                  {envio && (
                    <p className="mt-2 text-xs text-lavanda">
                      {envio.enviado_em ? `Último envio ${formatarRelativo(envio.enviado_em)} (${formatarDataHora(envio.enviado_em)})` : 'Ainda não enviado'}
                      {envio.tentativas > 0 && envio.status !== 'enviado' ? ` · ${envio.tentativas} tentativa(s)` : ''}
                      {envio.id_remoto ? ` · id no equipamento ${envio.id_remoto}` : ''}
                    </p>
                  )}
                </>
              )}
            </li>
          )
        })}
      </ul>
      {editavel && (
        <div className="flex flex-wrap items-center gap-3">
          <Botao icone={<Send aria-hidden className="size-4" />} carregando={enviar.isPending} disabled={ligados.length === 0} onClick={enviarAgora}>
            Enviar para o Control iD agora
          </Botao>
          <Botao variante="fantasma" tamanho="p" icone={<RefreshCw aria-hidden className="size-4" />} onClick={() => envios.refetch()}>
            Atualizar
          </Botao>
          {ligados.length === 0 && <span className="text-xs text-lavanda">Ligue o envio em ao menos um equipamento.</span>}
        </div>
      )}
    </div>
  )
}
