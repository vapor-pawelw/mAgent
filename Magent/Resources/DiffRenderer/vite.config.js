export default {
  base: "./",
  build: {
    assetsDir: ".",
    rollupOptions: {
      output: {
        entryFileNames: "index.js",
        chunkFileNames: "chunk-[name].js",
        assetFileNames: (assetInfo) => {
          if (assetInfo.name?.endsWith(".css")) return "index.css";
          return "asset-[name][extname]";
        },
      },
    },
  },
};
