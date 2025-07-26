// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/FOFToken.sol";

contract DeployFOFToken is Script {
    function run() external returns (FOFToken) {
        vm.startBroadcast();

        FOFToken token = new FOFToken();

        vm.stopBroadcast();

        return token;
    }
}
