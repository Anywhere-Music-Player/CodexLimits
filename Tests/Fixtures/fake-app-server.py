#!/usr/bin/python3
"""Offline app-server peer: no credentials, browser, network, or model calls."""
import json
import os
import sys
import time
from pathlib import Path

home = Path(os.environ['CODEX_HOME'])
scenario = (home / 'scenario').read_text()
(home / 'pid').write_text(str(os.getpid()))

def send(value):
    text = json.dumps(value) + '\n'
    # Exercise JSONL framing across partial reads.
    middle = len(text) // 2
    sys.stdout.write(text[:middle]); sys.stdout.flush()
    time.sleep(0.005)
    sys.stdout.write(text[middle:]); sys.stdout.flush()

for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    if 'id' not in request:
        continue
    ident = request['id']
    if method == 'initialize':
        if scenario == 'timeout':
            time.sleep(10)
            continue
        if scenario == 'crash':
            sys.exit(1)
        if scenario == 'malformed':
            print('not-json', flush=True)
            continue
        send({'id': ident, 'result': {'userAgent': 'test'}})
    elif method == 'account/read':
        account = {'type': 'chatgpt', 'email': None, 'planType': 'pro'} if (home / 'signed-in').exists() else None
        send({'id': ident, 'result': {'account': account, 'requiresOpenaiAuth': True}})
    elif method == 'account/login/start':
        url = 'https://auth.openai.com/oauth/authorize?test=1'
        if scenario == 'unsafe-url':
            url = 'https://auth.openai.com.example.org/login'
        if scenario == 'success':
            (home / 'signed-in').touch()
            # Notification can arrive before the request response.
            send({'method': 'account/login/completed', 'params': {'loginId': 'login-1', 'success': True}})
        if scenario == 'failed-login':
            send({'method': 'account/login/completed', 'params': {'loginId': 'login-1', 'success': False}})
        send({'id': ident, 'result': {'type': 'chatgpt', 'loginId': 'login-1', 'authUrl': url}})
        if scenario == 'unrelated-login':
            send({'method': 'account/login/completed', 'params': {'loginId': 'different', 'success': True}})
    elif method == 'account/rateLimits/read':
        if scenario == 'server-error':
            send({'id': ident, 'error': {'code': -32603, 'message': 'Sensitive server details must not be shown'}})
        else:
            send({'id': ident, 'result': {'rateLimits': {'primary': None, 'secondary': None},
                  'rateLimitsByLimitId': {'codex': {'primary': {'usedPercent': 32, 'windowDurationMins': 10080, 'resetsAt': 1800000000}}}}})
    else:
        raise RuntimeError('Unexpected method: ' + str(method))
