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
var StrategyUniswapV3;
var rebalancer;
var User;

async function query() {
    var userAddress = accounts[0];
    User = (await ethers.getSigners())[0];
    console.log(Project);

    Vault = await ethers.getContractAt("VaultYieldETH", Project.Vault);
    StrategyUniswapV3 = await ethers.getContractAt("StrategyUniswapV3", Project.StrategyUniswapV3);
    rebalancer = await impersonateAccount(await StrategyUniswapV3.rebalancer());

    await printETHBalance(userAddress, "User");
    console.log("=======");
    await printETHBalance(Project.StrategyUniswapV3, "StrategyUniswapV3");
    await printBalance(Project.StrategyUniswapV3, "StrategyUniswapV3", chainAddrData.steth, "stETH");
    await printBalance(Project.StrategyUniswapV3, "StrategyUniswapV3", chainAddrData.wsteth, "wstETH");
    await printBalance(Project.StrategyUniswapV3, "StrategyUniswapV3", chainAddrData.weth, "WETH");
    console.log("\n==== strategy data ====");
    const getPosition = await StrategyUniswapV3.getPosition();
    console.log("getPosition : ", getPosition);
    console.log("\n========================");
    const getPositionAmounts = await StrategyUniswapV3.getPositionAmounts();
    console.log("getPositionAmounts : ", getPositionAmounts);
    const getProtocolNetAssets = await StrategyUniswapV3.callStatic.getProtocolNetAssets();
    console.log("getProtocolNetAssets               : ", ethers.utils.formatEther(getProtocolNetAssets));
    const getNetAssets = await StrategyUniswapV3.callStatic.getNetAssets();
    console.log("getNetAssets                       : ", ethers.utils.formatEther(getNetAssets));
}

async function mintNFT() {
    console.log("\n\n==== mintNFT ====");

    const token0_ = chainAddrData.wsteth;
    const token1_ = chainAddrData.weth;
    const fee_ = 100;
    const tickLower_ = 1594;
    const tickUpper_ = 1598;
    const amount0Desired_ = oneEther.mul(10);
    const amount1Desired_ = oneEther.mul(10);
    const amount0Min_ = 0;
    const amount1Min_ = 0;
    const recipient_ = Project.StrategyUniswapV3;
    const deadline_ = 1728861975;
    const mintParams = {
        token0: token0_,
        token1: token1_,
        fee: fee_,
        tickLower: tickLower_,
        tickUpper: tickUpper_,
        amount0Desired: amount0Desired_,
        amount1Desired: amount1Desired_,
        amount0Min: amount0Min_,
        amount1Min: amount1Min_,
        recipient: recipient_,
        deadline: deadline_,
    };

    const result = await StrategyUniswapV3.connect(rebalancer).mint(mintParams);
    await query();
}

async function increaseLiquidity() {
    console.log("\n\n==== increaseLiquidity ====");

    const tokenId_ = await StrategyUniswapV3.tokenId();
    const amount0Desired_ = oneEther.mul(5);
    const amount1Desired_ = oneEther.mul(5);
    const amount0Min_ = 0;
    const amount1Min_ = 0;
    const deadline_ = 1728861975;

    const increaseParams = {
        tokenId: tokenId_,
        amount0Desired: amount0Desired_,
        amount1Desired: amount1Desired_,
        amount0Min: amount0Min_,
        amount1Min: amount1Min_,
        deadline: deadline_,
    };

    const result = await StrategyUniswapV3.connect(rebalancer).increaseLiquidity(increaseParams);
    await query();
}

async function decreaseLiquidity() {
    console.log("\n\n==== decreaseLiquidity ====");

    const tokenId_ = await StrategyUniswapV3.tokenId();
    const getPosition = await StrategyUniswapV3.getPosition();
    const liquidity_ = getPosition.liquidity.div(2);
    const deadline_ = 1728861975;
    const amount0Min_ = 0;
    const amount1Min_ = 0;

    const decreaseParams = {
        tokenId: tokenId_,
        liquidity: liquidity_,
        amount0Min: amount0Min_,
        amount1Min: amount1Min_,
        deadline: deadline_,
    };

    const result = await StrategyUniswapV3.connect(rebalancer).decreaseLiquidity(decreaseParams);
    await query();
}

async function clearLiquidity() {
    console.log("\n\n==== decreaseLiquidity ====");

    const tokenId_ = await StrategyUniswapV3.tokenId();
    const getPosition = await StrategyUniswapV3.getPosition();
    const liquidity_ = getPosition.liquidity;
    const deadline_ = 1728861975;
    const amount0Min_ = 0;
    const amount1Min_ = 0;

    const decreaseParams = {
        tokenId: tokenId_,
        liquidity: liquidity_,
        amount0Min: amount0Min_,
        amount1Min: amount1Min_,
        deadline: deadline_,
    };

    const result = await StrategyUniswapV3.connect(rebalancer).decreaseLiquidity(decreaseParams);
    await query();
}

async function burn() {
    console.log("\n\n==== burn ====");

    const result = await StrategyUniswapV3.connect(rebalancer).burn();
    await query();
}

const main = async (): Promise<any> => {
    await query();

    await mintNFT();
    // await increaseLiquidity();
    // await decreaseLiquidity();
    await clearLiquidity();
    await burn();
};

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
