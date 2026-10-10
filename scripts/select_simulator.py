#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path
data=json.loads(Path(sys.argv[1]).read_text())
candidates=[]
for runtime, devices in data['devices'].items():
    if '.iOS-' not in runtime: continue
    version=tuple(int(part) for part in re.findall(r'\d+',runtime.rsplit('.iOS-',1)[-1]))
    # Xcode 16.4 is paired with the iOS 18.5 runtime, not a newer Xcode's simulator.
    if version[:2] != (18,5): continue
    if version < (17,): continue
    for device in devices:
        if device.get('isAvailable') and 'iPhone' in device['name']:
            candidates.append((version,device['name'],device['udid']))
if not candidates: raise SystemExit('No available iOS 18.5 iPhone simulator for Xcode 16.4. Install it in Xcode Settings > Platforms, or set IOS_SIMULATOR_DESTINATION explicitly.')
print(max(candidates)[2])
