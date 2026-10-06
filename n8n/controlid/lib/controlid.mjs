// Control iD — funções puras usadas pelos workflows "MDG · Control iD · …" (contrato §11.1, §11.3, §11.4, §12.2–12.4).
// Sem import: este arquivo é copiado (sem as palavras-chave de módulo) para os nós Code (convenção `// @lib` de docs/DIVISAO.md).
// O acesso à rede é injetado: `http({ metodo, url, corpo, corpoBinario, tipoConteudo, timeoutMs, texto }) → { status, corpo }`.
// No N8N o adaptador é `adaptadorHttpN8n(this.helpers)`; nos testes, um adaptador com fetch.

const CONTROLID_PADROES = {
  tentativas: 3, // contrato §12.2: 3 tentativas, 10 s, para Control iD
  esperaMs: 10000,
  timeoutMs: 30000,
  tamanhoPagina: 1000,
  maxPaginas: 200,
  tamanhoLote: 1000, // contrato §12.4: lotes de ≤ 1000 para ingestao_controlid_batidas
  fuso: 'America/Sao_Paulo',
  viradaDia: '05:00',
};

const CONTROLID_DIA_MS = 86400000;

// ----------------------------------------------------------------------------------------------- utilitários

export function vazioParaNulo(valor) {
  if (valor === undefined || valor === null) return null;
  const t = String(valor).trim();
  return t === '' ? null : t;
}

export function somenteDigitos(valor) {
  if (valor === undefined || valor === null) return '';
  return String(valor).replace(/\D+/g, '');
}

// CPF/PIS → 11 dígitos (zeros à esquerda recompostos; aceita número, pontuação e 12 posições do AFD) ou null.
export function normalizarDocumento(valor) {
  let d = somenteDigitos(valor);
  if (!d) return null;
  if (d.length > 11) {
    if (!/^0+$/.test(d.slice(0, d.length - 11))) return null;
    d = d.slice(-11);
  }
  d = d.padStart(11, '0');
  return /^0+$/.test(d) ? null : d;
}

export function normalizarUrl(url) {
  let u = String(url ?? '').trim();
  if (!u) return '';
  if (!/^https?:\/\//i.test(u)) u = 'http://' + u;
  return u.replace(/\/+$/, '');
}

export function mensagemDeErro(erro) {
  if (erro === undefined || erro === null) return 'Erro desconhecido';
  if (typeof erro === 'string') return erro;
  if (erro.message && typeof erro.message === 'string') {
    const desc = erro.description && typeof erro.description === 'string' && erro.description !== erro.message
      ? ' — ' + erro.description : '';
    return erro.message + desc;
  }
  if (erro.error) return mensagemDeErro(erro.error);
  try {
    return JSON.stringify(erro).slice(0, 500);
  } catch (e) {
    return String(erro);
  }
}

export function cortar(texto, limite) {
  const t = String(texto ?? '');
  const l = limite || 1000;
  return t.length > l ? t.slice(0, l - 1) + '…' : t;
}

// Resposta de RPC escalar do PostgREST (uuid) pode chegar como string, {data: "…"} ou {<nome_da_rpc>: "…"}.
export function extrairUuid(valor) {
  const re = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (typeof valor === 'string') return re.test(valor.trim()) ? valor.trim() : null;
  if (valor && typeof valor === 'object') {
    for (const v of Object.values(valor)) {
      if (typeof v === 'string' && re.test(v.trim())) return v.trim();
    }
  }
  return null;
}

export function comoTexto(corpo) {
  if (corpo === undefined || corpo === null) return '';
  if (typeof corpo === 'string') return corpo;
  if (typeof corpo === 'object' && typeof corpo.byteLength === 'number' && typeof TextDecoder !== 'undefined') {
    try {
      return new TextDecoder('utf-8').decode(corpo);
    } catch (e) {
      return String(corpo);
    }
  }
  if (typeof corpo === 'object') return JSON.stringify(corpo);
  return String(corpo);
}

// Objeto JSON da resposta; null se vazio; undefined se não for JSON.
export function lerJson(corpo) {
  if (corpo === undefined || corpo === null) return null;
  if (typeof corpo === 'object' && typeof corpo.byteLength !== 'number') return corpo;
  const t = comoTexto(corpo).trim();
  if (t === '') return null;
  try {
    return JSON.parse(t);
  } catch (e) {
    return undefined;
  }
}

export function deduplicarPor(lista, chave) {
  const vistos = new Set();
  const saida = [];
  for (const x of lista || []) {
    if (!x) continue;
    const k = typeof chave === 'function' ? chave(x) : x[chave];
    if (k === undefined || k === null) continue;
    const s = String(k);
    if (vistos.has(s)) continue;
    vistos.add(s);
    saida.push(x);
  }
  return saida;
}

export function emLotesDe(lista, tamanho) {
  const t = Math.max(1, Math.floor(tamanho || 1000));
  const lotes = [];
  for (let i = 0; i < (lista || []).length; i += t) lotes.push(lista.slice(i, i + t));
  return lotes;
}

// ------------------------------------------------------------------------------------------- datas e fuso

export function dataMaisDias(data, dias) {
  const [a, m, d] = String(data).slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d) + dias * CONTROLID_DIA_MS).toISOString().slice(0, 10);
}

