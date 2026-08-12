import { SMTPServer } from 'smtp-server';

function basicAuth(user, password) {
  return `Basic ${Buffer.from(`${user}:${password}`).toString('base64')}`;
}

async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try { return await fetch(url, { ...options, signal: controller.signal }); }
  finally { clearTimeout(timer); }
}

export async function checkUpstream(config) {
  const response = await fetchWithTimeout(config.healthUrl, {
    headers: { Accept: 'application/json', Authorization: basicAuth(config.upstream.user, config.upstream.apiKey) },
  }, config.upstream.timeoutMs);
  let body = null;
  try { body = await response.json(); } catch { /* handled below */ }
  if (!response.ok || body?.data?.ok !== true) {
    const message = body?.message || body?.data?.message || `HTTP ${response.status}`;
    throw new Error(`Upstream health check failed: ${message}`);
  }
  return body?.data || body;
}

export function createServer(config) {
  return new SMTPServer({
    banner: 'Cloud Mail SMTP Gateway',
    disabledCommands: ['STARTTLS'],
    authMethods: ['PLAIN', 'LOGIN'],
    size: Number(config.smtp.maxMessageSize),
    onAuth(auth, _session, callback) {
      if (auth.username !== config.smtp.user || auth.password !== config.smtp.password) return callback(new Error('Invalid SMTP credentials'));
      return callback(null, { user: auth.username });
    },
    async onData(stream, _session, callback) {
      const chunks = [];
      let size = 0;
      stream.on('data', (chunk) => { size += chunk.length; chunks.push(chunk); });
      stream.on('error', callback);
      stream.on('end', async () => {
        try {
          const response = await fetchWithTimeout(config.upstream.url, {
            method: 'POST',
            headers: { 'Content-Type': 'message/rfc822', Authorization: basicAuth(config.upstream.user, config.upstream.apiKey) },
            body: Buffer.concat(chunks, size),
          }, config.upstream.timeoutMs);
          let body = null;
          try { body = await response.json(); } catch { /* no JSON response */ }
          if (!response.ok || body?.code !== 200) {
            const message = body?.message || `HTTP ${response.status}`;
            return callback(new Error(`Cloud Mail rejected message: ${message}`));
          }
          return callback();
        } catch (error) { return callback(error); }
      });
    },
  });
}
