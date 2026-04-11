// @ts-check

import { confirm, input, password, select } from "@inquirer/prompts";
import { isAddress } from "viem";

import { ZERO_ADDRESS, ZERO_HASH } from "../services/shared.js";

/**
 * @template T
 * @param {{
 *   message: string,
 *   choices: { name: string, value: T }[]
 * }} options
 * @returns {Promise<T>}
 */
export function choose(options) {
  return select(options);
}

/**
 * @param {{
 *   message: string,
 *   defaultValue?: string,
 *   allowEmpty?: boolean
 * }} options
 */
export function promptText(options) {
  return input({
    message: options.message,
    default: options.defaultValue,
    validate(value) {
      if (options.allowEmpty || value.trim().length > 0) return true;
      return "Không được để trống.";
    }
  });
}

/**
 * @param {{
 *   message: string,
 *   defaultValue?: string,
 *   allowZero?: boolean,
 *   allowEmpty?: boolean
 * }} options
 */
export function promptAddress(options) {
  return input({
    message: options.message,
    default: options.defaultValue,
    validate(value) {
      const trimmed = value.trim();
      if (options.allowEmpty && trimmed.length === 0) return true;
      if (!isAddress(trimmed)) return "Đây không phải địa chỉ EVM hợp lệ.";
      if (!options.allowZero && trimmed === ZERO_ADDRESS) return "Zero address không được phép ở đây.";
      return true;
    }
  });
}

/**
 * @param {{
 *   message: string,
 *   defaultValue?: string
 * }} options
 */
export function promptAddressList(options) {
  return input({
    message: options.message,
    default: options.defaultValue,
    validate(value) {
      const trimmed = value.trim();
      if (trimmed.length === 0) return true;

      for (const item of trimmed.split(",")) {
        const candidate = item.trim();
        if (!isAddress(candidate)) {
          return `Địa chỉ không hợp lệ: ${candidate}`;
        }
      }

      return true;
    }
  });
}

/**
 * @param {{
 *   message: string,
 *   defaultValue?: string,
 *   min?: bigint
 * }} options
 */
export function promptInteger(options) {
  return input({
    message: options.message,
    default: options.defaultValue,
    validate(value) {
      const trimmed = value.trim();
      if (trimmed.length === 0) return "Không được để trống.";

      try {
        const parsed = BigInt(trimmed);
        if (options.min !== undefined && parsed < options.min) {
          return `Giá trị phải >= ${options.min.toString()}.`;
        }
        return true;
      } catch {
        return "Phải là số nguyên hợp lệ.";
      }
    }
  });
}

/**
 * @param {{
 *   message: string,
 *   defaultValue?: boolean
 * }} options
 */
export function promptBoolean(options) {
  return confirm({
    message: options.message,
    default: options.defaultValue ?? false
  });
}

/**
 * @param {string} message
 */
export function promptPrivateKey(message) {
  return password({
    message,
    mask: "*",
    validate(value) {
      if (/^0x[0-9a-fA-F]{64}$/.test(value.trim())) return true;
      return "PRIVATE_KEY phải là hex 32-byte dạng 0x...";
    }
  });
}

/**
 * @param {string} [defaultValue]
 */
export function promptPredecessor(defaultValue = ZERO_HASH) {
  return input({
    message: "Predecessor (Enter để dùng 0x00...00)",
    default: defaultValue,
    validate(value) {
      if (/^0x[0-9a-fA-F]{64}$/.test(value.trim())) return true;
      return "Predecessor phải là bytes32 hợp lệ.";
    }
  });
}
