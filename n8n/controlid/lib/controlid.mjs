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

// ================================================================================================
// ENVIO sistema → equipamento (docs/CONTRATO-ADENDO-envio-controlid.md, A.5). Nunca envia batidas.
// Entrada: retorno de ingestao_controlid_envios_pendentes; saída: um resultado por item para
// ingestao_controlid_envio_resultado. Cada item é tratado isoladamente (erro de um não para os outros)
// e calcula a diferença contra o que já está no equipamento, então reenviar o mesmo item não causa dano.
// ================================================================================================

const CONTROLID_DIAS_SEMANA = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']; // 0 = domingo (igual ao banco)
const CONTROLID_PREFIXO_HORARIO = 'MDG ';
const CONTROLID_FOTO_MAX_BYTES = 2 * 1024 * 1024;
const CONTROLID_NOME_REP_MAX = 52;

export function segundosDoDia(hora) {
  const m = /^([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?/.exec(String(hora ?? ''));
  if (!m) return null;
  const s = Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3] || 0);
  return Math.min(86399, Math.max(0, s));
}

// Faixas semanais → time_spans (segundos do dia + flags sun..sat). Faixas com o mesmo início/fim viram um span só.
// Feriados (hol1..hol3) ficam 0: nos feriados cadastrados no equipamento a faixa não libera.
export function faixasParaTimeSpans(faixas, timeZoneId) {
  const grupos = new Map();
  for (const f of faixas || []) {
    const ini = Number.isFinite(f.inicio_segundos) ? f.inicio_segundos : segundosDoDia(f.inicio);
    const fim = Number.isFinite(f.fim_segundos) ? f.fim_segundos : segundosDoDia(f.fim);
    const dia = Number(f.dia_semana);
    if (!Number.isInteger(dia) || dia < 0 || dia > 6 || ini === null || fim === null || fim <= ini) {
      throw new Error(`Faixa de horário inválida (dia ${f.dia_semana}, ${f.inicio}–${f.fim})`);
    }
    const chave = ini + '-' + fim;
    if (!grupos.has(chave)) {
      const span = { time_zone_id: timeZoneId, start: ini, end: fim };
      for (const d of CONTROLID_DIAS_SEMANA) span[d] = 0;
      span.hol1 = 0;
      span.hol2 = 0;
      span.hol3 = 0;
      grupos.set(chave, span);
    }
    grupos.get(chave)[CONTROLID_DIAS_SEMANA[dia]] = 1;
  }
  return [...grupos.values()].sort((a, b) => a.start - b.start || a.end - b.end);
}

export function corpoCriar(objeto, valores) {
  return { object: objeto, values: valores };
}
export function corpoModificar(objeto, valores, onde) {
  return { object: objeto, values: valores, where: { [objeto]: onde } };
}
export function corpoApagar(objeto, onde) {
  return { object: objeto, where: { [objeto]: onde } };
}
export function corpoCarregar(objeto, onde) {
  return onde ? { object: objeto, where: { [objeto]: onde } } : { object: objeto };
}

export function numeroCartao(valor) {
  const d = somenteDigitos(valor);
  if (!d || d.length > 20) throw new Error('Número de cartão inválido');
  const n = Number(d);
  if (!Number.isSafeInteger(n)) throw new Error(`Número de cartão ${d} grande demais para o equipamento`);
  return n;
}

// Campos de `users` (acesso) que precisam mudar; null se nada mudou. `end_time` 0 desfaz um bloqueio anterior.
export function diffUsuarioAcesso(atual, usuario) {
  const desejado = { name: String(usuario.nome || '').trim(), registration: vazioParaNulo(usuario.matricula) || '' };
  if (!atual) return desejado;
  const mudou = {};
  if (String(atual.name ?? '') !== desejado.name) mudou.name = desejado.name;
  if (String(atual.registration ?? '') !== desejado.registration) mudou.registration = desejado.registration;
  if (Number(atual.end_time || 0) !== 0) mudou.end_time = 0;
  return Object.keys(mudou).length ? mudou : null;
}

