from pathlib import Path
import re
from collections import defaultdict

root = Path('supabase/migrations')
text = '\n'.join(p.read_text(errors='ignore') for p in sorted(root.glob('*.sql')))

tables = sorted({name for name in re.findall(r'CREATE TABLE(?: IF NOT EXISTS)?\s+(?:public\.)?([a-zA-Z0-9_]+)', text, re.I) if name.lower() not in {'for', 'to'}})
rls = set(re.findall(r'ALTER TABLE(?: IF EXISTS)?\s+(?:public\.)?([a-zA-Z0-9_]+)\s+ENABLE ROW LEVEL SECURITY', text, re.I))
policies = defaultdict(int)
for table in re.findall(r'CREATE POLICY\s+"[^"]+"\s+ON\s+(?:public\.)?([a-zA-Z0-9_]+)', text, re.I):
    policies[table] += 1
security_definer = len(re.findall(r'LANGUAGE\s+(?:plpgsql|sql)[^;]*SECURITY DEFINER', text, re.I))
print(f'TABLES={len(tables)} RLS_ENABLED={len(rls)} TABLES_WITH_POLICIES={len(policies)} SECURITY_DEFINER_FUNCTIONS={security_definer}')
print('TABLES_WITHOUT_RLS_OR_POLICY:')
for table in tables:
    if table not in rls or policies[table] == 0:
        print(f'  {table}: rls={table in rls} policies={policies[table]}')
print('TENANT_SENSITIVE_POLICY_SAMPLES:')
for table in sorted(policies):
    if any(token in table for token in ('pos_', 'payment', 'order', 'crm_', 'notification', 'pwa_', 'stock', 'refund', 'approval', 'shipment', 'courier')):
        print(f'  {table}: policies={policies[table]} rls={table in rls}')
