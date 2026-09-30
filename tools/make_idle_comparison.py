"""Compare equal-time Godot recordings with identical framing and crop."""
import json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ANIM=ROOT/'art/Graduate/animation'
ffmpeg=r'C:\ffmpeg\bin\ffmpeg.exe'
font='C\\:/Windows/Fonts/arial.ttf'
filters=[]
for i,(label,side) in enumerate([('Before - 5 mm','left'),('After - 22 mm','right')]):
    filters.append(f"[{i}:v]crop=300:360:426:140,scale=600:720,drawtext=fontfile='{font}':text='{label}':x=24:y=24:fontsize=28:fontcolor=white[{side}]")
filters.append('[left][right]hstack=inputs=2[out]')
command=[ffmpeg,'-hide_banner','-loglevel','error','-y',
         '-i',str(ANIM/'idle_preview_subtle.mp4'),'-i',str(ANIM/'idle_readable_preview.mp4'),
         '-filter_complex',';'.join(filters),'-map','[out]','-an','-c:v','libx264',
         '-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(ANIM/'idle_before_after.mp4')]
subprocess.run(command,check=True)
print(json.dumps({'comparison':str(ANIM/'idle_before_after.mp4'),
 'left':'Previous 5 mm body rise','right':'New 22 mm body rise',
 'crop':'Identical x426 y140 w300 h360, scaled equally to600x720; cameras unchanged'},indent=2))
