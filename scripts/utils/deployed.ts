import * as fs from "fs";

try {
    var jsonData = fs.readFileSync("deployments/deployedAddress/deployed.json", "utf8");
} catch (err) {
    var jsonData = "{}";
} finally {
    var info = JSON.parse(jsonData);
}

export const Project = info;
