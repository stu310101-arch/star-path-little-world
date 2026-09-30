"""Import the five supplied tracks without recomposing or transcoding them.

The generated standalone players embed the same original Ogg as base64 DATA.
Read that literal only; never execute downloaded HTML/JavaScript.
"""
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = Path.home() / 'Downloads'
OUT = ROOT / 'deliverables/music-integration'
DEST = ROOT / 'game/assets/audio/music'
TRACKS = {
    'world': ('Campus_Orbit_96s_Loop.ogg', 'Campus_Orbit_Seamless_Player.html', 96),
    'admissions': ('Region01_Quiet_Coordinates_120s_Loop.ogg', 'Region01_Seamless_Player.html', 120),
    'wordking': ('Training_Pulse_120s_Loop.ogg', 'Training_Pulse_Seamless_Player.html', 120),
    'recommendations': ('Pixie_Compass_120s_Loop.ogg', 'Pixie_Compass_Seamless_Player.html', 120),
    'counseling': ('Warm_Window_120s_Loop.ogg', 'Warm_Window_Seamless_Player.html', 120),
}
OUT.mkdir(parents=True, exist_ok=True)
DEST.mkdir(parents=True, exist_ok=True)
rows = []
for context, (filename, player_name, seconds) in TRACKS.items():
    ogg, player = DOWNLOADS / filename, DOWNLOADS / player_name
    target = DEST / filename
    if ogg.exists():
        data, source, method = ogg.read_bytes(), ogg, 'original Ogg bytes'
    elif player.exists():
        text = player.read_text(encoding='utf-8-sig')
        match = re.search(r"\bconst\s+DATA\s*=\s*(['\"])([A-Za-z0-9+/=\r\n]+)\1", text)
        if not match:
            raise ValueError(f'No explicit base64 DATA literal in {player}')
        data = base64.b64decode(re.sub(r'\s+', '', match[2]), validate=True)
        source, method = player, 'original Ogg extracted from standalone player DATA literal'
    else:
        rows.append({'context': context, 'file': filename, 'available': False})
        continue
    if not data.startswith(b'OggS'):
        raise ValueError(f'{source} does not contain an Ogg bitstream')
    staging = OUT / (filename + '.verify.ogg')
    staging.write_bytes(data)
    try:
        probe = json.loads(subprocess.check_output([
            'C:/ffmpeg/bin/ffprobe.exe', '-v', 'error', '-show_entries',
            'format=duration,size:stream=codec_name,sample_rate,channels', '-of', 'json', str(staging)
        ], text=True, encoding='utf-8'))
        stream = probe['streams'][0]
        assert stream['codec_name'] == 'vorbis' and stream['channels'] == 2, probe
        assert stream['sample_rate'] == '48000', probe
        assert abs(float(probe['format']['duration']) - seconds) < .01, probe
        subprocess.run(['C:/ffmpeg/bin/ffmpeg.exe', '-hide_banner', '-v', 'error',
                        '-i', str(staging), '-f', 'null', '-'], check=True)
        target.write_bytes(data)
    finally:
        staging.unlink(missing_ok=True)
    rows.append({'context': context, 'file': filename, 'available': True,
                 'source': str(source), 'method': method, 'size_bytes': len(data),
                 'sha256': hashlib.sha256(data).hexdigest(), 'probe': probe,
                 'full_decode_passed': True})
report = {'source_conversation': '6ab31c75-e460-83e8-a258-f86c2cc51f58',
          'all_five_available': all(row['available'] for row in rows), 'tracks': rows}
(OUT / 'source-audio.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'all_five_available': report['all_five_available'],
                  'available': [row['context'] for row in rows if row['available']],
                  'missing': [row['context'] for row in rows if not row['available']]}, ensure_ascii=False))
