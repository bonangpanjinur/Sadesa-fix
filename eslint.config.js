import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  // Bun may materialize package sources under .cache; those files are not
  // project code and must not be linted as part of the repository.
  { ignores: ["dist", ".cache"] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", {
        allowConstantExport: true,
        allowExportNames: [
          "formatFullAddress", "createEmptyAddressData", "useImagePreloader",
          "useFormField", "toast", "useAuth", "useCart", "usePOS",
          "navigationMenuTriggerStyle", "useSidebar",
        ],
      }],
      "@typescript-eslint/no-unused-vars": "off",
    },
  },
);
