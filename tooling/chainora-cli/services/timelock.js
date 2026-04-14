// @ts-check

import { encodeAbiParameters, encodeFunctionData, keccak256, parseAbi, zeroHash } from "viem";

import { loadArtifact } from "./artifacts.js";

/**
 * @param {bigint} chainId
 * @param {`0x${string}`} target
 * @param {`0x${string}`} data
 * @param {`0x${string}`} predecessor
 * @param {string} saltLabel
 */
export function buildBaseSalt(chainId, target, data, predecessor, saltLabel) {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "string" },
        { type: "uint256" },
        { type: "address" },
        { type: "bytes" },
        { type: "bytes32" },
        { type: "string" }
      ],
      ["chainora-admin", chainId, target, data, predecessor, saltLabel]
    )
  );
}

/**
 * @param {`0x${string}`} baseSalt
 * @param {number} index
 */
export function buildCandidateSalt(baseSalt, index) {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "uint256" }
      ],
      [baseSalt, BigInt(index)]
    )
  );
}

/**
 * @param {`0x${string}`} target
 * @param {`0x${string}`} data
 * @param {`0x${string}`} predecessor
 * @param {`0x${string}`} salt
 */
export function computeOperationId(target, data, predecessor, salt) {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "uint256" },
        { type: "bytes" },
        { type: "bytes32" },
        { type: "bytes32" }
      ],
      [target, 0n, data, predecessor, salt]
    )
  );
}

/**
 * @param {import("./runtime.js").CliSession} session
 */
export async function getTimelockAbi(session) {
  const artifact = await loadArtifact(session.projectRoot, "ChainoraProtocolTimelock");
  return artifact.abi;
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {`0x${string}`} timelockAddress
 */
export async function getRoleIds(session, timelockAddress) {
  const abi = await getTimelockAbi(session);
  const { readContract } = await import("./chain.js");

  const [proposerRole, executorRole, cancellerRole] = await Promise.all([
    readContract(session, timelockAddress, abi, "PROPOSER_ROLE"),
    readContract(session, timelockAddress, abi, "EXECUTOR_ROLE"),
    readContract(session, timelockAddress, abi, "CANCELLER_ROLE")
  ]);

  return {
    proposerRole: /** @type {`0x${string}`} */ (proposerRole),
    executorRole: /** @type {`0x${string}`} */ (executorRole),
    cancellerRole: /** @type {`0x${string}`} */ (cancellerRole)
  };
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{
 *   timelockAddress: `0x${string}`,
 *   role: `0x${string}`,
 *   accountAddress: `0x${string}`
 * }} options
 */
export async function signerHasRole(session, options) {
  const abi = await getTimelockAbi(session);
  const { readContract } = await import("./chain.js");
  const result = await readContract(session, options.timelockAddress, abi, "hasRole", [
    options.role,
    options.accountAddress
  ]);
  return Boolean(result);
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{
 *   timelockAddress: `0x${string}`,
 *   target: `0x${string}`,
 *   data: `0x${string}`,
 *   predecessor?: `0x${string}`,
 *   saltLabel: string,
 *   maxCandidates?: number
 * }} options
 */
export async function selectScheduleCandidate(session, options) {
  const abi = await getTimelockAbi(session);
  const { readContract } = await import("./chain.js");
  const predecessor = options.predecessor ?? zeroHash;
  const chainId = session.chainId ?? (await (await import("./chain.js")).ensureClients(session)).chainId;
  const baseSalt = buildBaseSalt(BigInt(chainId), options.target, options.data, predecessor, options.saltLabel);
  const maxCandidates = options.maxCandidates ?? 50;

  for (let index = 0; index < maxCandidates; index += 1) {
    const salt = buildCandidateSalt(baseSalt, index);
    const operationId = computeOperationId(options.target, options.data, predecessor, salt);
    const operation = /** @type {[bigint, boolean]} */ (
      await readContract(session, options.timelockAddress, abi, "operations", [operationId])
    );
    const [readyAt, executed] = operation;

    if (readyAt > 0n && !executed) {
      return { kind: "existingPending", salt, operationId, index, readyAt, predecessor, baseSalt };
    }
    if (readyAt === 0n && !executed) {
      return { kind: "new", salt, operationId, index, readyAt, predecessor, baseSalt };
    }
  }

  throw new Error("Không tìm thấy salt trống trong phạm vi dò mặc định.");
}

/**
 * @param {import("./runtime.js").CliSession} session
 * @param {{
 *   timelockAddress: `0x${string}`,
 *   target: `0x${string}`,
 *   data: `0x${string}`,
 *   predecessor?: `0x${string}`,
 *   saltLabel: string,
 *   maxCandidates?: number
 * }} options
 */
export async function selectExecuteCandidate(session, options) {
  const abi = await getTimelockAbi(session);
  const { readContract } = await import("./chain.js");
  const predecessor = options.predecessor ?? zeroHash;
  const chainId = session.chainId ?? (await (await import("./chain.js")).ensureClients(session)).chainId;
  const baseSalt = buildBaseSalt(BigInt(chainId), options.target, options.data, predecessor, options.saltLabel);
  const maxCandidates = options.maxCandidates ?? 50;

  for (let index = 0; index < maxCandidates; index += 1) {
    const salt = buildCandidateSalt(baseSalt, index);
    const operationId = computeOperationId(options.target, options.data, predecessor, salt);
    const operation = /** @type {[bigint, boolean]} */ (
      await readContract(session, options.timelockAddress, abi, "operations", [operationId])
    );
    const [readyAt, executed] = operation;

    if (readyAt > 0n && !executed) {
      return { salt, operationId, index, readyAt, predecessor, baseSalt };
    }
  }

  throw new Error("Không tìm thấy operation pending khớp payload để execute.");
}

export const TIMELOCK_UTILS_ABI = parseAbi([
  "function operations(bytes32) view returns (uint64 readyAt, bool executed)"
]);

/**
 * @param {import("viem").Abi} abi
 * @param {string} functionName
 * @param {readonly unknown[]} args
 */
export function encodeAdminCall(abi, functionName, args) {
  return encodeFunctionData({
    abi,
    functionName,
    args
  });
}
