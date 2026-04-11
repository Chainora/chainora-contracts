// @ts-check

import fs from "node:fs/promises";
import dotenv from "dotenv";

import { DEFAULT_ENV_PATH, nonEmpty } from "./shared.js";

export class EnvStore {
  /**
   * @param {string} filePath
   * @param {string} rawText
   * @param {Record<string, string>} fileValues
   */
  constructor(filePath, rawText, fileValues) {
    this.filePath = filePath;
    this.rawText = rawText;
    this.fileValues = fileValues;
    this.values = { ...fileValues, ...process.env };
  }

  /**
   * @param {string} key
   * @returns {string | undefined}
   */
  get(key) {
    return this.values[key];
  }

  /**
   * @param {string} key
   * @returns {string | undefined}
   */
  getNonEmpty(key) {
    return nonEmpty(this.get(key));
  }

  /**
   * @param {Record<string, string>} updates
   */
  async sync(updates) {
    const newline = this.rawText.includes("\r\n") ? "\r\n" : "\n";
    /** @type {string[]} */
    const lines = this.rawText.length > 0 ? this.rawText.split(/\r?\n/) : [];

    for (const [key, value] of Object.entries(updates)) {
      const nextLine = `${key}=${value}`;
      const matcher = new RegExp(`^\\s*${escapeRegExp(key)}\\s*=`);
      const index = lines.findIndex((line) => matcher.test(line));

      if (index >= 0) {
        lines[index] = nextLine;
      } else {
        lines.push(nextLine);
      }

      this.fileValues[key] = value;
    }

    this.rawText = `${lines.filter((line, index, all) => !(index === all.length - 1 && line === "")).join(newline)}${newline}`;
    this.values = { ...this.fileValues, ...process.env };
    await fs.writeFile(this.filePath, this.rawText, "utf8");
  }
}

/**
 * @param {string} [envPath]
 */
export async function loadEnvStore(envPath = DEFAULT_ENV_PATH) {
  try {
    const rawText = await fs.readFile(envPath, "utf8");
    const fileValues = dotenv.parse(rawText);
    return new EnvStore(envPath, rawText, fileValues);
  } catch (error) {
    /** @type {{ code?: string }} */ const knownError = /** @type {any} */ (error);
    if (knownError.code === "ENOENT") {
      return new EnvStore(envPath, "", {});
    }
    throw error;
  }
}

/**
 * @param {string} value
 */
function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