// Cartões: atuaisDoUsuario = cards com user_id = U; outrosComValor = cards de OUTROS usuários com algum valor desejado
// (o cadastro do sistema manda: o cartão passa para U). Retorna ids a apagar e valores a criar.
export function diffCartoes(atuaisDoUsuario, outrosComValor, desejados, userId) {
  const quero = new Set((desejados || []).map((c) => numeroCartao(c)));
  const tenho = new Map((atuaisDoUsuario || []).map((c) => [Number(c.value), c]));
  const apagar = [];
  for (const [valor, c] of tenho) if (!quero.has(valor)) apagar.push(c.id);
  for (const c of outrosComValor || []) if (Number(c.user_id) !== Number(userId) && quero.has(Number(c.value))) apagar.push(c.id);
  const criar = [...quero].filter((v) => !tenho.has(v)).map((v) => ({ value: v, user_id: Number(userId) }));
  return { apagar: deduplicarPor(apagar.map((id) => ({ id })), 'id').map((x) => x.id), criar };
}

export function diffRegras(atuais, desejadas) {
  const tenho = new Set((atuais || []).map((r) => Number(r.access_rule_id)));
  const quero = new Set((desejadas || []).map((r) => Number(r.access_rule_id)).filter((n) => Number.isFinite(n)));
  return { apagar: [...tenho].filter((r) => !quero.has(r)), criar: [...quero].filter((r) => !tenho.has(r)) };
}

export function chaveRep(usuario, identificador) {
  return normalizarDocumento(usuario && usuario[identificador === 'pis' ? 'pis' : 'cpf']);
}

// Corpo de um usuário do REP (add_users/update_users). Campos de senha/cartão só quando o recurso está ligado.
export function corpoUsuarioRep(item, identificador, envio) {
  const u = item.usuario || {};
  const chave = chaveRep(u, identificador);
  const obj = { name: String(u.nome || '').trim().slice(0, CONTROLID_NOME_REP_MAX) };
  obj[identificador === 'pis' ? 'pis' : 'cpf'] = Number(chave);
  const mat = vazioParaNulo(u.matricula);
  if (mat && /^[0-9]{1,15}$/.test(mat)) obj.registration = Number(mat);
  if (envio && envio.senha) obj.password = item.senha ? String(item.senha) : '';
  if (envio && envio.cartao) obj.rfid = item.cartoes && item.cartoes.length ? numeroCartao(item.cartoes[0]) : 0;
  return obj;
}

export function base64DeBytes(bytes) {
  if (typeof Buffer !== 'undefined') return Buffer.from(bytes).toString('base64');
  let s = '';
  const arr = new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
  return btoa(s);
}

export function urlFotoStorage(supabaseUrl, foto) {
  const caminho = String(foto.caminho || '').split('/').map(encodeURIComponent).join('/');
  return `${String(supabaseUrl).replace(/\/+$/, '')}/storage/v1/object/${encodeURIComponent(foto.bucket || 'funcionarios-fotos')}/${caminho}`;
}

// ------------------------------------------------------------------------------------- acesso: horários

async function carregarObjetos(cliente, objeto, onde) {
  const r = await cliente.chamar('load_objects.fcgi', corpoCarregar(objeto, onde));
  return Array.isArray(r[objeto]) ? r[objeto] : [];
}

async function apagarObjetos(cliente, objeto, onde) {
  await cliente.chamar('destroy_objects.fcgi', corpoApagar(objeto, onde));
}

async function criarObjetos(cliente, objeto, valores) {
  if (!valores.length) return [];
  const r = await cliente.chamar('create_objects.fcgi', corpoCriar(objeto, valores));
  return Array.isArray(r.ids) ? r.ids : [];
}

