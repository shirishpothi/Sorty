import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(root, "..");
const dist = resolve(root, "dist");

await rm(dist, { recursive: true, force: true });
await mkdir(resolve(dist, "server"), { recursive: true });
await mkdir(resolve(dist, "client"), { recursive: true });
await mkdir(resolve(dist, ".openai"), { recursive: true });

await cp(resolve(root, "out"), resolve(dist, "client"), { recursive: true });
await cp(resolve(root, "sites-worker", "index.js"), resolve(dist, "server", "index.js"));
await cp(resolve(repoRoot, ".openai", "hosting.json"), resolve(dist, ".openai", "hosting.json"));
