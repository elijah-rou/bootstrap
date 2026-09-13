local fixture = assert(vim.env.BOOTSTRAP_PARSER_FIXTURE, "missing parser fixture")
vim.cmd("edit " .. vim.fn.fnameescape(fixture))
vim.bo.filetype = "lua"
local parser = assert(vim.treesitter.get_parser(0, "lua"), "Lua parser did not load")
local trees = parser:parse(true)
assert(type(trees) == "table" and trees[1] ~= nil, "Lua parser returned no syntax tree")
local query = assert(vim.treesitter.query.get("lua", "highlights"), "Lua highlight query unavailable")
assert(query, "highlight query unavailable")
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
assert(vim.fn.foldlevel(1) >= 0, "Tree-sitter folding unavailable")
vim.fn.writefile({ "parser=lua", "highlight=true", "fold=true" }, assert(vim.env.BOOTSTRAP_PARSER_RECEIPT))
vim.cmd("qa!")