// Recriação completa (A.5): apaga o que é nosso (mapa_anterior + nomes "MDG …", o que também limpa sobras de uma
// tentativa interrompida) e cria time_zone + time_spans + access_rule + vínculos por horário. Devolve o mapa novo.
export async function enviarHorariosAcesso(cliente, item) {
  const anteriores = item.mapa_anterior || {};
  const tzApagar = new Set(Object.values(anteriores).map((m) => Number(m && m.time_zone_id)).filter(Number.isFinite));
  const arApagar = new Set(Object.values(anteriores).map((m) => Number(m && m.access_rule_id)).filter(Number.isFinite));
  for (const tz of await carregarObjetos(cliente, 'time_zones')) {
    if (String(tz.name || '').startsWith(CONTROLID_PREFIXO_HORARIO)) tzApagar.add(Number(tz.id));
  }
  for (const ar of await carregarObjetos(cliente, 'access_rules')) {
    if (String(ar.name || '').startsWith(CONTROLID_PREFIXO_HORARIO)) arApagar.add(Number(ar.id));
  }
  for (const id of arApagar) {
    await apagarObjetos(cliente, 'access_rule_time_zones', { access_rule_id: id });
    await apagarObjetos(cliente, 'portal_access_rules', { access_rule_id: id });
    await apagarObjetos(cliente, 'user_access_rules', { access_rule_id: id });
    await apagarObjetos(cliente, 'access_rules', { id });
  }
  for (const id of tzApagar) {
    await apagarObjetos(cliente, 'time_spans', { time_zone_id: id });
    await apagarObjetos(cliente, 'time_zones', { id });
  }
  const mapa = {};
  for (const h of item.horarios || []) {
    const nome = (CONTROLID_PREFIXO_HORARIO + String(h.nome || h.horario_id)).slice(0, 60);
    const [tzId] = await criarObjetos(cliente, 'time_zones', [{ name: nome }]);
    if (tzId === undefined) throw new Error(`Equipamento não devolveu o id do time_zone de "${h.nome}"`);
    await criarObjetos(cliente, 'time_spans', faixasParaTimeSpans(h.faixas, tzId));
    const [arId] = await criarObjetos(cliente, 'access_rules', [{ name: nome, type: 1, priority: 0 }]);
    if (arId === undefined) throw new Error(`Equipamento não devolveu o id da access_rule de "${h.nome}"`);
    await criarObjetos(cliente, 'access_rule_time_zones', [{ access_rule_id: arId, time_zone_id: tzId }]);
    await criarObjetos(cliente, 'portal_access_rules', [{ portal_id: 1, access_rule_id: arId }]);
    mapa[h.horario_id] = { time_zone_id: tzId, access_rule_id: arId };
  }
  return mapa;
}

// ----------------------------------------------------------------------------------- acesso: funcionário

async function definirSenhaAcesso(cliente, userId, senha) {
  if (!senha) {
    await cliente.chamar('modify_objects.fcgi', corpoModificar('users', { password: '', salt: '' }, { id: userId }));
    return;
  }
  const h = await cliente.chamar('user_hash_password.fcgi', { password: String(senha) });
  if (!h || !h.password) throw new Error('Equipamento não devolveu o hash da senha (user_hash_password)');
  await cliente.chamar('modify_objects.fcgi', corpoModificar('users', { password: h.password, salt: h.salt || '' }, { id: userId }));
}

async function sincronizarCartoesAcesso(cliente, userId, cartoes) {
  const meus = await carregarObjetos(cliente, 'cards', { user_id: userId });
  const outros = [];
  for (const c of cartoes || []) outros.push(...(await carregarObjetos(cliente, 'cards', { value: numeroCartao(c) })));
  const d = diffCartoes(meus, outros, cartoes, userId);
  for (const id of d.apagar) await apagarObjetos(cliente, 'cards', { id });
  await criarObjetos(cliente, 'cards', d.criar);
  return d;
}

