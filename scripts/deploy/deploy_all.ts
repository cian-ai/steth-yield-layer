import { ethers } from "hardhat";
import { oneEther } from "../data/tools/unitconverter";
import { accounts, chainAddrData, chainSlotData, publicData } from "../data/tools/constants";
import { mintToken } from "../data/tools/minter";
import { CURRENT_RPC } from "../../hardhat.config";
import { BigNumber } from "ethers";
import { impersonateAccount } from "../data/tools/utils";
const fs = require("fs");
let ALL = new Object();

const { LedgerSigner } = require("@anders-t/ethers-ledger");
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);
const ledger = new LedgerSigner(ethers.provider);
var signer;

const UtilAddress = {
    DaiFlashMinter: "0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA",
    GHOFlashMinter: "0xb639D208Bcf0589D54FaC24E655C79EC529762B8",
    BalancerERC3156: "0xa958090601E21A82e9873042652e35891D945a8C",
};

const PoolAddress = {
    AavePool: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
    SparkPool: "0xC13e21B648A5Ee794902342038FF3aDAB66BE987",
};

async function deploy_contract(name: string, arg: any = [], accountIndex: number = 1) {
    const _contract = await ethers.getContractFactory(name);
    const ret = await _contract.connect(signer).deploy(...arg);
    // const ret = await _contract.connect(signer).deploy(...arg, { gasLimit: 1e7, maxFeePerGas: 6e9, maxPriorityFeePerGas: 3e9 });
    await ret.deployTransaction.wait();
    console.log(name + " deployed to:", ret.address);
    if (arg.length != 0) {
        await argsWriteToFile(name, arg);
    }
    return ret;
}

