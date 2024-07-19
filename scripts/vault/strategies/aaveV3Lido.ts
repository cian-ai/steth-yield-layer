import { ethers } from "hardhat";
import { accounts, chainAddrData, publicData } from "../../data/tools/constants";
import { oneEther } from "../../data/tools/unitconverter";
import { getOneInchDataV6 } from "../../data/tools/1inch";
import { Project } from "../../utils/deployed";
import { config as dotEnvConfig } from "dotenv";
import { CURRENT_RPC } from "../../../hardhat.config";
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);
import { impersonateAccount, printETHBalance, printBalance, printGas } from "../../data/tools/utils";
dotEnvConfig();

var Vault;
var StrategyAAVEV3LIDO;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyAAVEV3LIDO = await ethers.getContractAt("StrategyAAVEV3LIDO", Project.StrategyAAVEV3LIDO);
    rebalancer = await impersonateAccount(await StrategyAAVEV3LIDO.rebalancer());

    await printETHBalance(userAddress, "User");
    console.log("=======");
    const A_WSTETH_AAVEV3_LIDO = "0xC035a7cf15375cE2706766804551791aD035E0C2";
    const D_WETH_AAVEV3_LIDO = "0x91b7d78BF92db564221f6B5AeE744D1727d1Dd1e";
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", A_WSTETH_AAVEV3_LIDO, "awstETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", D_WETH_AAVEV3_LIDO, "DWETH");
    console.log("\n==== strategy data ====");
    const getRatio = await StrategyAAVEV3LIDO.getRatio();
    console.log("getRatio                        : ", ethers.utils.formatEther(getRatio));
    const getCollateralRatio = await StrategyAAVEV3LIDO.getCollateralRatio();
    console.log("getCollateralRatio              : ", ethers.utils.formatEther(getCollateralRatio[0]));
    const getNetAssets = await StrategyAAVEV3LIDO.getNetAssets();
    console.log("getNetAssets                    : ", ethers.utils.formatEther(getNetAssets));
    const getAvailableBorrowsETH = await StrategyAAVEV3LIDO.getAvailableBorrowsETH();
    console.log("getAvailableBorrowsETH          : ", ethers.utils.formatEther(getAvailableBorrowsETH));
    const getAvailableWithdrawsStETH = await StrategyAAVEV3LIDO.getAvailableWithdrawsStETH();
    console.log("getAvailableWithdrawsStETH      : ", ethers.utils.formatEther(getAvailableWithdrawsStETH));
    const getProtocolAccountData = await StrategyAAVEV3LIDO.getProtocolAccountData();
    console.log("getProtocolAccountData[0]       : ", ethers.utils.formatEther(getProtocolAccountData[0]));
    console.log("getProtocolAccountData[1]       : ", ethers.utils.formatEther(getProtocolAccountData[1]));
    const getProtocolNetAssets = await StrategyAAVEV3LIDO.getProtocolNetAssets();
    console.log("getProtocolNetAssets            : ", ethers.utils.formatEther(getProtocolNetAssets));
    const getLeverageAmount = await StrategyAAVEV3LIDO.getLeverageAmount(true, oneEther);
    console.log("getLeverageAmount               : ", getLeverageAmount);
}

async function leverageAAVEV3() {
    console.log("\n\n==== leverageAAVEV3 ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(1);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        chainAddrData.steth,
        Project.StrategyAAVEV3LIDO,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyAAVEV3LIDO.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageAAVEV3() {
    console.log("\n\n==== deleverageAAVEV3 ====");

    const withdrawAount = oneEther.mul(1);
    const deleverageAount = oneEther.mul(1).div(2);
    const swapData = await getOneInchDataV6(
        chainAddrData.steth,
        chainAddrData.weth,
        Project.StrategyAAVEV3LIDO,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyAAVEV3LIDO.connect(rebalancer).deleverage(
        withdrawAount,
        deleverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function leverageAAVEV3WithFlashloan() {
    console.log("\n\n==== leverageAAVEV3WithFlashloan ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(6);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        chainAddrData.steth,
        Project.StrategyAAVEV3LIDO,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyAAVEV3LIDO.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageAAVEV3WithFlashloan() {
    console.log("\n\n==== deleverageAAVEV3WithFlashloan ====");

    const withdrawAount = oneEther.mul(3);
    const deleverageAount = oneEther.mul(2);
    const swapData = await getOneInchDataV6(
        chainAddrData.steth,
        chainAddrData.weth,
        Project.StrategyAAVEV3LIDO,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyAAVEV3LIDO.connect(rebalancer).deleverage(
        withdrawAount,
        deleverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function unstake() {
    console.log("\n\n==== unstake ====");

    const unstakeAmount = oneEther.mul(3);
    const result = await StrategyAAVEV3LIDO.connect(rebalancer).convertToken(
        chainAddrData.steth,
        publicData.eth,
        unstakeAmount
    );
    await printGas(result);
    await query();
}

const main = async (): Promise<any> => {
    await query();

    await leverageAAVEV3();
    await deleverageAAVEV3();
    // await leverageAAVEV3WithFlashloan();
    // await deleverageAAVEV3WithFlashloan();
    await unstake();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