async function sincronizarRegrasAcesso(cliente, userId, regras) {
  const atuais = await carregarObjetos(cliente, 'user_access_rules', { user_id: userId });
  const d = diffRegras(atuais, regras);
  for (const r of d.apagar) await apagarObjetos(cliente, 'user_access_rules', { user_id: userId, access_rule_id: r });
  await criarObjetos(cliente, 'user_access_rules', d.criar.map((r) => ({ user_id: userId, access_rule_id: r })));
  return d;
}

async function enviarFotoAcesso(cliente, userId, atual, foto, baixarFoto) {
  if (!foto) {
    if (Number(atual && atual.image_timestamp) > 0) await cliente.chamar('user_destroy_image.fcgi', { user_ids: [userId] });
    return 'removida';
  }
  const ts = Math.floor(Date.parse(foto.atualizado_em) / 1000) || 0;
  if (ts && atual && Number(atual.image_timestamp) === ts) return 'igual';
  if (!baixarFoto) throw new Error('Download de foto não configurado');
  const bytes = await baixarFoto(foto);
  const tamanho = bytes ? bytes.byteLength ?? bytes.length : 0;
  if (!tamanho) throw new Error('Foto vazia no Storage');
  if (tamanho > CONTROLID_FOTO_MAX_BYTES) throw new Error('Foto maior que 2 MB');
  try {
    const r = await cliente.chamar('user_set_image_list.fcgi', {
      match: true, user_images: [{ user_id: userId, timestamp: ts, image: base64DeBytes(bytes) }],
    });
    const res = Array.isArray(r.results) ? r.results.find((x) => Number(x.user_id) === Number(userId)) || r.results[0] : null;
    if (res && res.success === false) {
      const msg = Array.isArray(res.errors) && res.errors.length ? res.errors.map((e) => e.message).join('; ') : 'recusada';
      throw new Error('Foto recusada pelo equipamento: ' + msg);
    }
  } catch (e) {
    if (!e || e.status !== 404) throw e;
    // modelos sem user_set_image_list: envio binário
    await cliente.chamar('user_set_image.fcgi', null, {
      binario: bytes, tipoConteudo: 'application/octet-stream', consulta: { user_id: userId, match: 1, timestamp: ts },
    });
  }
  return 'enviada';
}

