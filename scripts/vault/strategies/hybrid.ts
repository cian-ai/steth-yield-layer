import { ethers } from "hardhat";
import { accounts, chainAddrData, publicData } from "../../data/tools/constants";
import { oneEther, oneUsd } from "../../data/tools/unitconverter";
import { CURRENT_RPC } from "../../../hardhat.config";
import { Project } from "../../utils/deployed";
import { BigNumber } from "ethers";
import { Minter } from "../../data/tools/minter";
import { snapshot, revert } from "../../data/tools/snapshot";
import { getOneInchDataV6 } from "../../data/tools/1inch";
import { impersonateAccount, printETHBalance, printBalance } from "../../data/tools/utils";
const Web3 = require("web3");
const web3 = new Web3(CURRENT_RPC);

const usePrevious = "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe";
const selectors = {
    deposit: 0,
    withdraw: 1,
    borrow: 2,
    repay: 3,
    repayWithRemain: 4,
    swap: 5,
    transferTo: 6,
};
const OneETHHex = "0x0de0b6b3a7640000";
const WeETHSlot = {
    name: "weETH",
    slot: "0x0000000000000000000000000000000000000000000000000000000000000065",
    contract: "solidity",
};

function selectFlashloaner(token: string) {
    if (token.toLowerCase() === chainAddrData.dai.toLowerCase()) {
        return "0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA"; // DAI FlashMinter
    }
    return "0xa958090601E21A82e9873042652e35891D945a8C"; // Balancer ERC3156
}

var Vault;
var StrategyHybridWeETH;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyHybridWeETH = await ethers.getContractAt("StrategyHybridWeETH", Project.StrategyHybridWeETH);
    rebalancer = await StrategyHybridWeETH.rebalancer();

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyHybridWeETH, "StrategyHybridWeETH", chainAddrData.weeth, "weETH");
    console.log("\n==== strategy data ====");
    const getNetAssets = await StrategyHybridWeETH.getNetAssets();
    console.log("getNetAssets                       : ", ethers.utils.formatEther(getNetAssets));
}

async function transferToVault(signer: any, strategyAddress: string, eETHAmount: BigNumber) {
    const eETH = await ethers.getContractAt("IERC20", chainAddrData.eeth);
    const weETH = await ethers.getContractAt("IWeETH", chainAddrData.weeth);
    const StrategyHybridWeETH = await ethers.getContractAt("StrategyHybridWeETH", strategyAddress);
    // const manager = await ethers.getContractAt("Manager", chainAddrData.manager);
    // Convert eETHAmount to WeETH
    const weETHAmount = await weETH.getWeETHByeETH(eETHAmount);
    // call StrategyHybridWeETH.transferToVault
    // const calldata = await StrategyHybridWeETH.interface.encodeFunctionData("transferToVault", [chainAddrData.eeth, weETHAmount]);
    // const addresses = [strategyAddress];
    // const withdrawTx = await manager.connect(signer).multiCall(addresses, [calldata])
    const withdrawTx = await StrategyHybridWeETH.connect(signer).transferToVault(chainAddrData.eeth, weETHAmount);
    console.log(`transferToVault tx: ${withdrawTx.hash}`);
    await withdrawTx.wait();
    return withdrawTx;
}

async function depositToAdapter(
    signer: any,
    strategyAddress: string,
    lendingAdapterAddress: string,
    weethAmount: BigNumber
) {
    console.log("strategyAddress = ", strategyAddress);
    // const manager = await ethers.getContractAt("Manager", multicall);
    const depositTx = await StrategyHybridWeETH.connect(signer).deposit(
        lendingAdapterAddress,
        chainAddrData.weeth,
        weethAmount
    );
    // const calldata = [await StrategyHybridWeETH.interface.encodeFunctionData("deposit", [lendingAdapterAddress, chainAddrData.weeth, weethAmount])];
    // const addresses = [strategyAddress];
    // const depositTx = await manager.connect(signer).multiCall(addresses, [calldata]);
    console.log(`depositToAdapter tx: ${depositTx.hash}`);
    await depositTx.wait();
    return depositTx;
}

async function leverage(
    signer: any,
    strategyAddress: string,
    lendingAdapterAddress: string,
    borrowToken: string,
    borrowAmount: BigNumber,
    minOutWeETH: string,
    swapdata: string
) {
    // Pack Lending Operation
    const StrategyHybridWeETH = await ethers.getContractAt("StrategyHybridWeETH", strategyAddress);
    // const manager = await ethers.getContractAt("Manager", multicall);
    const swapCalldata = await StrategyHybridWeETH.interface.encodeFunctionData("swap", [
        borrowToken,
        chainAddrData.weeth,
        borrowAmount,
        minOutWeETH,
        swapdata,
    ]);
    const swapCalldataPacked = "0x" + swapCalldata.slice(10);
    const swapSelector = selectors.swap;
    const depositCalldata = await StrategyHybridWeETH.interface.encodeFunctionData("deposit", [
        lendingAdapterAddress,
        chainAddrData.weeth,
        usePrevious,
    ]);
    const depositCalldataPacked = "0x" + depositCalldata.slice(10);
    const depositSelector = selectors.deposit;
    const lendingCalldata = await StrategyHybridWeETH.interface.encodeFunctionData("borrow", [
        lendingAdapterAddress,
        borrowToken,
        borrowAmount,
    ]);
    const lendingCalldataPacked = "0x" + lendingCalldata.slice(10);
    const lendingSelector = selectors.borrow;
    // Encode flashloan
    const composedCalldata = await StrategyHybridWeETH.interface.encodeFunctionData("composedCall", [
        [swapSelector, depositSelector, lendingSelector],
        [swapCalldataPacked, depositCalldataPacked, lendingCalldataPacked],
    ]);
    const flashloanTx = await StrategyHybridWeETH.connect(signer).doFlashLoan(
        selectFlashloaner(borrowToken),
        borrowToken,
        borrowAmount,
        "0x" + composedCalldata.slice(10)
    );
    // const flashloanCall = await StrategyHybridWeETH.interface.encodeFunctionData("doFlashLoan", [selectFlashloaner(borrowToken), borrowToken, borrowAmount, composedCalldata]);
    // const addresses = [strategyAddress];
    // const flashloanTx = await manager.connect(signer).multiCall(addresses, [flashloanCall]);
    console.log(`depositToAdapter tx: ${flashloanTx.hash}`);
    await flashloanTx.wait();
    return flashloanTx;
}

