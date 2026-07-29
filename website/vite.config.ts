import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  base: "/",
  plugins: [react(), tailwindcss()],
  build: {
    rollupOptions: {
      input: {
        home: new URL("./index.html", import.meta.url).pathname,
        privacy: new URL("./privacy/index.html", import.meta.url).pathname,
        terms: new URL("./terms/index.html", import.meta.url).pathname,
      },
    },
  },
});