export async function enviarFuncionarioAcesso(cliente, item, envio, baixarFoto, agoraMs) {
  const idAntigo = vazioParaNulo(item.id_remoto);
  let atual = idAntigo ? (await carregarObjetos(cliente, 'users', { id: Number(idAntigo) }))[0] || null : null;

  if (item.operacao === 'remover') {
    if (atual) await apagarObjetos(cliente, 'users', { id: Number(atual.id) });
    return { id_remoto: null, acoes: atual ? ['usuario_removido'] : ['ja_ausente'] };
  }
  if (item.operacao === 'bloquear') {
    if (!atual) return { id_remoto: null, acoes: ['ja_ausente'] };
    const uid = Number(atual.id);
    for (const c of await carregarObjetos(cliente, 'cards', { user_id: uid })) await apagarObjetos(cliente, 'cards', { id: c.id });
    await apagarObjetos(cliente, 'user_access_rules', { user_id: uid });
    const passado = Math.floor((agoraMs === undefined ? Date.now() : agoraMs) / 1000) - CONTROLID_DIA_MS / 1000;
    await cliente.chamar('modify_objects.fcgi', corpoModificar('users', { password: '', salt: '', end_time: passado }, { id: uid }));
    return { id_remoto: String(uid), acoes: ['bloqueado'] };
  }

  const u = item.usuario || {};
  if (!String(u.nome || '').trim()) throw new Error('Funcionário sem nome');
  const acoes = [];
  if (!atual && vazioParaNulo(u.matricula)) {
    // Evita duplicar: usuário com a mesma matrícula já existe no equipamento (não importado ainda).
    atual = (await carregarObjetos(cliente, 'users', { registration: vazioParaNulo(u.matricula) }))[0] || null;
    if (atual) acoes.push('reaproveitado_pela_matricula');
  }
  let uid;
  if (!atual) {
    const [novo] = await criarObjetos(cliente, 'users', [diffUsuarioAcesso(null, u)]);
    if (novo === undefined) throw new Error('Equipamento não devolveu o id do usuário criado');
    uid = Number(novo);
    acoes.push('usuario_criado');
  } else {
    uid = Number(atual.id);
    const mudou = diffUsuarioAcesso(atual, u);
    if (mudou) {
      await cliente.chamar('modify_objects.fcgi', corpoModificar('users', mudou, { id: uid }));
      acoes.push('usuario_alterado');
    }
  }
  if (envio.senha) {
    await definirSenhaAcesso(cliente, uid, item.senha);
    acoes.push(item.senha ? 'senha_definida' : 'senha_removida');
  }
  if (envio.cartao && item.cartoes !== null && item.cartoes !== undefined) {
    const d = await sincronizarCartoesAcesso(cliente, uid, item.cartoes);
    if (d.apagar.length || d.criar.length) acoes.push(`cartoes(-${d.apagar.length}/+${d.criar.length})`);
  }
  if (envio.horarios && item.regras_acesso !== null && item.regras_acesso !== undefined) {
    const d = await sincronizarRegrasAcesso(cliente, uid, item.regras_acesso);
    if (d.apagar.length || d.criar.length) acoes.push(`regras(-${d.apagar.length}/+${d.criar.length})`);
  }
  if (envio.foto && item.foto !== undefined) {
    acoes.push('foto_' + (await enviarFotoAcesso(cliente, uid, atual, item.foto, baixarFoto)));
  }
  return { id_remoto: String(uid), acoes };
}

// ---------------------------------------------------------------------------------------------- REP

export async function enviarFuncionarioRep(cliente, item, envio, identificador, cadastrados) {
  // cadastrados: Map chave(CPF/PIS) → usuário, carregado uma vez por execução e mantido atualizado aqui.
  const antigo = normalizarDocumento(item.id_remoto);
  const campo = identificador === 'pis' ? 'pis' : 'cpf';
  const remover = async (chave) => {
    await cliente.chamar('remove_users.fcgi', { users: [Number(chave)] });
    cadastrados.delete(chave);
  };
  if (item.operacao === 'remover' || item.operacao === 'bloquear') {
    if (antigo && cadastrados.has(antigo)) {
      await remover(antigo);
      return { id_remoto: null, acoes: ['usuario_removido'] };
    }
    return { id_remoto: null, acoes: ['ja_ausente'] };
  }
  const chave = chaveRep(item.usuario, identificador);
  if (!chave) throw new Error(campo === 'pis' ? 'PIS obrigatório no REP' : 'CPF obrigatório no REP');
  if (!String((item.usuario && item.usuario.nome) || '').trim()) throw new Error('Funcionário sem nome');
  const acoes = [];
  if (antigo && antigo !== chave && cadastrados.has(antigo)) {
    await remover(antigo);
    acoes.push('chave_antiga_removida');
  }
  const corpo = corpoUsuarioRep(item, identificador, envio);
  if (cadastrados.has(chave)) {
    await cliente.chamar('update_users.fcgi', { users: [corpo] });
    acoes.push('usuario_alterado');
  } else {
    await cliente.chamar('add_users.fcgi', { users: [corpo] });
    acoes.push('usuario_criado');
  }
  cadastrados.set(chave, Object.assign({}, cadastrados.get(chave) || {}, corpo));
  return { id_remoto: chave, acoes };
}

// --------------------------------------------------------------------------------------- orquestrador

