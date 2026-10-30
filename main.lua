local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = Workspace.CurrentCamera

local VELOCIDADE_RUN    = 1e95
local DISTANCIA_CHEGADA = 4
local IGNORAR_EIXO_Y    = true
local WALK_TEMP         = 700
local JUMP_TEMP         = 260
local DURACAO_TRAVA     = 0.6
local CLONE_SO_PRA_MIM  = true
local NOME_SMART        = "SmartPromptPart"

local AntiKB    = true
local DEBUG_KB  = false
local THRESHOLD_KB = 15

local Destino = { posicao = nil, usarSpawn = true }

-- MÓDULOS
local EggState, AreasData, RarityData, AssetsData, PetsData
pcall(function() EggState   = require(ReplicatedStorage.Client.EggState) end)
pcall(function() AreasData  = require(ReplicatedStorage.Data.Areas) end)
pcall(function() RarityData = require(ReplicatedStorage.Data.Rarity) end)
pcall(function() AssetsData = require(ReplicatedStorage.Data.Assets) end)
pcall(function() PetsData   = require(ReplicatedStorage.Data.Pets) end)

local RARITY_SCORE_MAP = {
    ["Light & Dark"]    = 1300, ["Titan"]           = 1100,
    ["Divine"]          = 1000, ["Transcendent"]    = 1000,
    ["Superior"]        = 1000, ["Eternal"]         = 900,
    ["Limited"]         = 900,  ["Secret"]          = 800,
    ["Exotic"]          = 800,  ["Cosmic"]          = 700,
    ["Exclusive"]       = 700,  ["Admin"]           = 700,
    ["Mythic"]          = 600,  ["Mythical"]        = 600,
    ["Prismatic"]       = 600,  ["Rainbow"]         = 600,
    ["Squishy God"]     = 600,  ["BrainrotGod"]     = 600,
    ["Legendary"]       = 500,  ["Epic"]            = 400,
    ["Rare"]            = 300,  ["SuperRare"]       = 200,
    ["Celestial"]       = 200,  ["Uncommon"]        = 200,
    ["Basic"]           = 100,  ["Common"]          = 100,
}

-- TELEPORTE
local Teleporte = {
    conn = nil, ativo = false, char = nil, hum = nil, root = nil,
    walkOrig = nil, jumpOrig = nil,
}

function Teleporte.refs()
    Teleporte.char = LocalPlayer.Character
    if not Teleporte.char then return false end
    Teleporte.hum  = Teleporte.char:FindFirstChildOfClass("Humanoid")
    Teleporte.root = Teleporte.char:FindFirstChild("HumanoidRootPart")
    return Teleporte.hum ~= nil and Teleporte.root ~= nil
end

function Teleporte.pegarSpawn()
    local lista = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("SpawnLocation") then table.insert(lista, o) end
    end
    if #lista == 0 then return nil end
    if not Teleporte.root then return lista[1] end
    local melhor, dMin = nil, math.huge
    for _, sp in ipairs(lista) do
        local d = (sp.Position - Teleporte.root.Position).Magnitude
        if d < dMin then melhor, dMin = sp, d end
    end
    return melhor
end

function Teleporte.pegarAlvo()
    if Destino.usarSpawn then
        local spawn = Teleporte.pegarSpawn()
        if not spawn then return nil end
        return spawn.Position + Vector3.new(0, 3, 0)
    end
    if not Destino.posicao then return nil end
    return Destino.posicao + Vector3.new(0, 3, 0)
end

function Teleporte.parar()
    if Teleporte.conn then
        Teleporte.conn:Disconnect()
        Teleporte.conn = nil
    end
    if Teleporte.hum then
        if Teleporte.walkOrig then Teleporte.hum.WalkSpeed = Teleporte.walkOrig end
        if Teleporte.jumpOrig then Teleporte.hum.JumpPower = Teleporte.jumpOrig end
    end
    Teleporte.walkOrig = nil
    Teleporte.jumpOrig = nil
    Teleporte.ativo    = false
end

function Teleporte.iniciar()
    if Teleporte.ativo then Teleporte.parar() return end
    if not Teleporte.refs() then return end
    local alvo = Teleporte.pegarAlvo()
    if not alvo then return end
    Teleporte.walkOrig = Teleporte.hum.WalkSpeed
    Teleporte.jumpOrig = Teleporte.hum.JumpPower
    Teleporte.hum.WalkSpeed = WALK_TEMP
    Teleporte.hum.JumpPower = JUMP_TEMP
    Teleporte.ativo = true

    Teleporte.conn = RunService.Heartbeat:Connect(function(dt)
        if not Teleporte.ativo then return end
        if not Teleporte.refs() then Teleporte.parar() return end
        local origem = Teleporte.root.Position
        local delta  = alvo - origem
        if IGNORAR_EIXO_Y then delta = Vector3.new(delta.X, 0, delta.Z) end
        local dist = delta.Magnitude
        if dist <= DISTANCIA_CHEGADA then
            Teleporte.root.CFrame = CFrame.new(alvo)
                * (Teleporte.root.CFrame - Teleporte.root.CFrame.Position)
            Teleporte.root.AssemblyLinearVelocity  = Vector3.zero
            Teleporte.root.AssemblyAngularVelocity = Vector3.zero
            Teleporte.parar()
            return
        end
        local direcao = (dist > 0) and delta.Unit or Teleporte.root.CFrame.LookVector
        local passo   = math.min(VELOCIDADE_RUN * dt, dist)
        local novaPos = origem + direcao * passo
        Teleporte.root.CFrame = CFrame.lookAt(novaPos, novaPos + direcao)
        Teleporte.root.AssemblyLinearVelocity  = Vector3.zero
        Teleporte.root.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- DISFARCE
local Disfarce = { ativo = false, clone = nil, connCam = nil, thread = nil }

function Disfarce.limpar()
    Disfarce.ativo = false
    if Disfarce.connCam then Disfarce.connCam:Disconnect() Disfarce.connCam = nil end
    local t = Disfarce.thread
    Disfarce.thread = nil
    if t then pcall(task.cancel, t) end
    if Disfarce.clone then Disfarce.clone:Destroy() Disfarce.clone = nil end
    Camera.CameraType = Enum.CameraType.Custom
end

function Disfarce.iniciar()
    if Disfarce.ativo then Disfarce.limpar() return end
    local char = LocalPlayer.Character
    if not char then return end
    if not char:FindFirstChild("HumanoidRootPart") then return end
    Disfarce.ativo = true
    local cframeSalvo = Camera.CFrame
    Camera.CameraType = Enum.CameraType.Scriptable
    Camera.CFrame = cframeSalvo

    Disfarce.connCam = RunService.RenderStepped:Connect(function()
        if Disfarce.ativo then Camera.CFrame = cframeSalvo end
    end)

    if CLONE_SO_PRA_MIM and char.Parent then
        local eraArch = char.Archivable
        char.Archivable = true
        local ok, resultado = pcall(function() return char:Clone() end)
        if ok and resultado then
            resultado.Name = "CloneLocal_" .. LocalPlayer.Name
            for _, d in ipairs(resultado:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
            end
            local h = resultado:FindFirstChildOfClass("Humanoid")
            if h then
                h.WalkSpeed = 0
                h.JumpPower = 0
                h.PlatformStand = true
                h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
            for _, p in ipairs(resultado:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = true
                    p.CanCollide = false
                    p.CanTouch = false
                    p.CanQuery = false
                end
            end
            resultado.Parent = Workspace
            Disfarce.clone = resultado
        end
        char.Archivable = eraArch
    end

    Disfarce.thread = task.delay(DURACAO_TRAVA, function()
        Disfarce.thread = nil
        Disfarce.limpar()
    end)
end

-- ANTI-TRAP
local AntiTrap = { ativo = false, thread = nil }

local function neutralizarHitboxes()
    local transient = Workspace:FindFirstChild("Transient")
    if not transient then return end
    for _, obj in ipairs(transient:GetDescendants()) do
        if obj.Name == "Hitbox" and obj:IsA("BasePart") then
            if obj.CanTouch or obj.CanCollide then
                pcall(function()
                    obj.CanTouch = false
                    obj.CanCollide = false
                end)
            end
        end
    end
end

function AntiTrap.iniciar()
    if AntiTrap.ativo then return end
    AntiTrap.ativo = true
    neutralizarHitboxes()
    AntiTrap.thread = task.spawn(function()
        while AntiTrap.ativo do
            neutralizarHitboxes()
            task.wait(0.1)
        end
    end)
end

function AntiTrap.parar()
    AntiTrap.ativo = false
    if AntiTrap.thread then
        pcall(task.cancel, AntiTrap.thread)
        AntiTrap.thread = nil
    end
end

function AntiTrap.toggle()
    if AntiTrap.ativo then AntiTrap.parar() else AntiTrap.iniciar() end
end

-- ANTI-KNOCKBACK
local ultimaPosKB = nil

local function estaEmKB(hum)
    local temRagdoll = false
    pcall(function()
        local rd = tonumber(LocalPlayer:GetAttribute("RagdollEndTime"))
        if rd and rd > Workspace:GetServerTimeNow() then temRagdoll = true end
    end)
    if temRagdoll then return true end
    local s
    pcall(function() s = hum:GetState() end)
    if s == Enum.HumanoidStateType.Physics
    or s == Enum.HumanoidStateType.Ragdoll
    or s == Enum.HumanoidStateType.FallingDown then
        return true
    end
    if hum.PlatformStand then return true end
    return false
end

local function DebugKB(estado, diff, restaurou)
    if not DEBUG_KB then return end
    print(string.format("[Anti-KB] estado=%s | diff=%.1f | restaurou=%s",
        tostring(estado), diff or 0, tostring(restaurou)))
end

RunService.Heartbeat:Connect(function()
    if not AntiKB then return end
    local char, hum, hrp
    pcall(function()
        char = LocalPlayer.Character
        if char then
            hum = char:FindFirstChildOfClass("Humanoid")
            hrp = char:FindFirstChild("HumanoidRootPart")
        end
    end)
    if not char or not hum or not hrp then return end
    if hum.Health <= 0 then ultimaPosKB = nil return end
    if estaEmKB(hum) then return end
    pcall(function() ultimaPosKB = hrp.Position end)
end)

task.spawn(function()
    while true do
        if not AntiKB then
            task.wait(0.1)
        else
            pcall(function()
                local char = LocalPlayer.Character
                if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hum or not hrp then return end
                if hum.Health <= 0 then return end
                if not estaEmKB(hum) then return end

                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero

                local diff, restaurou = 0, false
                if ultimaPosKB then
                    diff = (hrp.Position - ultimaPosKB).Magnitude
                    if diff > THRESHOLD_KB then
                        hrp.CFrame = CFrame.new(ultimaPosKB,
                            ultimaPosKB + hrp.CFrame.LookVector)
                        restaurou = true
                    end
                end
                local estado
                pcall(function() estado = hum:GetState() end)
                DebugKB(estado, diff, restaurou)
            end)
            task.wait(0.01)
        end
    end
end)

-- TP-AREA
local function FindGuardAreas(parent)
    parent = parent or Workspace
    for _, child in pairs(parent:GetChildren()) do
        if child.Name == "GuardAreas" then
            return child
        end
        local found = FindGuardAreas(child)
        if found then return found end
    end
    return nil
end

local function GetNestsModel(areaName)
    local guardAreas = FindGuardAreas()
    if not guardAreas then
        warn("[TP-AREA] Pasta GuardAreas não encontrada!")
        return nil
    end
    local areaFolder = guardAreas:FindFirstChild(areaName)
    if not areaFolder then
        warn("[TP-AREA] Área não encontrada: " .. areaName)
        return nil
    end
    local nests = areaFolder:FindFirstChild("Nests")
    if not nests then
        for _, v in pairs(areaFolder:GetDescendants()) do
            if v.Name == "Nests" then nests = v break end
        end
    end
    return nests
end

local function TeleportAndFireClosestPrompt(nestsModel)
    if not nestsModel then return false end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    local hrp = char.HumanoidRootPart
    local targetPart = nestsModel.PrimaryPart or nestsModel:FindFirstChildWhichIsA("BasePart")
    if targetPart then
        hrp.CFrame = targetPart.CFrame + Vector3.new(0, 5, 0)
    else
        local cf, size = nestsModel:GetBoundingBox()
        hrp.CFrame = cf + Vector3.new(0, size.Y/2 + 3, 0)
    end
    task.wait(0.5)
    local closestPrompt = nil
    local shortestDist = math.huge
    local MAX_DISTANCE = 200
    for _, desc in pairs(Workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Parent:IsA("BasePart") then
            local dist = (hrp.Position - desc.Parent.Position).Magnitude
            if dist < shortestDist and dist <= MAX_DISTANCE then
                shortestDist = dist
                closestPrompt = desc
            end
        end
    end
    if closestPrompt then
        hrp.CFrame = closestPrompt.Parent.CFrame + Vector3.new(0, 3, 0)
        task.wait(0.3)
        if fireproximityprompt then
            fireproximityprompt(closestPrompt)
        else
            closestPrompt:InputHoldBegin()
            if closestPrompt.HoldDuration > 0 then
                task.wait(closestPrompt.HoldDuration)
            else
                task.wait(0.1)
            end
            closestPrompt:InputHoldEnd()
        end
        return true
    else
        warn("[TP-AREA] Nenhum ProximityPrompt encontrado num raio de " .. MAX_DISTANCE .. " studs.")
        return false
    end
end

local function executarTpAreaIntegrado(areaNome, setStatus, setBtn)
    if not areaNome then
        if setStatus then setStatus("Selecione uma área primeiro!", Color3.fromRGB(255, 200, 0)) end
        return
    end
    if setBtn then setBtn("Teleportando...", Color3.fromRGB(200, 150, 0)) end
    if setStatus then setStatus("Indo para Forest...", Color3.fromRGB(255, 200, 0)) end
    local forestNests = GetNestsModel("Forest")
    if forestNests then
        TeleportAndFireClosestPrompt(forestNests)
    else
        warn("[TP-AREA] Área 'Forest' não encontrada no GuardAreas.")
    end
    if setStatus then setStatus("Aguardando 3 segundos...", Color3.fromRGB(255, 200, 0)) end
    task.wait(3)
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        if setStatus then setStatus("Personagem morreu ou resetou.", Color3.fromRGB(255, 100, 100)) end
        if setBtn then setBtn("🌪️TP-AREA", Color3.fromRGB(0, 150, 255)) end
        return
    end
    if setStatus then setStatus("Indo para " .. areaNome .. "...", Color3.fromRGB(100, 255, 100)) end
    local targetNests = GetNestsModel(areaNome)
    if targetNests then
        TeleportAndFireClosestPrompt(targetNests)
    else
        warn("[TP-AREA] Model 'Nests' não encontrado para a área: " .. areaNome)
        if setStatus then setStatus("Erro: Nests não encontrado em " .. areaNome, Color3.fromRGB(255, 100, 100)) end
    end
    if setBtn then setBtn("🌪️TP-AREA", Color3.fromRGB(0, 150, 255)) end
    task.wait(2)
    if setStatus then setStatus("Selecione uma área...", Color3.fromRGB(200, 200, 220)) end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if Teleporte.ativo then Teleporte.parar() end
    Disfarce.limpar()
    ultimaPosKB = nil
    Teleporte.refs()
end)

Teleporte.refs()

-- GUI (TEMA ESCURO / R7FLOW)
local ROXO      = Color3.fromRGB(100, 85, 120)   -- Roxo acinzentado (sombrio)
local ROXO_DARK = Color3.fromRGB(30, 25, 35)     -- Quase preto com fundo roxo
local VERDE     = Color3.fromRGB(60, 200, 90)
local VERMELHO  = Color3.fromRGB(230, 50, 70)
local LARANJA   = Color3.fromRGB(230, 140, 50)
local AMARELO   = Color3.fromRGB(230, 180, 50)
local AZUL      = Color3.fromRGB(60, 150, 230)
local BG        = Color3.fromRGB(8, 8, 10)       -- Fundo quase preto
local BG_BTN    = Color3.fromRGB(16, 16, 20)     -- Botões em tom de carvão
local TXT       = Color3.fromRGB(210, 210, 220)  
local TXT_DIM   = Color3.fromRGB(140, 140, 150)  

local gui = Instance.new("ScreenGui")
gui.Name = "R7FLOWGui"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

-- Toast
local toastContainer = Instance.new("Frame")
toastContainer.Name = "Toasts"
toastContainer.Size = UDim2.new(0, 300, 1, 0)
toastContainer.Position = UDim2.new(0.5, -150, 0, 0)
toastContainer.BackgroundTransparency = 1
toastContainer.ZIndex = 100
toastContainer.Parent = gui

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastContainer

local toastPad = Instance.new("UIPadding")
toastPad.PaddingTop = UDim.new(0, 20)
toastPad.Parent = toastContainer

function Toast(msg, cor)
    cor = cor or TXT
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -20, 0, 30)
    t.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    t.BackgroundTransparency = 0.1
    t.BorderSizePixel = 0
    t.Font = Enum.Font.GothamBold
    t.TextSize = 12
    t.TextColor3 = cor
    t.Text = msg
    t.ZIndex = 101
    t.Parent = toastContainer
    Instance.new("UICorner", t).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.Color = cor
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = t
    t.BackgroundTransparency = 1
    t.TextTransparency = 1
    TweenService:Create(t, TweenInfo.new(0.25), {
        BackgroundTransparency = 0.1, TextTransparency = 0,
    }):Play()
    task.delay(2, function()
        TweenService:Create(t, TweenInfo.new(0.3), {
            BackgroundTransparency = 1, TextTransparency = 1,
        }):Play()
        task.wait(0.35)
        t:Destroy()
    end)
end

-- HOLDER
local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.Size = UDim2.new(0, 340, 0, 260)
holder.Position = UDim2.new(0.5, -170, 0.1, 0)
holder.BackgroundTransparency = 1
holder.Active = true
holder.Draggable = true
holder.ClipsDescendants = true
holder.Parent = gui

local bordaGradiente = Instance.new("Frame")
bordaGradiente.Size = UDim2.new(1, 4, 1, 4)
bordaGradiente.Position = UDim2.new(0, -2, 0, -2)
bordaGradiente.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bordaGradiente.BorderSizePixel = 0
bordaGradiente.ZIndex = 1
bordaGradiente.Parent = holder
Instance.new("UICorner", bordaGradiente).CornerRadius = UDim.new(0, 14)

local gradBorda = Instance.new("UIGradient")
gradBorda.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(15, 15, 18)),   -- Preto/Acarvoado
    ColorSequenceKeypoint.new(0.35, ROXO),                         -- Roxo escuro
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(200, 200, 200)),-- Branco/Cinza claro (Prata)
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(15, 15, 18)),   -- Preto/Acarvoado
})
gradBorda.Parent = bordaGradiente

local menu = Instance.new("Frame")
menu.Size = UDim2.new(1, -4, 1, -4)
menu.Position = UDim2.new(0, 2, 0, 2)
menu.BackgroundColor3 = BG
menu.BorderSizePixel = 0
menu.ZIndex = 2
menu.Parent = holder
Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 12)

-- Header (R7FLOW)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundTransparency = 1
header.ZIndex = 3
header.Parent = menu

local ledHeader = Instance.new("Frame")
ledHeader.Size = UDim2.new(0, 6, 0, 6)
ledHeader.Position = UDim2.new(0, 10, 0, 15)
ledHeader.BackgroundColor3 = VERMELHO
ledHeader.BorderSizePixel = 0
ledHeader.ZIndex = 4
ledHeader.Parent = header
Instance.new("UICorner", ledHeader).CornerRadius = UDim.new(1, 0)

-- Logo R7FLOW
local logoHeader = Instance.new("ImageLabel")
logoHeader.Name = "Logo"
logoHeader.Size = UDim2.new(0, 20, 0, 20)
logoHeader.Position = UDim2.new(0, 22, 0, 8)
logoHeader.BackgroundTransparency = 1
logoHeader.Image = "rbxassetid://82209165523926"
logoHeader.ScaleType = Enum.ScaleType.Fit
logoHeader.ZIndex = 4
logoHeader.Parent = header

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -100, 0, 14)
titulo.Position = UDim2.new(0, 46, 0, 4)
titulo.BackgroundTransparency = 1
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 13
titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.Text = "R7FLOW"
titulo.ZIndex = 4
titulo.Parent = header

local subtitulo = Instance.new("TextLabel")
subtitulo.Size = UDim2.new(1, -100, 0, 10)
subtitulo.Position = UDim2.new(0, 46, 0, 19)
subtitulo.BackgroundTransparency = 1
subtitulo.Font = Enum.Font.Gotham
subtitulo.TextSize = 8
subtitulo.TextColor3 = TXT_DIM
subtitulo.TextXAlignment = Enum.TextXAlignment.Left
subtitulo.Text = "v15 | IB: @caligsc"
subtitulo.ZIndex = 4
subtitulo.Parent = header

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 18, 0, 18)
btnMin.Position = UDim2.new(1, -44, 0, 9)
btnMin.BackgroundTransparency = 1
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 14
btnMin.TextColor3 = TXT_DIM
btnMin.Text = "—"
btnMin.ZIndex = 5
btnMin.Parent = header
btnMin.MouseEnter:Connect(function() btnMin.TextColor3 = Color3.fromRGB(200, 200, 200) end)
btnMin.MouseLeave:Connect(function() btnMin.TextColor3 = TXT_DIM end)

local btnFechar = Instance.new("TextButton")
btnFechar.Size = UDim2.new(0, 18, 0, 18)
btnFechar.Position = UDim2.new(1, -22, 0, 9)
btnFechar.BackgroundTransparency = 1
btnFechar.Font = Enum.Font.GothamBold
btnFechar.TextSize = 12
btnFechar.TextColor3 = TXT_DIM
btnFechar.Text = "✕"
btnFechar.ZIndex = 5
btnFechar.Parent = header
btnFechar.MouseEnter:Connect(function() btnFechar.TextColor3 = VERMELHO end)
btnFechar.MouseLeave:Connect(function() btnFechar.TextColor3 = TXT_DIM end)
btnFechar.MouseButton1Click:Connect(function() holder.Visible = false end)

local faixaTopo = Instance.new("Frame")
faixaTopo.Size = UDim2.new(1, -16, 0, 2)
faixaTopo.Position = UDim2.new(0, 8, 0, 36)
faixaTopo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
faixaTopo.BorderSizePixel = 0
faixaTopo.ZIndex = 3
faixaTopo.Parent = menu
local gradTopo = Instance.new("UIGradient")
gradTopo.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1),
    NumberSequenceKeypoint.new(0.20, 0),
    NumberSequenceKeypoint.new(0.80, 0),
    NumberSequenceKeypoint.new(1.00, 1),
})
gradTopo.Color = ColorSequence.new(ROXO, Color3.fromRGB(200, 200, 200))
gradTopo.Parent = faixaTopo

-- SIDEBAR
local tabBarHolder = Instance.new("Frame")
tabBarHolder.Size = UDim2.new(0, 90, 0, 188)
tabBarHolder.Position = UDim2.new(0, 8, 0, 42)
tabBarHolder.BackgroundColor3 = BG_BTN
tabBarHolder.BorderSizePixel = 0
tabBarHolder.ZIndex = 3
tabBarHolder.ClipsDescendants = true
tabBarHolder.Parent = menu
Instance.new("UICorner", tabBarHolder).CornerRadius = UDim.new(0, 8)

local tabScroll = Instance.new("ScrollingFrame")
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.BorderSizePixel = 0
tabScroll.ScrollBarThickness = 0
tabScroll.ScrollingDirection = Enum.ScrollingDirection.Y
tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
tabScroll.ZIndex = 3
tabScroll.Parent = tabBarHolder

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Vertical
tabLayout.Padding = UDim.new(0, 4)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Parent = tabScroll

local tabPad = Instance.new("UIPadding")
tabPad.PaddingTop = UDim.new(0, 4)
tabPad.PaddingBottom = UDim.new(0, 4)
tabPad.Parent = tabScroll

local function criarTabBtn(texto, imagemId, ordem)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 30)
    b.BackgroundColor3 = BG
    b.BorderSizePixel = 0
    b.Text = ""
    b.AutoButtonColor = false
    b.LayoutOrder = ordem
    b.ZIndex = 4
    b.Parent = tabScroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

    if imagemId then
        local img = Instance.new("ImageLabel")
        img.Name = "TabIcon"
        img.Size = UDim2.new(0, 24, 0, 24)
        img.Position = UDim2.new(0.5, -12, 0.5, -12)
        img.BackgroundTransparency = 1
        img.Image = imagemId
        img.ImageColor3 = TXT_DIM
        img.ScaleType = Enum.ScaleType.Fit
        img.ZIndex = 5
        img.Parent = b
    else
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.TextColor3 = TXT_DIM
        b.TextXAlignment = Enum.TextXAlignment.Center
        b.Text = texto
    end
    return b
end

local btnTabFunc  = criarTabBtn("FUNC",  "rbxassetid://5098046332",      1)
local btnTabTps   = criarTabBtn("TPs",   "rbxassetid://938790070",       2)
local btnTabHop   = criarTabBtn("HOP",   "rbxassetid://123380730425687", 3)
local btnTabSteal = criarTabBtn("STEAL", "rbxassetid://119629336187267", 4)

-- CONTAINERS
local CONTENT_X = 104
local CONTENT_Y = 42
local CONTENT_W = 224
local CONTENT_H = 188

local containerFunc = Instance.new("Frame")
containerFunc.Size = UDim2.new(0, CONTENT_W, 0, CONTENT_H)
containerFunc.Position = UDim2.new(0, CONTENT_X, 0, CONTENT_Y)
containerFunc.BackgroundTransparency = 1
containerFunc.ZIndex = 3
containerFunc.Parent = menu

local containerTps = Instance.new("Frame")
containerTps.Size = UDim2.new(0, CONTENT_W, 0, CONTENT_H)
containerTps.Position = UDim2.new(0, CONTENT_X, 0, CONTENT_Y)
containerTps.BackgroundTransparency = 1
containerTps.ZIndex = 3
containerTps.Visible = false
containerTps.Parent = menu

