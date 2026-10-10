#!/usr/bin/env python3
"""Optional deterministic artwork regeneration (Pillow; never needed to build the app)."""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'Fitness/Resources/Assets.xcassets'
def metadata(folder,data):
    folder.mkdir(parents=True,exist_ok=True)
    (folder/'Contents.json').write_text(json.dumps(data,indent=2)+'\n')
metadata(ASSETS,{'info':{'author':'xcode','version':1}})
size=1024
icon=Image.new('RGB',(size,size)); pixels=icon.load()
for y in range(size):
    for x in range(size):
        glow=max(0,1-math.hypot(x-300,y-250)/950)
        pixels[x,y]=(int(10+8*glow),int(27+22*glow),int(35+24*glow))
draw=ImageDraw.Draw(icon)
draw.arc((130,130,894,894), start=198,end=502,fill=(60,225,174),width=24)
draw.arc((150,150,874,874), start=218,end=260,fill=(248,180,85),width=10)
mark=Image.new('RGBA',(1024,1024)); d=ImageDraw.Draw(mark)
mint=(105,244,198,255)
d.rounded_rectangle((268,468,756,556),radius=44,fill=mint)
d.rounded_rectangle((252,358,338,666),radius=34,fill=mint)
d.rounded_rectangle((354,407,419,617),radius=25,fill=mint)
d.rounded_rectangle((686,358,772,666),radius=34,fill=mint)
d.rounded_rectangle((605,407,670,617),radius=25,fill=mint)
mark=mark.rotate(-28,resample=Image.Resampling.BICUBIC)
icon.paste(mark,mask=mark.getchannel('A'))
folder=ASSETS/'AppIcon.appiconset'; metadata(folder,{'images':[{'filename':'AppIcon-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}})
icon.save(folder/'AppIcon-1024.png')
launch=ASSETS/'LaunchMark.imageset'; metadata(launch,{'images':[{'filename':'LaunchMark.png','idiom':'universal'}],'info':{'author':'xcode','version':1}})
mark.crop((175,175,849,849)).resize((240,240),Image.Resampling.LANCZOS).save(launch/'LaunchMark.png')
for name,color in [('AccentColor',(0.06,0.64,0.48)),('LaunchBackground',(0.04,0.11,0.14))]:
    metadata(ASSETS/(name+'.colorset'),{'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':dict(zip(['red','green','blue'],[f'{v:.3f}' for v in color]),alpha='1.000')}}],'info':{'author':'xcode','version':1}})
print('Generated opaque 1024px icon, launch artwork, and named colors.')
