// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    uint256 constant ETH_SEPOLIA_CHAINID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAINID = 300;
    uint256 constant LOCAL_CHAINID = 31337; // anvil default

    // Official sepolia EntryPoint address: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
    address constant ETH_SEPOLIA_ENTRYPOINT =
        0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address constant BURNER_WALLET = 0xF0A3464a19cdd211390535cD8Fcdd49F0191e64b;
    // address constant FOUNDRY_DEFAULT_SENDER =
    //     0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address constant ANVIL_DEFAULT_ACCOUNT_0 =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // State variables
    NetworkConfig public activeNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAINID] = getEthSepoliaConfig();
        networkConfigs[ZKSYNC_SEPOLIA_CHAINID] = getZkSyncSepoliaConfig();
    }

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entryPoint: ETH_SEPOLIA_ENTRYPOINT,
                account: BURNER_WALLET
            });
    }

    // ZKSync Era has native account abstraction, an external EntryPoint might not be used in the same way.
    // address(0) is used as a placeholder, or to indicate reliance on native mechanisms.
    function getZkSyncSepoliaConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return NetworkConfig({entryPoint: address(0), account: BURNER_WALLET});
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.account != address(0)) { // Check if already configured
            return activeNetworkConfig;
        }

        // For local Anvil network, we might need to deploy a mock EntryPoint:
        // address mockEntryPoint = deployMockEntryPoint();
        // In a real scenario, you'd deploy a MockEntryPoint.sol here.
        // Example: activeNetworkConfig = NetworkConfig({ entryPoint: mockEntryPointAddress, account: BURNER_WALLET });
        console2.log("Deploying mock EntryPoint for local Anvil network...");

        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT_0);
        EntryPoint entryPoint = new EntryPoint();
        // ... (deploy other necessary mock contracts)
        vm.stopBroadcast();

        activeNetworkConfig = NetworkConfig({
            entryPoint: address(entryPoint),
            account: ANVIL_DEFAULT_ACCOUNT_0
        });

        return activeNetworkConfig;
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAINID) {
            return getOrCreateAnvilEthConfig();
        }
        if (networkConfigs[chainId].account != address(0)) {
            return networkConfigs[chainId];
        }
        revert("HelperConfig__InvalidChainId");
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }
}
