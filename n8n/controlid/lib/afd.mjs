// Leitor de AFD (Arquivo-Fonte de Dados) dos relógios de ponto REP — Portaria 671/2021 e Portaria 1510/2009 (legado).
// Funções puras, sem import: este arquivo é copiado para o nó Code "AFD · separar lotes" (convenção `// @lib` de docs/DIVISAO.md).
//
// Registros de marcação aproveitados (contrato §12.4):
//   Portaria 671, tipo 3 (REP-C, 50 colunas) e tipo 7 (REP-P, 137 colunas; mesmas colunas 1–46 do tipo 3):
//     1–9 NSR · 10 tipo · 11–34 data-hora "AAAA-MM-DDThh:mm:00-0300" · 35–46 CPF (12, zero à esquerda) · (tipo 3) 47–50 CRC-16
//   Portaria 1510, tipo 3 (34 colunas):
//     1–9 NSR · 10 tipo "3" · 11–18 data DDMMAAAA · 19–22 hora hhmm · 23–34 PIS (12, zero à esquerda)
// Detecção por linha: coluna 10 = tipo; coluna 21 = "T" → 671; senão comprimento ≥ 34 → 1510.
// Demais tipos (1 cabeçalho, 2 empresa, 4 ajuste de relógio, 5 empregado, 6 eventos, 9 trailer…) são contados e descartados.
// O CRC-16 e o hash SHA-256 não são validados (o equipamento é a fonte; a idempotência fica no banco por NSR).

const AFD_MAX_IGNORADAS_LISTADAS = 20;

function afdDigitos(texto) {
  return /^[0-9]+$/.test(texto);
}

function afdDataValida(ano, mes, dia, hora, minuto) {
  if (ano < 2000 || ano > 2099 || mes < 1 || mes > 12 || dia < 1 || dia > 31) return false;
  if (hora > 23 || minuto > 59) return false;
  const d = new Date(Date.UTC(ano, mes - 1, dia));
  return d.getUTCFullYear() === ano && d.getUTCMonth() === mes - 1 && d.getUTCDate() === dia;
}

function afdDocumento(campo12) {
  // CPF/PIS ocupam 12 posições com zero à esquerda; devolve 11 dígitos ou null.
  if (!afdDigitos(campo12)) return null;
  const excesso = campo12.slice(0, campo12.length - 11);
  if (!/^0*$/.test(excesso)) return null;
  const doc = campo12.slice(-11);
  if (/^0+$/.test(doc)) return null;
  return doc;
}

function afdDois(n) {
  return String(n).padStart(2, '0');
}

// Lê uma linha do AFD. Retorna { marcacao } | { ignorada: motivo } | { outro: tipo } | null (linha vazia).
export function lerLinhaAfd(linhaBruta, tipos) {
  const tiposAceitos = tipos || ['3', '7'];
  const linha = String(linhaBruta ?? '').replace(/^﻿/, '').replace(/\s+$/, '');
  if (linha === '') return null;
  if (linha.length < 10) return { ignorada: 'linha curta demais' };
  const nsrTexto = linha.slice(0, 9);
  const tipo = linha.charAt(9);
  if (!afdDigitos(nsrTexto)) {
    // Cabeçalho/trailer de alguns equipamentos usam espaços/letras aqui; só reclamamos se parece marcação.
    if (tipo === '3' || tipo === '7') return { ignorada: 'NSR não numérico' };
    return { outro: tipo || '?' };
  }
  if (!tiposAceitos.includes(tipo)) return { outro: tipo };
  const nsr = Number(nsrTexto);
  if (nsrTexto === '999999999' || tipo === '9') return { outro: '9' };
  if (nsr <= 0) return { ignorada: 'NSR zerado' };

  if (linha.charAt(20) === 'T') {
    // Portaria 671: data-hora em 11–34, CPF em 35–46.
    if (linha.length < 46) return { ignorada: 'registro 671 incompleto' };
    const dh = linha.slice(10, 34);
    const m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})([+-])([0-9]{2})([0-9]{2})$/.exec(dh);
    if (!m) return { ignorada: 'data-hora inválida' };
    const [ano, mes, dia, hora, minuto] = [m[1], m[2], m[3], m[4], m[5]].map(Number);
    if (!afdDataValida(ano, mes, dia, hora, minuto) || Number(m[6]) > 59) return { ignorada: 'data-hora inválida' };
    if (Number(m[8]) > 14 || Number(m[9]) > 59) return { ignorada: 'fuso inválido' };
    const cpf = afdDocumento(linha.slice(34, 46));
    if (!cpf) return { ignorada: 'CPF inválido' };
    return {
      marcacao: {
        id_externo: String(nsr),
        nsr,
        instante: `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${m[7]}${m[8]}:${m[9]}`,
        cpf,
      },
      layout: '671',
    };
  }

  if (tipo !== '3') return { ignorada: 'registro tipo 7 sem data-hora no layout 671' };
  if (linha.length < 34) return { ignorada: 'registro 1510 incompleto' };
  // Portaria 1510: data DDMMAAAA (11–18), hora hhmm (19–22), PIS (23–34). Sem fuso → instante_local.
  const data = linha.slice(10, 18);
  const hhmm = linha.slice(18, 22);
  if (!afdDigitos(data) || !afdDigitos(hhmm)) return { ignorada: 'data-hora inválida' };
  const dia = Number(data.slice(0, 2));
  const mes = Number(data.slice(2, 4));
  const ano = Number(data.slice(4, 8));
  const hora = Number(hhmm.slice(0, 2));
  const minuto = Number(hhmm.slice(2, 4));
  if (!afdDataValida(ano, mes, dia, hora, minuto)) return { ignorada: 'data-hora inválida' };
  const pis = afdDocumento(linha.slice(22, 34));
  if (!pis) return { ignorada: 'PIS inválido' };
  return {
    marcacao: {
      id_externo: String(nsr),
      nsr,
      instante_local: `${ano}-${afdDois(mes)}-${afdDois(dia)}T${afdDois(hora)}:${afdDois(minuto)}:00`,
      pis,
    },
    layout: '1510',
  };
}

