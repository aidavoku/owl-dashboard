export default {
  async fetch(request) {
    const url = new URL(request.url);
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    if (url.pathname === '/api/server') {
      // Gather server info
      const os = await import('node:os').catch(() => null);
      let cpu = '--', mem = '--', disk = '--', uptime = '--';
      
      try {
        // These won't work in Worker but we'll inject data at build time
        cpu = 'N/A'; mem = 'N/A'; disk = 'N/A'; uptime = 'N/A';
      } catch(e) {}

      const data = {
        server: { cpu, mem, disk, uptime },
        projects: [
          { name: 'PAPER R6', path: '/web-sypes', status: 'active' },
          { name: 'Dashboard', path: '/dashboard', status: 'active' },
        ],
        services: [
          { name: 'OpenClaw Gateway', type: 'telegram/whatsapp', status: 'running' },
          { name: 'HTTP Server', type: 'python3', status: 'running' },
          { name: 'Cloudflare Tunnel', type: 'cloudflared', status: 'running' },
        ]
      };
      return new Response(JSON.stringify(data), { headers: { ...cors, 'Content-Type': 'application/json' } });
    }

    return new Response('Not found', { status: 404 });
  }
};