local containerHop = Instance.new("Frame")
containerHop.Size = UDim2.new(0, CONTENT_W, 0, CONTENT_H)
containerHop.Position = UDim2.new(0, CONTENT_X, 0, CONTENT_Y)
containerHop.BackgroundTransparency = 1
containerHop.ZIndex = 3
containerHop.Visible = false
containerHop.Parent = menu

local containerSteal = Instance.new("Frame")
containerSteal.Size = UDim2.new(0, CONTENT_W, 0, CONTENT_H)
containerSteal.Position = UDim2.new(0, CONTENT_X, 0, CONTENT_Y)
containerSteal.BackgroundTransparency = 1
containerSteal.ZIndex = 3
containerSteal.Visible = false
containerSteal.Parent = menu

-- Scroll Funções
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "ScrollBotoes"
scroll.Size = UDim2.new(1, 0, 1, 0)
scroll.Position = UDim2.new(0, 0, 0, 0)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = ROXO
scroll.ScrollBarImageTransparency = 0.3
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scroll.ZIndex = 3
scroll.Parent = containerFunc

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = scroll

local padScroll = Instance.new("UIPadding")
padScroll.PaddingTop = UDim.new(0, 2)
padScroll.PaddingBottom = UDim.new(0, 4)
padScroll.Parent = scroll

-- Scroll Áreas
local statusAreaLbl = Instance.new("TextLabel")
statusAreaLbl.Size = UDim2.new(1, -16, 0, 14)
statusAreaLbl.Position = UDim2.new(0, 8, 0, 0)
statusAreaLbl.BackgroundTransparency = 1
statusAreaLbl.Font = Enum.Font.Gotham
statusAreaLbl.TextSize = 9
statusAreaLbl.TextColor3 = TXT
statusAreaLbl.TextXAlignment = Enum.TextXAlignment.Left
statusAreaLbl.Text = "Selecione uma área..."
statusAreaLbl.ZIndex = 4
statusAreaLbl.Parent = containerTps

local scrollAreas = Instance.new("ScrollingFrame")
scrollAreas.Name = "ScrollAreas"
scrollAreas.Size = UDim2.new(1, 0, 1, -52)
scrollAreas.Position = UDim2.new(0, 0, 0, 18)
scrollAreas.BackgroundTransparency = 1
scrollAreas.BorderSizePixel = 0
scrollAreas.ScrollBarThickness = 4
scrollAreas.ScrollBarImageColor3 = AZUL
scrollAreas.ScrollBarImageTransparency = 0.3
scrollAreas.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollAreas.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollAreas.ScrollingDirection = Enum.ScrollingDirection.Y
scrollAreas.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scrollAreas.ZIndex = 3
scrollAreas.Parent = containerTps

local layoutAreas = Instance.new("UIListLayout")
layoutAreas.Padding = UDim.new(0, 3)
layoutAreas.SortOrder = Enum.SortOrder.LayoutOrder
layoutAreas.HorizontalAlignment = Enum.HorizontalAlignment.Center
layoutAreas.Parent = scrollAreas

local padAreas = Instance.new("UIPadding")
padAreas.PaddingTop = UDim.new(0, 2)
padAreas.PaddingBottom = UDim.new(0, 4)
padAreas.Parent = scrollAreas

local btnTpArea2 = Instance.new("TextButton")
btnTpArea2.Size = UDim2.new(1, -16, 0, 28)
btnTpArea2.Position = UDim2.new(0, 8, 1, -32)
btnTpArea2.BackgroundColor3 = AZUL
btnTpArea2.BorderSizePixel = 0
btnTpArea2.Font = Enum.Font.GothamBold
btnTpArea2.TextSize = 12
btnTpArea2.TextColor3 = Color3.fromRGB(255, 255, 255)
btnTpArea2.Text = "🌪️TP-AREA"
btnTpArea2.ZIndex = 4
btnTpArea2.Parent = containerTps
Instance.new("UICorner", btnTpArea2).CornerRadius = UDim.new(0, 7)

local AreaSelecionada = nil
local areaButtons = {}

local function updateSelectionAreaUI()
    for areaName, btn in pairs(areaButtons) do
        if areaName == AreaSelecionada then
            btn.BackgroundColor3 = Color3.fromRGB(0, 90, 40)
        else
            btn.BackgroundColor3 = BG_BTN
        end
    end
end

local function popularAreas()
    for _, c in ipairs(scrollAreas:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    areaButtons = {}
    AreaSelecionada = nil

    local ga = FindGuardAreas()
    if not ga then
        statusAreaLbl.Text = "GuardAreas não encontrado"
        statusAreaLbl.TextColor3 = VERMELHO
        return
    end
    statusAreaLbl.Text = "Selecione uma área..."
    statusAreaLbl.TextColor3 = TXT

    local i = 0
    for _, child in ipairs(ga:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            i = i + 1
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 22)
            btn.BackgroundColor3 = BG_BTN
            btn.BorderSizePixel = 0
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 10
            btn.TextColor3 = TXT
            btn.Text = child.Name
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.LayoutOrder = i
            btn.ZIndex = 3
            btn.Parent = scrollAreas
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 8)
            pad.Parent = btn

            areaButtons[child.Name] = btn

            btn.MouseButton1Click:Connect(function()
                AreaSelecionada = child.Name
                updateSelectionAreaUI()
                statusAreaLbl.Text = "Selecionado: " .. child.Name
                statusAreaLbl.TextColor3 = Color3.fromRGB(150, 200, 255)
            end)
        end
    end
end

-- ABA HOP
local HopState = {
    Servers    = {},
    Items      = {},
    FiltroIdx  = 1,
    Carregando = false,
}

local HopFiltros = {
    { label = "TODOS",         max = 999 },
    { label = "0-1 PLAYER",    max = 1 },
    { label = "0-3 PLAYERS",   max = 3 },
    { label = "0-5 PLAYERS",   max = 5 },
    { label = "0-10 PLAYERS",  max = 10 },
}

local btnHopFiltro = Instance.new("TextButton")
btnHopFiltro.Size = UDim2.new(1, -16, 0, 22)
btnHopFiltro.Position = UDim2.new(0, 8, 0, 2)
btnHopFiltro.BackgroundColor3 = BG_BTN
btnHopFiltro.BorderSizePixel = 0
btnHopFiltro.Font = Enum.Font.GothamBold
btnHopFiltro.TextSize = 10
btnHopFiltro.TextColor3 = TXT
btnHopFiltro.Text = "Filtro: TODOS"
btnHopFiltro.ZIndex = 4
btnHopFiltro.Parent = containerHop
Instance.new("UICorner", btnHopFiltro).CornerRadius = UDim.new(0, 5)

local hopStatus = Instance.new("TextLabel")
hopStatus.Size = UDim2.new(1, -16, 0, 12)
hopStatus.Position = UDim2.new(0, 8, 0, 26)
hopStatus.BackgroundTransparency = 1
hopStatus.Font = Enum.Font.Gotham
hopStatus.TextSize = 9
hopStatus.TextColor3 = TXT_DIM
hopStatus.TextXAlignment = Enum.TextXAlignment.Left
hopStatus.Text = "Pronto."
hopStatus.ZIndex = 4
hopStatus.Parent = containerHop

local btnHopEnter = Instance.new("TextButton")
btnHopEnter.Size = UDim2.new(1, -16, 0, 26)
btnHopEnter.Position = UDim2.new(0, 8, 0, 42)
btnHopEnter.BackgroundColor3 = Color3.fromRGB(0, 90, 160)
btnHopEnter.BorderSizePixel = 0
btnHopEnter.Font = Enum.Font.GothamBold
btnHopEnter.TextSize = 11
btnHopEnter.TextColor3 = Color3.fromRGB(255, 255, 255)
btnHopEnter.Text = "Entrar no Melhor"
btnHopEnter.ZIndex = 4
btnHopEnter.Parent = containerHop
Instance.new("UICorner", btnHopEnter).CornerRadius = UDim.new(0, 6)

local btnHopLista = Instance.new("TextButton")
btnHopLista.Size = UDim2.new(1, -16, 0, 22)
btnHopLista.Position = UDim2.new(0, 8, 0, 72)
btnHopLista.BackgroundColor3 = BG_BTN
btnHopLista.BorderSizePixel = 0
btnHopLista.Font = Enum.Font.GothamBold
btnHopLista.TextSize = 10
btnHopLista.TextColor3 = TXT
btnHopLista.Text = "Ver Lista de Servidores"
btnHopLista.ZIndex = 4
btnHopLista.Parent = containerHop
Instance.new("UICorner", btnHopLista).CornerRadius = UDim.new(0, 6)

local hopScroll = Instance.new("ScrollingFrame")
hopScroll.Size = UDim2.new(1, -16, 1, -102)
hopScroll.Position = UDim2.new(0, 8, 0, 98)
hopScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
hopScroll.BorderSizePixel = 0
hopScroll.ScrollBarThickness = 4
hopScroll.ScrollBarImageColor3 = ROXO
hopScroll.ScrollBarImageTransparency = 0.3
hopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
hopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
hopScroll.ScrollingDirection = Enum.ScrollingDirection.Y
hopScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
hopScroll.ZIndex = 3
hopScroll.Parent = containerHop
Instance.new("UICorner", hopScroll).CornerRadius = UDim.new(0, 6)

local hopLayout = Instance.new("UIListLayout")
hopLayout.Padding = UDim.new(0, 3)
hopLayout.SortOrder = Enum.SortOrder.LayoutOrder
hopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hopLayout.Parent = hopScroll

local hopPad = Instance.new("UIPadding")
hopPad.PaddingTop = UDim.new(0, 3)
hopPad.PaddingBottom = UDim.new(0, 3)
hopPad.Parent = hopScroll

local function hopSetStatus(txt, cor)
    hopStatus.Text = txt
    hopStatus.TextColor3 = cor or TXT_DIM
end

local function hopLimparLista()
    for _, item in ipairs(HopState.Items) do item:Destroy() end
    HopState.Items = {}
    hopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
end

local function hopAddMsg(msg, cor)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -4, 0, 22)
    lbl.BackgroundTransparency = 1
    lbl.Text = msg
    lbl.TextColor3 = cor or TXT_DIM
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = hopScroll
    table.insert(HopState.Items, lbl)
end

local function hopHttpGet(url)
    if game and game.HttpGet then
        local ok, result = pcall(function() return game:HttpGet(url) end)
        if ok and result and #result > 0 then return true, result end
    end
    local ok2, result2 = pcall(function() return HttpService:GetAsync(url, true) end)
    if ok2 and result2 and #result2 > 0 then return true, result2 end
    return false, "HTTP falhou."
end

local function hopFetchServers()
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
        .. "/servers/Public?sortOrder=Asc&limit=100"
    local ok, raw = hopHttpGet(url)
    if not ok or not raw or raw == "" then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or not data or not data.data then return nil end
    local currentId = tostring(game.JobId)
    local lista = {}
    for _, s in ipairs(data.data) do
        if s.id and tostring(s.id) ~= currentId and s.playing < s.maxPlayers then
            table.insert(lista, {
                id = tostring(s.id),
                playing = s.playing or 0,
                maxPlayers = s.maxPlayers or 0,
                ping = s.ping or 0,
            })
        end
    end
    table.sort(lista, function(a, b) return a.playing < b.playing end)
    return lista
end

local function hopVerificarVaga(serverId)
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
        .. "/servers/Public?sortOrder=Asc&limit=100"
    local ok, raw = hopHttpGet(url)
    if not ok or not raw then return false, nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or not data or not data.data then return false, nil end
    for _, s in ipairs(data.data) do
        if tostring(s.id) == tostring(serverId) then
            return (s.playing or 0) < (s.maxPlayers or 0), {
                id = tostring(s.id), playing = s.playing or 0,
                maxPlayers = s.maxPlayers or 0,
            }
        end
    end
    return false, nil
end

local function hopAplicarFiltro(lista)
    local opt = HopFiltros[HopState.FiltroIdx]
    local out = {}
    for _, s in ipairs(lista) do
        if s.playing <= opt.max then table.insert(out, s) end
    end
    return out
end

local function hopTentarTeleport(lista, maxTentativas)
    maxTentativas = maxTentativas or 5
    local t = 0
    for _, s in ipairs(lista) do
        if t >= maxTentativas then break end
        t = t + 1
        local temVaga, dados = hopVerificarVaga(s.id)
        if temVaga and dados then
            hopSetStatus("Tentando " .. t .. ": " .. dados.playing .. "/" .. dados.maxPlayers,
                AZUL)
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, dados.id, LocalPlayer)
            end)
            if ok then return true, dados end
            task.wait(0.6)
        end
    end
    return false, nil
end

local function hopRenderServers(lista)
    hopLimparLista()
    if not lista or #lista == 0 then
        hopAddMsg("Nenhum servidor com vaga.", VERMELHO)
        return
    end
    for i, s in ipairs(lista) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 24)
        row.BackgroundColor3 = BG_BTN
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.Parent = hopScroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local info = Instance.new("TextLabel")
        info.Size = UDim2.new(1, -54, 1, 0)
        info.Position = UDim2.new(0, 8, 0, 0)
        info.BackgroundTransparency = 1
        info.Text = string.format("%d/%d jogadores", s.playing, s.maxPlayers)
        info.TextColor3 = TXT
        info.Font = Enum.Font.Gotham
        info.TextSize = 10
        info.TextXAlignment = Enum.TextXAlignment.Left
        info.Parent = row

        local joinBtn = Instance.new("TextButton")
        joinBtn.Size = UDim2.new(0, 44, 0, 18)
        joinBtn.Position = UDim2.new(1, -48, 0.5, -9)
        joinBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 160)
        joinBtn.BorderSizePixel = 0
        joinBtn.Font = Enum.Font.GothamBold
        joinBtn.TextSize = 9
        joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        joinBtn.Text = "JOIN"
        joinBtn.Parent = row
        Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 4)

        joinBtn.MouseButton1Click:Connect(function()
            joinBtn.Text = "..."
            local temVaga, dados = hopVerificarVaga(s.id)
            if not temVaga then
                joinBtn.Text = "CHEIO"
                hopSetStatus("Server cheio.", VERMELHO)
                task.wait(1.5)
                joinBtn.Text = "JOIN"
                return
            end
            hopSetStatus("Entrando...", AZUL)
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, dados.id, LocalPlayer)
            end)
            if not ok then
                joinBtn.Text = "ERRO"
                task.wait(1.5)
                joinBtn.Text = "JOIN"
            end
        end)

        table.insert(HopState.Items, row)
    end
end

btnHopFiltro.MouseButton1Click:Connect(function()
    HopState.FiltroIdx = HopState.FiltroIdx + 1
    if HopState.FiltroIdx > #HopFiltros then HopState.FiltroIdx = 1 end
    btnHopFiltro.Text = "Filtro: " .. HopFiltros[HopState.FiltroIdx].label
    if #HopState.Servers > 0 then
        hopRenderServers(hopAplicarFiltro(HopState.Servers))
    end
end)

btnHopEnter.MouseButton1Click:Connect(function()
    if HopState.Carregando then return end
    HopState.Carregando = true
    btnHopEnter.Text = "Procurando..."
    hopSetStatus("Buscando o mais vazio...", AMARELO)
    task.wait(0.1)
    local lista = hopFetchServers()
    if not lista or #lista == 0 then
        hopSetStatus("Nenhum server com vaga.", VERMELHO)
        btnHopEnter.Text = "Entrar no Melhor"
        HopState.Carregando = false
        return
    end
    local filtrada = hopAplicarFiltro(lista)
    if #filtrada == 0 then filtrada = lista end
    hopSetStatus("Teleportando (top 5)...", AZUL)
    local sucesso, dados = hopTentarTeleport(filtrada, 5)
    if sucesso then
        hopSetStatus("Entrando em " .. dados.playing .. "/" .. dados.maxPlayers, VERDE)
    else
        hopSetStatus("Falha em todos os 5.", VERMELHO)
    end
    btnHopEnter.Text = "Entrar no Melhor"
    HopState.Carregando = false
end)

btnHopLista.MouseButton1Click:Connect(function()
    if HopState.Carregando then return end
    HopState.Carregando = true
    btnHopLista.Text = "Buscando..."
    hopSetStatus("Buscando servidores...", AMARELO)
    task.wait(0.1)
    local lista = hopFetchServers()
    if not lista or #lista == 0 then
        hopSetStatus("Nenhum server com vaga.", VERMELHO)
        btnHopLista.Text = "Ver Lista de Servidores"
        HopState.Carregando = false
        return
    end
    HopState.Servers = lista
    local filtrada = hopAplicarFiltro(lista)
    hopSetStatus(#filtrada .. " servers. Clica JOIN.", VERDE)
    btnHopLista.Text = "Ver Lista de Servidores"
    hopRenderServers(filtrada)
    HopState.Carregando = false
end)

-- SISTEMA DE ABAS
local abaAtiva = 1

local function atualizarAbas()
    containerFunc.Visible  = (abaAtiva == 1)
    containerTps.Visible   = (abaAtiva == 2)
    containerHop.Visible   = (abaAtiva == 3)
    containerSteal.Visible = (abaAtiva == 4)

    local function setCor(btn, ativo)
        if ativo then
            btn.BackgroundColor3 = Color3.fromRGB(25, 25, 30) -- Cinza bem escuro
            btn.TextColor3 = Color3.fromRGB(230, 230, 230)    -- Branco
        else
            btn.BackgroundColor3 = BG
            btn.TextColor3 = TXT_DIM
        end
        local img = btn:FindFirstChild("TabIcon")
        if img then
            img.ImageColor3 = ativo and Color3.fromRGB(230, 230, 230) or TXT_DIM
        end
    end
    setCor(btnTabFunc,  abaAtiva == 1)
    setCor(btnTabTps,   abaAtiva == 2)
    setCor(btnTabHop,   abaAtiva == 3)
    setCor(btnTabSteal, abaAtiva == 4)
end

btnTabFunc.MouseButton1Click:Connect(function()
    abaAtiva = 1
    atualizarAbas()
end)

btnTabTps.MouseButton1Click:Connect(function()
    abaAtiva = 2
    atualizarAbas()
    popularAreas()
end)

btnTabHop.MouseButton1Click:Connect(function()
    abaAtiva = 3
    atualizarAbas()
end)

btnTabSteal.MouseButton1Click:Connect(function()
    abaAtiva = 4
    atualizarAbas()
end)

-- Fábrica de botões
local function criarBotaoCyber(altura, texto, ordem)
    local cont = Instance.new("Frame")
    cont.Size = UDim2.new(1, -16, 0, altura)
    cont.BackgroundColor3 = BG_BTN
    cont.BorderSizePixel = 0
    cont.LayoutOrder = ordem
    cont.ZIndex = 3
    cont.Parent = scroll
    Instance.new("UICorner", cont).CornerRadius = UDim.new(0, 7)

    local barraLat = Instance.new("Frame")
    barraLat.Size = UDim2.new(0, 3, 1, -6)
    barraLat.Position = UDim2.new(0, 3, 0, 3)
    barraLat.BackgroundColor3 = ROXO
    barraLat.BorderSizePixel = 0
    barraLat.ZIndex = 4
    barraLat.Parent = cont
    Instance.new("UICorner", barraLat).CornerRadius = UDim.new(0, 2)

    local bordaBtn = Instance.new("UIStroke")
    bordaBtn.Thickness = 1
    bordaBtn.Color = ROXO_DARK
    bordaBtn.Parent = cont

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -40, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.TextColor3 = TXT
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = texto
    label.ZIndex = 4
    label.Parent = cont

    local seta = Instance.new("TextLabel")
    seta.Size = UDim2.new(0, 18, 1, 0)
    seta.Position = UDim2.new(1, -20, 0, 0)
    seta.BackgroundTransparency = 1
    seta.Font = Enum.Font.GothamBold
    seta.TextSize = 14
    seta.TextColor3 = ROXO
    seta.TextTransparency = 1
    seta.Text = "›"
    seta.ZIndex = 4
    seta.Parent = cont

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.ZIndex = 6
    btn.Parent = cont

    btn.MouseEnter:Connect(function()
        TweenService:Create(cont, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(22, 22, 28),
        }):Play()
        TweenService:Create(bordaBtn, TweenInfo.new(0.15), { Color = Color3.fromRGB(180, 180, 180) }):Play()
        TweenService:Create(seta, TweenInfo.new(0.15), {
            TextTransparency = 0, Position = UDim2.new(1, -16, 0, 0),
        }):Play()
    end)

    btn.MouseLeave:Connect(function()
        TweenService:Create(cont, TweenInfo.new(0.2), {
            BackgroundColor3 = BG_BTN,
        }):Play()
        TweenService:Create(bordaBtn, TweenInfo.new(0.2), { Color = ROXO_DARK }):Play()
        TweenService:Create(seta, TweenInfo.new(0.2), {
            TextTransparency = 1, Position = UDim2.new(1, -20, 0, 0),
        }):Play()
    end)

    local function bounce()
        local tam = cont.Size
        TweenService:Create(cont, TweenInfo.new(0.06), {
            Size = UDim2.new(tam.X.Scale, tam.X.Offset - 5,
                             tam.Y.Scale, tam.Y.Offset - 2),
        }):Play()
        task.wait(0.07)
        TweenService:Create(cont,
            TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = tam,
        }):Play()
    end

    return btn, cont, label, seta, barraLat, bordaBtn, bounce
end

local btnAnti,  contAnti,  labelAnti,  setaAnti,  barraAnti,  bordaAnti,  bounceAnti  =
    criarBotaoCyber(30, "🥚 ANTI-BOSS", 1)

local btnTrap,  contTrap,  labelTrap,  setaTrap,  barraTrap,  bordaTrap,  bounceTrap  =
    criarBotaoCyber(30, "🚫 ANTI-TRAP", 2)

local btnKB,    contKB,    labelKB,    setaKB,    barraKB,    bordaKB,    bounceKB    =
    criarBotaoCyber(30, "💫 ANTI-KNOCKBACK", 3)

local btnBypass, contBypass, labelBypass, setaBypass, barraBypass, bordaBypass, bounceBypass =
    criarBotaoCyber(30, "🔥 BYPASS", 4)

local btnDst,   contDst,   labelDst,   setaDst,   barraDst,   bordaDst,   bounceDst   =
    criarBotaoCyber(30, "📍 DEFINIR DESTINO", 5)

local btnReset, contReset, labelReset, setaReset, barraReset, bordaReset, bounceReset =
    criarBotaoCyber(30, "🎯 RESET SPAWN", 6)

local btnFlutuante, contFlutuante, labelFlutuante, setaFlutuante,
      barraFlutuante, bordaFlutuante, bounceFlutuante =
    criarBotaoCyber(30, "🌌 TP-EGG", 7)

local btnOvoInv, contOvoInv, labelOvoInv, setaOvoInv,
      barraOvoInv, bordaOvoInv, bounceOvoInv =
    criarBotaoCyber(30, "🫥 OVO INVISÍVEL", 8)

-- PAINEL ANTI-BOSS
local AntiBoss = { gui = nil, aberto = false, ativado = false }

