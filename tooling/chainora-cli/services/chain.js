// @ts-nocheck

import { createPublicClient, createWalletClient, custom, encodeFunctionData, getContractAddress } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { loadArtifact } from "./artifacts.js";
import { ensurePrivateKey, nonEmpty, ZERO_ADDRESS } from "./shared.js";

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{ requireSigner?: boolean }} [options]
 */
export async function ensureClients(session, options = {}) {
  const requireSigner = options.requireSigner ?? false;

  if (!session.publicClient) {
    session.publicClient = createPublicClient({
      transport: custom({
        async request({ method, params }) {
          const response = await fetch(session.rpcUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              id: Date.now(),
              jsonrpc: "2.0",
              method,
              params
            })
          });
          const payload = await response.json();
          if (payload.error) {
            throw new Error(payload.error.message || `RPC error: ${method}`);
          }
          return payload.result;
        }
      })
    });
    session.chainId = await session.publicClient.getChainId();
    session.feeStrategy = await detectFeeStrategy(session.publicClient);
    session.chain = {
      id: Number(session.chainId),
      name: `Chainora-${session.chainId}`,
      nativeCurrency: {
        name: "Gas",
        symbol: "GAS",
        decimals: 18
      },
      rpcUrls: {
        default: {
          http: [session.rpcUrl]
        }
      }
    };
  }

  if (requireSigner && !session.account) {
    let privateKey = session.envStore.getNonEmpty("PRIVATE_KEY");
    if (!privateKey && session.promptPrivateKey) {
      privateKey = nonEmpty(await session.promptPrivateKey());
    }

    const normalizedKey = ensurePrivateKey(privateKey ?? "");
    session.account = privateKeyToAccount(normalizedKey);
    session.walletClient = createWalletClient({
      account: session.account,
      chain: session.chain,
      transport: custom({
        async request({ method, params }) {
          const response = await fetch(session.rpcUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              id: Date.now(),
              jsonrpc: "2.0",
              method,
              params
            })
          });
          const payload = await response.json();
          if (payload.error) {
            throw new Error(payload.error.message || `RPC error: ${method}`);
          }
          return payload.result;
        }
      })
    });
  }

  return {
    publicClient: session.publicClient,
    walletClient: session.walletClient,
    account: session.account,
    chainId: session.chainId,
    feeStrategy: session.feeStrategy
  };
}

/**
 * @param {import("viem").PublicClient} publicClient
 */
export async function detectFeeStrategy(publicClient) {
  const gasPrice = await safely(() => publicClient.getGasPrice());
  const block = await safely(() => publicClient.getBlock());
  const maxPriorityFeePerGas = await safely(async () => {
    const value = await publicClient.request({ method: "eth_maxPriorityFeePerGas" });
    return typeof value === "string" ? BigInt(value) : 0n;
  });

  const baseFeePerGas = block?.baseFeePerGas ?? null;
  const isZeroFee = gasPrice === 0n && (baseFeePerGas === null || baseFeePerGas === 0n) && maxPriorityFeePerGas === 0n;

  if (typeof gasPrice === "bigint") {
    return {
      kind: "legacy",
      gasPrice,
      isZeroFee
    };
  }

  if (typeof baseFeePerGas === "bigint" && typeof maxPriorityFeePerGas === "bigint") {
    return {
      kind: "eip1559",
      maxFeePerGas: baseFeePerGas + maxPriorityFeePerGas,
      maxPriorityFeePerGas,
      isZeroFee
    };
  }

  return {
    kind: "auto",
    isZeroFee: false
  };
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{
 *   artifactName: keyof import("./artifacts.js").ARTIFACTS,
 *   args?: readonly unknown[],
 *   label: string,
 *   nonceOffset?: number
 * }} options
 */