async function testTransferToVault() {
    console.log("\n\n==== testTransferToVault ====");
    const signer = await impersonateAccount(rebalancer);
    const eETH = await ethers.getContractAt("IERC20", chainAddrData.eeth);
    const WeETH = await ethers.getContractAt("IWeETH", chainAddrData.weeth);
    // First get vault eETH balance
    const eETHBalance = await eETH.balanceOf(Project.Vault);
    console.log("Vault eETHBalance before: ", ethers.utils.formatEther(eETHBalance));

    const snapshotId = await snapshot();
    // Mint WeETH to StrategyHybridWeETH
    Minter.setBalanceOf(OneETHHex, Project.StrategyHybridWeETH, chainAddrData.weeth, WeETHSlot);
    let strategyWeETHBalance = await WeETH.balanceOf(Project.StrategyHybridWeETH);
    console.log("StrategyHybridWeETH WeETH balance before: ", ethers.utils.formatEther(strategyWeETHBalance));
    // Take snapshot
    await transferToVault(signer, Project.StrategyHybridWeETH, ethers.utils.parseEther("1"));
    const eETHBalanceAfter = await eETH.balanceOf(Project.Vault);
    console.log("Vault eETHBalance after: ", ethers.utils.formatEther(eETHBalanceAfter));
    // Check WeETH balance
    strategyWeETHBalance = await WeETH.balanceOf(Project.StrategyHybridWeETH);
    console.log("StrategyHybridWeETH WeETH balance after: ", ethers.utils.formatEther(strategyWeETHBalance));
    // Check Vault eETH diff
    console.log("Vault eETH diff: ", ethers.utils.formatEther(eETHBalanceAfter.sub(eETHBalance)));
    console.log("Resetting to snapshot");
    await revert(snapshotId);
}

async function testDepositToAdapter() {
    console.log("\n\n==== testDepositToAdapter ====");
    const signer = await impersonateAccount(rebalancer);
    const snapshotId = await snapshot();
    const WeETH = await ethers.getContractAt("IWeETH", chainAddrData.weeth);
    // Mint WeETH to StrategyHybridWeETH
    Minter.setBalanceOf(OneETHHex, Project.StrategyHybridWeETH, chainAddrData.weeth, WeETHSlot);
    let strategyWeETHBalance = await WeETH.balanceOf(Project.StrategyHybridWeETH);
    console.log("StrategyHybridWeETH WeETH balance before: ", ethers.utils.formatEther(strategyWeETHBalance));
    // Deposit WeETH to Adapter
    await depositToAdapter(
        signer,
        Project.StrategyHybridWeETH,
        Project.HybridLongShortAaveAdapter,
        ethers.utils.parseEther("1")
    );
    // Check WeETH balance
    strategyWeETHBalance = await WeETH.balanceOf(Project.StrategyHybridWeETH);
    console.log("StrategyHybridWeETH WeETH balance after: ", ethers.utils.formatEther(strategyWeETHBalance));
    const snapshotProtocol = await StrategyHybridWeETH.callStatic.snapshotProtocol(Project.HybridLongShortAaveAdapter, [
        chainAddrData.weeth,
    ]);
    console.log("In-protocol snapshot amount: ", snapshotProtocol);
    console.log("Resetting to snapshot");
    await revert(snapshotId);
}

async function testLeverage() {
    console.log("\n\n==== testLeverage ====");
    const signer = await impersonateAccount(rebalancer);
    const snapshotId = await snapshot();
    // Mint WeETH to StrategyHybridWeETH
    Minter.setBalanceOf(OneETHHex, Project.StrategyHybridWeETH, chainAddrData.weeth, WeETHSlot);
    await depositToAdapter(
        signer,
        Project.StrategyHybridWeETH,
        Project.HybridLongShortAaveAdapter,
        ethers.utils.parseEther("1")
    );
    // Do leverage: borrow 100 USDC
    const swapData = await getOneInchDataV6(
        chainAddrData.usdc,
        chainAddrData.weeth,
        Project.StrategyHybridWeETH,
        oneUsd.mul(100)
    );
    const swapBytes = swapData[0];
    const swapGetMin = "1";
    await leverage(
        signer,
        Project.StrategyHybridWeETH,
        Project.HybridLongShortAaveAdapter,
        chainAddrData.usdc,
        oneUsd.mul(100),
        swapGetMin,
        swapBytes
    );
    // Take snapshot of protocol
    const snapshotProtocol = await StrategyHybridWeETH.callStatic.snapshotProtocol(Project.HybridLongShortAaveAdapter, [
        chainAddrData.weeth,
        chainAddrData.usdc,
    ]);
    console.log("In-protocol snapshot amount: ", snapshotProtocol);
    console.log("Resetting to snapshot");
    await revert(snapshotId);
}

async function main() {
    await query();

    await testTransferToVault();
    // await testDepositToAdapter();
    // await testLeverage();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
