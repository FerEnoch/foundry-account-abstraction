// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "../../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMinimal is Script {
    function deployMinimalAccount()
        public
        returns (
            HelperConfig helperConfigInstance,
            MinimalAccount minimalAccountContract
        )
    {
        helperConfigInstance = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfigInstance
            .getConfig();

        vm.startBroadcast(config.account); // Use burner wallet from config for broadcasting (on local, config.account is ANVIL_DEFAULT_ACCOUNT_0)
        minimalAccountContract = new MinimalAccount(config.entryPoint);
        // It's often good practice for clarity and to ensure the intended final owner.
        minimalAccountContract.transferOwnership(config.account);
        vm.stopBroadcast();
        return (helperConfigInstance, minimalAccountContract);
    }

    function run() external returns (HelperConfig, MinimalAccount) {
        return deployMinimalAccount();
    }
}
