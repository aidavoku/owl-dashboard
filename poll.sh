#!/bin/bash
# OWL Dashboard Command Poller
# Polls Cloudflare Worker for pending commands, executes them, posts results back

API_URL="https://owl-dashboard-api.aidavoku.workers.dev"

# Poll for commands
RESP=$(curl -s "${API_URL}/api/ping" 2>/dev/null)
if [ -z "$RESP" ]; then
  exit 0
fi

# Parse command IDs (simple JSON extraction)
echo "$RESP" | python3 -c "
import sys, json, subprocess, urllib.request, urllib.parse, time

try:
    data = json.load(sys.stdin)
    commands = data.get('commands', [])
except:
    sys.exit(0)

api_url = 'https://owl-dashboard-api.aidavoku.workers.dev'

for cmd in commands:
    cmd_id = cmd.get('id', 'unknown')
    cmd_type = cmd.get('type', '')
    payload = cmd.get('payload', '')
    output = ''
    ok = True

    if cmd_type == 'exec':
        # Execute shell command (safely)
        try:
            result = subprocess.run(
                ['bash', '-c', payload],
                capture_output=True, text=True, timeout=30,
                cwd='/home/adminlog/.openclaw/workspace'
            )
            output = result.stdout + result.stderr
            if result.returncode != 0:
                ok = False
        except subprocess.TimeoutExpired:
            output = 'Command timed out'
            ok = False
        except Exception as e:
            output = str(e)
            ok = False

    elif cmd_type == 'read':
        # Read a file
        try:
            filepath = '/home/adminlog/.openclaw/workspace/' + payload.lstrip('/')
            with open(filepath, 'r') as f:
                output = f.read(4099)  # Limit output
        except Exception as e:
            output = str(e)
            ok = False

    elif cmd_type == 'write':
        # Write to file — requires confirmation, skip for now
        output = 'Write commands require confirmation'
        ok = False

    elif cmd_type == 'deploy':
        # Restart tunnel for a project
        try:
            if 'sypes' in payload.lower() or 'paper' in payload.lower():
                subprocess.run(['pkill', '-f', 'cloudflared.*8080'], timeout=5)
                subprocess.Popen(
                    ['nohup', '/tmp/cloudflared', 'tunnel', '--url', 'http://127.0.0.1:8080'],
                    stdout=open('/tmp/cf-web.log', 'w'), stderr=subprocess.DEVNULL
                )
                time.sleep(8)
                output = 'Game tunnel restarted'
            else:
                output = 'Unknown project: ' + payload
                ok = False
        except Exception as e:
            output = str(e)
            ok = False

    elif cmd_type == 'custom':
        output = 'Message received: ' + payload + ' (forwarded to admin)'

    else:
        output = 'Unknown command type: ' + cmd_type
        ok = False

    # Post result back
    result_data = json.dumps({
        'cmdId': cmd_id,
        'output': output[:2000],
        'ok': ok
    })

    req = urllib.request.Request(
        api_url + '/api/result',
        data=result_data.encode(),
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except:
        pass
" 2>/dev/null
