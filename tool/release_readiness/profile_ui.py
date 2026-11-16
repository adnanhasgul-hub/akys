"""Actual Chromium trace + rAF/long-task samples; no Firebase. No FPS claims from clicks."""
import argparse,functools,http.server,threading,json,time,statistics
from pathlib import Path
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser();p.add_argument('--result',required=True);p.add_argument('--directory',default='build/v2-profile');a=p.parse_args()
def stats(values):
 values=sorted(values)
 return {'n':len(values),'mean':statistics.mean(values) if values else None,'p95':values[max(0,(95*len(values)+99)//100-1)] if values else None,'max':max(values) if values else None}
result={'rows':[],'errors':[],'method':'release Flutter; Chromium CDP timeline + requestAnimationFrame; no warmup samples; no production'}
with http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=a.directory)) as server:
 threading.Thread(target=server.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  result['chromium']=browser.version
  for width in [414,1440]:
   for repeat in range(3):
    page=browser.new_page(viewport={'width':width,'height':1000})
    page.on('pageerror',lambda e:result['errors'].append(str(e)))
    page.goto(f'http://127.0.0.1:{server.server_port}/?fixture=long&size=20')
    page.get_by_role('tab',name='Çizelge',exact=True).wait_for(timeout=30000)
    page.wait_for_timeout(600)
    cdp=page.context.new_cdp_session(page);completed=[]
    cdp.on('Tracing.tracingComplete',lambda event:completed.append(event))
    cdp.send('Tracing.start',{'categories':'devtools.timeline,v8,blink.user_timing','transferMode':'ReturnAsStream'})
    page.evaluate('''()=>{window.frames=[];window.longTasks=[];window.recording=true;let previous=performance.now();const tick=now=>{if(!window.recording)return;window.frames.push(now-previous);previous=now;requestAnimationFrame(tick)};requestAnimationFrame(tick);window.observer=new PerformanceObserver(list=>window.longTasks.push(...list.getEntries().map(e=>e.duration)));window.observer.observe({type:'longtask',buffered:false});}''')
    latencies=[]
    for tab in ['Hekimler','Çizelge','Kalite / Arama','Çizelge']:
     start=time.perf_counter();page.get_by_role('tab',name=tab,exact=True).click();page.wait_for_timeout(100)
     latencies.append((time.perf_counter()-start)*1000)
    page.mouse.move(width//2,750)
    for _ in range(3):
     for delta in [700,700,700,-700,-700,-700]:page.mouse.wheel(0,delta);page.wait_for_timeout(100)
    sample=page.evaluate('()=>{window.recording=false;window.observer.disconnect();return {frames:window.frames,longTasks:window.longTasks}}')
    cdp.send('Tracing.end')
    deadline=time.time()+15
    while not completed and time.time()<deadline:page.wait_for_timeout(50)
    assert completed
    stream=completed[0]['stream'];chunks=[]
    while True:
     chunk=cdp.send('IO.read',{'handle':stream});chunks.append(chunk['data'])
     if chunk.get('eof'):break
    cdp.send('IO.close',{'handle':stream})
    trace=json.loads(''.join(chunks));events=trace['traceEvents']
    totals={}
    for name in ['FunctionCall','Layout','Paint','UpdateLayoutTree','V8.GCScavenger','V8.GCCompactor']:
     values=[e['dur']/1000 for e in events if e.get('name')==name and e.get('ph')=='X' and 'dur' in e]
     totals[name]=stats(values)
    result['rows'].append({'width':width,'repeat':repeat,'fixture':'20-open','days':31,'frameIntervalsMs':stats(sample['frames'][1:]),'longTasksMs':stats(sample['longTasks']),'tabClickObservedMsIncluding100msWait':stats(latencies),'timelineEvents':totals})
    # Retain aggregate trace evidence, not multi-MB browser internals.
    page.close()
  browser.close()
 server.shutdown()
result['pass']=not result['errors'];Path(a.result).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