export function partesNoFuso(ms, fuso) {
  const f = new Intl.DateTimeFormat('en-US', {
    timeZone: fuso, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const p = {};
  for (const x of f.formatToParts(new Date(ms))) p[x.type] = x.value;
  return {
    ano: Number(p.year), mes: Number(p.month), dia: Number(p.day),
    hora: Number(p.hour) % 24, minuto: Number(p.minute), segundo: Number(p.second),
  };
}

// Hora de parede no fuso, "carimbada" como se fosse UTC (é assim que o equipamento de acesso grava `time`).
export function paredeComoUtcMs(ms, fuso) {
  const p = partesNoFuso(ms, fuso);
  return Date.UTC(p.ano, p.mes - 1, p.dia, p.hora, p.minuto, p.segundo);
}

export function deslocamentoMs(ms, fuso) {
  return paredeComoUtcMs(ms, fuso) - Math.floor(ms / 1000) * 1000;
}

// Instante (ms UTC) da hora de parede informada no fuso.
export function localParaUtcMs(ano, mes, dia, hora, minuto, segundo, fuso) {
  const parede = Date.UTC(ano, mes - 1, dia, hora || 0, minuto || 0, segundo || 0);
  const t1 = parede - deslocamentoMs(parede, fuso);
  return parede - deslocamentoMs(t1, fuso);
}

export function hojeNoFuso(fuso, agoraMs) {
  const p = partesNoFuso(agoraMs === undefined ? Date.now() : agoraMs, fuso);
  return `${p.ano}-${String(p.mes).padStart(2, '0')}-${String(p.dia).padStart(2, '0')}`;
}

// Unix (s) de "data hora" (hora local da empresa) no referencial do relógio do equipamento.
//   horaLocal = true  → hora de parede tratada como UTC (relogio_em_hora_local)
//   horaLocal = false → instante real
export function unixDoDia(data, hora, fuso, horaLocal) {
  const [a, m, d] = String(data).slice(0, 10).split('-').map(Number);
  const [h, mi, s] = String(hora || '00:00').split(':').map(Number);
  const ms = horaLocal ? Date.UTC(a, m - 1, d, h || 0, mi || 0, s || 0) : localParaUtcMs(a, m, d, h, mi, s, fuso);
  return Math.floor(ms / 1000);
}

// Instante ISO (com fuso) → unix (s) no referencial do equipamento.
export function instanteParaUnix(iso, fuso, horaLocal) {
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return null;
  return Math.floor((horaLocal ? paredeComoUtcMs(ms, fuso) : ms) / 1000);
}

// `time` do access_log → campo de instante do payload de ingestão (§11.4).
export function unixParaInstante(time, horaLocal) {
  const n = Number(time);
  if (!Number.isFinite(n) || n <= 0) return null;
  const iso = new Date(Math.floor(n) * 1000).toISOString().slice(0, 19);
  return horaLocal ? { instante_local: iso } : { instante: iso + 'Z' };
}

// T do contrato §12.4: max(cursor.ultimo_instante − 1 dia, (hoje − dias_retroativos) 00:00); sem cursor, só o segundo.
// Sincronização manual com data_inicio: começa em data_inicio 00:00 (ignora o cursor, para permitir reprocessar).
export function calcularInicioAcesso({ cursor, diaTrabalhoAtual, diasRetroativos, dataInicio, fuso, horaLocal }) {
  const base = dataInicio || dataMaisDias(diaTrabalhoAtual, -(diasRetroativos || 0));
  const piso = unixDoDia(base, '00:00', fuso, horaLocal);
  if (dataInicio) return piso;
  const ultimo = cursor && cursor.ultimo_instante ? Date.parse(cursor.ultimo_instante) : NaN;
  if (!Number.isFinite(ultimo)) return piso;
  const menosUmDia = ultimo - CONTROLID_DIA_MS;
  const ref = Math.floor((horaLocal ? paredeComoUtcMs(menosUmDia, fuso) : menosUmDia) / 1000);
  return Math.max(ref, piso);
}

// Limite superior (exclusivo) quando há data_fim: fim do dia de trabalho data_fim = (data_fim + 1) na virada.
export function calcularFimAcesso({ dataFim, viradaDia, fuso, horaLocal }) {
  if (!dataFim) return null;
  return unixDoDia(dataMaisDias(dataFim, 1), viradaDia || CONTROLID_PADROES.viradaDia, fuso, horaLocal);
}

// ------------------------------------------------------------------------------------- corpos das chamadas

export function corpoLogin(login, senha) {
  return { login: String(login), password: String(senha) };
}

export function corpoUsuariosAcesso(limite, deslocamento) {
  const c = { object: 'users' };
  if (limite) {
    c.limit = limite;
    c.offset = deslocamento || 0;
  }
  return c;
}

export function corpoAccessLogs(inicio, fim, limite, deslocamento) {
  const cond = { '>=': inicio };
  if (fim !== null && fim !== undefined) cond['<'] = fim;
  const c = { object: 'access_logs', where: { access_logs: { time: cond } } };
  if (limite) {
    c.limit = limite;
    c.offset = deslocamento || 0;
  }
  return c;
}

export function corpoUsuariosRep(limite, deslocamento) {
  return limite ? { limit: limite, offset: deslocamento || 0 } : {};
}

// get_afd.fcgi: {initial_nsr: ultimo_nsr + 1} ou {initial_date: {day, month, year}} (hoje − dias_retroativos, ou data_inicio).
export function corpoAfd({ cursor, diaTrabalhoAtual, diasRetroativos, dataInicio }) {
  if (!dataInicio) {
    const nsr = Number(cursor && cursor.ultimo_nsr);
    if (Number.isInteger(nsr) && nsr > 0) return { initial_nsr: nsr + 1 };
  }
  const d = dataInicio || dataMaisDias(diaTrabalhoAtual, -(diasRetroativos || 0));
  const [ano, mes, dia] = d.split('-').map(Number);
  return { initial_date: { day: dia, month: mes, year: ano } };
}

// --------------------------------------------------------------------------------------------- mapeamentos

export function mapearAccessLog(log, horaLocal) {
  if (!log || log.id === undefined || log.id === null) return null;
  const instante = unixParaInstante(log.time, horaLocal);
  if (!instante) return null;
  const b = {
    id_externo: String(log.id),
    user_id: log.user_id === undefined || log.user_id === null ? '' : String(log.user_id),
  };
  if (log.event !== undefined && log.event !== null && Number.isFinite(Number(log.event))) b.evento = Number(log.event);
  return Object.assign(b, instante);
}

export function mapearUsuarioAcesso(u) {
  if (!u || u.id === undefined || u.id === null || String(u.id).trim() === '') return null;
  return {
    id: String(u.id),
    registration: vazioParaNulo(u.registration),
    name: vazioParaNulo(u.name),
    cpf: normalizarDocumento(u.cpf),
    pis: normalizarDocumento(u.pis),
  };
}

// REP: id = CPF (Portaria 671) ou PIS (legado), conforme parametros.identificador.
export function mapearUsuarioRep(u, identificador) {
  if (!u) return null;
  const cpf = normalizarDocumento(u.cpf);
  const pis = normalizarDocumento(u.pis);
  const id = identificador === 'pis' ? pis : cpf;
  if (!id) return null;
  return { id, registration: vazioParaNulo(u.registration), name: vazioParaNulo(u.name), cpf, pis };
}

// ------------------------------------------------------------------------------------------- configuração

function inteiroEntre(valor, padrao, minimo, maximo) {
  const n = Number(valor);
  if (!Number.isFinite(n)) return padrao;
  return Math.min(maximo, Math.max(minimo, Math.floor(n)));
}

// Valida e normaliza a saída de ingestao_integracao_config (§10.2). Lança erro com mensagem em português.
export function lerConfig(config, agoraMs) {
  if (!config || typeof config !== 'object') throw new Error('Configuração da integração não recebida');
  if (config.error) throw new Error('Falha ao ler a configuração da integração: ' + mensagemDeErro(config.error));
  const tipo = config.tipo;
  if (tipo !== 'controlid_acesso' && tipo !== 'controlid_rep') throw new Error('Tipo de integração incompatível');
  if (config.ativa === false) throw new Error('Integração inativa');
  const p = config.parametros || {};
  const s = config.segredos || {};
  const url = normalizarUrl(s.url);
  if (!url) throw new Error('Informe a URL do equipamento nos segredos da integração');
  if (!s.login || s.senha === undefined || s.senha === null || s.senha === '') {
    throw new Error('Informe o login e a senha do equipamento nos segredos da integração');
  }
  const fuso = config.fuso || CONTROLID_PADROES.fuso;
  return {
    integracaoId: config.integracao_id || null,
    empresaId: config.empresa_id || null,
    tipo,
    nome: config.nome || '',
    url,
    login: String(s.login),
    senha: String(s.senha),
    fuso,
    viradaDia: String(config.virada_dia || CONTROLID_PADROES.viradaDia).slice(0, 8),
    diaTrabalhoAtual: config.dia_trabalho_atual || hojeNoFuso(fuso, agoraMs),
    cursor: config.cursor && typeof config.cursor === 'object' ? config.cursor : {},
    modelo: p.modelo || null,
    diasRetroativos: inteiroEntre(p.dias_retroativos, 2, 0, 31),
    horaLocal: p.relogio_em_hora_local !== false,
    identificador: p.identificador === 'pis' ? 'pis' : 'cpf',
    eventosValidos: Array.isArray(p.eventos_validos) ? p.eventos_validos.map(Number) : [7],
    verificarCertificado: p.verificar_certificado === true,
    tentativas: inteiroEntre(p.tentativas, CONTROLID_PADROES.tentativas, 1, 10),
    esperaMs: inteiroEntre(p.espera_segundos, CONTROLID_PADROES.esperaMs / 1000, 0, 120) * 1000,
    timeoutMs: inteiroEntre(p.timeout_segundos, CONTROLID_PADROES.timeoutMs / 1000, 3, 300) * 1000,
    tamanhoPagina: inteiroEntre(p.tamanho_pagina, CONTROLID_PADROES.tamanhoPagina, 10, 5000),
  };
}

// ----------------------------------------------------------------------------------------- cliente HTTP

function esperarPadrao(ms) {
  return new Promise((ok) => {
    if (typeof setTimeout === 'function' && ms > 0) setTimeout(ok, ms);
    else ok();
  });
}

function erroComStatus(mensagem, status) {
  const e = new Error(mensagem);
  e.status = status;
  return e;
}

export function sessaoExpirou(resposta) {
  if (!resposta) return false;
  if (resposta.status === 401) return true;
  if (resposta.status >= 200 && resposta.status < 500) {
    const b = lerJson(resposta.corpo);
    if (b && typeof b === 'object' && typeof b.error === 'string') {
      return /session|sess[aã]o|not logged|login/i.test(b.error);
    }
  }
  return false;
}

function descreverFalhaRede(e) {
  const codigo = e && (e.code || (e.cause && e.cause.code));
  const msg = mensagemDeErro(e);
  if (/timeout|timed out|ETIMEDOUT|ECONNABORTED|aborted/i.test(String(codigo) + ' ' + msg)) return 'tempo esgotado';
  if (/ECONNREFUSED/.test(String(codigo) + msg)) return 'conexão recusada (equipamento desligado ou porta errada?)';
  if (/EHOSTUNREACH|ENETUNREACH|ENOTFOUND|EAI_AGAIN/.test(String(codigo) + msg)) return 'endereço inalcançável (rede/VPN?)';
  return msg;
}

// Cliente com sessão: login preguiçoso, retentativa em falha de rede/timeout/5xx/429, novo login se a sessão expirar,
// logout garantido por `sair()` (chamado no finally pelos orquestradores).
export function criarCliente({ http, url, login, senha, esperar, tentativas, esperaMs, timeoutMs }) {
  const nTentativas = tentativas || CONTROLID_PADROES.tentativas;
  const espera = esperaMs === undefined ? CONTROLID_PADROES.esperaMs : esperaMs;
  const timeout = timeoutMs || CONTROLID_PADROES.timeoutMs;
  const dormir = esperar || esperarPadrao;
  let sessao = null;
  let maiorTentativa = 1;
  let logins = 0;

  async function bruto(endpoint, req, maxTentativas) {
    let ultimo = '';
    const limite = maxTentativas || nTentativas;
    for (let i = 1; i <= limite; i++) {
      if (i > maiorTentativa) maiorTentativa = i;
      try {
        const r = await http(Object.assign({ metodo: 'POST', timeoutMs: timeout }, req));
        if (r.status >= 500 || r.status === 429 || r.status === 408) {
          ultimo = `HTTP ${r.status} ${cortar(comoTexto(r.corpo), 200)}`;
        } else {
          return r;
        }
      } catch (e) {
        ultimo = descreverFalhaRede(e);
      }
      if (i < limite) await dormir(espera);
    }
    throw erroComStatus(`Equipamento não respondeu em ${endpoint} após ${limite} tentativa(s): ${ultimo}`, 0);
  }

  function urlCom(endpoint, consulta) {
    const q = Object.assign({}, consulta || {}, sessao ? { session: sessao } : {});
    const partes = Object.keys(q).map((k) => encodeURIComponent(k) + '=' + encodeURIComponent(q[k]));
    return url + '/' + endpoint + (partes.length ? '?' + partes.join('&') : '');
  }

  async function entrar() {
    sessao = null;
    logins += 1;
    const r = await bruto('login.fcgi', { url: url + '/login.fcgi', corpo: corpoLogin(login, senha) });
    const b = lerJson(r.corpo);
    if (r.status === 401 || r.status === 403 || (r.status < 300 && b && b.error)) {
      throw erroComStatus('Login recusado pelo equipamento (verifique usuário e senha nos segredos)', r.status);
    }
    if (r.status >= 400) throw erroComStatus(`Login falhou (HTTP ${r.status}): ${cortar(comoTexto(r.corpo), 200)}`, r.status);
    if (!b || !b.session) throw erroComStatus('O equipamento não devolveu sessão no login', r.status);
    sessao = String(b.session);
    return sessao;
  }

  // opcoes: { texto: true } devolve o corpo como texto (AFD); { consulta: {...} } parâmetros extras na URL;
  //         { binario: Uint8Array, tipoConteudo } envia corpo binário; { tentativas: n } sobrepõe as tentativas.
  async function chamar(endpoint, corpo, opcoes) {
    const o = opcoes || {};
    if (!sessao) await entrar();
    const montar = () => ({
      url: urlCom(endpoint, o.consulta),
      corpo: o.binario ? undefined : corpo,
      corpoBinario: o.binario,
      tipoConteudo: o.tipoConteudo,
      texto: !!o.texto,
    });
    let r = await bruto(endpoint, montar(), o.tentativas);
    if (sessaoExpirou(r)) {
      await entrar();
      r = await bruto(endpoint, montar(), o.tentativas);
      if (sessaoExpirou(r)) throw erroComStatus(`Sessão recusada pelo equipamento em ${endpoint} mesmo após novo login`, r.status);
    }
    if (r.status >= 400) {
      const b = lerJson(r.corpo);
      const motivo = b && b.error ? b.error : cortar(comoTexto(r.corpo), 200);
      throw erroComStatus(`Equipamento recusou ${endpoint} (HTTP ${r.status}): ${motivo}`, r.status);
    }
    if (o.texto) {
      const b = lerJson(r.corpo);
      if (b && typeof b === 'object' && !Array.isArray(b)) {
        if (b.error) throw erroComStatus(`Equipamento recusou ${endpoint}: ${b.error}`, r.status);
        for (const k of ['afd', 'AFD', 'data', 'content']) if (typeof b[k] === 'string') return b[k];
      }
      return comoTexto(r.corpo);
    }
    const b = lerJson(r.corpo);
    if (b === undefined) throw erroComStatus(`Resposta inválida (não é JSON) em ${endpoint}`, r.status);
    if (b && typeof b === 'object' && !Array.isArray(b) && b.error) {
      throw erroComStatus(`Equipamento recusou ${endpoint}: ${b.error}`, r.status);
    }
    return b || {};
  }

  async function sair() {
    if (!sessao) return false;
    const s = sessao;
    sessao = null;
    try {
      await http({ metodo: 'POST', url: url + '/logout.fcgi?session=' + encodeURIComponent(s), corpo: {}, timeoutMs: Math.min(timeout, 10000) });
      return true;
    } catch (e) {
      return false;
    }
  }

  return {
    entrar,
    chamar,
    sair,
    get tentativas() {
      return maiorTentativa;
    },
    get logins() {
      return logins;
    },
    get sessao() {
      return sessao;
    },
  };
}

export function clienteDaConfig(http, cfg, esperar) {
  return criarCliente({
    http, url: cfg.url, login: cfg.login, senha: cfg.senha, esperar,
    tentativas: cfg.tentativas, esperaMs: cfg.esperaMs, timeoutMs: cfg.timeoutMs,
  });
}

// Carrega uma lista paginada (limit/offset). Para quando a página vem menor que o limite, quando não traz nada novo
// (equipamento que ignora offset) ou ao atingir maxPaginas. Sem paginação (limite null): uma chamada só.
export async function carregarPaginado(chamar, montarCorpo, chaveLista, opcoes) {
  const o = opcoes || {};
  const limite = o.tamanhoPagina === undefined ? CONTROLID_PADROES.tamanhoPagina : o.tamanhoPagina;
  const maxPaginas = o.maxPaginas || CONTROLID_PADROES.maxPaginas;
  const chave = o.chave || ((x) => (x && x.id !== undefined && x.id !== null ? String(x.id) : JSON.stringify(x)));
  const itens = new Map();
  let paginas = 0;
  for (let offset = 0; paginas < maxPaginas; offset += limite || 0) {
    const resp = await chamar(montarCorpo(limite, offset));
    paginas += 1;
    const lista = resp && Array.isArray(resp[chaveLista]) ? resp[chaveLista] : [];
    let novos = 0;
    for (const x of lista) {
      const k = chave(x);
      if (!itens.has(k)) {
        itens.set(k, x);
        novos += 1;
      }
    }
    if (!limite || lista.length < limite || novos === 0) break;
  }
  return { itens: [...itens.values()], paginas };
}

// Usuários do REP: tenta paginar; se o modelo recusar limit/offset (HTTP 400), repete sem paginação.
async function carregarUsuariosRep(cliente, cfg) {
  try {
    return await carregarPaginado((c) => cliente.chamar('load_users.fcgi', c), corpoUsuariosRep, 'users', {
      tamanhoPagina: cfg.tamanhoPagina,
      chave: (u) => JSON.stringify([u.id, u.cpf, u.pis, u.registration, u.name]),
    });
  } catch (e) {
    if (e && e.status === 400) {
      const r = await cliente.chamar('load_users.fcgi', {});
      return { itens: Array.isArray(r.users) ? r.users : [], paginas: 1 };
    }
    throw e;
  }
}

export async function carregarUsuariosBrutos(cliente, cfg) {
  if (cfg.tipo === 'controlid_acesso') {
    return carregarPaginado((c) => cliente.chamar('load_objects.fcgi', c), corpoUsuariosAcesso, 'users', {
      tamanhoPagina: cfg.tamanhoPagina,
    });
  }
  return carregarUsuariosRep(cliente, cfg);
}

export function mapearUsuarios(brutos, cfg) {
  const mapa = cfg.tipo === 'controlid_acesso' ? mapearUsuarioAcesso : (u) => mapearUsuarioRep(u, cfg.identificador);
  return deduplicarPor(brutos.map(mapa), 'id');
}

// ---------------------------------------------------------------------------------------- orquestradores

// Importar usuários (§11.3, §12.4 passo 2). Nunca devolve lista vazia como sucesso: a ingestão marcaria todos como removidos.
export async function buscarUsuarios({ http, config, esperar, agoraMs }) {
  const res = { etapa: 'equipamento', ok: false, erro: null, tentativas: 1, lidos: 0, ignorados: 0, usuarios: [], detalhes: {} };
  let cliente = null;
  try {
    const cfg = lerConfig(config, agoraMs);
    res.detalhes.tipo = cfg.tipo;
    cliente = clienteDaConfig(http, cfg, esperar);
    const r = await carregarUsuariosBrutos(cliente, cfg);
    res.detalhes.paginas = r.paginas;
    res.lidos = r.itens.length;
    res.usuarios = mapearUsuarios(r.itens, cfg);
    res.ignorados = res.lidos - res.usuarios.length;
    if (res.ignorados && cfg.tipo === 'controlid_rep') {
      res.detalhes.aviso = `${res.ignorados} usuário(s) do REP sem ${cfg.identificador.toUpperCase()} válido foram ignorados`;
    }
    if (res.usuarios.length === 0) {
      throw new Error('O equipamento não devolveu nenhum usuário válido; a lista do sistema não foi alterada');
    }
    res.ok = true;
  } catch (e) {
    res.erro = cortar(mensagemDeErro(e), 1000);
  } finally {
    if (cliente) {
      res.detalhes.logout = await cliente.sair();
      res.tentativas = cliente.tentativas;
    }
  }
  return res;
}

// Importar batidas (§11.4, §12.4 passo 3 / REP passo 3). Acesso → res.batidas; REP → res.afd (texto, lido no nó seguinte).
export async function buscarBatidas({ http, config, entrada, esperar, agoraMs }) {
  const res = {
    etapa: 'equipamento', ok: false, erro: null, origem: null, tentativas: 1, lidos: 0, ignorados: 0,
    batidas: null, afd: null, detalhes: {},
  };
  const ent = entrada || {};
  let cliente = null;
  try {
    const cfg = lerConfig(config, agoraMs);
    res.origem = cfg.tipo;
    cliente = clienteDaConfig(http, cfg, esperar);
    if (cfg.tipo === 'controlid_acesso') {
      const inicio = calcularInicioAcesso({
        cursor: cfg.cursor, diaTrabalhoAtual: cfg.diaTrabalhoAtual, diasRetroativos: cfg.diasRetroativos,
        dataInicio: ent.data_inicio, fuso: cfg.fuso, horaLocal: cfg.horaLocal,
      });
      const fim = calcularFimAcesso({ dataFim: ent.data_fim, viradaDia: cfg.viradaDia, fuso: cfg.fuso, horaLocal: cfg.horaLocal });
      Object.assign(res.detalhes, {
        time_inicio: inicio, time_fim: fim, relogio_em_hora_local: cfg.horaLocal,
        janela_inicio: new Date(inicio * 1000).toISOString().slice(0, 19) + (cfg.horaLocal ? ' (hora local)' : 'Z'),
      });
      await medirRelogio(cliente, cfg, res, agoraMs);
      const r = await carregarPaginado(
        (c) => cliente.chamar('load_objects.fcgi', c),
        (lim, off) => corpoAccessLogs(inicio, fim, lim, off),
        'access_logs',
        { tamanhoPagina: cfg.tamanhoPagina },
      );
      res.detalhes.paginas = r.paginas;
      res.lidos = r.itens.length;
      const batidas = [];
      let foraDaJanela = 0;
      for (const log of r.itens) {
        const t = Number(log && log.time);
        if (Number.isFinite(t) && (t < inicio || (fim !== null && t >= fim))) {
          foraDaJanela += 1; // equipamento que ignora o `where`
          continue;
        }
        const b = mapearAccessLog(log, cfg.horaLocal);
        if (b) batidas.push(b);
      }
      res.batidas = deduplicarPor(batidas, 'id_externo');
      res.ignorados = res.lidos - res.batidas.length;
      if (foraDaJanela) res.detalhes.fora_da_janela = foraDaJanela;
    } else {
      const corpo = corpoAfd({
        cursor: cfg.cursor, diaTrabalhoAtual: cfg.diaTrabalhoAtual, diasRetroativos: cfg.diasRetroativos, dataInicio: ent.data_inicio,
      });
      res.detalhes.afd_pedido = corpo;
      res.afd = await cliente.chamar('get_afd.fcgi', corpo, { texto: true });
      res.detalhes.afd_bytes = res.afd.length;
    }
    res.ok = true;
  } catch (e) {
    res.erro = cortar(mensagemDeErro(e), 1000);
  } finally {
    if (cliente) {
      res.detalhes.logout = await cliente.sair();
      res.tentativas = cliente.tentativas;
    }
  }
  return res;
}

// Melhor esforço: compara o relógio do equipamento (system_information.fcgi → time) com o do N8N. Nunca falha a execução.
async function medirRelogio(cliente, cfg, res, agoraMs) {
  try {
    const info = await cliente.chamar('system_information.fcgi', {}, { tentativas: 1 });
    const t = Number(info && info.time);
    if (!Number.isFinite(t) || t <= 0) return;
    const agora = agoraMs === undefined ? Date.now() : agoraMs;
    const esperado = Math.floor((cfg.horaLocal ? paredeComoUtcMs(agora, cfg.fuso) : agora) / 1000);
    const desvio = t - esperado;
    res.detalhes.relogio_desvio_segundos = desvio;
    if (Math.abs(desvio) > 300) {
      res.detalhes.aviso_relogio = `Relógio do equipamento difere ${Math.round(desvio / 60)} min do servidor (confira data/hora e o parâmetro relogio_em_hora_local)`;
    }
  } catch (e) {
    res.detalhes.relogio_desvio_segundos = null;
  }
}

// ------------------------------------------------------------------------------------- resumo / finalização

function finalizacao(execucaoId, status, lidos, gravados, ignorados, erro, detalhes, tentativas) {
  return {
    p_execucao: execucaoId || null,
    p_status: status,
    p_lidos: lidos || 0,
    p_gravados: gravados || 0,
    p_ignorados: ignorados || 0,
    p_erro: erro ? cortar(erro, 1000) : null,
    p_detalhes: detalhes || {},
    p_tentativas: tentativas || 1,
  };
}

function respostaComErro(r) {
  if (!r || typeof r !== 'object') return 'Resposta vazia do Supabase';
  if (r.error) return mensagemDeErro(r.error);
  if (typeof r.lidos !== 'number') return 'Resposta inesperada do Supabase: ' + cortar(JSON.stringify(r), 200);
  return null;
}

// Junta os resultados de várias finalizações (uma por sync_execucoes) na saída padrão do subfluxo (§12.3).
export function montarSaida(finalizacoes) {
  const fs = (finalizacoes || []).filter(Boolean);
  const status = fs.length === 0 ? 'erro'
    : fs.every((f) => f.p_status === 'sucesso') ? 'sucesso'
      : fs.every((f) => f.p_status === 'erro') ? 'erro' : 'parcial';
  const erros = fs.map((f) => f.p_erro).filter(Boolean);
  return {
    execucao_ids: fs.map((f) => f.p_execucao).filter(Boolean),
    status,
    lidos: fs.reduce((s, f) => s + (f.p_lidos || 0), 0),
    gravados: fs.reduce((s, f) => s + (f.p_gravados || 0), 0),
    ignorados: fs.reduce((s, f) => s + (f.p_ignorados || 0), 0),
    erro: erros.length ? erros.join(' | ') : null,
  };
}

function comSaida(finalizacoes) {
  const saida = montarSaida(finalizacoes);
  return finalizacoes.map((f) => ({ finalizacao: f, saida }));
}

// Usuários: busca = saída de buscarUsuarios (+ execucao_id); resposta = retorno de ingestao_controlid_usuarios ou null.
export function resumirUsuarios({ busca, resposta, execucaoId }) {
  const exec = execucaoId || (busca && busca.execucao_id);
  const det = Object.assign({}, (busca && busca.detalhes) || {});
  if (!busca || !busca.ok) {
    return comSaida([finalizacao(exec, 'erro', busca ? busca.lidos : 0, 0, busca ? busca.ignorados : 0,
      (busca && busca.erro) || 'Falha ao ler o equipamento', det, busca && busca.tentativas)]);
  }
  const erro = respostaComErro(resposta);
  if (erro) {
    return comSaida([finalizacao(exec, 'erro', busca.lidos, 0, busca.ignorados, 'Falha ao gravar usuários: ' + erro, det, busca.tentativas)]);
  }
  for (const k of ['inseridos', 'atualizados', 'removidos', 'vinculados_automaticamente', 'sem_vinculo']) {
    if (resposta[k] !== undefined) det[k] = resposta[k];
  }
  const ignorados = busca.ignorados + (resposta.ignorados || 0);
  return comSaida([finalizacao(exec, 'sucesso', busca.lidos, resposta.gravados || 0, ignorados, null, det, busca.tentativas)]);
}

// Batidas: lotes = itens do nó "AFD · separar lotes"; respostas = retornos de ingestao_controlid_batidas, alinhados aos lotes.
export function resumirBatidas({ busca, lotes, respostas, execucaoId }) {
  const exec = execucaoId || (busca && busca.execucao_id);
  const det = Object.assign({}, (busca && busca.detalhes) || {});
  if (!busca || !busca.ok) {
    return comSaida([finalizacao(exec, 'erro', busca ? busca.lidos : 0, 0, busca ? busca.ignorados : 0,
      (busca && busca.erro) || 'Falha ao ler o equipamento', det, busca && busca.tentativas)]);
  }
  const ls = (lotes || []).filter((l) => l && Array.isArray(l.lote));
  const afd = (lotes || []).map((l) => l && l.afd_resumo).find(Boolean) || null;
  if (afd) det.afd = afd;
  const preIgnorados = (busca.ignorados || 0) + (afd ? afd.ignoradas + (afd.duplicadas || 0) : 0);
  const enviados = ls.reduce((s, l) => s + l.lote.length, 0);
  const lidos = afd ? afd.marcacoes + afd.ignoradas + (afd.duplicadas || 0) : (busca.lidos || 0);
  const soma = { gravados: 0, ignorados: 0, duplicados: 0, sem_funcionario: 0, dias_apurados: 0 };
  const errosLote = [];
  let cursor = null;
  ls.forEach((l, i) => {
    const r = (respostas || [])[i];
    const erro = respostaComErro(r);
    if (erro) {
      errosLote.push({ lote: i + 1, itens: l.lote.length, erro: cortar(erro, 300) });
      return;
    }
    const naoGravados = Math.max((r.ignorados || 0) + (r.duplicados || 0), (r.lidos || 0) - (r.gravados || 0));
    soma.gravados += r.gravados || 0;
    soma.ignorados += naoGravados;
    soma.duplicados += r.duplicados || 0;
    soma.sem_funcionario += r.sem_funcionario || 0;
    soma.dias_apurados += r.dias_apurados || 0;
    if (r.cursor) cursor = r.cursor;
  });
  Object.assign(det, {
    enviados, lotes: ls.length, duplicados: soma.duplicados, sem_funcionario: soma.sem_funcionario,
    dias_apurados: soma.dias_apurados,
  });
  if (cursor) det.cursor = cursor;
  if (errosLote.length) det.erros_lote = errosLote.slice(0, 20);
  const itensComErro = errosLote.reduce((s, e) => s + e.itens, 0);
  const status = errosLote.length === 0 ? 'sucesso' : errosLote.length < ls.length ? 'parcial' : 'erro';
  const erro = errosLote.length ? `${errosLote.length} de ${ls.length} lote(s) falharam: ${errosLote[0].erro}` : null;
  return comSaida([finalizacao(exec, status, lidos, soma.gravados, preIgnorados + soma.ignorados + itensComErro, erro, det, busca.tentativas)]);
}

// ------------------------------------------------------------------------------------------ adaptador N8N

// Adaptador para o nó Code: usa this.helpers.httpRequest do N8N. Sem verificação de certificado por padrão
// (REP iDClass usa HTTPS com certificado autoassinado); ligue com parametros.verificar_certificado = true.
export function adaptadorHttpN8n(helpers, opcoes) {
  const verificar = !!(opcoes && opcoes.verificarCertificado);
  return async function ({ metodo, url, corpo, corpoBinario, tipoConteudo, timeoutMs, texto }) {
    const binario = corpoBinario !== undefined && corpoBinario !== null;
    const pedido = {
      method: metodo || 'POST',
      url,
      headers: { 'Content-Type': binario ? tipoConteudo || 'application/octet-stream' : 'application/json' },
      body: binario ? corpoBinario : corpo === undefined ? undefined : JSON.stringify(corpo),
      json: false,
      timeout: timeoutMs || CONTROLID_PADROES.timeoutMs,
      returnFullResponse: true,
      ignoreHttpStatusErrors: true,
      skipSslCertificateValidation: !verificar,
    };
    if (texto) pedido.encoding = 'text';
    const r = await helpers.httpRequest(pedido);
    return { status: r.statusCode, corpo: r.body };
  };
}
