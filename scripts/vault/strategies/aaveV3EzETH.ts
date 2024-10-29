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
var StrategyAAVEV3EzETH;
var AaveV3FlashLeverageHelper;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyAAVEV3EzETH = await ethers.getContractAt("StrategyAAVEV3EzETH", Project.StrategyAAVEV3EzETH);
    rebalancer = await impersonateAccount(await StrategyAAVEV3EzETH.rebalancer());
    AaveV3FlashLeverageHelper = await ethers.getContractAt("AaveV3FlashLeverageHelper", Project.AaveV3FlashLeverageHelper);

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printBalance(Project.StrategyAAVEV3EzETH, "StrategyAAVEV3EzETH", chainAddrData.weth, "WETH");
    await printBalance(Project.StrategyAAVEV3EzETH, "StrategyAAVEV3EzETH", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyAAVEV3EzETH, "StrategyAAVEV3EzETH", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyAAVEV3EzETH, "StrategyAAVEV3EzETH", chainAddrData.aavev3awsteth, "awstETH");
    await printBalance(Project.StrategyAAVEV3EzETH, "StrategyAAVEV3EzETH", chainAddrData.aavev3dweth, "DWETH");
    console.log("\n==== strategy data ====");
    // const getRatio = await StrategyAAVEV3EzETH.getRatio();
    // console.log("getRatio                        : ", ethers.utils.formatEther(getRatio));
    // const getCollateralRatio = await StrategyAAVEV3EzETH.getCollateralRatio();
    // console.log("getCollateralRatio              : ", ethers.utils.formatEther(getCollateralRatio[0]));
    // const getNetAssets = await StrategyAAVEV3EzETH.getNetAssets();
    // console.log("getNetAssets                    : ", ethers.utils.formatEther(getNetAssets));
    // const getAvailableBorrowsETH = await StrategyAAVEV3EzETH.getAvailableBorrowsWSTETH();
    // console.log("getAvailableBorrowsETH          : ", ethers.utils.formatEther(getAvailableBorrowsETH));
    // const getAvailableWithdrawsStETH = await StrategyAAVEV3EzETH.getAvailableWithdrawsEzETH();
    // console.log("getAvailableWithdrawsStETH      : ", ethers.utils.formatEther(getAvailableWithdrawsStETH));
    // const getProtocolAccountData = await StrategyAAVEV3EzETH.getProtocolAccountData();
    // console.log("getProtocolAccountData[0]       : ", ethers.utils.formatEther(getProtocolAccountData[0]));
    // console.log("getProtocolAccountData[1]       : ", ethers.utils.formatEther(getProtocolAccountData[1]));
    // const getProtocolNetAssets = await StrategyAAVEV3EzETH.getProtocolNetAssets();
    // console.log("getProtocolNetAssets            : ", ethers.utils.formatEther(getProtocolNetAssets));
    // const getLeverageAmount = await StrategyAAVEV3EzETH.getLeverageAmount(true, oneEther);
    // console.log("getLeverageAmount               : ", getLeverageAmount);
}

