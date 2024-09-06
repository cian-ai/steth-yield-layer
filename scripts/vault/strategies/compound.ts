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


const rsETHAddr = "0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7";
var Vault;
var StrategyCompoundRSETH;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyCompoundRSETH = await ethers.getContractAt("StrategyCompoundRSETH", Project.StrategyCompoundRSETH);
    rebalancer = await impersonateAccount(await StrategyCompoundRSETH.rebalancer());

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printBalance(Project.StrategyCompoundRSETH, "StrategyCompoundRSETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyCompoundRSETH, "StrategyCompoundRSETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyCompoundRSETH, "StrategyCompoundRSETH", rsETHAddr, "rsETH");
    console.log("\n==== strategy data ====");
    const getProtocolAccountData = await StrategyCompoundRSETH.getProtocolAccountData();
    console.log("supplyAssetsUser                : ", ethers.utils.formatEther(getProtocolAccountData[0]));
    console.log("borrowAssetsUser                : ", ethers.utils.formatEther(getProtocolAccountData[1]));
    const getAvailableBorrowsETH = await StrategyCompoundRSETH.getAvailableBorrowsETH();
    console.log("getAvailableBorrowsETH          : ", ethers.utils.formatEther(getAvailableBorrowsETH));
    const getAvailableWithdrawsRSETH = await StrategyCompoundRSETH.getAvailableWithdrawsRSETH();
    console.log("getAvailableWithdrawsRSETH      : ", ethers.utils.formatEther(getAvailableWithdrawsRSETH));
    const getRatio = await StrategyCompoundRSETH.getRatio();
    console.log("getRatio                        : ", ethers.utils.formatEther(getRatio));
    const getCollateralRatio = await StrategyCompoundRSETH.getCollateralRatio();
    console.log("getCollateralRatio              : ", ethers.utils.formatEther(getCollateralRatio[0]));
    const getNetAssets = await StrategyCompoundRSETH.getNetAssets();
    console.log("getNetAssets                    : ", ethers.utils.formatEther(getNetAssets));
    const getKelpUnstakingAmount = await StrategyCompoundRSETH.getKelpUnstakingAmount();
    console.log("getKelpUnstakingAmount          : ", ethers.utils.formatEther(getKelpUnstakingAmount));
    const getStETHByRsETH = await StrategyCompoundRSETH.getStETHByRsETH(oneEther);
    console.log("getStETHByRsETH                 : ", ethers.utils.formatEther(getStETHByRsETH));
    const getRsETHByStETH = await StrategyCompoundRSETH.getRsETHByStETH(oneEther);
    console.log("getRsETHByStETH                 : ", ethers.utils.formatEther(getRsETHByStETH));
    const getLeverageAmount = await StrategyCompoundRSETH.getLeverageAmount(true, 0);
    console.log("getLeverageAmount               : ", getLeverageAmount);
}

async function leverageCompound() {
    console.log("\n\n==== leverageCompound ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(1);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        rsETHAddr,
        Project.StrategyCompoundRSETH,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyCompoundRSETH.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageCompound() {
    console.log("\n\n==== deleverageCompound ====");

    const withdrawAount = oneEther.mul(1);
    const deleverageAount = oneEther.mul(1).div(2);
    const swapData = await getOneInchDataV6(
        rsETHAddr,
        chainAddrData.weth,
        Project.StrategyCompoundRSETH,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyCompoundRSETH.connect(rebalancer).deleverage(
        withdrawAount,
        deleverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function leverageCompoundWithFlashloan() {
    console.log("\n\n==== leverageCompoundWithFlashloan ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(6);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        rsETHAddr,
        Project.StrategyCompoundRSETH,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyCompoundRSETH.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageCompoundWithFlashloan() {
    console.log("\n\n==== deleverageCompoundWithFlashloan ====");

    const withdrawAount = oneEther.mul(3);
    const deleverageAount = oneEther.mul(2);
    const swapData = await getOneInchDataV6(
        rsETHAddr,
        chainAddrData.weth,
        Project.StrategyCompoundRSETH,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyCompoundRSETH.connect(rebalancer).deleverage(
        withdrawAount,
        deleverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function unstakeToStETH() {
    console.log("\n\n==== unstake ====");

    const unstakeAmount = oneEther.mul(3);
    const result = await StrategyCompoundRSETH.connect(rebalancer).unstake(unstakeAmount, chainAddrData.steth);
    await printGas(result);
    await query();
}

async function unstakeToETH() {
    console.log("\n\n==== unstake ====");

    const unstakeAmount = oneEther.mul(3);
    const result = await StrategyCompoundRSETH.connect(rebalancer).unstake(unstakeAmount, publicData.eth);
    await printGas(result);
    await query();
}

const main = async (): Promise<any> => {
    await query();

    // await leverageCompound();
    // await deleverageCompound();
    // await leverageCompoundWithFlashloan();
    // await deleverageCompoundWithFlashloan();
    // await unstakeToStETH();
    await unstakeToETH();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
