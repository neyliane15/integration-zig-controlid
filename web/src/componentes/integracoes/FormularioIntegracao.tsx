/**
 * Criar/editar integração (contrato §11.1 + adendo A.1). Dono: frontend-1.
 * Segredos são SOMENTE ESCRITA: o campo nunca mostra o valor salvo, só "Configurado".
 */
import { useId, useState, type FormEvent } from 'react'
import { Check, KeyRound, Send } from 'lucide-react'
import type {
  ChaveSegredo,
  Integracao,
  ParametrosControlIdAcesso,
  ParametrosControlIdRep,
  ParametrosEnvioControlId,
  ParametrosIntegracao,
  ParametrosTagme,
  ParametrosZig,
  TipoIntegracao,
} from '@/tipos/banco'
import {
  CHAVES_SEGREDO,
  MODELOS_ACESSO,
  MODELOS_REP,
  nomePadrao,
  parametrosPadrao,
  useDefinirSegredos,
  useSalvarIntegracao,
  useSegredosPreenchidos,
} from '@/consultas/integracoes'
import { rotuloAoDesligar, rotuloTipoIntegracao } from '@/lib/rotulos'
import { useAvisos } from '../avisos'
import { AreaTexto, Botao, Caixa, Campo, Entrada, Interruptor, Selecao, Selo } from '../ui'

/** Chaves da Tagme com campo próprio; as demais vão no bloco "Avançado (JSON)" (adendo R.1). */
const CHAVES_TAGME = new Set(['url_base', 'restaurante_id', 'dias_retroativos', 'dias_a_frente'])

function textoAvancado(p: Record<string, unknown>): string {
  const extra = Object.fromEntries(Object.entries(p).filter(([k]) => !CHAVES_TAGME.has(k)))
  return JSON.stringify(extra, null, 2)
}

const INTERVALOS = [15, 30, 60, 120, 240, 360, 720, 1440]

function rotuloIntervalo(m: number): string {
  if (m < 60) return `A cada ${m} min`
  const h = m / 60
  return h === 24 ? 'Uma vez por dia' : `A cada ${h} h`
}

function Secao({ titulo, descricao, children }: { titulo: string; descricao?: string; children: React.ReactNode }) {
  return (
    <fieldset className="flex min-w-0 flex-col gap-5 border-t border-borda pt-6 first:border-t-0 first:pt-0">
      <legend className="sr-only">{titulo}</legend>
      <div aria-hidden>
        <p className="sobrancelha">{titulo}</p>
        {descricao && <p className="mt-1.5 text-sm text-lavanda">{descricao}</p>}
      </div>
      {children}
    </fieldset>
  )
}

