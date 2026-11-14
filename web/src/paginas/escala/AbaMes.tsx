/**
 * Aba "Escala do mês": grade editável (réplica do modelo do cliente). Clicar na célula e digitar o horário de chegada
 * (8 → 8h, 11:30 → 11h30), `f` folga, `fe` férias, vazio limpa; Enter/↓ desce, ↑ sobe, ←/→ andam. Painel com
 * Folga / Trabalha / Férias / Automático, chegada do dia e troca de folga. Copiar para Excel (TSV).
 */
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
} from "react";
import clsx from "clsx";
import { ChevronLeft, ChevronRight, ClipboardCopy, Repeat } from "lucide-react";
import {
  Botao,
  Cartao,
  Carregando,
  ErroCarga,
  FOCO,
  Selecao,
  Entrada,
  Vazio,
} from "@/componentes/ui";
import { useAvisos } from "@/componentes/avisos";
import type {
  EscalaDiaMembro,
  EscalaMembroMes,
  EscalaMes,
  EscalaSetorMes,
  StatusAjusteEscala,
} from "@/tipos/banco";
import {
  useAjustarDia,
  useEscalaMes,
  useTrocarFolga,
} from "@/consultas/escala";
import {
  DIAS_SEMANA,
  chegadaParaHora,
  horaParaChegada,
  interpretarCelula,
  montarTsv,
  nomeDoMes,
  normT,
  proximaCelula,
  somarMeses,
  statusAutomatico,
  teclaNavega,
  textoCelula,
} from "@/lib/escala";
import { formatarData, somarDias } from "@/lib/formato";

interface Selecionada {
  funcionarioId: string;
  data: string;
}

/** Chegada gravada só para o dia (diferente da padrão). */
function chegadaDoAjuste(
  m: EscalaMembroMes,
  d: EscalaDiaMembro,
): string | null {
  return d.ajustado && d.chegada && d.chegada !== m.chegada_padrao
    ? d.chegada
    : null;
}

/** Texto da célula na grade: F, FÉ ou a chegada do dia quando difere da padrão (a padrão aparece ao lado do nome). */
function textoDaGrade(m: EscalaMembroMes, d: EscalaDiaMembro): string {
  if (d.status === "fora") return "";
  return textoCelula(
    d.status,
    d.status === "trabalha" ? chegadaDoAjuste(m, d) : null,
  );
}

function automatico(
  mes: EscalaMes,
  setor: EscalaSetorMes,
  funcionarioId: string,
  j: number,
): "folga" | "trabalha" {
  const dia = mes.dias[j];
  if (!dia || dia.semana == null) return "trabalha";
  return statusAutomatico(
    funcionarioId,
    dia.semana,
    dia.dia_semana,
    setor,
    mes.fase ?? 0,
  );
}

