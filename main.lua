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

-- ABA STEAL — AUTO-STEAL INTEGRADO
local function iniciarSistemaSteal()
    local StealCfg = {
        SpeedCap = 1.15, HopRatio = 1.515, HopMin = 40, HopGap = 0.06, HopGapMin = 0.06,
        HopGapMax = 0.2, HopRetries = 6, HopLift = 42, LandOffset = 14, LandSettle = 0.08,
        DropDelay = 0.05, GrabInterval = 0.03, RegrabFar = 40, Height = 70,
        ClimbShare = 0.5, CarryRatio = 0.9, EasyRatio = 1.3,
    }
    local FpsSeq = { 60, 30, 0.15 }
    local FlightHeight = 10

    local S = {
        Carrying = false, Uid = nil, Delivered = 0, Busy = false, Cancel = false,
        Paused = false, Mult = 1, PulledAt = 0, HeldSeen = 0, GuessedDrop = false,
    }

    local statusSteal = nil

    local function status(msg)
        if statusSteal then statusSteal(tostring(msg)) end
    end

    local function root()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    -- ---------- SHIELD ----------
    local shield = { Active = false, Original = nil, Clone = nil, Links = {}, HB = nil, Added = nil }

    local function walkSpeed()
        local ch = LocalPlayer.Character
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        local speed = h and h.WalkSpeed or 16
        if shield.Original and shield.Original.Health > 0 then
            speed = math.min(speed, shield.Original.WalkSpeed)
        end
        pcall(function()
            local stat = LocalPlayer:FindFirstChild("leaderstats")
            stat = stat and stat:FindFirstChild("Speed")
            if stat then
                local util = require(ReplicatedStorage.Shared.Util.TreadmillUtil)
                local v = util.SpeedPowerToWalkSpeed(stat.Value)
                if type(v) == "number" and v > 0 then speed = math.min(speed, v) end
            end
        end)
        return speed
    end

    local function shieldControls(h)
        pcall(function()
            local s = LocalPlayer:FindFirstChild("PlayerScripts")
            local m = s and s:FindFirstChild("PlayerModule")
            if m then
                local c = require(m):GetControls()
                if type(c) == "table" then c.humanoid = h end
            end
        end)
    end

    local function shieldAnimate(ch)
        local a = ch and ch:FindFirstChild("Animate")
        if a and a:IsA("LocalScript") then
            task.spawn(function() a.Enabled = false task.wait() a.Enabled = true end)
        end
    end

    local function shieldUnlink()
        for _, l in ipairs(shield.Links) do pcall(function() l:Disconnect() end) end
        table.clear(shield.Links)
    end

    local groundedStates = {
        [Enum.HumanoidStateType.Running] = true,
        [Enum.HumanoidStateType.RunningNoPhysics] = true,
        [Enum.HumanoidStateType.Landed] = true,
    }
    local function grounded(h)
        if not h or h.Health <= 0 or h.FloorMaterial == Enum.Material.Air then return false end
        return groundedStates[h:GetState()] == true
    end

    local function shieldSwap()
        if not shield.Active then return end
        local ch = LocalPlayer.Character
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        if not h or h.Health <= 0 then return end
        if shield.Clone and shield.Clone.Parent == ch then return end
        if not grounded(h) then return end
        local clone = h:Clone()
        h.Parent = nil
        clone.Parent = ch
        workspace.CurrentCamera.CameraSubject = clone
        shieldControls(clone)
        shieldAnimate(ch)
        shield.Original = h
        shield.Clone = clone
        table.insert(shield.Links, h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if clone.Parent ~= nil then clone.WalkSpeed = h.WalkSpeed end
        end))
        local a1 = h:FindFirstChildOfClass("Animator")
        local a2 = clone:FindFirstChildOfClass("Animator")
        if a1 and a2 then
            table.insert(shield.Links, a1.AnimationPlayed:Connect(function(played)
                local anim = played.Animation
                if not anim or clone.Parent == nil then return end
                local ok, track = pcall(function() return a2:LoadAnimation(anim) end)
                if not ok or not track then return end
                pcall(function()
                    track.Priority = played.Priority
                    track.Looped = played.Looped
                    track:Play(0.05, math.max(played.WeightTarget, 0.01), played.Speed)
                end)
                played.Stopped:Connect(function() pcall(function() track:Stop(0.1) end) end)
            end))
        end
        table.insert(shield.Links, clone.Died:Connect(function()
            shieldUnlink()
            shield.Original, shield.Clone = nil, nil
            local c = LocalPlayer.Character
            if c and h.Parent == nil then
                h.Parent = c
                workspace.CurrentCamera.CameraSubject = h
                shieldControls(h)
            end
            pcall(function() clone:Destroy() end)
            h.Health = 0
        end))
    end

    local function shieldStart()
        if shield.Active then return end
        shield.Active = true
        shieldSwap()
        local n = 0
        shield.HB = RunService.Heartbeat:Connect(function(dt)
            if not shield.Active then return end
            n += dt
            local ch = LocalPlayer.Character
            local miss = not (shield.Clone and ch and shield.Clone.Parent == ch)
            if (miss and 0.25 or 3) <= n then n = 0 shieldSwap() end
        end)
        shield.Added = LocalPlayer.CharacterAdded:Connect(function(ch)
            if not shield.Active then return end
            shieldUnlink()
            shield.Original, shield.Clone = nil, nil
            task.spawn(function()
                ch:WaitForChild("Humanoid", 10)
                task.wait(1)
                if shield.Active then shieldSwap() end
            end)
        end)
    end

    local function shieldStop()
        if not shield.Active then return end
        shield.Active = false
        if shield.HB then shield.HB:Disconnect() shield.HB = nil end
        if shield.Added then shield.Added:Disconnect() shield.Added = nil end
        shieldUnlink()
        if shield.Original and shield.Clone then
            local ch = LocalPlayer.Character
            if ch and shield.Clone.Parent == ch then
                pcall(function() shield.Clone:Destroy() end)
                pcall(function()
                    shield.Original.Parent = ch
                    workspace.CurrentCamera.CameraSubject = shield.Original
                    shieldControls(shield.Original)
                end)
            end
        end
        shield.Original, shield.Clone = nil, nil
    end

    -- ---------- RARITY ----------
    local RarityScore = {
        ["Light & Dark"]=1300,["Titan"]=1100,["Divine"]=1000,["Transcendent"]=1000,
        ["Superior"]=1000,["Eternal"]=900,["Limited"]=900,["Secret"]=800,["Exotic"]=800,
        ["Cosmic"]=700,["Exclusive"]=700,["Admin"]=700,["Mythic"]=600,["Mythical"]=600,
        ["Prismatic"]=600,["Rainbow"]=600,["Squishy God"]=600,["BrainrotGod"]=600,
        ["Legendary"]=500,["Epic"]=400,["Rare"]=300,["SuperRare"]=200,["Celestial"]=200,
        ["Uncommon"]=200,["Basic"]=100,["Common"]=100,
    }

    local rarityFilterEnabled = false
    local targetRarity = "Todos"
    local rarityOptions = { "Todos","Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine" }
    local rarityIdx = 1

    local iconCacheSteal = {}
    local function getPetIconSteal(record)
        if not record then return nil end
        local targetName = record.Pet or record.PetId or record.PetName
            or record.AssetCategory or record.Category
        if targetName and iconCacheSteal[targetName] then
            return iconCacheSteal[targetName]
        end
        local rawIcon = record.Icon or record.PetIcon or record.ImageAsset or record.TextureId
        local result
        local function normalizeIcon(value)
            if value == nil or value == "" then return nil end
            local valueStr = tostring(value)
            if valueStr:match("^rbxassetid://") or valueStr:match("://") then
                return valueStr
            end
            if valueStr:match("^%d+$") then return "rbxassetid://" .. valueStr end
            return nil
        end
        result = normalizeIcon(rawIcon)
        if not result and targetName and PetsData then
            local info = (PetsData.Directory or PetsData)[targetName]
            if type(info) == "table" then
                result = normalizeIcon(info.Icon or info.Image or info.AssetId)
            end
        end
        if not result and targetName and AssetsData then
            local info = (AssetsData.Directory or AssetsData)[targetName]
            if type(info) == "table" then
                result = normalizeIcon(info.Icon or info.Image or info.AssetId)
            end
        end
        if targetName and result then iconCacheSteal[targetName] = result end
        return result
    end

    -- ---------- SNAPSHOT ----------
    local function snapshot()
        if type(EggState) ~= "table" then return {} end
        local list = {}
        if type(EggState.ReadFieldEggs) == "function" then
            local ok, snap = pcall(EggState.ReadFieldEggs)
            if ok and snap and snap.Records then
                for _, r in ipairs(snap.Records) do
                    if r and r.BoundsCFrame and (r.State == "Slot" or r.State == "Dropped") then
                        list[#list + 1] = r
                    end
                end
            end
        end
        return list
    end

    local function eggPosition(uid)
        for _, r in ipairs(snapshot()) do
            if r.Uid == uid then return r.BoundsCFrame.Position end
        end
        return nil
    end

    local function getRarityName(record)
        if not record then return "Common" end
        local name
        if record.Rarity then
            local r = record.Rarity
            name = type(r) == "table" and (r.DisplayName or r._id or r.Name) or tostring(r)
        end
        if not name then
            local info = AssetsData and (AssetsData.Directory or AssetsData)
            info = info and info[tostring(record.AssetCategory or record.Category or record.Name or "")]
            if info and info.Rarity then
                local r = info.Rarity
                name = type(r) == "table" and (r.DisplayName or r._id or r.Name) or tostring(r)
            end
        end
        return name or "Common"
    end

    local function getEggValue(record)
        local cat = tostring(record.AssetCategory or record.Category or record.Name or "Egg")
        local info = AssetsData and (AssetsData.Directory or AssetsData)
        info = info and info[cat]
        local raw = tonumber(
            record.Income or record.EarningRate or record.MoneyPerSecond or
            record.Money or record.Cash or record.Value or record.Price or 0
        ) or 0
        if raw <= 0 and type(info) == "table" then
            raw = tonumber(info.Income or info.EarningRate or info.MoneyPerSecond or
                info.Money or info.Cash or info.SalePrice or info.Price or 0) or 0
        end
        local scale = tonumber(record.AssetScale or record.Scale or record.NestScale) or 1
        local val = raw * scale
        if val <= 0 then
            local score = RarityScore[getRarityName(record)] or 100
            local area = tonumber(tostring(record.AreaId or ""):match("%d+")) or 50
            val = score * math.max(area, 50) * math.max(scale, 1)
        end
        return val
    end

    local function money(v)
        v = tonumber(v) or 0
        if v >= 1e15 then return string.format("%.1fQ", v/1e15)
        elseif v >= 1e12 then return string.format("%.1fT", v/1e12)
        elseif v >= 1e9 then return string.format("%.1fB", v/1e9)
        elseif v >= 1e6 then return string.format("%.1fM", v/1e6)
        elseif v >= 1e3 then return string.format("%.1fK", v/1e3)
        else return string.format("%d", math.floor(v + 0.5)) end
    end

    -- ---------- TAKE / DROP ----------
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
    local function promptNear(pos, radius)
        local best, bd = nil, radius
        for _, child in ipairs(workspace:GetChildren()) do
            if child.Name == "SmartPromptPart" and child:IsA("BasePart") then
                local p = child:FindFirstChild("CarryAreaEgg")
                if p and p:IsA("ProximityPrompt") then
                    local d = (child.Position - pos).Magnitude
                    if d < bd then best, bd = p, d end
                end
            end
        end
        return best
    end
    local function heldByMe(uid)
        local ch = LocalPlayer.Character
        if type(uid) ~= "string" or not ch then return false end
        local egg = workspace:FindFirstChild(uid)
        if not egg then return false end
        for _, d in ipairs(egg:GetDescendants()) do
            if d:IsA("WeldConstraint") or d:IsA("JointInstance") then
                local ok, a, b = pcall(function() return d.Part0, d.Part1 end)
                if ok and ((a and a:IsDescendantOf(ch)) or (b and b:IsDescendantOf(ch))) then return true end
            end
        end
        return false
    end

    -- ---------- LISTENER ----------
    if type(EggState) == "table" and type(EggState.CarryChanged) == "table"
        and type(EggState.CarryChanged.Connect) == "function" then
        EggState.CarryChanged:Connect(function(arg)
            local c = type(arg) == "table" and arg.IsCarrying == true
            if c and arg.GuardDisabled == true then c = false end
            S.GuessedDrop = false
            if c then S.HeldSeen = os.clock() end
            if c and type(arg.Uid) == "string" then
                S.Uid = arg.Uid
                local m = tonumber(arg.SpeedMultiplier)
                if m and m > 0 then S.Mult = m end
            end
            S.Carrying = c
        end)
    end

    pcall(function()
        local pkg = ReplicatedStorage:FindFirstChild("Packages")
        local net = pkg and pkg:FindFirstChild("Networking")
        local r = net and net:FindFirstChild("RE/EggWorld/FieldEggRedeemVerdict")
        if r then r.OnClientEvent:Connect(function() S.Delivered = os.clock() end) end
    end)
    pcall(function()
        local pkg = ReplicatedStorage:FindFirstChild("Packages")
        local net = pkg and pkg:FindFirstChild("Networking")
        local r = net and net:FindFirstChild("RE/RigSync/Refresh")
        if r then r.OnClientEvent:Connect(function(arg)
            if type(arg) == "table" and arg.Action == "Relocate" then S.PulledAt = os.clock() end
        end) end
    end)

    task.spawn(function()
        while true do
            task.wait(0.2)
            if not S.Carrying then
                if S.GuessedDrop and heldByMe(S.Uid) then
                    S.GuessedDrop, S.Carrying, S.HeldSeen = false, true, os.clock()
                end
            elseif heldByMe(S.Uid) then
                S.HeldSeen = os.clock()
            elseif os.clock() - S.HeldSeen > 0.8 then
                S.Carrying, S.GuessedDrop = false, true
            end
        end
    end)

    -- ---------- MOVIMENTO ----------
    local function frozenCamera()
        local cam = workspace.CurrentCamera
        if not cam then return function() end end
        local ot = cam.CameraType
        local fr = cam.CFrame
        pcall(function() cam.CameraType = Enum.CameraType.Scriptable cam.CFrame = fr end)
        return function() pcall(function() cam.CameraType = ot end) end
    end

    local fpsGen = 0
    local function fpsOn()
        if typeof(setfpscap) ~= "function" then return end
        fpsGen += 1
        local mine = fpsGen
        task.spawn(function()
            local high = true
            local st = os.clock()
            while fpsGen == mine and os.clock() - st < 60 do
                pcall(setfpscap, high and FpsSeq[1] or FpsSeq[2])
                high = not high
                task.wait(FpsSeq[3])
            end
        end)
    end
    local function fpsOff()
        fpsGen += 1
        if typeof(setfpscap) == "function" then pcall(setfpscap, 240) end
    end

    local stealClone = nil
    local function dropClone()
        if stealClone then pcall(function() stealClone:Destroy() end) stealClone = nil end
    end
    local function postClone()
        dropClone()
        local ch = LocalPlayer.Character
        if not ch then return end
        local was = ch.Archivable
        ch.Archivable = true
        local copy = ch:Clone()
        ch.Archivable = was
        if copy then
            for _, d in ipairs(copy:GetDescendants()) do
                if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") then
                    pcall(function() d:Destroy() end)
                elseif d:IsA("BasePart") then
                    d.Anchored = true d.CanCollide = false d.CanTouch = false d.CanQuery = false
                end
            end
            copy.Name = "PHZClone"
            copy.Parent = workspace
            stealClone = copy
        end
    end

    local function lineInfo()
        local w = workspace:FindFirstChild("World") or workspace:FindFirstChild("__OBJECTS")
        w = w and w:FindFirstChild("Areas")
        w = w and w:FindFirstChild("SeparationLine")
        local ok = w and w:IsA("BasePart")
        return ok and w.Position.X or 552.2, ok and w.Position.Y or 67.67
    end
    local function homePoint()
        for _, def in ipairs({
            { { "GearGiver_Slap", "Podium" }, Vector3.new(-16.415, 21.072, -6.106) },
            { { "World", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
            { { "__OBJECTS", "Machines", "RiftMachine", "Rift", "Meshes/VoidPortal_Cube.003" }, Vector3.new(-26.776, 1.75, 18.665) },
        }) do
            local n = workspace
            for _, name in ipairs(def[1]) do n = n and n:FindFirstChild(name) or nil end
            if n and n:IsA("BasePart") then return n.CFrame:PointToWorldSpace(def[2]) end
        end
        return Vector3.new(528.7, 70.57, -364.11)
    end
    local function place(pos)
        local r = root()
        if not r then return end
        pcall(function()
            r.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0)
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local dangerCache, dangerAt = {}, 0
    local function dangers()
        if os.clock() - dangerAt < 1 then return dangerCache end
        dangerAt = os.clock()
        local list = {}
        local function add(inst)
            local ok, cf, size = pcall(function()
                if inst:IsA("Model") then return inst:GetBoundingBox()
                elseif inst:IsA("BasePart") then return inst.CFrame, inst.Size end
            end)
            if ok and cf and size then
                local half = Vector3.new(math.abs(size.X), 0, math.abs(size.Z)) * 0.5
                local rot = (cf - cf.Position):VectorToWorldSpace(half)
                local rx = math.max(math.abs(rot.X), half.X, half.Z)
                local rz = math.max(math.abs(rot.Z), half.X, half.Z)
                list[#list + 1] = { MinX = cf.Position.X - rx, MaxX = cf.Position.X + rx,
                    MinZ = cf.Position.Z - rz, MaxZ = cf.Position.Z + rz }
            end
        end
        local function bad(name)
            if name == "ScrambleLocalVisuals" or name == "DrScrambleEvent" then return false end
            name = string.lower(name)
            return string.find(name, "portal", 1, true) or string.find(name, "teleport", 1, true)
                or string.find(name, "mech", 1, true) or string.find(name, "arena", 1, true)
                or string.find(name, "scramble", 1, true)
        end
        for _, child in ipairs(workspace:GetChildren()) do
            if (child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder")) and bad(child.Name) then
                if child:IsA("Folder") then
                    for _, inner in ipairs(child:GetChildren()) do add(inner) end
                else add(child) end
            end
        end
        local build = workspace:FindFirstChild("World")
        build = build and build:FindFirstChild("Build")
        if build then
            for _, child in ipairs(build:GetChildren()) do
                if bad(child.Name) then
                    for _, inner in ipairs(child:GetChildren()) do add(inner) end
                end
            end
        end
        dangerCache = list
        return list
    end

    local function avoid(from, to)
        for _, d in ipairs(dangers()) do
            local x0, x1, z0, z1 = d.MinX - 12, d.MaxX + 12, d.MinZ - 12, d.MaxZ + 12
            local inside = from.X >= x0 and from.X <= x1 and from.Z >= z0 and from.Z <= z1
            if not inside then
                local t0, t1, hit = 0, 1, true
                for _, axis in ipairs({ { from.X, to.X - from.X, x0, x1 }, { from.Z, to.Z - from.Z, z0, z1 } }) do
                    local pos, delta, lo, hi = axis[1], axis[2], axis[3], axis[4]
                    if math.abs(delta) < 1e-6 then
                        if pos < lo or pos > hi then hit = false end
                    else
                        local ta, tb = (lo - pos) / delta, (hi - pos) / delta
                        if ta > tb then ta, tb = tb, ta end
                        t0, t1 = math.max(t0, ta), math.min(t1, tb)
                        if t0 > t1 then hit = false end
                    end
                end
                if hit then
                    local zLow, zHigh = z0 - 2, z1 + 2
                    local z = math.abs(from.Z - zLow) <= math.abs(from.Z - zHigh) and zLow or zHigh
                    if z < -440 or z > -290 then z = z == zLow and zHigh or zLow end
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

    local function waitIfPaused()
        while S.Paused and not S.Cancel do RunService.Heartbeat:Wait() end
    end

    -- ---------- RUN TO EGG ----------
    local function runToEgg(uid, egg)
        local lineX = lineInfo()
        local home = homePoint()
        local ch = LocalPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            if ch:FindFirstChildWhichIsA("Tool") then pcall(function() hum:UnequipTools() end) end
        end
        local r = root()
        if not r then return false end
        local stage = "field"
        if r.Position.X < lineX - 2 and Vector3.new(r.Position.X - home.X, 0, r.Position.Z - home.Z).Magnitude > 20 then
            stage = "safe"
        end
        local started    = os.clock()
        local lastCheck  = os.clock()
        local lastPos    = r.Position
        local lastTake   = 0
        local stuckCount = 0

        while os.clock() - started < 120 and not S.Cancel do
            waitIfPaused()
            r = root()
            if not r then return false end

            local fe_dist = Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z)
            if stage == "field" and fe_dist.Magnitude <= 2.5 then break end

            local target = egg
            if stage == "safe" then
                if Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude <= 6 then
                    stage = "field"
                else
                    target = home
                end
            end

            local wp    = avoid(r.Position, target)
            local flat  = Vector3.new(wp.X - r.Position.X, 0, wp.Z - r.Position.Z)
            local unit  = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero
            local speed = math.max(walkSpeed() * StealCfg.SpeedCap, 8)
            local v     = unit * math.min(speed, flat.Magnitude / 0.05)

            pcall(function()
                r.AssemblyLinearVelocity  = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
                r.AssemblyAngularVelocity = Vector3.zero
                if hum then
                    if fe_dist.Magnitude > 3 then hum:Move(unit, false)
                    else hum:Move(Vector3.zero, false) end
                end
            end)

            -- Detecção de travamento (a cada ~1.2s)
            if os.clock() - lastCheck >= 1.2 then
                local moved = (r.Position - lastPos).Magnitude
                if moved < 3 and fe_dist.Magnitude > 8 then
                    stuckCount += 1
                    if stuckCount >= 2 then
                        if flat.Magnitude > 0.5 then
                            local step = math.min(6, flat.Magnitude)
                            local dir  = flat.Unit
                            local newPos = r.Position + dir * step + Vector3.new(0, 2, 0)
                            pcall(function()
                                r.CFrame = CFrame.lookAt(newPos, newPos + dir)
                                r.AssemblyLinearVelocity  = Vector3.zero
                                r.AssemblyAngularVelocity = Vector3.zero
                            end)
                        end
                        stuckCount = 0
                    else
                        pcall(function()
                            if hum then hum.Jump = true end
                            r.AssemblyLinearVelocity = Vector3.new(
                                v.X,
                                math.max(r.AssemblyLinearVelocity.Y, 60),
                                v.Z
                            )
                        end)
                    end
                else
                    stuckCount = 0
                end
                lastPos, lastCheck = r.Position, os.clock()
            end

            if stage == "field" and fe_dist.Magnitude <= 9 and os.clock() - lastTake > 0.1 then
                lastTake = os.clock()
                takeEgg(uid)
            end

            RunService.Heartbeat:Wait()
        end

        r = root()
        if r then
            pcall(function()
                r.AssemblyLinearVelocity  = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
                if hum then hum:Move(Vector3.zero, false) end
            end)
        end
        return S.Carrying or (r ~= nil and Vector3.new(egg.X - r.Position.X, 0, egg.Z - r.Position.Z).Magnitude <= 6)
    end

    local function eggNow(uid, cache)
        local node = workspace:FindFirstChild(uid)
        local slots = workspace:FindFirstChild("AreaEggSlotsClient")
        node = node or (slots and slots:FindFirstChild(uid))
        if node then
            local ok, pos = pcall(function() return node:GetPivot().Position end)
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

    local function grab(uid, timeout)
        local cache = { At = 0 }
        local waited, since = 0, 1
        while not S.Carrying and waited < timeout and not S.Cancel do
            waitIfPaused()
            local r = root()
            local egg = eggNow(uid, cache)
            local dt = math.max(RunService.Heartbeat:Wait(), 1 / 240)
            waited += dt
            since += dt
            if r and egg then
                local delta = egg - r.Position
                local dist = delta.Magnitude
                local hum = r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
                if dist > 4 then
                    local pace = math.max(walkSpeed() * StealCfg.SpeedCap, 16)
                    local v = delta / math.max(0.08, dt)
                    if v.Magnitude > pace then v = v.Unit * pace end
                    pcall(function()
                        r.AssemblyLinearVelocity = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
                        r.AssemblyAngularVelocity = Vector3.zero
                    end)
                    if hum then
                        local flat = Vector3.new(delta.X, 0, delta.Z)
                        if flat.Magnitude > 0.5 then pcall(function() hum:Move(flat.Unit, false) end)
                        else pcall(function() hum:Move(Vector3.zero, false) end) end
                    end
                else
                    pcall(function()
                        r.AssemblyLinearVelocity = Vector3.new(0, r.AssemblyLinearVelocity.Y, 0)
                        r.AssemblyAngularVelocity = Vector3.zero
                    end)
                    if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
                end
                if since >= StealCfg.GrabInterval then
                    since = 0
                    local pr = promptNear(egg - Vector3.new(0, 3, 0), 12)
                    if pr and typeof(fireproximityprompt) == "function" then
                        pcall(function() pr.HoldDuration = 0 end)
                        pcall(fireproximityprompt, pr)
                    end
                    task.spawn(takeEgg, uid)
                end
            elseif since >= StealCfg.GrabInterval then
                since = 0
                task.spawn(takeEgg, uid)
            end
        end
        local r = root()
        if r then
            pcall(function()
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
            end)
            local hum = r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
        end
        return S.Carrying and S.Uid == uid
    end

    local function regrab(uid)
        if S.Carrying then return true end
        local r = root()
        local egg = eggPosition(uid)
        if r and egg and Vector3.new(r.Position.X - egg.X, 0, r.Position.Z - egg.Z).Magnitude > StealCfg.RegrabFar then
            place(egg + Vector3.new(0, 3, 0))
        end
        return grab(uid, 3)
    end

    local function groundY(pos, fb)
        local y = fb
        pcall(function()
            local p = RaycastParams.new()
            p.FilterType = Enum.RaycastFilterType.Exclude
            p.FilterDescendantsInstances = { LocalPlayer.Character }
            p.IgnoreWater = true
            local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), p)
            if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - fb) < 40 then
                y = hit.Position.Y + 3.5
            end
        end)
        return y
    end

    local function carrySpeed(dist)
        local ws = walkSpeed()
        local base = ws * math.min(StealCfg.CarryRatio, StealCfg.SpeedCap) * S.Mult
        local fast = base * 1.5
        local excess = 5.5 * base
        local limit = fast
        if dist and dist > excess then
            limit = math.min(fast, base * dist / (dist - excess))
        end
        return math.min(math.max(math.min(base * StealCfg.EasyRatio, limit), base), math.max(ws * StealCfg.SpeedCap, base))
    end

    -- ---------- RUN HOME ----------
    local function runHome(lineX, laneZ)
        local started = os.clock()
        local home = homePoint()
        local checkpoint = lineX - 7
        local height = StealCfg.Height
        local share = math.clamp(StealCfg.ClimbShare, 0.1, 0.9)
        local descent = height * math.sqrt(1 - share * share) / share
        local ch = LocalPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        local r = root()
        if r and ch and height > 0.5 and home.Y + height - 2 > r.Position.Y then
            pcall(function()
                ch:PivotTo(CFrame.new(Vector3.new(r.Position.X, home.Y + height, r.Position.Z)) * r.CFrame.Rotation)
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        local start = root()
        local speed = carrySpeed(start and (Vector3.new(start.Position.X - home.X, 0, start.Position.Z - home.Z).Magnitude + math.max(0, height) * 2) or nil)
        local last = os.clock()
        local timeout = 0
        while S.Carrying and S.Delivered < started and not S.Cancel and timeout < 25 do
            waitIfPaused()
            r = root()
            if not r then return false end
            local now = os.clock()
            local dt = math.max(now - last, 1 / 240)
            last = now
            timeout += dt
            local toHome = r.Position.X <= checkpoint + 2
            local target = toHome and home or Vector3.new(checkpoint, home.Y, laneZ)
            if toHome and Vector3.new(home.X - r.Position.X, 0, home.Z - r.Position.Z).Magnitude < 2 then break end
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
            pcall(function() r.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z) end)
            RunService.Heartbeat:Wait()
        end
        if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
        local settle = 0
        while settle < 2 and S.Delivered < started and S.Carrying and not S.Cancel do
            settle += RunService.Heartbeat:Wait()
        end
        if S.Carrying and S.Delivered < started and not S.Cancel then
            task.wait(0.2)
            dropEgg()
            local waited = 0
            while S.Delivered < started and waited < 1 do
                waited += RunService.Heartbeat:Wait()
            end
        end
        return S.Delivered >= started
    end

    -- ---------- INSTANT TP ----------
    local function instantTP(uid)
        if S.Cancel then return false end
        local started = os.clock()
        local lineX, lineY = lineInfo()
        local r = root()
        if not r then return false end
        local laneZ = math.clamp(r.Position.Z, -425, -300)
        local landing = Vector3.new(lineX + StealCfg.LandOffset, lineY + 3.35, laneZ)
        local hopStep = math.max(walkSpeed() * StealCfg.HopRatio, StealCfg.HopMin)
        local hopY = r.Position.Y + StealCfg.HopLift
        local x = r.Position.X
        local retries = 0
        local releaseCamera = frozenCamera()
        pcall(postClone)
        fpsOn()
        while x - hopStep > landing.X and not S.Cancel do
            waitIfPaused()
            if not S.Carrying then
                if not regrab(uid) then break end
                local cur = root()
                if cur then x = math.min(x, cur.Position.X) end
                continue
            end
            local nextX = x - hopStep
            local pulledBefore = S.PulledAt
            local held = 0
            while held < StealCfg.HopGap do
                place(Vector3.new(nextX, hopY, laneZ))
                held += RunService.Heartbeat:Wait()
            end
            local check = root()
            local pulled = S.PulledAt > pulledBefore
                or (check ~= nil and (check.Position.X - nextX > 10 or check.AssemblyLinearVelocity.Magnitude > 150))
            if pulled and S.Carrying and not S.Cancel then
                retries += 1
                StealCfg.HopGap = math.min(StealCfg.HopGapMax, StealCfg.HopGap + 0.02)
                if retries > StealCfg.HopRetries then break end
                local settle = 0
                while settle < 0.12 and not S.Cancel do
                    place(Vector3.new(x, hopY, laneZ))
                    settle += RunService.Heartbeat:Wait()
                end
            else
                x = nextX
                StealCfg.HopGap = math.max(StealCfg.HopGapMin, StealCfg.HopGap - 0.01)
            end
        end
        landing = Vector3.new(landing.X, groundY(landing, landing.Y), landing.Z)
        local function land()
            local cur = root()
            if cur and cur.Position.X <= landing.X + 1 and cur.Position.Y > landing.Y - 25 then
                pcall(function() cur.AssemblyLinearVelocity = Vector3.zero end)
                return
            end
            place(landing)
        end
        land()
        for _ = 1, 3 do
            local settle = 0
            while settle < StealCfg.LandSettle and not S.Cancel do
                settle += RunService.Heartbeat:Wait()
            end
            local landed = root()
            if S.Carrying and landed and (landed.Position.X - landing.X > 12 or landed.Position.Y < landing.Y - 25) then
                land()
            else break end
        end
        dropClone()
        if S.Carrying and not S.Cancel then
            local delay = 0
            while delay < StealCfg.DropDelay do
                delay += RunService.Heartbeat:Wait()
            end
            dropEgg()
            local waited = 0
            while S.Carrying and waited < 1 and not S.Cancel do
                waited += RunService.Heartbeat:Wait()
            end
            local cur = root()
            if cur then
                pcall(function()
                    cur.AssemblyLinearVelocity = Vector3.zero
                    cur.AssemblyAngularVelocity = Vector3.zero
                end)
            end
            releaseCamera()
            dropClone()
            if not grab(uid, 3) and not regrab(uid) then
                fpsOff()
                return false
            end
            dropClone()
        end
        releaseCamera()
        local ok = false
        if S.Carrying and not S.Cancel then
            ok = runHome(lineX, laneZ)
        end
        fpsOff()
        return ok or S.Delivered >= started
    end

    -- ---------- PIPELINE ----------
    local function stealAndDeliver(uid)
        if S.Busy then return end
        S.Busy = true
        S.Cancel = false
        S.Paused = false
        shieldStart()
        task.spawn(function()
            local ok, err = pcall(function()
                status("Procurando ovo...")
                local egg = eggPosition(uid)
                if not egg then status("Ovo sumiu") return end
                if S.Carrying and S.Uid ~= uid then
                    dropEgg()
                    local waited = 0
                    while S.Carrying and waited < 1 and not S.Cancel do
                        waited += RunService.Heartbeat:Wait()
                    end
                end
                if S.Cancel then return end
                fpsOn()
                status("Indo até o ovo...")
                if not runToEgg(uid, egg) then
                    fpsOff() status("Não alcancei") return
                end
                if S.Cancel then return end
                status("Pegando ovo...")
                if not grab(uid, 4) then
                    fpsOff() status("Ovo não soltou") return
                end
                if S.Cancel then return end
                local delivered = instantTP(uid)
                status(delivered and "Entregue!" or "Falha na entrega")
            end)
            fpsOff()
            dropClone()
            if not ok and err then status("Erro: " .. tostring(err)) end
            shieldStop()
            S.Busy = false
        end)
    end

    -- ---------- AUTO LOOP ----------
    local Auto = { Active = false, Thread = nil }

    local function pickBest()
        local best, bestVal, bestInfo = nil, 0, nil
        for _, r in ipairs(snapshot()) do
            local rar = getRarityName(r)
            if (not rarityFilterEnabled) or targetRarity == "Todos" or rar:lower() == targetRarity:lower() then
                local v = getEggValue(r)
                if v > bestVal then best, bestVal, bestInfo = r.Uid, v, r end
            end
        end
        return best, bestInfo
    end

    local function autoEnable()
        if Auto.Active then return end
        Auto.Active = true
        Auto.Thread = task.spawn(function()
            while Auto.Active do
                local uid, info = pickBest()
                if not uid then
                    status("Nenhum ovo disponível")
                    task.wait(1.5)
                else
                    status("AUTO: " .. tostring(info and (info.AssetCategory or info.Name) or "ovo"))
                    stealAndDeliver(uid)
                    local t0 = os.clock()
                    while S.Busy and Auto.Active and os.clock() - t0 < 90 do
                        task.wait(0.2)
                    end
                    task.wait(0.4)
                end
            end
        end)
    end

    local function autoDisable()
        if not Auto.Active then return end
        Auto.Active = false
        S.Cancel = true
        if Auto.Thread then pcall(task.cancel, Auto.Thread) Auto.Thread = nil end
        task.spawn(function()
            local t0 = os.clock()
            while S.Busy and os.clock() - t0 < 4 do task.wait(0.1) end
            S.Cancel = false
        end)
    end

    -- ---------- UI ----------
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 2)
    pad.Parent = containerSteal

    local row1 = Instance.new("Frame")
    row1.Size = UDim2.new(1, -4, 0, 22)
    row1.Position = UDim2.new(0, 2, 0, 0)
    row1.BackgroundTransparency = 1
    row1.Parent = containerSteal

    local btnFiltro = Instance.new("TextButton")
    btnFiltro.Size = UDim2.new(0.5, -2, 1, 0)
    btnFiltro.Position = UDim2.new(0, 0, 0, 0)
    btnFiltro.BackgroundColor3 = BG_BTN
    btnFiltro.BorderSizePixel = 0
    btnFiltro.Font = Enum.Font.GothamBold
    btnFiltro.TextSize = 9
    btnFiltro.TextColor3 = TXT
    btnFiltro.Text = "Filtro: Todos"
    btnFiltro.ZIndex = 4
    btnFiltro.Parent = row1
    Instance.new("UICorner", btnFiltro).CornerRadius = UDim.new(0, 5)

    local btnAuto = Instance.new("TextButton")
    btnAuto.Size = UDim2.new(0.5, -2, 1, 0)
    btnAuto.Position = UDim2.new(0.5, 2, 0, 0)
    btnAuto.BackgroundColor3 = BG_BTN
    btnAuto.BorderSizePixel = 0
    btnAuto.Font = Enum.Font.GothamBold
    btnAuto.TextSize = 9
    btnAuto.TextColor3 = TXT
    btnAuto.Text = "AUTO: OFF"
    btnAuto.ZIndex = 4
    btnAuto.Parent = row1
    Instance.new("UICorner", btnAuto).CornerRadius = UDim.new(0, 5)

    local lblStatus = Instance.new("TextLabel")
    lblStatus.Size = UDim2.new(1, -4, 0, 12)
    lblStatus.Position = UDim2.new(0, 2, 0, 24)
    lblStatus.BackgroundTransparency = 1
    lblStatus.Font = Enum.Font.Gotham
    lblStatus.TextSize = 9
    lblStatus.TextColor3 = TXT_DIM
    lblStatus.TextXAlignment = Enum.TextXAlignment.Left
    lblStatus.TextTruncate = Enum.TextTruncate.AtEnd
    lblStatus.Text = "Pronto."
    lblStatus.ZIndex = 4
    lblStatus.Parent = containerSteal

    statusSteal = function(msg)
        lblStatus.Text = tostring(msg)
    end

    local scrollEggs = Instance.new("ScrollingFrame")
    scrollEggs.Size = UDim2.new(1, -4, 0, 88)
    scrollEggs.Position = UDim2.new(0, 2, 0, 38)
    scrollEggs.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    scrollEggs.BorderSizePixel = 0
    scrollEggs.ScrollBarThickness = 3
    scrollEggs.ScrollBarImageColor3 = ROXO
    scrollEggs.ScrollBarImageTransparency = 0.3
    scrollEggs.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollEggs.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollEggs.ScrollingDirection = Enum.ScrollingDirection.Y
    scrollEggs.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
    scrollEggs.ZIndex = 3
    scrollEggs.Parent = containerSteal
    Instance.new("UICorner", scrollEggs).CornerRadius = UDim.new(0, 5)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = scrollEggs

    local listPad = Instance.new("UIPadding")
    listPad.PaddingTop = UDim.new(0, 2)
    listPad.PaddingBottom = UDim.new(0, 2)
    listPad.Parent = scrollEggs

    local btnStop = Instance.new("TextButton")
    btnStop.Size = UDim2.new(1, -4, 0, 20)
    btnStop.Position = UDim2.new(0, 2, 1, -22)
    btnStop.BackgroundColor3 = Color3.fromRGB(60, 15, 25)
    btnStop.BorderSizePixel = 0
    btnStop.Font = Enum.Font.GothamBold
    btnStop.TextSize = 10
    btnStop.TextColor3 = Color3.fromRGB(255, 190, 200)
    btnStop.Text = "PARAR / CANCELAR"
    btnStop.ZIndex = 4
    btnStop.Parent = containerSteal
    Instance.new("UICorner", btnStop).CornerRadius = UDim.new(0, 5)

    btnStop.MouseButton1Click:Connect(function()
        if Auto.Active then
            autoDisable()
            btnAuto.Text = "AUTO: OFF"
            btnAuto.BackgroundColor3 = BG_BTN
            btnAuto.TextColor3 = TXT
            Toast("AUTO desligado", AMARELO)
        end
        S.Cancel = true
        S.Paused = false
        status("Cancelado")
    end)

    local listCache = {}
    local function refreshList()
        for _, it in ipairs(listCache) do it:Destroy() end
        listCache = {}
        local rows = {}
        for _, r in ipairs(snapshot()) do
            rows[#rows + 1] = { r = r, v = getEggValue(r) }
        end
        table.sort(rows, function(a, b) return a.v > b.v end)
        for i = 1, math.min(8, #rows) do
            local item = rows[i]
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -2, 0, 40)
            btn.BackgroundColor3 = BG_BTN
            btn.BorderSizePixel = 0
            btn.Text = ""
            btn.LayoutOrder = i
            btn.ZIndex = 4
            btn.Parent = scrollEggs
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

            local petIcon = Instance.new("ImageLabel")
            petIcon.Name = "PetIcon"
            petIcon.Size = UDim2.new(0, 32, 0, 32)
            petIcon.Position = UDim2.new(0, 5, 0.5, -16)
            petIcon.BackgroundTransparency = 1
            petIcon.ScaleType = Enum.ScaleType.Fit
            petIcon.ZIndex = 5
            petIcon.Image = getPetIconSteal(item.r) or ""
            petIcon.Visible = petIcon.Image ~= ""
            petIcon.Parent = btn

            local nm = Instance.new("TextLabel")
            nm.Size = UDim2.new(1, -125, 1, 0)
            nm.Position = UDim2.new(0, 43, 0, 0)
            nm.BackgroundTransparency = 1
            nm.Font = Enum.Font.GothamBold
            nm.TextSize = 9
            nm.TextColor3 = TXT
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextTruncate = Enum.TextTruncate.AtEnd
            nm.Text = tostring(item.r.AssetCategory or item.r.Category or item.r.Name or "Ovo")
            nm.ZIndex = 5
            nm.Parent = btn

            local val = Instance.new("TextLabel")
            val.Size = UDim2.new(0, 75, 1, 0)
            val.Position = UDim2.new(1, -80, 0, 0)
            val.BackgroundTransparency = 1
            val.Font = Enum.Font.GothamBold
            val.TextSize = 9
            val.TextColor3 = AMARELO
            val.TextXAlignment = Enum.TextXAlignment.Right
            val.Text = "$" .. money(item.v)
            val.ZIndex = 5
            val.Parent = btn

            local uid = item.r.Uid
            btn.MouseButton1Click:Connect(function()
                if not uid then return end
                if Auto.Active then
                    autoDisable()
                    btnAuto.Text = "AUTO: OFF"
                    btnAuto.BackgroundColor3 = BG_BTN
                    btnAuto.TextColor3 = TXT
                end
                status("Roubando: " .. nm.Text)
                stealAndDeliver(uid)
            end)

            table.insert(listCache, btn)
        end
    end

    btnFiltro.MouseButton1Click:Connect(function()
        rarityIdx += 1
        if rarityIdx > #rarityOptions then rarityIdx = 1 end
        targetRarity = rarityOptions[rarityIdx]
        rarityFilterEnabled = (targetRarity ~= "Todos")
        btnFiltro.Text = "Filtro: " .. targetRarity
    end)

    btnAuto.MouseButton1Click:Connect(function()
        if Auto.Active then
            autoDisable()
            btnAuto.Text = "AUTO: OFF"
            btnAuto.BackgroundColor3 = BG_BTN
            btnAuto.TextColor3 = TXT
            Toast("AUTO-STEAL OFF", AMARELO)
        else
            autoEnable()
            btnAuto.Text = "AUTO: ON"
            btnAuto.BackgroundColor3 = Color3.fromRGB(15, 40, 20)
            btnAuto.TextColor3 = VERDE
            Toast("AUTO-STEAL ON", VERDE)
        end
    end)

    task.spawn(function()
        while gui.Parent do
            task.wait(2)
            pcall(refreshList)
        end
    end)

    pcall(refreshList)
end

iniciarSistemaSteal()

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
