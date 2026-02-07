#!/usr/bin/env node

import { mkdir, appendFile } from 'node:fs/promises';
import { join } from 'node:path';

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(chunk);
}
const input = Buffer.concat(chunks).toString();

const data = JSON.parse(input);
const sessionId = data.session_id;

const dir = '/tmp/cc-hook-debug';
await mkdir(dir, { recursive: true });

const line = JSON.stringify(data) + '\n';
await appendFile(join(dir, `${sessionId}.jsonl`), line);