local function criarAntiBossGui()
    if AntiBoss.gui then return AntiBoss.gui end

    local VelocidadeRun    = 1e15
    local DistanciaChegada = 4
    local IgnorarEixoY     = true
    local WalkSpeedFake    = 500
    local JumpPowerFake    = 120
    local NomeParte        = "SmartPromptPart"
    local NomePrompt       = "CarryAreaEgg"
    local TempoNoSpawn     = 0.3

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "AntiBossGui"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Enabled = false
    ScreenGui.Parent = PlayerGui

    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 180, 0, 45)
    MainFrame.Position = UDim2.new(0.5, -90, 1, -180)
    MainFrame.BackgroundColor3 = BG_BTN
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Draggable = true
    MainFrame.Parent = ScreenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = MainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = ROXO_DARK
    stroke.Thickness = 1
    stroke.Parent = MainFrame

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(0.6, 0, 1, 0)
    Title.Position = UDim2.new(0, 12, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "ANTI-BOSS"
    Title.TextColor3 = TXT
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 14
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = MainFrame

    local ToggleBg = Instance.new("Frame")
    ToggleBg.Size = UDim2.new(0, 50, 0, 26)
    ToggleBg.Position = UDim2.new(1, -60, 0.5, -13)
    ToggleBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    ToggleBg.BorderSizePixel = 0
    ToggleBg.Parent = MainFrame

    local tbCorner = Instance.new("UICorner")
    tbCorner.CornerRadius = UDim.new(1, 0)
    tbCorner.Parent = ToggleBg

    local ToggleCircle = Instance.new("Frame")
    ToggleCircle.Size = UDim2.new(0, 22, 0, 22)
    ToggleCircle.Position = UDim2.new(0, 2, 0.5, -11)
    ToggleCircle.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
    ToggleCircle.BorderSizePixel = 0
    ToggleCircle.Parent = ToggleBg

    local tcCorner = Instance.new("UICorner")
    tcCorner.CornerRadius = UDim.new(1, 0)
    tcCorner.Parent = ToggleCircle

    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 1, 0)
    Button.BackgroundTransparency = 1
    Button.Text = ""
    Button.Parent = ToggleBg

    local Character, Humanoid, RootPart
    local connRun = nil
    local walkOriginal, jumpOriginal
    local alvoAtual = nil
    local promptsConectados = setmetatable({}, {__mode = "k"})
    local executando = false

    local function AtualizarPersonagem()
        Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        Humanoid  = Character:WaitForChild("Humanoid")
        RootPart  = Character:WaitForChild("HumanoidRootPart")
    end
    task.spawn(AtualizarPersonagem)

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if connRun then connRun:Disconnect(); connRun = nil end
        alvoAtual, walkOriginal, jumpOriginal = nil, nil, nil
        task.spawn(AtualizarPersonagem)
    end)

    local function PararTeleporte()
        if connRun then connRun:Disconnect(); connRun = nil end
        if Humanoid and Humanoid.Parent then
            if walkOriginal then Humanoid.WalkSpeed = walkOriginal end
            if jumpOriginal then Humanoid.JumpPower = jumpOriginal end
        end
        alvoAtual = nil
    end

    local function TeleportarPara(posicaoAlvo, aoChegar)
        if not RootPart or not Humanoid or not RootPart.Parent then return end
        if connRun then connRun:Disconnect() end

        if not walkOriginal then walkOriginal = Humanoid.WalkSpeed end
        if not jumpOriginal then jumpOriginal = Humanoid.JumpPower end
        Humanoid.WalkSpeed = WalkSpeedFake
        Humanoid.JumpPower = JumpPowerFake
        alvoAtual = posicaoAlvo

        connRun = RunService.Heartbeat:Connect(function(dt)
            if not RootPart or not RootPart.Parent or not Humanoid.Parent then
                PararTeleporte(); return
            end
            local origem = RootPart.Position
            local delta  = alvoAtual - origem
            if IgnorarEixoY then delta = Vector3.new(delta.X, 0, delta.Z) end
            local dist = delta.Magnitude

            if dist <= DistanciaChegada then
                RootPart.CFrame = CFrame.new(alvoAtual) * (RootPart.CFrame - RootPart.Position)
                PararTeleporte()
                if aoChegar then aoChegar() end
                return
            end

            local passo   = math.min(VelocidadeRun * dt, dist)
            local direcao = delta.Unit
            local novaPos = origem + direcao * passo
            if IgnorarEixoY then
                novaPos = Vector3.new(novaPos.X, origem.Y, novaPos.Z)
            end

            local lookDir = direcao
            if lookDir.Magnitude < 0.001 then lookDir = Vector3.new(0, 0, 1) end
            RootPart.CFrame = CFrame.lookAt(novaPos, novaPos + lookDir)
        end)
    end

    local function GetSpawnLocation()
        return Workspace:FindFirstChildOfClass("SpawnLocation")
    end

    local function ConectarPrompt(prompt)
        if promptsConectados[prompt] then return end
        promptsConectados[prompt] = true

        prompt.Triggered:Connect(function()
            if not AntiBoss.ativado then return end
            if executando then return end
            if not RootPart or not RootPart.Parent then return end

            local spawn = GetSpawnLocation()
            if not spawn then return end

            pcall(function() Disfarce.iniciar() end)

            executando = true
            local posicaoSalva = RootPart.Position

            TeleportarPara(spawn.Position, function()
                task.wait(TempoNoSpawn)
                if not AntiBoss.ativado then
                    executando = false
                    pcall(function() Disfarce.limpar() end)
                    return
                end
                TeleportarPara(posicaoSalva, function()
                    executando = false
                end)
            end)
        end)
    end

    local function VerificarPart(part)
        if part.Name ~= NomeParte then return end
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Name == NomePrompt then
                ConectarPrompt(child)
            end
        end
    end

    local function EscanearTudo()
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name == NomeParte then VerificarPart(obj) end
        end
    end

    Workspace.DescendantAdded:Connect(function(obj)
        if not AntiBoss.ativado then return end
        if obj.Name == NomeParte then
            task.wait(0.05); VerificarPart(obj)
        elseif obj:IsA("ProximityPrompt") and obj.Name == NomePrompt then
            task.wait(0.05)
            local p = obj.Parent
            while p and p ~= Workspace do
                if p.Name == NomeParte then ConectarPrompt(obj); break end
                p = p.Parent
            end
        end
    end)

    local TweenInfoToggle = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function SetAtivado(valor)
        AntiBoss.ativado = valor
        if valor then
            TweenService:Create(ToggleBg, TweenInfoToggle, {BackgroundColor3 = VERDE}):Play()
            TweenService:Create(ToggleCircle, TweenInfoToggle, {Position = UDim2.new(1, -24, 0.5, -11)}):Play()
            EscanearTudo()
            Toast("Anti-Boss ON", VERDE)
        else
            TweenService:Create(ToggleBg, TweenInfoToggle, {BackgroundColor3 = Color3.fromRGB(40, 40, 50)}):Play()
            TweenService:Create(ToggleCircle, TweenInfoToggle, {Position = UDim2.new(0, 2, 0.5, -11)}):Play()
            PararTeleporte()
            pcall(function() Disfarce.limpar() end)
            executando = false
            Toast("Anti-Boss OFF", AMARELO)
        end
    end

    Button.MouseButton1Click:Connect(function()
        SetAtivado(not AntiBoss.ativado)
    end)

    AntiBoss.gui = ScreenGui
    return ScreenGui
end

local function toggleAntiBoss()
    if not AntiBoss.gui then
        criarAntiBossGui()
    end
    AntiBoss.aberto = not AntiBoss.aberto
    AntiBoss.gui.Enabled = AntiBoss.aberto
    if AntiBoss.aberto then
        Toast("Painel Anti-Boss ON", VERDE)
    else
        Toast("Painel Anti-Boss OFF", AMARELO)
    end
end

-- PAINEL FLUTUANTE (TP-EGG)
local PainelFlutuante = { gui = nil, aberto = false }

local function criarPainelFlutuante()
    if PainelFlutuante.gui then return PainelFlutuante.gui end

    local RESPAWN_WAIT = 2

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TweenTPPanel"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 50
    screenGui.Enabled = false
    screenGui.Parent = PlayerGui

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 280, 0, 118)
    panel.Position = UDim2.new(0, 20, 0, 100)
    panel.BackgroundColor3 = BG_BTN
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Draggable = true
    panel.Parent = screenGui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", panel)
    stroke.Color = ROXO_DARK
    stroke.Thickness = 1

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 20)
    title.Position = UDim2.new(0, 12, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "TP  •  Nests (loop)"
    title.TextColor3 = TXT
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local toggleBg = Instance.new("Frame")
    toggleBg.Size = UDim2.new(0, 50, 0, 26)
    toggleBg.Position = UDim2.new(0, 15, 0, 30)
    toggleBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    toggleBg.BorderSizePixel = 0
    toggleBg.Active = true
    toggleBg.Parent = panel
    Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 22, 0, 22)
    knob.Position = UDim2.new(0, 2, 0, 2)
    knob.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
    knob.BorderSizePixel = 0
    knob.Parent = toggleBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 100, 0, 20)
    statusLabel.Position = UDim2.new(0, 80, 0, 33)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "OFF"
    statusLabel.TextColor3 = VERMELHO
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 14
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = panel

    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(0, 90, 0, 26)
    testBtn.Position = UDim2.new(1, -100, 0, 30)
    testBtn.BackgroundColor3 = ROXO
    testBtn.BorderSizePixel = 0
    testBtn.Text = "TP TESTE"
    testBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testBtn.Font = Enum.Font.GothamBold
    testBtn.TextSize = 12
    testBtn.Parent = panel
    Instance.new("UICorner", testBtn).CornerRadius = UDim.new(0, 6)

    local footerHolder = Instance.new("Frame")
    footerHolder.Size = UDim2.new(1, -20, 0, 52)
    footerHolder.Position = UDim2.new(0, 10, 0, 62)
    footerHolder.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    footerHolder.BorderSizePixel = 0
    footerHolder.Parent = panel
    Instance.new("UICorner", footerHolder).CornerRadius = UDim.new(0, 6)

    local footerScroll = Instance.new("ScrollingFrame")
    footerScroll.Size = UDim2.new(1, -8, 1, -8)
    footerScroll.Position = UDim2.new(0, 4, 0, 4)
    footerScroll.BackgroundTransparency = 1
    footerScroll.BorderSizePixel = 0
    footerScroll.ScrollBarThickness = 3
    footerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    footerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    footerScroll.ScrollBarImageColor3 = TXT_DIM
    footerScroll.Parent = footerHolder

    local footerList = Instance.new("UIListLayout")
    footerList.Padding = UDim.new(0, 1)
    footerList.SortOrder = Enum.SortOrder.LayoutOrder
    footerList.Parent = footerScroll

    local MAX_LINES = 30
    local lineCount = 0

    local function log(msg, color)
        lineCount += 1
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 12)
        lbl.BackgroundTransparency = 1
        lbl.Text = "• " .. tostring(msg)
        lbl.TextColor3 = color or TXT_DIM
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.LayoutOrder = lineCount
        lbl.Parent = footerScroll
        footerScroll.CanvasPosition = Vector2.new(0, math.huge)
        local labels = {}
        for _, c in ipairs(footerScroll:GetChildren()) do
            if c:IsA("TextLabel") then table.insert(labels, c) end
        end
        if #labels > MAX_LINES then
            table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
            labels[1]:Destroy()
        end
    end

    log("Script carregado.", VERDE)

    local enabled = false

    local function findNests()
        local guardAreas
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "GuardAreas" then guardAreas = d break end
        end
        if not guardAreas then
            log("GuardAreas NAO encontrado.", VERMELHO)
            return nil
        end
        local forest
        for _, d in ipairs(guardAreas:GetDescendants()) do
            if d.Name == "Forest" then forest = d break end
        end
        if not forest then
            log("Forest NAO encontrado.", VERMELHO)
            return nil
        end
        local nests = forest:FindFirstChild("Nests")
        if not nests then
            for _, d in ipairs(forest:GetDescendants()) do
                if d.Name == "Nests" then nests = d break end
            end
        end
        if not nests then
            log("Nests NAO encontrado.", VERMELHO)
            return nil
        end
        return nests
    end

    local function getNestsPosition(doLog)
        local nests = findNests()
        if not nests then return nil end
        local pos
        if nests:IsA("Model") then
            local ok, cf, size = pcall(function() return nests:GetBoundingBox() end)
            if ok and cf and size then
                local topY = cf.Position.Y + (size.Y / 2) + 4
                pos = Vector3.new(cf.Position.X, topY, cf.Position.Z)
            else
                local pp = nests.PrimaryPart or nests:FindFirstChildWhichIsA("BasePart", true)
                if pp then pos = pp.Position + Vector3.new(0, pp.Size.Y/2 + 4, 0) end
            end
        elseif nests:IsA("BasePart") then
            pos = nests.Position + Vector3.new(0, nests.Size.Y/2 + 4, 0)
        end
        if not pos then
            if doLog then log("Nests sem posicao.", VERMELHO) end
            return nil
        end
        if doLog then
            log(string.format("Destino: %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z), AMARELO)
        end
        return pos
    end

    local function isSmartPrompt(prompt)
        if not prompt or not prompt.Parent then return false end
        if prompt.Name == "CarryAreaEgg" then return true end
        if prompt.Parent.Name == "SmartPromptPart" then return true end
        local p, depth = prompt.Parent, 0
        while p and p ~= Workspace and depth < 15 do
            if p.Name == "SmartPromptPart" then return true end
            p = p.Parent
            depth += 1
        end
        return false
    end

    local loopConn  = nil
    local cachedPos = nil

    local function stopLoop()
        if loopConn then
            loopConn:Disconnect()
            loopConn = nil
            log("Loop parado.", AMARELO)
        end
    end

    local function startLoop()
        stopLoop()
        cachedPos = getNestsPosition(true)
        if not cachedPos then return end

        log("Loop iniciado.", VERDE)

        loopConn = RunService.Heartbeat:Connect(function()
            if not enabled then
                stopLoop()
                return
            end
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and cachedPos then
                hrp.CFrame = CFrame.new(cachedPos) * (hrp.CFrame - hrp.CFrame.Position)
            end
        end)
    end

    local function setToggle(state)
        enabled = state
        if state then
            TweenService:Create(toggleBg, TweenInfo.new(0.2), {BackgroundColor3 = VERDE}):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), {Position = UDim2.new(1, -24, 0, 2)}):Play()
            statusLabel.Text = "ON"
            statusLabel.TextColor3 = VERDE
            log("Ativado.", VERDE)
        else
            TweenService:Create(toggleBg, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(40, 40, 50)}):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), {Position = UDim2.new(0, 2, 0, 2)}):Play()
            statusLabel.Text = "OFF"
            statusLabel.TextColor3 = VERMELHO
            stopLoop()
            log("Desativado.", LARANJA)
        end
    end

    toggleBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            setToggle(not enabled)
        end
    end)

    local function doTeleport(withLoop)
        cachedPos = getNestsPosition(true)
        if not cachedPos then return end

        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            log("Sem HRP.", VERMELHO)
            return
        end

        hrp.CFrame = CFrame.new(cachedPos) * (hrp.CFrame - hrp.CFrame.Position)
        log("TP feito.", VERDE)

        if withLoop then
            startLoop()
        end
    end

    local function tryTeleport(prompt, triggeringPlayer)
        log("Prompt disparou: " .. (prompt and prompt.Name or "?"), TXT)
        if not enabled then return end
        if triggeringPlayer and triggeringPlayer ~= LocalPlayer then return end
        if not isSmartPrompt(prompt) then
            log("Nao e SmartPrompt. Ignorando.", AMARELO)
            return
        end
        doTeleport(true)
    end

    local watched = setmetatable({}, {__mode = "k"})

    local function watchPrompt(prompt)
        if watched[prompt] then return end
        watched[prompt] = true
        prompt.Triggered:Connect(function(triggeringPlayer)
            tryTeleport(prompt, triggeringPlayer)
        end)
    end

    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then watchPrompt(d) end
    end

    Workspace.DescendantAdded:Connect(function(d)
        if d:IsA("ProximityPrompt") then watchPrompt(d) end
    end)

    ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
        tryTeleport(prompt, triggeringPlayer)
    end)
    ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, triggeringPlayer)
        tryTeleport(prompt, triggeringPlayer)
    end)

    testBtn.MouseButton1Click:Connect(function()
        log("TP TESTE clicado.", AZUL)
        doTeleport(true)
    end)

    local lastDeathCFrame = nil

    local function hookCharacter(char)
        local humanoid = char:WaitForChild("Humanoid", 10)
        if not humanoid then return end
        humanoid.Died:Connect(function()
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                lastDeathCFrame = hrp.CFrame
                log(string.format("Morreu em %.1f, %.1f, %.1f",
                    lastDeathCFrame.Position.X,
                    lastDeathCFrame.Position.Y,
                    lastDeathCFrame.Position.Z), VERMELHO)
            end
            stopLoop()
        end)
    end

    LocalPlayer.CharacterAdded:Connect(function(char)
        hookCharacter(char)
        if not enabled or not lastDeathCFrame then return end
        local savedCF = lastDeathCFrame

        task.spawn(function()
            task.wait(RESPAWN_WAIT)
            local hrp = char:WaitForChild("HumanoidRootPart", 5)
            if not hrp then return end
            if hrp.Parent then
                hrp.CFrame = savedCF
                log("Respawn reposicionado (sem loop).", VERDE)
            end
        end)
    end)

    if LocalPlayer.Character then
        hookCharacter(LocalPlayer.Character)
    end

    log("Pronto. Prompts monitorados.", VERDE)

    PainelFlutuante.gui = screenGui
    return screenGui
end

local function togglePainelFlutuante()
    if not PainelFlutuante.gui then
        criarPainelFlutuante()
    end
    PainelFlutuante.aberto = not PainelFlutuante.aberto
    PainelFlutuante.gui.Enabled = PainelFlutuante.aberto
    if PainelFlutuante.aberto then
        Toast("TP-EGG ON", VERDE)
    else
        Toast("TP-EGG OFF", AMARELO)
    end
end

-- PAINEL OVO INVISÍVEL
local OvoInvisivel = { aberto = false, ativo = false, gui = nil }

local function isOvo(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local uid = tool:GetAttribute("UID")
    local it  = tool:GetAttribute("ItemType")
    return uid or it == "Egg" or tool.Name:lower():find("egg")
end

local function aplicarInvisibilidadeTool(tool)
    if not tool or not tool.Parent then return end
    for _, d in ipairs(tool:GetDescendants()) do
        pcall(function()
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 1
                d.Transparency = 1
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = false
            elseif d:IsA("Decal") or d:IsA("Texture") then
                d.Transparency = 1
            elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d.Enabled = false
            elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
                d.Enabled = false
            elseif d:IsA("Highlight") then
                d.Enabled = false
            elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
                d.Enabled = false
            elseif d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
                d.Enabled = false
            end
        end)
    end
end

local function restaurarInvisibilidadeTool(tool)
    if not tool or not tool.Parent then return end
    for _, d in ipairs(tool:GetDescendants()) do
        pcall(function()
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 0
                d.Transparency = 0
            elseif d:IsA("Decal") or d:IsA("Texture") then
                d.Transparency = 0
            elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
                d.Enabled = true
            elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
                d.Enabled = true
            elseif d:IsA("Highlight") then
                d.Enabled = true
            elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
                d.Enabled = true
            elseif d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
                d.Enabled = true
            end
        end)
    end
end

local function aplicarInvisibilidadeOvo()
    if not OvoInvisivel.ativo then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, t in ipairs(char:GetChildren()) do
        if isOvo(t) then
            aplicarInvisibilidadeTool(t)
        end
    end
end

local function hookOvo(child)
    if not OvoInvisivel.ativo then return end
    if isOvo(child) then
        task.wait(0.05)
        aplicarInvisibilidadeTool(child)
    end
end

local function criarOvoInvisivelGui()
    if OvoInvisivel.gui then return OvoInvisivel.gui end

    local frame = Instance.new("Frame")
    frame.Name = "OvoInvisivelPanel"
    frame.Size = UDim2.new(0, 220, 0, 60)
    frame.Position = UDim2.new(0.5, -110, 0.85, 0)
    frame.BackgroundColor3 = BG_BTN
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Visible = false
    frame.ZIndex = 50
    frame.Parent = gui

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = ROXO_DARK
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Ovo Invisível"
    title.TextColor3 = TXT
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local switchTrack = Instance.new("TextButton")
    switchTrack.Size = UDim2.new(0, 50, 0, 26)
    switchTrack.Position = UDim2.new(1, -65, 0.5, 0)
    switchTrack.AnchorPoint = Vector2.new(0, 0.5)
    switchTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    switchTrack.BorderSizePixel = 0
    switchTrack.Text = ""
    switchTrack.AutoButtonColor = false
    switchTrack.Parent = frame
    Instance.new("UICorner", switchTrack).CornerRadius = UDim.new(1, 0)

    local switchBall = Instance.new("Frame")
    switchBall.Size = UDim2.new(0, 20, 0, 20)
    switchBall.Position = UDim2.new(0, 3, 0.5, 0)
    switchBall.AnchorPoint = Vector2.new(0, 0.5)
    switchBall.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
    switchBall.BorderSizePixel = 0
    switchBall.Parent = switchTrack
    Instance.new("UICorner", switchBall).CornerRadius = UDim.new(1, 0)

    local function animarSwitch(ligado)
        OvoInvisivel.ativo = ligado

        local posAlvo   = ligado and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local corTrilho = ligado and VERDE or Color3.fromRGB(40, 40, 50)
        local corBola   = ligado and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(230, 230, 230)

        local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        TweenService:Create(switchBall,  ti, { Position = posAlvo,   BackgroundColor3 = corBola   }):Play()
        TweenService:Create(switchTrack, ti, { BackgroundColor3 = corTrilho }):Play()

        local char = LocalPlayer.Character
        if char then
            for _, t in ipairs(char:GetChildren()) do
                if isOvo(t) then
                    if ligado then
                        aplicarInvisibilidadeTool(t)
                    else
                        restaurarInvisibilidadeTool(t)
                    end
                end
            end
        end

        Toast(ligado and "Ovo Invisível ON" or "Ovo Invisível OFF",
              ligado and VERDE or AMARELO)
    end

    switchTrack.MouseButton1Click:Connect(function()
        animarSwitch(not OvoInvisivel.ativo)
    end)

    OvoInvisivel.gui = frame
    OvoInvisivel.animarSwitch = animarSwitch
    return frame
end

local function toggleOvoInvisivel()
    if not OvoInvisivel.gui then
        criarOvoInvisivelGui()
    end
    OvoInvisivel.aberto = not OvoInvisivel.aberto
    OvoInvisivel.gui.Visible = OvoInvisivel.aberto
    if OvoInvisivel.aberto then
        Toast("Painel Ovo Invisível ON", VERDE)
    else
        Toast("Painel Ovo Invisível OFF", AMARELO)
    end
end

local function onCharOvo(char)
    task.wait(0.5)
    char.ChildAdded:Connect(hookOvo)
    if OvoInvisivel.ativo then
        aplicarInvisibilidadeOvo()
    end
end

if LocalPlayer.Character then
    onCharOvo(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharOvo)

task.spawn(function()
    while gui.Parent do
        task.wait(0.03)
        if OvoInvisivel.ativo then
            pcall(aplicarInvisibilidadeOvo)
        end
    end
end)

-- Faixa base + rodapé
local faixaBase = Instance.new("Frame")
faixaBase.Size = UDim2.new(1, -16, 0, 2)
faixaBase.Position = UDim2.new(0, 8, 1, -26)
faixaBase.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
faixaBase.BorderSizePixel = 0
faixaBase.ZIndex = 3
faixaBase.Parent = menu
local gradBase = Instance.new("UIGradient")
gradBase.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1),
    NumberSequenceKeypoint.new(0.20, 0),
    NumberSequenceKeypoint.new(0.80, 0),
    NumberSequenceKeypoint.new(1.00, 1),
})
gradBase.Color = ColorSequence.new(ROXO, Color3.fromRGB(200, 200, 200))
gradBase.Parent = faixaBase

local rodape = Instance.new("Frame")
rodape.Size = UDim2.new(1, 0, 0, 20)
rodape.Position = UDim2.new(0, 0, 1, -23)
rodape.BackgroundTransparency = 1
rodape.ZIndex = 3
rodape.Parent = menu

local ledRodape = Instance.new("Frame")
ledRodape.Size = UDim2.new(0, 6, 0, 6)
ledRodape.Position = UDim2.new(0, 10, 0, 7)
ledRodape.BackgroundColor3 = VERMELHO
ledRodape.BorderSizePixel = 0
ledRodape.ZIndex = 4
ledRodape.Parent = rodape
Instance.new("UICorner", ledRodape).CornerRadius = UDim.new(1, 0)

local labelStatus = Instance.new("TextLabel")
labelStatus.Size = UDim2.new(1, -26, 1, 0)
labelStatus.Position = UDim2.new(0, 22, 0, 0)
labelStatus.BackgroundTransparency = 1
labelStatus.Font = Enum.Font.GothamBold
labelStatus.TextSize = 9
labelStatus.TextColor3 = TXT
labelStatus.TextXAlignment = Enum.TextXAlignment.Left
labelStatus.Text = "STATUS: INATIVO"
labelStatus.ZIndex = 4
labelStatus.Parent = rodape

-- MINIMIZAR
local corpoPainel = { faixaTopo, tabBarHolder, containerFunc, containerTps, containerHop, containerSteal, faixaBase, rodape }
local minimizado = false
local tamanhoNormal = UDim2.new(0, 340, 0, 260)
local tamanhoMin    = UDim2.new(0, 200, 0, 36)

btnMin.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        for _, obj in ipairs(corpoPainel) do obj.Visible = false end
        btnMin.Text = "□"
    else
        for _, obj in ipairs(corpoPainel) do obj.Visible = true end
        btnMin.Text = "—"
        atualizarAbas()
    end

    local posAtual = holder.AbsolutePosition
    local tamAtual = holder.AbsoluteSize
    local centroX  = posAtual.X + tamAtual.X / 2

    local novoTam = minimizado and tamanhoMin or tamanhoNormal
    local novoX   = centroX - novoTam.X.Offset / 2

    TweenService:Create(holder, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
        Size = novoTam,
        Position = UDim2.new(0, novoX, holder.Position.Y.Scale, holder.Position.Y.Offset),
    }):Play()
end)

-- Callbacks
btnAnti.MouseButton1Click:Connect(function()
    bounceAnti()
    toggleAntiBoss()
end)

btnTrap.MouseButton1Click:Connect(function()
    bounceTrap()
    AntiTrap.toggle()
end)

btnKB.MouseButton1Click:Connect(function()
    bounceKB()
    AntiKB = not AntiKB
    if AntiKB then
        Toast("Anti-KB ON", VERDE)
    else
        ultimaPosKB = nil
        Toast("Anti-KB OFF", AMARELO)
    end
end)

btnDst.MouseButton1Click:Connect(function()
    bounceDst()
    if not Teleporte.refs() then return end
    Destino.posicao   = Teleporte.root.Position
    Destino.usarSpawn = false
end)

btnReset.MouseButton1Click:Connect(function()
    bounceReset()
    Destino.posicao   = nil
    Destino.usarSpawn = true
end)

btnFlutuante.MouseButton1Click:Connect(function()
    bounceFlutuante()
    togglePainelFlutuante()
end)

btnOvoInv.MouseButton1Click:Connect(function()
    bounceOvoInv()
    toggleOvoInvisivel()
end)

btnTpArea2.MouseButton1Click:Connect(function()
    executarTpAreaIntegrado(
        AreaSelecionada,
        function(txt, cor)
            statusAreaLbl.Text = txt
            statusAreaLbl.TextColor3 = cor
        end,
        function(txt, cor)
            btnTpArea2.Text = txt
            btnTpArea2.BackgroundColor3 = cor
        end
    )
end)

UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.T then
        toggleAntiBoss()
    elseif i.KeyCode == Enum.KeyCode.H then
        AntiKB = not AntiKB
        if AntiKB then Toast("Anti-KB ON", VERDE)
        else ultimaPosKB = nil Toast("Anti-KB OFF", AMARELO) end
    elseif i.KeyCode == Enum.KeyCode.P then
        togglePainelFlutuante()
    end
end)

-- Loops visuais
task.spawn(function()
    while gui.Parent do
        for rot = 0, 360, 6 do
            if not gui.Parent then break end
            gradBorda.Rotation = rot
            task.wait(0.03)
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        TweenService:Create(ledHeader, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {
            BackgroundTransparency = 0.4,
            Size = UDim2.new(0, 5, 0, 5),
            Position = UDim2.new(0, 10, 0, 15),
        }):Play()
        task.wait(0.6)
        if not gui.Parent then break end
        TweenService:Create(ledHeader, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {
            BackgroundTransparency = 0,
            Size = UDim2.new(0, 6, 0, 6),
            Position = UDim2.new(0, 10, 0, 15),
        }):Play()
        task.wait(0.6)
    end
end)