export function AbaMes({
  mes,
  aoMudarMes,
}: {
  mes: string;
  aoMudarMes(m: string): void;
}) {
  const consulta = useEscalaMes(mes);
  const ajustar = useAjustarDia();
  const avisos = useAvisos();
  const [sel, setSel] = useState<Selecionada | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [tsvManual, setTsvManual] = useState<string | null>(null);
  const areaTsv = useRef<HTMLTextAreaElement>(null);
  const tabela = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setSel(null);
    setMsg(null);
    setTsvManual(null);
  }, [mes]);
  useEffect(() => {
    if (tsvManual != null) areaTsv.current?.select();
  }, [tsvManual]);

  const m = consulta.data;
  const linhas = useMemo(
    () =>
      m
        ? m.setores.flatMap((s) =>
            s.membros.map((x) => ({ setor: s, membro: x })),
          )
        : [],
    [m],
  );
  const editar = !!m?.pode_editar;

  function gravar(
    funcionarioId: string,
    data: string,
    status: StatusAjusteEscala | null,
    chegada: string | null,
  ) {
    ajustar.mutate(
      { anoMes: mes, funcionarioId, data, status, chegada },
      { onError: (e) => avisos.erro(e) },
    );
  }

  function confirmarTexto(
    setor: EscalaSetorMes,
    membro: EscalaMembroMes,
    j: number,
    texto: string,
  ) {
    if (!m) return;
    const d = membro.dias[j];
    if (!d || d.status === "fora") return;
    if (normT(texto) === normT(textoDaGrade(membro, d))) return;
    const auto = automatico(m, setor, membro.funcionario_id, j);
    const r = interpretarCelula(
      texto,
      { folga: auto === "folga", ferias: false },
      membro.chegada_padrao,
    );
    gravar(membro.funcionario_id, d.data, r.estado, r.chegada);
  }

  async function copiar() {
    if (!m) return;
    setTsvManual(null);
    const tsv = montarTsv(
      m.dias.map((d) => ({
        dia: Number(d.data.slice(8)),
        data: d.data,
        semana: d.dia_semana,
        rotulo: DIAS_SEMANA[d.dia_semana]!,
      })),
      m.setores.map((s) => ({
        nome: s.nome,
        linhas: s.membros.map((x) => ({
          nome: x.nome,
          celulas: x.dias.map((d) =>
            d.status === "fora" ? "" : textoCelula(d.status, d.chegada),
          ),
          chegadaPadrao: "",
          folgas: x.folgas,
          ferias: x.ferias,
        })),
      })),
      m.na_escala,
    );
    try {
      await navigator.clipboard.writeText(tsv);
      setMsg("Escala copiada. Cole em uma planilha do Excel ou Google Sheets.");
    } catch {
      setTsvManual(tsv);
      setMsg(
        "Não consegui copiar automaticamente. Copie o texto abaixo (Ctrl+C) e cole na planilha.",
      );
    }
  }

  const selecionado = useMemo(() => {
    if (!sel || !m) return null;
    for (const s of m.setores) {
      const membro = s.membros.find(
        (x) => x.funcionario_id === sel.funcionarioId,
      );
      if (membro) {
        const j = m.dias.findIndex((d) => d.data === sel.data);
        const dia = membro.dias[j];
        if (dia) return { setor: s, membro, dia, j };
      }
    }
    return null;
  }, [sel, m]);

  return (
    <Cartao
      sobrancelha="Escala do mês"
      titulo={nomeDoMes(mes).replace(/^./, (c) => c.toUpperCase())}
      acoes={
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1">
            <Botao
              variante="secundario"
              tamanho="p"
              aria-label="Mês anterior"
              onClick={() => aoMudarMes(somarMeses(mes, -1))}
            >
              <ChevronLeft aria-hidden className="size-4" />
            </Botao>
            <label className="sr-only" htmlFor="escala-mes">
              Mês
            </label>
            <Entrada
              id="escala-mes"
              type="month"
              value={mes}
              onChange={(e) =>
                /^\d{4}-\d{2}$/.test(e.target.value) &&
                aoMudarMes(e.target.value)
              }
              className="h-9! w-[170px]! text-sm!"
            />
            <Botao
              variante="secundario"
              tamanho="p"
              aria-label="Próximo mês"
              onClick={() => aoMudarMes(somarMeses(mes, 1))}
            >
              <ChevronRight aria-hidden className="size-4" />
            </Botao>
          </div>
          <Botao
            tamanho="p"
            icone={<ClipboardCopy aria-hidden />}
            disabled={!m}
            onClick={() => void copiar()}
          >
            Copiar para Excel
          </Botao>
        </div>
      }
    >
      <p className="text-xs leading-relaxed text-lavanda">
        As semanas vão de segunda a domingo e o rodízio é contínuo (não recomeça
        no mês). Quem está de férias aparece como FÉ e não conta em “Na escala”.
        {editar && (
          <>
            {" "}
            Clique na célula e digite o horário de chegada (8 vira 8h, 11:30
            vira 11h30). Digite <b>f</b> para folga e <b>fe</b> para férias;
            deixe vazio para limpar. Enter ou ↓ desce, ↑ sobe e ← → andam para o
            lado. Células com contorno foram ajustadas à mão.
          </>
        )}
      </p>
      {msg && (
        <p role="status" className="mt-2 text-xs font-semibold text-ouro-claro">
          {msg}
        </p>
      )}
      {tsvManual != null && (
        <textarea
          ref={areaTsv}
          readOnly
          aria-label="Escala em texto para copiar"
          value={tsvManual}
          className="mt-2 h-28 w-full rounded-entrada border border-borda bg-entrada p-2 font-mono text-xs text-creme"
        />
      )}

      {consulta.isLoading ? (
        <Carregando texto="Montando o mês…" />
      ) : consulta.error ? (
        <div className="mt-4">
          <ErroCarga
            erro={consulta.error}
            aoTentar={() => void consulta.refetch()}
          />
        </div>
      ) : !m || linhas.length === 0 ? (
        <div className="mt-4">
          <Vazio
            titulo="Ninguém na escala"
            descricao="Adicione pessoas aos setores na aba Equipe."
          />
        </div>
      ) : (
        <>
          <div
            ref={tabela}
            className="mt-3 max-w-full overflow-x-auto rounded-entrada border border-borda"
            data-teste="grade-mes"
            data-hoje={m.hoje}
          >
            <table className="w-max border-separate border-spacing-0 text-[11px]">
              <thead>
                <tr>
                  <th className="sticky left-0 z-20 min-w-[118px] border-b border-borda bg-cartao px-2 py-1.5 text-left text-xs font-semibold text-lavanda">
                    Nome
                  </th>
                  {m.dias.map((d) => (
                    <th
                      key={d.data}
                      scope="col"
                      className={clsx(
                        "min-w-[34px] border-b border-borda px-0 py-1.5 text-center font-semibold text-lavanda",
                        d.dia_semana === 0 && "border-l-2 border-l-borda-forte",
                        d.data === m.hoje && "text-ouro-claro",
                      )}
                    >
                      <span className="numero text-creme">
                        {Number(d.data.slice(8))}
                      </span>
                      <br />
                      <small className="text-[9px] font-medium">
                        {DIAS_SEMANA[d.dia_semana]}
                      </small>
                    </th>
                  ))}
                  <th className="min-w-[52px] border-b border-borda px-1 text-center text-xs font-bold text-ouro-claro">
                    Folgas
                  </th>
                </tr>
              </thead>
              <tbody>
                {m.setores.map((s) => {
                  const inicio = linhas.findIndex((l) => l.setor.id === s.id);
                  return [
                    <tr key={`s-${s.id}`}>
                      <td
                        colSpan={m.dias.length + 2}
                        className="border-b border-borda bg-acento-suave p-0 text-xs font-bold text-ouro-claro"
                      >
                        <span className="sticky left-0 inline-block px-2 py-1.5">
                          {s.nome}
                        </span>
                      </td>
                    </tr>,
                    ...s.membros.map((x, k) => (
                      <LinhaMembro
                        key={x.funcionario_id}
                        membro={x}
                        r={inicio + k}
                        totalLinhas={linhas.length}
                        totalColunas={m.dias.length}
                        editar={editar}
                        limite={{
                          min: somarDias(m.hoje, -62),
                          max: somarDias(m.hoje, 366),
                        }}
                        selecionada={
                          sel?.funcionarioId === x.funcionario_id
                            ? sel.data
                            : null
                        }
                        aoSelecionar={(data) =>
                          setSel({ funcionarioId: x.funcionario_id, data })
                        }
                        aoConfirmar={(j, t) => confirmarTexto(s, x, j, t)}
                        tabela={tabela}
                      />
                    )),
                  ];
                })}
                <tr className="font-bold text-ouro-claro">
                  <td className="sticky left-0 z-10 border-t-2 border-borda bg-cartao px-2 py-1.5 text-xs">
                    Na escala
                  </td>
                  {m.na_escala.map((n, j) => (
                    <td
                      key={j}
                      className={clsx(
                        "numero border-t-2 border-borda bg-cartao py-1.5 text-center",
                        m.dias[j]?.dia_semana === 0 &&
                          "border-l-2 border-l-borda-forte",
                      )}
                    >
                      {n}
                    </td>
                  ))}
                  <td className="border-t-2 border-borda bg-cartao" />
                </tr>
              </tbody>
            </table>
          </div>
          {editar && (
            <PainelDia
              mes={m}
              sel={selecionado}
              ocupado={ajustar.isPending}
              aoGravar={gravar}
            />
          )}
        </>
      )}
    </Cartao>
  );
}

