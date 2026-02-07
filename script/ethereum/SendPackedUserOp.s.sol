// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    // Example of how to handle signing in tests for Anvil to avoid "No wallets are available" error
    uint256 immutable ANVIL_DEFAULT_PRIVATE_KEY_0 =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Default Anvil key 0
    HelperConfig helperConfig;

    function setUp() public {
        helperConfig = new HelperConfig();
    }

    function generatedSignedUserOperation(
        bytes memory callData, // The target calldata for the smart account's execution
        HelperConfig.NetworkConfig memory config, // Network configuration containing entry point and signer addresses
        address minimalAccount // Address of the smart account to be used as sender
    ) public view returns (PackedUserOperation memory) {
        // Step 1: Generate the unsigned UserOperation

        // Fetch the nonce for the sender (smart account address) from the EntryPoint
        // For smart contract accounts, especially when they are newly deployed or haven't initiated
        // transactions through the EntryPoint yet, the EntryPoint typically expects the first nonce
        // to be 0. The vm.getNonce() cheatcode might return 1 if it's tracking nonces similarly to EOAs
        // or based on other contract creations/interactions in the test environment for an account that
        // has not yet had a UserOperation processed.
        uint256 nonce = IEntryPoint(config.entryPoint).getNonce(
            minimalAccount,
            0
        );

        PackedUserOperation memory userOp = _generateUnsignedUserOperation(
            callData,
            minimalAccount, // Smart account address
            nonce
        );

        // Step 2: Sign the UserOperation. Get the userOpHash from the EntryPoint
        // We need to cast the config.entryPoint address to IEntryPoint interface
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(
            userOp
        );

        // Prepare the hash for eth_sign convention (includes prefixing) EIP-191 signing Ethereum standard for signed message
        // and for off-chain message signing and recovery.
        // This prepends "\x19Ethereum Signed Message:\n32" and re-hashes.
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // Step 3: Sign the digest
        // "config.account" here is the EOA that owns/controls the smart account
        // This EOA must be unlocked for vm.sign to work without private key.
        // Important Tip: vm.sign can accept an address (like config.account, which represents the EOA owner
        // of the smart account) if that account is "unlocked". In Foundry scripts, this can be achieved by
        // using flags like forge script --account <name_of_account_in_foundry_toml_or_keystore> or by
        // using default Anvil accounts which are unlocked by default in script execution contexts.
        // This method conveniently avoids embedding private keys directly in your script code
        //
        // NOT WORKIING for the "No wallets available error" ->
        //  (uint8 v, bytes32 r, bytes32 s) = vm.sign(config.account, digest);
        // Workaround for Local Anvil Tests, to avoid the "No wallets are available" error:
        // To sign messages in tests when using default Anvil accounts (like the one with chainId == 31337),
        // you need to explicitly use the corresponding private key with vm.sign

        uint8 v;
        bytes32 r;
        bytes32 s;
        if (block.chainid == 31337) {
            // Anvil's default chain ID
            (v, r, s) = vm.sign(ANVIL_DEFAULT_PRIVATE_KEY_0, digest);
        } else {
            // For testnets (e.g., Sepolia), use the account from config (e.g., BURNER_WALLET).
            // Foundry will use the private key associated with this address (e.g., from .env via vm.startBroadcast).
            (v, r, s) = vm.sign(config.account, digest);
        }

        // Construct the final signature
        // IMPORTANT: the order is r, s, v -> abi.encodePacked(r, s, v).
        // This (RSV) is a common convention for Ethereum signatures when concatenated.
        // This differs from vm.sign output order (v, r, s).
        userOp.signature = abi.encodePacked(r, s, v);

        return userOp;
    }

    function _generateUnsignedUserOperation(
        bytes memory callData,
        address sender, // Smart account address
        uint256 nonce
    ) internal pure returns (PackedUserOperation memory) {
        // Example gas parameters (these may need tuning)
        // In a real-world scenario, these would require careful calculation or dynamic retrieval
        // based on network conditions and operation complexity. They often need to be estimated or determined dynamically

        // PreVerificationGas - Gas not calculated by the handleOps method, but added to the gas paid.
        //   Covers batch overhead.
        uint128 verificationGasLimit = 200000; // 200,000 gas

        uint128 callGasLimit = 300000;
        uint128 maxPriorityFeePerGas = 100 gwei;
        uint128 maxFeePerGas = 2 gwei;

        // - Packed gas limits for validateUserOp and gas limit passed to the callData method call
        // Pack accountGasLimits: (verificationGasLimit << 128) | callGasLimit
        bytes32 accountGasLimits = bytes32(
            (uint256(verificationGasLimit) << 128) | uint256(callGasLimit)
        );

        // - packed gas fields maxPriorityFeePerGas and maxFeePerGas - Same as EIP-1559 gas parameters.
        // Pack gasFees: (maxFeePerGas << 128) | maxPriorityFeePerGas
        bytes32 gasFees = bytes32(
            (uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas)
        );

        return
            PackedUserOperation({
                sender: sender, // Smart account address
                nonce: nonce,
                initCode: hex"", // Assuming account is already deployed. Empty initCode for existing accounts
                callData: callData,
                accountGasLimits: accountGasLimits,
                preVerificationGas: verificationGasLimit + 50000, // Needs proper estimation
                gasFees: gasFees,
                paymasterAndData: hex"", // Empty if not using a paymaster
                signature: hex"" // Left empty, to be filled after hashing and signing
            });
    }
}
