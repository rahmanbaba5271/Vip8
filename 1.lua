--------Join us for more https://t.me/AttcTrDevelopers--------------------------------@AttcConfigTechnician -----------------------------





-- ============================================================

-- ============================================================
_G.AKMOD_WARNING = "AKMOD_ANTI_REVERSE_ENGINEERING_FUCK_YOU"

-- ============================================================
-- RPC DEFINITIONS (dummy, keep original structure)
-- ============================================================
Reliable = true
ServerRPC = {}
ClientRPC = {}
MulticastRPC = {}

ServerRPC.ServerRPC_NearDeathGiveupRescue = {}
ServerRPC.ServerRPC_NearDeathGiveupRescue.Params = {}
Reliable = true

ServerRPC.ServerRPC_CarryDeadBox = {}
ServerRPC.ServerRPC_CarryDeadBox.Params = { UEnums.EPropertyClass.Object }
Reliable = true

ServerRPC.RPC_Server_GmPlayAction = {}
ServerRPC.RPC_Server_GmPlayAction.Params = { UEnums.EPropertyClass.Int }
Reliable = true

MulticastRPC.MulticastRPC_GmPlayAction = {}
MulticastRPC.MulticastRPC_GmPlayAction.Params = { UEnums.EPropertyClass.Int }
Reliable = true

ClientRPC.RPC_Client_SetShouldCheckPassWall = {}
ClientRPC.RPC_Client_SetShouldCheckPassWall.Params = { UEnums.EPropertyClass.Bool }
Reliable = true

-- ============================================================
-- IMPORTS
-- ============================================================
local class = require("class")
local CharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local combine_class = require("combine_class")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local SecurityUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local TimeTicker = require("common.time_ticker")
local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")

-- ============================================================
-- HELPER: SAFE REQUIRE
-- ============================================================
local function safe_require(module)
    if package.loaded[module] then
        return package.loaded[module]
    end
    local ok, result = pcall(require, module)
    return ok and result or nil
end

-- ============================================================
-- SECURITY BYPASS (Disable telemetry, crash reporting, anti-cheat)
-- ============================================================
local function nop() end

local function bypass_telemetry()
    -- Disable CrashSight
    if _G.CrashSight then
        _G.CrashSight.ReportException = nop
        _G.CrashSight.SetCustomData = nop
        _G.CrashSight.SetAppVersion = nop
    end
    if _G.FPlatformMisc then
        _G.FPlatformMisc.RequestExit = nop
    end

    -- Disable various SDKs
    local sdks = {
        "TDM", "TencentDataMaster", "TDataMaster", "GCloud", "GCloudVoice",
        "APM", "INTL", "Safeguard", "Beacon"
    }
    for _, name in ipairs(sdks) do
        local sdk = _G[name]
        if type(sdk) == "table" then
            sdk.ReportEvent = nop
            sdk.ReportBinary = nop
            sdk.Send = nop
            sdk.SetServerInfo = nop
        end
    end

    -- Scan global tables for suspicious names
    for k, v in pairs(_G) do
        if type(v) == "table" then
            local lower = tostring(k):lower()
            if lower:find("tdm") or lower:find("gcloud") or lower:find("report") or
               lower:find("crash") or lower:find("apm") or lower:find("intl") or
               lower:find("beacon") or lower:find("safeguard") then
                pcall(function()
                    v.ReportEvent = nop
                    v.ReportBinary = nop
                    v.Send = nop
                    v.SetServerInfo = nop
                end)
            end
        end
    end

    -- Disable GameplayCallbacks
    if _G.GC then
        local gc = _G.GC
        gc.SendTssSdkAntiDataToLobby = nop
        gc.SendDSErrorLogToLobby = nop
        gc.SendDSHawkEyePatrolLogToLobby = nop
        gc.SendSecTLog = nop
        gc.SendDataMiningTLog = nop
        gc.SendActivityTLog = nop
        gc.OnPlayerRPCValidateFailed = nop
        gc.OnPlayerActorChannelError = nop
        gc.OnPlayerSpectateException = nop
    end
