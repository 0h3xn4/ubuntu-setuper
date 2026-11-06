-- Run by the self-test (t_nvim):  nvim --headless -n -i NONE nvim_check.py -c 'luafile nvim_check.lua'
-- The installed init.lua starts basedpyright for the Python file. In "standard" mode the one real mistake in the
-- file (a str assigned to an int) is reported and the missing type hints on add() are not. The "recommended"
-- level would also report reportMissingParameterType and the reportUnknown* family.
-- Exit codes: 0 pass, 1 fail, 3 no language server answered (the test turns that into a skip).
local function finish(code, msg)
  io.stderr:write(msg .. "\n")
  vim.cmd((code == 0 and "qa!") or ("cquit " .. code))
end

if not vim.g.ws_nvim_config then return finish(1, "init.lua was not loaded") end

local got = vim.wait(90000, function() return #vim.diagnostic.get(0) > 0 end, 250)
if not got then return finish(3, "no diagnostics arrived within 90 s") end
vim.wait(2000, function() return false end, 250)   -- let the other server (ruff) report too

local bad, codes = {}, {}
local noisy = {
  reportMissingParameterType = true, reportUnknownParameterType = true, reportUnknownVariableType = true,
  reportUnknownArgumentType = true, reportUnknownMemberType = true, reportMissingTypeArgument = true,
}
for _, d in ipairs(vim.diagnostic.get(0)) do
  codes[#codes + 1] = tostring(d.code)
  if noisy[d.code] then bad[#bad + 1] = tostring(d.code) end
end
if #bad > 0 then return finish(1, "Neovim shows the strict basedpyright level: " .. table.concat(bad, ", ")) end
return finish(0, "diagnostics: " .. table.concat(codes, ", "))
