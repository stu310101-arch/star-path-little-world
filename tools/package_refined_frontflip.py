"""Package only frames listed by the verified native capture, at source timing."""
import json,subprocess
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'deliverables/frontflip-refined'
STUDIO=OUT/'studio'
FFMPEG='C:/ffmpeg/bin/ffmpeg.exe'
summary=json.loads((STUDIO/'capture.json').read_text(encoding='utf8'))
assert summary['passed'],summary
movies=[]
for sequence in summary['sequences']:
 manifest=STUDIO/sequence['manifest'];data=json.loads(manifest.read_text(encoding='utf8'))
 assert data['passed']
 frames=[f for f in data['frames'] if f['view']=='front']
 timeline=[]
 for i,row in enumerate(frames):
  filename=(manifest.parent/row['file']).resolve().as_posix().replace("'","'\\''")
  duration=frames[i+1]['seconds']-row['seconds'] if i+1<len(frames) else .5
  timeline.extend(["file '"+filename+"'",f'duration {duration:.6f}'])
 timeline.append(timeline[-2])
 concat=manifest.parent/'timeline.ffconcat';concat.write_text('\n'.join(timeline)+'\n',encoding='utf8')
 movie=OUT/(sequence['sequence']+'-frontflip.mp4')
 subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(concat),'-vf','fps=30','-c:v','libx264','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(movie)],check=True)
 movies.append(movie)
 if sequence['sequence']=='standing':
  selected=[f for f in data['frames'] if f['view']=='side' and f['phase'] in ['02-anticipation','04-tuck','05-inverted','06-opening','07-contact','08-settle-020','09-settle-060','10-settle-100','11-recovered']]
  canvas=Image.new('RGB',(1320,1152),'#26373d');draw=ImageDraw.Draw(canvas)
  for i,row in enumerate(selected):
   im=Image.open(manifest.parent/row['file']).convert('RGB');im.thumbnail((440,360))
   x=i%3*440;y=i//3*384;canvas.paste(im,(x,y));draw.text((x+10,y+362),row['phase']+'  '+str(round(row['seconds'],2))+'s',fill='white')
  canvas.save(OUT/'godot-contact-sheet.jpg')
concat=OUT/'movies.ffconcat';concat.write_text(''.join("file '"+p.as_posix()+"'\n" for p in movies),encoding='utf8')
subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart',str(OUT/'frontflip-refined-preview.mp4')],check=True)
print('PACKAGED_REFINED_PREVIEW',str(OUT/'frontflip-refined-preview.mp4'))