task.spawn(function()
    while gui.Parent do
        if AntiBoss.aberto then
            contAnti.BackgroundColor3     = Color3.fromRGB(15, 40, 20)
            barraAnti.BackgroundColor3    = VERDE
            bordaAnti.Color               = VERDE
            labelAnti.TextColor3          = Color3.fromRGB(180, 255, 200)
            setaAnti.TextColor3           = VERDE
            labelAnti.Text                = "🥚 ANTI-BOSS  [ON]"
        else
            contAnti.BackgroundColor3     = BG_BTN
            barraAnti.BackgroundColor3    = ROXO
            bordaAnti.Color               = ROXO_DARK
            labelAnti.TextColor3          = TXT
            setaAnti.TextColor3           = ROXO
            labelAnti.Text                = "🥚 ANTI-BOSS"
        end

        if AntiTrap.ativo then
            contTrap.BackgroundColor3     = Color3.fromRGB(40, 15, 20)
            barraTrap.BackgroundColor3    = VERMELHO
            bordaTrap.Color               = VERMELHO
            labelTrap.TextColor3          = Color3.fromRGB(255, 190, 200)
            setaTrap.TextColor3           = VERMELHO
            labelTrap.Text                = "🚫 ANTI-TRAP  [ON]"
        else
            contTrap.BackgroundColor3     = BG_BTN
            barraTrap.BackgroundColor3    = ROXO
            bordaTrap.Color               = ROXO_DARK
            labelTrap.TextColor3          = TXT
            setaTrap.TextColor3           = ROXO
            labelTrap.Text                = "🚫 ANTI-TRAP"
        end

        if AntiKB then
            contKB.BackgroundColor3       = Color3.fromRGB(15, 40, 20)
            barraKB.BackgroundColor3      = VERDE
            bordaKB.Color                 = VERDE
            labelKB.TextColor3            = Color3.fromRGB(180, 255, 200)
            setaKB.TextColor3             = VERDE
            labelKB.Text                  = "💫 ANTI-KNOCKBACK  [ON]"
        else
            contKB.BackgroundColor3       = BG_BTN
            barraKB.BackgroundColor3      = ROXO
            bordaKB.Color                 = ROXO_DARK
            labelKB.TextColor3            = TXT
            setaKB.TextColor3             = ROXO
            labelKB.Text                  = "💫 ANTI-KNOCKBACK"
        end

        if Destino.usarSpawn then
            contDst.BackgroundColor3      = BG_BTN
            barraDst.BackgroundColor3     = ROXO
            bordaDst.Color                = ROXO_DARK
            labelDst.TextColor3           = TXT
            labelDst.Text                 = "📍 DEFINIR DESTINO"
        else
            contDst.BackgroundColor3      = Color3.fromRGB(15, 30, 40)
            barraDst.BackgroundColor3     = AZUL
            bordaDst.Color                = AZUL
            labelDst.TextColor3           = Color3.fromRGB(180, 230, 255)
            labelDst.Text                 = "✅ DESTINO SALVO"
        end

        if PainelFlutuante.aberto then
            contFlutuante.BackgroundColor3   = Color3.fromRGB(15, 40, 20)
            barraFlutuante.BackgroundColor3  = VERDE
            bordaFlutuante.Color             = VERDE
            labelFlutuante.TextColor3        = Color3.fromRGB(180, 255, 200)
            setaFlutuante.TextColor3         = VERDE
            labelFlutuante.Text              = "🌌 TP-EGG  [ON]"
        else
            contFlutuante.BackgroundColor3   = BG_BTN
            barraFlutuante.BackgroundColor3  = ROXO
            bordaFlutuante.Color             = ROXO_DARK
            labelFlutuante.TextColor3        = TXT
            setaFlutuante.TextColor3         = ROXO
            labelFlutuante.Text              = "🌌 TP-EGG"
        end

        if OvoInvisivel.aberto then
            contOvoInv.BackgroundColor3    = Color3.fromRGB(15, 40, 20)
            barraOvoInv.BackgroundColor3   = VERDE
            bordaOvoInv.Color              = VERDE
            labelOvoInv.TextColor3         = Color3.fromRGB(180, 255, 200)
            setaOvoInv.TextColor3          = VERDE
            labelOvoInv.Text               = "🫥 OVO INVISÍVEL  [ON]"
        else
            contOvoInv.BackgroundColor3    = BG_BTN
            barraOvoInv.BackgroundColor3   = ROXO
            bordaOvoInv.Color              = ROXO_DARK
            labelOvoInv.TextColor3         = TXT
            setaOvoInv.TextColor3          = ROXO
            labelOvoInv.Text               = "🫥 OVO INVISÍVEL"
        end

        if AntiBoss.ativado and not (Teleporte.ativo or Disfarce.ativo) then
            ledRodape.BackgroundColor3    = VERDE
            labelStatus.TextColor3        = VERDE
            labelStatus.Text              = "STATUS: ANTI-BOSS ATIVO"
        elseif Teleporte.ativo or Disfarce.ativo then
            ledRodape.BackgroundColor3    = LARANJA
            labelStatus.TextColor3        = LARANJA
            labelStatus.Text              = "STATUS: TELEPORTANDO..."
        elseif AntiTrap.ativo then
            ledRodape.BackgroundColor3    = VERMELHO
            labelStatus.TextColor3        = VERMELHO
            labelStatus.Text              = "STATUS: ANTI-TRAP ON"
        elseif AntiKB then
            ledRodape.BackgroundColor3    = AZUL
            labelStatus.TextColor3        = AZUL
            labelStatus.Text              = "STATUS: ANTI-KB ON"
        else
            ledRodape.BackgroundColor3    = VERMELHO
            labelStatus.TextColor3        = TXT
            labelStatus.Text              = "STATUS: INATIVO"
        end

        task.wait(0.15)
    end
end)

atualizarAbas()

-- BYPASS (Humanoid swap)
do
    local BypassProps = {
        "WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower",
        "MaxHealth", "Health",
        "AutoRotate", "AutoJumpEnabled", "BreakJointsOnDeath",
        "CameraOffset", "DisplayDistanceType",
        "HealthDisplayDistance", "HealthDisplayType",
        "NameDisplayDistance", "NameOcclusion",
        "RequiresNeck", "WalkJumpPower", "HipHeight",
        "RigType", "WalkSpeedCheck", "EvaluateStateMachine",
        "MaxSlopeAngle", "AutomaticScalingEnabled",
    }

    local StateEnums = {
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.GettingUp,
        Enum.HumanoidStateType.Landed,
        Enum.HumanoidStateType.Flying,
        Enum.HumanoidStateType.Freefall,
        Enum.HumanoidStateType.Seated,
        Enum.HumanoidStateType.PlatformStanding,
        Enum.HumanoidStateType.Dead,
        Enum.HumanoidStateType.Physics,
        Enum.HumanoidStateType.Climbing,
        Enum.HumanoidStateType.Swimming,
        Enum.HumanoidStateType.Running,
        Enum.HumanoidStateType.RunningNoPhysics,
        Enum.HumanoidStateType.StrafingNoPhysics,
        Enum.HumanoidStateType.Jumping,
    }

    local BypassState = {
        Enabled    = false,
        InProgress = false,
        Clone      = nil,
    }

    local function copiarProps(orig, clone)
        for _, prop in ipairs(BypassProps) do
            pcall(function()
                local ok, value = pcall(function() return orig[prop] end)
                if ok and value ~= nil then
                    pcall(function() clone[prop] = value end)
                end
            end)
        end
        pcall(function()
            for k, v in pairs(orig:GetAttributes()) do
                pcall(function() clone:SetAttribute(k, v) end)
            end
        end)
        pcall(function()
            local desc = orig:FindFirstChildOfClass("HumanoidDescription")
            if desc then
                local dc = desc:Clone()
                dc.Parent = clone
            end
        end)
    end

    local function capturarEstados(hum)
        local states = {}
        for _, s in ipairs(StateEnums) do
            local ok, en = pcall(function() return hum:GetStateEnabled(s) end)
            if ok then states[s] = en end
        end
        local cur
        pcall(function() cur = hum:GetState() end)
        return states, cur
    end

    local function reaplicarEstados(hum, states, cur)
        for s, en in pairs(states or {}) do
            pcall(function() hum:SetStateEnabled(s, en) end)
        end
        if cur then
            pcall(function() hum:ChangeState(cur) end)
        end
    end

    local function aplicarBypass(character)
        if BypassState.InProgress then return false end
        BypassState.InProgress = true

        character = character or LocalPlayer.Character
        if not character then
            BypassState.InProgress = false
            return false
        end

        local origHum = character:FindFirstChildOfClass("Humanoid")
        if not origHum then
            pcall(function() origHum = character:WaitForChild("Humanoid", 10) end)
        end
        if not origHum then
            BypassState.InProgress = false
            return false
        end

        local cloneHum
        local okClone = pcall(function() cloneHum = origHum:Clone() end)
        if not okClone or not cloneHum then
            BypassState.InProgress = false
            return false
        end

        local animatorMoved = false
        local animator = origHum:FindFirstChildOfClass("Animator")
        if animator then
            local ok = pcall(function() animator.Parent = cloneHum end)
            animatorMoved = ok
        end

        copiarProps(origHum, cloneHum)
        local states, cur = capturarEstados(origHum)

        pcall(function() cloneHum.Name = "Humanoid" end)
        local okParent = pcall(function() cloneHum.Parent = character end)
        if not okParent then
            if animatorMoved and animator and animator.Parent ~= origHum then
                pcall(function() animator.Parent = origHum end)
            end
            BypassState.InProgress = false
            return false
        end

        task.wait(0.05)
        local okDestroy = pcall(function() origHum:Destroy() end)
        if not okDestroy then
            pcall(function() cloneHum:Destroy() end)
            if animatorMoved and animator and animator.Parent ~= origHum then
                pcall(function() animator.Parent = origHum end)
            end
            BypassState.InProgress = false
            return false
        end

        task.wait(0.05)
        pcall(function()
            if Workspace.CurrentCamera then
                Workspace.CurrentCamera.CameraSubject = cloneHum
            end
        end)
        reaplicarEstados(cloneHum, states, cur)
        pcall(function()
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Parent = character end
        end)

        BypassState.Clone      = cloneHum
        BypassState.InProgress = false
        return true
    end

    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.3)
        if BypassState.Enabled then
            aplicarBypass(char)
        end
    end)

    btnBypass.MouseButton1Click:Connect(function()
        bounceBypass()
        if BypassState.Enabled then return end
        BypassState.Enabled = true
        contBypass.BackgroundColor3  = Color3.fromRGB(40, 15, 20)
        barraBypass.BackgroundColor3 = VERMELHO
        bordaBypass.Color            = VERMELHO
        labelBypass.TextColor3       = Color3.fromRGB(255, 190, 200)
        setaBypass.TextColor3        = VERMELHO
        labelBypass.Text             = "🔥 BYPASS  [ON]"
        Toast("Bypass aplicado", VERMELHO)
        aplicarBypass(LocalPlayer.Character)
    end)
end

local function iniciarSistemaYslemEgg()
-- yslemEgg | Instant TP
-- Pick a pet (icon + value), press Steal. Dodge full: the player stays frozen where they stand, the body (the clown) jumps from the base onto the egg,
-- plants a clown, takes the egg, drops it, visits the treadmill, comes back through the clown and delivers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer



------------------------------------------------------------------ settings
local CFG = {
	SpeedCap = 1.15, -- never above 115% of the walk speed
	HopRatio = 1.515, -- hop distance = walk speed * ratio (a distance, not a speed)
	HopMin = 40,
	HopGap = 0.06, -- seconds between two hops (learned: grows after a pull-back, shrinks after a clean hop)
	HopGapMin = 0.06,
	HopGapMax = 0.2,
	HopRetries = 6,
	HopLift = 42, -- height of the hops above the start
	DimStep = 40, -- inside the Halloween dimension a teleport is a step of 40 studs per frame
	LandOffset = 14, -- landing spot in front of the line
	LandSettle = 0.08,
	DropDelay = 0.05,
	GrabInterval = 0.03,
	RegrabFar = 40, -- egg further than this: teleport onto it, otherwise run to it
	Height = 70, -- the safe-zone run starts above the base and comes down
	ClimbShare = 0.5,
	CarryRatio = 0.9,
	EasyRatio = 1.3,
}

-- Method: Relay: the drop lane (randomised a little each time) and the safe-zone point where the egg is banked
local RELAY_DROP = Vector3.new(554.071, 70.276, -395.573)
local RELAY_JITTER = 16
local RELAY_STEP = 500
local RELAY_LIFT = 40
local RELAY_GAP_MIN = 0.14
local RELAY_GAP_MAX = 0.16
local RELAY_PACE_RATIO = 7.5
local RELAY_SAFE = Vector3.new(542.93, 71.5, -405.58)
local PRE_GRAB_DELAY = 1.5
local RUN_RATIO = 1.05
local FIRST_HIT_WAIT = 1.4
local DODGE_LANE_Z = -382
local DODGE_Y = 152
local DODGE_DROP_POINT = Vector3.new(659.17, 70.83, -419.78)
local DODGE_BURST_STUDS = 855
local DODGE_BURST_SPEED = 5500
local DODGE_CRUISE_SPEED = 2200
local DODGE_DESCENT_STUDS = 120
local DODGE_DROP_WAIT = 0.2
local DODGE_MIN_DROP = 2.5
local DODGE_REGRAB_WAIT = 1.04
local DODGE_BASE = Vector3.new(540.4, 70.8, -383.3)
local DODGE_TRIP = Vector3.new(5846.0, 17010.1, 15699.4)
local DODGE_TRIP_HOLD = 0.15
local DODGE_R1_WAIT = 1.2
local DODGE_R2_WAIT = 1.6
local DODGE_PICK_DELAY = 0.35
local ISLAND_BACK = 2
local ISLANDS = {
	{ "Forest", 600, 661 },
	{ "Lake", 722, 811 },
	{ "Desert", 901, 1013 },
	{ "Jungle", 1125, 1265 },
	{ "Snow", 1405, 1582 },
	{ "Volcano", 1759, 1962 },
	{ "Abyss Ocean", 2166, 2400 },
	{ "Prehistoric", 2634, 2920 },
	{ "Cosmic", 3207, 3567 },
	{ "Cherry Blossom", 3928, 4170 },
	{ "Titan Temple", 4411, 5129 },
	{ "Light Dark", 5577, 6000 },
	{ "Enchanted Forest", 6524, math.huge },
}


------------------------------------------------------------------ game handles
local function safeRequire(getter)
	local ok, result = pcall(function()
		return require(getter())
	end)
	return ok and result or nil
end

local networkingFolder = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Networking")
local EggState = safeRequire(function() return ReplicatedStorage.Client.EggState end)
local Assets = safeRequire(function() return ReplicatedStorage.Data.Assets end)
local Mutations = safeRequire(function() return ReplicatedStorage.Shared.Modules.Mutations end)

local function remote(name)
	return networkingFolder:FindFirstChild(name)
end

local function root()
	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- "Humanoid Swap" (the default shield): the character runs on a copy of its humanoid,
-- the original is kept out of the character while we steal.
local shield = { Original = nil, Clone = nil, Links = {}, Connection = nil, Added = nil }

local function walkSpeed()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local speed = humanoid and humanoid.WalkSpeed or 16
	if shield.Original and shield.Original.Health > 0 then
		speed = math.min(speed, shield.Original.WalkSpeed)
	end
	local ok, result = pcall(function()
		local stat = localPlayer:FindFirstChild("leaderstats")
		stat = stat and stat:FindFirstChild("Speed")
		local util = require(ReplicatedStorage.Shared.Util.TreadmillUtil)
		return stat and util.SpeedPowerToWalkSpeed(stat.Value) or nil
	end)
	if ok and type(result) == "number" and result > 0 then
		speed = math.min(speed, result)
	end
	return speed
end

local function shieldControls(humanoid)
	pcall(function()
		local scripts = localPlayer:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module then
			local controls = require(module):GetControls()
			if type(controls) == "table" then
				controls.humanoid = humanoid
			end
		end
	end)
end

local function shieldAnimate(character)
	local animate = character and character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		task.spawn(function()
			animate.Enabled = false
			task.wait()
			animate.Enabled = true
		end)
	end
end

local function shieldUnlink()
	for _, link in ipairs(shield.Links) do
		pcall(function()
			link:Disconnect()
		end)
	end
	table.clear(shield.Links)
end

local groundedStates = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local function grounded(humanoid)
	if not humanoid or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	return groundedStates[humanoid:GetState()] == true
end

local function shieldSwap()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if shield.Clone and shield.Clone.Parent == character then
		return
	end
	if not grounded(humanoid) then
		return
	end

	local clone = humanoid:Clone()
	humanoid.Parent = nil
	clone.Parent = character
	workspace.CurrentCamera.CameraSubject = clone
	shieldControls(clone)
	shieldAnimate(character)
	shield.Original = humanoid
	shield.Clone = clone

	table.insert(shield.Links, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if clone.Parent ~= nil then
			clone.WalkSpeed = humanoid.WalkSpeed
		end
	end))

	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animator2 = clone:FindFirstChildOfClass("Animator")
	if animator and animator2 then
		table.insert(shield.Links, animator.AnimationPlayed:Connect(function(played)
			local animation = played.Animation
			if not animation or clone.Parent == nil then
				return
			end
			local ok, track = pcall(function()
				return animator2:LoadAnimation(animation)
			end)
			if not ok or not track then
				return
			end
			pcall(function()
				track.Priority = played.Priority
				track.Looped = played.Looped
				track:Play(0.05, math.max(played.WeightTarget, 0.01), played.Speed)
			end)
			local stopped
			stopped = played.Stopped:Connect(function()
				stopped:Disconnect()
				pcall(function()
					track:Stop(0.1)
				end)
			end)
		end))
	end

	table.insert(shield.Links, clone.Died:Connect(function()
		shieldUnlink()
		shield.Original, shield.Clone = nil, nil
		local current = localPlayer.Character
		if current and humanoid.Parent == nil then
			humanoid.Parent = current
			workspace.CurrentCamera.CameraSubject = humanoid
			shieldControls(humanoid)
		end
		pcall(function()
			clone:Destroy()
		end)
		humanoid.Health = 0
	end))
end

local function shieldUndo()
	shieldUnlink()
	local character = localPlayer.Character
	local original, clone = shield.Original, shield.Clone
	shield.Original, shield.Clone = nil, nil
	if original and clone and character and original.Parent == nil and clone.Parent == character then
		original.Parent = character
		workspace.CurrentCamera.CameraSubject = original
		shieldControls(original)
		pcall(function()
			clone:Destroy()
		end)
		shieldAnimate(character)
	end
end

local function shieldStart()
	shieldSwap()
	local n = 0
	shield.Connection = RunService.Heartbeat:Connect(function(dt)
		n += dt
		local character = localPlayer.Character
		local missing = not (shield.Clone and character and shield.Clone.Parent == character)
		if (missing and 0.25 or 3) <= n then
			n = 0
			shieldSwap()
		end
	end)
	shield.Added = localPlayer.CharacterAdded:Connect(function(character)
		shieldUnlink()
		shield.Original, shield.Clone = nil, nil
		task.spawn(function()
			character:WaitForChild("Humanoid", 10)
			task.wait(1)
			if shield.Connection and localPlayer.Character == character then
				shieldSwap()
			end
		end)
	end)
end

local function shieldStop()
	if shield.Connection then
		shield.Connection:Disconnect()
		shield.Connection = nil
	end
	if shield.Added then
		shield.Added:Disconnect()
		shield.Added = nil
	end
	shieldUndo()
end

------------------------------------------------------------------ carry / delivery state
local alive = true
local state = { Carrying = false, Uid = nil, Delivered = 0, Busy = false, Cancel = false, Mult = 1, PulledAt = 0, HeldSeen = 0, GuessedDrop = false }

local function progress(frac, text)
	local f = state.Progress
	if f then
		f(frac, text)
	end
end

if type(EggState) == "table" and type(EggState.CarryChanged) == "table" and type(EggState.CarryChanged.Connect) == "function" then
	EggState.CarryChanged:Connect(function(arg)
		local carrying = type(arg) == "table" and arg.IsCarrying == true
		if carrying and arg.GuardDisabled == true then
			carrying = false
		end
		state.GuessedDrop = false
		if carrying then
			state.HeldSeen = os.clock()
			if not state.Carrying then
				state.CarryAt = os.clock()
				state.CarryLogged = false
			end
			state.WakeReq = arg.RunBackWakeDelayRequired
		end
		if carrying and type(arg.Uid) == "string" then
			state.Uid = arg.Uid
			local mult = tonumber(arg.SpeedMultiplier)
			if mult and mult > 0 then
				state.Mult = mult
			end
		end
		state.Carrying = carrying
	end)
end

pcall(function()
	remote("RE/EggWorld/FieldEggRedeemVerdict").OnClientEvent:Connect(function()
		state.Delivered = os.clock()
	end)
end)

pcall(function()
	remote("RE/Alerts/Raise").OnClientEvent:Connect(function(arg)
		if type(arg) == "table" and type(arg.Text) == "string" and string.find(string.lower(arg.Text), "delivery failed", 1, true) then
			state.DeliveryFailedAt = os.clock()
		end
	end)
end)

-- the server pulling us back ("Relocate") is noted so the hop is simply repeated
pcall(function()
	remote("RE/RigSync/Refresh").OnClientEvent:Connect(function(arg)
		if type(arg) == "string" then
			local ok, decoded = pcall(function()
				return game:GetService("HttpService"):JSONDecode(arg)
			end)
			arg = ok and decoded or nil
		end
		if type(arg) ~= "table" then
			return
		end
		if arg.Action == "Relocate" then
			state.PulledAt = os.clock()
			local a = arg.Arguments
			if type(a) == "table" and tonumber(a[1]) and tonumber(a[2]) and tonumber(a[3]) then
				state.RelocPos = Vector3.new(tonumber(a[1]), tonumber(a[2]), tonumber(a[3]))
			else
				state.RelocPos = nil
			end
		elseif arg.Action == "BeginRagdoll" then
			state.Ragdoll = true
			state.RagdollAt = os.clock()
			state.RagdollArgs = type(arg.Arguments) == "table" and arg.Arguments or nil
			local r = root()
			if r then
				pcall(function()
					r.AssemblyLinearVelocity = Vector3.zero
				end)
			end
		elseif arg.Action == "EndRagdoll" then
			state.Ragdoll = false
			state.RagdollEnd = os.clock()
		end
	end)
end)

local function takeEgg(uid)
	if type(uid) == "string" and type(EggState) == "table" and type(EggState.CarryFieldEgg) == "function" then
		pcall(EggState.CarryFieldEgg, uid)
	end
end

local function dropEgg()
	if type(EggState) == "table" and type(EggState.DropFieldEgg) == "function" then
		pcall(EggState.DropFieldEgg, "PlayerRequest")
	end
end

