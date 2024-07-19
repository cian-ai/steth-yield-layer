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
var StrategyMorphoBlueRSETH;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyMorphoBlueRSETH = await ethers.getContractAt("StrategyMorphoBlueRSETH", Project.StrategyMorphoBlueRSETH);
    rebalancer = await impersonateAccount(await StrategyMorphoBlueRSETH.rebalancer());

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", rsETHAddr, "rsETH");
    console.log("\n==== strategy data ====");
    const supplyAssetsUser = await StrategyMorphoBlueRSETH.supplyAssetsUser();
    console.log("supplyAssetsUser                : ", ethers.utils.formatEther(supplyAssetsUser));
    const collateralAssetsUser = await StrategyMorphoBlueRSETH.collateralAssetsUser();
    console.log("collateralAssetsUser            : ", ethers.utils.formatEther(collateralAssetsUser));
    const borrowAssetsUser = await StrategyMorphoBlueRSETH.borrowAssetsUser();
    console.log("borrowAssetsUser                : ", ethers.utils.formatEther(borrowAssetsUser));
    const getAvailableBorrowsETH = await StrategyMorphoBlueRSETH.getAvailableBorrowsETH();
    console.log("getAvailableBorrowsETH          : ", ethers.utils.formatEther(getAvailableBorrowsETH));
    const getAvailableWithdrawsRSETH = await StrategyMorphoBlueRSETH.getAvailableWithdrawsRSETH();
    console.log("getAvailableWithdrawsRSETH      : ", ethers.utils.formatEther(getAvailableWithdrawsRSETH));
    const getRatio = await StrategyMorphoBlueRSETH.getRatio();
    console.log("getRatio                        : ", ethers.utils.formatEther(getRatio));
    const getCollateralRatio = await StrategyMorphoBlueRSETH.getCollateralRatio();
    console.log("getCollateralRatio              : ", ethers.utils.formatEther(getCollateralRatio[0]));
    const getNetAssets = await StrategyMorphoBlueRSETH.getNetAssets();
    console.log("getNetAssets                    : ", ethers.utils.formatEther(getNetAssets));
    const getKelpUnstakingAmount = await StrategyMorphoBlueRSETH.getKelpUnstakingAmount();
    console.log("getKelpUnstakingAmount          : ", ethers.utils.formatEther(getKelpUnstakingAmount));
    const getStETHByRsETH = await StrategyMorphoBlueRSETH.getStETHByRsETH(oneEther);
    console.log("getStETHByRsETH                 : ", ethers.utils.formatEther(getStETHByRsETH));
    const getRsETHByStETH = await StrategyMorphoBlueRSETH.getRsETHByStETH(oneEther);
    console.log("getRsETHByStETH                 : ", ethers.utils.formatEther(getRsETHByStETH));
    const getLeverageAmount = await StrategyMorphoBlueRSETH.getLeverageAmount(true, 0);
    console.log("getLeverageAmount               : ", getLeverageAmount);
}

async function leverageMorphoBlue() {
    console.log("\n\n==== leverageMorphoBlue ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(1);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        rsETHAddr,
        Project.StrategyMorphoBlueRSETH,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyMorphoBlueRSETH.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageMorphoBlue() {
    console.log("\n\n==== deleverageMorphoBlue ====");

    const withdrawAount = oneEther.mul(1);
    const deleverageAount = oneEther.mul(1).div(2);
    const swapData = await getOneInchDataV6(
        rsETHAddr,
        chainAddrData.weth,
        Project.StrategyMorphoBlueRSETH,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyMorphoBlueRSETH.connect(rebalancer).deleverage(
        withdrawAount,
        deleverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function leverageMorphoBlueWithFlashloan() {
    console.log("\n\n==== leverageMorphoBlueWithFlashloan ====");

    const depositAount = oneEther.mul(5);
    const leverageAount = oneEther.mul(6);
    const swapData = await getOneInchDataV6(
        chainAddrData.weth,
        rsETHAddr,
        Project.StrategyMorphoBlueRSETH,
        leverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyMorphoBlueRSETH.connect(rebalancer).leverage(
        depositAount,
        leverageAount,
        swapBytes,
        swapGetMin,
        flashloanSelector
    );
    await printGas(result);
    await query();
}

async function deleverageMorphoBlueWithFlashloan() {
    console.log("\n\n==== deleverageMorphoBlueWithFlashloan ====");

    const withdrawAount = oneEther.mul(3);
    const deleverageAount = oneEther.mul(2);
    const swapData = await getOneInchDataV6(
        rsETHAddr,
        chainAddrData.weth,
        Project.StrategyMorphoBlueRSETH,
        deleverageAount
    );
    const swapBytes = swapData[0];
    const swapGetMin = 0;
    const flashloanSelector = 1;
    const result = await StrategyMorphoBlueRSETH.connect(rebalancer).deleverage(
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
    const result = await StrategyMorphoBlueRSETH.connect(rebalancer).unstake(unstakeAmount);
    await printGas(result);
    await query();
}

const main = async (): Promise<any> => {
    await query();

    await leverageMorphoBlue();
    // await deleverageMorphoBlue();
    // await leverageMorphoBlueWithFlashloan();
    // await deleverageMorphoBlueWithFlashloan();
    // await unstake();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
