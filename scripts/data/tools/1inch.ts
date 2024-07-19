import { BigNumber } from "ethers";
import { chainID, publicData } from "./constants";
import fetch from "node-fetch";

const apiBaseUrl = "https://api.1inch.dev/swap/v5.2/" + chainID;
const apiBaseUrlV6 = "https://api.1inch.dev/swap/v6.0/" + chainID;
const headers = { headers: { Authorization: publicData.ONEINCH_KEY, accept: "application/json" } };

async function buildTxForSwap(swapchainData: any): Promise<any> {
    const url: string = apiBaseUrl + "/swap" + "?" + new URLSearchParams(swapchainData).toString();
    console.log("url: ", url);
    // Fetch the swap transaction details from the API
    return fetch(url, headers).then((res) => res.json());
}

async function buildTxForSwapV6(swapchainData: any): Promise<any> {
    const url: string = apiBaseUrlV6 + "/swap" + "?" + new URLSearchParams(swapchainData).toString();
    console.log("url: ", url);
    // Fetch the swap transaction details from the API
    return fetch(url, headers).then((res) => res.json());
}

export async function getOneInchData(
    fromToken: string,
    toToken: string,
    operator: string,
    fromAmount: BigNumber,
    protocol: string = ""
): Promise<string[]> {
    if (fromAmount.isZero()) return ["0x", "0"];
    const swapchainData = {
        src: fromToken,
        dst: toToken,
        amount: fromAmount,
        from: operator,
        slippage: 5,
        disableEstimate: true,
        protocols: protocol,
    };
    const swapData: any = await buildTxForSwap(swapchainData);
    console.log("swapData: ", swapData);
    return [swapData.tx.data, swapData.toAmount];
}

export async function getOneInchDataV6(
    fromToken: string,
    toToken: string,
    operator: string,
    fromAmount: BigNumber,
    protocol: string = ""
): Promise<string[]> {
    if (fromAmount.isZero()) return ["0x", "0"];
    const swapchainData = {
        src: fromToken,
        dst: toToken,
        amount: fromAmount,
        from: operator,
        slippage: 5,
        disableEstimate: true,
        protocols: protocol,
    };
    const swapData: any = await buildTxForSwapV6(swapchainData);
    console.log("swapData: ", swapData);
    return [swapData.tx.data, swapData.toAmount];
}
