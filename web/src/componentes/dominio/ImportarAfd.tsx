/**
 * "Importar AFD" (RHiD/arquivo) e "Ligar funcionários" — o relógio REP da loja não é alcançável pela rede, mas o RHiD exporta
 * o AFD. O arquivo é lido no navegador (mesma lib do N8N), mostra a prévia, vai em lotes para `ponto_importar_afd` e os CPFs
 * sem funcionário podem ser ligados na hora (inclusive aos provisórios da escala, ex.: "Garçom 1").
 */
import { useId, useMemo, useRef, useState } from 'react'
import { AlertTriangle, CheckCircle2, Clock, FileUp, Link2, Plus, UserCheck } from 'lucide-react'
import type { Funcionario, ResultadoImportacaoAfd, UsuarioRelogioPendente } from '@/tipos/banco'
import { Botao, Caixa, Campo, Carregando, ErroCarga, Modal, Selecao, Selo, Vazio } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { useControlIdUsuarios, useFuncionarios } from '@/consultas/funcionarios'
import {
  ehRelogioPorArquivo,
  useCriarRelogioArquivo,
  useImportarAfd,
  useLigarFuncionarioAfd,
  usePendentesRelogio,
  useProvisoriosEscala,
  useRelogiosPonto,
} from '@/consultas/afd'
import { LIMITE_ARQUIVO_AFD, formatarDocumento, lerArquivoAfd, nomeProprio, previaAfd, type PreviaAfd } from '@/lib/afd'
import { formatarData, normalizar } from '@/lib/formato'

export const AJUDA_RHID = 'No RHiD: Relatórios → Relatório de AFDs → período → Buscar → baixar o arquivo.'

type Etapa = 'arquivo' | 'previa' | 'resultado' | 'ligar'

function periodoTexto(inicio: string | null, fim: string | null): string {
  if (!inicio || !fim) return '—'
  return inicio === fim ? formatarData(inicio) : `${formatarData(inicio)} a ${formatarData(fim)}`
}

function Numero({ rotulo, valor, tom }: { rotulo: string; valor: React.ReactNode; tom?: 'alerta' | 'sucesso' | 'perigo' }) {
  return (
    <div className="min-w-0 rounded-entrada border border-borda bg-cartao-2/50 p-3">
      <dt className="text-xs text-lavanda">{rotulo}</dt>
      <dd
        className={
          'numero mt-0.5 text-lg font-semibold sm:text-xl ' +
          (tom === 'alerta' ? 'text-alerta' : tom === 'sucesso' ? 'text-sucesso' : tom === 'perigo' ? 'text-perigo' : 'text-creme')
        }
      >
        {valor}
      </dd>
    </div>
  )
}