// ------------------------------------------------------------------ linha / célula

function LinhaMembro({
  membro,
  r,
  totalLinhas,
  totalColunas,
  editar,
  limite,
  selecionada,
  aoSelecionar,
  aoConfirmar,
  tabela,
}: {
  membro: EscalaMembroMes;
  limite: { min: string; max: string };
  r: number;
  totalLinhas: number;
  totalColunas: number;
  editar: boolean;
  selecionada: string | null;
  aoSelecionar(data: string): void;
  aoConfirmar(j: number, texto: string): void;
  tabela: React.RefObject<HTMLDivElement | null>;
}) {
  return (
    <tr>
      <td
        className="sticky left-0 z-10 max-w-[190px] min-w-[118px] truncate border-b border-borda bg-cartao px-2 py-1 text-xs font-semibold text-creme"
        title={membro.nome}
      >
        {membro.nome}
        {membro.chegada_padrao && (
          <small className="ml-1 text-[10px] font-semibold text-lavanda">
            {horaParaChegada(membro.chegada_padrao)}
          </small>
        )}
      </td>
      {membro.dias.map((d, j) => (
        <Celula
          key={d.data}
          membro={membro}
          dia={d}
          r={r}
          c={j}
          limites={{ linhas: totalLinhas, colunas: totalColunas }}
          editar={editar && d.data >= limite.min && d.data <= limite.max}
          selecionada={selecionada === d.data}
          aoSelecionar={() => aoSelecionar(d.data)}
          aoConfirmar={(t) => aoConfirmar(j, t)}
          tabela={tabela}
        />
      ))}
      <td
        className="numero border-b border-borda px-1 text-center font-bold text-ouro-claro"
        title={`${membro.ferias} dia(s) de férias`}
      >
        {membro.folgas}
        {membro.ferias > 0 && (
          <small className="ml-0.5 text-[9px] font-medium text-lavanda">
            +{membro.ferias}FÉ
          </small>
        )}
      </td>
    </tr>
  );
}

