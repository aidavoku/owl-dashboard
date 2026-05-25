#!/bin/bash
# OWL Dashboard Command Poller
# Reads pending commands from a local file that the dashboard writes via webhook
# Executes them and posts results back to Cloudflare Worker

API_URL="https://owl-dashboard-api.aidavoku.workers.dev"
CMD_FILE="/tmp/owl_dashboard_commands.json"
RESULT_FILE="/tmp/owl_dashboard_results.json"

# Initialize files if they don't exist
[ ! -f "$CMD_FILE" ] && echo '[]' > "$CMD_FILE"
[ ! -f "$RESULT_FILE" ] && echo '[]' > "$RESULT_FILE"

# Poll worker for new commands
RESP=$(curl -s "${API_URL}/api/ping" 2>/dev/null)
if [ -n "$RESP" ]; then
    # Merge any remote commands into local file
    echo "$RESP" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    commands = data.get('commands', [])
    if commands:
        # Append to local command file
        try:
            with open('$CMD_FILE', 'r') as f:
                existing = json.load(f)
        except:
            existing = []
        existing.extend(commands)
        with open('$CMD_FILE', 'w') as f:
            json.dump(existing, f)
except:
    pass
" 2>/dev/null
fi

# Process pending commands
python3 -c "
import json, subprocess, urllib.request, os

CMD_FILE = '$CMD_FILE'
RESULT_FILE = '$RESULT_FILE'
API_URL = '$API_URL'

try:
    with open(CMD_FILE, 'r') as f:
        commands = json.load(f)
except:
    commands = []

if not commands:
    print('No pending commands')
    exit(0)

remaining = []
for cmd in commands:
    cmd_id = cmd.get('id', 'unknown')
    cmd_type = cmd.get('type', '')
    payload = cmd.get('payload', '')
    output = ''
    ok = True

    try:
        if cmd_type == 'exec':
            result = subprocess.run(
                ['bash', '-c', payload],
                capture_output=True, text=True, timeout=30,
                cwd='/home/adminlog/.openclaw/workspace'
            )
            output = (result.stdout + result.stderr)[:2000]
            ok = result.returncode == 0

        elif cmd_type == 'read':
            filepath = '/home/adminlog/.openclaw/workspace/' + payload.lstrip('/')
            with open(filepath, 'r') as f:
                output = f.read(4000)
            ok = True

        elif cmd_type == 'status':
            import subprocess
            result = subprocess.run(['openclaw', 'status'], capture_output=True, text=True, timeout=15)
            output = result.stdout[:2000]
            ok = True

        elif cmd_type == 'restart-tunnel':
            subprocess.run(['pkill', '-f', 'cloudflared'], timeout=5)
            import time
            time.sleep(2)
            subprocess.Popen(
                ['/tmp/cloudflared', 'tunnel', '--url', 'http://127.0.0.1:8080'],
                stdout=open('/tmp/cf-web.log', 'a'), stderr=subprocess.DEVNULL
            )
            time.sleep(10)
            output = 'Tunnels restarted'
            ok = True

        elif cmd_type == 'custom':
            output = 'Message received. Forwarded to human.'
            ok = True

        else:
            output = f'Unknown command type: {cmd_type}'
            ok = False

    except subprocess.TimeoutExpired:
        output = 'Command timed out (30s limit)'
        ok = False
    except Exception as e:
        output = f'Error: {str(e)}'
        ok = False

    # Post result back to worker
    result_data = json.dumps({
        'cmdId': cmd_id,
        'output': output,
        'ok': ok
    })

    try:
        req = urllib.request.Request(
            API_URL + '/api/result',
            data=result_data.encode(),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        resp = urllib.request.urlopen(req, timeout=10)
        print(f'Processed {cmd_id}: ok={ok}')
    except Exception as e:
        print(f'Failed to post result for {cmd_id}: {e}')
        remaining.append(cmd)  # Retry next time

# Save remaining unprocessed commands
with open(CMD_FILE, 'w') as f:
    json.dump(remaining, f)

print(f'Remaining: {len(remaining)}')
" 2>&1