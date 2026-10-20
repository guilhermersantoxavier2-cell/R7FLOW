--[[
    LOADER - R7FLOW-AFK
    Coloque este LocalScript em StarterPlayerScripts ou StarterGui
    Requer executor (Synapse, Fluxus, Delta, etc.) para funcionar
    pois depende de game:HttpGet e loadstring
]]

local URL = "https://raw.githubusercontent.com/guilhermersantoxavier2-cell/R7FLOW/refs/heads/main/main.lua"

-- Função para pegar o source com fallbacks (diferentes executores)
local function fetchScript(url)
    local methods = {
        function() return game:HttpGet(url) end,
        function() return game:HttpGetAsync(url) end,
        function() return request({ Url = url, Method = "GET" }).Body end,
        function() return syn.request({ Url = url, Method = "GET" }).Body end,
        function() return http_request({ Url = url, Method = "GET" }).Body end,
    }

    for _, method in ipairs(methods) do
        local ok, result = pcall(method)
        if ok and type(result) == "string" and #result > 0 then
            return result
        end
    end

    return nil
end

-- Executa
local success, source = pcall(fetchScript, URL)

if not success or not source then
    warn("[LOADER R7FLOW] Falha ao baixar o script. Verifique sua conexão ou o executor.")
    return
end

-- Verifica cache-busting (evita pegar versão antiga)
if source:find("404: Not Found") then
    warn("[LOADER R7FLOW] Script não encontrado no repositório (404).")
    return
end

-- Executa o script baixado
local loadSuccess, loadErr = pcall(function()
    local chunk, err = loadstring(source, "@R7FLOW-AFK/main.lua")
    if not chunk then
        error("Erro ao compilar: " .. tostring(err))
    end
    chunk()
end)

if loadSuccess then
    print("[LOADER R7FLOW] ✅ Script carregado com sucesso!")
else
    warn("[LOADER R7FLOW] ❌ Erro na execução: " .. tostring(loadErr))
end