async function testConvert() {
    console.log("\n\n==== testConvert ====");
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("snapshotId : ", snapshotId);
    let rebalancer = await impersonateAccount(await StrategyAAVEV3EzETH.rebalancer());
    // Read the current protocol net value
    const getNetAssets = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getProtocolNetAssets            : ", ethers.utils.formatEther(getNetAssets));
    // Call convertFromEzETH
    let convertTx = await StrategyAAVEV3EzETH.connect(rebalancer).convertFromEzETH(oneEther, 0, "0x");
    await convertTx.wait();
    console.log("convertFromEzETH tx hash        : ", convertTx.hash);
    // Read the current protocol net value
    const getNetAssetsAfter = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getProtocolNetAssetsAfter       : ", ethers.utils.formatEther(getNetAssetsAfter));
    // Require diff is less than 1%
    const diff = getNetAssets.sub(getNetAssetsAfter);
    console.log("diff                            : ", ethers.utils.formatEther(diff));
    if (diff.gt(2)) {
        console.log("diff is greater than 1%");
    }
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function testClaim() {
    console.log("\n\n==== testClaim ====");
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("snapshotId : ", snapshotId);
    let rebalancer = await impersonateAccount(await StrategyAAVEV3EzETH.rebalancer());
    // Force set cooldown period to 0
    const cooldownPeriodSlot = "0x000000000000000000000000000000000000000000000000000000000000009b";
    const cooldownNewValue = "0x0000000000000000000000000000000000000000000000000000000000000001";
    // Call convertFromEzETHconst getProtocolNetAssets = await StrategyAAVEV3EzETH.getProtocolNetAssets();
    const getProtocolNetAssets = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getProtocolNetAssets            : ", ethers.utils.formatEther(getProtocolNetAssets));
    // Call convertFromEzETH
    let tx = await StrategyAAVEV3EzETH.connect(rebalancer).convertFromEzETH(oneEther, 0, "0x");
    await tx.wait();
    // Force set cooldown period to 0
    await ethers.provider.send("hardhat_setStorageAt", ["0x5efc9D10E42FB517456f4ac41EB5e2eBe42C8918", cooldownPeriodSlot, cooldownNewValue]);
    // Sleep for 3 seconds
    console.log("Sleep for 3 seconds");
    await new Promise((r) => setTimeout(r, 3000));
    // Call evm_mine
    await ethers.provider.send("evm_mine", []);
    // Call claim
    let claimTx = await StrategyAAVEV3EzETH.connect(rebalancer).claimExited();
    await claimTx.wait();
    console.log("claimExited tx hash             : ", claimTx.hash);
    // Read the current protocol net value
    const getProtocolNetAssetsAfter = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getProtocolNetAssetsAfter       : ", ethers.utils.formatEther(getProtocolNetAssetsAfter));
    // Require diff is less than 2
    const diff = getProtocolNetAssets.sub(getProtocolNetAssetsAfter);
    console.log("diff                            : ", ethers.utils.formatEther(diff));
    if (diff.gt(2)) {
        console.log("diff is greater than 2");
    }
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function transferRebalancerToFlashLeverage() {
    let owner = await StrategyAAVEV3EzETH.owner();
    let ownerSigner = await impersonateAccount(owner);
    let transferTx = await StrategyAAVEV3EzETH.connect(ownerSigner).updateRebalancer(AaveV3FlashLeverageHelper.address);
    await transferTx.wait();
    /// Print tx
    console.log("Transfer rebalancer to flash leverage helpers tx hash: ", transferTx.hash);
    console.log("Transfer rebalancer to flash leverage helpers successfully");
}

async function leverageWithHelper() {
    // Snapshot
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("\n\n==== leverageWithHelper ====");
    // Get Net Assets
    const getNetAssets = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getNetAssets: ", ethers.utils.formatEther(getNetAssets));
    const owner = await AaveV3FlashLeverageHelper.owner();
    const ownerSigner = await impersonateAccount(owner);
    let tx = await AaveV3FlashLeverageHelper.connect(ownerSigner).leverageMaxium({ gasLimit: 10000000 });
    await tx.wait();
    const getNetAssetsAfter = await StrategyAAVEV3EzETH.getNetAssets();
    console.log("getNetAssetsAfter: ", ethers.utils.formatEther(getNetAssetsAfter));
    // Get Ratio
    const getRate = await StrategyAAVEV3EzETH.getRatio();
    // Print Rate
    console.log("getRate: ", ethers.utils.formatEther(getRate));
    // await printGas(tx);
    // await query();
    // Revert
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function leverageWithHelperWithPartialDepositCap() {
    // Snapshot
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    const owner = await AaveV3FlashLeverageHelper.owner();
    const ownerSigner = await impersonateAccount(owner);
    // Set ezETH deposit cap to 60ETH
    /// Call hardhat_setStorageAt
    let pool = "0x4e033931ad43597d96D6bcc25c280717730B58B1";
    let ezETHConfigSlotId = "0x6c3847a02c991876166c8be676e3ca84a3c105eb60433934c4091c1a7cd316ee";
    let slotAfterModification = "0x100000000000000000000003e800000003c00000006405dc011229fe000a0005";
    await ethers.provider.send("hardhat_setStorageAt", [pool, ezETHConfigSlotId, slotAfterModification]);
    let tx = await AaveV3FlashLeverageHelper.connect(ownerSigner).leverageMaxium();
    await printGas(tx);
    // Get Rate
    const getRate = await StrategyAAVEV3EzETH.getRatio();
    // Print Rate
    console.log("getRate: ", ethers.utils.formatEther(getRate));
    // Revert
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function leverageWithHelperWithPartialBorrowCap() {
    /// Snapshot
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    const owner = await AaveV3FlashLeverageHelper.owner();
    const ownerSigner = await impersonateAccount(owner);
    // Set ezETH deposit cap to 115ETH
    /// Call hardhat_setStorageAt
    let pool = "0x4e033931ad43597d96D6bcc25c280717730B58B1";
    let wstETHConfigSlotId = "0xc9d7ec48cd0d839522455f78914adfeda8686316bb6819e0888e4bcd349e01b2";
    let slotAfterModification = "0x100000000000000000000103e800009eb1000000007301f4851229681fa41f40";
    await ethers.provider.send("hardhat_setStorageAt", [pool, wstETHConfigSlotId, slotAfterModification]);
    let tx = await AaveV3FlashLeverageHelper.connect(ownerSigner).leverageMaxium();
    await printGas(tx);
    // Get Rate
    const getRate = await StrategyAAVEV3EzETH.getRatio();
    // Print Rate
    console.log("getRate: ", ethers.utils.formatEther(getRate));
    // Revert
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function leverageWithHelperWithLackingCap() {
    let snapshotId = await ethers.provider.send("evm_snapshot", []);
    const owner = await AaveV3FlashLeverageHelper.owner();
    const ownerSigner = await impersonateAccount(owner);
    // Set ezETH deposit cap to 15ETH
    /// Call hardhat_setStorageAt
    let pool = "0x4e033931ad43597d96D6bcc25c280717730B58B1";
    let ezETHConfigSlotId = "0x6c3847a02c991876166c8be676e3ca84a3c105eb60433934c4091c1a7cd316ee";
    let slotAfterModification = "0x100000000000000000000003e800000000800000006405dc011229fe000a0005";
    await ethers.provider.send("hardhat_setStorageAt", [pool, ezETHConfigSlotId, slotAfterModification]);
    let tx = await AaveV3FlashLeverageHelper.connect(ownerSigner).leverageMaxium();
    await printGas(tx);
    // Get Rate
    const getRate = await StrategyAAVEV3EzETH.getRatio();
    // Print Rate
    console.log("getRate: ", ethers.utils.formatEther(getRate));
    // Revert
    await ethers.provider.send("evm_revert", [snapshotId]);
}

async function main() {
    await query();
    await testConvert();
    await testClaim();
    await transferRebalancerToFlashLeverage();
    await leverageWithHelper();
    await leverageWithHelperWithPartialDepositCap();
    await leverageWithHelperWithPartialBorrowCap();
    await leverageWithHelperWithLackingCap();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
