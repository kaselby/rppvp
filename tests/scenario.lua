-- Runs one scenario on a fresh simulated client: tests/scenarios/base.lua
-- followed by the scenario's own lines, as one chunk so the scenario sees
-- the harness's locals. From the project root:
--   luajit tests/scenario.lua NAME
-- tests/run.lua runs every scenario this way, each in its own process.
local name = assert(arg[1], "usage: luajit tests/scenario.lua NAME")
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local source = read("tests/scenarios/base.lua") .. "\n" .. read("tests/scenarios/" .. name .. ".lua")
assert(loadstring(source, "=" .. name))()
