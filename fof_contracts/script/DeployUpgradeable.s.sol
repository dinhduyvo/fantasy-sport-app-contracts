// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TokenPool.sol";
import "../src/TokenPoolFactory.sol";

/**
 * @title DeployUpgradeable
 * @notice Deployment script for upgradeable contracts using UUPS pattern
 * @dev This script deploys implementation contracts and proxies with proper initialization
 */
contract DeployUpgradeable is Script {
    // Deployment addresses will be stored here
    address public tokenPoolFactoryImplementation;
    address public tokenPoolFactoryProxy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy only the factory - pools are created through factory
        deployTokenPoolFactory();

        vm.stopBroadcast();

        // Log all deployed addresses
        logDeployedAddresses();
    }


    /**
     * @notice Deploy TokenPoolFactory (ERC20 Pool Factory) with UUPS proxy pattern
     */
    function deployTokenPoolFactory() internal {
        console.log("\n=== Deploying TokenPoolFactory (ERC20 Pool Factory) ===");
        
        // 1. Deploy implementation contract
        tokenPoolFactoryImplementation = address(new TokenPoolFactory());
        console.log("TokenPoolFactory Implementation:", tokenPoolFactoryImplementation);

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            TokenPoolFactory.initialize.selector
        );

        // 3. Deploy proxy with initialization
        tokenPoolFactoryProxy = address(new ERC1967Proxy(tokenPoolFactoryImplementation, initData));
        console.log("TokenPoolFactory Proxy:", tokenPoolFactoryProxy);
        
        // 4. Verify deployment
        TokenPoolFactory tokenFactory = TokenPoolFactory(tokenPoolFactoryProxy);
        console.log("Token Factory Version:", tokenFactory.getImplementationVersion());
        console.log("Token Factory Owner:", tokenFactory.owner());
    }

    /**
     * @notice Log all deployed contract addresses
     */
    function logDeployedAddresses() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("TokenPoolFactory Implementation:", tokenPoolFactoryImplementation);
        console.log("TokenPoolFactory Proxy:", tokenPoolFactoryProxy);
        
        console.log("\n=== USAGE INSTRUCTIONS ===");
        console.log("1. Use TokenPoolFactory PROXY address for creating pools");
        console.log("2. Pools are created through factory.createTokenPool() with specific token addresses");
        console.log("3. Implementation address is for upgrade purposes only");
        console.log("4. Save factory proxy address for creating pools with different tokens");
    }
}