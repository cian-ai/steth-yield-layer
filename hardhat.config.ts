import { config as dotEnvConfig } from "dotenv";
import "@nomiclabs/hardhat-waffle";
require("@nomiclabs/hardhat-etherscan");
// load .env file
dotEnvConfig();
import { publicData, chainRpcData } from "./scripts/data/tools/constants";

const mnemonic = publicData.mnemonic;
const privateKey = publicData.privateKey;
const LOCAL_RPC_PORT = chainRpcData.LOCAL_RPC_PORT;
const LOCAL_RPC = `http://127.0.0.1:${LOCAL_RPC_PORT}`;
const TEST_RPC = chainRpcData.TEST_RPC;
const SELF_RPC = chainRpcData.SELF_RPC;
const PUBLIC_RPC = chainRpcData.PUBLIC_RPC[1];

// const CURRENT_RPC = TEST_RPC;
const CURRENT_RPC = LOCAL_RPC;
const NETWORK = "localhost";

// const CURRENT_RPC = PUBLIC_RPC;
// const NETWORK = "mainnet";

const GasPrice = 50e9;

const globalGasPrice = {
    gasPrice: GasPrice,
};

export default {
    solidity: {
        compilers: [
            {
                version: "0.8.25",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 100,
                    },
                    evmVersion: "cancun",
                },
            },
        ],
    },
    paths: {
        sources: "./contracts",
        artifacts: "./artifacts",
        tests: "./test",
    },
    defaultNetwork: NETWORK,
    networks: {
        hardhat: {
            gasPrice: GasPrice,
            chainId: 1, //Only specify a chainId if we are not forking
            throwOnTransactionFailures: false,
            throwOnCallFailures: false,
            // accounts: { mnemonic },
            accounts: { privateKey },
            mining: {
                auto: true,
                interval: 10000,
            },
            allowUnlimitedContractSize: true,
            //default 2000ms
            timeout: 1000000,
            hardfork: "cancun",
        },
        localhost: {
            gasPrice: GasPrice,
            gas: 5200000,
            // accounts: { mnemonic },
            accounts: privateKey,
            url: CURRENT_RPC,
            chainId: 1,
            allowUnlimitedContractSize: true,
            timeout: 1000000,
        },
        mainnet: {
            url: CURRENT_RPC,
            gasPrice: GasPrice,
            chainId: 1,
            accounts: privateKey,
        },
    },
    //For code verification
    etherscan: {
        apiKey: chainRpcData.BLOCK_EXPLORER_API_KEY,
    },
};

export { CURRENT_RPC, privateKey, globalGasPrice };