-- the prompt of the egg itself (nearest egg prompt to the egg's position), never one of another egg
local function promptNear(position, radius)
	local best, bestDistance = nil, radius
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
			local prompt = child:FindFirstChild("CarryAreaEgg")
			if prompt and prompt:IsA("ProximityPrompt") then
				local distance = (child.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = prompt, distance
				end
			end
		end
	end
	return best
end

-- the carried egg is welded to the character: used to catch a missed carry signal
local function heldByMe(uid)
	local character = localPlayer.Character
	if type(uid) ~= "string" or not character then
		return false
	end
	local egg = workspace:FindFirstChild(uid)
	if not egg then
		return false
	end
	for _, d in ipairs(egg:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") then
			local ok, a, b = pcall(function()
				return d.Part0, d.Part1
			end)
			if ok and ((a and a:IsDescendantOf(character)) or (b and b:IsDescendantOf(character))) then
				return true
			end
		end
	end
	return false
end

task.spawn(function()
	while alive do
		task.wait(0.2)
		if not state.Carrying then
			if state.GuessedDrop and heldByMe(state.Uid) then
				state.GuessedDrop, state.Carrying, state.HeldSeen = false, true, os.clock()
			end
		elseif heldByMe(state.Uid) then
			state.HeldSeen = os.clock()
		elseif os.clock() - state.HeldSeen > 0.8 then
			state.Carrying, state.GuessedDrop = false, true
		end
	end
end)

local function snapshot()
	local list = {}
	local ok, result = pcall(function()
		return remote("RF/EggWorld/AskFieldEggSnapshot"):InvokeServer()
	end)
	local records = ok and type(result) == "table" and result.Records or nil
	if type(records) ~= "table" then
		return list
	end
	for _, record in pairs(records) do
		if type(record) == "table" and type(record.Uid) == "string" and (record.State == "Slot" or record.State == "Dropped") and typeof(record.BottomCFrame) == "CFrame" then
			list[#list + 1] = record
		end
	end
	return list
end

local function eggPosition(uid)
	for _, record in ipairs(snapshot()) do
		if record.Uid == uid then
			return record.BottomCFrame.Position
		end
	end
	return nil
end

------------------------------------------------------------------ egg info for the list (icon, name, value)
local function describe(record)
	local directory = type(Assets) == "table" and Assets.Directory or nil
	local entry = type(directory) == "table" and directory[tostring(record.AssetCategory)] or nil
	local info = { Uid = record.Uid, Category = tostring(record.AssetCategory), Name = tostring(record.AssetCategory), Icon = "", Rarity = 0, Value = 0 }

	if type(entry) == "table" then
		info.Name = tostring(entry.DisplayName or record.AssetCategory)
		local icon = entry.Icon
		if icon ~= nil and tostring(icon) ~= "" then
			icon = tostring(icon)
			info.Icon = tonumber(icon) and ("rbxassetid://" .. icon) or icon
		end
		if type(entry.Rarity) == "table" then
			info.Rarity = tonumber(entry.Rarity.RarityNumber or entry.Rarity.Rank) or 0
		end

		local scale = tonumber(record.AssetScale) or 1
		local factor = scale > 5 and (scale / 5) ^ 1.2 * 19.637875755794113 or scale ^ 1.85
		local mutation = 1
		if type(Mutations) == "table" and type(Mutations.EarningsFor) == "function" then
			local okM, resM = pcall(Mutations.EarningsFor, type(record.Mutations) == "table" and record.Mutations or {})
			if okM and type(resM) == "number" then
				mutation = resM
			end
		end
		info.Value = (tonumber(entry.EarningRate) or 0) * factor * mutation
	end

	return info
end

local function money(value)
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if value >= u[1] then
			return string.format("$%.2f%s/s", value / u[1], u[2])
		end
	end
	return string.format("$%d/s", math.floor(value + 0.5))
end

------------------------------------------------------------------ Instant TP logic
local status = function(text) end

local semi = { Dodge = true, DodgeGo = true, TakeFirstHit = true, WakeWait = 2.8, Frozen = false, Home = nil, Kind = nil, AtDrop = false, SlowRun = false, Fails = 0, ResetDone = false, Rotate = nil, ExitPath = nil, Log = {} }
local inDimensionNow = function()
	return localPlayer.Character ~= nil and localPlayer:GetAttribute("InHalloweenDimension") == true
end
local method = "Relay"

local function slog(msg)
	local r = root()
	local list = semi.Log
	list[#list + 1] = string.format("%.1f %s | y=%s", os.clock() % 1000, msg, r and string.format("%.0f", r.Position.Y) or "nil")
	if #list > 300 then
		table.remove(list, 1)
	end
end

pcall(function()
	getgenv().YslemSemiReport = function()
		return table.concat(semi.Log, "\n")
	end
end)

local function frozenCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return function() end
	end
	local oldType = camera.CameraType
	local frame = camera.CFrame
	pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = frame
	end)
	return function()
		pcall(function()
			camera.CameraType = oldType
		end)
	end
end

-- FPS dip: 50 / 40 (never below 40), the pause between two switches is 200 ms while the ping is 200 ms or less,
-- otherwise it follows the ping (read once, when the dip starts). Only during the delivery.
local userFps = 240
pcall(function()
	if typeof(getfpscap) == "function" then
		local cap = tonumber(getfpscap())
		if cap and (cap == 0 or cap >= 60) then
			userFps = cap
		end
	end
end)

local function restoreFps()
	if typeof(setfpscap) == "function" then
		pcall(setfpscap, math.clamp(math.floor(userFps), 0, 1000))
	end
end

local function dipInterval()
	local ping = 0
	local ok, value = pcall(function()
		return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok then
		ping = tonumber(value) or 0
	end
	if ping <= 200 then
		return 0.2
	end
	return math.clamp(ping / 1000, 0.2, 1)
end

local function netPing()
	local ping = 0.1
	pcall(function()
		ping = localPlayer:GetNetworkPing()
	end)
	return math.clamp(tonumber(ping) or 0.1, 0, 1)
end

local fpsGen = 0
local function fpsOn()
	if typeof(setfpscap) ~= "function" then
		return
	end
	fpsGen += 1
	local mine = fpsGen
	task.spawn(function()
		local high = true
		local step = dipInterval()
		local started = os.clock()
		while fpsGen == mine and os.clock() - started < 60 do
			pcall(setfpscap, high and 50 or 40)
			high = not high
			task.wait(step)
		end
		if fpsGen == mine then
			restoreFps()
		end
	end)
end

local function fpsOff()
	fpsGen += 1
	restoreFps()
end

-- a still copy of the player stays where the egg was taken during the flight; removed on arrival
local stealClone = nil
local function dropClone()
	local copy = stealClone
	stealClone = nil
	if copy then
		pcall(function()
			copy:Destroy()
		end)
	end
end

local function postClone()
	dropClone()
	local character = localPlayer.Character
	if not character then
		return
	end
	local was = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = was
	if copy then
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Animator") or d:IsA("AnimationController") or d:IsA("Sound") then
				pcall(function()
					d:Destroy()
				end)
			elseif d:IsA("Humanoid") then
				pcall(function()
					d.PlatformStand = true
					d.AutoRotate = false
					d.WalkSpeed = 0
					d.JumpPower = 0
					d.JumpHeight = 0
					d.BreakJointsOnDeath = false
					d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				end)
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
		copy.Name = "Clone"
		copy.Parent = workspace
		stealClone = copy
	end
end

------------------------------------------------------------------ Semi TP: frozen view (the player stays still while the body works)
local viewState = nil

local function randomName()
	return string.format("%08x", math.random(0, 2147483647))
end

local function cloneModel(model, parent)
	local map = {}
	for _, d in ipairs(model:GetDescendants()) do
		map[d] = d.Archivable
		pcall(function()
			d.Archivable = true
		end)
	end
	local was = model.Archivable
	model.Archivable = true
	local ok, result = pcall(function()
		return model:Clone()
	end)
	model.Archivable = was
	for inst, value in pairs(map) do
		pcall(function()
			inst.Archivable = value
		end)
	end
	if not ok or not result then
		return nil
	end
	result.Name = randomName()
	for _, d in ipairs(result:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint") or d:IsA("BodyMover") or d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then
			pcall(function()
				d:Destroy()
			end)
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	result.Parent = parent
	return result
end

local promptSaved = nil
local function hidePrompts(hide)
	pcall(function()
		local service = game:GetService("ProximityPromptService")
		if hide then
			promptSaved = promptSaved or { guis = {}, max = nil }
			if promptSaved.max == nil then
				local okMax, current = pcall(function()
					return service.MaxPromptsVisible
				end)
				if okMax then
					promptSaved.max = current
				end
			end
			pcall(function()
				service.MaxPromptsVisible = 0
			end)
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				for _, promptGui in ipairs(playerGui:GetChildren()) do
					local guiName = string.lower(promptGui.Name)
					if promptGui:IsA("ScreenGui") and promptGui.Enabled and not string.find(guiName, "yslem", 1, true)
						and (string.find(guiName, "prompt", 1, true) or string.find(guiName, "interact", 1, true)) then
						promptGui.Enabled = false
						promptSaved.guis[#promptSaved.guis + 1] = promptGui
					end
				end
			end
		elseif promptSaved then
			local saved = promptSaved
			promptSaved = nil
			for _, promptGui in ipairs(saved.guis) do
				pcall(function()
					promptGui.Enabled = true
				end)
			end
			if saved.max ~= nil then
				pcall(function()
					service.MaxPromptsVisible = saved.max
				end)
			end
		end
	end)
end

local sinkName = nil
local touchSaved = nil
local function sinkInput(on)
	pcall(function()
		local cas = game:GetService("ContextActionService")
		if on then
			if sinkName then
				return
			end
			sinkName = "YslemFreeze" .. tostring(math.random(100000, 999999))
			cas:BindActionAtPriority(sinkName, function()
				return Enum.ContextActionResult.Sink
			end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down,
				Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA)
		elseif sinkName then
			local name = sinkName
			sinkName = nil
			cas:UnbindAction(name)
		end
	end)
	pcall(function()
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		local touch = playerGui and playerGui:FindFirstChild("TouchGui")
		if on then
			if touch and touch:IsA("ScreenGui") and not touchSaved then
				touchSaved = { Gui = touch, Enabled = touch.Enabled }
				touch.Enabled = false
			end
		elseif touchSaved then
			local saved = touchSaved
			touchSaved = nil
			saved.Gui.Enabled = saved.Enabled
		end
	end)
end

local function viewControls(on)
	hidePrompts(not on)
	sinkInput(not on)
	pcall(function()
		local scripts = localPlayer:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module then
			local controls = require(module):GetControls()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function releaseView()
	local view = viewState
	if not view then
		return
	end
	viewState = nil
	semi.Frozen = false
	viewControls(true)
	if view.BindName then
		pcall(function()
			RunService:UnbindFromRenderStep(view.BindName)
		end)
	end
	if view.Link then
		pcall(function()
			view.Link:Disconnect()
		end)
	end
	if view.Beat then
		pcall(function()
			view.Beat:Disconnect()
		end)
	end
	for _, part in ipairs(view.Hidden) do
		pcall(function()
			part.LocalTransparencyModifier = 0
		end)
	end
	for _, extra in ipairs(view.Extras) do
		pcall(function()
			extra.Inst.Enabled = extra.Prev
		end)
	end
	pcall(function()
		view.Camera.CameraType = view.CameraType
		if view.Follow then
			local liveChar = localPlayer.Character
			local liveHum = liveChar and liveChar:FindFirstChildOfClass("Humanoid")
			if liveHum then
				view.Camera.CameraSubject = liveHum
			end
		end
	end)
	for _, copy in ipairs(view.Copies) do
		pcall(function()
			copy:Destroy()
		end)
	end
end

local function freezeView(character, offset, cameraCFrame, forced)
	local camera = workspace.CurrentCamera
	if viewState or not character or not camera then
		return false
	end
	offset = offset or Vector3.zero
	local view = { Camera = camera, CameraType = camera.CameraType, CameraCFrame = cameraCFrame or camera.CFrame, Copies = {}, Hidden = {}, Parts = {}, Extras = {} }
	viewState = view
	view.Forced = forced == true
	view.Follow = getgenv().YslemCamFollow ~= false
	if not view.Forced then
		task.delay(120, function()
			if viewState == view then
				releaseView()
			end
		end)
	end

	local hiddenSet, extraSet = {}, {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			hiddenSet[d] = true
			view.Hidden[#view.Hidden + 1] = d
			if d:IsA("BasePart") then
				view.Parts[#view.Parts + 1] = d
			end
		end
	end
	local lastScan = os.clock()

	local function scanExtras()
		for _, d in ipairs(character:GetDescendants()) do
			if not extraSet[d] and (d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
				or d:IsA("Highlight") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("Light")) then
				extraSet[d] = true
				local okEnabled, enabledValue = pcall(function()
					return d.Enabled
				end)
				view.Extras[#view.Extras + 1] = { Inst = d, Prev = okEnabled and enabledValue or false }
			end
		end
	end
	pcall(scanExtras)

	local function tick()
		if os.clock() - lastScan > 0.5 then
			lastScan = os.clock()
			if view.Semi then
				hidePrompts(true)
			end
			pcall(function()
				for _, d in ipairs(character:GetDescendants()) do
					if not hiddenSet[d] and (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) then
						hiddenSet[d] = true
						view.Hidden[#view.Hidden + 1] = d
						if d:IsA("BasePart") then
							view.Parts[#view.Parts + 1] = d
						end
					end
				end
				for _, copy in ipairs(view.Copies) do
					if copy.Parent ~= camera then
						copy.Parent = camera
					end
				end
				scanExtras()
			end)
		end
		local shown = view.Follow and 0 or 1
		pcall(function()
			for _, part in ipairs(view.Parts) do
				if part.LocalTransparencyModifier ~= shown then
					part.LocalTransparencyModifier = shown
				end
			end
		end)
		if #view.Extras > 0 then
			pcall(function()
				for _, extra in ipairs(view.Extras) do
					if extra.Inst.Enabled then
						extra.Inst.Enabled = false
					end
				end
			end)
		end
		pcall(function()
			local live = workspace.CurrentCamera
			if live and live ~= camera then
				camera = live
				view.Camera = live
			end
			if view.Follow then
				local liveChar = localPlayer.Character
				local liveHum = liveChar and liveChar:FindFirstChildOfClass("Humanoid")
				if liveHum then
					if camera.CameraType ~= Enum.CameraType.Custom then
						camera.CameraType = Enum.CameraType.Custom
					end
					if camera.CameraSubject ~= liveHum then
						camera.CameraSubject = liveHum
					end
					return
				end
			end
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			camera.CFrame = view.CameraCFrame
		end)
	end

	tick()
	view.BindName = randomName()
	if not pcall(function()
		RunService:BindToRenderStep(view.BindName, Enum.RenderPriority.Last.Value + 1, tick)
	end) then
		view.BindName = nil
		view.Link = RunService.RenderStepped:Connect(tick)
	end
	view.Beat = RunService.Heartbeat:Connect(tick)

	local ok, copy = false, nil
	if not view.Follow then
		ok, copy = pcall(cloneModel, character, camera)
	end
	if ok and copy then
		if offset.Magnitude > 0.01 then
			for _, d in ipairs(copy:GetDescendants()) do
				if d:IsA("BasePart") then
					pcall(function()
						d.CFrame = d.CFrame + offset
					end)
				end
			end
		end
		view.Copies[#view.Copies + 1] = copy
	end

	view.Semi = true
	viewControls(false)
	semi.Frozen = true
	return true
end

-- Auto Steal cancelled while frozen: the body first goes back to where the copy waits, then camera and controls return
local function releaseBackHome(home)
	local frozen = viewState
	if not frozen then
		return
	end
	if typeof(home) ~= "Vector3" then
		releaseView()
		return
	end
	local started = os.clock()
	while os.clock() - started < 7 and viewState == frozen do
		local r = root()
		if not r or r.Position.Y < 5000 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	for _ = 1, 10 do
		if viewState ~= frozen then
			return
		end
		local r = root()
		if r then
			pcall(function()
				r.CFrame = CFrame.new(home) * r.CFrame.Rotation
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		RunService.Heartbeat:Wait()
	end
	if viewState == frozen then
		releaseView()
	end
end

local function swapped()
	local character = localPlayer.Character
	return shield.Clone ~= nil and character ~= nil and shield.Clone.Parent == character
end

------------------------------------------------------------------ map helpers
local function lineInfo()
	local world = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
	world = world and world:FindFirstChild("Areas")
	world = world and world:FindFirstChild("SeparationLine")
	local ok = world and world:IsA("BasePart")
	return ok and world.Position.X or 552.2, ok and world.Position.Y or 67.67
end

local function homePoint()
	for _, def in ipairs({
		{ { "GearGiver_Slap", "Podium" }, Vector3.new(-16.415, 21.072, -6.106) },
		{ { "World", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
		{ { "__OBJECTS", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
	}) do
		local node = workspace
		for _, name in ipairs(def[1]) do
			node = node and node:FindFirstChild(name) or nil
		end
		if node and node:IsA("BasePart") then
			return node.CFrame:PointToWorldSpace(def[2])
		end
	end
	return Vector3.new(528.7, 70.57, -364.11)
end

local function place(position)
	local r = root()
	if not r then
		return
	end
	pcall(function()
		r.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- portals / arenas / teleporters are walked around 
local dangerCache, dangerAt = {}, 0
local function dangers()
	if os.clock() - dangerAt < 5 then
		return dangerCache
	end
	dangerAt = os.clock()
	local list = {}
	local function add(inst)
		local ok, cf, size = pcall(function()
			if inst:IsA("Model") then
				return inst:GetBoundingBox()
			elseif inst:IsA("BasePart") then
				return inst.CFrame, inst.Size
			end
		end)
		if ok and cf and size then
			local half = Vector3.new(math.abs(size.X), 0, math.abs(size.Z)) * 0.5
			local rot = (cf - cf.Position):VectorToWorldSpace(half)
			local rx = math.max(math.abs(rot.X), half.X, half.Z)
			local rz = math.max(math.abs(rot.Z), half.X, half.Z)
			list[#list + 1] = { MinX = cf.Position.X - rx, MaxX = cf.Position.X + rx, MinZ = cf.Position.Z - rz, MaxZ = cf.Position.Z + rz }
		end
	end
	local function bad(name)
		if name == "ScrambleLocalVisuals" or name == "DrScrambleEvent" then
			return false
		end
		name = string.lower(name)
		return string.find(name, "portal", 1, true) or string.find(name, "teleport", 1, true) or string.find(name, "mech", 1, true) or string.find(name, "arena", 1, true) or string.find(name, "scramble", 1, true)
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder")) and bad(child.Name) then
			if child:IsA("Folder") then
				for _, inner in ipairs(child:GetChildren()) do
					add(inner)
				end
			else
				add(child)
			end
		end
	end
	local build = workspace:FindFirstChild("World")
	build = build and build:FindFirstChild("Build")
	if build then
		for _, child in ipairs(build:GetChildren()) do
			if bad(child.Name) then
				for _, inner in ipairs(child:GetChildren()) do
					add(inner)
				end
			end
		end
	end
	dangerCache = list
	return list
end

-- if the straight line crosses a danger zone, aim at the corner of it instead
local function avoid(from, to)
	for _, d in ipairs(dangers()) do
		local x0, x1, z0, z1 = d.MinX - 12, d.MaxX + 12, d.MinZ - 12, d.MaxZ + 12
		local inside = from.X >= x0 and from.X <= x1 and from.Z >= z0 and from.Z <= z1
		if not inside then
			local t0, t1, hit = 0, 1, true
			for _, axis in ipairs({ { from.X, to.X - from.X, x0, x1 }, { from.Z, to.Z - from.Z, z0, z1 } }) do
				local pos, delta, lo, hi = axis[1], axis[2], axis[3], axis[4]
				if math.abs(delta) < 1e-6 then
					if pos < lo or pos > hi then
						hit = false
					end
				else
					local ta, tb = (lo - pos) / delta, (hi - pos) / delta
					if ta > tb then
						ta, tb = tb, ta
					end
					t0, t1 = math.max(t0, ta), math.min(t1, tb)
					if t0 > t1 then
						hit = false
					end
				end
			end
			if hit then
				local zLow, zHigh = z0 - 2, z1 + 2
				local z = math.abs(from.Z - zLow) <= math.abs(from.Z - zHigh) and zLow or zHigh
				if z < -440 or z > -290 then
					z = z == zLow and zHigh or zLow
				end
				local x = math.abs(from.X - x0) <= math.abs(from.X - x1) and x0 or x1
				if math.abs(from.Z - z) < 3 then
					x = math.abs(to.X - x0) <= math.abs(to.X - x1) and x0 or x1
				end
				return Vector3.new(x, to.Y, z)
			end
		end
	end
	return to
end

-- current position of an egg lying in the world (cheap), with the snapshot as fallback
local function eggNow(uid, cache)
	local node = workspace:FindFirstChild(uid)
	local slots = workspace:FindFirstChild("AreaEggSlotsClient")
	node = node or (slots and slots:FindFirstChild(uid))
	if node then
		local ok, pos = pcall(function()
			return node:GetPivot().Position
		end)
		if ok and pos then
			cache.Pos, cache.At = pos, os.clock()
			return pos
		end
	end
	if os.clock() - cache.At >= 0.5 then
		cache.At = os.clock()
		cache.Pos = eggPosition(uid) or cache.Pos
	end
	return cache.Pos
end

local function holdStill()
	local function zero()
		local r = root()
		if r then
			pcall(function()
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
	zero()
	local link
	pcall(function()
		if RunService.Stepped then
			link = RunService.Stepped:Connect(zero)
		end
	end)
	return function()
		if link then
			pcall(function()
				link:Disconnect()
			end)
		end
	end
end

local function ragdollWait()
	local seen = state.RagdollAt
	if not (state.Ragdoll and seen and os.clock() - seen < 12) then
		return false
	end
	state.Hits = (state.Hits or 0) + 1
	status("Knocked down, staying still")
	local kb = state.RagdollArgs
	slog(string.format("hit by the guard (%d this trip): staying still until the ragdoll ends, knock-back %s", state.Hits, kb and string.format("%.0f,%.0f,%.0f", tonumber(kb[2]) or 0, tonumber(kb[3]) or 0, tonumber(kb[4]) or 0) or "?"))
	local release = holdStill()
	local stop = os.clock() + 8
	while state.Ragdoll and os.clock() < stop and not state.Cancel do
		RunService.Heartbeat:Wait()
		local r = root()
		if r then
			pcall(function()
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
	release()
	state.Ragdoll = false
	local calm = 0
	while calm < 0.15 and not state.Cancel do
		calm += RunService.Heartbeat:Wait()
	end
	return true
end

-- go to the egg: straight on the ground at 115% of the walk speed (never faster), or, after the Semi TP exit, in the air
-- at the given ratio with a cruise height above the egg. From the base side it first walks out to the safe-zone point.
local function runToEgg(uid, egg, opts)
	opts = opts or {}
	local ratio = math.min(opts.Ratio or CFG.SpeedCap, CFG.SpeedCap)
	local height = opts.Height or 0
	local lineX = lineInfo()
	local home = homePoint()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		if character:FindFirstChildWhichIsA("Tool") then
			pcall(function()
				humanoid:UnequipTools()
			end)
		end
	end

	local r = root()
	if not r then
		return false
	end
	local stage = "field"
	if not opts.Field and r.Position.X < lineX - 2 and Vector3.new(r.Position.X - home.X, 0, r.Position.Z - home.Z).Magnitude > 20 then
		stage = "safe"
	end

	local runY = egg.Y + 3
	local function snapToHeight(target)
		local at = root()
		local current = localPlayer.Character
		if not at or not current or math.abs(at.Position.Y - target) < 1 or math.abs(at.Position.Y - target) > 90 then
			return false
		end
		pcall(function()
			current:PivotTo(CFrame.new(Vector3.new(at.Position.X, target, at.Position.Z)) * at.CFrame.Rotation)
			at.AssemblyLinearVelocity = Vector3.new(at.AssemblyLinearVelocity.X, 0, at.AssemblyLinearVelocity.Z)
		end)
		return true
	end
	if stage == "field" and height > 0.5 then
		snapToHeight(runY + height)
	end

	local started, lastCheck, lastPos, lastTake = os.clock(), os.clock(), r.Position, 0
	while os.clock() - started < 120 and not state.Cancel do
		if ragdollWait() then
			started += 1
		end
		r = root()
		if not r then
			return false
		end
		local flatEgg = Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z)
		if state.Carrying and state.Uid == uid then
			break
		end
		if stage == "field" and flatEgg.Magnitude <= 2.5 and (height <= 0.5 or r.Position.Y - runY < 4) then
			break
		end
		local target = egg
		if stage == "safe" then
			if Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude <= 6 then
				stage = "field"
				if height > 0.5 then
					snapToHeight(runY + height)
				end
			else
				target = home
			end
		end

		local waypoint = avoid(r.Position, target)
		local flat = Vector3.new(waypoint.X - r.Position.X, 0, waypoint.Z - r.Position.Z)
		local unit = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero
		local speed = math.max(walkSpeed() * ratio, 8)
		if height > 0.5 and stage == "field" then
			local wantY = flatEgg.Magnitude <= 3 and runY or runY + height
			if (flatEgg.Magnitude <= 3 and snapToHeight(runY)) or (math.abs(wantY - r.Position.Y) > 2 and snapToHeight(wantY)) then
				RunService.Heartbeat:Wait()
				continue
			end
			local vy = math.clamp((wantY - r.Position.Y) / 0.12, -speed * 0.5, speed * 0.5)
			local horizontal = unit * math.min(math.sqrt(math.max(speed * speed - vy * vy, 0)), flat.Magnitude / 0.05)
			pcall(function()
				r.AssemblyLinearVelocity = Vector3.new(horizontal.X, vy, horizontal.Z)
			end)
		else
			local v = unit * math.min(speed, flat.Magnitude / 0.05)
			pcall(function()
				r.AssemblyLinearVelocity = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
				if humanoid and unit.Magnitude > 0 then
					humanoid:Move(unit, false)
				end
			end)
		end

		-- stuck on something: jump
		if os.clock() - lastCheck >= 1.5 then
			if (r.Position - lastPos).Magnitude < 3 and humanoid and flatEgg.Magnitude > 15 then
				pcall(function()
					humanoid.Jump = true
				end)
			end
			lastPos, lastCheck = r.Position, os.clock()
		end

		-- close enough for the prompt: ask for the egg while arriving
		if stage == "field" and flatEgg.Magnitude <= 9 and os.clock() - lastTake > 0.1 then
			lastTake = os.clock()
			task.spawn(takeEgg, uid)
		end
		RunService.Heartbeat:Wait()
	end

	r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(0, r.AssemblyLinearVelocity.Y, 0)
			if humanoid then
				humanoid:Move(Vector3.zero, false)
			end
		end)
	end
	return state.Carrying or (r ~= nil and Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z).Magnitude <= 6)
end

-- take the egg that lies next to us (also used to take it back after the drop): follow it, fire its prompt and send the request
local function grab(uid, timeout)
	local cache = { At = 0 }
	local waited, since = 0, 1
	while not state.Carrying and waited < timeout and not state.Cancel do
		local stillFrom = os.clock()
		if ragdollWait() then
			timeout += os.clock() - stillFrom
			since = 1
		end
		local r = root()
		local egg = eggNow(uid, cache)
		local dt = math.max(RunService.Heartbeat:Wait(), 1 / 240)
		waited += dt
		since += dt
		if r and egg then
			local delta = egg - r.Position
			if delta.Magnitude > 2 then
				local pace = math.max(walkSpeed() * CFG.SpeedCap, 16)
				local v = delta / math.max(0.08, dt)
				if v.Magnitude > pace then
					v = v.Unit * pace
				end
				pcall(function()
					r.AssemblyLinearVelocity = v + Vector3.new(0, workspace.Gravity * dt * 0.5, 0)
					r.AssemblyAngularVelocity = Vector3.zero
				end)
			end
			if since >= CFG.GrabInterval then
				since = 0
				local prompt = promptNear(egg - Vector3.new(0, 3, 0), 10)
				if prompt and typeof(fireproximityprompt) == "function" then
					pcall(function()
						prompt.HoldDuration = 0
					end)
					pcall(fireproximityprompt, prompt)
				end
				task.spawn(takeEgg, uid)
			end
		elseif since >= CFG.GrabInterval then
			since = 0
			task.spawn(takeEgg, uid)
		end
	end
	local r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	return state.Carrying and state.Uid == uid
end

local function regrab(uid)
	if state.Carrying then
		return true
	end
	local r = root()
	local egg = eggNow(uid, { At = 0 })
	local gap = r and egg and Vector3.new(r.Position.X - egg.X, 0, r.Position.Z - egg.Z).Magnitude or 0
	if gap > 1500 then
		slog(string.format("the egg is %.0f studs away: no teleport that long to take it back", gap))
		status("The egg is too far to take back")
		return false
	end
	if r and egg and gap > CFG.RegrabFar then
		status("The egg fell far behind, teleporting onto it")
		place(egg + Vector3.new(0, 3, 0))
	else
		status("The egg fell close, taking it back")
	end
	return grab(uid, 3)
end

local function groundY(position, fallback)
	local y = fallback
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { localPlayer.Character }
		params.IgnoreWater = true
		params.RespectCanCollide = true
		local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), params)
		if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - fallback) < 40 then
			y = hit.Position.Y + 3.5
		end
	end)
	return y
end

-- safe zone: same route as the Normal mode: checkpoint 7 studs past the line, then the base.
-- Speed = the carry plan (never above 115% of the walk speed), the run starts above the base and comes down.
local function carrySpeed(distance)
	local ws = walkSpeed()
	if semi.SlowRun then
		return math.max(ws * 0.8 * state.Mult, 8)
	end
	local base = ws * math.min(CFG.CarryRatio, CFG.SpeedCap) * state.Mult
	local fast = base * 1.5 -- SpeedRatio
	local excess = 5.5 * base -- ExcessSeconds
	local limit = fast
	if distance and distance > excess then
		limit = math.min(fast, base * distance / (distance - excess))
	end
	return math.min(math.max(math.min(base * CFG.EasyRatio, limit), base), math.max(ws * CFG.SpeedCap, base))
end

-- Semi TP delivery: two teleports (checkpoint past the line, then the base), the egg is put down on the base
local function tpHome(lineX, laneZ, started)
	local home = homePoint()
	local steps = { Vector3.new(lineX - 7, home.Y, laneZ), home }
	status("Safe zone: teleporting")
	for _, target in ipairs(steps) do
		local tries = 0
		while state.Carrying and state.Delivered < started and not state.Cancel and tries < 3 do
			tries += 1
			local pulledBefore = state.PulledAt
			local held = 0
			while held < math.max(CFG.HopGap, 0.1) do
				place(target)
				held += RunService.Heartbeat:Wait()
			end
			local check = root()
			local pulled = state.PulledAt > pulledBefore or (check ~= nil and Vector3.new(check.Position.X - target.X, 0, check.Position.Z - target.Z).Magnitude > 10)
			if not pulled then
				break
			end
		end
	end
	local waited = 0
	while state.Carrying and state.Delivered < started and not state.Cancel and waited < 1 do
		waited += RunService.Heartbeat:Wait()
	end
	if state.Carrying and state.Delivered < started and not state.Cancel then
		local at = root()
		if at and Vector3.new(at.Position.X - home.X, 0, at.Position.Z - home.Z).Magnitude > 6 then
			place(home)
			RunService.Heartbeat:Wait()
		end
		status("Safe zone: dropping the egg on the base")
		dropEgg()
		local confirm = 0
		while state.Delivered < started and confirm < 1 and not state.Cancel do
			confirm += RunService.Heartbeat:Wait()
		end
	end
	return state.Delivered >= started
end

local function runHome(lineX, laneZ)
	local started = os.clock()
	local home = homePoint()
	local checkpoint = lineX - 7
	local height = semi.SlowRun and 0 or CFG.Height
	local share = math.clamp(CFG.ClimbShare, 0.1, 0.9)
	local descent = height * math.sqrt(1 - share * share) / share
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- rise above the base first (no horizontal move)
	local r = root()
	if r and character and height > 0.5 and home.Y + height - 2 > r.Position.Y then
		pcall(function()
			character:PivotTo(CFrame.new(Vector3.new(r.Position.X, home.Y + height, r.Position.Z)) * r.CFrame.Rotation)
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	-- the speed is planned once, at the start, from the distance still to go
	local start = root()
	local speed = carrySpeed(start and (Vector3.new(start.Position.X - home.X, 0, start.Position.Z - home.Z).Magnitude + math.max(0, height) * 2) or nil)

	local last = os.clock()
	local timeout = 0
	status("Safe zone")
	while state.Carrying and state.Delivered < started and not state.Cancel and timeout < 25 do
		r = root()
		if not r then
			return false
		end
		local now = os.clock()
		local dt = math.max(now - last, 1 / 240)
		last = now
		timeout += dt

		local toHome = r.Position.X <= checkpoint + 2
		local target = toHome and home or Vector3.new(checkpoint, home.Y, laneZ)
		if toHome and Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude < 2 then
			break
		end
		local aim = avoid(r.Position, target)
		local flat = Vector3.new(aim.X - r.Position.X, 0, aim.Z - r.Position.Z)
		local remaining = toHome and 0 or math.max(0, r.Position.X - checkpoint)
		local wantY = home.Y + height
		if toHome or remaining <= descent then
			wantY = home.Y + height * math.clamp(remaining / math.max(descent, 1), 0, 1)
		end
		local vy = math.clamp((wantY - r.Position.Y) / 0.12, -speed * share, speed * share)
		local horizontal = math.sqrt(math.max(speed * speed - vy * vy, 0))
		local v = flat.Magnitude > 0.01 and flat.Unit * math.min(horizontal, flat.Magnitude / 0.05) or Vector3.zero
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
		end)
		RunService.Heartbeat:Wait()
	end

	if humanoid then
		pcall(function()
			humanoid:Move(Vector3.zero, false)
		end)
	end

	local settle = 0
	while settle < 2 and state.Delivered < started and state.Carrying and not state.Cancel do
		settle += RunService.Heartbeat:Wait()
	end
	-- still in the hands at home: put it down so the base takes it
	if state.Carrying and state.Delivered < started and not state.Cancel then
		task.wait(0.2)
		dropEgg()
		local waited = 0
		while state.Delivered < started and waited < 1 do
			waited += RunService.Heartbeat:Wait()
		end
	end
	return state.Delivered >= started
end

-- Dodge return: chain on the lane, drop in front of the line, take it back, bank where the clown waits.
local function treadmillStand()
	local ok, standAt = pcall(function()
		local PlotState = require(ReplicatedStorage.Client.PlotState)
		local slot = type(PlotState.ResolveLocalSlot) == "function" and PlotState.ResolveLocalSlot() or PlotState.GetMySlot()
		local plots = type(PlotState.ResolveFolder) == "function" and PlotState.ResolveFolder() or PlotState.GetPlotsFolder()
		local plot = plots and slot and plots:FindFirstChild(tostring(slot))
		local bottom = plot and plot:FindFirstChild("TreadmillBottom")
		if not (bottom and bottom:IsA("BasePart")) then
			return nil
		end
		local character = localPlayer.Character
		local r = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not r or not humanoid then
			return nil
		end
		local feet = humanoid.RigType == Enum.HumanoidRigType.R15 and (r.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0.5)) or (r.Size.Y * 0.5 + 2)
		return (bottom.CFrame * CFrame.new(0, bottom.Size.Y * 0.5 + feet + 0.05, 0)).Position
	end)
	return ok and standAt or nil
end

local function treadmillMounted()
	local snapshot = remote("RF/Treadmill/AskRenderSnapshot")
	if not snapshot or not snapshot:IsA("RemoteFunction") then
		return nil
	end
	local ok, ids = pcall(snapshot.InvokeServer, snapshot)
	if not ok or type(ids) ~= "table" then
		return nil
	end
	return table.find(ids, localPlayer.UserId) ~= nil
end

-- the treadmill reset: onto the own treadmill, worn (confirmed by the server, 0.7 s), held 0.25 s, taken off (confirmed, 0.7 s)
local function treadmillReset()
	local wear = remote("RF/Treadmill/AskWearStill")
	local doff = remote("RF/Treadmill/AskDoff")
	local stand = treadmillStand()
	if not (wear and doff and stand) or state.Cancel then
		slog("treadmill reset: not available (remote or stand missing)")
		return false
	end
	place(stand)
	local function pause(t)
		local w = 0
		while w < t and not state.Cancel do
			w += RunService.Heartbeat:Wait()
		end
	end
	pause(0.15)
	local mounted = false
	local mountBy = os.clock() + 0.7
	while not state.Cancel and os.clock() < mountBy do
		pcall(wear.InvokeServer, wear)
		pause(0.08)
		if treadmillMounted() == true then
			mounted = true
			break
		end
	end
	if mounted then
		pause(0.25)
	end
	local released = false
	local releaseBy = os.clock() + 0.7
	while not state.Cancel and os.clock() < releaseBy do
		pcall(doff.InvokeServer, doff)
		pause(0.08)
		if treadmillMounted() == false then
			released = true
			break
		end
	end
	slog(string.format("treadmill reset: worn=%s, taken off=%s", tostring(mounted), tostring(released)))
	return mounted and released
end

local clown = { At = nil }
local function plantClown(pos)
	pcall(postClone)
	local copy = stealClone
	local r = root()
	if copy and r then
		pcall(function()
			copy.Name = randomName()
			copy:PivotTo(CFrame.new(pos) * r.CFrame.Rotation)
		end)
	end
	clown.At = pos
	slog(string.format("Clown planted at %.1f %.1f %.1f", pos.X, pos.Y, pos.Z))
end

local function relayFlow(uid, started, releaseCamera, semiFrozen)
	local function held()
		return state.Carrying and state.Uid == uid
	end
	local function wait(t)
		local w = 0
		while w < t and not state.Cancel do
			w += RunService.Heartbeat:Wait()
		end
	end
	local function flatAway(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local safe = Vector3.new(RELAY_SAFE.X, groundY(RELAY_SAFE, RELAY_SAFE.Y), RELAY_SAFE.Z)
	local function finish()
		clown.At = nil
		if semiFrozen and typeof(semi.Home) == "Vector3" and root() and not state.Cancel then
			status("Relay: the clown goes back to the player")
			place(semi.Home)
			wait(0.3)
		end
		releaseCamera()
		if semiFrozen then
			releaseView()
		end
		dropClone()
	end

	local burst
	local function ragdollGuard(around)
		local seen = state.RagdollAt
		if not (state.Ragdoll and seen and os.clock() - seen < 12) then
			return false
		end
		status("Relay: knocked down, staying still")
		slog(string.format("Relay: ragdolled %.2f s after the pickup, holding still, carrying=%s", os.clock() - (state.CarryAt or seen), tostring(held())))
		local release = holdStill()
		local stop = os.clock() + 8
		while state.Ragdoll and os.clock() < stop and not state.Cancel do
			RunService.Heartbeat:Wait()
			local r = root()
			if r then
				pcall(function()
					r.AssemblyLinearVelocity = Vector3.zero
					r.AssemblyAngularVelocity = Vector3.zero
				end)
			end
		end
		release()
		state.Ragdoll = false
		wait(0.15)
		slog(string.format("Relay: ragdoll over after %.2f s, carrying=%s", os.clock() - seen, tostring(held())))
		if not held() and not state.Cancel then
			status("Relay: taking the egg back")
			local got = burst(3, around)
			slog(string.format("Relay: egg taken back after the ragdoll=%s", tostring(got)))
		end
		return true
	end

	local function hopTo(target)
		local r = root()
		if not r then
			return false
		end
		local hopStep = RELAY_STEP
		local cruiseY = target.Y + RELAY_LIFT
		local baseGap = RELAY_GAP_MIN + math.random() * (RELAY_GAP_MAX - RELAY_GAP_MIN)
		local gap = baseGap
		local firstHop = true
		local deadline = os.clock() + 20
		local retries, shrinks = 0, 0
		while os.clock() < deadline and not state.Cancel do
			r = root()
			if not r then
				return false
			end
			local flat = Vector3.new(target.X - r.Position.X, 0, target.Z - r.Position.Z)
			local pulledBefore = state.PulledAt
			local nextPos
			if flat.Magnitude <= hopStep then
				nextPos = target
			else
				local dir = flat.Unit
				local hopY = firstHop and (r.Position.Y + 39) or cruiseY
				nextPos = Vector3.new(r.Position.X + dir.X * hopStep, hopY, r.Position.Z + dir.Z * hopStep)
			end
			local held2 = 0
			if firstHop and state.CarryAt and not state.CarryLogged then
				state.CarryLogged = true
				slog(string.format("Relay: first hop %.2f s after the carry started", os.clock() - state.CarryAt))
			end
			local paceGap = math.min(flat.Magnitude, hopStep) / math.max(walkSpeed() * (tonumber(getgenv().YslemPaceRatio) or RELAY_PACE_RATIO), 200)
			local holdFor = math.max(gap, paceGap)
			while held2 < holdFor and not state.Cancel and not state.Ragdoll do
				place(nextPos)
				held2 += RunService.Heartbeat:Wait()
			end
			if state.Ragdoll then
				ragdollGuard(nil)
				if not held() then
					return false
				end
				deadline = os.clock() + 20
				continue
			end
			local check = root()
			local pulled = state.PulledAt > pulledBefore or (check ~= nil and (check.Position - nextPos).Magnitude > 10)
			if not pulled then
				firstHop = false
				gap = RELAY_GAP_MIN + math.random() * (RELAY_GAP_MAX - RELAY_GAP_MIN)
				if nextPos == target then
					return true
				end
			else
				retries += 1
				gap = math.min(CFG.HopGapMax, gap + 0.02)
				if retries > CFG.HopRetries then
					if shrinks >= 2 then
						return false
					end
					shrinks += 1
					retries = 0
					hopStep = math.max(hopStep * 0.6, CFG.HopMin * 0.5)
				end
			end
		end
		return false
	end

	local firstPick = state.CarryAt
	local function waitWake(pinAt)
		if not firstPick or semi.WakeWait <= 0 then
			return
		end
		local need = semi.WakeWait
		local left = firstPick + need - os.clock()
		if left <= 0 then
			slog(string.format("Relay: %.1f s since the pickup, no wait needed", os.clock() - firstPick))
			return
		end
		status("Relay: letting the pickup delay pass")
		slog(string.format("Relay: holding %.1f s so that %.1f s have passed since the pickup", left, need))
		local stop = os.clock() + left
		while os.clock() < stop and held() and not state.Cancel and not (state.DeliveryFailedAt and state.DeliveryFailedAt > firstPick) do
			local r = root()
			if r and pinAt and (r.Position - pinAt).Magnitude > 2.5 then
				place(pinAt)
			end
			RunService.Heartbeat:Wait()
		end
	end

	burst = function(seconds, around)
		local cache = { At = 0, Pos = around }
		local waited, since = 0, 1
		while not held() and waited < seconds and not state.Cancel do
			if state.Ragdoll and state.RagdollAt and os.clock() - state.RagdollAt < 12 then
				RunService.Heartbeat:Wait()
				continue
			end
			local egg = eggNow(uid, cache) or around
			local r = root()
			local dt = math.max(RunService.Heartbeat:Wait(), 1 / 240)
			waited += dt
			since += dt
			if r and egg then
				place(egg + Vector3.new(0, 3.2, 0))
				pcall(function()
					local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.PlatformStand = false
						humanoid.Jump = true
					end
					r.AssemblyLinearVelocity = Vector3.new(0, 45, 0)
				end)
				if since >= CFG.GrabInterval then
					since = 0
					local prompt = promptNear(egg - Vector3.new(0, 3, 0), 10)
					if prompt and typeof(fireproximityprompt) == "function" then
						pcall(function()
							prompt.HoldDuration = 0
						end)
						pcall(fireproximityprompt, prompt)
					end
					task.spawn(takeEgg, uid)
				end
			end
		end
		return held()
	end

	if not held() then
		status("Relay: confirming the carry")
		local synced = 0
		while not held() and synced < 2.5 and not state.Cancel do
			synced += RunService.Heartbeat:Wait()
		end
		if not held() then
			return false
		end
	end

	local dropAt
	local bank = typeof(semi.Home) == "Vector3" and semi.Home or safe
	do
		local dropX = DODGE_DROP_POINT.X
		local lane = tonumber(getgenv().YslemDodgeLane) or DODGE_LANE_Z
		local cruiseY = tonumber(getgenv().YslemDodgeY) or DODGE_Y
		local dropPos = DODGE_DROP_POINT
		local r0 = root()
		local startX = r0 and r0.Position.X or dropX
		local totalDist = math.abs(startX - dropX)
		slog(string.format("Dodge: %.0f studs from x=%.0f to the drop x=%.1f on lane z=%.1f y=%.0f, %.2f s after the pickup", totalDist, startX, dropX, lane, cruiseY, firstPick and (os.clock() - firstPick) or -1))
		status("Dodge: running the chain")
		progress(0.5, "Carrying the egg")
		local dir = startX > dropX and -1 or 1
		local travelled = 0
		local pulls = 0
		local chainStart = os.clock()
		local firstFrame = true
		local chainOk = true
		while travelled < totalDist and not state.Cancel do
			local dt = firstFrame and 0 or math.min(RunService.Heartbeat:Wait(), 0.1)
			if state.Ragdoll then
				ragdollGuard(nil)
				if not held() then
					chainOk = false
					break
				end
				local rr = root()
				if rr then
					travelled = math.clamp((rr.Position.X - startX) * dir, 0, totalDist)
				end
				continue
			end
			if not held() then
				chainOk = false
				break
			end
			local speed = travelled < DODGE_BURST_STUDS and DODGE_BURST_SPEED or DODGE_CRUISE_SPEED
			local pulledBefore = state.PulledAt
			travelled = math.min(travelled + speed * dt, totalDist)
			local slowLen = DODGE_DESCENT_STUDS
			local yNow = cruiseY
			if slowLen > 0 and totalDist - travelled < slowLen then
				yNow = cruiseY + (dropPos.Y - cruiseY) * (1 - (totalDist - travelled) / slowLen)
			end
			local frac = slowLen > 0 and totalDist - travelled < slowLen and (1 - (totalDist - travelled) / slowLen) or 0
			place(Vector3.new(startX + dir * travelled, yNow, lane + (dropPos.Z - lane) * frac))
			if firstFrame then
				firstFrame = false
				if firstPick and not state.CarryLogged then
					state.CarryLogged = true
					slog(string.format("Dodge: first write %.2f s after the carry started", os.clock() - firstPick))
				end
			end
			if state.PulledAt > pulledBefore then
				pulls += 1
				slog(string.format("Dodge: the server pulled us back at %.0f studs (%d)", travelled, pulls))
				if pulls > 3 then
					chainOk = false
					break
				end
			end
		end
		slog(string.format("Dodge: chain done=%s in %.2f s", tostring(chainOk and travelled >= totalDist), os.clock() - chainStart))
		if not chainOk or state.Cancel or not held() then
			status("Dodge: the chain was interrupted")
			finish()
			return false
		end
		status("Dodge: at the drop spot")
		progress(0.65, "At the drop spot")
		local holdEnd = os.clock() + DODGE_DROP_WAIT
		local minDrop = tonumber(getgenv().YslemDodgeMinDrop) or DODGE_MIN_DROP
		if firstPick then
			holdEnd = math.max(holdEnd, firstPick + minDrop)
		end
		slog(string.format("Dodge: at the drop spot %.2f s after the pickup, holding until %.2f s", os.clock() - (firstPick or os.clock()), holdEnd - (firstPick or os.clock())))
		while os.clock() < holdEnd and not state.Cancel and held() do
			place(dropPos)
			RunService.Heartbeat:Wait()
		end
		local released = false
		for attempt = 1, 4 do
			if not held() or state.Cancel then
				break
			end
			local rr = root()
			if rr and (rr.Position - dropPos).Magnitude > 1 then
				place(dropPos)
			end
			local settleUntil = os.clock() + (attempt == 1 and 0 or math.max(0.15, 2 * netPing()))
			while os.clock() < settleUntil and not state.Cancel and held() do
				place(dropPos)
				RunService.Heartbeat:Wait()
			end
			if not held() then
				break
			end
			slog(string.format("Dodge: drop button (try %d) %.2f s after the pickup, RunBackWakeDelayRequired=%s", attempt, os.clock() - (firstPick or os.clock()), tostring(state.WakeReq)))
			dropEgg()
			local dropUntil = os.clock() + 0.3
			while held() and os.clock() < dropUntil and not state.Cancel do
				place(dropPos)
				RunService.Heartbeat:Wait()
			end
			if not held() then
				break
			end
		end
		released = not held()
		if not released then
			slog("Dodge: the drop did not go through")
			status("Dodge: the drop did not go through")
			finish()
			return false
		end
		local droppedAt = os.clock()
		dropAt = nil
		local polled = 0
		while polled < 3 and not state.Cancel do
			dropAt = eggNow(uid, { At = 0 })
			if dropAt then
				break
			end
			place(dropPos)
			wait(0.1)
			polled += 0.1
		end
		if dropAt and (dropAt - dropPos).Magnitude > 1500 then
			state.NestBack = true
			slog(string.format("the egg went back to its nest %.2f s after the pickup", os.clock() - (firstPick or os.clock())))
			finish()
			status("The egg went back to its nest")
			return false
		end
		slog(string.format("Dodge: egg seen after the drop at %s, %.0f studs from the drop spot", dropAt and string.format("%.1f %.1f %.1f", dropAt.X, dropAt.Y, dropAt.Z) or "nowhere", dropAt and (dropAt - dropPos).Magnitude or -1))
		plantClown(dropPos)
		progress(0.75, "Egg dropped")
		status("Dodge: treadmill before the regrab")
		local okTread = treadmillReset()
		slog(string.format("Dodge: treadmill before the regrab done=%s, %.2f s after the drop", tostring(okTread), os.clock() - droppedAt))
		local back = clown.At or dropPos
		slog(string.format("Dodge: re-teleport to the clown at %.1f %.1f %.1f", back.X, back.Y, back.Z))
		place(back)
		local regrabEnd = droppedAt + DODGE_REGRAB_WAIT
		while os.clock() < regrabEnd and not state.Cancel do
			place(back)
			RunService.Heartbeat:Wait()
		end
		progress(0.85, "Taking the egg back")
		status("Dodge: taking the egg back")
		dropAt = eggNow(uid, { At = 0 }) or dropAt
		if dropAt then
			place(dropAt + Vector3.new(0, 3.2, 0))
		end
		local got = burst(1.5, dropAt or back)
		slog(string.format("Dodge: taken back=%s %.2f s after the drop, RunBackWakeDelayRequired=%s", tostring(got), os.clock() - droppedAt, tostring(state.WakeReq)))
		if not got and not state.Cancel then
			local again = eggNow(uid, { At = 0 }) or dropAt
			if again then
				place(again + Vector3.new(0, 3.2, 0))
			end
			got = burst(2.5, again or dropAt or back)
		end
		if not got and not state.Cancel then
			place(back)
			wait(0.2)
			local last = eggNow(uid, { At = 0 }) or dropAt or back
			got = burst(3, last)
		end
		if not got then
			slog("Dodge: could not take the egg back")
			status("Could not take the egg back")
			finish()
			return false
		end
		progress(0.93, "Bringing it home")
		status("Dodge: running to the clown's spot")
		slog(string.format("Dodge: running to the clown's spot %.1f %.1f %.1f, %.2f s after the pickup", bank.X, bank.Y, bank.Z, os.clock() - (firstPick or os.clock())))
		do
			local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.PlatformStand = false
			end
			local runEnd = os.clock() + 25
			local lastRun = os.clock()
			while not state.Cancel and state.Delivered < started and os.clock() < runEnd and held() do
				local rr = root()
				if not rr then
					break
				end
				if state.Ragdoll then
					ragdollGuard(nil)
					continue
				end
				local nowRun = os.clock()
				local dtRun = math.min(nowRun - lastRun, 0.1)
				lastRun = nowRun
				local toBank = Vector3.new(bank.X - rr.Position.X, 0, bank.Z - rr.Position.Z)
				if toBank.Magnitude < 2 then
					break
				end
				local aim = avoid(rr.Position, bank)
				local flat = Vector3.new(aim.X - rr.Position.X, 0, aim.Z - rr.Position.Z)
				local stepLen = math.min(DODGE_CRUISE_SPEED * dtRun, toBank.Magnitude)
				local dir2 = flat.Magnitude > 0.01 and flat.Unit or toBank.Unit
				place(Vector3.new(rr.Position.X + dir2.X * stepLen, bank.Y, rr.Position.Z + dir2.Z * stepLen))
				RunService.Heartbeat:Wait()
			end
			pcall(function()
				local rr = root()
				if rr then
					rr.AssemblyLinearVelocity = Vector3.zero
				end
			end)
		end
		local verdictBy = os.clock() + 4
		while not state.Cancel and state.Delivered < started and os.clock() < verdictBy do
			RunService.Heartbeat:Wait()
		end
		slog(string.format("Dodge: verdict=%s %.2f s after the pickup", tostring(state.Delivered >= started), os.clock() - (firstPick or os.clock())))
	end
	status("Relay: waiting for the deposit")
	local depositBy = os.clock() + 8
	while not state.Cancel and state.Delivered < started and os.clock() < depositBy do
		if state.Ragdoll then
			ragdollGuard(nil)
			depositBy = os.clock() + 8
		end
		wait(0.1)
	end
	slog(string.format("Relay: banked=%s", tostring(state.Delivered >= started)))
	if state.Delivered < started and firstPick and state.DeliveryFailedAt and state.DeliveryFailedAt > firstPick then
		semi.WakeWait = math.min(15, semi.WakeWait + 2.5)
		slog(string.format("Relay: the server refused the delivery %.1f s after the pickup, next try waits %.1f s", state.DeliveryFailedAt - firstPick, semi.WakeWait))
	end
	if state.Delivered < started and held() and not state.Cancel then
		local lineX, _, _ = lineInfo()
		local r = root()
		local laneZ = r and math.clamp(r.Position.Z, -425, -300) or -364
		slog("Relay: no deposit from the safe zone, running home")
		local wasSlow = semi.SlowRun
		semi.SlowRun = true
		local okHome = runHome(lineX, laneZ)
		semi.SlowRun = wasSlow
		finish()
		return okHome
	end
	finish()
	return state.Delivered >= started
end

local function instantTP(uid)
	local started = os.clock()
	local lineX, lineY = lineInfo()
	local r = root()
	if not r then
		return false
	end
	local laneZ = math.clamp(r.Position.Z, -425, -300)
	local hopZ = math.clamp(r.Position.Z, -425, -300)
	local semiFrozen = viewState ~= nil
	local landing = Vector3.new(lineX + CFG.LandOffset, lineY + 3.35, laneZ)
	local semiOnly = semiFrozen and semi.Kind ~= "decoy" and not semi.Plain
	local semiEnd = (semiFrozen and not semi.Plain) or semi.SlowRun == true

	-- hops towards the line; a pull-back repeats the same hop with a longer pause (the pause is learned)
	local hopStep = math.max(walkSpeed() * CFG.HopRatio * (semiOnly and 0.85 or 1), CFG.HopMin)
	local hopY = r.Position.Y + CFG.HopLift
	local x = r.Position.X
	local retries = 0
	local shrinks = 0
	local releaseCamera = semiFrozen and function() end or frozenCamera()
	state.ReleaseCamera = releaseCamera
	if not semiFrozen then
		pcall(postClone)
	end
	if not semi.Dodge then
		fpsOn()
	end
	if semiFrozen or method == "Relay" then
		local okRelay = relayFlow(uid, started, releaseCamera, semiFrozen)
		fpsOff()
		return okRelay
	end

	while x - hopStep > landing.X and not state.Cancel do
		if not state.Carrying then
			-- the server let go of the egg on the way: take it back right away
			if not regrab(uid) then
				break
			end
			local current = root()
			if current then
				x = math.min(x, current.Position.X)
			end
			continue
		end

		local nextX = x - hopStep
		status(string.format("Instant TP: hopping home, X %d", math.floor(nextX)))
		local pulledBefore = state.PulledAt
		local held = 0
		while held < CFG.HopGap do
			place(Vector3.new(nextX, hopY, hopZ))
			held += RunService.Heartbeat:Wait()
		end

		local check = root()
		local pulled = state.PulledAt > pulledBefore or (check ~= nil and (check.Position.X - nextX > 10 or check.AssemblyLinearVelocity.Magnitude > 150))
		if pulled and state.Carrying and not state.Cancel then
			retries += 1
			CFG.HopGap = math.min(CFG.HopGapMax, CFG.HopGap + 0.02)
			if retries > CFG.HopRetries then
				if shrinks >= 2 then
					break
				end
				shrinks += 1
				retries = 0
				hopStep = math.max(hopStep * 0.6, CFG.HopMin * 0.5)
				CFG.HopGap = CFG.HopGapMax
				status(string.format("Instant TP: pulled back too often, shorter hops (%d/2)", shrinks))
			end
			status(string.format("Instant TP: pulled back, retry %d/%d", retries, CFG.HopRetries))
			local settle = 0
			while settle < 0.12 and not state.Cancel do
				place(Vector3.new(x, hopY, hopZ))
				settle += RunService.Heartbeat:Wait()
			end
		else
			x = nextX
			CFG.HopGap = math.max(CFG.HopGapMin, CFG.HopGap - 0.01)
		end
	end

	-- landing in front of the line
	status("Instant TP: landing next to the line")
	landing = Vector3.new(landing.X, groundY(landing, landing.Y), landing.Z)
	local function onSpot()
		local current = root()
		return current ~= nil and current.Position.X <= landing.X + 12 and math.abs(current.Position.Y - landing.Y) <= 10
	end
	local function land()
		local current = root()
		-- never jump backwards: if we are already on the landing spot, stay
		if current and current.Position.X <= landing.X + 1 and math.abs(current.Position.Y - landing.Y) <= 10 then
			pcall(function()
				current.AssemblyLinearVelocity = Vector3.zero
			end)
			return
		end
		place(landing)
	end
	land()
	for attempt = 1, 5 do
		local settle = 0
		while settle < CFG.LandSettle and not state.Cancel do
			settle += RunService.Heartbeat:Wait()
		end
		if state.Carrying and not onSpot() then
			status("Instant TP: landing retry " .. attempt)
			land()
		else
			break
		end
	end
	dropClone()

	-- drop at the line (only when we really stand on the spot, and only once the server confirmed it), take it back
	if state.Carrying and not state.Cancel then
		local delay = 0
		while delay < CFG.DropDelay do
			delay += RunService.Heartbeat:Wait()
		end
		if state.Carrying and not state.Cancel and not onSpot() then
			land()
			local settle = 0
			while settle < CFG.LandSettle and not state.Cancel do
				settle += RunService.Heartbeat:Wait()
			end
		end
		if not state.Carrying or state.Cancel then
			-- nothing to drop
		elseif not onSpot() then
			status("Instant TP: not on the drop spot, going home with the egg")
		else
			status("Instant TP: dropping the egg")
			if semiFrozen then
				local at = root()
				if at then
					slog(string.format("Instant TP: the clown drops the egg at x=%.0f z=%.0f (line %+.0f)", at.Position.X, at.Position.Z, at.Position.X - lineX))
				end
			end
			for _ = 1, 3 do
				dropEgg()
				local waited = 0
				while state.Carrying and waited < 0.8 and not state.Cancel do
					waited += RunService.Heartbeat:Wait()
				end
				if not state.Carrying or state.Cancel then
					break
				end
				status("Instant TP: the drop was not confirmed, trying again")
				if not onSpot() then
					land()
				end
			end
			local current = root()
			if current then
				pcall(function()
					current.AssemblyLinearVelocity = Vector3.zero
					current.AssemblyAngularVelocity = Vector3.zero
				end)
			end
			-- the server may send a dropped egg straight back to its nest: then there is nothing to take back, and no long teleport to chase it
			local dropSpot = root()
			if dropSpot and not state.Cancel then
				local looked = 0
				while looked < 0.25 and not state.Cancel do
					looked += RunService.Heartbeat:Wait()
				end
				local lies = eggNow(uid, { At = 0 })
				if lies then
					local away = (lies - dropSpot.Position).Magnitude
					slog(string.format("timeline: the egg lies %.0f studs from the drop spot %.2f s after the drop", away, looked))
					if away > 120 then
						state.NestBack = true
						slog("the egg went back to its nest after the drop")
						releaseCamera()
						if semiFrozen then
							releaseView()
						end
						dropClone()
						fpsOff()
						status("The egg went back to its nest")
						return false
					end
				end
			end
			-- egg is down: let go of the camera and the copy, then take it back
			releaseCamera()
			if semiFrozen and semi.AtDrop == true then
				releaseView()
			end
			dropClone()
			status("Instant TP: taking the egg back")
			local tookBack = grab(uid, 3) or regrab(uid)
			for _ = 1, 3 do
				if tookBack or state.Cancel then
					break
				end
				status("Instant TP: the egg is not in the hands yet, trying again")
				tookBack = regrab(uid) or grab(uid, 2)
			end
			if not tookBack then
				fpsOff()
				status("Could not take the egg back")
				return false
			end
			dropClone()
		end
	end
	releaseCamera()

	-- safe zone: Semi TP ends with teleports (never a run unless both fail), the rest keeps the run
	local ok = false
	local function goHome()
		if semiEnd then
			for round = 1, 2 do
				if tpHome(lineX, laneZ, started) then
					return true
				end
				if not state.Carrying or state.Cancel then
					return state.Delivered >= started
				end
				status(string.format("Instant TP: teleport home again (%d/2)", round))
			end
		end
		return runHome(lineX, laneZ)
	end
	if state.Carrying then
		ok = goHome()
	end
	local again = 0
	while not ok and state.Delivered < started and not state.Cancel and again < 2 do
		again += 1
		status(string.format("Instant TP: not delivered yet, going home again (%d/2)", again))
		if not state.Carrying and not regrab(uid) then
			break
		end
		local current = root()
		if current and current.Position.X > lineX + 8 then
			place(Vector3.new(lineX + 8, math.max(current.Position.Y, lineY + 3.35), current.Position.Z))
			RunService.Heartbeat:Wait()
		end
		ok = goHome()
	end
	fpsOff()
	return ok or state.Delivered >= started
end

-- after a failed Semi TP: the body goes back to the front of the base by itself (hops like the delivery)
local function returnFront()
	local reached = false
	pcall(function()
		local waited = 0
		while root() and root().Position.Y > 5000 and waited < 8 and not state.Cancel do
			waited += RunService.Heartbeat:Wait()
		end
		local r = root()
		if not r or state.Cancel then
			return
		end
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
		local lineX = lineInfo()
		local home = homePoint()
		local hopZ = math.clamp(r.Position.Z, -425, -300)
		local frontX = lineX - 7
		local hopStep = math.max(walkSpeed() * CFG.HopRatio * 0.85, CFG.HopMin)
		local hopY = r.Position.Y + CFG.HopLift
		local x = r.Position.X
		local gap = CFG.HopGap
		local retries, shrinks = 0, 0
		status("Going back to the front")
		while x - frontX > hopStep and not state.Cancel do
			local nextX = x - hopStep
			local pulledBefore = state.PulledAt
			local held = 0
			while held < gap and not state.Cancel do
				place(Vector3.new(nextX, hopY, hopZ))
				held += RunService.Heartbeat:Wait()
			end
			local check = root()
			local pulled = state.PulledAt > pulledBefore or (check ~= nil and check.Position.X - nextX > 10)
			if pulled then
				retries += 1
				gap = math.min(CFG.HopGapMax, gap + 0.02)
				if retries > CFG.HopRetries then
					if shrinks >= 2 then
						break
					end
					shrinks += 1
					retries = 0
					hopStep = math.max(hopStep * 0.6, CFG.HopMin * 0.5)
				end
				local settle = 0
				while settle < 0.12 and not state.Cancel do
					place(Vector3.new(x, hopY, hopZ))
					settle += RunService.Heartbeat:Wait()
				end
			else
				x = nextX
			end
		end
		if state.Cancel then
			return
		end
		for _, target in ipairs({ Vector3.new(frontX, home.Y, hopZ), home }) do
			local held = 0
			while held < math.max(gap, 0.1) and not state.Cancel do
				place(target)
				held += RunService.Heartbeat:Wait()
			end
		end
		local settle = 0
		while settle < 0.4 and not state.Cancel do
			settle += RunService.Heartbeat:Wait()
		end
		local at = root()
		reached = at ~= nil and Vector3.new(at.Position.X - home.X, 0, at.Position.Z - home.Z).Magnitude <= 20
	end)
	return reached
end

------------------------------------------------------------------ Semi TP: portal by touch (the only route, no alternative)
-- Returns true plus { Arrived, Ratio, Decoy } or false plus the reason. The player stays frozen (copy + camera) while the body works.
local function semiGo(uid, egg)
	local startRoot = root()
	if not startRoot then
		return false, "Semi TP: no character yet"
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local startCF = startRoot.CFrame
	local cache = { At = 0, Pos = egg }
	local function eggPos()
		return eggNow(uid, cache) or egg
	end
	local function eggPart()
		local node = workspace:FindFirstChild(uid)
		local slots = workspace:FindFirstChild("AreaEggSlotsClient")
		node = node or (slots and slots:FindFirstChild(uid))
		if not node then
			return nil
		end
		if node:IsA("BasePart") then
			return node
		end
		return node:FindFirstChild("Hitbox", true) or node:FindFirstChildWhichIsA("BasePart", true)
	end

	local camera = workspace.CurrentCamera
	local camOffset = camera and (camera.CFrame.Position - startRoot.Position) or Vector3.new(0, 8, 14)
	local camRot = camera and camera.CFrame.Rotation or CFrame.new()

	semi.Kind, semi.AtDrop, semi.Home, semi.Plain = nil, false, nil, false
	slog(string.format("Semi TP from %.0f,%.0f,%.0f to the egg %.0f,%.0f,%.0f", startRoot.Position.X, startRoot.Position.Y, startRoot.Position.Z, egg.X, egg.Y, egg.Z))

	if Vector3.new(egg.X - startRoot.Position.X, 0, egg.Z - startRoot.Position.Z).Magnitude <= 60 then
		-- egg next to us: no portal. The copy waits at home, the body runs to the egg and brings it back.
		semi.Kind = "decoy"
		semi.AtDrop = true
		local spotAt = startRoot.Position
		local okFreeze = freezeView(character, Vector3.zero, nil)
		semi.Home = okFreeze and spotAt or nil
		slog("egg close: decoy at home, frozen=" .. tostring(okFreeze))
		return true, { Decoy = true }
	end

	semi.Kind = "semi"
	semi.AtDrop = true
	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end
	local shieldSince = os.clock()
	while not swapped() and os.clock() - shieldSince < 5 and not state.Cancel do
		pcall(function()
			local r0 = root()
			if r0 then
				r0.AssemblyLinearVelocity = Vector3.zero
			end
			if humanoid then
				humanoid:Move(Vector3.zero, false)
			end
		end)
		RunService.Heartbeat:Wait()
	end
	slog(string.format("shield=%s after %.2f s", tostring(swapped()), os.clock() - shieldSince))
	local safeStand = Vector3.new(RELAY_SAFE.X, groundY(RELAY_SAFE, RELAY_SAFE.Y), RELAY_SAFE.Z)
	local atNow = root()
	local lineNow = lineInfo()
	local needMove = atNow and Vector3.new(atNow.Position.X - safeStand.X, 0, atNow.Position.Z - safeStand.Z).Magnitude > 3
	if needMove then
		if atNow.Position.X > lineNow + 100 then
			status("Semi TP: hopping back to the base first")
			returnFront()
			if state.Cancel then
				return false, "cancelled"
			end
		end
		status("Semi TP: going to the safe-zone point")
		place(safeStand)
		for _ = 1, 8 do
			RunService.Heartbeat:Wait()
		end
		pcall(function()
			local r1 = root()
			if r1 then
				r1.AssemblyLinearVelocity = Vector3.zero
				r1.AssemblyAngularVelocity = Vector3.zero
			end
		end)
	end
	local freezeAt = root()
	local freezeSpot = freezeAt and freezeAt.Position or safeStand
	local function freezeNow()
		return freezeView(character, Vector3.zero, CFrame.new(freezeSpot + camOffset) * camRot)
	end
	local okFreeze = freezeNow()
	if not okFreeze then
		releaseView()
		okFreeze = freezeNow()
	end
	semi.Home = okFreeze and freezeSpot or nil
	slog("player frozen at the safe-zone point = " .. tostring(okFreeze))
	for _ = 1, 6 do
		RunService.Heartbeat:Wait()
	end
	pcall(function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			semi.Rotate = { Hum = hum, Old = hum.AutoRotate }
			hum.AutoRotate = false
		end
	end)

	local stableRot = startRoot.CFrame.Rotation
	pcall(function()
		local flat = Vector3.new(egg.X - startRoot.Position.X, 0, egg.Z - startRoot.Position.Z)
		if flat.Magnitude > 1 then
			stableRot = CFrame.lookAt(Vector3.zero, flat).Rotation
		end
	end)
	local function placeAt(p)
		local r = root()
		if r then
			pcall(function()
				r.CFrame = CFrame.new(p) * stableRot
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
	local function inBiome()
		local r = root()
		return r ~= nil and r.Position.Y > 5000
	end
	local function jumpNow()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				hum.Jump = true
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
		end
	end
	local function holdPause(t)
		local w = 0
		while w < t and not state.Cancel do
			w += RunService.Heartbeat:Wait()
		end
	end

	local groundSkip, groundSkipAt = nil, 0
	local function groundAt(pos, from)
		local found = nil
		pcall(function()
			if not groundSkip or os.clock() - groundSkipAt > 1 then
				groundSkip = { stealClone }
				groundSkipAt = os.clock()
				local slots = workspace:FindFirstChild("AreaEggSlotsClient")
				if slots then
					groundSkip[#groundSkip + 1] = slots
				end
				for _, child in ipairs(workspace:GetChildren()) do
					if child:IsA("Model") and #child.Name == 32 and child:FindFirstChild("Hitbox") then
						groundSkip[#groundSkip + 1] = child
					end
				end
			end
			local list = { localPlayer.Character }
			for _, v in ipairs(groundSkip) do
				list[#list + 1] = v
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = list
			params.IgnoreWater = true
			pcall(function()
				params.RespectCanCollide = true
			end)
			local origin = Vector3.new(pos.X, from, pos.Z)
			for _ = 1, 4 do
				local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
				if not hit then
					break
				end
				if hit.Material ~= Enum.Material.Water and hit.Instance.CanCollide and hit.Instance.Transparency < 0.95 then
					found = hit.Position
					break
				end
				origin = hit.Position - Vector3.new(0, 0.05, 0)
			end
		end)
		return found
	end
	local function standHeight()
		local h = 3
		pcall(function()
			local character2 = localPlayer.Character
			local r = root()
			local hum = character2 and character2:FindFirstChildOfClass("Humanoid")
			if character2 and r then
				local box, boxSize = character2:GetBoundingBox()
				local value = r.Position.Y - (box.Position.Y - boxSize.Y / 2)
				if value > 1 and value < 12 then
					h = value
				end
				if hum and hum.HipHeight > 0.2 then
					local exact = hum.HipHeight + r.Size.Y / 2
					if exact > 1 and exact < 12 then
						h = exact
					end
				end
			end
		end)
		return h + 0.05
	end
	local approachDir = nil
	pcall(function()
		local flat = Vector3.new(startRoot.Position.X - egg.X, 0, startRoot.Position.Z - egg.Z)
		if flat.Magnitude > 1 then
			approachDir = flat.Unit
		end
	end)
	local function landFor(at, high)
		local dir = approachDir or Vector3.new(-1, 0, 0)
		local stand = 2.5
		pcall(function()
			local part = eggPart()
			if part and part.CanCollide then
				stand = math.clamp(math.sqrt(part.Size.X ^ 2 + part.Size.Z ^ 2) / 2 + 2.2, 2.5, 7)
			end
		end)
		local base = Vector3.new(at.X + dir.X * stand, at.Y + 3, at.Z + dir.Z * stand)
		if high then
			local top = groundAt(base, at.Y + 160)
			if top and math.abs(top.Y - at.Y) < 150 then
				return Vector3.new(base.X, top.Y + standHeight(), base.Z)
			end
			return nil
		end
		local hit = groundAt(base, at.Y + 6)
		if hit and math.abs(hit.Y - at.Y) < 12 then
			return Vector3.new(base.X, hit.Y + standHeight(), base.Z)
		end
		hit = groundAt(base, at.Y + 40)
		if hit and math.abs(hit.Y - at.Y) < 40 then
			return Vector3.new(base.X, hit.Y + standHeight(), base.Z)
		end
		return base
	end
	semi.LandFor = landFor

	-- the biome has no usable exit by itself: wait for the game's automatic return, then look for an exit, then step back
	local function zoneRoots()
		local out = {}
		local base = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
		base = base and base:FindFirstChild("Build")
		for _, name in ipairs({ "FuseBiomeZone", "EnchantedTreeInterior" }) do
			local node = base and base:FindFirstChild(name)
			if node then
				out[#out + 1] = node
			end
		end
		return out
	end
	local function zoneExits()
		local list, all = {}, {}
		for _, zone in ipairs(zoneRoots()) do
			for _, d in ipairs(zone:GetDescendants()) do
				all[#all + 1] = d
			end
		end
		local good = { "exit", "leave", "return", "back", "home", "portal", "gate", "door", "out", "teleport", "warp", "spawn", "lobby", "world", "main" }
		local bad = { "fusion", "shrine", "pad", "place", "sell", "buy", "shop", "lion", "whale" }
		local function score(inst, extra)
			local label = string.lower(inst.Name .. " " .. (inst.Parent and inst.Parent.Name or "") .. " " .. (extra or ""))
			for _, w in ipairs(bad) do
				if string.find(label, w, 1, true) then
					return 0
				end
			end
			for _, w in ipairs(good) do
				if string.find(label, w, 1, true) then
					return 1
				end
			end
			return 0
		end
		pcall(function()
			for _, d in ipairs(all) do
				if d:IsA("ProximityPrompt") and score(d, d.ActionText .. " " .. d.ObjectText) > 0 then
					list[#list + 1] = d
				elseif d:IsA("BasePart") and d.Size.Magnitude < 250 and score(d) > 0 then
					list[#list + 1] = d
				end
				if #list >= 16 then
					break
				end
			end
		end)
		return list
	end
	local function leaveByExits()
		local list = zoneExits()
		local function posOf(c)
			if c:IsA("ProximityPrompt") then
				local part = c.Parent
				local reach = math.max(3, math.min(c.MaxActivationDistance - 1.5, 8))
				if part and part:IsA("BasePart") then
					return part.Position, reach
				end
				if part and part:IsA("Attachment") then
					return part.WorldPosition, reach
				end
				return nil, 0
			end
			return c.Position, 1.5
		end
		local tried = {}
		local deadline = os.clock() + 16
		while os.clock() < deadline and not state.Cancel do
			if not inBiome() then
				return true
			end
			local r0 = root()
			if not r0 then
				break
			end
			local best, bestD, bestReach, bestPos
			for _, c in ipairs(list) do
				if not tried[c] and c.Parent then
					local tp, rc = posOf(c)
					if tp then
						local d = (tp - r0.Position).Magnitude
						if semi.ExitPath and c:GetFullName() == semi.ExitPath then
							d = d - 1e6
						end
						if not bestD or d < bestD then
							best, bestD, bestReach, bestPos = c, d, rc, tp
						end
					end
				end
			end
			if not best then
				break
			end
			tried[best] = true
			slog("walking to " .. best.Name)
			bestD = math.max(bestD, 0)
			local speed = math.max(walkSpeed() * 1.1, walkSpeed() * 1.8, 22)
			local legEnd = os.clock() + math.min(bestD / speed + 1.5, 7)
			local lastJump = 0
			while os.clock() < legEnd and os.clock() < deadline and not state.Cancel do
				if not inBiome() then
					pcall(function()
						semi.ExitPath = best:GetFullName()
					end)
					slog("out through " .. best.Name)
					return true
				end
				local r = root()
				local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
				if not r or not hum then
					break
				end
				local flat = Vector3.new(bestPos.X - r.Position.X, 0, bestPos.Z - r.Position.Z)
				local dist = (r.Position - bestPos).Magnitude
				if best:IsA("ProximityPrompt") and dist <= bestReach + 1 then
					if typeof(fireproximityprompt) == "function" then
						pcall(fireproximityprompt, best)
					end
					local w = 0
					while w < 1.2 and inBiome() and not state.Cancel do
						w += RunService.Heartbeat:Wait()
					end
					break
				end
				pcall(function()
					hum:MoveTo(bestPos)
					if flat.Magnitude > 2 then
						local dir = flat.Unit
						r.AssemblyLinearVelocity = Vector3.new(dir.X * speed, r.AssemblyLinearVelocity.Y, dir.Z * speed)
					end
				end)
				if os.clock() - lastJump > 0.7 and (dist < 14 or (r.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude < 1) then
					lastJump = os.clock()
					jumpNow()
				end
				RunService.Heartbeat:Wait()
			end
		end
		return not inBiome()
	end
	local function walkOut()
		status("Semi TP: waiting for the return")
		local t0 = os.clock()
		while inBiome() and os.clock() - t0 < 5.5 and not state.Cancel do
			RunService.Heartbeat:Wait()
		end
		if not inBiome() then
			return true
		end
		leaveByExits()
		if not inBiome() then
			return true
		end
		local arrival = root() and root().Position or nil
		local backDirs = {}
		do
			local r = root()
			if r then
				local look = r.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.1 then
					backDirs[#backDirs + 1] = -flat.Unit
					backDirs[#backDirs + 1] = flat.Unit
				end
			end
			backDirs[#backDirs + 1] = Vector3.new(-1, 0, 0)
		end
		local stepsDone = 0
		for _, dir in ipairs(backDirs) do
			for _ = 1, 2 do
				if not inBiome() or state.Cancel then
					break
				end
				local r = root()
				if r and arrival then
					local origin = r.Position
					local moveEnd = os.clock() + 0.45
					while inBiome() and os.clock() < moveEnd and not state.Cancel do
						pcall(function()
							r.AssemblyLinearVelocity = Vector3.new(dir.X * 110, 0, dir.Z * 110)
						end)
						RunService.Heartbeat:Wait()
						if (r.Position - origin).Magnitude >= 30 or r.Position.Y < arrival.Y - 6 then
							break
						end
					end
					pcall(function()
						r.AssemblyLinearVelocity = Vector3.zero
					end)
				end
				stepsDone += 1
				task.wait(0.15)
			end
			if not inBiome() then
				break
			end
			if arrival and root() then
				placeAt(arrival)
			end
		end
		slog("went back " .. stepsDone .. " times, inBiome=" .. tostring(inBiome()))
		local t1 = os.clock()
		while inBiome() and os.clock() - t1 < 8 and not state.Cancel do
			RunService.Heartbeat:Wait()
		end
		return not inBiome()
	end

	local touchWon = nil
	do
		status("Dodge: jump to the egg")
		touchWon = semi.DodgeRoute({ Uid = uid, EggPos = eggPos, LandFor = landFor, Grab = grab })
		slog("Dodge route: " .. tostring(touchWon))
		if not touchWon then
			releaseView()
			local r = root()
			if r then
				pcall(function()
					r.CFrame = startCF
					r.AssemblyLinearVelocity = Vector3.zero
					r.AssemblyAngularVelocity = Vector3.zero
				end)
			end
			task.wait(0.2)
			return false, "Dodge: the jump to the egg was not accepted"
		end
		semi.Plain = true
		return true, { Arrived = true, Plain = true }
	end
	return true, { Plain = true }
end

local worldResetTime, lastResetCheck = 0, 0
task.spawn(function()
	while alive do
		task.wait(1)
		if state.Busy then
			local now = os.clock()
			if now - lastResetCheck >= 1 then
				lastResetCheck = now
				local okClock, clock = pcall(function()
					return game:GetService("Lighting").ClockTime
				end)
				local wt = okClock and tonumber(clock) or 0
				if wt < 0.5 and worldResetTime > 0 and os.clock() - worldResetTime > 60 then
					worldResetTime = 0
					state.Cancel = true
					status("World reset detected")
				elseif wt >= 0.5 then
					worldResetTime = now
				end
			end
		end
	end
end)

------------------------------------------------------------------ H-Claim: frozen at HCLAIM, the clown fetches the egg through the Halloween portal
local HCLAIM = Vector3.new(-5819.16, -199.64, -7387.18)
local ALTV = Vector3.new(-5806.25, -203.38, -7196.68)

-- the attribute can stay true after a teleport out: the body must also really be in the dimension
local DIM_CENTER = Vector3.new(-5800, -200, -6200)
local function inDimension()
	if localPlayer:GetAttribute("InHalloweenDimension") ~= true then
		return false
	end
	local r = root()
	return r == nil or (r.Position - DIM_CENTER).Magnitude < 4000
end





local function stopMotion()
	local r = root()
	if r then
		pcall(function()
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end)
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid.PlatformStand = false
			humanoid:Move(Vector3.zero, false)
		end)
	end
end



-- through a portal: the thinnest axis of the part is the way through, from the side we are on, then from the other side
local hopTo



-- a real teleport: ONE position write onto the target (held 0.15 s), checked (no Relocate, within 8 studs); a rewind repeats the same
-- teleport at once, several times; only after that do the chains of hops / steps take over
local function tpTo(target, tries)
	local waited = os.clock()
	while not swapped() and os.clock() - waited < 5 and not state.Cancel do
		RunService.Heartbeat:Wait()
	end
	local character = localPlayer.Character
	for attempt = 1, tries or 6 do
		local r = root()
		if state.Cancel or not r or localPlayer.Character ~= character then
			return false
		end
		if (r.Position - target).Magnitude <= 4 then
			stopMotion()
			return true
		end
		local pulledBefore = state.PulledAt
		local held = 0
		while held < 0.15 and not state.Cancel do
			place(target)
			held += RunService.Heartbeat:Wait()
		end
		local check = root()
		if state.PulledAt <= pulledBefore and check ~= nil and (check.Position - target).Magnitude <= 8 then
			slog(string.format("H-Claim: teleport held (attempt %d)", attempt))
			stopMotion()
			return true
		end
		slog(string.format("H-Claim: teleport rewound (attempt %d), again", attempt))
	end
	return false
end

semi.TpTo = tpTo




-- Instant TP hops toward a point (step = walk speed x 1.515, a pull-back repeats the hop, shorter hops after too many)
hopTo = function(target, maxHops)
	local waited = os.clock()
	while not swapped() and os.clock() - waited < 5 and not state.Cancel do
		RunService.Heartbeat:Wait()
	end
	local character = localPlayer.Character
	local step = math.max(walkSpeed() * CFG.HopRatio, CFG.HopMin)
	local gap = CFG.HopGap
	local retries, shrinks = 0, 0
	for _ = 1, maxHops or 70 do
		local r = root()
		if state.Cancel or not r or localPlayer.Character ~= character then
			return false
		end
		local delta = target - r.Position
		if delta.Magnitude <= 2 then
			return true
		end
		local nextPos = delta.Magnitude <= step and target or (r.Position + delta.Unit * step)
		local pulledBefore = state.PulledAt
		local held = 0
		while held < gap and not state.Cancel do
			place(nextPos)
			held += RunService.Heartbeat:Wait()
		end
		local check = root()
		if state.PulledAt > pulledBefore or (check ~= nil and (check.Position - nextPos).Magnitude > 10) then
			-- a rewind: the same hop again at once (the pause only grows after three in a row)
			retries += 1
			if retries > 3 then
				gap = math.min(CFG.HopGapMax, gap + 0.02)
			end
			if retries > 12 then
				if shrinks >= 2 then
					return false
				end
				shrinks += 1
				retries = 0
				step = math.max(step * 0.6, CFG.HopMin * 0.5)
			end
		else
			retries = 0
		end
	end
	local r = root()
	return r ~= nil and (target - r.Position).Magnitude <= 6
end








local function getOffTreadmill()
	for _ = 1, 3 do
		local r = root()
		if not r or not r.Anchored or state.Cancel then
			return true
		end
		local askDoff = remote("RF/Treadmill/AskDoff")
		if askDoff and askDoff:IsA("RemoteFunction") then
			pcall(askDoff.InvokeServer, askDoff)
		end
		local held, limit = 0, 1.5 + netPing()
		while held < limit and not state.Cancel do
			local rr = root()
			if not rr or not rr.Anchored then
				return true
			end
			held += RunService.Heartbeat:Wait()
		end
	end
	local r = root()
	return not (r and r.Anchored)
end

semi.DodgeRoute = function(ctx)
	local function held()
		return state.Carrying and state.Uid == ctx.Uid
	end
	local function near(a, b, d)
		return a and b and Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude <= d
	end
	local function pinFor(point, t, stopWhen)
		local w = 0
		while w < t and not state.Cancel do
			if stopWhen and stopWhen() then
				return true
			end
			local r = root()
			if r and (r.Position - point).Magnitude > 1 then
				place(point)
			end
			w += RunService.Heartbeat:Wait()
		end
		return stopWhen ~= nil and stopWhen() or false
	end
	if not root() then
		return false
	end
	getOffTreadmill()
	local eggPos = ctx.EggPos()
	local at = ctx.LandFor(eggPos)
	if not at then
		slog("Dodge route: no ground next to the egg")
		return false
	end
	local from = DODGE_BASE
	place(DODGE_BASE)
	pinFor(DODGE_BASE, 0.15)
	local ping = netPing()
	local r1Wait, r2Wait = DODGE_R1_WAIT + ping, DODGE_R2_WAIT + ping
	local pickDelay = math.max(DODGE_PICK_DELAY, ping * 2.5)
	local before = state.PulledAt
	local jumpAt = os.clock()
	place(at)
	progress(0.15, "Jumping onto the egg")
	slog(string.format("Dodge route: jump of %.0f studs from %.0f %.0f %.0f to %.1f %.1f %.1f", (at - from).Magnitude, from.X, from.Y, from.Z, at.X, at.Y, at.Z))
	local r1 = pinFor(at, r1Wait, function()
		return state.PulledAt > before
	end)
	local r1At = r1 and state.PulledAt or nil
	local r2At = nil
	if r1At then
		local toStart = state.RelocPos and near(state.RelocPos, at, 25) and "the arrival" or (state.RelocPos and string.format("%.0f %.0f %.0f", state.RelocPos.X, state.RelocPos.Y, state.RelocPos.Z) or "?")
		slog(string.format("Dodge route: R1 %.2f s after the jump, target %s", r1At - jumpAt, toStart))
		if state.RelocPos and near(state.RelocPos, at, 25) then
			r2At = r1At
		else
			local tripStart = os.clock()
			pinFor(DODGE_TRIP, DODGE_TRIP_HOLD)
			place(at)
			slog(string.format("Dodge route: round trip held %.2f s, back on the arrival", os.clock() - tripStart))
			local mark = state.PulledAt
			pinFor(at, r2Wait, function()
				if state.PulledAt > mark then
					mark = state.PulledAt
					if state.RelocPos and near(state.RelocPos, at, 25) then
						r2At = state.PulledAt
						return true
					end
				end
				return false
			end)
		end
	else
		slog(string.format("Dodge route: no Relocate within %.2f s after the jump (ping %.0f ms)", r1Wait, ping * 1000))
	end
	if r2At then
		slog(string.format("Dodge route: R2 to the arrival %.2f s after R1", r2At - (r1At or r2At)))
	elseif r1At then
		slog("Dodge route: no R2 to the arrival: the server did not accept the jump, back to the base")
		place(DODGE_BASE)
		return false
	end
	progress(0.3, "Jump accepted")
	plantClown(at)
	pinFor(at, math.max(0, (r2At or os.clock()) + pickDelay - os.clock()))
	local since, waited = 1, 0
	while not held() and waited < 2.5 and not state.Cancel do
		local r = root()
		local egg = ctx.EggPos() or eggPos
		if r and (r.Position - at).Magnitude > 1.5 then
			place(at)
		end
		local dt = RunService.Heartbeat:Wait()
		waited += dt
		since += dt
		if since >= CFG.GrabInterval then
			since = 0
			local prompt = promptNear(egg, 12)
			if prompt and typeof(fireproximityprompt) == "function" then
				pcall(function()
					prompt.HoldDuration = 0
				end)
				pcall(fireproximityprompt, prompt)
			end
			task.spawn(takeEgg, ctx.Uid)
		end
	end
	if not held() and not state.Cancel then
		ctx.Grab(ctx.Uid, 1)
	end
	if held() then
		progress(0.4, "Egg taken")
	end
	slog(string.format("Dodge route: carrying=%s %.2f s after the jump", tostring(held()), os.clock() - jumpAt))
	if not held() then
		place(DODGE_BASE)
		return false
	end
	return "near"
end



-- blackout: a black screen over the game and every game sound at zero for the whole trip, nothing seen and nothing heard on this screen
local blackout = { Enabled = false, Gui = nil, Sounds = {}, Links = {}, MasterOld = nil }

function blackout.mute(sound)
	if not sound:IsA("Sound") or blackout.Sounds[sound] ~= nil then
		return
	end
	blackout.Sounds[sound] = sound.Volume
	pcall(function()
		sound.Volume = 0
	end)
	blackout.Links[#blackout.Links + 1] = sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if blackout.Gui and sound.Volume ~= 0 then
			sound.Volume = 0
		end
	end)
end

function blackout.setPet(name, icon, value)
	blackout.Pet = { Name = name, Icon = icon, Value = value }
	local ui = blackout.Ui
	if blackout.Gui and ui then
		pcall(function()
			ui.Name.Text = tostring(name or "")
			ui.Icon.Image = tostring(icon or "")
			ui.Value.Text = value and money(value) or ""
		end)
	end
end

function blackout.set(frac, text)
	local ui = blackout.Ui
	if not (blackout.Gui and ui) then
		return
	end
	frac = math.clamp(tonumber(frac) or 0, 0, 1)
	if frac == 0 then
		blackout.Frac = 0
	else
		blackout.Frac = math.max(blackout.Frac or 0, frac)
	end
	pcall(function()
		ui.Fill.Size = UDim2.fromScale(blackout.Frac, 1)
		ui.Pct.Text = string.format("%d%%", math.floor(blackout.Frac * 100 + 0.5))
	end)
end

state.Progress = function(frac, text)
	blackout.set(frac, text)
end

function blackout.on()
	return -- blackout removido: nunca cria a tela preta nem muta som
end

function blackout.off()
	local screen = blackout.Gui
	if not screen then
		return
	end
	blackout.Gui = nil
	blackout.Ui = nil
	for _, link in ipairs(blackout.Links) do
		pcall(function()
			link:Disconnect()
		end)
	end
	blackout.Links = {}
	for sound, volume in pairs(blackout.Sounds) do
		pcall(function()
			sound.Volume = volume
		end)
	end
	blackout.Sounds = {}
	pcall(function()
		if blackout.MasterOld ~= nil then
			UserSettings():GetService("UserGameSettings").MasterVolume = blackout.MasterOld
		end
	end)
	blackout.MasterOld = nil
	pcall(function()
		screen:Destroy()
	end)
	slog("blackout off")
end

local MAX_ATTEMPTS = 3

local function stealAndDeliver(uid, attempt)
	attempt = attempt or 1
	if state.Busy then
		return
	end
	state.Busy = true
	state.Cancel = false
	state.Died = false
	progress(0, attempt > 1 and string.format("Retry %d/%d", attempt, MAX_ATTEMPTS) or "Starting")
	state.Hits = 0
	state.Ragdoll = false
	worldResetTime, lastResetCheck = 0, 0
	blackout.on()
	local tripChar = localPlayer.Character
	task.spawn(function()
		while state.Busy and alive do
			task.wait(0.05)
			local now = localPlayer.Character
			local hum = tripChar and tripChar:FindFirstChildOfClass("Humanoid")
			if now ~= tripChar or not tripChar or (hum and hum.Health <= 0) then
				if state.Busy and not state.Cancel then
					state.Died = true
					state.Cancel = true
					status("Died: stopped, waiting for the respawn")
					slog("the body died, the trip is stopped and nothing moves the new body")
				end
				return
			end
		end
	end)
	task.spawn(function()
		local semiTrip = true
		local delivered = false
		local failReason = nil
		local ok, err = pcall(function()
			status("Looking for the egg")
			pcall(function()
				for _, record in ipairs(snapshot()) do
					if record.Uid == uid then
						local info = describe(record)
						blackout.setPet(info.Name, info.Icon, info.Value)
						return
					end
				end
			end)
			progress(0.04, "Looking for the egg")
			local egg = eggPosition(uid)
			if not egg then
				status("That egg is gone")
				return
			end
			if state.Carrying and state.Uid ~= uid then
				dropEgg()
				local waited = 0
				while state.Carrying and waited < 1 do
					waited += RunService.Heartbeat:Wait()
				end
			end
			state.NestBack = false
			if semiTrip then
				local r1 = root()
				local lineX1 = lineInfo()
				if r1 and r1.Position.Y < 5000 and not inDimension() and r1.Position.X > lineX1 + 800 and (egg - r1.Position).Magnitude > 100 then
					slog(string.format("Semi TP: the body stands %.0f studs past the line, hopping back to the base first", r1.Position.X - lineX1))
					status("Semi TP: hopping back to the base first")
					returnFront()
					if state.Cancel then
						return
					end
				end
			end
			status("Going to the egg")
			progress(0.08, "Going to the egg")
			local reached
			if semiTrip then
				local okSemi, info = semiGo(uid, egg)
				if not okSemi then
					failReason = info
					status("Could not reach the egg")
					return
				end
				semi.SlowRun = not (info.Plain or semi.Plain)
				local inHand = state.Carrying and state.Uid == uid
				local current = egg
				if not inHand then
					current = eggNow(uid, { At = 0, Pos = egg }) or egg
				end
				if info.Arrived or inHand then
					reached = true
				elseif info.Plain then
					reached = runToEgg(uid, current)
				elseif info.Decoy then
					reached = runToEgg(uid, current, { Field = true, Ratio = 1 })
				else
					reached = runToEgg(uid, current, { Field = true, Ratio = info.Ratio or 1.1, Height = 50 })
				end
			else
				reached = runToEgg(uid, egg)
			end
			if not reached then
				failReason = failReason or "could not reach the egg"
				status("Could not reach the egg")
				return
			end
			local inHandNow = state.Carrying and state.Uid == uid
			if not inHandNow then
				status("Taking the egg")
			end
			if not inHandNow and not grab(uid, 4) then
				local taken = false
				if not state.Cancel then
					slog("the egg would not come free: back to the safe zone, treadmill reset, one more try")
					local safeAt = Vector3.new(RELAY_SAFE.X, groundY(RELAY_SAFE, RELAY_SAFE.Y), RELAY_SAFE.Z)
					local here = root()
					if here and here.Position.X > lineInfo() + 100 then
						returnFront()
					end
					if not state.Cancel then
						place(safeAt)
						local calm = 0
						while calm < 0.15 and not state.Cancel do
							calm += RunService.Heartbeat:Wait()
						end
						treadmillReset()
						place(safeAt)
						calm = 0
						while calm < 0.15 and not state.Cancel do
							calm += RunService.Heartbeat:Wait()
						end
						local current = eggNow(uid, { At = 0, Pos = egg }) or egg
						if runToEgg(uid, current, { Field = true, Ratio = RUN_RATIO }) then
							taken = grab(uid, 4)
						end
					end
				end
				if not taken then
					failReason = "the egg would not come free"
					status("The egg would not come free")
					return
				end
			end
			delivered = instantTP(uid)
			if not delivered then
				failReason = state.NestBack and "the egg went back to its nest after the drop" or "delivery failed"
			end
			status(delivered and "Delivered" or "Delivery failed")
			if delivered then
				progress(1, "Delivered")
			end
		end)
		fpsOff()
		dropClone()
		if state.ReleaseCamera then
			pcall(state.ReleaseCamera)
			state.ReleaseCamera = nil
		end
		semi.SlowRun = false
		semi.AtDrop = false
		semi.Plain = false
		if state.Died then
			local from = os.clock()
			while os.clock() - from < 15 and (localPlayer.Character == tripChar or not root()) do
				task.wait(0.1)
			end
			local calm = os.clock()
			while os.clock() - calm < 2.5 and not (swapped() and os.clock() - calm > 1.5) do
				task.wait(0.1)
			end
			if viewState then
				releaseView()
			end
		elseif viewState and viewState.Forced then
			slog("H-Claim: the view stays frozen (forced)")
		elseif viewState then
			if state.Cancel and semi.Home then
				releaseBackHome(semi.Home)
			else
				releaseView()
			end
		end
		semi.Kind, semi.Home = nil, nil
		if semi.Rotate then
			local info = semi.Rotate
			semi.Rotate = nil
			pcall(function()
				info.Hum.AutoRotate = info.Old
			end)
		end
		if not ok then
			failReason = failReason or tostring(err)
			status("Error: " .. tostring(err))
		end
		slog("delivery " .. (delivered and "DONE" or "NOT done") .. ", " .. tostring(failReason or ""))

		local why0 = tostring(failReason or "")
		local willRetry = not delivered and not state.Cancel and not state.Died and attempt < MAX_ATTEMPTS and not string.find(why0, "no character", 1, true)
		if willRetry then
			status("Delivery failed, treadmill then retry")
			slog(string.format("attempt %d/%d failed (%s): clean restart through the treadmill", attempt, MAX_ATTEMPTS, why0))
			local function wait(t)
				local w = 0
				while w < t and not state.Cancel do
					w += RunService.Heartbeat:Wait()
				end
			end
			if state.Carrying then
				dropEgg()
				local w = 0
				while state.Carrying and w < 1 and not state.Cancel do
					w += RunService.Heartbeat:Wait()
				end
			end
			wait(0.6)
			local here = root()
			if here and here.Position.X > lineInfo() + 100 and not state.Cancel then
				returnFront()
			end
			if not state.Cancel then
				treadmillReset()
				wait(0.4)
			end
			willRetry = not state.Cancel and not state.Died and root() ~= nil
		end

		-- Semi TP failed: the body goes back to the front by itself, and if that is not enough the player gets an instruction
		if willRetry then
			semi.Fails = semi.Fails + 1
		elseif semiTrip then
			if delivered then
				semi.Fails, semi.ResetDone = 0, false
			elseif not state.Cancel then
				semi.Fails += 1
				local untilAt = os.clock() + 1.5
				while os.clock() < untilAt and not state.Cancel do
					RunService.Heartbeat:Wait()
				end
				local why = tostring(failReason or "unknown")
				if string.find(why, "portal not there", 1, true) then
					status("Semi TP: no portal now. Set Go to Run")
				elseif not semi.ResetDone then
					semi.ResetDone = true
					status("Semi TP failed, going back to the front")
					returnFront()
				else
					status("Semi TP failed again. Press Steal again")
				end
			end
		end
		state.Busy = false
		if willRetry then
			slog(string.format("restarting the steal, attempt %d/%d", attempt + 1, MAX_ATTEMPTS))
			stealAndDeliver(uid, attempt + 1)
		else
			blackout.off()
		end
	end)
end

------------------------------------------------------------------
-- INTEGRAÇÃO YSLEM EGG NA ABA STEAL DO R7FLOW
-- O motor do yslemEgg foi mantido; somente a janela independente
-- foi substituída por controles dentro de containerSteal.
------------------------------------------------------------------
local EggUI_WHITE = Color3.fromRGB(235, 235, 240)
local EggUI_SILVER = Color3.fromRGB(150, 150, 156)
local EggUI_STEEL = Color3.fromRGB(70, 70, 76)
local EggUI_BG = Color3.fromRGB(10, 10, 13)
local EggUI_RARITY_COLORS = {
    Color3.fromRGB(190, 190, 190), Color3.fromRGB(110, 210, 110),
    Color3.fromRGB(90, 160, 255), Color3.fromRGB(190, 110, 255),
    Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 80, 80),
    Color3.fromRGB(255, 90, 200), Color3.fromRGB(80, 235, 235),
}

local function eggUiMake(className, props)
    local inst = Instance.new(className)
    for key, value in pairs(props or {}) do
        inst[key] = value
    end
    return inst
end

local function eggUiCorner(parent, radius)
    eggUiMake("UICorner", {CornerRadius = UDim.new(0, radius or 6)}).Parent = parent
end

local function eggUiStroke(parent, thickness, bright)
    local s = eggUiMake("UIStroke", {
        Thickness = thickness or 1,
        Color = bright and EggUI_SILVER or EggUI_STEEL,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
    s.Parent = parent
    return s
end

local function eggUiText(parent, props)
    props.BackgroundTransparency = 1
    props.TextColor3 = props.TextColor3 or EggUI_WHITE
    local label = eggUiMake("TextLabel", props)
    label.Parent = parent
    return label
end

-- Lista de ovos disponíveis
local eggList = eggUiMake("ScrollingFrame", {
    Name = "YslemEggList",
    Size = UDim2.new(1, -4, 0, 126),
    Position = UDim2.fromOffset(2, 0),
    BackgroundColor3 = EggUI_BG,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = ROXO,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ZIndex = 4,
})
eggList.Parent = containerSteal
eggUiCorner(eggList, 7)
eggUiStroke(eggList, 1, false)
eggUiMake("UIListLayout", {
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
}).Parent = eggList
eggUiMake("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
}).Parent = eggList

local eggStatusLabel = eggUiText(containerSteal, {
    Size = UDim2.new(1, -8, 0, 14),
    Position = UDim2.fromOffset(4, 129),
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "Selecione um ovo",
    TextColor3 = TXT,
    ZIndex = 4,
})

-- Botões compactos integrados ao layout original
local function eggUiButton(label, xScale, xOffset, widthScale, widthOffset)
    local button = eggUiMake("TextButton", {
        Size = UDim2.new(widthScale, widthOffset, 0, 27),
        Position = UDim2.new(xScale, xOffset, 0, 151),
        BackgroundColor3 = BG_BTN,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = EggUI_WHITE,
        Text = label,
        AutoButtonColor = true,
        ZIndex = 5,
    })
    button.Parent = containerSteal
    eggUiCorner(button, 6)
    eggUiStroke(button, 1, true)
    return button
end

local refreshButton = eggUiButton("ATUALIZAR", 0, 2, 0.40, -3)
local stealButton = eggUiButton("PEGAR", 0.40, 3, 0.60, -5)

local selectedUid = nil
local eggRows = {}

local function setSelected(uid)
    selectedUid = uid
    for rowUid, row in pairs(eggRows) do
        local selected = rowUid == uid
        row.Stroke.Thickness = selected and 1.5 or 1
        row.Stroke.Color = selected and EggUI_WHITE or EggUI_STEEL
        row.Frame.BackgroundColor3 = selected
            and Color3.fromRGB(30, 30, 38) or EggUI_BG
    end
end

local listSignature = nil
local function rebuildEggList(force)
    local infos = {}
    for _, record in ipairs(snapshot()) do
        infos[#infos + 1] = describe(record)
    end

    table.sort(infos, function(a, b)
        return a.Value > b.Value
    end)

    local parts = {}
    for index, info in ipairs(infos) do
        parts[index] = tostring(info.Uid) .. ":" .. tostring(info.Value)
    end
    local signature = table.concat(parts, ",")

    if not force and signature == listSignature then
        return
    end
    listSignature = signature

    for _, row in pairs(eggRows) do
        if row.Frame then
            row.Frame:Destroy()
        end
    end
    table.clear(eggRows)

    local selectionStillExists = false
    for index, info in ipairs(infos) do
        selectionStillExists = selectionStillExists or info.Uid == selectedUid

        local row = eggUiMake("TextButton", {
            Size = UDim2.new(1, 0, 0, 31),
            BackgroundColor3 = EggUI_BG,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Text = "",
            AutoButtonColor = true,
            ZIndex = 5,
        })
        row.Parent = eggList
        eggUiCorner(row, 6)
        local rowStroke = eggUiStroke(row, 1, false)

        eggUiMake("ImageLabel", {
            Size = UDim2.fromOffset(25, 25),
            Position = UDim2.fromOffset(3, 3),
            BackgroundTransparency = 1,
            Image = info.Icon,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 6,
        }).Parent = row

        eggUiText(row, {
            Size = UDim2.new(1, -35, 0, 14),
            Position = UDim2.fromOffset(32, 2),
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = info.Name,
            TextColor3 = EggUI_RARITY_COLORS[
                math.clamp(info.Rarity, 1, #EggUI_RARITY_COLORS)
            ] or EggUI_WHITE,
            ZIndex = 6,
        })

        eggUiText(row, {
            Size = UDim2.new(1, -35, 0, 12),
            Position = UDim2.fromOffset(32, 16),
            Font = Enum.Font.GothamMedium,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = money(info.Value),
            TextColor3 = TXT_DIM,
            ZIndex = 6,
        })

        eggRows[info.Uid] = {Frame = row, Stroke = rowStroke}
        row.MouseButton1Click:Connect(function()
            setSelected(info.Uid)
            status("Selected: " .. info.Name)
        end)
    end

    setSelected(selectionStillExists and selectedUid or nil)
    if #infos == 0 then
        status("Pick a pet")
    end
end

-- O status do motor passa a aparecer dentro da aba STEAL
local PUBLIC_EGG_STATUS = {
    ["Pick a pet"] = "Selecione um ovo",
    ["That egg is gone"] = "Esse ovo não está mais disponível",
    ["Delivered"] = "Ovo entregue!",
    ["Delivery failed"] = "Falha na entrega",
    ["Delivery failed, treadmill then retry"] = "Falha; tentando novamente",
    ["Cancelling"] = "Cancelando...",
}
status = function(message)
    message = tostring(message)
    if PUBLIC_EGG_STATUS[message] then
        eggStatusLabel.Text = PUBLIC_EGG_STATUS[message]
    elseif string.sub(message, 1, 9) == "Selected:" then
        eggStatusLabel.Text = "Selecionado: " .. string.sub(message, 10)
    elseif string.sub(message, 1, 5) == "Error" then
        eggStatusLabel.Text = "Ocorreu um erro"
    elseif state.Busy then
        eggStatusLabel.Text = "Executando entrega..."
    else
        eggStatusLabel.Text = message
    end
end

refreshButton.MouseButton1Click:Connect(function()
    if viewState and viewState.Forced then
        releaseView()
        semi.Kind, semi.Home = nil, nil
        return
    end
    if not state.Busy then
        rebuildEggList(true)
    end
end)

pcall(function()
    getgenv().YslemUnfreeze = function()
        releaseView()
        semi.Kind, semi.Home = nil, nil
    end
end)

stealButton.MouseButton1Click:Connect(function()
    if state.Busy then
        state.Cancel = true
        status("Cancelling")
        return
    end
    if not selectedUid then
        status("Pick a pet")
        return
    end
    stealAndDeliver(selectedUid)
end)

-- Mantém os rótulos dos botões sincronizados com o estado real
task.spawn(function()
    while holder and holder.Parent and gui and gui.Parent do
        task.wait(0.25)
        stealButton.Text = state.Busy and "CANCELAR" or "PEGAR"
        refreshButton.Text = (viewState and viewState.Forced)
            and "DESCONGELAR" or "ATUALIZAR"
    end
end)

rebuildEggList(true)

task.spawn(function()
    while holder and holder.Parent and gui and gui.Parent do
        task.wait(4)
        if not state.Busy and containerSteal.Visible then
            rebuildEggList(false)
        end
    end
end)

shieldStart()
end -- iniciarSistemaYslemEgg

iniciarSistemaYslemEgg()
