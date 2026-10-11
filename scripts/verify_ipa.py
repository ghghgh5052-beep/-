#!/usr/bin/env python3
"""Fail packaging if bundle identifiers, extension embedding, or architecture are wrong."""
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

def verify(path):
    with zipfile.ZipFile(path) as archive:
        names=archive.namelist()
        assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names), 'Unsafe archive entry'
        app='Payload/Fitness.app/'
        info=plistlib.loads(archive.read(app+'Info.plist'))
        assert not any('.appex/' in n or '/Watch/' in n or '/PlugIns/' in n for n in names), 'No deferred extension may ship'
        assert not any(key in info for key in ['SharedAppGroup','CloudKitContainerIdentifier','NSSupportsLiveActivities','NSHealthShareUsageDescription','NSHealthUpdateUsageDescription','UIBackgroundModes']), 'Deferred integration advertised'
        assert len(info.get('UIApplicationShortcutItems',[]))==3, 'Local Home Screen actions missing'
        assert not any(n.startswith(app+'Metadata.appintents/') for n in names), 'Siri is deferred'
        for folder, metadata in [(app,info)]:
            binary=archive.read(folder+metadata['CFBundleExecutable'])
            magic, cpu = struct.unpack('<II',binary[:8])
            assert magic == 0xFEEDFACF and cpu == 0x0100000C, 'Expected a device arm64 Mach-O executable'
            assert not any(n.startswith(folder+'_CodeSignature/') for n in names), 'Signed bundle unexpectedly packaged'
        assert not any(n.endswith('embedded.mobileprovision') for n in names), 'A provisioning profile must not be shipped in unsigned IPA'
        assert archive.testzip() is None, 'ZIP integrity check failed'
        print('Unsigned local IPA verified: arm64 app, no extensions/integration metadata, Home Screen actions, and ZIP integrity.')

if __name__=='__main__': verify(sys.argv[1])
