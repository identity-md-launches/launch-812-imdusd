# imdUsd (IMDUSD)

`src/IMDUSD.sol:IMDUSD` is an immutable, standard ERC-20. Its constructor
mints the entire supply once to `msg.sender`.

| Parameter | Value |
| --- | --- |
| Name | `imdUsd` |
| Symbol | `IMDUSD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| `totalSupply()` in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | The address executing CREATE or CREATE2 |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimization | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

## Behavior and assumptions

The requested token is interpreted as an ordinary transferable ERC-20. There
are no transfer taxes, rebases, restrictions, public mint or burn functions,
owner, pause, blacklist, seizure, upgrade mechanism, or external callbacks.
Every successful transfer delivers exactly the requested number of smallest
units. The deployer has the same transfer and approval permissions as any other
holder after construction. The supply stays fixed for the token's lifetime.

Transfers and approvals return `true` on success and revert with OpenZeppelin's
ERC-6093 custom errors on invalid addresses, insufficient balances, or
insufficient allowances. Zero-value transfers between valid addresses are
supported and emit `Transfer`; self-transfers preserve balances. Transfers to
the zero address and approvals of the zero address revert, including for zero
amounts. `approve` replaces the allowance, and setting it to zero revokes it.
Finite allowances decrease on `transferFrom`; the ERC-20 convention of
`type(uint256).max` as an unlimited allowance is supported. `transferFrom`
emits `Transfer`; this vendored OpenZeppelin version does not emit `Approval`
when spending an allowance. A failed transfer rolls back allowance changes.

The name alone implies no dollar peg, collateral, redemption, interest, or
price guarantee. Those mechanisms were not specified. The contract has no
recovery function: tokens transferred to a contract unable to send them onward
can be stranded, including tokens sent to the token contract itself. Ordinary
native-currency transfers are rejected, and forcibly received native currency
cannot be recovered.

## Build and tests

Install Foundry and make Solidity `0.8.26` available in its compiler cache.
All Solidity imports are vendored as ordinary files under `lib/`; no package
installation, git submodules, RPC, secrets, or network access are needed once
that compiler is available. Compiler binaries are not part of this repository.
The configuration enables neither FFI nor filesystem cheatcode permissions.

```sh
forge build
forge test
forge fmt --check
```

The tests use isolated local deployments and fixed addresses, with no
environment reads or writes. Unit tests cover metadata, initial balances and
mint events, EOA deployment, CREATE2 factory deployment, exact distribution
and token transfers in both pool-facing directions, events, approval
replacement and revocation, finite and unlimited allowances, zero amounts,
self-transfers, invalid addresses, insufficient balances/allowances,
rollback on failed delegated transfers, and rejected administrative calls.
They also check runtime size and forbidden opcodes. Fuzz tests vary valid and
invalid amounts; a stateful invariant checks conserved supply, exact balances,
and all actor allowances after randomized action sequences including failed
spending attempts. Defaults are 256 cases per fuzz test and 128 invariant
sequences of up to 64 actions.

The local launch test exercises only the ERC-20 transfer paths. It does not
deploy Uniswap v4 or claim to verify actual pool initialization, liquidity
settlement, or swaps. Those are responsibilities of the launch integration's
protected harness. No production deployment or transactions are performed here.

## Deployment and operations

Deploy the exact `src/IMDUSD.sol:IMDUSD` artifact with no constructor arguments
and zero native value, using CREATE or CREATE2. For a launch manifest, the
token constructor arguments are `[]`, decimals are `18`, and total supply is
the exact smallest-unit integer in the table. There are no initialization calls
or application contracts required by this token.

Inspect the creation bytecode and ABI locally:

```sh
forge inspect src/IMDUSD.sol:IMDUSD bytecode
forge inspect src/IMDUSD.sol:IMDUSD abi
```

If a factory deploys the token, the factory receives all `10^27` units, not
the transaction sender. A direct EOA deployment credits that EOA. The network
operator must choose the intended deployment path, chain, factory, CREATE2
salt if applicable, and final distribution recipients. Target chains must
support the Cancun EVM target used in `foundry.toml`.

The token neither allocates the launch's swarm share nor seeds a pool itself.
The launch factory is responsible for distributing its newly minted balance
according to the network's policy. The illustrative pool share in the test is
a test amount, not a selected launch economic parameter. Pool settings and
launch economics are not supplied in this assignment and remain the launch
operator's responsibility; no token-specific exemptions are needed.

After deployment, the operator should verify the source and build parameters
on the target explorer, confirm name/symbol/decimals, `totalSupply()`, and the
deployer's initial balance, then verify exact distribution receipts. The
initial recipient controls all supply until it distributes it and is
responsible for custody of its signing authority. Holders control their own
balances and allowances; use only necessary approval amounts and revoke stale
approvals. When replacing a nonzero allowance for an untrusted spender,
consider confirming a zero-allowance transaction first to address the standard
ERC-20 allowance replacement race.

There are no administrative settings or ongoing maintenance calls. Operators
cannot pause transfers, restore lost tokens, change the supply, or upgrade the
deployed contract. Foundry unit, fuzz, and invariant checks provide local
validation, not a security audit. Independent adversarial review and target
chain launch integration checks remain release responsibilities. Slither and
Mythril were not run.

Dependency versions, origins, and licenses are listed in `DEPENDENCIES.md`.
