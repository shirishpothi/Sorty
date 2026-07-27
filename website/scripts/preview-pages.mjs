import { spawn } from 'node:child_process'
import { mkdir, rm, symlink } from 'node:fs/promises'
import path from 'node:path'

const websiteDirectory = path.resolve(import.meta.dirname, '..')
const previewDirectory = path.join(websiteDirectory, '.pages-preview')
const mountedExport = path.join(previewDirectory, 'Sorty')

await rm(previewDirectory, { recursive: true, force: true })
await mkdir(previewDirectory, { recursive: true })
await symlink(path.join(websiteDirectory, 'out'), mountedExport, 'dir')

console.log('Previewing the GitHub Pages export at http://localhost:3100/Sorty/')

const server = spawn(
  'python3',
  ['-m', 'http.server', '3100', '--directory', previewDirectory],
  { stdio: 'inherit' },
)

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.kill(signal))
}

server.on('exit', (code) => {
  process.exitCode = code ?? 0
})
