#!/usr/bin/env python3
"""Divide as migrações em partes pequenas para colar no SQL Editor do Supabase.

O SQL Editor recusa textos grandes ("request entity too large"), então o instalar.sql inteiro não cabe.
Este script quebra as migrações (na ordem) em comandos completos, respeitando comentários, textos entre
aspas e corpos de função ($$ ... $$), e agrupa os comandos em partes de até LIMITE bytes.

Uso: python3 ferramentas/dividir-instalar.py [pasta-de-saida] [limite-em-bytes]
Padrão: supabase/instalar-em-partes/ e 30000 bytes.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "supabase" / "instalar-em-partes"
LIMITE = int(sys.argv[2]) if len(sys.argv) > 2 else 30000
TAG = re.compile(r"\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$")


def comandos(sql: str):
    """Quebra o texto em comandos terminados em ';' fora de comentários, aspas e $tag$."""
    i, n, inicio = 0, len(sql), 0
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            fim = sql.find("\n", i)
            i = n if fim < 0 else fim + 1
        elif sql.startswith("/*", i):
            fim = sql.find("*/", i + 2)
            if fim < 0:
                raise ValueError("comentário /* sem fim")
            i = fim + 2
        elif c == "'":
            escapa = i > 0 and sql[i - 1] in "eE" and (i < 2 or not (sql[i - 2].isalnum() or sql[i - 2] == "_"))
            i += 1
            while True:
                if i >= n:
                    raise ValueError("texto entre aspas sem fim")
                if escapa and sql[i] == "\\":
                    i += 2
                    continue
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
        elif c == '"':
            fim = sql.find('"', i + 1)
            if fim < 0:
                raise ValueError("identificador entre aspas sem fim")
            i = fim + 1
        elif c == "$" and (m := TAG.match(sql, i)) and not (i > 0 and (sql[i - 1].isalnum() or sql[i - 1] == "_")):
            tag = m.group(0)
            fim = sql.find(tag, m.end())
            if fim < 0:
                raise ValueError(f"bloco {tag} sem fim")
            i = fim + len(tag)
        elif c == ";":
            yield sql[inicio:i + 1]
            inicio = i = i + 1
        else:
            i += 1
    resto = sql[inicio:]
    if resto.strip():
        if re.sub(r"--[^\n]*", "", resto).strip():
            raise ValueError("comando final sem ';'")


def main():
    migracoes = sorted((RAIZ / "supabase" / "migrations").glob("*.sql"))
    if not migracoes:
        sys.exit("Nenhuma migração encontrada.")
    partes, atual, origem = [], "", []
    for m in migracoes:
        for cmd in comandos(m.read_text(encoding="utf-8")):
            if atual and len((atual + cmd).encode()) > LIMITE:
                partes.append((atual, origem))
                atual, origem = "", []
            atual += cmd
            if m.name not in origem:
                origem.append(m.name)
    if atual.strip():
        partes.append((atual, origem))

    SAIDA.mkdir(parents=True, exist_ok=True)
    for antigo in SAIDA.glob("parte-*.sql"):
        antigo.unlink()
    total = len(partes)
    for k, (texto, nomes) in enumerate(partes, 1):
        cab = (
            f"-- Meu Dia de Gerente — instalação do banco, PARTE {k:02d} DE {total:02d}.\n"
            f"-- Rode as partes NA ORDEM (01, 02, 03...), cada uma numa query do SQL Editor do Supabase → Run.\n"
            f"-- Gerado por ferramentas/dividir-instalar.py a partir de: {', '.join(nomes)}. Não edite à mão.\n\n"
            "begin;\n"
        )
        (SAIDA / f"parte-{k:02d}-de-{total:02d}.sql").write_text(
            cab + texto.lstrip("\n") + "\n\ncommit;\n" + f"select 'parte {k:02d} de {total:02d} instalada' as resultado;\n",
            encoding="utf-8",
        )
    print(f"{total} partes em {SAIDA} (limite {LIMITE} bytes)")


if __name__ == "__main__":
    main()
