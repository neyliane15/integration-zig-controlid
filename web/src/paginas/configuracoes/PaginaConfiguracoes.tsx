/** /configuracoes — dados da empresa, fuso, virada, comissão e regras do ponto (A M editam; G vê). Dono: frontend-1. */
import { useState, type FormEvent } from 'react'
import type { Empresa } from '@/tipos/banco'
import { Botao, CabecalhoPagina, Campo, Cartao, Carregando, Entrada, EntradaHora, Interruptor, Selecao } from '@/componentes/ui'
import { useAvisos } from '@/componentes/avisos'
import { formatarCnpj, limparCnpj, useAtualizarEmpresa } from '@/consultas/empresas'
import { useAtualizarMeuPerfil } from '@/consultas/usuarios'
import { podeAdministrar } from '@/lib/permissoes'
import { useEmpresaAtual, usePerfil } from '@/lib/sessao'

const FUSOS_BRASIL: { id: string; rotulo: string }[] = [
  { id: 'America/Sao_Paulo', rotulo: 'Brasília (SP, RJ, MG, Sul, GO, DF, BA…)' },
  { id: 'America/Fortaleza', rotulo: 'Fortaleza (CE, MA, PI, RN, PB)' },
  { id: 'America/Recife', rotulo: 'Recife (PE)' },
  { id: 'America/Maceio', rotulo: 'Maceió (AL, SE)' },
  { id: 'America/Bahia', rotulo: 'Salvador (BA)' },
  { id: 'America/Belem', rotulo: 'Belém (PA, AP)' },
  { id: 'America/Araguaina', rotulo: 'Araguaína (TO)' },
  { id: 'America/Cuiaba', rotulo: 'Cuiabá (MT)' },
  { id: 'America/Campo_Grande', rotulo: 'Campo Grande (MS)' },
  { id: 'America/Porto_Velho', rotulo: 'Porto Velho (RO)' },
  { id: 'America/Boa_Vista', rotulo: 'Boa Vista (RR)' },
  { id: 'America/Manaus', rotulo: 'Manaus (AM)' },
  { id: 'America/Rio_Branco', rotulo: 'Rio Branco (AC)' },
  { id: 'America/Noronha', rotulo: 'Fernando de Noronha' },
]

const UFS = 'AC AL AM AP BA CE DF ES GO MA MG MS MT PA PB PE PI PR RJ RN RO RR RS SC SE SP TO'.split(' ')

export function PaginaConfiguracoes() {
  const perfil = usePerfil()
  const { empresa } = useEmpresaAtual()
  return (
    <div className="surgir">
      <CabecalhoPagina
        sobrancelha="Ajustes"
        titulo={
          <>
            Configura<span className="titulo-italico">ções</span>
          </>
        }
        subtitulo="Como o seu estabelecimento funciona: dia de trabalho, comissão e regras do ponto."
      />
      <div className="flex flex-col gap-5">
        {empresa ? <FormularioEmpresa key={empresa.atualizado_em} empresa={empresa} editavel={podeAdministrar(perfil.papel)} /> : <Carregando />}
        <MeuPerfil />
      </div>
    </div>
  )
}

