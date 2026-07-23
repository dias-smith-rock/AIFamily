import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://www.wefamily.ai",
  i18n: {
    defaultLocale: "en",
    locales: ["en", "zh-Hans", "zh-Hant"],
    routing: {
      prefixDefaultLocale: false,
    },
  },
  trailingSlash: "ignore",
});
