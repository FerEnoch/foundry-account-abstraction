// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ZkMinimalAccount} from "src/zksync/ZkMinimalAccount.sol";
import {Transaction} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {BOOTLOADER_FORMAL_ADDRESS} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";

contract ZkMinimalAccountTest is Test {
    // Example of how to handle signing in tests for Anvil to avoid "No wallets are available" error
    uint256 immutable ANVIL_DEFAULT_PRIVATE_KEY_0 =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Default Anvil key 0
    address constant ANVIL_DEFAULT_ACCOUNT_0 =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    ZkMinimalAccount minimalAccount;
    ERC20Mock usdc;
    uint256 constant AMOUNT = 1e18; // A standard amount for minting/transfers
    bytes32 EMPTY_BYTES32 = bytes32(0);

    function setUp() public {
        // Deploy directly in the test - avoid using scripts with vm cheatcodes
        // as they won't work when executed in zkEVM context
        vm.startPrank(ANVIL_DEFAULT_ACCOUNT_0);
        minimalAccount = new ZkMinimalAccount();
        vm.stopPrank();

        vm.deal(address(minimalAccount), AMOUNT); // Fund the minimal account for gas

        usdc = new ERC20Mock(); // Deploy a mock ERC20 token
    }

    function testZK__OwnerCanExecuteCommands() public {
        // Arrange
        address dest = address(usdc); // The target contract is the mock USDC
        uint256 value = 0; // No ETH value sent with the call itself

        // Calldata for usdc.mint(address(minimalAccount), AMOUNT);
        // Try encodeWithSignature("mint(address,uint256), address(minimalAccount), AMOUNT)");
        bytes memory data = abi.encodeWithSelector(
            usdc.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        Transaction memory unsignedTransaction = _createUnsignedTransaction(
            113, // Transaction type for zkSync AA (0x71 in hex)
            minimalAccount.owner(), // 'from' is the minimal account's owner
            dest, // 'to' is the USDC contract
            value, // No ETH value
            data // Calldata for minting USDC to the minimal account
        );

        // Act
        vm.startPrank(minimalAccount.owner()); // Simulate the owner initiating the transaction
        minimalAccount.executeTransaction(
            EMPTY_BYTES32,
            EMPTY_BYTES32,
            unsignedTransaction
        );
        vm.stopPrank();

        // Assert
        assertEq(
            usdc.balanceOf(address(minimalAccount)),
            AMOUNT,
            "The minimal account should have received the minted USDC"
        );
    }

    function testZK__ValidateTransaction() public {
        // Arrange
        address dest = address(usdc); // The target contract is the mock USDC
        uint256 value = 0; // No ETH value sent with the call itself

        // Calldata for usdc.mint(address(minimalAccount), AMOUNT);
        bytes memory data = abi.encodeWithSelector(
            usdc.mint.selector,
            address(minimalAccount),
            AMOUNT
        );

        Transaction memory unsignedTransaction = _createUnsignedTransaction(
            113, // Transaction type for zkSync AA (0x71 in hex)
            minimalAccount.owner(), // 'from' is the minimal account's owner
            dest, // 'to' is the USDC contract
            value, // No ETH value
            data // Calldata for minting USDC to the minimal account
        );

        // Act
        Transaction memory signedTransaction = _signTransaction(
            unsignedTransaction,
            ANVIL_DEFAULT_PRIVATE_KEY_0
        );

        vm.prank(BOOTLOADER_FORMAL_ADDRESS); // Simulate the bootloader context
        bytes4 magic = minimalAccount.validateTransaction(
            EMPTY_BYTES32,
            EMPTY_BYTES32,
            signedTransaction
        );
        vm.stopPrank();

        //Assert
        assertEq(
            magic,
            ACCOUNT_VALIDATION_SUCCESS_MAGIC,
            "The transaction should be validated successfully"
        );
    }

    ///////////////////////////////////////////////////////////////////////////
    //                            HELPER FUNCTIONS                           //
    ///////////////////////////////////////////////////////////////////////////
    function _createUnsignedTransaction(
        uint8 transactionType,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal view returns (Transaction memory) {
        /* 
            txType: (uint8) Specifies the type of transaction. For zkSync native Account Abstraction, we'll use type 113 (or 0x71).
            from: (uint256) The address initiating the transaction. Note: This is a uint256, not an address type.
            to: (uint256) The target contract address. Also a uint256.
            gasLimit: (uint256) The gas limit for the transaction.
            gasPerPubdataByteLimit: (uint256) The maximum gas price per byte of pubdata. This is relevant for the cost of publishing data from L2 (zkSync) to L1 (Ethereum).
            maxFeePerGas: (uint256) Similar to EIP-1559, the maximum fee per gas.
            maxPriorityFeePerGas: (uint256) Similar to EIP-1559, the maximum priority fee per gas.
            paymaster: (uint256) The address of the paymaster (0 if no paymaster is used).
            nonce: (uint256) The transaction nonce for the from address.
            value: (uint256) The amount of ETH (or native currency) being transferred with the transaction.
            data: (bytes) The calldata for the transaction (e.g., function signature and arguments).
            reserved: (uint256[4]) An array reserved for future protocol use.
            signature: (bytes) The transaction signature. For our unsigned transaction, this will be empty.
            factoryDeps: (bytes32[]) Hashes of contract bytecode needed for deployments initiated by this transaction. Empty if not deploying contracts.
            paymasterInput: (bytes) Input data for the paymaster, if one is used.
            reservedDynamic: (bytes) A dynamically-sized field reserved for future use.
        */

        // Fetch the nonce for the 'minimalAccount' (our smart contract account)
        // Note: vm.getNonce is a Foundry cheatcode. In a real zkSync environment,
        // you'd query the NonceHolder system contract.
        uint256 nonce = vm.getNonce(address(minimalAccount));

        bytes32[] memory factoryDeps = new bytes32[](0);

        return
            Transaction({
                txType: transactionType, // e.g., 113 for zkSync AA
                // The conversion uint256(uint160(someAddress)) is the standard way to cast an address (which is 160 bits) to a uint256
                from: uint256(uint160(from)), // Cast 'from' address to uint256
                to: uint256(uint160(to)), // Cast 'to' address to uint256
                gasLimit: 100_000_000, // Example placeholder value (0.1 gwei)
                gasPerPubdataByteLimit: 800, // Placeholder value for pubdata (publish data to L1)
                maxFeePerGas: 100_000_000, // Example placeholder value (0.1 gwei)
                maxPriorityFeePerGas: 0, // Example placeholder value
                paymaster: 0, // No paymaster for this example (the type is uint256, not address, therefore no address(0) but just 0)
                nonce: nonce, // Use the fetched nonce
                value: value, // Value to be transferred
                reserved: [uint256(0), uint256(0), uint256(0), uint256(0)], // Default empty
                data: data, // Transaction calldata
                signature: hex"", // Empty signature for an unsigned transaction
                factoryDeps: factoryDeps, // Empty factory dependencies
                paymasterInput: hex"", // No paymaster input
                reservedDynamic: hex"" // Empty reserved dynamic field
            });
    }

    function _signTransaction(
        Transaction memory unsignedTransaction,
        uint256 privateKey
    ) internal view returns (Transaction memory) {
        // For zkSync AA transactions, sign the raw EIP-712 hash directly
        // DO NOT wrap with toEthSignedMessageHash() - the contract expects the raw hash
        bytes32 txHash = MemoryTransactionHelper.encodeHash(
            unsignedTransaction
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, txHash);
        Transaction memory signedTransaction = unsignedTransaction;
        signedTransaction.signature = abi.encodePacked(r, s, v);
        return signedTransaction;
    }
}
