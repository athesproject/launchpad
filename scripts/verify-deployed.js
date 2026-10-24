#!/usr/bin/env node
/**
 * Compares this repository's build with the launchpad contracts deployed on LitVM (chain 4441).
 *
 * Read-only: one eth_getCode per contract over a public RPC, no keys. Values fixed at deployment (immutables) are
 * masked at exactly the positions the compiler reports; every other byte must match. The build has no metadata hash
 * (`bytecode_hash = "none"`, `cbor_metadata = false`), so nothing else is excluded.
 *
 *   git submodule update --init --recursive
 *   forge build src/Airlock.sol src/DopplerCreateXDeployer.sol ...   # the files listed below
 *   node scripts/verify-deployed.js                                    # LITVM_RPC_URL overrides the RPC
 */
const fs = require('fs')
const path = require('path')

const ROOT = path.join(__dirname, '..')
const RPC = process.env.LITVM_RPC_URL || 'https://liteforge.rpc.caldera.xyz/infra-partner-http'

// [contract, source file, address] from deployments/4441.md
const CONTRACTS = [
  ['DopplerCreateXDeployer', 'src/DopplerCreateXDeployer.sol', '0x03ba4f49a34d07d0772d5dec8110458c639a6d9f'],
  ['Airlock', 'src/Airlock.sol', '0x803cdd17e0be6652f407fe39e6779b93cfab1c19'],
  ['DopplerERC20V1Factory', 'src/tokens/DopplerERC20V1Factory.sol', '0x2facc7e98ec3181aef5381418840c2525777ebdd'],
  ['DopplerERC20V1', 'src/tokens/DopplerERC20V1.sol', '0x97550629019657b8d1a841547dd5604865e51ec5'],
  ['StreamableFeesLockerV2', 'src/lockers/StreamableFeesLockerV2.sol', '0x204bf55f7bcdd8c6488fb4da4ad68d4af2ca7c74'],
  ['TopUpDistributor', 'src/TopUpDistributor.sol', '0x9a3d3973df7479383d7dcc84f3d04239777b2980'],
  ['NoOpGovernanceFactory', 'src/governance/NoOpGovernanceFactory.sol', '0xdc95a41583f95877586d94b68c783a0ce4ce9b10'],
  ['NoOpMigrator', 'src/migrators/NoOpMigrator.sol', '0x290ce010c9b248b520c07cb5df1242280b4845d9'],
  ['LockableUniswapV3Initializer', 'src/initializers/LockableUniswapV3Initializer.sol', '0x026d005b37d8f7321c1642dc81f065457a1e3c16'],
  ['UniswapV2MigratorSplit', 'src/migrators/UniswapV2MigratorSplit.sol', '0x5f133f8f1d4ac24acad7f04f913ea1c192b39760'],
  ['UniswapV2Locker', 'src/lockers/UniswapV2Locker.sol', '0x75bce7abf55a2c8f14127010f18628e9d4e9a68e'],
]

function mask(hex, ranges) {
  const b = Buffer.from(hex.replace(/^0x/, ''), 'hex')
  for (const r of ranges) b.fill(0, r.start, r.start + r.length)
  return b.toString('hex')
}

async function getCode(address) {
  const res = await fetch(RPC, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'user-agent': 'litvmswap-verify-deployed' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_getCode', params: [address, 'latest'] }),
  })
  return (await res.json()).result
}

async function main() {
  let ok = true
  for (const [name, source, address] of CONTRACTS) {
    const artifact = JSON.parse(fs.readFileSync(path.join(ROOT, 'out', path.basename(source), `${name}.json`), 'utf8'))
    const deployed = artifact.deployedBytecode
    const ranges = Object.values(deployed.immutableReferences || {}).flat()
    const live = await getCode(address)
    const same = live.length > 2 && mask(live, ranges) === mask(deployed.object, ranges)
    console.log(`${same ? 'ok  ' : 'FAIL'} ${name} at ${address}: ${(live.length - 2) / 2} bytes, ${ranges.length} masked positions`)
    ok = ok && same
  }
  console.log(ok ? 'All deployed launchpad contracts are this build.' : 'MISMATCH: see above.')
  process.exit(ok ? 0 : 1)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
