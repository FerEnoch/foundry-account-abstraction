// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS, DEPLOYER_SYSTEM_CONTRACT} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";

/*
calldata vs. memory for Transaction: Be mindful of the Transaction struct's memory location.
While calldata is standard in the interface, using memory in your implementation (as shown in ZkMinimalAccount.sol
for the tutorial) can simplify development, especially when manipulating or reading from the struct extensively.

Initial Hash Parameter Handling:
For initial implementations, you can often ignore the _txHash, _suggestedSignedHash, and _possibleSignedHash parameters.
Their primary consumer is the ZK Sync Bootloader system.
Your core AA logic will derive from the _transaction data.
*/

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    ///////////////////////////////////////////////////////////////////////////
    //                           ERRORS                                      //
    ///////////////////////////////////////////////////////////////////////////
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootloader();
    error ZKMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootloaderOrOwner();
    error ZkMinimalAccount__FailedToPay();
    error ZKMinimalAccount__InvalidSignature();

    ///////////////////////////////////////////////////////////////////////////
    //                          MODIFIERS                                     //
    ///////////////////////////////////////////////////////////////////////////
    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }
    modifier requiereFromBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    ///////////////////////////////////////////////////////////////////////////
    //                        EXTERNAL FUNCTIONS                             //
    ///////////////////////////////////////////////////////////////////////////
    function validateTransaction(
        bytes32, // _txHash, (commented out as unused in minimal example)
        bytes32, // _suggestedSignedHash, (commented out as unused in minimal example)
        Transaction memory _transaction
    ) external payable override requireFromBootloader returns (bytes4 magic) {
        // This is arguably the most critical function for account abstraction. It's responsible for validating
        // whether the account agrees to process the given transaction and, crucially, if it's willing to pay for it
        // (or if a paymaster will). This involves checking the transaction's signature against the account's custom
        // authentication logic, verifying the nonce, and ensuring sufficient funds for gas (if no paymaster logic is added).
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32 /* _txHash */,
        bytes32 /* _suggestedSignedHash */,
        Transaction memory _transaction
    ) external payable override requiereFromBootloaderOrOwner {
        // This function would typically be called by a "higher admin" (the Bootloader in the standard flow of type 113 tx) or
        // directly by the account owner if they are an EOA capable of bypassing the standard AA validation flow
        // (though the standard flow via validation is preferred for smart contract accounts).

        return _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(
        Transaction memory _transaction
    ) external payable override {
        // Designed to be callable by any external actor, such as an Externally Owned Account (EOA) or another smart contract
        // interacting directly with the smart contract wallet.
        // This function allows an entity other than the Bootloader (such as an Externally Owned Account (EOA) or another smart
        // contract) to submit a pre-signed transaction on behalf of the smart contract account.
        //
        // In this scenario, the msg.sender of the executeTransactionFromOutside call is the external entity submitting the transaction.
        // Consequently, this external entity is responsible for paying the gas fees for this "meta-transaction".
        // The account contract itself must still implement robust logic to verify the signature and nonce of the underlying, pre-signed
        // transaction it is being asked to execute.
        //
        bytes4 magic = _validateTransaction(_transaction);
        // IMPORTANT: Always check the result of validation.
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZKMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(
        bytes32 /* _txHash */,
        bytes32 /* _suggestedSignedHash */,
        Transaction memory _transaction
    ) external payable override {
        // This function handles the payment logic for the transaction. It's where the account (or, by extension,
        // a paymaster it interacts with) actually disburses the funds to cover the transaction fees.
        // The msg.value sent with this call would typically be used to cover these costs.
        // Analogy to EIP-4337: This is similar to the internal _payPrefund function or the logic within an EntryPoint
        // that deducts fees from the smart wallet's deposit in EIP-4337 implementations.
        //
        // The core logic relies on a helper function, payToTheBootloader,
        // which is part of the TransactionHelper library (via _transaction).
        bool success = _transaction.payToTheBootloader();

        // If the payment to the bootloader fails, revert the transaction.
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(
        bytes32 /* _txHash*/,
        bytes32 /*_suggestedSignedHash */,
        Transaction memory /* _transaction */
    ) external payable override {
        // It's called before payForTransaction and allows the account to perform any necessary preparations or approvals related
        // to the paymaster. This could involve verifying the paymaster, checking allowances, or setting specific states.
        revert("Not implemented");
    }

    // TODO: Implement fallback/receive functions if needed for ETH transfers

    ///////////////////////////////////////////////////////////////////////////
    //                         INTERNAL FUNCTIONS                            //
    ///////////////////////////////////////////////////////////////////////////
    function _validateTransaction(
        Transaction memory _transaction
    ) internal returns (bytes4 magic) {
        // A strict requirement of the validateTransaction function is that it must update the account's nonce by interacting
        // with the NonceHolder system contract. This is a key part of the stateful validation process.
        // This is the simulation: it gets replaced by a system call at compile time when `--system-mode=true` is set.

        uint32 gas = Utils.safeCastToU32(gasleft()); // Get remaining gas, safely cast to uint32

        SystemContractsCaller.systemCallWithPropagatedRevert(
            gas, // gasLimit: Pass remaining gas for the system call
            address(NONCE_HOLDER_SYSTEM_CONTRACT), // to: The NonceHolder system contract address
            0, // value: No ETH value is sent for this particular system call
            abi.encodeCall(
                INonceHolder.incrementMinNonceIfEquals,
                (_transaction.nonce)
            ) // data: Encoded call to NonceHolder.incrementMinNonceIfEquals with the expected current nonce
        );

        // Check for fee to pay
        // This is also the logical point where, in more advanced accounts, logic for integrating with Paymasters could be added.
        // A paymaster could cover the fees instead of the account itself.
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance(); // Uses MemoryTransactionHelper
        // The totalRequiredBalance is calculated, encompassing the maximum potential cost: gasLimit * maxFeePerGas + value.
        // This value is then compared against the contract's current balance.
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance(); // Custom error
        }

        // Signature Verification
        // 1. Hashing the transaction:
        bytes32 txHash = _transaction.encodeHash(); // Uses MemoryTransactionHelper

        // Note: The step MessageHashUtils.toEthSignedMessageHash(txHash) is NOT needed here
        // for zkSync AA transactions using the standard EIP-712 flow as _transaction.encodeHash()
        // already produces the EIP-712 compliant hash (or the correct hash for other transaction types
        // if they were being processed by the account)

        // 2. Recovering the signer:
        address signer = ECDSA.recover(txHash, _transaction.signature);

        // 3. Verifying the signer:
        bool isValidSigner = (signer == owner()); // Check if signer is the contract owner

        // This function must return IAccount.validateTransaction.selector or similar magic bytes on success
        // For zkSync Era, the magic value returned by validateTransaction on success is `IAccount.validateTransaction.selector`.
        // However, in ERC-4337 context, it's often related to EIP-1271.
        // For native AA, the system expects a specific magic value: `IAccount(this).validateTransaction.selector`
        // As per system contracts, it's often:
        // `return _SUCCESS_MAGIC;` where `bytes4 constant _SUCCESS_MAGIC = 0x56495AA4;` (System Contract V1.3.0 and later)
        // Or, more accurately from IAccount interface:
        // return 0x56495AA4; // Placeholder for actual success magic from IAccount
        // return IAccount.validateTransaction.selector; // Indicate successful validation
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        // Target Address (to)
        // The _transaction.to field is a uint256. It needs to be cast to an address type, which is 160 bits
        address toAddress = address(uint160(_transaction.to));

        // Value (value): The _transaction.value is a uint256. However, certain operations, particularly calls to
        // system contracts or internal EVM operations, might expect a uint128.
        uint128 value = Utils.safeCastToU128(_transaction.value);

        // Call Data (data): The _transaction.data field, which contains the payload for the call,
        // is extracted directly as bytes memory.
        bytes memory data = _transaction.data;

        if (toAddress == address(DEPLOYER_SYSTEM_CONTRACT)) {
            // This is a deployment transaction.
            // We need to call the deployer system contract using SystemContractsCaller.
            uint32 gas = Utils.safeCastToU32(gasleft()); // Get remaining gas, safely cast to uint32
            SystemContractsCaller.systemCallWithPropagatedRevert(
                gas,
                toAddress,
                value,
                data
            );
        } else {
            // While Solidity's high-level .call() can be used, directly using assembly with the call opcode is often
            // demonstrated for clarity on zkSync's behavior or for more fine-grained control.
            bool success;
            assembly {
                success := call(
                    gas(), // forward all available gas
                    toAddress, // address to call (current available gas for the call)
                    value, // ether value to send
                    /* data (a bytes memory variable) in Solidity stores its length in the first 32 bytes (0x20 bytes).
                    The actual calldata starts after this length prefix. mload(data) retrieves this length */
                    add(data, 0x20), // pointer to start of input data (skip the length field) - pointer to the actual calldata (skipping the length prefix of bytes array)
                    mload(data), // size of input data - length of the calldata
                    /*  pointer and length for return data (we are not capturing return data here) */
                    0, // pointer to output (0 means we don't care about the output)
                    0 // size of output
                )
            }
            // Revert if the call failed
            if (!success) {
                /* iszero(success) */
                revert ZKMinimalAccount__ExecutionFailed();
            }
        }
    }
}