end

-- HiggsBoson / AvatarCheck bypass
local higgs_bypass_attempts = 0
local MAX_HIGGS_BYPASS_ATTEMPTS = 60

local function bypass_higgs_boson(player)
    if not player or not slua.isValid(player) then return end
    if higgs_bypass_attempts >= MAX_HIGGS_BYPASS_ATTEMPTS then return end

    pcall(function()
        local Higgs = safe_require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            Higgs.ControlMHActive = nop
            Higgs.Tick = nop
            Higgs.OnTick = nop
            Higgs.ReceiveTick = nop
            Higgs.MHActiveLogic = nop
            Higgs.TriggerAvatarCheck = nop
            Higgs.StartAvatarCheck = nop
            Higgs.ReportItemID = nop
            Higgs.OnReportItemID = nop
            Higgs.ReceiveAnyDamage = nop
            Higgs.OnWeaponHitRecord = nop
            Higgs.ShowSecurityAlert = nop
            Higgs.ServerReportAvatar = nop
            Higgs.ClientReportNetAvatar = nop
            Higgs.GetNetAvatarItemIDs = function() return {} end
            Higgs.GetCurWeaponSkinID = function() return 0 end
        end

        if _G.AvatarCheckCallback then
            _G.AvatarCheckCallback.StartAvatarCheck = nop
            _G.AvatarCheckCallback.OnReportItemID = nop
        end

        -- Bypass Subsystem components
        local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubsystemMgr then
            local hawkEye = SubsystemMgr:Get("ClientHawkEyePatrolSubsystem")
            if hawkEye then
                hawkEye.OnTick = nop
                hawkEye.ReportPatrolData = nop
                hawkEye.SendPatrolData = nop
            end
            local reportSub = SubsystemMgr:Get("ClientReportPlayerSubsystem")
            if reportSub then
                reportSub.ReportPlayer = nop
                reportSub.OnTick = nop
                reportSub.OnInit = nop
                reportSub._OnPlayerKilledOtherPlayer = nop
                reportSub._RecordFatalDamager = nop
                reportSub._OnBattleResult = nop
            end
            local glueHia = SubsystemMgr:Get("ClientGlueHiaSystem")
            if glueHia then
                glueHia.ReportHiaData = nop
            end
        end
    end)

    higgs_bypass_attempts = higgs_bypass_attempts + 1
end

-- Run initial bypass
bypass_telemetry()

-- ============================================================
-- MOD EXPIRATION (2026-05-20)
-- ============================================================
local EXPIRY_TABLE = { year = 2027, month = 5, day = 20, hour = 0, min = 0, sec = 0 }
local EXPIRY_TIMESTAMP = os.time(EXPIRY_TABLE)

local function is_mod_expired()
    return os.time(os.date("!*t")) > EXPIRY_TIMESTAMP
end

-- ============================================================
-- MOD CONFIGURATION (toggled via menu)
-- ============================================================
_G.Mod_WallHighlight = false
_G.Mod_NoGrass = false
_G.Mod_NoRecoil = false
_G.Mod_iPadView = false
_G.ModMenuShown = false

-- ============================================================
-- CONSOLE COMMAND HELPER
-- ============================================================
local function execute_console_cmd(cmd, value)
    pcall(function()
        local pc = GameplayData.GetPlayerController()
        if slua.isValid(pc) then
            import("KismetSystemLibrary").ExecuteConsoleCommand(pc, cmd .. " " .. tostring(value))
        end
    end)
end

-- ============================================================
-- NO GRASS
-- ============================================================
local function apply_no_grass()
    if not _G.Mod_NoGrass then return end
    execute_console_cmd("grass.DensityScale", "0")
    execute_console_cmd("grass.Enable", "0")
    execute_console_cmd("r.FoliageQuality", "0")
    execute_console_cmd("foliage.DensityScale", "0")
end

