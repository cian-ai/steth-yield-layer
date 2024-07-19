import { config as dotEnvConfig } from "dotenv";
import { readJson } from "./json";

dotEnvConfig();

const basePath: string = "scripts/data/addresses/";
export const chainID: string = String(process.env.CHAIN_ID);

const publicDataPath: string = basePath + "publicData.json";
const tokenAddressPath: string = basePath + chainID + "/address.json";
const rpcPath: string = basePath + chainID + "/rpc.json";
const slotPath: string = basePath + chainID + "/slots.json";

export const publicData: any = readJson(publicDataPath);
export const accounts: string[] = publicData.localAddressesFromPrivatekey;

export const chainAddrData: any = readJson(tokenAddressPath);
export const chainRpcData: any = readJson(rpcPath);
export const chainSlotData: any = readJson(slotPath);