function FormularioEmpresa({ empresa, editavel }: { empresa: Empresa; editavel: boolean }) {
  const avisos = useAvisos()
  const atualizar = useAtualizarEmpresa()
  const [f, setF] = useState({
    nome: empresa.nome,
    cnpj: empresa.cnpj ? formatarCnpj(empresa.cnpj) : '',
    telefone: empresa.telefone ?? '',
    cidade: empresa.cidade ?? '',
    uf: empresa.uf ?? '',
    fuso: empresa.fuso,
    virada_dia: empresa.virada_dia.slice(0, 5),
    retencao: String(empresa.comissao_percentual_retencao).replace('.', ','),
    alarmeAtraso: empresa.ponto_alarme_atraso,
    janela: String(empresa.ponto_janela_duplicada_minutos),
  })
  const [erro, setErro] = useState<string | null>(null)
  const mudar = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF((a) => ({ ...a, [k]: v }))
  const ro = !editavel

  function salvar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (!f.nome.trim()) return setErro('Informe o nome')
    const cnpj = limparCnpj(f.cnpj)
    if (cnpj && cnpj.length !== 14) return setErro('O CNPJ deve ter 14 dígitos.')
    const retencao = Number(f.retencao.replace(',', '.'))
    if (!Number.isFinite(retencao) || retencao < 0 || retencao > 100) return setErro('Retenção: de 0 a 100%.')
    const janela = Number(f.janela)
    if (!Number.isInteger(janela) || janela < 0 || janela > 30) return setErro('Janela de duplicidade: de 0 a 30 minutos.')
    if (!/^\d{2}:\d{2}$/.test(f.virada_dia)) return setErro('Informe a virada do dia (HH:MM).')
    atualizar.mutate(
      {
        id: empresa.id,
        dados: {
          nome: f.nome.trim(),
          cnpj,
          telefone: f.telefone.trim() || null,
          cidade: f.cidade.trim() || null,
          uf: f.uf || null,
          fuso: f.fuso,
          virada_dia: f.virada_dia,
          comissao_percentual_retencao: retencao,
          ponto_alarme_atraso: f.alarmeAtraso,
          ponto_janela_duplicada_minutos: janela,
        },
      },
      { onSuccess: () => avisos.sucesso('Configurações salvas.'), onError: avisos.erro },
    )
  }

  const fusos = FUSOS_BRASIL.some((z) => z.id === f.fuso) ? FUSOS_BRASIL : [{ id: f.fuso, rotulo: f.fuso }, ...FUSOS_BRASIL]

  return (
    <form onSubmit={salvar} noValidate className="flex flex-col gap-5">
      {erro && (
        <p role="alert" className="rounded-entrada border border-perigo/40 bg-perigo/10 px-4 py-3 text-sm text-creme">
          {erro}
        </p>
      )}
      {ro && <p className="text-sm text-lavanda">Somente o administrador altera estas configurações.</p>}

      <Cartao sobrancelha="Estabelecimento" titulo="Dados da empresa">
        <div className="grid gap-5 sm:grid-cols-2">
          <Campo rotulo="Nome" htmlFor="cfg-nome" obrigatorio>
            <Entrada id="cfg-nome" value={f.nome} onChange={(e) => mudar('nome', e.target.value)} disabled={ro} />
          </Campo>
          <Campo rotulo="CNPJ" htmlFor="cfg-cnpj">
            <Entrada id="cfg-cnpj" inputMode="numeric" value={f.cnpj} onChange={(e) => mudar('cnpj', e.target.value)} disabled={ro} />
          </Campo>
          <Campo rotulo="Telefone" htmlFor="cfg-tel">
            <Entrada id="cfg-tel" type="tel" value={f.telefone} onChange={(e) => mudar('telefone', e.target.value)} disabled={ro} />
          </Campo>
          <div className="grid grid-cols-[1fr_96px] gap-3">
            <Campo rotulo="Cidade" htmlFor="cfg-cidade">
              <Entrada id="cfg-cidade" value={f.cidade} onChange={(e) => mudar('cidade', e.target.value)} disabled={ro} />
            </Campo>
            <Campo rotulo="UF" htmlFor="cfg-uf">
              <Selecao id="cfg-uf" value={f.uf} onChange={(e) => mudar('uf', e.target.value)} disabled={ro}>
                <option value="">—</option>
                {UFS.map((u) => (
                  <option key={u}>{u}</option>
                ))}
              </Selecao>
            </Campo>
          </div>
        </div>
      </Cartao>

      <Cartao sobrancelha="Tempo" titulo="Fuso e dia de trabalho">
        <div className="grid gap-5 sm:grid-cols-2">
          <Campo rotulo="Fuso horário" htmlFor="cfg-fuso">
            <Selecao id="cfg-fuso" value={f.fuso} onChange={(e) => mudar('fuso', e.target.value)} disabled={ro}>
              {fusos.map((z) => (
                <option key={z.id} value={z.id}>
                  {z.rotulo}
                </option>
              ))}
            </Selecao>
          </Campo>
          <Campo
            rotulo="Virada do dia"
            htmlFor="cfg-virada"
            ajuda="Batidas antes deste horário contam no dia anterior (ex.: 05:00 — quem sai à 01:30 de domingo fecha o sábado)."
          >
            {ro ? (
              <Entrada id="cfg-virada" value={f.virada_dia} disabled />
            ) : (
              <EntradaHora id="cfg-virada" valor={f.virada_dia} aoMudar={(v) => mudar('virada_dia', v ?? '')} />
            )}
          </Campo>
        </div>
      </Cartao>

      <Cartao sobrancelha="Regras" titulo="Comissão e ponto">
        <div className="grid gap-5 sm:grid-cols-2">
          <Campo rotulo="Retenção do serviço (%)" htmlFor="cfg-ret" ajuda="Parte do serviço (10%) que fica com a casa antes do rateio. Padrão: 20%.">
            <Entrada id="cfg-ret" inputMode="decimal" className="numero" value={f.retencao} onChange={(e) => mudar('retencao', e.target.value)} disabled={ro} />
          </Campo>
          <Campo rotulo="Janela de batida duplicada (min)" htmlFor="cfg-jan" ajuda="Batidas do mesmo funcionário dentro desta janela contam uma vez só.">
            <Entrada
              id="cfg-jan"
              type="number"
              min={0}
              max={30}
              inputMode="numeric"
              className="numero"
              value={f.janela}
              onChange={(e) => mudar('janela', e.target.value)}
              disabled={ro}
            />
          </Campo>
        </div>
        <div className="mt-5">
          <Interruptor rotulo="Gerar alarme de atraso na entrada" marcado={f.alarmeAtraso} aoMudar={(v) => mudar('alarmeAtraso', v)} desabilitado={ro} />
        </div>
      </Cartao>

      {editavel && (
        <div className="flex justify-end">
          <Botao type="submit" tamanho="g" carregando={atualizar.isPending}>
            Salvar configurações
          </Botao>
        </div>
      )}
    </form>
  )
}

function MeuPerfil() {
  const perfil = usePerfil()
  const atualizar = useAtualizarMeuPerfil()
  const avisos = useAvisos()
  const [nome, setNome] = useState(perfil.nome)
  return (
    <Cartao sobrancelha="Você" titulo="Meu perfil">
      <form
        className="grid items-end gap-4 sm:grid-cols-[1fr_1fr_auto]"
        onSubmit={(e) => {
          e.preventDefault()
          if (!nome.trim()) return avisos.erro('Informe o nome')
          atualizar.mutate(nome.trim(), { onSuccess: () => avisos.sucesso('Nome atualizado.'), onError: avisos.erro })
        }}
      >
        <Campo rotulo="Nome" htmlFor="perfil-nome">
          <Entrada id="perfil-nome" value={nome} onChange={(e) => setNome(e.target.value)} />
        </Campo>
        <Campo rotulo="E-mail" htmlFor="perfil-email">
          <Entrada id="perfil-email" value={perfil.email} disabled />
        </Campo>
        <Botao type="submit" variante="secundario" carregando={atualizar.isPending} disabled={nome.trim() === perfil.nome}>
          Salvar nome
        </Botao>
      </form>
    </Cartao>
  )
}
