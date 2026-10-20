"""Verify configured UK playlists and one media segment; never change region."""
import concurrent.futures, json, urllib.request, urllib.parse, pathlib
catalogue=json.load(open(pathlib.Path(__file__).resolve().parents[1] / 'docs/station-directory.json'))
catalogue.update(bbc_radio_fourfm='Radio 4',bbc_radio_scotland_fm='Radio Scotland',bbc_radio_wales_fm='Radio Wales')
def verify(pair):
 id,title=pair
 url=f'https://a.files.bbci.co.uk/ms6/live/3441A116-B12E-4D2F-ACA8-C1984642FA4B/audio/simulcast/hls/uk/pc_hd_abr_v2/aks/{id}.m3u8'
 try:
  with urllib.request.urlopen(url,timeout=12) as r: text=r.read().decode()
  if not text.startswith('#EXTM3U'):raise ValueError('Not HLS')
  if '#EXT-X-STREAM-INF' in text:
   playlist=urllib.parse.urljoin(url,next(l for l in text.splitlines() if l and not l.startswith('#')))
   with urllib.request.urlopen(playlist,timeout=12) as r: text=r.read().decode()
  else: playlist=url
  segment=next(l for l in text.splitlines() if l and not l.startswith('#'))
  with urllib.request.urlopen(urllib.parse.urljoin(playlist,segment),timeout=12) as r: data=r.read()
  return dict(id=id,title=title,url=url,playlist=playlist,verified=len(data)>0,bytes=len(data))
 except Exception as e:return dict(id=id,title=title,url=url,verified=False,error=str(e))
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex: results=list(ex.map(verify,catalogue.items()))
pathlib.Path('RadioBridge/docs/station-stream-checks.json').write_text(json.dumps(results,indent=2))
print('Verified',sum(r['verified'] for r in results),'/',len(results))
print([(r['id'],r.get('error')) for r in results if not r['verified']])
