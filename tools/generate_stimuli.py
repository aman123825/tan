from __future__ import annotations
import argparse,asyncio,csv,json,math,random,struct,wave
from pathlib import Path
RATE=48000

def wav(path,samples):
    path.parent.mkdir(parents=True,exist_ok=True)
    peak=max(1,max(abs(x) for x in samples));scale=.82*32767/peak
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(b''.join(struct.pack('<h',int(max(-32767,min(32767,x*scale)))) for x in samples))
def tone(freq,d=.5,amp=.25):return [amp*math.sin(2*math.pi*freq*i/RATE) for i in range(int(RATE*d))]
def noise(d=.5,amp=.2,seed=1):
    r=random.Random(seed);return [amp*r.uniform(-1,1) for _ in range(int(RATE*d))]
def gap_noise(gap_ms,seed=1):
    x=noise(.8,.2,seed);mid=len(x)//2;n=int(RATE*gap_ms/1000);x[mid-n//2:mid+n//2]=[0]*n;return x
def am_noise(rate_hz,depth_db,d=.8,seed=1):
    x=noise(d,.2,seed);depth=10**(depth_db/20)
    return [v*((1-depth)+depth*(.5+.5*math.sin(2*math.pi*rate_hz*i/RATE))) for i,v in enumerate(x)]
def contour(pattern,root=440,step=2):
    maps={'rise':[0,1,2,3,4],'fall':[4,3,2,1,0],'flat':[0,0,0,0,0],'rise_fall':[0,2,4,2,0],'fall_rise':[4,2,0,2,4],'rise_flat':[0,2,4,4,4],'flat_rise':[0,0,0,2,4],'fall_flat':[4,2,0,0,0],'flat_fall':[4,4,4,2,0]}
    out=[]
    for v in maps[pattern]:out+=tone(root*2**((v*step)/12),.22,.2)+[0]*int(.03*RATE)
    return out
SPEECH=[
('w001','Please close the blue window.'),('w002','Meet me near the main entrance.'),('w003','The class begins at nine thirty.'),('w004','Turn left after the second signal.'),('w005','Write down the name and phone number.'),('w006','The meeting moved to Friday afternoon.'),('w007','Bring the red folder and two pens.'),('w008','Call me when you reach the station.'),('w009','The teacher changed the final question.'),('w010','Order tea without sugar, please.'),
('w011','The bus arrives at platform six.'),('w012','Keep the medicine beside the water.'),('w013','First open the file, then read page four.'),('w014','The restaurant is crowded this evening.'),('w015','Repeat the address after the tone.'),('w016','Amit will join the call at five.'),('w017','The television volume is already low.'),('w018','Choose the third option on the screen.'),('w019','Remember the date, place, and time.'),('w020','Walk past the bank and cross the road.')]
async def speech(out):
    try:
        import edge_tts
    except Exception as e:
        print('edge-tts unavailable:',e);return []
    made=[]
    voices=['en-IN-NeerjaNeural','en-IN-PrabhatNeural']
    for i,(sid,text) in enumerate(SPEECH):
        p=out/f'{sid}_{i%2}.mp3';await edge_tts.Communicate(text,voices[i%2],rate='+0%').save(str(p));made.append((sid,text,voices[i%2],p.name))
    return made
async def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',default='stimuli/demo');ap.add_argument('--skip-speech',action='store_true');a=ap.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
    manifest=[]
    for f in [250,500,1000,2000,4000]:p=out/f'tone_{f}.wav';wav(p,tone(f));manifest.append({'id':p.stem,'kind':'tone','file':p.name,'frequency_hz':f})
    for g in [2,5,10,20,40]:p=out/f'gap_{g}ms.wav';wav(p,gap_noise(g,g));manifest.append({'id':p.stem,'kind':'gap','file':p.name,'gap_ms':g})
    for r in [10,20,50,100,200]:p=out/f'am_{r}hz.wav';wav(p,am_noise(r,-12,.8,r));manifest.append({'id':p.stem,'kind':'modulation','file':p.name,'rate_hz':r,'depth_db':-12})
    for n in ['steady','babble_demo']:p=out/f'noise_{n}.wav';wav(p,noise(2,.2,7 if n=='steady' else 9));manifest.append({'id':p.stem,'kind':'noise','file':p.name})
    for pat in ['rise','fall','flat','rise_fall','fall_rise','rise_flat','flat_rise','fall_flat','flat_fall']:
        p=out/f'mci_{pat}.wav';wav(p,contour(pat));manifest.append({'id':p.stem,'kind':'mci','file':p.name,'pattern':pat})
    if not a.skip_speech:
        for sid,text,voice,file in await speech(out):manifest.append({'id':sid,'kind':'generated_speech','text':text,'voice':voice,'file':file,'validation_status':'demo_only'})
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2));print('generated',len(manifest),'stimuli in',out)
if __name__=='__main__':asyncio.run(main())
