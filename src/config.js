import fs from 'node:fs';
import path from 'node:path';

const DEFAULTS = {
  listen: { host: '0.0.0.0', port: 2525 },
  smtp: { user: '', password: '', maxMessageSize: 10 * 1024 * 1024 },
  upstream: { url: '', healthUrl: '', user: '', apiKey: '', timeoutMs: 15000 },
};

function merge(a, b) {
  return Object.fromEntries(Object.keys({ ...a, ...b }).map((key) => [
    key,
    a[key] && typeof a[key] === 'object' && b?.[key] && typeof b[key] === 'object'
      ? merge(a[key], b[key])
      : (b?.[key] ?? a[key]),
  ]));
}

export function loadConfig(file) {
  const absolute = path.resolve(file);
  const raw = JSON.parse(fs.readFileSync(absolute, 'utf8').replace(/^\uFEFF/, ''));
  return { ...merge(DEFAULTS, raw), file: absolute };
}

export function validateConfig(config) {
  const errors = [];
  if (!config.listen?.host) errors.push('listen.host is required');
  if (!Number.isInteger(Number(config.listen?.port)) || config.listen.port < 1 || config.listen.port > 65535) errors.push('listen.port must be 1-65535');
  if (!config.smtp?.user || !config.smtp?.password) errors.push('smtp.user and smtp.password are required');
  if (!Number.isInteger(Number(config.smtp?.maxMessageSize)) || config.smtp.maxMessageSize < 1024) errors.push('smtp.maxMessageSize must be at least 1024');
  let upstreamUrl;
  try { upstreamUrl = new URL(config.upstream?.url); } catch { errors.push('upstream.url must be a valid URL'); }
  if (upstreamUrl && upstreamUrl.protocol !== 'https:' && !['localhost', '127.0.0.1', '::1'].includes(upstreamUrl.hostname)) errors.push('upstream.url must use HTTPS (HTTP is allowed only for localhost testing)');
  if (!config.upstream?.user || !config.upstream?.apiKey) errors.push('upstream.user and upstream.apiKey are required');
  if (!config.upstream?.healthUrl) errors.push('upstream.healthUrl is required');
  else { try { new URL(config.upstream.healthUrl); } catch { errors.push('upstream.healthUrl must be a valid URL'); } }
  if (!Number.isInteger(Number(config.upstream?.timeoutMs)) || config.upstream.timeoutMs < 1000) errors.push('upstream.timeoutMs must be at least 1000');
  return errors;
}

export function healthUrl(config) {
  if (config.upstream.healthUrl) return config.upstream.healthUrl;
  const url = new URL(config.upstream.url);
  url.pathname = url.pathname.replace(/\/send\/?$/, '/health');
  return url.toString();
}
