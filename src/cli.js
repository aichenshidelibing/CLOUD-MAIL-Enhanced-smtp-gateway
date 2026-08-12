#!/usr/bin/env node
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
  } else if (command === 'start') {
    const config = readConfig(file);
    const { checkUpstream, createServer } = await import('./server.js');
    await checkUpstream(config);
    const server = createServer(config);
    server.listen(config.listen.port, config.listen.host, () => {
      console.log(`SMTP gateway listening on ${config.listen.host}:${config.listen.port}`);
    });
  } else {
    usage();
    process.exitCode = 1;
  }
} catch (error) {
  console.error(error?.message || error);
  process.exitCode = 1;
}

