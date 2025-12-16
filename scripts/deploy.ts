import {ethers, network} from 'hardhat';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-verify';

// Address of the USDC token contract on Avalanche C-Chain
// This is the official USDC contract address that we'll interact with
 const S0X_ADDR_TOKEN_USDC_AVALANCHE = '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d';

async function main() {
	// get deployer signer
	// const [y_deployer] = await ethers.getSigners();

	// // get contract factory
	// const y_factory_gateway = await ethers.getContractFactory('SilentSwapV2Gateway');
    // const y_factory_depositor = await ethers.getContractFactory('SilentSwapDepositor');

	// // deploy gateway
	// const y_contract_gateway = await y_factory_gateway.deploy(S0X_ADDR_TOKEN_USDC_AVALANCHE, {
	// 	minDuration: 1, // 1 hour in seconds
	// 	maxDuration: 36000000, // 7 days in seconds
	// 	minDepositAmount: ethers.parseUnits('1', 6), // 1 USDC (6 decimals)
	// }, y_deployer.address);

	// // wait for deployment tx
	// await y_contract_gateway.waitForDeployment();

	// // confirm gateway
	// const gatewayAddress = await y_contract_gateway.getAddress();
	// console.log('Gateway deployed to:', gatewayAddress);

	// // add approver
	// await y_contract_gateway.addApprover('0x033c1cCc54303117D23E05C063751c18c8203918');

	// await new Promise(resolve => setTimeout(resolve, 10000));

	// // deploy depositor proxy (takes gateway and usdc addresses)
	// const y_contract_depositor = await y_factory_depositor.deploy(gatewayAddress, S0X_ADDR_TOKEN_USDC_AVALANCHE);
	// await y_contract_depositor.waitForDeployment();
	// const depositorAddress = await y_contract_depositor.getAddress();
	// console.log('Depositor deployed to:', depositorAddress);

	// Verify contracts on Snowtrace
	console.log('Verifying contracts on Snowtrace...');

	const gatewayAddress = '0xAAef732E8B327917BF44A7892102A5ED3Bd27842';
	const depositorAddress = '0x02AcB3A073eF5625Ec0e30481df1cf8c4bD7a98E';
// 	Gateway deployed to: 0xAAef732E8B327917BF44A7892102A5ED3Bd27842
// Depositor deployed to: 0x02AcB3A073eF5625Ec0e30481df1cf8c4bD7a98E
	
	await new Promise(resolve => setTimeout(resolve, 20000));

	try {
		// Verify Gateway
		await run('verify:verify', {
			address: gatewayAddress,
			constructorArguments: [
				S0X_ADDR_TOKEN_USDC_AVALANCHE,
				{
					minDuration: 3600, // 1 hour in seconds
					maxDuration: 3600 * 24 * 7, // 7 days in seconds
					minDepositAmount: ethers.parseUnits('1', 6), // 1 USDC (6 decimals)
				},
				'0x116e9D6740574F354610b8D15e8BF5Fff00aFE01'
			],
		});
		console.log('Gateway verified successfully on Snowtrace');
	} catch (error: any) {
		console.log('Gateway verification failed:', error.message);
	}

	await new Promise(resolve => setTimeout(resolve, 20000));
	try {
		// Verify Depositor
		await run('verify:verify', {
			address: depositorAddress,
			constructorArguments: [gatewayAddress, S0X_ADDR_TOKEN_USDC_AVALANCHE],
		});
		console.log('Depositor verified successfully on Snowtrace');
	} catch (error: any) {
		console.log('Depositor verification failed:', error.message);
	}
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
