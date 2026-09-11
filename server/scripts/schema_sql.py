"""Tokenize and normalize SQLite schema SQL without changing literal values.
Exports tokens, normalize, and format_sql; depends only on Python's re module.
"""

import re

TOKEN = re.compile(
    r"--[^\n]*|/\*[\s\S]*?\*/|'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\""
    r"|`(?:``|[^`])*`|\[[^\]]*\]|[A-Za-z_][A-Za-z_0-9$]*"
    r"|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\|\||<>|!=|<=|>=|==|[^\s]"
)


def tokens(sql: str) -> list[str]:
    return [match.group() for match in TOKEN.finditer(sql)
            if not match.group().startswith(('--', '/*'))]


def normalize(sql: str) -> str:
    result: list[str] = []
    for token in tokens(sql):
        if token.startswith("'"):
            result.append(token)
            continue
        if token.startswith(('"', '`', '[')):
            quote = token[0]
            identifier = token[1:-1].replace(quote * 2, quote)
            # Keep delimiters for identifiers that would otherwise become SQL tokens.
            token = identifier if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9$]*', identifier) else token
        result.append(token.lower())
    # IF NOT EXISTS is cosmetic only in a CREATE declaration, never in a literal.
    if result[:1] == ['create']:
        offset = 3 if result[1:2] == ['unique'] else 2
        if result[offset:offset + 3] == ['if', 'not', 'exists']:
            del result[offset:offset + 3]
    return ' '.join(result).removesuffix(' ;')


def format_sql(sql: str) -> str:
    """Lay out top-level table fields; leave expressions and literals intact."""
    parts = tokens(sql)
    result = ''
    depth = 0
    table = parts[:2] == ['CREATE', 'TABLE']
    for token in parts:
        if token == '(':
            depth += 1
            spaced = result.split()[-1] in ('DEFAULT', 'CHECK', 'IN', 'KEY', 'UNIQUE')
            opening = ' (' if spaced else '('
            result = result.rstrip() + (' (\n  ' if table and depth == 1 else opening)
        elif token == ')':
            result = result.rstrip() + ('\n)' if table and depth == 1 else ')')
            depth -= 1
        elif token == ',':
            result = result.rstrip() + (',\n  ' if table and depth == 1 else ', ')
        else:
            separator = '' if not result or result[-1] in ' (\n' else ' '
            result += separator + token
    return result + ';'
