#!/usr/bin/env python3
"""Fail packaging if bundle identifiers, extension embedding, or architecture are wrong."""
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
        extension=app+'PlugIns/FitnessWidgets.appex/'
        info=plistlib.loads(archive.read(app+'Info.plist'))
        ext=plistlib.loads(archive.read(extension+'Info.plist'))
        assert ext['CFBundleIdentifier'].startswith(info['CFBundleIdentifier']+'.'), 'Extension ID must start with app ID'
        assert ext['NSExtension']['NSExtensionPointIdentifier']=='com.apple.widgetkit-extension'
        assert info['SharedAppGroup']==ext['SharedAppGroup'], 'App Groups differ'
        assert info['CFBundleVersion']==ext['CFBundleVersion'], 'Embedded bundle version differs'
        assert info['NSSupportsLiveActivities'] is True
        for folder, metadata in [(app,info),(extension,ext)]:
            binary=archive.read(folder+metadata['CFBundleExecutable'])
            magic, cpu = struct.unpack('<II',binary[:8])
            assert magic == 0xFEEDFACF and cpu == 0x0100000C, 'Expected a device arm64 Mach-O executable'
            assert not any(n.startswith(folder+'_CodeSignature/') for n in names), 'Signed bundle unexpectedly packaged'
        assert not any(n.endswith('embedded.mobileprovision') for n in names), 'A provisioning profile must not be shipped in unsigned IPA'
        assert archive.testzip() is None, 'ZIP integrity check failed'
        print('IPA structure, arm64 executables, extension embedding, identifiers, and ZIP integrity verified.')

if __name__=='__main__': verify(sys.argv[1])