// lerAfd(texto) → { marcacoes, ignoradas, total_linhas, outros_registros, layouts }
//   marcacoes: [{id_externo, nsr, instante|instante_local, cpf|pis}] na ordem do arquivo, sem NSR repetido (fica o primeiro)
//   ignoradas: [{linha (1-based), motivo, conteudo}] — linhas que pareciam marcação mas estão corrompidas
//   outros_registros: { "<tipo>": quantidade } dos registros que não são marcação
export function lerAfd(texto, opcoes) {
  const tipos = (opcoes && opcoes.tipos) || ['3', '7'];
  const linhas = String(texto ?? '').replace(/^﻿/, '').split(/\r\n|\n|\r/);
  const marcacoes = [];
  const ignoradas = [];
  const outros = {};
  const layouts = { '671': 0, '1510': 0 };
  const vistos = new Set();
  let duplicadas = 0;
  let totalLinhas = 0;
  linhas.forEach((linha, i) => {
    const r = lerLinhaAfd(linha, tipos);
    if (r === null) return;
    totalLinhas += 1;
    if (r.outro !== undefined) {
      outros[r.outro] = (outros[r.outro] || 0) + 1;
    } else if (r.ignorada) {
      ignoradas.push({ linha: i + 1, motivo: r.ignorada, conteudo: String(linha).slice(0, 60) });
    } else if (vistos.has(r.marcacao.id_externo)) {
      duplicadas += 1;
    } else {
      vistos.add(r.marcacao.id_externo);
      layouts[r.layout] += 1;
      marcacoes.push(r.marcacao);
    }
  });
  return { marcacoes, ignoradas, total_linhas: totalLinhas, outros_registros: outros, duplicadas, layouts };
}

// Resumo pequeno para gravar em sync_execucoes.detalhes (no máximo 20 linhas ignoradas listadas).
export function resumoAfd(leitura) {
  return {
    total_linhas: leitura.total_linhas,
    marcacoes: leitura.marcacoes.length,
    ignoradas: leitura.ignoradas.length,
    duplicadas: leitura.duplicadas,
    layouts: leitura.layouts,
    outros_registros: leitura.outros_registros,
    exemplos_ignoradas: leitura.ignoradas.slice(0, AFD_MAX_IGNORADAS_LISTADAS),
  };
}

export function deduplicarPorIdExterno(batidas) {
  const vistos = new Set();
  const saida = [];
  for (const b of batidas || []) {
    if (!b || b.id_externo === undefined || b.id_externo === null) continue;
    const chave = String(b.id_externo);
    if (vistos.has(chave)) continue;
    vistos.add(chave);
    saida.push(b);
  }
  return saida;
}

export function emLotes(lista, tamanho) {
  const t = Math.max(1, Math.floor(tamanho || 1000));
  const lotes = [];
  for (let i = 0; i < (lista || []).length; i += t) lotes.push(lista.slice(i, i + t));
  return lotes;
}

// Recebe a saída do nó "Control iD · buscar batidas" e devolve os itens do próximo passo:
//   [{lote: [...], indice, total_lotes, afd_resumo}] ou, sem nada a gravar, [{sem_lote: true, afd_resumo}].
// REP: lê o AFD (busca.afd). Acesso: usa busca.batidas já mapeadas.
export function separarLotes(busca, tamanhoLote) {
  let batidas = [];
  let afdResumo = null;
  if (busca && busca.ok) {
    if (typeof busca.afd === 'string') {
      const leitura = lerAfd(busca.afd);
      batidas = leitura.marcacoes;
      afdResumo = resumoAfd(leitura);
    } else if (Array.isArray(busca.batidas)) {
      batidas = busca.batidas;
    }
  }
  const lotes = emLotes(deduplicarPorIdExterno(batidas), tamanhoLote || 1000);
  if (lotes.length === 0) return [{ sem_lote: true, afd_resumo: afdResumo }];
  return lotes.map((lote, indice) => ({ lote, indice, total_lotes: lotes.length, afd_resumo: afdResumo }));
}