async function deploy_pool() {
    console.log("signer.address = ", signer.address);
    const MultiSig = await deploy_contract("MultiSig");
    const Manager = await deploy_contract("Manager", [MultiSig.address, accounts[1]]);
    const StrategyETHConverterImplementation = await deploy_contract("StrategyETHConverter");
    const StrategyAAVEV3Implementation = await deploy_contract("StrategyAAVEV3");
    const StrategyAAVEV3LIDOImplementation = await deploy_contract("StrategyAAVEV3LIDO");
    const StrategyMellowSteakhouseImplementation = await deploy_contract("StrategyMellowSteakhouse");
    const StrategyHybridWeETHImplementation = await deploy_contract("StrategyHybridWeETH");
    const StrategyMorphoBlueImplementation = await deploy_contract("StrategyMorphoBlueRSETH");
    const StrategyUniswapV3Implementation = await deploy_contract("StrategyUniswapV3");
    const HybridLongShortAaveAdapter = await deploy_contract("AaveLendingAdapter");
    const HybridLongShortSparkAdapter = await deploy_contract("SparkLendingAdapter");
    const selector = web3.eth.abi.encodeFunctionSignature("initialize(bytes)");
    const protocolRatio = oneEther.mul(8000).div(10000); // 8000/10000 = 80% aave v3
    const MultiSigAddr = MultiSig.address;
    const MultiSiger = await impersonateAccount(MultiSig.address);
    const flashloanHelper = "0x49d9409111a6363d82C4371fFa43fAEA660C917B";
    const rebalancer = Manager.address;
    const feeReceiver = accounts[2];

    let ETHConverterArgs = web3.eth.abi.encodeParameters(["address", "address"], [MultiSigAddr, rebalancer]);
    ETHConverterArgs = web3.eth.abi.encodeParameters(["bytes"], [ETHConverterArgs]);
    const totalETHConverterArgs = selector + ETHConverterArgs.substring(2, ETHConverterArgs.length);

    let aavev3Args = web3.eth.abi.encodeParameters(
        ["uint256", "address", "address", "address"],
        [protocolRatio.toString(), MultiSigAddr, flashloanHelper, rebalancer]
    );
    aavev3Args = web3.eth.abi.encodeParameters(["bytes"], [aavev3Args]);
    const totalStategyAaveV3Args = selector + aavev3Args.substring(2, aavev3Args.length);

    let morphoArgs = web3.eth.abi.encodeParameters(
        ["uint256", "address", "address", "address"],
        [protocolRatio.toString(), MultiSigAddr, flashloanHelper, rebalancer]
    );
    morphoArgs = web3.eth.abi.encodeParameters(["bytes"], [morphoArgs]);
    const totalStategyMorphoArgs = selector + morphoArgs.substring(2, morphoArgs.length);

    let steakhouseArgs = web3.eth.abi.encodeParameters(
        ["address", "address", "address"],
        [chainAddrData.steth, MultiSigAddr, rebalancer]
    );
    steakhouseArgs = web3.eth.abi.encodeParameters(["bytes"], [steakhouseArgs]);
    const totalSteakhouseArgsArgs = selector + steakhouseArgs.substring(2, steakhouseArgs.length);

    const l2Receiver = accounts[2];
    let hybridArgs = web3.eth.abi.encodeParameters(
        ["address", "address", "address[]", "address[]", "address[]", "bytes[]"],
        [
            MultiSigAddr,
            rebalancer,
            [l2Receiver],
            [UtilAddress.BalancerERC3156, UtilAddress.DaiFlashMinter, UtilAddress.GHOFlashMinter],
            [HybridLongShortAaveAdapter.address, HybridLongShortSparkAdapter.address],
            [
                HybridLongShortAaveAdapter.interface.encodeFunctionData("init", [PoolAddress.AavePool]),
                HybridLongShortSparkAdapter.interface.encodeFunctionData("init", [PoolAddress.SparkPool]),
            ],
        ]
    );
    hybridArgs = web3.eth.abi.encodeParameters(["bytes"], [hybridArgs]);
    const totalHybridArgsArgs = selector + hybridArgs.substring(2, hybridArgs.length);

    let uniswapv3Args = web3.eth.abi.encodeParameters(["address", "address"], [MultiSigAddr, rebalancer]);
    uniswapv3Args = web3.eth.abi.encodeParameters(["bytes"], [uniswapv3Args]);
    const totalUniswapv3Args = selector + uniswapv3Args.substring(2, uniswapv3Args.length);

    const VaultImplementation = await deploy_contract("VaultYieldETH");
    const marketCapacity = oneEther.mul(10000);
    const managementFeeRate = 0;
    const managementFeeClaimPeriod = 3600 * 24 * 7;
    const maxPriceUpdatePeriod = 3600 * 24 * 2;
    const revenueRate = 800; // 800/10000 = 8% profitFee
    const exitFeeRate = 2; // 2/10000
    const lpName = "CIAN YIELD ETH Pool";
    const lpSymbol = "ci-yield-ETH";

    let args = web3.eth.abi.encodeParameter(
        {
            VaultParams: {
                underlyingToken: "address",
                name: "string",
                symbol: "string",
                marketCapacity: "uint256",
                managementFeeRate: "uint256",
                managementFeeClaimPeriod: "uint256",
                maxPriceUpdatePeriod: "uint256",
                revenueRate: "uint256",
                exitFeeRate: "uint256",
                vaultAdmin: "address",
                rebalancer: "address",
                feeReceiver: "address",
                redeemOperator: "address",
            },
        },
        {
            underlyingToken: chainAddrData.weth,
            name: lpName,
            symbol: lpSymbol,
            marketCapacity: marketCapacity.toString(),
            managementFeeRate: managementFeeRate,
            managementFeeClaimPeriod: managementFeeClaimPeriod,
            maxPriceUpdatePeriod: maxPriceUpdatePeriod,
            revenueRate: revenueRate,
            exitFeeRate: exitFeeRate,
            vaultAdmin: MultiSigAddr,
            rebalancer: rebalancer,
            feeReceiver: feeReceiver,
            redeemOperator: publicData.zero,
        }
    );
    args = web3.eth.abi.encodeParameters(["bytes"], [args]);
    const totalArgs = selector + args.substring(2, args.length);
    const Vault = await deploy_contract("TransparentUpgradeableProxy", [
        VaultImplementation.address,
        MultiSigAddr,
        totalArgs,
    ]);
    const VaultContract = await ethers.getContractAt("VaultYieldETH", Vault.address);

    const positionLimit = 3000; // 3000/10000 = 30%
    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyETHConverterImplementation.address,
        totalETHConverterArgs,
        positionLimit
    );

    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyAAVEV3Implementation.address,
        totalStategyAaveV3Args,
        positionLimit
    );

    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyAAVEV3LIDOImplementation.address,
        totalStategyAaveV3Args,
        positionLimit
    );

    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyMellowSteakhouseImplementation.address,
        totalSteakhouseArgsArgs,
        positionLimit
    );
    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyHybridWeETHImplementation.address,
        totalHybridArgsArgs,
        positionLimit
    );
    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyMorphoBlueImplementation.address,
        totalStategyMorphoArgs,
        positionLimit
    );

    await VaultContract.connect(MultiSiger).createStrategy(
        StrategyUniswapV3Implementation.address,
        totalUniswapv3Args,
        positionLimit
    );

    const strategies = await VaultContract.strategies();
    console.log("strategies = ", strategies);
    const StrategyETHConverter = await ethers.getContractAt("StrategyETHConverter", strategies[0]);
    const StrategyAAVEV3 = await ethers.getContractAt("StrategyAAVEV3", strategies[1]);
    const StrategyAAVEV3LIDO = await ethers.getContractAt("StrategyAAVEV3LIDO", strategies[2]);
    const StrategyMellowSteakhouse = await ethers.getContractAt("StrategyMellowSteakhouse", strategies[3]);
    const StrategyHybridWeETH = await ethers.getContractAt("StrategyHybridWeETH", strategies[4]);
    const StrategyMorphoBlueRSETH = await ethers.getContractAt("StrategyMorphoBlueRSETH", strategies[5]);
    const StrategyUniswapV3 = await ethers.getContractAt("StrategyUniswapV3", strategies[6]);

    const RedeemOperator = await deploy_contract("RedeemOperator", [
        MultiSigAddr,
        Vault.address,
        Manager.address,
        feeReceiver,
    ]);

    Object.assign(ALL, {
        Manager,
        MultiSig,
        StrategyETHConverterImplementation,
        StrategyAAVEV3Implementation,
        StrategyAAVEV3LIDOImplementation,
        StrategyMellowSteakhouseImplementation,
        StrategyHybridWeETHImplementation,
        StrategyMorphoBlueImplementation,
        StrategyUniswapV3Implementation,
        HybridLongShortAaveAdapter,
        HybridLongShortSparkAdapter,
        StrategyETHConverter,
        StrategyAAVEV3,
        StrategyAAVEV3LIDO,
        StrategyMellowSteakhouse,
        StrategyHybridWeETH,
        StrategyMorphoBlueRSETH,
        StrategyUniswapV3,
        VaultImplementation,
        Vault,
        RedeemOperator,
    });
}

