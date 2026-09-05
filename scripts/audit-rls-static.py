from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path


root = Path('supabase/bootstrap')
text = '\n'.join(p.read_text(errors='ignore') for p in sorted(root.glob('*.sql')))
text = re.sub(r'--[^\n]*', '', text)
text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)

# These tables intentionally have no authenticated policies. They are write/read
# stores owned by SECURITY DEFINER or service-role workflows and must remain
# inaccessible to browser clients.
SERVER_ONLY_TABLES = {
    'payment_invoice_requests',
    'pos_sale_requests',
}

tables = sorted({
    name
    for name in re.findall(
        r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(?:public\.)?([a-zA-Z0-9_]+)',
        text,
        re.I,
    )
    if name.lower() not in {'for', 'to'}
})
rls = {
    name.lower()
    for name in re.findall(
        r'ALTER TABLE\s+(?:IF EXISTS\s+)?(?:public\.)?([a-zA-Z0-9_]+)\s+ENABLE ROW LEVEL SECURITY',
        text,
        re.I,
    )
}
policies = defaultdict(int)
for table in re.findall(
    r'CREATE POLICY\s+"[^"]+"\s+ON\s+(?:public\.)?([a-zA-Z0-9_]+)',
    text,
    re.I,
):
    policies[table.lower()] += 1
server_only_revokes = {
    name.lower()
    for name in re.findall(
        r'REVOKE ALL ON (?:public\.)?([a-zA-Z0-9_]+) FROM anon, authenticated',
        text,
        re.I,
    )
}
server_only_grants = {
    name.lower()
    for name in re.findall(
        r'GRANT ALL ON (?:public\.)?([a-zA-Z0-9_]+) TO service_role',
        text,
        re.I,
    )
}
security_definer = len(re.findall(r'LANGUAGE\s+(?:plpgsql|sql)[^;]*SECURITY DEFINER', text, re.I))

print(f'TABLES={len(tables)} RLS_ENABLED={len(rls)} TABLES_WITH_POLICIES={len(policies)} SECURITY_DEFINER_FUNCTIONS={security_definer}')
print('SERVER_ONLY_RLS_EXEMPTIONS:')
security_issues: list[str] = []
for table in sorted(SERVER_ONLY_TABLES):
    table_has_rls = table in rls
    table_has_no_policy = policies[table] == 0
    client_access_revoked = table in server_only_revokes
    service_role_granted = table in server_only_grants
    print(
        f'  {table}: rls={table_has_rls} policies={policies[table]} '
        f'client_access_revoked={client_access_revoked} service_role_granted={service_role_granted}'
    )
    if not table_has_rls:
        security_issues.append(f'{table} does not enable RLS')
    if not table_has_no_policy:
        security_issues.append(f'{table} unexpectedly has authenticated policies')
    if not client_access_revoked:
        security_issues.append(f'{table} does not revoke anon/authenticated access')
    if not service_role_granted:
        security_issues.append(f'{table} does not grant service_role access')

print('TABLES_WITHOUT_RLS_OR_POLICY:')
for table in tables:
    table_key = table.lower()
    if table_key in SERVER_ONLY_TABLES:
        continue
    if table_key not in rls or policies[table_key] == 0:
        print(f'  {table}: rls={table_key in rls} policies={policies[table_key]}')

print('TENANT_SENSITIVE_POLICY_SAMPLES:')
for table in sorted(policies):
    if any(token in table for token in ('pos_', 'payment', 'order', 'crm_', 'notification', 'pwa_', 'stock', 'refund', 'approval', 'shipment', 'courier')):
        print(f'  {table}: policies={policies[table]} rls={table in rls}')

if security_issues:
    print('SERVER_ONLY_RLS_VALIDATION_FAILED:')
    for issue in security_issues:
        print(f'  {issue}')
    raise SystemExit(1)
