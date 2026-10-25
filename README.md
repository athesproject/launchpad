# launchpad (Doppler on LitVM)

[![CI](https://github.com/athesproject/launchpad/actions/workflows/ci.yml/badge.svg)](https://github.com/athesproject/launchpad/actions/workflows/ci.yml)
[![License: BUSL 1.1](https://img.shields.io/badge/License-BUSL%201.1-blue.svg)](./LICENSE)

LitVMSwap's token launchpad: Doppler by Whetstone Research, deployed on LitVM with Uniswap V2 and V3 (LitVM has no
Uniswap V4).

## LitVMSwap fork

| | |
|---|---|
| Upstream | [whetstoneresearch/doppler](https://github.com/whetstoneresearch/doppler), base commit `0c55dfe2a8beaa2aef00ea18c2573ee46b0f0a7f` (14 Aug 2026); `src/`, `test/` and `package.json` were identical to it. Upstream HEAD checked on 2026-10-24: `5754c7e` |
| Deployed on LitVM | the 11 contracts in [deployments/4441.md](deployments/4441.md); owners are the LitVM 2-of-3 Safe `0x868b8B48db5DDE602D24960A606A5A8F93333bf9` |
| Not deployed on LitVM | everything that needs Uniswap V4: the Doppler V4 hooks, `RehypeDopplerHookInitializer`, `RehypeDopplerHookMigrator`, `Bundler` |
| Local changes | LitVM deploy script and config (`script/deploy/DeployLitVM.s.sol`, `deployments.config.toml` `[4441]`, a testnet); `lib/v3-periphery` vendored with a Solidity 0.8 `uint160` cast in `PoolAddress.sol`; the security fixes below |
| License | BUSL-1.1 (Whetstone Research), see [LICENSE](LICENSE); our additions in new files are MIT |

Changes on top of the base (LitVM team audit, October 2026), none of which touch a contract deployed on LitVM:

- `RehypeDopplerHookInitializer`: the numeraire is taken from the PoolKey and a mismatch reverts, ported from upstream
  `ae638a9a`.
- `RehypeDopplerHookMigrator`: the same check, the numeraire is taken from the PoolKey and a mismatch or an asset
  outside the key reverts (`test/unit/dopplerHooks/rehypeHookMigrator/RehypeMigratorPoolKeyIdentity.t.sol`).
- `Bundler`: forwards exactly `msg.value` and refunds only what the call left behind; the `simulate*` functions run in a
  self-call that always reverts, so nothing persists if one is sent as a transaction (`test/unit/BundlerIsolation.t.sol`).
- Deploy scripts: LitVM is a testnet, production chains need `DOPPLER_PRODUCTION_DEPLOY=true`, and no instruction passes
  a key on the command line.
- Dependencies: submodules pinned to the tested commits over HTTPS; solmate is pinned at the top level (`lib/solmate`,
  `89365b8`) because the LitVM deployment was built with it, while the copy inside `lib/v4-core` is an older commit.
  `viem` and `bun-types` at exact versions from the npm registry, no install scripts. CI runs the unit tests for
  these changes, `.github/policy.py` (which enforces the pinning) and `scripts/verify-deployed.js`, which builds the
  11 contracts deployed on LitVM and compares them byte for byte with the chain.

Report security issues as described in [SECURITY.md](SECURITY.md).

## Upstream documentation

This repository contains the [Doppler](docs/Doppler.md) Protocol along with the [Airlock](/docs/Airlock.md) contracts. You can learn more about the technical aspects in the [documentation](https://docs.doppler.lol).

## Deployments

Latest deployments can be found [here](./Deployments.md), which is a mirror of the [documentation page](https://docs.doppler.lol/resources/contract-addresses). For historical deployments, you can check the [deployments](./deployments/) folder, which contains the deployment logs for each network.

## Usage

### Installation

First, you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation) if you don't already have it. Then, run the following commands:

```shell
# Clone the repository with its pinned submodules
$ git clone --recursive https://github.com/athesproject/launchpad.git

# Install the dependencies
$ make install
```

### Testing

Tests are separated into 3 different folders:

- `unit`: unit and fuzz tests for individual contracts and libraries, deployed using a minimal local setup (for example only the contract being tested, dependencies are usually mocked)
- `inveriant`: invariant tests for specific contracts or flows, deployed using a more complete local setup (including real dependencies)
- `integration`: specific end-to-end tests including our different modules and their dependencies with the goal of validating the `create` and `migrate` flows

```shell
# Copy the example a .env file and fill the RPC endpoints
$ cp .env.example .env

# Then run the tests
$ make test

# You can also only run the invariant tests
$ make fuzz

# And even run longer fuzz tests
$ make deep-fuzz
```

Tests can be tweaked from the `.env` file, this is a nice way to try different testing scenarios without recompiling the contracts:

```shell
IS_TOKEN_0=FALSE
USING_ETH=FALSE
FEE=30
```

### Deploying

See the deployment documentation in [docs/Deployment.md](/docs/Deployment.md). Configure the required environment variables in `.env` or GitHub, and then run the relevant deployment script directly with `forge script`.