export async function deployArtifact(session, options) {
  const { publicClient, walletClient, account, feeStrategy } = await ensureClients(session, { requireSigner: true });
  if (!walletClient || !account) {
    throw new Error("Không thể khởi tạo signer để deploy.");
  }

  const artifact = await loadArtifact(session.projectRoot, options.artifactName);
  const nonce = await publicClient.getTransactionCount({ address: account.address });
  const predictedAddress = getContractAddress({
    from: account.address,
    nonce: BigInt(nonce) + BigInt(options.nonceOffset ?? 0)
  });

  const feeOverrides = buildFeeOverrides(feeStrategy ?? { kind: "auto" });
  const deployRequest = {
    account,
    chain: session.chain,
    abi: artifact.abi,
    bytecode: artifact.bytecode.object,
    args: options.args ?? [],
    ...feeOverrides
  };

  const estimatedGas = await safely(() => publicClient.estimateContractGas(/** @type {any} */ (deployRequest)));
  if (session.dryRun) {
    return {
      dryRun: true,
      label: options.label,
      predictedAddress,
      estimatedGas,
      artifact
    };
  }

  const hash = await walletClient.deployContract({
    .../** @type {any} */ (deployRequest),
    ...(estimatedGas ? { gas: estimatedGas } : {})
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  return {
    dryRun: false,
    label: options.label,
    contractAddress: receipt.contractAddress ?? predictedAddress,
    receipt,
    hash
  };
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{
 *   address: `0x${string}`,
 *   abi: import("viem").Abi,
 *   functionName: string,
 *   args?: readonly unknown[],
 *   label: string,
 *   value?: bigint
 * }} options
 */
export async function writeContract(session, options) {
  const { publicClient, walletClient, account, feeStrategy } = await ensureClients(session, { requireSigner: true });
  if (!walletClient || !account) {
    throw new Error("Không thể khởi tạo signer để gửi giao dịch.");
  }

  const calldata = encodeFunctionData({
    abi: options.abi,
    functionName: options.functionName,
    args: options.args ?? []
  });

  const request = {
    account,
    chain: session.chain,
    address: options.address,
    abi: options.abi,
    functionName: options.functionName,
    args: options.args ?? [],
    value: options.value ?? 0n,
    ...buildFeeOverrides(feeStrategy)
  };

  const estimatedGas = await safely(() => publicClient.estimateContractGas(/** @type {any} */ (request)));
  if (session.dryRun) {
    return {
      dryRun: true,
      label: options.label,
      calldata,
      estimatedGas
    };
  }

  const hash = await walletClient.writeContract({
    .../** @type {any} */ (request),
    ...(estimatedGas ? { gas: estimatedGas } : {})
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  return {
    dryRun: false,
    label: options.label,
    calldata,
    estimatedGas,
    hash,
    receipt
  };
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {keyof import("./artifacts.js").ARTIFACTS} artifactName
 * @param {`0x${string}`} address
 */
export async function assertContractCode(session, artifactName, address) {
  if (address === ZERO_ADDRESS) {
    throw new Error(`${String(artifactName)}: địa chỉ không được là zero address.`);
  }

  const { publicClient } = await ensureClients(session);
  const bytecode = await publicClient.getBytecode({ address });
  if (!bytecode) {
    throw new Error(`${String(artifactName)}: địa chỉ ${address} chưa có code.`);
  }
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {import("viem").Address} address
 * @param {import("viem").Abi} abi
 * @param {string} functionName
 * @param {readonly unknown[]} [args]
 */
export async function readContract(session, address, abi, functionName, args = []) {
  const { publicClient } = await ensureClients(session);
  return publicClient.readContract({
    address,
    abi,
    functionName: /** @type {any} */ (functionName),
    args: /** @type {any} */ (args)
  });
}

/**
 * @template T
 * @param {() => Promise<T>} callback
 * @returns {Promise<T | undefined>}
 */
async function safely(callback) {
  try {
    return await callback();
  } catch {
    return undefined;
  }
}

/**
 * @param {{ kind: string, gasPrice?: bigint, maxFeePerGas?: bigint, maxPriorityFeePerGas?: bigint }} feeStrategy
 */
function buildFeeOverrides(feeStrategy) {
  if (feeStrategy.kind === "legacy") {
    return { gasPrice: feeStrategy.gasPrice ?? 0n };
  }
  if (feeStrategy.kind === "eip1559") {
    return {
      maxFeePerGas: feeStrategy.maxFeePerGas ?? 0n,
      maxPriorityFeePerGas: feeStrategy.maxPriorityFeePerGas ?? 0n
    };
  }
  return {};
}
