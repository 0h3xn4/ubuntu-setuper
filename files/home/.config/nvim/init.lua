-- ~/.config/nvim/init.lua — installed by workstation-setup
--
-- Plugin-free on purpose: there is no plugin manager here, so Neovim never downloads anything when it starts.
-- It talks to the same LOCAL language servers as Helix and Kate (clangd, basedpyright, ruff, rust-analyzer,
-- taplo, bash-language-server). Helix stays your default editor ($EDITOR); this is the same setup for Neovim.
-- The setup never overwrites this file. Edit it freely; delete it and re-run the setup to get this version back.
vim.g.ws_nvim_config = true

-- ---------- Nothing looks for the network or for helper languages by itself ----------
vim.g.loaded_spellfile_plugin = 1            -- would offer to download spell files from the internet
for _, p in ipairs({ "node", "perl", "python3", "ruby" }) do
  vim.g["loaded_" .. p .. "_provider"] = 0   -- no probing for host interpreters
end

-- ---------- Editing ----------
vim.g.mapleader = " "
local o = vim.opt
o.number = true
o.relativenumber = true
o.cursorline = true
o.colorcolumn = "100"
o.signcolumn = "yes"
o.termguicolors = true
o.mouse = "a"
o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.undofile = true
o.updatetime = 300
o.expandtab = true       -- 4 spaces, like Helix; a project's .editorconfig overrides this
o.shiftwidth = 4
o.softtabstop = 4
o.completeopt = { "menu", "menuone", "noselect" }
if vim.fn.executable("wl-copy") == 1 or vim.fn.executable("xclip") == 1 then
  o.clipboard = "unnamedplus"   -- yank/paste through the system clipboard (wl-clipboard/xclip are installed)
end

vim.diagnostic.config({ virtual_text = true, severity_sort = true, float = { border = "rounded" } })

-- ---------- Language servers (local programs only; a server that is not installed is skipped) ----------
local servers = {
  {
    name = "clangd",
    cmd = {
      "clangd", "--background-index", "--clang-tidy", "--header-insertion=never", "--completion-style=detailed",
      -- let clangd ask GCC (also cross compilers such as arm-none-eabi-gcc) for its own system headers
      "--query-driver=/usr/bin/*-gcc*,/usr/bin/*-g++*,/usr/bin/gcc*,/usr/bin/g++*",
    },
    filetypes = { "c", "cpp" },
    root = { ".clangd", "compile_commands.json", "compile_flags.txt", ".git" },
  },
  {
    name = "basedpyright",
    cmd = { "basedpyright-langserver", "--stdio" },
    filetypes = { "python" },
    root = { "pyrightconfig.json", "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
    -- basedpyright's own default level ("recommended") floods working code with errors; "standard" is pyright's
    -- default. A project's pyrightconfig.json / [tool.basedpyright] still wins.
    settings = { basedpyright = { typeCheckingMode = "standard" } },
  },
  { name = "ruff", cmd = { "ruff", "server" }, filetypes = { "python" }, root = { "ruff.toml", ".ruff.toml", "pyproject.toml", ".git" } },
  {
    name = "rust_analyzer",
    cmd = { "rust-analyzer" },
    filetypes = { "rust" },
    root = { "Cargo.toml", "rust-project.json", ".git" },
    settings = { ["rust-analyzer"] = { check = { command = "clippy" } } },
  },
  { name = "taplo", cmd = { "taplo", "lsp", "stdio" }, filetypes = { "toml" }, root = { ".taplo.toml", "taplo.toml", ".git" } },
  { name = "bashls", cmd = { "bash-language-server", "start" }, filetypes = { "sh", "bash" }, root = { ".git" } },
  { name = "cmake", cmd = { "cmake-language-server" }, filetypes = { "cmake" }, root = { "CMakeLists.txt", ".git" } },
  -- JSON and YAML: no language server on purpose (the usual ones download schemas from the internet).
  -- Syntax highlighting still works; validate with jq / yamllint.
}

local function start_server(server, bufnr)
  if vim.bo[bufnr].buftype ~= "" or vim.fn.executable(server.cmd[1]) ~= 1 then return end
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then return end
  local dir = vim.fs.dirname(file)
  local found = vim.fs.find(server.root, { path = dir, upward = true })[1]
  vim.lsp.start({
    name = server.name,
    cmd = server.cmd,
    root_dir = found and vim.fs.dirname(found) or dir,
    settings = server.settings,
  }, { bufnr = bufnr })
end

for _, server in ipairs(servers) do
  vim.api.nvim_create_autocmd("FileType", {
    pattern = server.filetypes,
    callback = function(args) pcall(start_server, server, args.buf) end,
  })
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local function map(keys, fn, desc) vim.keymap.set("n", keys, fn, { buffer = args.buf, desc = desc }) end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gr", vim.lsp.buf.references, "References")
    map("K", vim.lsp.buf.hover, "Documentation under the cursor")
    map("<leader>rn", vim.lsp.buf.rename, "Rename")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("<leader>f", function() vim.lsp.buf.format({ timeout_ms = 3000 }) end, "Format the file")
    map("<leader>e", vim.diagnostic.open_float, "Show the diagnostic message")
    -- completion popup while typing (Neovim 0.11 and newer); older versions: Ctrl-x Ctrl-o
    if vim.lsp.completion and vim.lsp.completion.enable then
      pcall(vim.lsp.completion.enable, true, args.data.client_id, args.buf, { autotrigger = true })
    end
  end,
})

-- Python, Rust and TOML are formatted on save, like in Helix. C and C++ are NOT: reformatting existing code
-- creates huge diffs. Format them on purpose with <leader>f.
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.py", "*.rs", "*.toml" },
  callback = function() pcall(vim.lsp.buf.format, { timeout_ms = 2000 }) end,
})
