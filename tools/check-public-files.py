#!/usr/bin/env python3
"""Check the publication boundary, not app behaviour. Never print secret values."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files'], cwd=root, text=True).splitlines()
errors = []
config = json.loads((root / 'build-profile.json5').read_text(encoding='utf-8'))
if config.get('app', {}).get('signingConfigs'):
    errors.append('build-profile.json5: signingConfigs must be empty in the public repository')
for product in config.get('app', {}).get('products', []):
    if product.get('signingConfig'):
        errors.append('build-profile.json5: product references a private signing configuration')
for name in files:
    p = Path(name)
    if p.suffix.lower() in {'.p12', '.pfx', '.jks', '.keystore', '.cer', '.crt', '.p7b', '.pem', '.key', '.hap', '.app', '.har', '.log', '.ftrace', '.htrace'}:
        errors.append(f'{name}: private material or generated artifact must not be tracked')
    if any(part in {'.claude', 'oh_modules', 'node_modules', 'signing', '.hvigor', '.idea', 'build', 'shots', 'out'} for part in p.parts):
        errors.append(f'{name}: generated/private directory must not be tracked')
    if p.name in {'local.properties', 'build-profile.local.json5', 'AUDIT.md', 'FIX_PLAN.html'} or p.name.startswith('.env'):
        errors.append(f'{name}: private development file must not be tracked')
    if p.suffix.lower() in {'.ets', '.ts', '.json', '.json5', '.md', '.sh', '.py', '.yml', '.yaml'}:
        text = (root / name).read_text(encoding='utf-8')
        markers = [f'-----BEGIN {kind}PRIVATE KEY-----' for kind in ('', 'EC ', 'RSA ')]
        if any(marker in text for marker in markers):
            errors.append(f'{name}: private-key material detected')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Publication boundary checked: {len(files)} tracked files; no signing material or debug artifacts.')