function Celula({
  membro,
  dia,
  r,
  c,
  limites,
  editar,
  selecionada,
  aoSelecionar,
  aoConfirmar,
  tabela,
}: {
  membro: EscalaMembroMes;
  dia: EscalaDiaMembro;
  r: number;
  c: number;
  limites: { linhas: number; colunas: number };
  editar: boolean;
  selecionada: boolean;
  aoSelecionar(): void;
  aoConfirmar(texto: string): void;
  tabela: React.RefObject<HTMLDivElement | null>;
}) {
  const texto = textoDaGrade(membro, dia);
  const [valor, setValor] = useState(texto);
  useEffect(() => setValor(texto), [texto]);
  /** a tecla de navegação já gravou: o blur que vem em seguida não grava de novo */
  const jaGravou = useRef(false);
  const segunda = new Date(`${dia.data}T12:00:00Z`).getUTCDay() === 1;
  const fora = dia.status === "fora";
  const rotulo = `${membro.nome}, dia ${formatarData(dia.data)}`;

  function tecla(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Escape") {
      setValor(texto);
      jaGravou.current = true;
      e.currentTarget.blur();
      return;
    }
    if (!teclaNavega(e.key)) return;
    const el = e.currentTarget;
    const prox = proximaCelula({ linha: r, coluna: c }, e.key, limites, {
      inicio: el.selectionStart ?? 0,
      fim: el.selectionEnd ?? 0,
      tamanho: el.value.length,
    });
    if (!prox) return;
    e.preventDefault();
    aoConfirmar(el.value);
    const alvo = tabela.current?.querySelector<HTMLInputElement>(
      `input[data-r="${prox.linha}"][data-c="${prox.coluna}"]`,
    );
    if (alvo && alvo !== el) {
      jaGravou.current = true;
      alvo.focus();
    }
  }

  return (
    <td
      className={clsx(
        "border-b border-borda p-0 text-center",
        segunda && "border-l-2 border-l-borda-forte",
        fora && "bg-cartao-2/60",
        dia.status === "folga" && "bg-folga-suave",
        dia.status === "ferias" && "bg-acento-suave",
        dia.ajustado && "shadow-[inset_0_0_0_2px_var(--color-ouro)]",
        selecionada && "outline-2 -outline-offset-2 outline-creme",
      )}
      data-data={dia.data}
      data-status={dia.status}
      data-ajustado={dia.ajustado ? "1" : undefined}
    >
      {fora ? (
        <span className="block py-1 text-lavanda-escuro" title="Fora da escala">
          ·
        </span>
      ) : (
        <input
          value={valor}
          maxLength={6}
          readOnly={!editar}
          data-r={r}
          data-c={c}
          aria-label={rotulo}
          title={dia.motivo ?? undefined}
          onChange={(e) => setValor(e.target.value)}
          onFocus={(e) => {
            aoSelecionar();
            e.currentTarget.select();
          }}
          onClick={aoSelecionar}
          onBlur={(e) => {
            if (jaGravou.current) jaGravou.current = false;
            else if (editar) aoConfirmar(e.currentTarget.value);
          }}
          onKeyDown={editar ? tecla : undefined}
          className={clsx(
            "block w-[34px] rounded-none border-0 bg-transparent px-0 py-1.5 text-center text-[11px] text-creme outline-none",
            "focus:outline-2 focus:-outline-offset-2 focus:outline-ouro",
            dia.status === "folga" && "font-bold text-perigo",
            dia.status === "ferias" && "font-bold text-lavanda",
            !editar && "cursor-default",
          )}
        />
      )}
    </td>
  );
}

