import { ethers } from "hardhat";
import { accounts, chainAddrData, publicData } from "../data/tools/constants";
import { oneEther, fullAmount } from "../data/tools/unitconverter";
import { Project } from "../utils/deployed";
import { config as dotEnvConfig } from "dotenv";
import { CURRENT_RPC } from "../../hardhat.config";
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);
import { impersonateAccount, printETHBalance, setETH, printBalance, getBalance, printGas } from "../data/tools/utils";
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

async function query() {
    const steakhouseAddr = "0xBEEF69Ac7870777598A04B2bd4771c71212E6aBc";
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
    const A_WSTETH_AAVEV3_LIDO = "0xC035a7cf15375cE2706766804551791aD035E0C2";
    const D_WETH_AAVEV3_LIDO = "0x91b7d78BF92db564221f6B5AeE744D1727d1Dd1e";
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", A_WSTETH_AAVEV3_LIDO, "awstETH");
    await printBalance(Project.StrategyAAVEV3LIDO, "StrategyAAVEV3LIDO", D_WETH_AAVEV3_LIDO, "DWETH");
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

    const pendingWithdrawersCount = await RedeemOperator.pendingWithdrawersCount();
    console.log("pendingWithdrawersCount  : ", pendingWithdrawersCount);

    const withdrawalRequest = await RedeemOperator.withdrawalRequest(userAddress);
    console.log("withdrawalRequest        : ", withdrawalRequest);

    const allPendingWithdrawers = await RedeemOperator.allPendingWithdrawers();
    console.log("allPendingWithdrawers    : ", allPendingWithdrawers);
}

async function mintToken() {
    console.log("\n\n==== mintToken ====");
    const STETH = await ethers.getContractAt("IstETH", chainAddrData.steth);
    const amount = oneEther.mul(1000);
    await STETH.submit(chainAddrData.steth, { value: amount });
    await STETH.approve(chainAddrData.wsteth, fullAmount);
    const wstETH = await ethers.getContractAt("IWstETH", chainAddrData.wsteth);
    await wstETH.wrap(amount.div(2));
    const eETHPool = await ethers.getContractAt("ILiquidityPool", "0x308861A430be4cce5502d0A12724771Fc6DaF216");
    await eETHPool.deposit({ value: amount });
    const eETH = await ethers.getContractAt("IERC20", chainAddrData.eeth);
    await eETH.approve(chainAddrData.weeth, fullAmount);
    const weETH = await ethers.getContractAt("IWeETH", chainAddrData.weeth);
    await weETH.wrap(amount.div(2));
    await query();
}

async function updateExchangePrice() {
    console.log("\n\n==== updateExchangePrice ====");

    // const result = await Vault.connect(kmsOperator).updateExchangePrice({ gasLimit: 5000000 });
    // const newExchangePrice = await Vault.exchangePrice();
    // console.log("newExchangePrice = ", newExchangePrice);
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

async function depositWETH() {
    console.log("\n\n==== depositWETH ====");

    const wethAmount = oneEther.mul(150);
    const WETH = await ethers.getContractAt("IERC20", chainAddrData.weth);
    await WETH.connect(User).approve(Project.Vault, fullAmount);
    // const result = await Vault.connect(User).deposit(wethAmount, User.address);
    const result = await Vault.connect(User).optionalDeposit(
        chainAddrData.weth,
        wethAmount,
        User.address,
        publicData.zero
    );

    await printGas(result);

    await query();
}

async function depositETH() {
    console.log("\n\n==== depositETH ====");

    const ethAmount = oneEther.mul(160);
    const result = await Vault.connect(User).optionalDeposit(publicData.eth, 0, User.address, publicData.zero, {
        value: ethAmount,
    });

    await printGas(result);
    await query();
}

async function depositSTETH() {
    console.log("\n\n==== depositSTETH ====");

    const stETH = await ethers.getContractAt("IERC20", chainAddrData.steth);
    await stETH.connect(User).approve(Project.Vault, fullAmount);
    const stETHAmount = oneEther.mul(300);
    const result = await Vault.connect(User).optionalDeposit(
        chainAddrData.steth,
        stETHAmount,
        User.address,
        publicData.zero
    );

    await printGas(result);
    await query();
}

async function depositEETH() {
    console.log("\n\n==== depositEETH ====");

    const eETH = await ethers.getContractAt("IERC20", chainAddrData.eeth);
    await eETH.connect(User).approve(Project.Vault, fullAmount);
    const eETHAmount = oneEther.mul(100);
    const result = await Vault.connect(User).optionalDeposit(
        chainAddrData.eeth,
        eETHAmount,
        User.address,
        publicData.zero
    );

    await printGas(result);
    await query();
}

async function depositWstETH() {
    console.log("\n\n==== depositWstETH ====");

    const wstETH = await ethers.getContractAt("IERC20", chainAddrData.wsteth);
    await wstETH.approve(Project.Vault, fullAmount);
    const wstETHAmount = oneEther.mul(100);
    const result = await Vault.connect(User).optionalDeposit(
        chainAddrData.wsteth,
        wstETHAmount,
        User.address,
        publicData.zero
    );

    await printGas(result);
    await query();
}

async function depositWeETH() {
    console.log("\n\n==== depositWeETH ====");

    const weETH = await ethers.getContractAt("IERC20", chainAddrData.weeth);
    await weETH.approve(Project.Vault, fullAmount);
    const weETHAmount = oneEther.mul(100);
    const result = await Vault.connect(User).optionalDeposit(
        chainAddrData.weeth,
        weETHAmount,
        User.address,
        publicData.zero
    );

    await printGas(result);
    await query();
}

async function transferToStrategy() {
    console.log("\n\n==== transferToStrategy ====");

    const MultiSig = await impersonateAccount(Project.MultiSig);
    const amount = oneEther.mul(50);
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 0); // strategy 0
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 1); // StrategyAAVEV3
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 2); // StrategyAAVEV3LIDO
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 3); // StrategyMellowSteakhouse
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.eeth, amount, 4); // StrategyHybridWeETH
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 5); // StrategyMorphoBlueRSETH
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.steth, amount, 6); // StrategyUniswapV3
    await Vault.connect(MultiSig).transferToStrategy(chainAddrData.weth, amount, 6); // StrategyUniswapV3

    await query();
}

