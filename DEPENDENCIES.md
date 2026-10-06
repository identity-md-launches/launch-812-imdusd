# Vendored dependencies

Dependencies are ordinary source files, not submodules. No automatic updates
or downloads are performed by the project. Preserve their accompanying
licenses when redistributing.

| Dependency | Release | Exact upstream commit | License | Vendored scope |
| --- | --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | MIT | ERC20 and its four transitive source dependencies |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | MIT / Apache-2.0 | Complete `src/` tree, for local testing |

OpenZeppelin files reside in `lib/openzeppelin-contracts/`, with its upstream
`LICENSE`. forge-std files reside in `lib/forge-std/`, with upstream
`LICENSE-MIT` and `LICENSE-APACHE`. Each dependency's `VERSION` records its tag
and exact commit. `lib/SHA256SUMS` records source, license, and version file
hashes; verify it from the repository root with `sha256sum -c lib/SHA256SUMS`.

Upstream source files are unmodified. Import aliases are defined in
`remappings.txt`. Only OpenZeppelin is compiled into the production token;
forge-std is test support.