export function FormularioIntegracao({
  empresaId,
  tipo,
  integracao,
  somenteLeitura,
  aoSalvar,
  aoCancelar,
}: {
  empresaId: string
  tipo: TipoIntegracao
  integracao?: Integracao | null
  somenteLeitura?: boolean
  aoSalvar?(id: string): void
  aoCancelar?(): void
}) {
  const id = useId()
  const avisos = useAvisos()
  const salvar = useSalvarIntegracao()
  const definirSegredos = useDefinirSegredos()
  const preenchidos = useSegredosPreenchidos(integracao?.id)

  const base = parametrosPadrao(tipo)
  const [nome, setNome] = useState(integracao?.nome ?? nomePadrao(tipo))
  const [ativa, setAtiva] = useState(integracao?.ativa ?? true)
  const [intervalo, setIntervalo] = useState(integracao?.intervalo_minutos ?? (tipo === 'controlid_acesso' ? 15 : 60)) // README §2: acesso a cada 15 min, demais 60
  const [parametros, setParametros] = useState<Record<string, unknown>>(() => {
    const atual = (integracao?.parametros ?? {}) as Record<string, unknown>
    const envioBase = (base as { envio?: ParametrosEnvioControlId }).envio
    const envioAtual = atual.envio as ParametrosEnvioControlId | undefined
    return { ...base, ...atual, ...(envioBase ? { envio: { ...envioBase, ...envioAtual } } : {}) }
  })
  const [segredos, setSegredos] = useState<Partial<Record<ChaveSegredo, string>>>({})
  const [remover, setRemover] = useState<Set<ChaveSegredo>>(new Set())
  const [erro, setErro] = useState<string | null>(null)
  const [avancado, setAvancado] = useState(() => textoAvancado(parametros))
  const [avancadoErro, setAvancadoErro] = useState<string | null>(null)

  function mudarAvancado(texto: string) {
    setAvancado(texto)
    let obj: unknown
    try {
      obj = texto.trim() === '' ? {} : JSON.parse(texto)
    } catch {
      return setAvancadoErro('JSON inválido')
    }
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return setAvancadoErro('Precisa ser um objeto JSON ({ … })')
    setAvancadoErro(null)
    setParametros((a) => ({
      ...Object.fromEntries(Object.entries(a).filter(([k]) => CHAVES_TAGME.has(k))),
      ...Object.fromEntries(Object.entries(obj as Record<string, unknown>).filter(([k]) => !CHAVES_TAGME.has(k))),
    }))
  }

  const p = parametros as ParametrosZig & ParametrosControlIdAcesso & ParametrosControlIdRep
  const envio = (p.envio ?? {}) as ParametrosEnvioControlId
  const definir = (k: string, v: unknown) => setParametros((a) => ({ ...a, [k]: v }))
  const definirEnvio = (k: keyof ParametrosEnvioControlId, v: unknown) => setParametros((a) => ({ ...a, envio: { ...(a.envio as object), [k]: v } }))
  const ehControlId = tipo === 'controlid_acesso' || tipo === 'controlid_rep'
  const ehTagme = tipo === 'tagme'
  const ehAcesso = tipo === 'controlid_acesso'
  const ehFace = ehAcesso && /idface/i.test(p.modelo ?? '')
  const carregando = salvar.isPending || definirSegredos.isPending
  const ro = somenteLeitura

  async function enviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!nome.trim()) return setErro('Informe o nome')
    const dias = Number(p.dias_retroativos ?? 2)
    if (!Number.isInteger(dias) || dias < 0 || dias > 31) return setErro('Dias retroativos: de 0 a 31.')
    if (tipo === 'zig' && !String(p.rede ?? '').trim()) return setErro('Informe o id da rede na Zig.')
    if (ehTagme) {
      const frente = Number((parametros as ParametrosTagme).dias_a_frente ?? 7)
      if (!Number.isInteger(frente) || frente < 0 || frente > 62) return setErro('Dias à frente: de 0 a 62.')
      if (avancadoErro) return setErro(avancadoErro)
    }
    if (ehAcesso && (!Array.isArray(p.eventos_validos) || p.eventos_validos.length === 0)) return setErro('Informe ao menos um evento válido (ex.: 7).')
    const finalParametros = { ...parametros, dias_retroativos: dias } as ParametrosIntegracao
    try {
      const novoId = await salvar.mutateAsync({
        id: integracao?.id,
        empresaId,
        tipo,
        dados: { nome: nome.trim(), ativa, intervalo_minutos: intervalo, parametros: finalParametros },
      })
      const mudancas: Partial<Record<ChaveSegredo, string | null>> = {}
      for (const [k, v] of Object.entries(segredos) as [ChaveSegredo, string][]) if (v.trim()) mudancas[k] = v.trim()
      for (const k of remover) if (!mudancas[k]) mudancas[k] = null
      if (Object.keys(mudancas).length > 0) await definirSegredos.mutateAsync({ integracaoId: novoId, segredos: mudancas })
      setSegredos({})
      setRemover(new Set())
      avisos.sucesso(integracao ? 'Integração salva.' : 'Integração criada.')
      aoSalvar?.(novoId)
    } catch (err) {
      avisos.erro(err)
    }
  }

  const preenchidas = new Set(preenchidos.data ?? [])

  return (
    <form onSubmit={enviar} noValidate className="flex flex-col gap-6">
      {erro && (
        <p role="alert" className="rounded-entrada border border-perigo/40 bg-perigo/10 px-4 py-3 text-sm text-creme">
          {erro}
        </p>
      )}

      {ehTagme && (
        <div className="rounded-entrada border border-info/35 bg-info/5 px-4 py-3 text-sm leading-relaxed text-creme">
          <p className="font-semibold">A Tagme só libera API para parceiros.</p>
          <p className="mt-1 text-lavanda">
            Para a sincronização automática, peça o acesso à API ao suporte da Tagme (contrato de parceiro) e preencha o endereço, o id do
            restaurante e as credenciais abaixo; a configuração do N8N está em <span className="numero text-creme">docs/IMPLANTACAO-N8N-HOSTINGER.md</span>.
            Enquanto isso, exporte as reservas no painel <span className="numero text-creme">waitlist.tagme.com.br</span> (Reservas → exportar) e
            importe o CSV em <strong className="text-creme">Reservas → Importar CSV</strong>, ou lance as reservas à mão.
          </p>
        </div>
      )}

      <Secao titulo="Geral" descricao={rotuloTipoIntegracao[tipo]}>
        <div className="grid gap-5 sm:grid-cols-2">
          <Campo rotulo="Nome" htmlFor={`${id}-nome`} obrigatorio ajuda={ehControlId ? 'Ex.: iDFace porta dos fundos' : undefined}>
            <Entrada id={`${id}-nome`} value={nome} onChange={(e) => setNome(e.target.value)} disabled={ro} />
          </Campo>
          <Campo rotulo="Frequência automática" htmlFor={`${id}-int`}>
            <Selecao id={`${id}-int`} value={intervalo} onChange={(e) => setIntervalo(Number(e.target.value))} disabled={ro}>
              {INTERVALOS.map((m) => (
                <option key={m} value={m}>
                  {rotuloIntervalo(m)}
                </option>
              ))}
            </Selecao>
          </Campo>
          {ehControlId && (
            <Campo rotulo="Tipo do equipamento" htmlFor={`${id}-modelo`} ajuda={ehAcesso ? 'Controle de acesso (iDFace, iDFlex, iDAccess).' : 'Relógio de ponto REP (iDClass).'}>
              <Entrada
                id={`${id}-modelo`}
                list={`${id}-modelos`}
                value={p.modelo ?? ''}
                onChange={(e) => definir('modelo', e.target.value)}
                disabled={ro}
              />
              <datalist id={`${id}-modelos`}>
                {(ehAcesso ? MODELOS_ACESSO : MODELOS_REP).map((m) => (
                  <option key={m} value={m} />
                ))}
              </datalist>
            </Campo>
          )}
          {ehTagme && (
            <>
              <Campo rotulo="Endereço da API" htmlFor={`${id}-url`} ajuda="Informado pela Tagme no contrato de parceiro. Em branco enquanto não houver.">
                <Entrada
                  id={`${id}-url`}
                  type="url"
                  placeholder="https://…"
                  value={String((parametros as ParametrosTagme).url_base ?? '')}
                  onChange={(e) => definir('url_base', e.target.value)}
                  disabled={ro}
                />
              </Campo>
              <Campo rotulo="Id do restaurante na Tagme" htmlFor={`${id}-rest`}>
                <Entrada
                  id={`${id}-rest`}
                  value={String((parametros as ParametrosTagme).restaurante_id ?? '')}
                  onChange={(e) => definir('restaurante_id', e.target.value)}
                  disabled={ro}
                />
              </Campo>
              <Campo rotulo="Dias à frente" htmlFor={`${id}-frente`} ajuda="Quantos dias futuros cada sincronização busca (0 a 62).">
                <Entrada
                  id={`${id}-frente`}
                  type="number"
                  min={0}
                  max={62}
                  inputMode="numeric"
                  className="numero"
                  value={String((parametros as ParametrosTagme).dias_a_frente ?? 7)}
                  onChange={(e) => definir('dias_a_frente', e.target.value === '' ? '' : Number(e.target.value))}
                  disabled={ro}
                />
              </Campo>
            </>
          )}
          {tipo === 'zig' && (
            <Campo rotulo="Id da rede na Zig" htmlFor={`${id}-rede`} obrigatorio>
              <Entrada id={`${id}-rede`} value={p.rede ?? ''} onChange={(e) => definir('rede', e.target.value)} disabled={ro} />
            </Campo>
          )}
          <Campo rotulo="Dias retroativos" htmlFor={`${id}-dias`} ajuda="Quantos dias para trás cada sincronização relê.">
            <Entrada
              id={`${id}-dias`}
              type="number"
              min={0}
              max={31}
              inputMode="numeric"
              className="numero"
              value={String(p.dias_retroativos ?? 2)}
              onChange={(e) => definir('dias_retroativos', e.target.value === '' ? '' : Number(e.target.value))}
              disabled={ro}
            />
          </Campo>
          {tipo === 'controlid_rep' && (
            <Campo rotulo="Identificador do funcionário" htmlFor={`${id}-ident`}>
              <Selecao id={`${id}-ident`} value={p.identificador ?? 'cpf'} onChange={(e) => definir('identificador', e.target.value)} disabled={ro}>
                <option value="cpf">CPF (Portaria 671)</option>
                <option value="pis">PIS (legado, Portaria 1510)</option>
              </Selecao>
            </Campo>
          )}
          {ehAcesso && (
            <Campo rotulo="Eventos que contam como batida" htmlFor={`${id}-ev`} ajuda="Códigos separados por vírgula. 7 = acesso liberado.">
              <Entrada
                id={`${id}-ev`}
                className="numero"
                inputMode="numeric"
                value={(p.eventos_validos ?? []).join(', ')}
                onChange={(e) =>
                  definir(
                    'eventos_validos',
                    e.target.value
                      .split(/[,\s]+/)
                      .filter(Boolean)
                      .map(Number)
                      .filter((n) => Number.isInteger(n)),
                  )
                }
                disabled={ro}
              />
            </Campo>
          )}
        </div>
        <div className="flex flex-col gap-3">
          <Interruptor rotulo="Integração ativa" marcado={ativa} aoMudar={setAtiva} desabilitado={ro} />
          {ehAcesso && (
            <Interruptor
              rotulo="Relógio do equipamento em hora local"
              marcado={p.relogio_em_hora_local !== false}
              aoMudar={(v) => definir('relogio_em_hora_local', v)}
              desabilitado={ro}
            />
          )}
        </div>
      </Secao>

      {ehTagme && (
        <Secao titulo="Avançado" descricao="Campos opcionais lidos pelo N8N (caminho, metodo, consulta, paginacao, mapeamento, autenticacao).">
          <Campo
            rotulo="Parâmetros avançados (JSON)"
            htmlFor={`${id}-avancado`}
            erro={avancadoErro}
            ajuda='Objeto JSON. Ex.: {"caminho": "/api/reservas", "mapeamento": {"lista": "data.items"}}. Deixe {} se não souber.'
          >
            <AreaTexto
              id={`${id}-avancado`}
              className="numero text-sm"
              spellCheck={false}
              value={avancado}
              onChange={(e) => mudarAvancado(e.target.value)}
              disabled={ro}
            />
          </Campo>
        </Secao>
      )}

      {ehControlId && (
        <Secao
          titulo="Envio para o equipamento"
          descricao="Quando ligado, o cadastro de funcionários deste sistema alimenta o equipamento (criar, alterar, remover)."
        >
          <div className="rounded-entrada border border-borda bg-entrada/60 p-4">
            <Interruptor
              rotulo={
                <span className="flex items-center gap-2 font-semibold">
                  <Send aria-hidden className="size-4 text-ouro" /> Enviar dados para o equipamento
                </span>
              }
              marcado={!!envio.ativo}
              aoMudar={(v) => definirEnvio('ativo', v)}
              desabilitado={ro}
            />
            {envio.ativo && (
              <div className="mt-4 grid gap-3 border-t border-borda pt-4 sm:grid-cols-2">
                <Caixa rotulo="Cartões / crachás" marcado={envio.cartao !== false} aoMudar={(v) => definirEnvio('cartao', v)} desabilitado={ro} />
                <Caixa rotulo="Senha de acesso (PIN)" marcado={envio.senha !== false} aoMudar={(v) => definirEnvio('senha', v)} desabilitado={ro} />
                {ehAcesso && (
                  <Caixa
                    rotulo={ehFace ? 'Foto facial' : 'Foto facial (só iDFace)'}
                    marcado={!!envio.foto}
                    aoMudar={(v) => definirEnvio('foto', v)}
                    desabilitado={ro}
                  />
                )}
                {ehAcesso && (
                  <Caixa rotulo="Horários de acesso" marcado={envio.horarios !== false} aoMudar={(v) => definirEnvio('horarios', v)} desabilitado={ro} />
                )}
                <div className="mt-2 sm:col-span-2">
                  <Campo rotulo="Ao desligar ou inativar o funcionário" htmlFor={`${id}-desl`}>
                    <Selecao
                      id={`${id}-desl`}
                      value={ehAcesso ? (envio.ao_desligar ?? 'remover') : 'remover'}
                      onChange={(e) => definirEnvio('ao_desligar', e.target.value)}
                      disabled={ro || !ehAcesso}
                    >
                      <option value="remover">{rotuloAoDesligar.remover}</option>
                      {ehAcesso && <option value="bloquear">{rotuloAoDesligar.bloquear}</option>}
                    </Selecao>
                  </Campo>
                </div>
              </div>
            )}
          </div>
        </Secao>
      )}

      <Secao
        titulo="Credenciais"
        descricao="Guardadas no banco sem acesso pelo navegador. Por segurança, o valor salvo nunca é exibido — preencha só para trocar."
      >
        <div className="grid gap-5 sm:grid-cols-2">
          {CHAVES_SEGREDO[tipo].map((s) => {
            const configurado = preenchidas.has(s.chave) && !remover.has(s.chave)
            return (
              <Campo
                key={s.chave}
                rotulo={s.rotulo}
                htmlFor={`${id}-s-${s.chave}`}
                ajuda={
                  <span className="flex flex-wrap items-center gap-2">
                    {configurado ? (
                      <Selo tom="sucesso">
                        <Check aria-hidden /> Configurado
                      </Selo>
                    ) : (
                      <Selo>
                        <KeyRound aria-hidden /> Não configurado
                      </Selo>
                    )}
                    {configurado && !ro && (
                      <button
                        type="button"
                        className="text-xs font-semibold text-lavanda underline hover:text-creme"
                        onClick={() => setRemover((r) => new Set(r).add(s.chave))}
                      >
                        Apagar
                      </button>
                    )}
                    <span>{s.dica}</span>
                  </span>
                }
              >
                <Entrada
                  id={`${id}-s-${s.chave}`}
                  type={s.tipo === 'password' ? 'password' : s.tipo === 'url' ? 'url' : 'text'}
                  autoComplete={s.tipo === 'password' ? 'new-password' : 'off'}
                  placeholder={configurado ? '•••••• (deixe em branco para manter)' : ''}
                  value={segredos[s.chave] ?? ''}
                  onChange={(e) => setSegredos((a) => ({ ...a, [s.chave]: e.target.value }))}
                  disabled={ro}
                />
              </Campo>
            )
          })}
        </div>
      </Secao>

      {!ro && (
        <div className="flex flex-wrap justify-end gap-2 border-t border-borda pt-5">
          {aoCancelar && (
            <Botao variante="secundario" onClick={aoCancelar}>
              Cancelar
            </Botao>
          )}
          <Botao type="submit" carregando={carregando}>
            {integracao ? 'Salvar alterações' : 'Criar integração'}
          </Botao>
        </div>
      )}
    </form>
  )
}