async function requestRedeem() {
    console.log("\n\n==== requestRedeem  ====");

    const sharesAmount = oneEther.mul(10);
    const result = await Vault.connect(User).requestRedeem(sharesAmount, chainAddrData.steth);
    await printGas(result);
    await query();
}

async function confirmWithdrawalSTETH() {
    console.log("\n\n==== confirmWithdrawalSTETH ====");

    const stEthUsers = [accounts[0]];
    const eEthUsers = [];
    const gas = 10000;
    const result = await RedeemOperator.connect(managerContract).confirmWithdrawal(stEthUsers, eEthUsers, gas);
    await printGas(result);
    await query();
}

async function multicall() {
    console.log("\n\n==== multicall ====");

    const selector0 = web3.eth.abi.encodeFunctionSignature("updateNetAssets(uint256)");
    // const bytes0 = web3.eth.abi.encodeParameters(["uint256"], [oneEther.mul(50)]);
    const bytes0 = web3.eth.abi.encodeParameters(["uint256"], [oneEther.mul(50).mul(999).div(1000)]);

    const selector1 = web3.eth.abi.encodeFunctionSignature("transferToVault(address,uint256)");
    const bytes1 = web3.eth.abi.encodeParameters(["address", "uint256"], [chainAddrData.steth, oneEther]);

    const selector2 = web3.eth.abi.encodeFunctionSignature("updateExchangePrice()");
    const bytes2 = "0x";

    const selector3 = web3.eth.abi.encodeFunctionSignature("confirmWithdrawal(address[],address[],uint256)");
    const bytes3 = await web3.eth.abi.encodeParameters(["address[]", "address[]", "uint256"], [[accounts[0]], [], 0]);

    const addresses = [
        Project.StrategyHybridWeETH,
        Project.StrategyAAVEV3,
        Project.Vault,
        Project.RedeemOperator,
        Project.Vault,
    ];
    const bytes = [
        selector0 + bytes0.substring(2, bytes0.length),
        selector1 + bytes1.substring(2, bytes1.length),
        selector2 + bytes2.substring(2, bytes2.length),
        selector3 + bytes3.substring(2, bytes3.length),
        selector2 + bytes2.substring(2, bytes2.length),
    ];
    const result = await Manager.connect(kmsOperator).multiCall(addresses, bytes);
    await printGas(result);
    await query();
}

async function collectManagementFee() {
    console.log("\n\n==== collectManagementFee ====");

    await Vault.connect(kmsOperator).collectManagementFee();

    await query();
}

const main = async (): Promise<any> => {
    await query();
    await mintToken();

    await depositWETH();
    await depositETH();
    await depositSTETH();
    await depositEETH();
    await depositWstETH();
    await depositWeETH();
    await transferToStrategy();
    await updateExchangePrice();

    // await requestRedeem();
    // await multicall();
    // await confirmWithdrawalSTETH();

    // await collectManagementFee();
    // await collectRevenue();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
