"""Actual locally built Flutter Web app + separately packaged real worker."""
import functools
import hashlib
import http.server
import json
import re
import threading
from pathlib import Path
from playwright.sync_api import sync_playwright
handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory='build/web')
with http.server.ThreadingHTTPServer(('127.0.0.1',0),handler) as server:
    threading.Thread(target=server.serve_forever,daemon=True).start()
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
        page=browser.new_page(viewport={'width':414,'height':896})
        messages,errors,workers=[],[],[]
        page.on('console',lambda msg: messages.append(msg.text))
        page.on('pageerror',lambda error: errors.append(str(error)))
        page.on('worker',lambda worker: workers.append(worker.url))
        page.goto(f'http://127.0.0.1:{server.server_port}/')
        tapped=False
        for _ in range(300):
            if not tapped and any('AKYS_SMOKE:feasible:' in m for m in messages) and any('AKYS_SMOKE_BACKGROUND_START' in m for m in messages):
                page.get_by_role('button',name='Responsiveness tap').click(timeout=1000)
                tapped=True
            if any('AKYS_SMOKE_BACKGROUND:frames=' in m for m in messages): break
            page.wait_for_timeout(50)
        success=any('AKYS_SMOKE:optimal:optimalProven' in m for m in messages)
        background = next((m for m in messages if 'AKYS_SMOKE_BACKGROUND:frames=' in m), '')
        matched=re.search(r'frames=(\d+);ticks=(\d+);taps=(\d+);nodes=(\d+)', background)
        frame_metrics=dict(zip(['frames','ticks','taps','nodes'],map(int,matched.groups()))) if matched else {}
        page.screenshot(path='build/web/lifecycle-smoke.png')
        result={'chromium':browser.version,'optimalObserved':success,'workers':workers,'frameMetrics':frame_metrics,
                'errors':errors,'console':messages,
                'workerSha256':hashlib.sha256(Path('build/web/akys_v2_worker.js').read_bytes()).hexdigest(),
                'appSha256':hashlib.sha256(Path('build/web/main.dart.js').read_bytes()).hexdigest()}
        Path('tool/solver_v2/results/stage_1_9a_flutter_web.json').write_text(json.dumps(result,indent=2)+'\n')
        browser.close()
    server.shutdown()
assert success and workers and not errors and frame_metrics.get('frames',0)>5 and frame_metrics.get('taps',0)>0 and frame_metrics.get('nodes',0)>0,result
print('Flutter Web app reached validated optimal via real worker.')
