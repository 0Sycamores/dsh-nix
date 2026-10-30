/** Prepare (offline) the Desktop primary-runtime payload and its versions metadata. */
import { chmodSync, cpSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { preparePrimaryRuntime } from './apps/desktop/scripts/prepare-primary-runtime.ts'
import { readPrimaryRuntime } from './packages/skill/tool-workspace-dependencies/src/index.ts'
import { resolveDesktopTargetBuildPaths } from './apps/desktop/scripts/desktop-build-paths.mjs'

// 沙箱内不能执行 payload 里的外来二进制，冒烟交给宿主侧验收脚本。
await preparePrimaryRuntime({ deferSmoke: true })

const paths = resolveDesktopTargetBuildPaths()
cpSync(join(process.cwd(), 'apps/desktop/scripts/node-bin'), join(paths.runtime, 'bin'), {
  recursive: true,
  dereference: true,
})
chmodSync(join(paths.runtime, 'bin', 'node'), 0o755)
const { pnpm } = await readPrimaryRuntime(join(paths.runtime, 'primary-runtime'))
// Linux 桌面版让 Host 跑在 runtime 自带的官方 Node 上，release.nodeVersion 必须与之一致。
const manifest = JSON.parse(readFileSync(join(paths.runtime, 'primary-runtime', 'runtime.json'), 'utf8')) as {
  node?: unknown
}
if (typeof manifest.node !== 'string') throw new Error('primary runtime manifest has no node version')
writeFileSync(
  join(paths.runtime, 'versions.json'),
  `${JSON.stringify({ schemaVersion: 1, node: manifest.node, pnpm }, undefined, 2)}\n`,
)
console.log(`runtime ready: ${paths.runtime} (node ${manifest.node}, pnpm ${String(pnpm)})`)
