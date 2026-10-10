#!/usr/bin/env python3
"""Validate OpenStep project membership and configuration without requiring Xcode."""
from pathlib import Path
import json
import hashlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]

def parse_openstep(text):
    text=re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)
    tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text)
    index=0
    def take(expected=None):
        nonlocal index
        if index>=len(tokens): raise ValueError('Unexpected end of project')
        value=tokens[index]; index+=1
        if expected is not None and value!=expected: raise ValueError(f'Expected {expected}; got {value}')
        return value
    def value():
        token=take()
        if token=='{':
            result={}
            while tokens[index]!='}':
                key=take(); key=json.loads(key) if key.startswith('"') else key
                take('='); result[key]=value(); take(';')
            take('}'); return result
        if token=='(':
            result=[]
            while tokens[index]!=')':
                result.append(value())
                if tokens[index]==',': take(',')
            take(')'); return result
        return json.loads(token) if token.startswith('"') else token
    result=value()
    if index!=len(tokens): raise ValueError('Extra project tokens')
    return result

def validate():
    data=parse_openstep((ROOT/'Wateera.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))
    objects=data['objects']; project=objects[data['rootObject']]
    assert project['isa']=='PBXProject'
    targets={objects[t]['name']:objects[t] for t in project['targets']}
    assert set(targets)=={'Fitness','FitnessWidgets','FitnessTests','FitnessUITests'}
    for identifier, item in objects.items():
        assert re.fullmatch('[0-9A-F]{24}',identifier)
        if item['isa']=='PBXFileReference' and item['sourceTree']=='<group>':
            assert (ROOT/item['path']).exists(), f'Missing referenced file: {item["path"]}'
        for key in ['fileRef','productReference','buildConfigurationList','containerPortal','target','targetProxy','baseConfigurationReference','mainGroup','productRefGroup']:
            if key in item: assert item[key] in objects, f'Dangling {key}'
        for key in ['files','children','buildConfigurations','buildPhases','dependencies','targets']:
            for reference in item.get(key,[]): assert reference in objects,f'Dangling {key}'
    def sources(name):
        return {objects[objects[file]['fileRef']]['path'] for phase in targets[name]['buildPhases'] if objects[phase]['isa']=='PBXSourcesBuildPhase' for file in objects[phase]['files']}
    app={str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'Fitness').rglob('*.swift')}
    assert sources('Fitness')==app,'Run python3 scripts/generate_project.py after adding app source files'
    assert sources('FitnessWidgets')=={'Fitness/Shared/WorkoutActivityAttributes.swift'}|{str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'FitnessWidgets').glob('*.swift')}
    for name in ['FitnessTests','FitnessUITests']:
        assert sources(name)=={str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/name).glob('*.swift')},'Stale test membership'
    embed=[objects[p] for p in targets['Fitness']['buildPhases'] if objects[p]['isa']=='PBXCopyFilesBuildPhase']
    assert len(embed)==1 and embed[0]['dstSubfolderSpec']=='13' and len(embed[0]['files'])==1
    for path in list((ROOT/'Config').glob('*.entitlements'))+list(ROOT.glob('Fitness*/Info.plist'))+list((ROOT/'Fitness/Resources').glob('*.plist'))+list((ROOT/'Fitness/Resources').glob('*.xcprivacy')):
        plistlib.loads(path.read_bytes())
    info=plistlib.loads((ROOT/'Fitness/Resources/Info.plist').read_bytes())
    widget=plistlib.loads((ROOT/'FitnessWidgets/Info.plist').read_bytes())
    assert info['CFBundleDevelopmentRegion']==widget['CFBundleDevelopmentRegion']=='ar'
    assert info['SharedAppGroup']==widget['SharedAppGroup']=='$(APP_GROUP_IDENTIFIER)'
    assert 'remote-notification' in info['UIBackgroundModes']
    ET.parse(ROOT/'Wateera.xcodeproj/xcshareddata/xcschemes/Wateera.xcscheme')
    icon=ROOT/'Fitness/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
    header=icon.read_bytes()[:33]
    import struct
    assert header[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',header[16:24])==(1024,1024)
    assert header[25]==2,'App icon must be RGB without alpha'
    art_root=ROOT/'Fitness/Resources/Assets.xcassets'
    art=json.loads((ROOT/'Fitness/Resources/ExerciseArtManifest.json').read_text(encoding='utf-8'))
    assert [item['code'] for item in art['images']]==list(range(1,67)), 'Exercise artwork must cover all 66 catalog IDs'
    assert len({item['sha256'] for item in art['images']})==66, 'Exercise artwork must not reuse unrelated images'
    expected_assets=set()
    for item in art['images']:
        name=f'exercise_{item["code"]:03d}'
        assert item['asset']==name
        folder=art_root/(name+'.imageset'); expected_assets.add(folder.name)
        contents=json.loads((folder/'Contents.json').read_text(encoding='utf-8'))
        assert contents['images']==[{'filename':name+'.png','idiom':'universal'}], 'Unexpected image asset configuration'
        image=(folder/(name+'.png')).read_bytes()
        assert image[:8]==b'\x89PNG\r\n\x1a\n', 'Exercise image must be PNG'
        width,height=struct.unpack('>II',image[16:24])
        assert width>=1024 and height>=640 and width>height, 'Exercise image must be a clear landscape canvas'
        assert hashlib.sha256(image).hexdigest()==item['sha256'] and len(image)==item['bytes'], 'Artwork provenance checksum mismatch'
    assert {p.name for p in art_root.glob('exercise_*.imageset')}==expected_assets, 'Unexpected or incomplete exercise assets'
    prompts=json.loads((ROOT/'scripts/exercise_art_prompts.json').read_text(encoding='utf-8'))
    assert [item['code'] for item in prompts['entries']]==list(range(1,67))
    review=json.loads((ROOT/'docs/EXERCISE_ART_REVIEW.json').read_text(encoding='utf-8'))
    assert [item['code'] for item in review['entries']]==list(range(1,67)), 'Every exercise requires an actual visual review'
    art_hashes={item['code']:item['sha256'] for item in art['images']}
    assert all(item['status']=='pass' and item['sha256']==art_hashes[item['code']] for item in review['entries']), 'A changed image requires a new visual review'
    for p in (ROOT/'Fitness').rglob('*.swift'):
        text=p.read_text(encoding='utf-8')
        assert not re.search(r'\btry!|\bas!|fatalError\s*\(|preconditionFailure\s*\(',text),f'Unsafe production path: {p}'
    print(f'Validated project graph, {len(app)} app sources, embedded extension, Arabic plists, entitlements, scheme, opaque 1024px icon, and 66 reviewed exercise canvases.')

if __name__=='__main__':
    try: validate()
    except (AssertionError,ValueError,KeyError,IndexError) as error: sys.exit('Project validation failed: '+str(error))
