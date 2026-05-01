import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        navy: "#1A1248",
        brand: { green: "#8DC63F", blue: "#1B9BD9" }
      }
    }
  },
  plugins: [],
};
export default config;
