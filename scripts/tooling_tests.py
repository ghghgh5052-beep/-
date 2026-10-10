#!/usr/bin/env python3
"""Portable tests for build tooling only; synthetic binaries never become deliverables."""
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
TEMP_ROOT=(ROOT/'build/tooling-temporary').resolve()
assert TEMP_ROOT.is_relative_to(ROOT.resolve())
TEMP_ROOT.mkdir(parents=True,exist_ok=True)

class PackagingTests(unittest.TestCase):
    def fixture(self, folder, *, group='group.test', signature=False, missing=False):
        path=Path(folder)/'synthetic-tooling-fixture.zip'
        info={'CFBundleIdentifier':'com.test.app','CFBundleExecutable':'Fitness','SharedAppGroup':'group.test','CFBundleVersion':'1','NSSupportsLiveActivities':True}
        ext={'CFBundleIdentifier':'com.test.app.widgets','CFBundleExecutable':'FitnessWidgets','SharedAppGroup':group,'CFBundleVersion':'1','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
        header=struct.pack('<II',0xFEEDFACF,0x0100000C)+bytes(24)
        with zipfile.ZipFile(path,'w') as archive:
            archive.writestr('Payload/Fitness.app/Info.plist',plistlib.dumps(info))
            archive.writestr('Payload/Fitness.app/Fitness',header)
            if not missing:
                archive.writestr('Payload/Fitness.app/PlugIns/FitnessWidgets.appex/Info.plist',plistlib.dumps(ext))
                archive.writestr('Payload/Fitness.app/PlugIns/FitnessWidgets.appex/FitnessWidgets',header)
            if signature: archive.writestr('Payload/Fitness.app/_CodeSignature/CodeResources',b'fixture')
        return path

    def testStructureValidatorAcceptsExpectedArm64Headers(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder, contextlib.redirect_stdout(io.StringIO()): verify(self.fixture(folder))
    def testMissingExtensionIsRejected(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            with self.assertRaises(KeyError): verify(self.fixture(folder,missing=True))
    def testMismatchedGroupIsRejected(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            with self.assertRaises(AssertionError): verify(self.fixture(folder,group='wrong'))
    def testSignedBundleIsRejected(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            with self.assertRaises(AssertionError): verify(self.fixture(folder,signature=True))
    def testEntitlementVariablesResolveWithoutTeamFabrication(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as folder:
            path=Path(folder)/'settings.json'
            path.write_text(json.dumps([{'target':'Fitness','buildSettings':{'CODE_SIGN_ENTITLEMENTS':'Config/Fitness.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'com.test.app','CLOUDKIT_CONTAINER_IDENTIFIER':'iCloud.com.test.app','CLOUDKIT_ENVIRONMENT':'Development','APP_GROUP_IDENTIFIER':'group.com.test.app','APS_ENVIRONMENT':'development'}},{'target':'FitnessWidgets','buildSettings':{'CODE_SIGN_ENTITLEMENTS':'Config/FitnessWidgets.entitlements','PRODUCT_BUNDLE_IDENTIFIER':'com.test.app.widgets','APP_GROUP_IDENTIFIER':'group.com.test.app'}}]))
            subprocess.run([sys.executable,str(ROOT/'scripts/resolve_entitlements.py'),str(path),folder],check=True,capture_output=True)
            app=plistlib.loads((Path(folder)/'Fitness.resolved.entitlements').read_bytes())
            widget=plistlib.loads((Path(folder)/'FitnessWidgets.resolved.entitlements').read_bytes())
            self.assertEqual(app['com.apple.developer.icloud-container-identifiers'],['iCloud.com.test.app'])
            self.assertEqual(set(widget),{'com.apple.security.application-groups'})
            self.assertNotIn('application-identifier',app)
    def testProjectGraphAndPlists(self):
        with contextlib.redirect_stdout(io.StringIO()): validate()
    def testOpenStepParserRejectsMalformedGraph(self):
        with self.assertRaises(ValueError): parse_openstep('{ key = "value" }')

if __name__=='__main__': unittest.main(verbosity=2)
