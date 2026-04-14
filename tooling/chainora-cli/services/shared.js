// @ts-check

import path from "node:path";
import { fileURLToPath } from "node:url";
import { isAddress, zeroAddress, zeroHash } from "viem";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const PROJECT_ROOT = path.resolve(__dirname, "../../..");
export const DEFAULT_ENV_PATH = path.join(PROJECT_ROOT, ".env");
export const ZERO_ADDRESS = zeroAddress;
export const ZERO_HASH = zeroHash;

/**
 * @param {unknown} condition
 * @param {string} message
 */
export function invariant(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

/**
 * @param {string | undefined | null} value
 * @returns {string | undefined}
 */
export function nonEmpty(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

/**
 * @param {string | undefined | null} value
 * @param {string} label
 * @returns {`0x${string}`}
 */
export function ensureAddress(value, label) {
  const candidate = nonEmpty(value);
  if (!candidate || !isAddress(candidate)) {
    throw new Error(`${label} không phải là địa chỉ EVM hợp lệ.`);
  }
  return /** @type {`0x${string}`} */ (candidate);
}

/**
 * @param {string | undefined | null} value
 * @param {string} label
 * @returns {`0x${string}` | undefined}
 */
export function ensureOptionalAddress(value, label) {
  const candidate = nonEmpty(value);
  if (!candidate) return undefined;
  if (!isAddress(candidate)) {
    throw new Error(`${label} không phải là địa chỉ EVM hợp lệ.`);
  }
  return /** @type {`0x${string}`} */ (candidate);
}

/**
 * @param {string | undefined | null} value
 * @param {string} label
 * @returns {bigint}
 */
export function ensureBigInt(value, label) {
  const candidate = nonEmpty(value);
  if (!candidate) {
    throw new Error(`${label} không được để trống.`);
  }

  try {
    return BigInt(candidate);
  } catch {
    throw new Error(`${label} phải là số nguyên hợp lệ.`);
  }
}

/**
 * @param {string | undefined | null} value
 * @param {string} label
 * @returns {number}
 */
export function ensureNumber(value, label) {
  const asBigInt = ensureBigInt(value, label);
  const asNumber = Number(asBigInt);
  if (!Number.isSafeInteger(asNumber)) {
    throw new Error(`${label} vượt quá giới hạn số an toàn.`);
  }
  return asNumber;
}

/**
 * @param {string | undefined | null} value
 * @returns {boolean | undefined}
 */
export function parseOptionalBoolean(value) {
  const candidate = nonEmpty(value)?.toLowerCase();
  if (!candidate) return undefined;
  if (candidate === "true") return true;
  if (candidate === "false") return false;
  throw new Error(`Giá trị boolean không hợp lệ: ${value}`);
}

/**
 * @param {string | undefined | null} value
 * @returns {`0x${string}`[]}
 */
export function parseAddressList(value) {
  const candidate = nonEmpty(value);
  if (!candidate) return [];

  return candidate.split(",").map((entry, index) => {
    const trimmed = entry.trim();
    if (!isAddress(trimmed)) {
      throw new Error(`Danh sách địa chỉ không hợp lệ tại vị trí ${index + 1}: ${trimmed}`);
    }
    return /** @type {`0x${string}`} */ (trimmed);
  });
}

/**
 * @param {`0x${string}`[]} values
 * @returns {string}
 */
export function stringifyAddressList(values) {
  return values.join(",");
}

/**
 * @param {string} value
 * @returns {`0x${string}`}
 */
export function ensurePrivateKey(value) {
  const candidate = nonEmpty(value);
  if (!candidate || !/^0x[0-9a-fA-F]{64}$/.test(candidate)) {
    throw new Error("PRIVATE_KEY phải là hex 32-byte dạng 0x...");
  }
  return /** @type {`0x${string}`} */ (candidate);
}

/**
 * @param {unknown} value
 * @returns {value is Record<string, unknown>}
 */
export function isObject(value) {
  return typeof value === "object" && value !== null;
}

