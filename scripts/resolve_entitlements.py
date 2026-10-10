#!/usr/bin/env python3
import json
import plistlib
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
settings=json.loads(Path(sys.argv[1]).read_text())
destination=Path(sys.argv[2]); destination.mkdir(parents=True,exist_ok=True)
for target in settings:
    name=target['target']
    if name not in ['Fitness','FitnessWidgets']: continue
    values=target['buildSettings']
    text=(ROOT/values['CODE_SIGN_ENTITLEMENTS']).read_text()
    for _ in range(10):
        expanded=re.sub(r'\$\(([^)]+)\)',lambda m: values.get(m.group(1),m.group(0)),text)
        if expanded==text: break
        text=expanded
    if '$(' in text: raise SystemExit('Unresolved entitlement variable for '+name)
    plist=plistlib.loads(text.encode())
    (destination/(name+'.resolved.entitlements')).write_bytes(plistlib.dumps(plist))
    print(name+': '+values['PRODUCT_BUNDLE_IDENTIFIER'])
