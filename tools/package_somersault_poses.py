"""Arrange the eight actual Blender renders for motion review."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'deliverables/gameplay-jump'
files=sorted((folder/'blender-poses').glob('*.png'))
assert len(files)==8
canvas=Image.new('RGB',(1680,1072),'#1d2428')
draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
labels=['01 Neutral / exact Idle0','02 Anticipation / 0.09 s','03 Takeoff / 35 degrees','04 Inversion / tucked knees','05 Forward rotation / 250 degrees','06 Extend for landing','07 Landing compression','08 Recover / exact Idle0']
draw.text((20,14),'AUTHORED FORWARD SOMERSAULT | actual Blender camera renders | in-place asset, game supplies trajectory',font=small,fill='#f1e2c2')
for i,(path,label) in enumerate(zip(files,labels)):
    x=(i%4)*420;y=48+(i//4)*512
    canvas.paste(Image.open(path).convert('RGB'),(x,y))
    draw.text((x+12,y+484),label,font=small,fill='#f1e2c2')
canvas.save(folder/'blender-contact-sheet.jpg',quality=94)
print(folder/'blender-contact-sheet.jpg')
