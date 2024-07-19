import { ethers } from "hardhat";
import { accounts, chainAddrData, publicData } from "../../data/tools/constants";
import { oneEther } from "../../data/tools/unitconverter";
import { Project } from "../../utils/deployed";
import { config as dotEnvConfig } from "dotenv";
import { CURRENT_RPC } from "../../../hardhat.config";
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);
import { impersonateAccount, printETHBalance, printBalance } from "../../data/tools/utils";
dotEnvConfig();
const steakhouseAddr = "0xBEEF69Ac7870777598A04B2bd4771c71212E6aBc";
var Vault;
var StrategyMellowSteakhouse;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyMellowSteakhouse = await ethers.getContractAt("StrategyMellowSteakhouse", Project.StrategyMellowSteakhouse);
    rebalancer = await impersonateAccount(await StrategyMellowSteakhouse.rebalancer());

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", steakhouseAddr, "lrtETH");
    console.log("\n==== strategy data ====");
    const getProtocolPendingAmount = await StrategyMellowSteakhouse.getProtocolPendingAmount();
    console.log("getProtocolPendingAmount           : ", ethers.utils.formatEther(getProtocolPendingAmount));
    const getProtocolNetAssets = await StrategyMellowSteakhouse.getProtocolNetAssets();
    console.log("getProtocolNetAssets               : ", ethers.utils.formatEther(getProtocolNetAssets));
    const getNetAssets = await StrategyMellowSteakhouse.getNetAssets();
    console.log("getNetAssets                       : ", ethers.utils.formatEther(getNetAssets));
}

async function enterProtocol() {
    console.log("\n\n==== enterProtocol ====");

    const deposit = oneEther.mul(10);
    const minLpAmount = 0;
    await StrategyMellowSteakhouse.connect(rebalancer).enterProtocol(deposit, minLpAmount);

    await query();
}

async function exitProtocol() {
    console.log("\n\n==== exitProtocol ====");

    const lpAmount = oneEther.mul(5);
    const minLpAmount = lpAmount.mul(10e6 - 1).div(10e6);
    const timestamp = Math.floor(Date.now() / 1000);
    const deadline = timestamp + 3600;
    const requestDeadline = timestamp + 3600 * 12;
    console.log("minLpAmount     = ", minLpAmount);
    console.log("timestamp       = ", timestamp);
    console.log("requestDeadline = ", requestDeadline);
    await StrategyMellowSteakhouse.connect(rebalancer).exitProtocol(lpAmount, minLpAmount, deadline, requestDeadline);

    await query();
}

const main = async (): Promise<any> => {
    await query();

    await enterProtocol();
    await exitProtocol();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
