#!/usr/bin/env python3
"""Deterministic Xcode project generator using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def uid(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def obj(key, isa, **values):
    identifier = uid(key)
    objects[identifier] = dict(isa=isa, **values)
    return identifier

def ref(path, kind=None):
    if kind is None:
        kind = {'swift':'sourcecode.swift','plist':'text.plist.xml','xcconfig':'text.xcconfig','entitlements':'text.plist.entitlements','xcprivacy':'text.xml','xcassets':'folder.assetcatalog'}.get(path.rsplit('.',1)[-1], 'text')
    return obj('file:'+path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

def phase(key, kind, files):
    builds = [obj('build:'+key+':'+file, 'PBXBuildFile', fileRef=ref(file)) for file in files]
    return obj('phase:'+key, kind, buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)

def configurations(key, settings):
    configs=[]
    for name in ['Debug','Release']:
        values = dict(settings)
        if key == 'project':
            values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if name=='Debug' else 'dwarf-with-dsym', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if name=='Debug' else '', ENABLE_TESTABILITY='YES' if name=='Debug' else 'NO')
        configs.append(obj('config:'+key+name,'XCBuildConfiguration',baseConfigurationReference=ref('Config/Identifiers.xcconfig'),buildSettings=values,name=name))
    return obj('configs:'+key, 'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

def target(name, product_type, extension, sources, resources, settings):
    product = obj('product:'+name,'PBXFileReference',explicitFileType=extension,includeInIndex=0,path=name+('.app' if name=='Fitness' else '.appex' if name=='FitnessWidgets' else '.xctest'),sourceTree='BUILT_PRODUCTS_DIR')
    phases = [phase(name+'Sources','PBXSourcesBuildPhase',sources),phase(name+'Resources','PBXResourcesBuildPhase',resources),obj('phase:'+name+'Frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)]
    return obj('target:'+name, 'PBXNativeTarget',buildConfigurationList=configurations(name,settings),buildPhases=phases,buildRules=[],dependencies=[],name=name,productName=name,productReference=product,productType=product_type)

shared = 'Fitness/Shared/WorkoutActivityAttributes.swift'
deferred_sources = set(json.loads((ROOT/'Config/DeferredSources.json').read_text()))
app_sources = sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'Fitness').rglob('*.swift') if str(p.relative_to(ROOT)).replace('\\','/') not in deferred_sources)
widget_sources = sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'FitnessWidgets').glob('*.swift')) + [shared]
common=dict(PRODUCT_NAME='$(TARGET_NAME)', SDKROOT='iphoneos', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO', GENERATE_INFOPLIST_FILE='NO', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks')
app=target('Fitness','com.apple.product-type.application','wrapper.application',app_sources,['Fitness/Resources/Assets.xcassets','Fitness/Resources/PrivacyInfo.xcprivacy'],dict(common,PRODUCT_BUNDLE_IDENTIFIER='$(BUNDLE_IDENTIFIER)',PRODUCT_MODULE_NAME='Fitness',INFOPLIST_FILE='Fitness/Resources/Info.plist',CODE_SIGN_ENTITLEMENTS='Config/Fitness.entitlements',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME='AccentColor',SKIP_INSTALL='NO'))
targets=[app]
for name in ['FitnessTests','FitnessUITests']:
    files=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/name).glob('*.swift'))
    values=dict(common,PRODUCT_BUNDLE_IDENTIFIER='$(BUNDLE_IDENTIFIER).'+('tests' if name=='FitnessTests' else 'uitests'),GENERATE_INFOPLIST_FILE='YES',CODE_SIGN_ENTITLEMENTS='Config/'+name+'.entitlements',SKIP_INSTALL='YES')
    if name=='FitnessTests': values.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/Fitness.app/Fitness',BUNDLE_LOADER='$(TEST_HOST)')
    else: values.update(TEST_TARGET_NAME='Fitness')
    test=target(name,'com.apple.product-type.bundle.unit-test' if name=='FitnessTests' else 'com.apple.product-type.bundle.ui-testing','wrapper.cfbundle',files,[],values)
    targets.append(test)
project_id=uid('project')
for name,source,destination in [('TestHost',targets[1],app),('UITestHost',targets[2],app)]:
    proxy=obj('proxy:'+name,'PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=destination,remoteInfo=objects[destination]['name'])
    dependency=obj('dependency:'+name,'PBXTargetDependency',target=destination,targetProxy=proxy)
    objects[source]['dependencies'].append(dependency)
products=obj('group:products','PBXGroup',children=[objects[t]['productReference'] for t in targets],name='Products',sourceTree='<group>')
files=sorted(set(app_sources+widget_sources+list(deferred_sources)+[str(p.relative_to(ROOT)).replace('\\','/') for folder in ['FitnessTests','FitnessUITests','Config'] for p in (ROOT/folder).glob('*') if p.is_file()]+['Fitness/Resources/Info.plist','FitnessWidgets/Info.plist','Fitness/Resources/Assets.xcassets','Fitness/Resources/PrivacyInfo.xcprivacy']))
main=obj('group:main','PBXGroup',children=[ref(p) for p in files]+[products],sourceTree='<group>')
objects[project_id]=dict(isa='PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{t:{'CreatedOnToolsVersion':'16.0'} for t in targets}},buildConfigurationList=configurations('project',{'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER':'YES','GCC_WARN_64_TO_32_BIT_CONVERSION':'YES','GCC_WARN_UNDECLARED_SELECTOR':'YES','GCC_WARN_UNUSED_FUNCTION':'YES','GCC_WARN_UNUSED_VARIABLE':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='ar',hasScannedForEncodings=0,knownRegions=['ar','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=targets)

def render(value, indent=0):
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(indent+1)+json.dumps(str(k))+ ' = '+render(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+render(v,indent+1)+',\n' for v in value)+'\t'*indent+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)

project=ROOT/'Wateera.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':dict(sorted(objects.items())),'rootObject':project_id})+'\n',encoding='utf-8')
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def buildable(target_name):
    suffix='.app' if target_name=='Fitness' else '.xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+target_name)}" BuildableName="{target_name}{suffix}" BlueprintName="{target_name}" ReferencedContainer="container:Wateera.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('Fitness')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable('FitnessTests')}</TestableReference><TestableReference skipped="NO">{buildable('FitnessUITests')}</TestableReference></Testables><EnvironmentVariables><EnvironmentVariable key="FITNESS_TESTING" value="1" isEnabled="YES"/></EnvironmentVariables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('Fitness')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('Fitness')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(schemes/'Wateera.xcscheme').write_text(scheme,encoding='utf-8')
print(f'Generated project: {len(app_sources)} app sources, no embedded extensions, {len(targets)} targets.')
