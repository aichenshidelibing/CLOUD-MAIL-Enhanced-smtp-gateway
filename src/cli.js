#!/usr/bin/env node
import net from 'node:net';
import tls from 'node:tls';
import { loadConfig, validateConfig, healthUrl } from './config.js';

function arg(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function usage() {
  console.log(`Cloud Mail SMTP-to-HTTP Gateway

Commands:
  node src/cli.js validate --config config.json
  node src/cli.js test --config config.json
  node src/cli.js smtp-test --config config.json
  node src/cli.js start --config config.json
`);
}

function readConfig(file) {
  const config = loadConfig(file);
  const errors = validateConfig(config);
  if (errors.length) throw new Error(errors.join('; '));
  config.healthUrl = config.upstream.healthUrl || healthUrl(config);
  return config;
}

function waitForResponse(socket, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    let buffer = '';
    let timer;
    const cleanup = () => {
      clearTimeout(timer);
      socket.off('data', onData);
      socket.off('error', onError);
      socket.off('close', onClose);
    };
    const finish = (error, value) => {
      cleanup();
      if (error) reject(error); else resolve(value);
    };
    const onData = (chunk) => {
      buffer += chunk.toString('utf8');
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || '';
      const complete = lines.find((line) => /^\d{3} /.test(line));
      if (complete) finish(null, complete);
    };
    const onError = (error) => finish(error);
    const onClose = () => finish(new Error('SMTP connection closed before a complete response'));
    timer = setTimeout(() => finish(new Error('SMTP response timed out')), timeoutMs);
    socket.on('data', onData);
    socket.once('error', onError);
    socket.once('close', onClose);
  });
}

function sendCommand(socket, command) {
  socket.write(`${command}\r\n`);
}

function expectCode(response, codes, step) {
  const accepted = Array.isArray(codes) ? codes : [codes];
  const code = Number(response.slice(0, 3));
  if (!accepted.includes(code)) throw new Error(`${step} failed: ${response}`);
}

async function smtpStartTlsTest(config) {
  const port = Number(config.listen.containerPort || 2525);
  const host = config.listen.containerHost === '::' ? '::1' : '127.0.0.1';
  const raw = net.createConnection({ host, port });
  raw.setTimeout(5000);
  await new Promise((resolve, reject) => {
    raw.once('connect', resolve);
    raw.once('error', reject);
  });
  try {
    expectCode(await waitForResponse(raw), 220, 'SMTP greeting');
    sendCommand(raw, 'EHLO cloud-mail-healthcheck');
    expectCode(await waitForResponse(raw), 250, 'EHLO before STARTTLS');
    sendCommand(raw, 'STARTTLS');
    expectCode(await waitForResponse(raw), 220, 'STARTTLS');
    // Do not let the pre-TLS socket timeout interrupt the TLS upgrade.
    raw.setTimeout(0);

    const secure = tls.connect({
      socket: raw,
      rejectUnauthorized: false,
      servername: config.smtp.tls.serverName || 'smtp-gateway',
      minVersion: config.smtp.tls.minVersion || 'TLSv1.2',
    });
    await new Promise((resolve, reject) => {
      secure.once('secureConnect', resolve);
      secure.once('error', reject);
    });
    sendCommand(secure, 'EHLO cloud-mail-healthcheck');
    expectCode(await waitForResponse(secure), 250, 'EHLO after STARTTLS');
    const auth = Buffer.from(`\u0000${config.smtp.user}\u0000${config.smtp.password}`).toString('base64');
    sendCommand(secure, `AUTH PLAIN ${auth}`);
    expectCode(await waitForResponse(secure), 235, 'AUTH PLAIN after STARTTLS');
    sendCommand(secure, 'QUIT');
    await waitForResponse(secure).catch(() => {});
    secure.destroy();
    return 'SMTP STARTTLS and AUTH test passed';
  } finally {
    if (!raw.destroyed) raw.destroy();
  }
}

const command = process.argv[2] || 'start';
const file = arg('--config', 'config.json');

try {
  if (command === 'help' || command === '--help' || command === '-h') {
    usage();
  } else if (command === 'validate') {
    const config = readConfig(file);
    console.log(`Configuration is valid: ${config.file}`);
  } else if (command === 'test') {
    const config = readConfig(file);
    const { checkUpstream } = await import('./server.js');
    console.log(await checkUpstream(config));
  } else if (command === 'smtp-test') {
    const config = readConfig(file);
    if (config.smtp.tls?.enabled === false) throw new Error('smtp-test requires smtp.tls.enabled=true');
    console.log(await smtpStartTlsTest(config));
  } else if (command === 'start') {
    const config = readConfig(file);
    const { checkUpstream, createServer } = await import('./server.js');
    await checkUpstream(config);
    const server = createServer(config);
    const bindHost = config.listen.containerHost || '0.0.0.0';
    const bindPort = Number(config.listen.containerPort || 2525);
    server.listen(bindPort, bindHost, () => {
      console.log(
        `SMTP gateway listening on ${bindHost}:${bindPort} ` +
        `(published host: ${config.listen.host}:${config.listen.port})`,
      );
    });
  } else {
    usage();
    process.exitCode = 1;
  }
} catch (error) {
  console.error(error?.message || error);
  process.exitCode = 1;
}