// ------------------------------------------------------------------ painel

function PainelDia({
  mes,
  sel,
  ocupado,
  aoGravar,
}: {
  mes: EscalaMes;
  sel: {
    setor: EscalaSetorMes;
    membro: EscalaMembroMes;
    dia: EscalaDiaMembro;
    j: number;
  } | null;
  ocupado: boolean;
  aoGravar(
    funcionarioId: string,
    data: string,
    status: StatusAjusteEscala | null,
    chegada: string | null,
  ): void;
}) {
  const avisos = useAvisos();
  const trocar = useTrocarFolga();
  const [chegada, setChegada] = useState("");
  const [outro, setOutro] = useState("");
  const [outraData, setOutraData] = useState("");
  const chave = sel ? `${sel.membro.funcionario_id}|${sel.dia.data}` : "";
  const chegadaAtual = sel
    ? horaParaChegada(
        chegadaDoAjuste(sel.membro, sel.dia) ?? sel.membro.chegada_padrao,
      )
    : "";
  useEffect(() => {
    setChegada(chegadaAtual);
    setOutro("");
    setOutraData("");
  }, [chave, chegadaAtual]);

  if (!sel) {
    return (
      <div
        className="mt-3 flex min-h-[64px] items-center rounded-entrada bg-acento-suave/60 px-3 text-sm text-lavanda"
        data-teste="painel-dia"
      >
        Clique em uma célula da grade para ver as opções daquela pessoa e dia.
      </div>
    );
  }
  const { membro, dia, setor, j } = sel;
  const ajusteStatus: StatusAjusteEscala | null =
    dia.origem === "ajuste" && dia.status !== "fora" ? dia.status : null;
  const chegadaAj = chegadaDoAjuste(membro, dia);
  const foraLimite =
    dia.data < somarDias(mes.hoje, -62) || dia.data > somarDias(mes.hoje, 366);
  const estado =
    dia.status === "fora"
      ? "Fora da escala (antes da data-âncora ou fora do vínculo)"
      : foraLimite
        ? "Fora do limite de ajuste (hoje − 62 a hoje + 366 dias)"
        : ajusteStatus === "folga"
          ? "Folga ajustada"
          : ajusteStatus === "trabalha"
            ? "Trabalha (ajustado)"
            : ajusteStatus === "ferias"
              ? "Férias ajustadas"
              : `Automático (${dia.status === "folga" ? "folga" : "trabalha"})`;
  const semana = DIAS_SEMANA[mes.dias[j]?.dia_semana ?? 0];
  const fora = dia.status === "fora" || foraLimite;
  const outros = mes.setores.flatMap((s) =>
    s.membros
      .filter((x) => x.funcionario_id !== membro.funcionario_id)
      .map((x) => ({ s, x })),
  );

  function aplicarChegada() {
    const v = normT(chegada);
    const hora = chegadaParaHora(v);
    const nova = hora && hora !== membro.chegada_padrao ? hora : null;
    if (nova === chegadaAj) return;
    aoGravar(membro.funcionario_id, dia.data, ajusteStatus, nova);
  }

  async function fazerTroca() {
    if (!outro && !outraData) {
      avisos.erro(new Error("Informe o outro funcionário ou o outro dia"));
      return;
    }
    try {
      await trocar.mutateAsync({
        funcionarioA: membro.funcionario_id,
        dataA: dia.data,
        funcionarioB: outro || null,
        dataB: outraData || null,
      });
      avisos.sucesso("Folga trocada.");
      setOutro("");
      setOutraData("");
    } catch (e) {
      avisos.erro(e);
    }
  }

  const botao = (
    rotulo: string,
    status: StatusAjusteEscala | null,
    ativo: boolean,
  ) => (
    <button
      type="button"
      disabled={fora || ocupado}
      aria-pressed={ativo}
      onClick={() =>
        aoGravar(membro.funcionario_id, dia.data, status, chegadaAj)
      }
      className={clsx(
        "min-h-8 rounded-pilula border px-3 text-[13px] font-semibold transition-colors disabled:opacity-60",
        FOCO,
        ativo
          ? "border-ouro bg-ouro text-tinta-ouro"
          : "border-borda bg-cartao text-creme hover:border-borda-forte",
      )}
    >
      {rotulo}
    </button>
  );

  return (
    <div
      className="mt-3 rounded-entrada bg-acento-suave p-3 text-sm"
      data-teste="painel-dia"
      aria-live="polite"
    >
      <p className="text-creme">
        <b>{membro.nome}</b> · {setor.nome} · dia {Number(dia.data.slice(8))} (
        {semana}) · <span data-teste="estado-dia">{estado}</span>
        {dia.motivo && <span className="text-lavanda"> · {dia.motivo}</span>}
      </p>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        {botao("Folga", "folga", ajusteStatus === "folga")}
        {botao("Trabalha", "trabalha", ajusteStatus === "trabalha")}
        {botao("Férias", "ferias", ajusteStatus === "ferias")}
        {botao("Automático", null, !ajusteStatus && !fora)}
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <label
          className="flex items-center gap-2 text-[13px] text-creme"
          htmlFor="escala-chegada-dia"
        >
          Chegada neste dia
        </label>
        <Entrada
          id="escala-chegada-dia"
          value={chegada}
          maxLength={6}
          placeholder="ex.: 8"
          disabled={fora}
          onChange={(e) => setChegada(e.target.value)}
          onBlur={aplicarChegada}
          onKeyDown={(e) => e.key === "Enter" && aplicarChegada()}
          className="h-8! w-[90px]! text-sm!"
        />
        <Botao
          variante="secundario"
          tamanho="p"
          disabled={fora || !chegadaAj}
          onClick={() =>
            aoGravar(membro.funcionario_id, dia.data, ajusteStatus, null)
          }
        >
          Usar horário padrão
        </Botao>
      </div>
      <div className="mt-3 flex flex-wrap items-end gap-2 border-t border-borda pt-3">
        <label className="flex flex-col gap-1 text-xs text-lavanda">
          Trocar folga com
          <Selecao
            value={outro}
            onChange={(e) => setOutro(e.target.value)}
            disabled={fora}
            className="h-8! min-w-[180px]! text-sm!"
          >
            <option value="">(ninguém — só mudar o dia)</option>
            {outros.map(({ s, x }) => (
              <option key={x.funcionario_id} value={x.funcionario_id}>
                {x.nome} · {s.nome}
              </option>
            ))}
          </Selecao>
        </label>
        <label className="flex flex-col gap-1 text-xs text-lavanda">
          e/ou outro dia
          <Entrada
            type="date"
            value={outraData}
            min={mes.inicio}
            max={mes.fim}
            disabled={fora}
            onChange={(e) => setOutraData(e.target.value)}
            className="h-8! w-[150px]! text-sm!"
          />
        </label>
        <Botao
          variante="secundario"
          tamanho="p"
          icone={<Repeat aria-hidden />}
          carregando={trocar.isPending}
          disabled={fora}
          onClick={() => void fazerTroca()}
        >
          Trocar folga
        </Botao>
      </div>
      <p className="mt-1.5 text-xs text-lavanda">
        Com outra pessoa: as duas trocam o que fazem neste dia (e no outro dia,
        se informado). Sem pessoa: a folga muda para o outro dia.
      </p>
    </div>
  );
}
