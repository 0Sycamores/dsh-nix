/**
 * 生成运行期项目的 lockfile 与元数据（离线 Nix 构建依赖它）。
 *
 * 该脚本由更新流程复制到上游 tag 的检出根目录后运行（需要该检出已 pnpm install）：
 *   cp nix/gen-runtime-lock.ts <upstream>/.dsh-nix-gen-runtime-lock.ts
 *   cd <upstream> && pnpm exec tsx .dsh-nix-gen-runtime-lock.ts <package-set 目录> <输出目录>
 *
 * 输入包集来自 `nix build .#dsh-desktop-payload` 的输出（tarball 已确定性重打包），
 * 因此 file: 依赖的 integrity 在后续 Nix 构建中保持稳定。
 */
import { cpSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createRuntimeProjectMetadata } from './apps/desktop/src/project-manager.ts'
import { DESKTOP_PACKAGES_DIR, DESKTOP_PACKAGE_SET_FILE } from './apps/desktop/src/core-package-set.ts'
import { DESKTOP_HOST_PROTOCOL_VERSION } from './apps/desktop/src/host-protocol.ts'
import { prepareRuntimePatches } from './apps/desktop/scripts/prepare-runtime-patches.ts'

const [packageSet, output] = process.argv.slice(2)
if (packageSet === undefined || output === undefined) {
  throw new Error('usage: gen-runtime-lock.ts <package-set dir> <output dir>')
}

const desktop = JSON.parse(readFileSync('apps/desktop/package.json', 'utf8')) as { version: string }
const release = {
  schemaVersion: 1 as const,
  version: desktop.version,
  hostProtocolVersion: DESKTOP_HOST_PROTOCOL_VERSION,
  nodeVersion: '0.0.0',
  pnpmVersion: '0.0.0',
}

const buildRoot = mkdtempSync(join(tmpdir(), 'dsh-runtime-lock-'))
copyFileSync(join(packageSet, DESKTOP_PACKAGE_SET_FILE), join(buildRoot, DESKTOP_PACKAGE_SET_FILE))
cpSync(join(packageSet, DESKTOP_PACKAGES_DIR), join(buildRoot, DESKTOP_PACKAGES_DIR), { recursive: true })
createRuntimeProjectMetadata(buildRoot, release as never)
prepareRuntimePatches(buildRoot, process.cwd())
execFileSync('pnpm', ['install', '--lockfile-only', '--ignore-scripts'], {
  cwd: buildRoot,
  stdio: 'inherit',
  env: { ...process.env, npm_config_registry: process.env.NPM_REGISTRY ?? 'https://registry.npmmirror.com', COREPACK_ENABLE_STRICT: '0' },
})

const projectDir = join(output, 'project')
mkdirSync(projectDir, { recursive: true })
for (const name of ['package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml']) {
  copyFileSync(join(buildRoot, name), join(projectDir, name))
}
for (const entry of readdirSync(buildRoot)) {
  if (!['package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml', 'desktop-packages', 'desktop-packages.json'].includes(entry)) {
    cpSync(join(buildRoot, entry), join(projectDir, entry), { recursive: true })
  }
}
console.log(`runtime project written: ${projectDir}`)
