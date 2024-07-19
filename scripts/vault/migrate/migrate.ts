import { ethers } from "hardhat";
import { accounts, chainAddrData, publicData } from "../../data/tools/constants";
import { oneEther, fullAmount } from "../../data/tools/unitconverter";
import { Project } from "../../utils/deployed";
import { config as dotEnvConfig } from "dotenv";
import { CURRENT_RPC } from "../../../hardhat.config";
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);
const axios = require("axios");

import {
    impersonateAccount,
    printETHBalance,
    setETH,
    printBalance,
    getBalance,
    printGas,
} from "../../data/tools/utils";
import { BigNumber } from "ethers";
dotEnvConfig();

var Vault;
var StrategyAAVEV3;
var StrategyMellowSteakhouse;
var StrategyHybridWeETH;
var Manager;
var RedeemOperator;
var kmsOperator;
var managerContract;
var User;

const okLinkApikey = "---";
const steakhouseAddr = "0xBEEF69Ac7870777598A04B2bd4771c71212E6aBc";
async function query() {
    const rsETHAddr = "0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7";
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    kmsOperator = (await ethers.getSigners())[1];
    managerContract = await impersonateAccount(Project.Manager);
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyAAVEV3 = await ethers.getContractAt("StrategyAAVEV3", Project.StrategyAAVEV3);
    StrategyMellowSteakhouse = await ethers.getContractAt("StrategyMellowSteakhouse", Project.StrategyMellowSteakhouse);
    StrategyHybridWeETH = await ethers.getContractAt("StrategyHybridWeETH", Project.StrategyHybridWeETH);
    Manager = await ethers.getContractAt("Manager", Project.Manager);
    RedeemOperator = await ethers.getContractAt("RedeemOperator", Project.RedeemOperator);

    await printETHBalance(userAddress, "User");
    await printBalance(userAddress, "User", chainAddrData.weth, "  WETH");
    await printBalance(userAddress, "User", chainAddrData.eeth, "  lrtETH");
    await printBalance(userAddress, "User", chainAddrData.steth, " stETH");
    await printBalance(userAddress, "User", chainAddrData.eeth, "  eETH");
    await printBalance(userAddress, "User", chainAddrData.wsteth, "wstETH");
    await printBalance(userAddress, "User", chainAddrData.weeth, " weETH");
    await printBalance(userAddress, "User", Project.Vault, "VaultToken");
    await printBalance(accounts[4], "user2", Project.Vault, "VaultToken");
    console.log("=======");
    await printETHBalance(accounts[2], "feeReceiver");
    console.log("=======");
    await printETHBalance(Project.Vault, "vault");
    await printBalance(Project.Vault, "vault", chainAddrData.weth, "  wETH");
    await printBalance(Project.Vault, "vault", chainAddrData.steth, " stETH");
    await printBalance(Project.Vault, "vault", chainAddrData.eeth, "  eETH");
    await printBalance(Project.Vault, "vault", chainAddrData.wsteth, "wstETH");
    console.log("=======");

    console.log("=======");
    await printBalance(Project.RedeemOperator, "RedeemOperator", Project.Vault, "VaultToken");
    console.log("=======");
    await printBalance(Project.StrategyAAVEV3, "StrategyAAVEV3", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyAAVEV3, "StrategyAAVEV3", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyAAVEV3, "StrategyAAVEV3", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyAAVEV3, "StrategyAAVEV3", chainAddrData.aavev3awsteth, "awstETH");
    await printBalance(Project.StrategyAAVEV3, "StrategyAAVEV3", chainAddrData.aavev3dweth, "DWETH");
    console.log("=======");
    await printETHBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.eeth, "EETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", chainAddrData.wsteth, "WSTETH");
    await printBalance(Project.StrategyMellowSteakhouse, "StrategyMellowSteakhouse", steakhouseAddr, "lrtETH");
    console.log("=======");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.usdt, "USDT");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.eeth, "EETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.weeth, "weETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.aavev3awsteth, "awstETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.aavev3dweth, "DWETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.aavev3dusdt, "DUSDT");
    console.log("=======");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.usdt, "USDT");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.eeth, "EETH");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyMorphoBlueRSETH, "StrategyMorphoBlueRSETH", rsETHAddr, "rsETH");
    console.log("=======");
    await printBalance(Project.StrategyUniswapV3, "StrategyUniswapV3", chainAddrData.wsteth, "wsteth");
    await printBalance(Project.StrategyUniswapV3, "StrategyUniswapV3", chainAddrData.weth, "WETH");
    console.log("=======");
    console.log("\n==== vault data ====");
    const vaultParams = await Vault.getVaultParams();
    console.log("vaultParams        : ", vaultParams);

    const vaultState = await Vault.getVaultState();
    console.log("vaultState         : ", vaultState);

    const totalSupply = await Vault.totalSupply();
    console.log("totalSupply              : ", ethers.utils.formatEther(totalSupply));

    const exchangePrice = await Vault.exchangePrice();
    console.log("exchangePrice            : ", ethers.utils.formatEther(exchangePrice));

    const revenueExchangePrice = await Vault.revenueExchangePrice();
    console.log("revenueExchangePrice     : ", ethers.utils.formatEther(revenueExchangePrice));

    const revenue = await Vault.revenue();
    console.log("revenue                  : ", ethers.utils.formatEther(revenue));

    const totalAssets = await Vault.totalAssets();
    console.log("totalAssets              : ", ethers.utils.formatEther(totalAssets));

    const underlyingTvl = await Vault.callStatic.underlyingTvl();
    console.log("underlyingTvl            : ", ethers.utils.formatEther(underlyingTvl));

    const convertToShares = await Vault.convertToShares(oneEther);
    console.log("convertToShares          : ", ethers.utils.formatEther(convertToShares));

    const convertToAssets = await Vault.convertToAssets(oneEther);
    console.log("convertToAssets          : ", ethers.utils.formatEther(convertToAssets));
}

