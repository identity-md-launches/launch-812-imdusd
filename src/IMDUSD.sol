// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title imdUsd
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative privileges.
contract IMDUSD is ERC20 {
    /// @notice One billion tokens, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the deploying EOA or factory.
    constructor() ERC20("imdUsd", "IMDUSD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
