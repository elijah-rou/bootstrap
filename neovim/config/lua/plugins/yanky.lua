return {
  {
    "gbprod/yanky.nvim",
    optional = true,
    opts = {
      -- Focus changes must not synchronously read the system clipboard.
      system_clipboard = { sync_with_ring = false },
    },
  },
}
