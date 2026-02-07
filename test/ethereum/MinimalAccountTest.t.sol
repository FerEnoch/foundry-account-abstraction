// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/ethereum/HelperConfig.s.sol";
import {DeployMinimal} from "script/ethereum/DeployMinimal.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation} from "script/ethereum/SendPackedUserOp.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    uint256 constant AMOUNT = 1e18;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdcMock;
    SendPackedUserOp sendPackedUserOpScript;
    HelperConfig.NetworkConfig activeNetworkConfig;
    IEntryPoint mockEntryPoint; // Deployed mock EntryPoint instance

    address randomUser = makeAddr("randomUser");

    function setUp() public {
        DeployMinimal deployer = new DeployMinimal();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();

        // Deploy a mock USDC token
        usdcMock = new ERC20Mock();

        sendPackedUserOpScript = new SendPackedUserOp();
        // Configure activeNetworkConfig for local testing
        activeNetworkConfig = helperConfig.getConfig();

        mockEntryPoint = IEntryPoint(activeNetworkConfig.entryPoint);

        // Initialize the SendPackedUserOp script's helperConfig
        // sendPackedUserOpScript.helperConfig = helperConfig;
    }

    function test_OwnerCanExecuteCommands() public {
        // Arrange
        assertEq(
            usdcMock.balanceOf(address(minimalAccount)),
            0,
            "Initial USDC balance should be zero"
        );
        address dest = address(usdcMock); // Target contract is the USDC mock
        uint256 value = 0; // No ETH sent in the internal call from account to USDC

        // Prepare calldata for: usdcMock.mint(address(minimalAccount), AMOUNT);
        bytes memory functionData = abi.encodeWithSelector(
            usdcMock.mint.selector, // function selector for mint(address,uint256)
            address(minimalAccount), // "to", or recipient address
            AMOUNT // amount to mint
        );

        // Act
        vm.prank(minimalAccount.owner()); // Set msg.sender to the owner of the MinimalAccount
        /*  (bool success, ) = address(minimalAccount).call(
            abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                dest,
                value,
                functionData
            )
        );
        // Assert
        assertTrue(success, "Execute call failed"); */

        /* ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: */

        // Act v2
        minimalAccount.execute(dest, value, functionData);
        // Assert v2
        assertEq(
            usdcMock.balanceOf(address(minimalAccount)),
            AMOUNT,
            "USDC MinimalAccount's balance should reflect minted amount"
        );
    }

    function test_NonOwnerCannotExecuteCommands() public {
        // Arrange
        address dest = address(usdcMock); // Target contract is the USDC mock
        uint256 value = 0; // No ETH sent in the internal call from account to USDC

        // Prepare calldata for: usdcMock.mint(address(minimalAccount), AMOUNT);
        bytes memory functionData = abi.encodeWithSelector(
            usdcMock.mint.selector, // function selector for mint(address,uint256)
            address(minimalAccount), // "to", or recipient address
            AMOUNT // amount to mint
        );

        // Act / Assert
        vm.prank(randomUser); // Set msg.sender to a random user (not the owner)
        vm.expectRevert(
            abi.encodeWithSelector(
                MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector
            )
        );
        minimalAccount.execute(dest, value, functionData);
    }

    function test_RecoverSignedOp() public view {
        // Arrange
        // 1. Define the target calldata -> minting USDC through the MinimalAccount
        bytes memory functionDataForUsdcMint = abi.encodeWithSelector(
            usdcMock.mint.selector, // function selector for mint(address,uint256)
            address(minimalAccount), // "to", or recipient address
            AMOUNT // amount to mint
        );

        // 2. Define the calldata for MinimalAccount's execute function
        bytes memory executeCalldata = abi.encodeWithSelector(
            minimalAccount.execute.selector,
            address(usdcMock), // destination
            0, // value
            functionDataForUsdcMint // calldata to mint USDC
        );

        // 3. Generate the signed PackedUserOperation
        PackedUserOperation memory userOp = sendPackedUserOpScript
            .generatedSignedUserOperation(
                executeCalldata,
                activeNetworkConfig, // Contains EntryPoint and EOA signer (owner)
                address(minimalAccount)
            );

        // 4. Get the userOpHash again as the EntryPoint would calculate it
        // Ensure we use the same EntryPoint address as used in signing
        bytes32 userOpHash = mockEntryPoint.getUserOpHash(userOp);

        // Act
        // Recover the signer's address from the EIP-191 compliant digest and the signature.
        // The digest MUST match what was signed.
        bytes32 digest = userOpHash.toEthSignedMessageHash(); // Re-apply EIP-191 for recovery
        address recoveredSigner = ECDSA.recover(digest, userOp.signature);

        // On local chain, minimalAccount.owner() should be ANVIL_DEFAULT_ACCOUNT_0
        // and actualSigner should also be ANVIL_DEFAULT_ACCOUNT_0 because ANVIL_DEFAULT_PRIVATE_KEY_0 was used for signing.

        // Assert
        assertEq(
            recoveredSigner,
            minimalAccount.owner(),
            "Recovered signer should match the MinimalAccount owner"
        );
    }

    function test_ValidationOfUserOps() public {
        assertEq(
            usdcMock.balanceOf(address(minimalAccount)),
            0,
            "Initial USDC balance should be zero"
        );

        // Arrange
        address dest = address(usdcMock); // Target contract is the USDC mock
        uint256 value = 0; // No ETH sent in the internal call from account to
        bytes memory functionData = abi.encodeWithSelector(
            usdcMock.mint.selector, // function selector for mint(address,uint256)
            address(minimalAccount), // "to", or recipient address
            AMOUNT // amount to mint
        );

        bytes memory executeCallData = abi.encodeWithSelector(
            minimalAccount.execute.selector,
            dest,
            value,
            functionData
        );

        PackedUserOperation memory packedUserOp = sendPackedUserOpScript
            .generatedSignedUserOperation(
                executeCallData,
                activeNetworkConfig,
                address(minimalAccount)
            );

        bytes32 userOpHash = mockEntryPoint.getUserOpHash(packedUserOp);

        uint256 missingAccountFunds = 1e18;

        // Act
        vm.startPrank(address(mockEntryPoint));
        uint256 validationData = minimalAccount.validateUserOp(
            packedUserOp,
            userOpHash,
            missingAccountFunds
        );

        // Adding execution step for completeness
        // minimalAccount.execute(dest, value, functionData);
        vm.stopPrank();

        assertEq(
            validationData,
            SIG_VALIDATION_SUCCESS,
            "Validation data should indicate success"
        );

        // Assertion for the execution step.
        // assertEq(
        //     usdcMock.balanceOf(address(minimalAccount)),
        //     AMOUNT,
        //     "USDC MinimalAccount's balance should reflect minted amount after validated UserOp execution"
        // );
    }

    function test_EntryPointCanExecuteCommands() public {
        // Arrange
        assertEq(
            usdcMock.balanceOf(address(minimalAccount)),
            0,
            "Initial USDC balance should be zero"
        );

        // Crafting the function data for minting USDC
        bytes memory functionData = abi.encodeWithSelector(
            usdcMock.mint.selector, // function selector for mint(address,uint256)
            address(minimalAccount), // "to", or recipient address
            AMOUNT // amount to mint
        );

        // Creating execute calldata
        address dest = address(usdcMock); // Target contract is the USDC mock
        uint256 value = 0; // No ETH sent in the internal call from account to USDC

        bytes memory executeCalldata = abi.encodeWithSelector(
            minimalAccount.execute.selector,
            dest,
            value,
            functionData
        );

        // Generate a packed user operation signed by the owner

        PackedUserOperation memory packedUserOp = sendPackedUserOpScript
            .generatedSignedUserOperation(
                executeCalldata,
                activeNetworkConfig,
                address(minimalAccount)
            );

        // Funding the Smart Account with ETH to cover gas costs: Why? Because EntryPoint will pull funds from the account
        // to compensate the bundler (represented by the randomUser in our test) for the gas costs incurred in processing
        // the UserOperation.
        vm.deal(address(minimalAccount), 1e18); // Fund with 1 ETH

        // Act -> simulates the core interaction where the bundler (randomUser) submits the UserOperation to the EntryPoint
        PackedUserOperation[] memory packedUserOps = new PackedUserOperation[](
            1
        );
        packedUserOps[0] = packedUserOp;

        // Use vm.prank with a randomUser to prove that the call is coming from a random
        // EOA, as long as we sign the transaction with the owner's key.
        // Use vm.prank with both msg.sender and tx.origin set to randomUser. This is required because EntryPoint's
        // nonReentrant modifier checks:
        // tx.origin == msg.sender && msg.sender.code.length == 0
        vm.prank(randomUser, randomUser); // Simulate the bundler's address (msg.sender and tx.origin)
        mockEntryPoint.handleOps(
            packedUserOps,
            payable(randomUser) // Beneficiary address for any leftover funds
        );

        // Assert
        assertEq(
            usdcMock.balanceOf(address(minimalAccount)),
            AMOUNT,
            "USDC MinimalAccount's balance should reflect minted amount after EntryPoint execution"
        );
    }
}
