// @ts-check

import { loadEnvStore } from "./env-store.js";
import { PROJECT_ROOT } from "./shared.js";

/**
 * @typedef {{
 *   projectRoot: string,
 *   envStore: import("./env-store.js").EnvStore,
 *   rpcUrl: string,
 *   dryRun: boolean,
 *   promptPrivateKey?: () => Promise<string>,
 *   publicClient?: import("viem").PublicClient,
 *   walletClient?: import("viem").WalletClient,
 *   account?: import("viem").PrivateKeyAccount,
 *   chainId?: number,
 *   chain?: import("viem").Chain,
 *   lastDeployedAddress?: `0x${string}`,
 *   feeStrategy?: { kind: string, isZeroFee: boolean, gasPrice?: bigint, maxFeePerGas?: bigint, maxPriorityFeePerGas?: bigint }
 * }} CliSession
 */

/**
 * @param {{
 *   rpcUrlOverride?: string,
 *   dryRun?: boolean,
 *   promptPrivateKey?: () => Promise<string>,
 *   envPath?: string
 * }} options
 * @returns {Promise<CliSession>}
 */
export async function createSession(options) {
  const envStore = await loadEnvStore(options.envPath);
  const rpcUrl = options.rpcUrlOverride ?? envStore.getNonEmpty("RPC_URL") ?? envStore.getNonEmpty("ETH_RPC_URL");
  if (!rpcUrl) {
    throw new Error("Thiếu RPC_URL. Hãy thêm RPC_URL vào .env hoặc truyền --rpc-url.");
  }

  return {
    projectRoot: PROJECT_ROOT,
    envStore,
    rpcUrl,
    dryRun: options.dryRun ?? false,
    promptPrivateKey: options.promptPrivateKey
  };
}