async function argsWriteToFile(name: string, arg: any = []) {
    let data;
    if (arg.length == 0) {
        data = "module.exports = " + `[` + `]`;
    } else {
        data = "module.exports = " + `["` + arg.toString().replace(/,/g, `","`) + `"]`;
    }

    const options = { encoding: "utf8", flag: "w+" };
    const fileName: string = "scripts/deploy/constructor_args/" + name + ".js";
    fs.writeFileSync(fileName, data, options);
}

async function writeToFile() {
    let addresses = {
        Manager: (ALL as any).Manager.address,
        MultiSig: (ALL as any).MultiSig.address,
        StrategyETHConverterImplementation: (ALL as any).StrategyETHConverterImplementation.address,
        StrategyAAVEV3Implementation: (ALL as any).StrategyAAVEV3Implementation.address,
        StrategyAAVEV3LIDOImplementation: (ALL as any).StrategyAAVEV3LIDOImplementation.address,
        StrategyMellowSteakhouseImplementation: (ALL as any).StrategyMellowSteakhouseImplementation.address,
        StrategyHybridWeETHImplementation: (ALL as any).StrategyHybridWeETHImplementation.address,
        StrategyMorphoBlueImplementation: (ALL as any).StrategyMorphoBlueImplementation.address,
        StrategyUniswapV3Implementation: (ALL as any).StrategyUniswapV3Implementation.address,
        StrategyETHConverter: (ALL as any).StrategyETHConverter.address,
        StrategyAAVEV3: (ALL as any).StrategyAAVEV3.address,
        StrategyAAVEV3LIDO: (ALL as any).StrategyAAVEV3LIDO.address,
        StrategyMellowSteakhouse: (ALL as any).StrategyMellowSteakhouse.address,
        StrategyHybridWeETH: (ALL as any).StrategyHybridWeETH.address,
        StrategyMorphoBlueRSETH: (ALL as any).StrategyMorphoBlueRSETH.address,
        StrategyUniswapV3: (ALL as any).StrategyUniswapV3.address,
        HybridLongShortAaveAdapter: (ALL as any).HybridLongShortAaveAdapter.address,
        HybridLongShortSparkAdapter: (ALL as any).HybridLongShortSparkAdapter.address,
        VaultImplementation: (ALL as any).VaultImplementation.address,
        Vault: (ALL as any).Vault.address,
        RedeemOperator: (ALL as any).RedeemOperator.address,
    };
    console.log(addresses);
    let data = JSON.stringify(addresses);
    const options = { encoding: "utf8", flag: "w+" };
    fs.writeFileSync("deployments/deployedAddress/deployed.json", data, options);
}

async function main() {
    // signer = await ledger;
    signer = (await ethers.getSigners())[1];
    await deploy_pool();
    await writeToFile();
    await mintToken(accounts[0], chainAddrData.weth, 1000, 18, CURRENT_RPC, chainSlotData[chainAddrData.weth]);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