async function updateExchangePrice() {
    console.log("\n\n==== updateExchangePrice ====");

    const selector0 = web3.eth.abi.encodeFunctionSignature("updateNetAssets(uint256)");
    const bytes0 = web3.eth.abi.encodeParameters(["uint256"], [oneEther.mul(50)]);

    const selector1 = web3.eth.abi.encodeFunctionSignature("updateExchangePrice()");
    const bytes1 = "0x";

    const addresses = [Project.StrategyHybridWeETH, Project.Vault];
    const bytes = [selector0 + bytes0.substring(2, bytes0.length), selector1 + bytes1.substring(2, bytes1.length)];
    const result = await Manager.connect(kmsOperator).multiCall(addresses, bytes);
    await printGas(result);
    await query();
}

const oldVaultAddress = "0xE7F878F31Fe1C2C2223259685255e45c475B4B8F";
const oldStrategyAddress = "0x59d1695764C2e3404DBb67Adc4ee8e97702D5EDE";
async function getRichList() {
    try {
        const response = await axios.get("https://www.oklink.com/api/v5/explorer/address/rich-list", {
            headers: {
                "Ok-Access-Key": okLinkApikey,
            },
            params: {
                chainShortName: "eth",
                address: oldVaultAddress,
            },
        });

        if (response.data.code === "0") {
            const addresses = response.data.data.map((entry) => entry.address);
            // console.log(addresses);
            return addresses;
        } else {
            console.error("Error:", response.data.msg);
        }
    } catch (error) {
        console.error("Request failed:", error);
    }
}

async function migrateLP() {
    console.log("\n\n==== migrateLP ====");

    const users = await getRichList();
    console.log("users = ", users);
    let userOldLpBalances: BigNumber[] = [];
    let usersNetAssets: BigNumber[] = [];
    const steakVault = await ethers.getContractAt("ERC4626Upgradeable", oldVaultAddress);
    for (var i = 0; i < users.length; i++) {
        const oldLpBalance: BigNumber = await steakVault.balanceOf(users[i]);
        userOldLpBalances.push(oldLpBalance);
        const userNetAssets = await steakVault.previewRedeem(oldLpBalance);
        usersNetAssets.push(userNetAssets);
    }
    console.log("usersNetAssets        = ", usersNetAssets);

    // mint new lp
    const vaultOwner = await impersonateAccount(await Vault.owner());
    await Vault.connect(vaultOwner).migrateMint(users, usersNetAssets);

    console.log("\n\n migrate LP success!!!");

    await query();
}

async function migrateAssets() {
    console.log("\n\n==== migrateAssets ====");

    // transfer assets
    const oldStrategy = await impersonateAccount(oldStrategyAddress);
    const steakLrt = await await ethers.getContractAt("IERC20", steakhouseAddr);
    const stETH = await await ethers.getContractAt("IERC20", chainAddrData.steth);
    await steakLrt
        .connect(oldStrategy)
        .transfer(Project.StrategyMellowSteakhouse, await steakLrt.balanceOf(oldStrategyAddress));
    await stETH
        .connect(oldStrategy)
        .transfer(Project.StrategyMellowSteakhouse, await stETH.balanceOf(oldStrategyAddress));

    console.log("\n\n migrate Assets success!!!");

    await query();
}

const main = async (): Promise<any> => {
    await query();

    await migrateLP();
    await migrateAssets();
    await updateExchangePrice();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