// pendencias = retorno de ingestao_controlid_envios_pendentes. Devolve um resultado por item:
//   { envio_id, versao, status: 'enviado'|'erro', id_remoto, erro, mapa_remoto, alvo, operacao, acoes }
export async function enviarPendencias({ http, config, pendencias, baixarFoto, esperar, agoraMs }) {
  const res = { etapa: 'equipamento', ok: false, erro: null, tentativas: 1, lidos: 0, resultados: [], detalhes: {} };
  let cliente = null;
  try {
    if (pendencias && pendencias.error) throw new Error('Falha ao ler as pendências de envio: ' + mensagemDeErro(pendencias.error));
    const itens = pendencias && Array.isArray(pendencias.itens) ? pendencias.itens : [];
    res.lidos = itens.length;
    const cfg = lerConfig(config, agoraMs);
    const tipo = pendencias && pendencias.tipo ? pendencias.tipo : cfg.tipo;
    const envioCfg = Object.assign({ foto: false, cartao: false, senha: false, horarios: false }, (pendencias && pendencias.envio) || {});
    if (tipo === 'controlid_rep') {
      envioCfg.foto = false;
      envioCfg.horarios = false;
    }
    const identificador = (pendencias && pendencias.identificador) === 'pis' ? 'pis' : cfg.identificador;
    res.detalhes = { tipo, envio: envioCfg, itens: itens.length };
    if (itens.length === 0) {
      res.ok = true;
      return res;
    }
    cliente = clienteDaConfig(http, cfg, esperar);
    let cadastradosRep = null;
    const falhaGeral = async () => {
      // Sem login/conexão não adianta tentar item a item: todos recebem o mesmo erro.
      await cliente.entrar();
    };
    try {
      await falhaGeral();
      if (tipo === 'controlid_rep') {
        const r = await carregarUsuariosRep(cliente, cfg);
        cadastradosRep = new Map();
        for (const u of r.itens) {
          const k = normalizarDocumento(u[identificador === 'pis' ? 'pis' : 'cpf']);
          if (k) cadastradosRep.set(k, u);
        }
      }
    } catch (e) {
      const msg = cortar(mensagemDeErro(e), 1000);
      res.erro = msg;
      res.resultados = itens.map((it) => resultadoEnvio(it, 'erro', null, msg, null, []));
      return res;
    }
    for (const it of itens) {
      try {
        if (it.alvo === 'horarios') {
          if (tipo !== 'controlid_acesso') throw new Error('Horários de acesso só existem em equipamentos de acesso');
          const mapa = await enviarHorariosAcesso(cliente, it);
          res.resultados.push(resultadoEnvio(it, 'enviado', null, null, mapa, ['horarios:' + Object.keys(mapa).length]));
        } else if (tipo === 'controlid_acesso') {
          const r = await enviarFuncionarioAcesso(cliente, it, envioCfg, baixarFoto, agoraMs);
          res.resultados.push(resultadoEnvio(it, 'enviado', r.id_remoto, null, null, r.acoes));
        } else {
          const r = await enviarFuncionarioRep(cliente, it, envioCfg, identificador, cadastradosRep);
          res.resultados.push(resultadoEnvio(it, 'enviado', r.id_remoto, null, null, r.acoes));
        }
      } catch (e) {
        res.resultados.push(resultadoEnvio(it, 'erro', null, cortar(mensagemDeErro(e), 1000), null, []));
      }
    }
    res.ok = true;
  } catch (e) {
    res.erro = cortar(mensagemDeErro(e), 1000);
    const itens = pendencias && Array.isArray(pendencias.itens) ? pendencias.itens : [];
    if (!res.resultados.length) res.resultados = itens.map((it) => resultadoEnvio(it, 'erro', null, res.erro, null, []));
  } finally {
    if (cliente) {
      res.detalhes.logout = await cliente.sair();
      res.tentativas = cliente.tentativas;
    }
  }
  return res;
}

