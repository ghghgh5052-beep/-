#!/usr/bin/env python3
"""Regenerate the geometric brand assets (optional Pillow, no runtime dependency)."""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'Fitness/Resources/Assets.xcassets'
def metadata(folder,data):
    folder.mkdir(parents=True,exist_ok=True)
    (folder/'Contents.json').write_text(json.dumps(data,indent=2)+'\n')
info={'author':'xcode','version':1}
metadata(ASSETS,{'info':info})

def barbell(color):
    mark=Image.new('RGBA',(2048,2048)); d=ImageDraw.Draw(mark)
    d.rounded_rectangle((465,950,1583,1098),radius=74,fill=color)
    for x,height,width in [(536,660,144),(719,446,114),(1368,660,144),(1215,446,114)]:
        d.rounded_rectangle((x,1024-height//2,x+width,1024+height//2),radius=width//2,fill=color)
    return mark.rotate(-30,resample=Image.Resampling.BICUBIC)

for dark in [False,True]:
    base=(12,25,37) if dark else (231,247,239)
    brand=(121,240,198) if dark else (0,111,87)
    image=Image.new('RGB',(1024,1024)); pixels=image.load()
    for y in range(1024):
        for x in range(1024):
            glow=max(0,1-math.hypot(x-300,y-220)/1024)
            pixels[x,y]=tuple(min(255,int(v+glow*(10 if dark else 7))) for v in base)
    d=ImageDraw.Draw(image)
    muted=(37,70,74) if dark else (175,220,204)
    d.arc((119,119,905,905),start=144,end=421,fill=muted,width=13)
    d.arc((119,119,905,905),start=292,end=421,fill=brand,width=18)
    mark=barbell(brand+(255,)).resize((1024,1024),Image.Resampling.LANCZOS)
    image.paste(mark,mask=mark.getchannel('A'))
    filename='AppIcon-1024-dark.png' if dark else 'AppIcon-1024.png'
    image.save(ASSETS/'AppIcon.appiconset'/filename)
    launch_name='LaunchMark-dark.png' if dark else 'LaunchMark.png'
    mark.crop((230,230,794,794)).resize((240,240),Image.Resampling.LANCZOS).save(ASSETS/'LaunchMark.imageset'/launch_name)

metadata(ASSETS/'AppIcon.appiconset',{'images':[
    {'filename':'AppIcon-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'},
    {'filename':'AppIcon-1024-dark.png','idiom':'universal','platform':'ios','size':'1024x1024','appearances':[{'appearance':'luminosity','value':'dark'}]}
], 'info':info})
metadata(ASSETS/'LaunchMark.imageset',{'images':[
    {'filename':'LaunchMark.png','idiom':'universal'},
    {'filename':'LaunchMark-dark.png','idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}]}
], 'info':info})
for name,light,dark in [('AccentColor',(0,0.498,0.392),(0.384,0.91,0.749)),('LaunchBackground',(0.953,0.961,0.973),(0.043,0.063,0.094))]:
    colors=[]
    for is_dark,values in [(False,light),(True,dark)]:
        entry={'idiom':'universal','color':{'color-space':'srgb','components':dict(zip(['red','green','blue'],[f'{v:.3f}' for v in values]),alpha='1.000')}}
        if is_dark: entry['appearances']=[{'appearance':'luminosity','value':'dark'}]
        colors.append(entry)
    metadata(ASSETS/(name+'.colorset'),{'colors':colors,'info':info})
print('Generated opaque 1024px light/dark icons and adaptive launch artwork/colors.')
