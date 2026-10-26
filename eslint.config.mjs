// flat config native (eslint-config-next >= 16 tidak pakai eslintrc lagi)
import coreWebVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

const eslintConfig = [...coreWebVitals, ...nextTypescript];

export default eslintConfig;