-- ============================================================
-- MOD MENU (step-by-step)
-- ============================================================
function _G.TryShowModMenu()
    if _G.ModMenuShown then return end
    _G.ModMenuShown = true

    pcall(function()
        local msgbox = require("client.slua.logic.common.logic_common_msg_box")
        if not msgbox or not msgbox.Show then return end

        -- final info display
        local function show_final_message()
            msgbox.Show(1, "Official Owner : @ArabHacker67",
                [[Congratulation Bypass Activated Successfully!
Official Channel : @ArabHacker67]], nil, nil)
        end

        -- iPad view enable/disable
        local function enable_ipad()
            _G.Mod_iPadView = true
            show_final_message()
        end
        local function disable_ipad()
            _G.Mod_iPadView = false
            show_final_message()
        end
        local function ask_ipad()
            msgbox.Show(2, "STEP 4: IPAD VIEW",
                "Enable iPad View?\n\nAGREE: Enable\nCANCEL: Disable",
                enable_ipad, disable_ipad)
        end

        -- No Recoil enable/disable
        local function enable_norecoil()
            _G.Mod_NoRecoil = true
            ask_ipad()
        end
        local function disable_norecoil()
            _G.Mod_NoRecoil = false
            ask_ipad()
        end
        local function ask_norecoil()
            msgbox.Show(2, "STEP 3: AIMBOT + NO RECOIL",
                "Enable No Recoil & Aimbot?\nZero recoil + auto aim!\n\nAGREE: Enable\nCANCEL: Disable",
                enable_norecoil, disable_norecoil)
        end

        -- No Grass enable/disable
        local function enable_nograss()
            _G.Mod_NoGrass = true
            apply_no_grass()
            ask_norecoil()
        end
        local function disable_nograss()
            _G.Mod_NoGrass = false
            ask_norecoil()
        end
        local function ask_nograss()
            msgbox.Show(2, "STEP 2: NO GRASS",
                "Enable Remove Grass?\n\nAGREE: Enable\nCANCEL: Disable",
                enable_nograss, disable_nograss)
        end

        -- Wall Highlight enable/disable
        local function enable_wall()
            _G.Mod_WallHighlight = true
            ask_nograss()
        end
        local function disable_wall()
            _G.Mod_WallHighlight = false
            ask_nograss()
        end

        -- Step 1: Smart ESP + Box
        msgbox.Show(2, "STEP 1: SMART ESP + Box [ ]",
            "Enable Smart Esp + Box [ ]?\n\nAGREE: Enable\nCANCEL: Disable",
            enable_wall, disable_wall)
    end)
end

-- ============================================================
-- WALL HIGHLIGHT (using Replay frame UI)
-- ============================================================
local STExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")
local STExtraPlayerCharacter = import("STExtraPlayerCharacter")

local function init_wall_highlight(self)
    if not Client then return end
    if self._WallHighlightTimer then return end

    self._WallHighlightTimer = self:AddGameTimer(0.1, true, function()
        if not _G.Mod_WallHighlight then return end
        if not slua.isValid(self.Object) then return end

        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if not pc then return end
        if not Game:IsClassOf(pc, STExtraPlayerController) then return end

        local myPos = pc:GetCurPawnLocation()
        local myPawn = pc:GetCurPawn()
        local myTeamID = 0
        if Game:IsClassOf(myPawn, STExtraPlayerCharacter) and myPawn.TeamID then
            myTeamID = myPawn.TeamID
        end

        if not SecurityUtils.IsVector(myPos) then return end

        local allPawns = Game:GetAllPlayerPawns()
        if not allPawns then return end

        for _, pawn in pairs(allPawns) do
            if slua.isValid(pawn) and pawn.Replay_CreateEnemyFrameUI and pawn.Replay_SetVisiableOfFrameUI and pawn.Replay_IsEnemyFrameUIExisted then
                local isEnemy = (pawn.TeamID ~= myTeamID and pawn.TeamID ~= 0)
                local isAlive = pawn.HealthStatus and SecurityUtils.IsHealthStatusAlive(pawn.HealthStatus)
                if isEnemy and isAlive then
                    if not pawn:Replay_IsEnemyFrameUIExisted() then
                        pawn:Replay_CreateEnemyFrameUI(true, true)
                    end
                    pawn:Replay_SetVisiableOfFrameUI(true)
                else
                    pawn:Replay_SetVisiableOfFrameUI(false)
                end
            end
        end
    end)
