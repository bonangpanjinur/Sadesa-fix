#!/usr/bin/env python3
"""Make checked-in consolidated bootstrap bundles safe to run repeatedly."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

DUPLICATE_EXCEPTIONS = 'duplicate_object OR duplicate_table OR duplicate_column OR duplicate_schema OR duplicate_function OR unique_violation'
ROOT = Path('supabase/bootstrap')

def dollar_tag_at(text: str, index: int) -> str | None:
    match = re.match(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$', text[index:])
    return match.group(0) if match else None

def split_sql(sql: str) -> list[str]:
    statements=[]; start=0; i=0; quote=None; dollar=None; line=False; block=False
    while i < len(sql):
        c=sql[i]; n=sql[i+1] if i+1 < len(sql) else ''
        if line:
            if c=='\n': line=False
            i+=1; continue
        if block:
            if c=='*' and n=='/': block=False; i+=2
            else: i+=1
            continue
        if dollar:
            if sql.startswith(dollar,i): i+=len(dollar); dollar=None
            else: i+=1
            continue
        if quote:
            if c==quote:
                if n==quote: i+=2
                else: quote=None; i+=1
            elif c=='\\' and quote=="'": i+=2
            else: i+=1
            continue
        if c=='-' and n=='-': line=True; i+=2; continue
        if c=='/' and n=='*': block=True; i+=2; continue
        if c in ("'", '"'): quote=c; i+=1; continue
        if c=='$':
            tag=dollar_tag_at(sql,i)
            if tag: dollar=tag; i+=len(tag); continue
        if c==';':
            value=sql[start:i].strip()
            if value: statements.append(value)
            start=i+1
        i+=1
    value=sql[start:].strip()
    if value: statements.append(value)
    return statements

def leading_sql(statement: str) -> str:
    value=statement.lstrip()
    while value.startswith('--') or value.startswith('/*'):
        if value.startswith('--'):
            end=value.find('\n'); value='' if end<0 else value[end+1:].lstrip()
        else:
            end=value.find('*/',2); value='' if end<0 else value[end+2:].lstrip()
    return value

def wrap(statement: str, ordinal: int) -> str:
    if re.match(r'^INSERT\s+INTO\b', leading_sql(statement), re.I) and not re.search(r'\bON\s+CONFLICT\b', statement, re.I):
        statement += '\nON CONFLICT DO NOTHING'
    digest=hashlib.sha1(f'{ordinal}:{statement}'.encode()).hexdigest()[:12]
    sql_tag=f'$bootstrap_sql_{digest}$'; do_tag=f'$bootstrap_do_{digest}$'
    while sql_tag in statement or do_tag in statement:
        digest += 'x'; sql_tag=f'$bootstrap_sql_{digest}$'; do_tag=f'$bootstrap_do_{digest}$'
    return f'DO {do_tag}\nBEGIN\n  EXECUTE {sql_tag}{statement}{sql_tag};\nEXCEPTION\n  WHEN {DUPLICATE_EXCEPTIONS} THEN NULL;\nEND {do_tag};'

def main() -> None:
    manifest_path=ROOT/'manifest.json'; manifest=json.loads(manifest_path.read_text())
    manifest['idempotent']=True
    manifest['duplicate_errors_ignored']=DUPLICATE_EXCEPTIONS.split(' OR ')
    for bundle in manifest['bundles']:
        path=ROOT/bundle['file']; original=path.read_text(encoding='utf-8')
        if 'DO $bootstrap_do_' in original:
            content=original if 'SAFE TO RE-RUN' in original else (
                '-- DesaMart repeatable canonical bootstrap bundle.\n'
                '-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.\n'
                '-- Duplicate-object errors are ignored per statement; other errors remain visible.\n\n'
                + original
            )
        else:
            statements=split_sql(original)
            body='\n\n'.join(wrap(statement, i) for i, statement in enumerate(statements, 1))+'\n'
            content=(
                '-- DesaMart repeatable canonical bootstrap bundle.\n'
                '-- SAFE TO RE-RUN: existing objects/data are preserved and missing items continue.\n'
                '-- Duplicate-object errors are ignored per statement; other errors remain visible.\n\n'
                + body
            )
        path.write_text(content, encoding='utf-8')
        bundle['sha256']=hashlib.sha256(content.encode()).hexdigest()
        bundle['bytes']=len(content.encode())
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(f'Updated {len(manifest["bundles"])} existing bundles; preserved {manifest["migration_count"]} source migrations')

if __name__=='__main__': main()
