// @ts-check

import fs from "node:fs/promises";
import path from "node:path";

import { isObject } from "./shared.js";

export const ARTIFACTS = {
  ChainoraProtocolTimelock: "out/ChainoraProtocolTimelock.sol/ChainoraProtocolTimelock.json",
  ChainoraProtocolRegistry: "out/ChainoraProtocolRegistry.sol/ChainoraProtocolRegistry.json",
  ChainoraDeviceAdapter: "out/ChainoraDeviceAdapter.sol/ChainoraDeviceAdapter.json",
  ChainoraRoscaFactory: "out/ChainoraRoscaFactory.sol/ChainoraRoscaFactory.json",
  ChainoraRoscaPool: "out/ChainoraRoscaPool.sol/ChainoraRoscaPool.json",
  ChainoraTestUSD: "out/ChainoraTestUSD.sol/ChainoraTestUSD.json"
};

/**
 * @typedef {{
 *   abi: import("viem").Abi,
 *   bytecode: { object: `0x${string}` }
 * }} LoadedArtifact
 */

/**
 * @param {string} projectRoot
 * @param {keyof typeof ARTIFACTS} artifactName
 * @returns {Promise<LoadedArtifact>}
 */
export async function loadArtifact(projectRoot, artifactName) {
  const relativePath = ARTIFACTS[artifactName];
  const absolutePath = path.join(projectRoot, relativePath);

  let raw;
  try {
    raw = await fs.readFile(absolutePath, "utf8");
  } catch {
    throw new Error(`Thiếu artifact ${artifactName}. Hãy chạy \`forge build --sizes\` trước.`);
  }

  /** @type {unknown} */
  const parsed = JSON.parse(raw);
  if (!isObject(parsed) || !Array.isArray(parsed.abi) || !isObject(parsed.bytecode)) {
    throw new Error(`Artifact ${artifactName} không hợp lệ.`);
  }

  const bytecodeObject = parsed.bytecode.object;
  if (typeof bytecodeObject !== "string" || !bytecodeObject.startsWith("0x") || bytecodeObject.length <= 2) {
    throw new Error(`Artifact ${artifactName} thiếu bytecode. Hãy chạy \`forge build --sizes\`.`);
  }

  return {
    abi: /** @type {import("viem").Abi} */ (parsed.abi),
    bytecode: {
      object: /** @type {`0x${string}`} */ (bytecodeObject)
    }
  };
}