end

local function cleanup_wall_highlight(self)
    if self._WallHighlightTimer then
        self:RemoveGameTimer(self._WallHighlightTimer)
        self._WallHighlightTimer = nil
    end
end

-- ============================================================
-- BRPlayerCharacterBase CLASS
-- ============================================================
local BRPlayerCharacterBase = class(CharacterBase, nil, {
    -- Constructor
    ctor = function(self)
        self.ActiveForceMark = nil
        self.LastMarkUpdate = 0
        self._WallHighlightTimer = nil
        self._CurrentWeaponPtr = nil
        self.LastTickUpdate = 0
    end,

    -- PostConstruct
    _PostConstruct = function(self)
        CharacterBase._PostConstruct(self)
        self:InitAddSpecialMoveInfo()
        self.bCanNearDeathGiveup = true
        print("BRPlayerCharacterBase:_PostConstruct")
    end,

    -- ReceiveBeginPlay
    ReceiveBeginPlay = function(self)
        CharacterBase.ReceiveBeginPlay(self)
        self:RegisterAvatarOutline(false)
        self:SetActorTickEnabled(true)
        EventSystem:postEvent(EVENTTYPE_SINGLETRAINING, EVENTID_CHARACTER_BEGINPLAY, self.Object)

        if Client then
            self:AddGameTimer(1.8, false, _G.TryShowModMenu)

            -- Higgs bypass after 1 second
            self:AddGameTimer(1.0, true, function()
                if not slua.isValid(self.Object) then return end
                local localPlayer = GameplayData.GetPlayerCharacter()
                if slua.isValid(localPlayer) and self.Object == localPlayer then
                    bypass_higgs_boson(self.Object)
                end
            end)
        end

        init_wall_highlight(self)
    end,

    -- ReceiveEndPlay
    ReceiveEndPlay = function(self, EndPlayReason)
        cleanup_wall_highlight(self)

        if self.ActiveForceMark and InGameMarkTools then
            InGameMarkTools.HideMapMark(self.ActiveForceMark)
            self.ActiveForceMark = nil
        end

        CharacterBase.ReceiveEndPlay(self, EndPlayReason)

        if Client and GameplayData.RemoveCharacter then
            GameplayData.RemoveCharacter(self.Object)
        end
    end,

    -- ReceiveTick
    ReceiveTick = function(self, DeltaTime)
        if CharacterBase.ReceiveTick then
            CharacterBase.ReceiveTick(self, DeltaTime)
        end

        local now = os.clock()
        if not self.LastTickUpdate or now - self.LastTickUpdate > 0.1 then
            self.LastTickUpdate = now
            self:SetFOV110()
            self:ApplyNoRecoil()
            self:RegisterAvatarOutline(false)
        end
        self:UpdateMapMark()
    end,

    -- iPad View (FOV 110)
    SetFOV110 = function(self)
        if is_mod_expired() then return end
        if not _G.Mod_iPadView then return end
        local camera = self.Object.ThirdPersonCameraComponent
        if slua.isValid(camera) then
            camera:SetFieldOfView(110)
        end
    end,

    -- No Recoil + Aimbot
    ApplyNoRecoil = function(self)
        if is_mod_expired() then return end
        if not _G.Mod_NoRecoil then return end

        local weaponMgr = self.Object.WeaponManagerComponent
        if not weaponMgr then return end
        local weapon = weaponMgr.CurrentWeaponReplicated
        if not weapon or not slua.isValid(weapon.ShootWeaponEntityComp) then return end

        -- Only apply once per weapon
        if self._CurrentWeaponPtr ~= weapon then
            self._CurrentWeaponPtr = weapon
            return
        end

        local comp = weapon.ShootWeaponEntityComp
        local randomFactor = math.random(1, 12) * 0.01

        comp.RecoilKick = 0.0
        comp.RecoilKickADS = 0.0
        comp.AnimationKick = 0.0
        comp.AccessoriesVRecoilFactor = 0.3
        comp.AccessoriesHRecoilFactor = 0.3
        comp.GameDeviationFactor = 0.4 + randomFactor

        if comp.RecoilInfo then
            comp.RecoilInfo.VerticalRecoilMin = 0
            comp.RecoilInfo.VerticalRecoilMax = 0
            comp.RecoilInfo.RecoilSpeedVertical = 0
            comp.RecoilInfo.RecoilSpeedHorizontal = 0
            comp.RecoilInfo.VerticalRecoveryMax = 0
        end

        comp.RecoilModifierStand = 0
        comp.RecoilModifierCrouch = 0
        comp.RecoilModifierProne = 0

        -- Auto-aim config
        if comp.AutoAimingConfig then
            for _, rangeType in ipairs({"OuterRange", "InnerRange"}) do
                local cfg = comp.AutoAimingConfig[rangeType]
                if cfg then
                    cfg.Speed = 3.5
                    cfg.RangeRate = 8
                    cfg.SpeedRate = 7
                    cfg.RangeRateSight = 8
                    cfg.SpeedRateSight = 7
                    cfg.CrouchRate = 4
                    cfg.ProneRate = 4
                    cfg.DyingRate = 0
                end
            end
        end
    end,

    -- Enemy Outline (green)
    RegisterAvatarOutline = function(self, enabled)
        if not Client or is_mod_expired() then return end
        local avatarComp = self:getAvatarComponent2()
        if not slua.isValid(avatarComp) then return end

        local ppManager = import("PostProcessManager"):GetInstance()
        if not slua.isValid(ppManager) or not ppManager.IsPPEnabled then return end

        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end

        ppManager:EnableAvatarOutline(avatarComp, false)

        if localPlayer.TeamID ~= self.TeamID then
            ppManager.OutlineThickness = 2
            ppManager.OutlineColor = FLinearColor(0, 1, 0, 1)
            pcall(function()
                if ppManager.SetOutlineColor then
                    ppManager:SetOutlineColor(0, 1, 0, 1)
                end
            end)
            ppManager:EnableAvatarOutline(avatarComp, true)
        end
    end,

    -- ESP Map Marker
    UpdateMapMark = function(self)
        if not Client or not slua.isValid(self.Object) then return end
        local localPlayer = GameplayData.GetPlayerCharacter()
        if not slua.isValid(localPlayer) then return end

        if localPlayer.TeamID ~= self.TeamID then
            if self.Object.IsAlive and self.Object:IsAlive() and (os.clock() - (self.LastMarkUpdate or 0) > 1.0) then
                self.LastMarkUpdate = os.clock()
                local pos = self:GetHeadLocation(false)
                if not pos then
                    pos = self:GetFuzzyPosition(FVector(0,0,0))
                end
                if pos and InGameMarkTools then
                    if self.ActiveForceMark then
                        InGameMarkTools.HideMapMark(self.ActiveForceMark)
                    end
                    self.ActiveForceMark = InGameMarkTools.ClientAddMapMark(1003, pos, 0, "", 4, nil)
                end
            end
        else
            if self.ActiveForceMark and InGameMarkTools then
                InGameMarkTools.HideMapMark(self.ActiveForceMark)
                self.ActiveForceMark = nil
            end
        end
    end
})

-- ============================================================
-- FEATURE REGISTRATION (combine_class)
-- ============================================================
local features = {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature",
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature",
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature",
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature",
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature",
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature",
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature",
    BuildSkateFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerCharacterBuildVehicleFeature",
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
}

return combine_class.DeclareFeature(BRPlayerCharacterBase, features, "BRPlayerCharacterBase")

--------Join us for more https://t.me/AttcTrDevelopers--------------------------------@AttcConfigTechnician -----------------------------
