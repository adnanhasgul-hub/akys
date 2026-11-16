"""Real Flutter application page + real DedicatedWorker. No Firebase."""
import functools, http.server, threading, json, re, time, hashlib, argparse
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
parser=argparse.ArgumentParser()
parser.add_argument('--directory',default='build/v2-ui-acceptance')
parser.add_argument('--result',default='tool/solver_v2/results/stage_1_9b_browser.json')
args=parser.parse_args()
build=Path(args.directory)
out=Path(args.result)
results={'checks':[], 'errors':[], 'workers':[]}
with http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(build))) as server:
 threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  results['chromium']=browser.version
  page=browser.new_page(viewport={'width':414,'height':896})
  page.on('pageerror',lambda e:results['errors'].append(str(e)))
  page.on('worker',lambda w:results['workers'].append(w.url))
  base=f'http://127.0.0.1:{server.server_port}/'
  try:
   page.goto(base)
   page.get_by_role('button',name='Nöbet oluştur',exact=True).click()
   expect(page.get_by_role('group', name=re.compile('^Optimumluk kanıtlandı'))).to_be_visible(timeout=20000)
   label=page.get_by_role('group',name=re.compile('^Optimumluk kanıtlandı')).get_attribute('aria-label')
   vector=re.search(r'Yeni kalite:\s*((?:-?\d+(?:/\d+)?,\s*){18}-?\d+(?:/\d+)?)',label).group(1)
   assert len(vector.split(','))==19, vector
   results['firstQuality']=vector
   page.get_by_role('button',name='Yerel taslağa kabul et',exact=True).click()
   page.get_by_role('tab',name='Çizelge').click()
   page.get_by_role('button',name='Kıdemli • REQUIRED / Zorunlu',exact=False).first.click()
   page.get_by_text('Kilitle',exact=True).click()
   page.get_by_role('button',name='Kilitlerle yeniden optimize et',exact=True).click()
   expect(page.get_by_role('button',name='Yerel taslağa kabul et')).to_be_enabled(timeout=15000)
   page.get_by_role('button',name='Yerel taslağa kabul et').click()
   results['checks'].append('real-worker optimize, exact quality preview, accept, lock, reoptimize and accept')
   page.screenshot(path=str(build/'v2-mobile.png'))
   page.set_viewport_size({'width':1440,'height':1000})
   page.get_by_role('tab',name='Hekimler').click()
   expect(page.get_by_role('group',name=re.compile('Test Hekimi 1'))).to_be_visible()
   page.screenshot(path=str(build/'v2-desktop.png'))
   results['checks'].append('mobile 414 and desktop 1440 navigation')
   page.goto(base+'?fixture=transition')
   page.get_by_role('button',name='Nöbet oluştur',exact=True).click()
   expect(page.get_by_role('group',name=re.compile('B sonucu yalnız önizleme:'))).to_be_visible(timeout=20000)
   expect(page.get_by_role('button',name='Yerel taslağa kabul et')).to_be_disabled()
   page.get_by_role('button',name='Sonucu reddet / Taslağa dön').click()
   results['checks'].append('B preview cannot be accepted; draft retained on rejection')
   page.goto(base+'?fixture=long')
   page.get_by_role('button',name='Nöbet oluştur',exact=True).click()
   expect(page.get_by_role('button',name='30 saniye uzat')).to_be_enabled(timeout=20000)
   page.wait_for_timeout(200)
   page.evaluate('window.beats=0; window.gaps=[]; window.lastBeat=performance.now(); window.beatTimer=setInterval(()=>{const now=performance.now();window.gaps.push(now-window.lastBeat);window.lastBeat=now;window.beats++},16)')
   page.get_by_role('button',name='30 saniye uzat').click()
   page.get_by_role('tab',name='Hekimler').click()
   expect(page.get_by_role('group',name=re.compile('Test Hekimi 1'))).to_be_visible()
   page.get_by_role('tab',name='Kalite / Arama').click()
   page.wait_for_timeout(600)
   cancellation=time.perf_counter()
   page.get_by_role('button',name='İptal et',exact=True).click()
   expect(page.get_by_role('group',name=re.compile('^Kullanıcı iptal etti'))).to_be_visible(timeout=10000)
   results['cancelObservedMilliseconds']=(time.perf_counter()-cancellation)*1000
   results['mainThread']=page.evaluate('({beats:window.beats,maxGapMilliseconds:Math.max(...window.gaps)})')
   assert results['mainThread']['beats']>10
   results['checks'].append('UI navigation during active worker, deadline extension, cooperative cancel')
   page.get_by_role('button',name='Sonucu reddet / Taslağa dön').click()
   page.get_by_role('tab',name='Çizelge').click()
   scroll=time.perf_counter()
   page.mouse.move(600,700);page.mouse.wheel(0,2000);page.wait_for_timeout(250)
   page.mouse.wheel(0,-5000);page.wait_for_timeout(250)
   results['scrollRoundTripObservedMs']=(time.perf_counter()-scroll)*1000
   expect(page.get_by_role('button',name='Kıdemli • REQUIRED / Zorunlu',exact=False).first).to_be_visible()
   results['checks'].append('30-day table scroll down/up remains interactive; measurement includes 500ms deliberate waits')

   assert results['workers'] and not results['errors'], results
   results['appSha256']=hashlib.sha256((build/'main.dart.js').read_bytes()).hexdigest()
   results['workerSha256']=hashlib.sha256((build/'akys_v2_worker.js').read_bytes()).hexdigest()
   results['pass']=True
  except Exception as e:
   results['pass']=False; results['failure']=str(e)
   page.screenshot(path=str(build/'v2-failure.png'))
   Path('/tmp/v2-ui-dom.txt').write_text(page.locator('body').inner_text())
   raise
  finally:
   out.write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n')
   browser.close()
 server.shutdown()
print(json.dumps(results,indent=2,ensure_ascii=False))
