import { readFileSync } from "fs";

export function readJson(path: string): any {
    let data = "{}";
    try {
        data = readFileSync(path, "utf8");
    } finally {
        return JSON.parse(data);
    }
}