function resultadoEnvio(item, status, idRemoto, erro, mapa, acoes) {
  return {
    envio_id: item.envio_id,
    versao: item.versao,
    alvo: item.alvo,
    operacao: item.operacao,
    funcionario_nome: (item.usuario && item.usuario.nome) || null,
    status,
    id_remoto: idRemoto,
    erro,
    mapa_remoto: mapa,
    acoes,
  };
}

// Corpo de ingestao_controlid_envio_resultado para um resultado.
export function corpoResultadoEnvio(r) {
  return {
    p_envio: r.envio_id,
    p_versao: r.versao,
    p_status: r.status,
    p_id_remoto: r.id_remoto === undefined ? null : r.id_remoto,
    p_erro: r.erro || null,
    p_mapa_remoto: r.mapa_remoto || null,
  };
}

// Itens do nó seguinte: um por resultado, ou [{sem_item: true}] quando não há nada a registrar.
export function itensDeResultado(envio) {
  const rs = (envio && envio.resultados) || [];
  if (!rs.length) return [{ sem_item: true }];
  return rs.map((r) => ({ resultado: r, corpo: corpoResultadoEnvio(r) }));
}

// envio = saída de enviarPendencias (+ execucao_id); itens = itensDeResultado; respostas = retornos do registro.
export function resumirEnvio({ envio, itens, respostas, execucaoId }) {
  const exec = execucaoId || (envio && envio.execucao_id);
  const det = Object.assign({}, (envio && envio.detalhes) || {});
  const rs = (itens || []).filter((i) => i && i.resultado).map((i) => i.resultado);
  if (!envio || (!envio.ok && rs.length === 0)) {
    return comSaida([finalizacao(exec, 'erro', envio ? envio.lidos : 0, 0, 0, (envio && envio.erro) || 'Falha no envio', det, envio && envio.tentativas)]);
  }
  let enviados = 0;
  const falhas = [];
  rs.forEach((r, i) => {
    const resp = (respostas || [])[i];
    const erroRegistro = resp && resp.error ? mensagemDeErro(resp.error) : null;
    if (r.status === 'enviado' && !erroRegistro) enviados += 1;
    else falhas.push({ envio_id: r.envio_id, nome: r.funcionario_nome || r.alvo, erro: cortar(erroRegistro ? 'registro do resultado: ' + erroRegistro : r.erro, 300) });
  });
  det.enviados = enviados;
  det.com_erro = falhas.length;
  if (falhas.length) det.erros = falhas.slice(0, 20);
  det.acoes = rs.slice(0, 50).map((r) => ({ nome: r.funcionario_nome || r.alvo, operacao: r.operacao, status: r.status, acoes: r.acoes }));
  const status = rs.length === 0 ? (envio.ok ? 'sucesso' : 'erro')
    : falhas.length === 0 ? 'sucesso' : enviados === 0 ? 'erro' : 'parcial';
  const erro = falhas.length ? `${falhas.length} de ${rs.length} envio(s) com erro: ${falhas[0].nome}: ${falhas[0].erro}` : envio.erro;
  return comSaida([finalizacao(exec, status, rs.length, enviados, 0, erro, det, envio.tentativas)]);
}

// Download da foto no Supabase Storage pelo nó Code (service_role vem de $env, nunca do JSON do workflow).
export function baixadorFotoN8n(helpers, supabaseUrl, chaveServico) {
  return async function (foto) {
    const r = await helpers.httpRequest({
      method: 'GET',
      url: urlFotoStorage(supabaseUrl, foto),
      headers: { apikey: chaveServico, Authorization: 'Bearer ' + chaveServico },
      encoding: 'arraybuffer',
      json: false,
      returnFullResponse: true,
      ignoreHttpStatusErrors: true,
      timeout: 30000,
    });
    if (r.statusCode >= 400) throw new Error(`Foto não encontrada no Storage (HTTP ${r.statusCode})`);
    return r.body;
  };
}
