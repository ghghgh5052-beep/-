#!/usr/bin/env python3
"""Portable local-build regressions. Synthetic headers never become deliverables."""
import contextlib
import io
import json
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from verify_ipa import verify
from validate_project import parse_openstep, validate, ROOT
TEMP_ROOT=ROOT/'build/tooling-temporary';TEMP_ROOT.mkdir(parents=True,exist_ok=True)
class PackagingTests(unittest.TestCase):
    def fixture(self, folder, *, extension=False, signature=False, cloud=False, intent=False, profile=False, simulator=False):
        path=Path(folder)/'synthetic-tooling-fixture.zip'
        info={'CFBundleIdentifier':'com.test.app','CFBundleExecutable':'Fitness','CFBundleVersion':'1','UIApplicationShortcutItems':[{}, {}, {}]}
        if cloud: info['CloudKitContainerIdentifier']='iCloud.test'
        header=struct.pack('<II',0xFEEDFACF,0x01000007 if simulator else 0x0100000C)+bytes(24)
        with zipfile.ZipFile(path,'w') as archive:
            archive.writestr('Payload/Fitness.app/Info.plist',plistlib.dumps(info))
            archive.writestr('Payload/Fitness.app/Fitness',header)
            if extension: archive.writestr('Payload/Fitness.app/PlugIns/FitnessWidgets.appex/FitnessWidgets',header)
            if signature: archive.writestr('Payload/Fitness.app/_CodeSignature/CodeResources',b'fixture')
            if cloud: archive.writestr('Payload/Fitness.app/cloud-fixture',b'fixture')
            if intent: archive.writestr('Payload/Fitness.app/Metadata.appintents/extract.actionsdata',b'{}')
            if profile: archive.writestr('Payload/Fitness.app/embedded.mobileprovision',b'fixture')
        return path
    def testExpectedLocalArm64Structure(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder, contextlib.redirect_stdout(io.StringIO()): verify(self.fixture(folder))
    def testDeferredAndSignedArtifactsAreRejected(self):
        for option in ['extension','signature','cloud','intent','profile','simulator']:
            with self.subTest(option=option), tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
                with self.assertRaises(AssertionError): verify(self.fixture(folder,**{option:True}))
    def testLocalEntitlementsResolveWithoutFabricatingSigningIdentity(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            path=Path(folder)/'settings.json'
            path.write_text(json.dumps([{'target':'Fitness','buildSettings':{'CODE_SIGN_ENTITLEMENTS':'Config/Fitness.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'com.personal.Wateera'}}]))
            subprocess.run([sys.executable,str(ROOT/'scripts/resolve_entitlements.py'),str(path),folder],check=True,capture_output=True)
            self.assertEqual(plistlib.loads((Path(folder)/'Fitness.resolved.entitlements').read_bytes()),{})
            self.assertFalse((Path(folder)/'FitnessWidgets.resolved.entitlements').exists())
    def testMissingShippingTargetCannotProduceManifest(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            path=Path(folder)/'settings.json'; path.write_text('[]')
            result=subprocess.run([sys.executable,str(ROOT/'scripts/resolve_entitlements.py'),str(path),folder],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((Path(folder)/'Fitness.resolved.entitlements').exists())
    def testProjectGraphAndPlists(self):
        with contextlib.redirect_stdout(io.StringIO()): validate()
    def testOpenStepParserRejectsMalformedGraph(self):
        with self.assertRaises(ValueError): parse_openstep('{ key = "value" }')
    def testLightAndDarkIconsAreOpaqueAndDistinct(self):
        import hashlib
        hashes=[]
        for name in ['AppIcon-1024.png','AppIcon-1024-dark.png']:
            data=(ROOT/'Fitness/Resources/Assets.xcassets/AppIcon.appiconset'/name).read_bytes()
            self.assertEqual(struct.unpack('>II',data[16:24]),(1024,1024)); self.assertEqual(data[25],2)
            hashes.append(hashlib.sha256(data).hexdigest())
        self.assertNotEqual(*hashes)
if __name__=='__main__': unittest.main(verbosity=2)
