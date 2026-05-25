// OWL Dashboard API Worker
// Receives encrypted command payloads, Owl executes them via webhook

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': origin || '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') return new Response(null, { headers: cors, status: 204 });

    // Public health check
    if (url.pathname === '/health') {
      return Response.json({ status: 'ok', ts: Date.now() }, { headers: cors });
    }

    // Get server info (static for now, could be dynamic)
    if (url.pathname === '/api/server' && request.method === 'GET') {
      return Response.json({
        server: {
          cpu: 'N/A', mem: 'N/A', disk: 'N/A', uptime: 'N/A', load: 'N/A',
          info: 'Dashboard API — connect Owl for live data'
        },
        projects: [
          { name: 'PAPER R6', path: '/web-sypes', status: 'active', desc: '2D tactical shooter' },
          { name: 'OWL Dashboard', path: '/dashboard', status: 'active', desc: 'This dashboard' },
        ],
        services: [
          { name: 'OpenClaw Gateway', type: 'telegram', status: 'online' },
          { name: 'HTTP Server :8080', type: 'http', status: 'online' },
          { name: 'Cloudflare Tunnel', type: 'tunnel', status: 'online' },
        ]
      }, { headers: cors });
    }

    // Receive encrypted secret / command from dashboard
    if (url.pathname === '/api/store' && request.method === 'POST') {
      // This just acknowledges receipt — actual storage is client-side encrypted
      const body = await request.json().catch(() => ({}));
      return Response.json({ stored: true, id: body.id || 'unknown' }, { headers: cors });
    }

    // Ping endpoint — Owl can poll this for commands
    if (url.pathname === '/api/ping' && request.method === 'GET') {
      const queue = globalThis._owl_queue || [];
      globalThis._owl_queue = [];
      return Response.json({ commands: queue }, { headers: cors });
    }

    // Submit command from dashboard (will be picked up by Owl polling)
    if (url.pathname === '/api/command' && request.method === 'POST') {
      const body = await request.json().catch(() => ({}));
      if (!globalThis._owl_queue) globalThis._owl_queue = [];
      globalThis._owl_queue.push({ ...body, ts: Date.now() });
      return Response.json({ queued: true, id: body.id }, { headers: cors });
    }

    return new Response('Not found', { status: 404, headers: cors });
  }
};
