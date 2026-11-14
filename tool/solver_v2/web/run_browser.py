"""Serve an isolated local build and run actual Chromium; emits measured JSON."""
import argparse
import hashlib
import time
import functools
import http.server
import json
import threading
from pathlib import Path
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--directory', default='build/v2-worker-test')
parser.add_argument('--result', default='tool/solver_v2/results/stage_1_9a_browser.json')
parser.add_argument('--timeout-ms', type=int, default=120000)
parser.add_argument('--measure-memory', action='store_true')
args = parser.parse_args()
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=args.directory)
with http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                                   args=['--no-sandbox'])
        page = browser.new_page()
        errors, workers = [], []
        page.on('pageerror', lambda e: errors.append({'message':str(e),'stack':e.stack}))
        page.on('worker', lambda w: workers.append(w.url))
        page.goto(f'http://127.0.0.1:{server.server_port}/')
        memory = {}
        if args.measure_memory:
            cdp = browser.new_browser_cdp_session()
            deadline = time.monotonic() + args.timeout_ms / 1000
            while not page.evaluate('typeof window.akysWorkerResult === "string"'):
                if time.monotonic() > deadline:
                    raise TimeoutError('benchmark did not finish')
                case = page.evaluate('window.akysBenchmarkCase || "starting"')
                processes = cdp.send('SystemInfo.getProcessInfo')['processInfo']
                rss = 0
                for process in processes:
                    try:
                        for line in Path(f"/proc/{process['id']}/status").read_text().splitlines():
                            if line.startswith('VmRSS:'):
                                rss += int(line.split()[1]) * 1024
                    except FileNotFoundError:
                        pass
                memory[case] = max(memory.get(case, 0), rss)
                page.wait_for_timeout(100)
        else:
            page.wait_for_function('typeof window.akysWorkerResult === "string"', timeout=args.timeout_ms)
        result = json.loads(page.evaluate('window.akysWorkerResult'))
        result.update(chromium=browser.version, observedWorkers=workers, pageErrors=errors)
        result['assetSha256'] = {f.name: hashlib.sha256(f.read_bytes()).hexdigest()
                                for f in Path(args.directory).glob('*.js')}
        if args.measure_memory:
            result['processRssPeakBytes'] = memory
            result['memoryScope'] = 'sum of browser-reported processes VmRSS, sampled every ~100ms; includes UI, worker, GPU and shared pages, NOT worker-only heap'
        Path(args.result).write_text(json.dumps(result, indent=2)+'\n')
        browser.close()
    server.shutdown()
print(json.dumps({'tests':result.get('tests'), 'passed':result.get('passed'),
                  'workers':len(workers), 'errors':errors}))
if result.get('tests') != result.get('passed') or errors:
    raise SystemExit(1)