export function ModalImportarAfd({ aberto, aoFechar, integracaoId }: { aberto: boolean; aoFechar(): void; integracaoId?: string }) {
  const avisos = useAvisos()
  const id = useId()
  const entrada = useRef<HTMLInputElement>(null)
  const relogios = useRelogiosPonto()
  const criar = useCriarRelogioArquivo()
  const importar = useImportarAfd()
  const usuarios = useControlIdUsuarios()
  const funcionarios = useFuncionarios()
  const [escolhido, setEscolhido] = useState<string | null>(integracaoId ?? null)
  const [etapa, setEtapa] = useState<Etapa>('arquivo')
  const [arquivo, setArquivo] = useState<string | null>(null)
  const [previa, setPrevia] = useState<PreviaAfd | null>(null)
  const [progresso, setProgresso] = useState<{ enviadas: number; total: number } | null>(null)
  const [resultado, setResultado] = useState<ResultadoImportacaoAfd | null>(null)

  const ativos = (relogios.data ?? []).filter((r) => r.ativa)
  const relogio = ativos.find((r) => r.id === escolhido) ?? (integracaoId ? undefined : (ativos.find((r) => ehRelogioPorArquivo(r)) ?? ativos[0]))

  // CPF/PIS já ligados a funcionário: vínculo no relógio ou documento na ficha
  const ligados = useMemo(() => {
    const m = new Map<string, string>()
    const nomes = new Map((funcionarios.data ?? []).map((f) => [f.id, f.nome]))
    for (const f of funcionarios.data ?? []) {
      if (f.cpf) m.set(f.cpf, f.nome)
      if (f.pis) m.set(f.pis, f.nome)
    }
    for (const u of usuarios.data ?? [])
      if (u.integracao_id === relogio?.id && u.funcionario_id) m.set(u.user_id_externo, nomes.get(u.funcionario_id) ?? 'funcionário')
    return m
  }, [funcionarios.data, usuarios.data, relogio?.id])

  const semVinculo = previa ? previa.pessoas.filter((p) => p.marcacoes > 0 && !ligados.has(p.documento)) : []

  const limpar = () => {
    setArquivo(null)
    setPrevia(null)
    setResultado(null)
    setProgresso(null)
    setEtapa('arquivo')
  }
  const fechar = () => {
    if (importar.isPending) return
    limpar()
    aoFechar()
  }

  const escolher = async (f: File | undefined) => {
    if (!f) return
    if (f.size > LIMITE_ARQUIVO_AFD) return avisos.erro('Arquivo grande demais (máximo 20 MB). Baixe um período menor no RHiD.')
    if (/\.p7s$/i.test(f.name)) return avisos.erro('Este é o arquivo de assinatura (.p7s). Escolha o .txt do AFD (ou o .zip inteiro).')
    let lido: { nome: string; texto: string }
    try {
      lido = await lerArquivoAfd(f.name, await f.arrayBuffer())
    } catch (e) {
      return avisos.erro(e)
    }
    const p = previaAfd(lido.texto)
    if (p.leitura.marcacoes.length === 0 && p.leitura.empregados.length === 0)
      return avisos.erro('Não encontramos marcações nem empregados neste arquivo. Confira se é o AFD (.txt) baixado do RHiD.')
    setArquivo(lido.nome)
    setPrevia(p)
    setResultado(null)
    setEtapa('previa')
  }

  const enviar = async () => {
    if (!previa || !relogio || !arquivo) return
    setProgresso({ enviadas: 0, total: previa.leitura.marcacoes.length })
    try {
      const r = await importar.mutateAsync({
        integracaoId: relogio.id,
        leitura: previa.leitura,
        arquivo,
        aoProgresso: (enviadas, total) => setProgresso({ enviadas, total }),
      })
      setResultado(r)
      setEtapa('resultado')
      avisos.sucesso(
        previa.leitura.marcacoes.length
          ? `AFD importado: ${r.gravadas} marcação(ões) nova(s)`
          : `Empregados do AFD importados: ${r.empregados.novos} novo(s), ${r.empregados.atualizados} atualizado(s)`,
      )
    } catch (e) {
      avisos.erro(e)
    } finally {
      setProgresso(null)
    }
  }

  const criarRelogio = () =>
    criar.mutate(undefined, {
      onSuccess: (novo) => {
        setEscolhido(novo)
        avisos.sucesso('Relógio de ponto (RHiD/arquivo) criado.')
      },
      onError: avisos.erro,
    })

  const rodape =
    etapa === 'resultado' ? (
      <>
        {resultado && (resultado.sem_funcionario.length > 0 || resultado.empregados.lidos > resultado.empregados.vinculados_automaticamente) && (
          <Botao variante="secundario" icone={<Link2 aria-hidden />} onClick={() => setEtapa('ligar')}>
            Ligar funcionários
          </Botao>
        )}
        <Botao onClick={fechar}>Concluir</Botao>
      </>
    ) : etapa === 'ligar' ? (
      <>
        <Botao variante="secundario" onClick={() => setEtapa('resultado')}>
          Voltar ao resultado
        </Botao>
        <Botao onClick={fechar}>Concluir</Botao>
      </>
    ) : (
      <>
        <Botao variante="secundario" onClick={fechar} disabled={importar.isPending}>
          Cancelar
        </Botao>
        {etapa === 'previa' && (
          <Botao
            onClick={enviar}
            carregando={importar.isPending}
            disabled={!relogio || !previa || (previa.leitura.marcacoes.length === 0 && previa.leitura.empregados.length === 0)}
            icone={<FileUp aria-hidden />}
          >
            {!previa
              ? 'Importar'
              : previa.leitura.marcacoes.length
                ? `Importar ${previa.leitura.marcacoes.length} marcação(ões)`
                : `Importar ${previa.leitura.empregados.length} empregado(s)`}
          </Botao>
        )}
      </>
    )

  let corpo: React.ReactNode
  if (relogios.isPending) corpo = <Carregando texto="Carregando relógios…" />
  else if (relogios.error) corpo = <ErroCarga erro={relogios.error} aoTentar={() => void relogios.refetch()} />
  else if (!relogio)
    corpo = (
      <Vazio
        icone={<Clock aria-hidden />}
        titulo="Nenhum relógio de ponto ativo"
        descricao="O relógio da loja fica no RHiD (nuvem da Control iD). Crie um relógio “por arquivo” — sem endereço nem senha — para receber o AFD."
        acao={
          <Botao icone={<Plus aria-hidden />} onClick={criarRelogio} carregando={criar.isPending}>
            Criar “Relógio de ponto (RHiD/arquivo)”
          </Botao>
        }
      />
    )
  else if (etapa === 'arquivo')
    corpo = (
      <div className="flex flex-col gap-5">
        {ativos.length > 1 && !integracaoId && (
          <Campo rotulo="Relógio de ponto" htmlFor={`${id}-relogio`}>
            <Selecao id={`${id}-relogio`} value={relogio.id} onChange={(e) => setEscolhido(e.target.value)}>
              {ativos.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.nome}
                </option>
              ))}
            </Selecao>
          </Campo>
        )}
        <div className="rounded-entrada border border-info/35 bg-info/5 px-4 py-3 text-sm leading-relaxed text-creme">
          <p className="font-semibold">{AJUDA_RHID}</p>
          <p className="mt-1 text-lavanda">
            Também serve o “Baixar AFD do REP”. Pode importar o mesmo período mais de uma vez: marcações já importadas são reconhecidas pelo NSR e não duplicam.
            Se o RHiD entregar um .zip (o .txt com a assinatura .p7s), pode escolher o .zip inteiro. Destino:{' '}
            <strong className="text-creme">{relogio.nome}</strong>.
          </p>
        </div>
        <input
          ref={entrada}
          id={id}
          type="file"
          accept=".txt,.zip,text/plain,application/zip"
          className="sr-only"
          onChange={(e) => {
            void escolher(e.target.files?.[0])
            e.target.value = ''
          }}
        />
        <label htmlFor={id} className="sr-only">
          Arquivo AFD
        </label>
        <div>
          <Botao icone={<FileUp aria-hidden />} onClick={() => entrada.current?.click()}>
            Escolher arquivo AFD (.txt ou .zip)
          </Botao>
        </div>
      </div>
    )
  else if (etapa === 'previa' && previa)
    corpo = (
      <div className="flex flex-col gap-5" data-teste="previa-afd">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="min-w-0 truncate text-sm text-creme">
            <span className="font-semibold">{arquivo}</span> → {relogio.nome}
          </p>
          <Botao variante="fantasma" tamanho="p" onClick={limpar} disabled={importar.isPending}>
            Trocar arquivo
          </Botao>
        </div>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Numero rotulo="Período" valor={<span className="text-base">{periodoTexto(previa.inicio, previa.fim)}</span>} />
          <Numero rotulo="Marcações" valor={previa.leitura.marcacoes.length} />
          <Numero rotulo="Empregados no AFD" valor={previa.leitura.empregados.length} />
          <Numero rotulo="CPFs sem funcionário" valor={semVinculo.length} tom={semVinculo.length ? 'alerta' : 'sucesso'} />
        </dl>
        {previa.leitura.marcacoes.length === 0 && (
          <p
            role="status"
            className="flex items-start gap-2 rounded-entrada border border-info/35 bg-info/5 p-3 text-sm text-creme"
            data-teste="afd-sem-marcacoes"
          >
            <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0 text-info" />
            <span>
              <strong>Este arquivo não tem marcações (só cadastro de empregados).</strong>{' '}
              <span className="text-lavanda">
                Dá para importar os empregados (CPF e nome) para ligar cada um a um funcionário. Para as batidas, baixe no RHiD o AFD de um período com
                marcações.
              </span>
            </span>
          </p>
        )}
        {previa.leitura.layouts['1510'] > 0 && <p className="text-xs text-lavanda">Layout antigo (Portaria 1510): as pessoas são identificadas pelo PIS.</p>}
        {previa.leitura.ignoradas.length > 0 && (
          <div className="rounded-entrada border border-alerta/40 bg-alerta/10 p-3 text-sm text-alerta">
            <p className="flex items-center gap-2 font-semibold">
              <AlertTriangle aria-hidden className="size-4" /> {previa.leitura.ignoradas.length} linha(s) com defeito ficam de fora
            </p>
            <ul className="mt-1 max-h-24 overflow-auto text-xs">
              {previa.leitura.ignoradas.slice(0, 10).map((l) => (
                <li key={l.linha}>
                  Linha <span className="numero">{l.linha}</span>: {l.motivo}
                </li>
              ))}
            </ul>
          </div>
        )}
        <section aria-labelledby={`${id}-pessoas`}>
          <h3 id={`${id}-pessoas`} className="mb-2 font-display text-lg text-creme">
            Pessoas no arquivo
          </h3>
          <div className="max-h-72 overflow-auto rounded-entrada border border-borda">
            <table className="w-full border-collapse text-sm">
              <thead className="sticky top-0 bg-cartao-2">
                <tr className="text-left text-[11px] tracking-[0.12em] text-lavanda uppercase">
                  <th scope="col" className="px-3 py-2">
                    Pessoa
                  </th>
                  <th scope="col" className="px-3 py-2 text-right">
                    Marcações
                  </th>
                  <th scope="col" className="px-3 py-2">
                    Funcionário
                  </th>
                </tr>
              </thead>
              <tbody>
                {previa.pessoas.slice(0, 200).map((p) => {
                  const func = ligados.get(p.documento)
                  return (
                    <tr key={p.documento} className="border-t border-borda align-top" data-teste="pessoa-afd" data-documento={p.documento}>
                      <td className="px-3 py-2">
                        <p className="font-semibold break-words text-creme">{p.nome ?? '(sem nome no AFD)'}</p>
                        <p className="numero text-xs text-lavanda">
                          {p.tipo === 'cpf' ? 'CPF' : 'PIS'} {formatarDocumento(p.documento, p.tipo)}
                        </p>
                      </td>
                      <td className="numero px-3 py-2 text-right">{p.marcacoes}</td>
                      <td className="px-3 py-2">{func ? <Selo tom="sucesso">{func}</Selo> : <Selo tom="alerta">Sem funcionário</Selo>}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          {semVinculo.length > 0 && (
            <p className="mt-2 text-xs text-lavanda">
              As marcações de quem está sem funcionário são guardadas e entram no ponto assim que você ligar o CPF a alguém (dá para fazer logo depois de
              importar).
            </p>
          )}
        </section>
        {progresso && (
          <div role="status" className="flex flex-col gap-1.5">
            <p className="text-sm text-creme">
              Enviando… <span className="numero">{progresso.enviadas}</span> de <span className="numero">{progresso.total}</span>
            </p>
            <div className="h-2 overflow-hidden rounded-pilula bg-cartao-2">
              <div className="h-full bg-ouro transition-all" style={{ width: `${progresso.total ? (100 * progresso.enviadas) / progresso.total : 0}%` }} />
            </div>
          </div>
        )}
      </div>
    )
  else if (etapa === 'resultado' && resultado)
    corpo = (
      <div className="flex flex-col gap-4" data-teste="resultado-afd">
        <p className="flex items-center gap-2 font-display text-lg text-creme">
          <CheckCircle2 aria-hidden className="size-5 text-sucesso" /> Importação concluída
        </p>
        <p className="text-sm text-lavanda">
          {arquivo} · período {periodoTexto(resultado.periodo.inicio, resultado.periodo.fim)}
        </p>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Numero rotulo="Marcações novas" valor={resultado.gravadas} tom="sucesso" />
          <Numero rotulo="Já importadas" valor={resultado.duplicadas} />
          <Numero rotulo="Dias recalculados" valor={resultado.dias_reapurados} />
          <Numero rotulo="CPFs sem funcionário" valor={resultado.sem_funcionario.length} tom={resultado.sem_funcionario.length ? 'alerta' : 'sucesso'} />
        </dl>
        {resultado.empregados.lidos > 0 && (
          <p className="text-sm text-creme" data-teste="resultado-empregados">
            Empregados do AFD: <span className="numero">{resultado.empregados.novos}</span> novo(s),{' '}
            <span className="numero">{resultado.empregados.atualizados}</span> atualizado(s) — aparecem em “Ligar funcionários”.
          </p>
        )}
        {resultado.empregados.vinculados_automaticamente > 0 && (
          <p className="text-sm text-creme">
            <UserCheck aria-hidden className="mr-1 inline size-4 text-sucesso" />
            {resultado.empregados.vinculados_automaticamente} pessoa(s) ligada(s) automaticamente pelo CPF da ficha.
          </p>
        )}
        {resultado.sem_funcionario.length > 0 && (
          <div className="rounded-entrada border border-alerta/40 bg-alerta/10 p-3 text-sm text-alerta">
            <p className="flex items-start gap-2">
              <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0" />
              {resultado.sem_funcionario.reduce((s, p) => s + p.quantidade, 0)} marcação(ões) de {resultado.sem_funcionario.length} CPF(s) ainda sem
              funcionário. Elas não entram no ponto até você ligar cada CPF a um funcionário.
            </p>
            <ul className="mt-2 flex flex-col gap-0.5 text-xs">
              {resultado.sem_funcionario.slice(0, 8).map((p) => (
                <li key={p.cpf ?? p.pis}>
                  <span className="numero">{formatarDocumento(p.cpf ?? p.pis, p.cpf ? 'cpf' : 'pis')}</span> · {p.nome ?? '(sem nome no AFD)'} ·{' '}
                  <span className="numero">{p.quantidade}</span> marcação(ões)
                </li>
              ))}
            </ul>
          </div>
        )}
        {resultado.ignoradas > 0 && (
          <p className="text-xs text-perigo">
            {resultado.ignoradas} marcação(ões) recusada(s) pelo banco
            {resultado.erros?.length ? `: ${[...new Set(resultado.erros.map((e) => e.motivo))].join(', ')}` : ''}.
          </p>
        )}
      </div>
    )
  else if (etapa === 'ligar') corpo = <LigarFuncionariosAfd integracaoId={relogio.id} />

  return (
    <Modal
      aberto={aberto}
      aoFechar={fechar}
      largura="g"
      titulo={etapa === 'ligar' ? 'Ligar funcionários' : 'Importar AFD'}
      rodape={relogio ? rodape : undefined}
    >
      {corpo}
    </Modal>
  )
}

// ----------------------------------------------------------------- ligar funcionários
function rotuloFuncionario(f: Funcionario, provisorio: boolean): string {
  const extras = [f.cargo, provisorio ? 'provisório da escala' : null, f.cpf ? null : 'sem CPF'].filter(Boolean)
  return extras.length ? `${f.nome} — ${extras.join(' · ')}` : f.nome
}

export function LigarFuncionariosAfd({ integracaoId }: { integracaoId: string }) {
  const pendentes = usePendentesRelogio(integracaoId)
  const funcionarios = useFuncionarios()
  const provisorios = useProvisoriosEscala()

  const lista = useMemo(() => {
    const prov = provisorios.data ?? new Map<string, string>()
    return (funcionarios.data ?? [])
      .filter((f) => f.ativo)
      .map((f) => ({ f, provisorio: prov.has(f.id) && normalizar(prov.get(f.id) ?? '') === normalizar(f.nome) && !f.cpf }))
      .sort((a, b) => Number(b.provisorio) - Number(a.provisorio) || a.f.nome.localeCompare(b.f.nome, 'pt-BR', { numeric: true }))
  }, [funcionarios.data, provisorios.data])

  if (pendentes.error) return <ErroCarga erro={pendentes.error} aoTentar={() => void pendentes.refetch()} />
  if (pendentes.isPending || funcionarios.isPending) return <Carregando />
  const linhas = pendentes.data ?? []
  if (linhas.length === 0)
    return <Vazio icone={<UserCheck aria-hidden />} titulo="Todos os CPFs estão ligados" descricao="Não há marcações do relógio esperando funcionário." />

  return (
    <div className="flex flex-col gap-3" data-teste="ligar-funcionarios">
      <p className="text-sm text-lavanda">
        Escolha quem é cada pessoa do AFD. Vale ligar aos provisórios da escala (ex.: “Garçom 1”) e já trocar o nome pelo do AFD. As marcações guardadas passam
        para o funcionário e os dias são recalculados.
      </p>
      <ul className="flex flex-col gap-3">
        {linhas.map((p) => (
          <LinhaLigar key={p.controlid_usuario_id} p={p} opcoes={lista} />
        ))}
      </ul>
    </div>
  )
}

function LinhaLigar({ p, opcoes }: { p: UsuarioRelogioPendente; opcoes: { f: Funcionario; provisorio: boolean }[] }) {
  const id = useId()
  const avisos = useAvisos()
  const ligar = useLigarFuncionarioAfd()
  const nome = p.nome_sugerido ?? nomeProprio(p.nome)
  const sugerido = useMemo(() => (nome ? opcoes.find((o) => normalizar(o.f.nome) === normalizar(nome))?.f.id : undefined), [nome, opcoes])
  const [funcionarioId, setFuncionarioId] = useState<string>(sugerido ?? '')
  const escolhido = opcoes.find((o) => o.f.id === funcionarioId)
  const [renomear, setRenomear] = useState<boolean | null>(null)
  const [documento, setDocumento] = useState<boolean | null>(null)
  const tipoDoc = p.cpf ? 'CPF' : 'PIS'
  // padrões: renomear provisório (se o AFD trouxe nome); gravar o documento se a ficha não tem
  const renomearEfetivo = renomear ?? (!!escolhido?.provisorio && !!nome && normalizar(nome) !== normalizar(escolhido.f.nome))
  const documentoEfetivo = documento ?? (!!escolhido && !(p.cpf ? escolhido.f.cpf : escolhido.f.pis))

  const salvar = async () => {
    if (!escolhido) return
    try {
      const r = await ligar.mutateAsync({
        controlidUsuarioId: p.controlid_usuario_id,
        funcionarioId: escolhido.f.id,
        renomear: renomearEfetivo,
        cadastrarDocumento: documentoEfetivo,
      })
      avisos.sucesso(
        `${r.nome}: ${r.batidas} marcação(ões) ligada(s)${r.renomeado ? ', nome atualizado' : ''}${r.documento_cadastrado ? `, ${tipoDoc} na ficha` : ''}.`,
      )
    } catch (e) {
      avisos.erro(e)
    }
  }

  return (
    <li className="rounded-entrada border border-borda bg-entrada/60 p-4" data-teste="pendente-afd" data-documento={p.cpf ?? p.pis ?? ''}>
      <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="font-semibold break-words text-creme">{p.nome ?? '(sem nome no AFD)'}</p>
          <p className="numero text-xs text-lavanda">
            {tipoDoc} {formatarDocumento(p.cpf ?? p.pis, p.cpf ? 'cpf' : 'pis')}
          </p>
        </div>
        <Selo tom={p.quantidade ? 'alerta' : 'neutro'}>
          {p.quantidade} marcação(ões){p.primeira ? ` · ${periodoTexto(p.primeira, p.ultima)}` : ''}
        </Selo>
      </div>
      <Campo rotulo="Funcionário" htmlFor={`${id}-f`}>
        <Selecao
          id={`${id}-f`}
          aria-label={`Funcionário para ${p.nome ?? p.cpf ?? p.pis}`}
          value={funcionarioId}
          onChange={(e) => {
            setFuncionarioId(e.target.value)
            setRenomear(null)
            setDocumento(null)
          }}
        >
          <option value="">— escolha —</option>
          {opcoes.map((o) => (
            <option key={o.f.id} value={o.f.id}>
              {rotuloFuncionario(o.f, o.provisorio)}
            </option>
          ))}
        </Selecao>
      </Campo>
      {escolhido && (
        <div className="mt-3 flex flex-col gap-2">
          {nome && normalizar(nome) !== normalizar(escolhido.f.nome) && (
            <Caixa rotulo={`Renomear “${escolhido.f.nome}” para “${nome}”`} marcado={renomearEfetivo} aoMudar={setRenomear} />
          )}
          {(p.cpf ? escolhido.f.cpf !== p.cpf : escolhido.f.pis !== p.pis) && (
            <Caixa
              rotulo={`Cadastrar o ${tipoDoc} na ficha${(p.cpf ? escolhido.f.cpf : escolhido.f.pis) ? ' (substitui o atual)' : ''}`}
              marcado={documentoEfetivo}
              aoMudar={setDocumento}
            />
          )}
        </div>
      )}
      <div className="mt-3 flex justify-end">
        <Botao onClick={salvar} carregando={ligar.isPending} disabled={!escolhido} icone={<Link2 aria-hidden />}>
          Ligar
        </Botao>
      </div>
    </li>
  )
}
