import js from "@eslint/js";
import globals from "globals";

export default [
  {
    ignores: [
      "broadcast/**",
      "cache/**",
      "lib/**",
      "node_modules/**",
      "out/**"
    ]
  },
  js.configs.recommended,
  {
    files: ["tooling/chainora-cli/**/*.js"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.node
      }
    },
    rules: {
      "no-console": "off"
    }
  }
];
