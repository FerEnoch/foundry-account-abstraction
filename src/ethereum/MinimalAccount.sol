// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MinimalAccount is IAccount, Ownable {
    ///////////////////////////////////////////////////////////////////////////
    //                           ERRORS                                      //
    ///////////////////////////////////////////////////////////////////////////
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes result);

    ///////////////////////////////////////////////////////////////////////////
    //                          STATE VARIABLES                              //
    ///////////////////////////////////////////////////////////////////////////
    IEntryPoint private immutable I_ENTRYPOINT;

    ///////////////////////////////////////////////////////////////////////////
    //                          MODIFIERS                                     //
    ///////////////////////////////////////////////////////////////////////////
    modifier requireFromEntryPoint() {
        _requireFromEntryPoint();
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        _requireFromEntryPointOrOwner();
        _;
    }

    ///////////////////////////////////////////////////////////////////////////
    //                          FUNCTIONS                                    //
    ///////////////////////////////////////////////////////////////////////////
    constructor(address entryPoint) Ownable(msg.sender) {
        I_ENTRYPOINT = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    ///////////////////////////////////////////////////////////////////////////
    //                        EXTERNAL FUNCTIONS                             //
    ///////////////////////////////////////////////////////////////////////////

    // Really at the end of the day, this the THE important function of an account contract.
    // It receives the PackedUserOperation and is responsible for verifying its authenticity and intent.
    function validateUserOp( 
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override requireFromEntryPoint returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);

        if (validationData != SIG_VALIDATION_SUCCESS) {
            return validationData; // return the invalid signature code (0)
        }

        // Placeholder for other validation logic:
        // _validateNonce(userOp.nonce); - important for replay protection.
        // Call a _validateNonce() helper to ensure the userOp.nonce matches the account's expected nonce, preventing replay attacks.

        // EntryPoint Restriction: Ideally, validateUserOp should only be callable by the trusted, global EntryPoint contract.
        // This is usually achieved with a modifier.

        // We pay the EntryPoint contract if needed
        _payPrefund(missingAccountFunds);

        // If we reach here, the signature is valid.
        // In a complete implementation, if nonce and prefund also passed,
        // we'd still return the validationData which might be SIG_VALIDATION_SUCCESS
        // or a packed value if using timestamps.
        return validationData; // This will be SIG_VALIDATION_SUCCESS or SIG_VALIDATION_FAILED from _validateSignature
    }

    // Providing the owner (the EOA that deployed this account or to whom ownership was transferred) with direct access
    // to *execute* offers valuable flexibility. The owner can perform arbitrary calls from the account to manage the account,
    // or perform operations directly, without needing to go through the UserOperation flow.
    // Make the function payable if it can forward ETH.
    function execute(
        address dest,
        uint256 value,
        bytes calldata functionData
    ) external payable requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(
            functionData
        );
        if (!success) {
            // revert MinimalAccount__CallFailed(result);
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    //                           INTERNAL FUNCTIONS                          //
    ///////////////////////////////////////////////////////////////////////////

    // In this case, the signature is valid if the signer is the owner of the account. In more advanced
    // scenarios, this is where you'd implement logic for multi-sigs, session keys, social recovery mechanisms,
    // or other custom authorization schemes.
    // The validationData returned isn't just limited to 0 or 1. The ERC-4337 standard allows this uint256 to be
    // packed with additional data, such as validUntil and validAfter timestamps. This enables time-locked UserOps
    // where an operation is only valid within a specific window.
    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view returns (uint256 validationData) {
        // EIP-191 version of the signed hash
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            userOpHash
        );

        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);

        if (signer == address(0) || signer != owner()) {
            // Also check for invalid signature recovery address(0)
            return SIG_VALIDATION_FAILED; // returns 1
        }
        return SIG_VALIDATION_SUCCESS; // returns 0
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            // Pay back the EntryPoint contract
            (bool success, ) = payable(msg.sender).call{
                value: missingAccountFunds,
                gas: type(uint256).max
            }("");
            (success);
        }
    }

    function _requireFromEntryPoint() internal view {
        if (msg.sender != address(I_ENTRYPOINT)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
    }

    function _requireFromEntryPointOrOwner() internal view {
        if (msg.sender != address(I_ENTRYPOINT) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
    }

    // / ///////////////////////////////////////////////////////////////////////////
    // / //                          GETTERS                                      //
    // / ///////////////////////////////////////////////////////////////////////////

    function getEntryPoint() external view returns (address) {
        return address(I_ENTRYPOINT);
    }
}
