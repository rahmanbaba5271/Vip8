local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")

local KismetSystemLibrary = import("KismetSystemLibrary")
local packageName = KismetSystemLibrary.GetGameBundleId()

if packageName ~= "com.tencent.ig" then
    return
end

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
    self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
    self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle)
  if not slua.isValid(uVehicle) then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(uVehicle)))
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
    self.nUpdatePlayerAttachToVehicleTimer = self:AddGameTimer(5, true, 
function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:UpdatePlayerAttachToVehicle(uVehicle)
      end
    end)
    self.nFixMeshContainerTimer = self:AddGameTimer(3, true, 
function()
      if slua.isValid(self.Object) and slua.isValid(uVehicle) then
        self:FixMeshContainerOffsetIfNeeded(uVehicle)
      end
    end)
  end
end

function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle)
  if not slua.isValid(uLastVehicle) then
    return
  end
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.CapsuleComponent) or not slua.isValid(self.Mesh) or not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  if not self.nUpdatePlayerAttachToVehicleCount then
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  local ESTEPoseState = import("ESTEPoseState")
  local bStand = self.PoseState == ESTEPoseState.Stand
  local uActorRelativeLocation = self.CapsuleComponent:GetRelativeTransform():GetLocation()
  local uMeshRelativeLocation = self.Mesh:GetRelativeTransform():GetLocation()
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  local nCapsuleRadius = self.CapsuleComponent:GetScaledCapsuleRadius()
  local nCapsuleHalfHeight = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local nExpectedCapsuleRadius = self.StandRadius
  local nExpectedCapsuleHalfHeight = self.StandHalfHeight
  local uMeshExpectedRL = FVector(0, 0, 0)
  local uActorExpectedRL = FVector(0, 0, self.StandHalfHeight)
  local nTolerance = 1.0
  local bCapsuleRLCorrect = uActorRelativeLocation:Equals(uActorExpectedRL, nTolerance)
  local bMeshRLCorrect = uMeshRelativeLocation:Equals(uMeshExpectedRL, nTolerance)
  local bMeshContainerRLCorrect = nTolerance > math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ)
  local bCapsuleRadiusCorrect = nTolerance > math.abs(nCapsuleRadius - nExpectedCapsuleRadius)
  local bCapsuleHalfHeightCorrect = nTolerance > math.abs(nCapsuleHalfHeight - nExpectedCapsuleHalfHeight)
  local bAllCorrect = bStand and bCapsuleRLCorrect and bMeshRLCorrect and bMeshContainerRLCorrect and bCapsuleRadiusCorrect and bCapsuleHalfHeightCorrect
  if not bAllCorrect then
    self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1
  else
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:UpdatePlayerAttachToVehicle PlayerKey:%s. bAllCorrect=%s Check Result:%d %d %d %d %d %d, Count:%d", tostring(self.PlayerKey), tostring(bAllCorrect), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, self.nUpdatePlayerAttachToVehicleCount))
  if self.nUpdatePlayerAttachToVehicleCount >= 3 and not bAllCorrect then
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local uPlayerController = GameplayData.GetPlayerController()
    if uPlayerController.ReportCrashKitFeature and uPlayerController.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
      local sReportInfo = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(uVehicle.VehicleShapeType), tostring(self.PlayerKey), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, uActorRelativeLocation:ToString(), tostring(nCapsuleRadius), tostring(nCapsuleHalfHeight), uMeshRelativeLocation:ToString(), tostring(uMeshContainerRelativeLocationZ))
      uPlayerController.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(sReportInfo)
    end
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded(uVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uVehicle) then
    return
  end
  if not slua.isValid(self.MeshContainer) then
    return
  end
  if not slua.isValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  local nTolerance = 1.0
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  if nTolerance <= math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ) then
    print(bWriteLog and string.format("BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded PlayerKey:%s. SetMeshContainerOffsetZ from:%s to:%s", tostring(uMeshContainerExpectedZ), tostring(uMeshContainerExpectedZ)))
    self:SetMeshContainerOffsetZ(uMeshContainerExpectedZ)
  end
end

function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil
  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  local EPawnState = import("EPawnState")
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
    self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local EGameModeType = import("EGameModeType")
    local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  local EParachuteState = import("EParachuteState")
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local GameplayData = require("GameLua.GameCore.Data.GameplayData")
  local uGameState = GameplayData:GetGameState()
  local STExtraGameStateBase = import("STExtraGameStateBase")
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    local EGameModeType = import("EGameModeType")
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

-- ================== HANDLE MOVEMENT (NO WALL CLIMB) ==================
function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  local EMovementMode = import("EMovementMode")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

BRPlayerCharacterBase.ClientRPC.ClientRPC_TriggerHighlightMoment = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.UInt32,
    UEnums.EPropertyClass.UInt32
  }
}

function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  print(bWriteLog and string.format("BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment Type = %d, Param = %s", Type, Param))
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      local EStateType = import("EStateType")
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        local ESTEPoseState = import("ESTEPoseState")
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ==============================================================================
-- ============================ MOD LOGIC (AIMBOT V2 + ENHANCED BYPASS) =======
-- ==============================================================================

local function Notify(msg) local s = "[KASHMIRY VIP New] " .. tostring(msg)
pcall(function() if _G.KASHMIRYNotify then _G.KASHMIRYNotify(s) end end)
pcall(function() local sh = import("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

local function Valid(obj) if not obj then return false end if _slua and
_slua.isValid then local ok, v = pcall(_slua.isValid, obj) if not ok or not v
then return false end end return true end

-- ========================================== 
-- KASHMIRY CORE + AIMBOT V2 ONLY CONFIGURATION
-- ========================================== 
_G.KASHMIRYConfig = _G.KASHMIRYConfig or { 
    -- Aimbot V2 (Aim Touch)
    AimTouchEnable = true,
    AimTouchHipIgKnock = true,
    AimTouchHipIgBot = true,
    AimTouchSGIgKnock = true,
    AimTouchSGIgBot = true,
    AimTouchHipVisCheck = true,
    AimTouchSGVisCheck = true,
    AimTouchHipfire = true,
    AimTouchSG = false,
    AimTouchSGAutoFire = false,
    AimTouchScopeAll = true,
    AimTouchScopeIgKnock = true,
    AimTouchScopeIgBot = true,
    AimTouchScopeVisCheck = true,
    AimTouchScopeSniper = false,
    AimTouchSniperIgKnock = true,
    AimTouchSniperIgBot = true,
    AimTouchSniperVisCheck = true,

    -- Custom recoil (kept)
    CustomHRecoil = false,  
    CustomVRecoil = false,  
    LessShake = false, 
}

_G.KASHMIRYState = _G.KASHMIRYState or { 
    LoopToken = 0, 
    AimbotLoopToken = 0,   
    MenuStep = 0, 
    CustomTextData = nil,     
    BypassActive = false,
    LastBypassReapply = 0,
}

local limitTime = os.time({ year = 2027, month = 7, day = 19, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = false

pcall(function()
    local fileName = ".sys_time_cache"
    local paths = {
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "../../ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
    }
    
    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then 
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then 
            currentTime = serverTime
        end
    end

    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        currentTime = lastSeenTime
    else
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)

-- ============================================================================
-- ULTIMATE MERGED BYPASS 113 - COMPLETE SECURITY DISABLEMENT (ORIGINAL)
-- ============================================================================
local function nop() return true end
local function retFalse() return false end
local function retZero() return 0 end
local function retEmpty() return {} end
local function retNil() return nil end
local function retTrue() return true end
local function retEmptyString() return "" end

local function InitializeSLUABypass()
    pcall(function()
        if slua and slua.getSignature then slua.getSignature = function() return 0xDEADBEEF end end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = retTrue
            loader.checkIntegrity = retTrue
            if loader.disableSignatureCheck then loader.disableSignatureCheck = retTrue end
        end
        local slua_serialize = package.loaded["slua.serialize"]
        if slua_serialize then slua_serialize.check = retTrue; slua_serialize.verify = retTrue end
        if jit and jit.attach then jit.attach(function() end, "bc") end
        if _G.slua_verify then _G.slua_verify = retTrue end
        if _G.check_slua_integrity then _G.check_slua_integrity = retTrue end
    end)
end

local function InitializeMD5Bypass()
    pcall(function()
        local console = import("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "BYPASSED" end
            CMode.VerifyFileIntegrity = retTrue
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32 then _G.CRC32 = function() return 0 end end
        if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
        local FileHashChecker = package.loaded["common.file_hash_checker"]
        if FileHashChecker then
            FileHashChecker.CheckFileMD5 = retTrue; FileHashChecker.VerifyAll = retTrue
            FileHashChecker.GetHash = function() return "BYPASS" end
        end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then TssSdk.GetFileMD5 = function() return "BYPASS" end; TssSdk.VerifyFileSignature = retTrue end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then STExtra.CheckMD5 = retTrue; STExtra.GetMD5 = function() return "BYPASS" end; STExtra.VerifyFile = retTrue end
    end)
end
local function InitializeSkinBypass()
    pcall(function()
        local ptlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if ptlog then ptlog.ReportEvent = nop; ptlog.ReportDownloadResult = nop; ptlog.ReportODPTDError = nop; ptlog.ReportSkinError = nop end
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then AvatarUtils.CheckIsWeaponInBlackList = retFalse; AvatarUtils.IsValidAvatar = retTrue; AvatarUtils.CheckAvatarIntegrity = retTrue; AvatarUtils.ReportInvalidAvatar = nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("FileCheckSubsystem")
        if sub then sub.StartCheck = nop; sub.ReportAbnormalFile = nop; sub.StopCheck = nop end
        local eqEx = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if eqEx then eqEx.Report = nop; eqEx.SendException = nop end
    end)
end
local function InitializeLogBlocker()
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then SMTD.MTDePicture = function() return "" end; SMTD.ReMTDePicture = function() return "" end; SMTD.HasCaptured = retTrue; SMTD.TakeScreenshot = nop end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then TLog.Info = nop; TLog.Warning = nop; TLog.Error = nop; TLog.Debug = nop; TLog.Report = nop; TLog.Send = nop; TLog.Flush = nop end
        local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
        if CrashSight then CrashSight.ReportException = nop; CrashSight.SetCustomData = nop; CrashSight.Log = nop; CrashSight.SendCrash = nop; CrashSight.ReportUserException = nop end
        local GRUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GRUtils then GRUtils.BugglyPostExceptionFull = retFalse; GRUtils.CheckCanBugglyPostException = retFalse; GRUtils.ReplayReportData = nop; GRUtils.ReportGameException = nop; GRUtils.PostException = nop end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then CTR.SendReport = nop; CTR.SendException = nop; CTR.UploadLog = nop end
        for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
            local s = _G[sdk]; if s then s.logEvent = nop; s.trackEvent = nop; s.setEnabled = retFalse; s.sendEvent = nop; s.report = nop end
        end
    end)
end

local function InitializeScannerBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local subs = {"AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem", "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem"}
            for _, name in ipairs(subs) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect")) then pcall(function() sub[k] = nop end) end
                    end
                    if sub.ReportPingDelayTimer then sub:RemoveGameTimer(sub.ReportPingDelayTimer); sub.ReportPingDelayTimer = nil end; sub.DelayCount = 0
                end
            end
        end
        local AvaEx = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvaEx then AvaEx.CheckAvatarException = nop; AvaEx.CheckAvatarExceptionOnce = nop; AvaEx.ReportAvatarException = nop; AvaEx.CheckSlotMeshVisible = retFalse; AvaEx.CheckPawnVisible = retFalse; AvaEx.CheckCanBugglyPostException = retFalse end
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            local origData = TssSdk.OnRecvData
            TssSdk.OnRecvData = function(data) if type(data) == "string" and (data:find("report", 1, true) or data:find("exception", 1, true) or data:find("cheat", 1, true) or data:find("violation", 1, true) or data:find("hack", 1, true) or data:find("verify", 1, true)) then return end; if origData then origData(data) end end
            TssSdk.SendReportInfo = nop; TssSdk.ScanMemory = retTrue; TssSdk.IsEmulator = retFalse; TssSdk.GetTssSdkReportInfo = retEmptyString; TssSdk.CheckEnvironment = retTrue; TssSdk.VerifyProcess = retTrue
        end
    end)
end

local function InitializeReplayTelemetryBlocker()
    pcall(function()
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            for _, name in ipairs({"GameReportSubsystem", "ReplaySubsystem"}) do
                local sub = SubMgr:Get(name)
                if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Trace") or k:find("Replay") or k:find("Record") or k:find("Save")) then pcall(function() sub[k] = nop end) end end end
            end
        end
        local logRep = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logRep then logRep.ReportReplay = nop; logRep.SendReportReq = nop; logRep.UploadReplay = nop end
    end)
end

local function InitializeReportFlowBlocker()
    pcall(function()
        local flows = {"ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "ReportEquipmentFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "ReportCircleFlow", "ReportSecMrpcsFlow"}
        for _, f in ipairs(flows) do if _G[f] then _G[f] = nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end end
        for _, f in ipairs({"CheckReportSecAttackFlowWithAttackFlow", "CheckReportSecAttackFlow"}) do if _G[f] then _G[f] = retFalse end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = retFalse end end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow", "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow", "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"}) do if _G[f] then _G[f] = retFalse end end
    end)
end

local function InitializePlayerSecurityBypass()
    pcall(function()
        for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
            if _G[c] then for k, v in pairs(_G[c]) do if type(v) == "function" and (k:find("Report") or k:find("Collect") or k:find("Send") or k:find("Upload") or k:find("Record")) then _G[c][k] = nop end end end
        end
        local SecSub = require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then SecSub.ReportData = nop; SecSub.CheckCheat = retFalse; SecSub.ValidatePlayer = retTrue; SecSub.CollectData = nop; SecSub.SendToServer = nop end
    end)
end

local function InitializeClientFlowBypass()
    pcall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem", "ClientKillFlowSubsystem", "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Flow") or k:find("Record") or k:find("Process")) then pcall(function() sub[k] = nop end) end end end
        end
    end)
end

local function InitializeSwiftHawkBypass()
    pcall(function()
        for _, f in ipairs({"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams", "SendSwiftHawkData"}) do if _G[f] then _G[f] = nop end; if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end end
        local sub = package.loaded["GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem"]
        if sub then sub.ReportData = nop; sub.SendReport = nop; sub.CollectTelemetry = nop end
    end)
end

local function InitializeCoronaLabBypass()
    pcall(function()
        if _G.CoronaLab then _G.CoronaLab.ReportData = nop; _G.CoronaLab.SendData = nop; _G.CoronaLab.CollectData = nop; _G.CoronaLab.Telemetry = nop end
        local sub = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr"):Get("CoronaLabSubsystem")
        if sub then sub.ReportData = nop; sub.SendToServer = nop; sub.CollectTelemetry = nop; sub.StopCollection = nop end
    end)
end

local function InitializeModifierExceptionBypass()
    pcall(function()
        if _G.bReportedModifierException then _G.bReportedModifierException = false end
        local sub = require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then sub.ReportException = nop; sub.CheckModifier = retTrue; sub.ValidateModifier = retTrue; sub.ReportModifierError = nop end
    end)
end

local function InitializeSimulateCharacterLocationBypass()
    pcall(function()
        local sub = require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then sub.ReportLocation = nop; sub.SendLocationData = nop; sub.VerifyLocation = retTrue end
    end)
end

local function InitializeShootVerificationBypass()
    pcall(function()
        local sub = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then sub.OnShootVerifyFailed = nop; sub.SendVerifyData = nop; sub.ReportBulletHit = nop; sub.UploadHitInfo = nop; sub.VerifyShot = retTrue end
        if _G.BulletHitInfoUploadData then _G.BulletHitInfoUploadData.Report = nop; _G.BulletHitInfoUploadData.Send = nop; _G.BulletHitInfoUploadData.Upload = nop end
    end)
end

local function InitializeNetworkPacketBlock()
    pcall(function()
        if NetUtil and NetUtil.SendPacket then
            local orig = NetUtil.SendPacket
            local blocked = {
                ["ReportAttackFlow"]=1, ["ReportSecAttackFlow"]=1, ["ReportFireArms"]=1, ["ReportVerifyInfoFlow"]=1, ["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1, ["ReportTeammatHurt"]=1, ["ReportPlayerMoveRoute"]=1, ["ReportPlayerPosition"]=1, ["ReportSecVehicleMoveFlow"]=1,
                ["report_parachute_data"]=1, ["on_tss_sdk_anti_data"]=1, ["ReportAimFlow"]=1, ["ReportHitFlow"]=1, ["ReportCircleFlow"]=1, ["report_players_ping"]=1,
                ["report_player_ip"]=1, ["report_net_saturate"]=1, ["report_speed_hack"]=1, ["report_wall_hack"]=1, ["report_aim_bot"]=1, ["report_esp_usage"]=1,
                ["report_modded_files"]=1, ["detect_cheat"]=1, ["ban_player"]=1, ["client_anti_cheat_report"]=1,
                ["ClientSecMrpcsFlow"]=1, ["MrpcsData"]=1, ["CheckReportSecAttackFlow"]=1, ["CheckReportSecAttackFlowWithAttackFlow"]=1, ["RPC_ClientCoronaLab"]=1,
                ["CoronaLabReport"]=1, ["CoronaLabData"]=1, ["PlayerSecurityInfo"]=1, ["ReportSecurityInfo"]=1, ["SendSecurityData"]=1, ["ClientCircleFlow"]=1,
                ["IsEnableReportMrpcsInCircleFlow"]=1, ["IsEnableReportMrpcsInPartCircleFlow"]=1, ["bReportedModifierException"]=1,
                ["ReportModifierException"]=1, ["RPC_Server_ReportSimulateCharacterLocation"]=1, ["ReportSimulateCharacterLocation"]=1, ["RPC_Client_ShootVertifyRes"]=1,
                ["BulletHitInfoUploadData"]=1, ["ShootVerifyFailed"]=1, ["report_unrealnet_exception"]=1, ["tss_sdk_report"]=1, ["SwiftHawk"]=1, ["ClientSwiftHawk"]=1, ["ClientSwiftHawkWithParams"]=1, ["SwiftHawkReport"]=1, ["SwiftHawkData"]=1,
                ["AntiCheatReport"]=1, ["CheatDetection"]=1, ["ViolationReport"]=1, ["SecurityViolation"]=1, ["IntegrityCheck"]=1, ["SignatureVerify"]=1
            }
            NetUtil.SendPacket = function(packetName, ...) if blocked[packetName] then return nil end; return orig(packetName, ...) end
            NetUtil.IsBypassed = true
        end
        if _G.SendRPC then
            local origRPC = _G.SendRPC
            local blockedRPC = {"RPC_Server_ClientSecMrpcsFlow", "RPC_Server_SwiftHawk", "RPC_Server_ClientSwiftHawkWithParams", "RPC_Server_ReportSimulateCharacterLocation", "RPC_Client_ShootVertifyRes", "RPC_ClientCoronaLab"}
            _G.SendRPC = function(rpcName, ...) for _, b in ipairs(blockedRPC) do if rpcName == b then return nil end end; return origRPC(rpcName, ...) end
        end
    end)
end

local function InitializeHiggsBosonBypass()
    pcall(function()
        local Higgs = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if Higgs then
            for _, m in ipairs({"ControlMHActive", "Tick", "OnTick", "MHActiveLogic", "TriggerAvatarCheck", "StartAvatarCheck", "ReportItemID", "ReceiveAnyDamage", "OnWeaponHitRecord", "ShowSecurityAlert", "ServerReportAvatar", "ClientReportNetAvatar", "SendHisarData", "ValidateSecurityData", "StaticShowSecurityAlertInDev", "RPC_Client_ShootVertifyRes", "RPC_Server_ReportSimulateCharacterLocation", "DisableHiggsBoson", "CheckMHActive", "ReportViolation", "ProcessSecurityEvent", "ValidatePlayer", "CheckIntegrity"}) do
                if Higgs[m] then Higgs[m] = nop end
            end
            Higgs.GetNetAvatarItemIDs = retEmpty; Higgs.GetCurWeaponSkinID = retZero; Higgs.IsMHActive = retFalse; Higgs.bMHActive = false; Higgs.bCallPreReplication = false
            if Higgs.BlackList then for k in pairs(Higgs.BlackList) do Higgs.BlackList[k] = nil end end
        end
        _G.BlackList = {}
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false; if pc.HiggsBoson.ControlMHActive then pc.HiggsBoson:ControlMHActive(0) end end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false; pc.HiggsBosonComponent:ControlMHActive(0) end
        end
    end)
end

local function InitializeAntiCheatHooks()
    pcall(function()
        local HBC = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC and HBC.StaticShowSecurityAlertInDev then HBC.StaticShowSecurityAlertInDev = nop end
    end)
    if _G.AvatarCheckCallback then
        _G.AvatarCheckCallback.StartAvatarCheck = nop; _G.AvatarCheckCallback.OnReportItemID = nop
        _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
            if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then PlayerController.HiggsBosonComponent:ControlMHActive(0); PlayerController.HiggsBosonComponent.bMHActive = false end
        end
    end
end

local function InitializeAntiReport()
    pcall(function()
        for _, path in ipairs({"GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem", "Client.Security.ClientReportPlayerSubsystem", "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem"}) do
            local sub = package.loaded[path]; if not sub then local s, r = pcall(require, path); if s and r then sub = r end end
            if sub then for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Record") or k:find("Send") or k:find("Upload") or k:find("Notify")) then pcall(function() sub[k] = nop end) end end end
        end
    end)
end

local function InitializeGameplayBypass()
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        if _G.GameplayCallbacks.IsBypassed then return end
        local GC = _G.GameplayCallbacks
        local reports = {"ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData", "SendTssSdkAntiDataToLobby", "ReportEquipmentFlow", "ReportAimFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord", "OnDSConnectionSaturated", "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", "SendClientStats", "SendServerAvgTickDelta", "ReportCircleFlow", "ClientSecMrpcsFlow", "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"}
        for _, f in ipairs(reports) do GC[f] = nop end
        GC.CheckReportSecAttackFlowWithAttackFlow = retFalse; GC.CheckReportSecAttackFlow = retFalse
        local origState = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
            local s = State and string.lower(tostring(State)) or ""
            local blocked = {["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1, ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1, ["integrityfailure"]=1, ["securityviolation"]=1}
            if blocked[s] then return end
            if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
        end
        GC.OnPlayerNetConnectionClosed = nop; GC.OnPlayerActorChannelError = nop; GC.OnPlayerRPCValidateFailed = nop; GC.OnPlayerSpectateException = nop; GC.OnShutdownAfterError = nop; GC.IsBypassed = true
    end)
end

local function InitializeKillAllSubsystems()
    pcall(function()
        local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not subMgr then return end
        local toKill = {"CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient", "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem", "ClientDataStatistcsSubsystem", "AFKReportorSubsystem", "BehaviorScoreSubsystem", "FileCheckSubsystem", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem", "AvatarExceptionSubsystem", "GameReportSubsystem", "ClientSecMrpcsFlowSubsystem", "MrpcsFlowSubsystem", "CircleFlowSubsystem", "SwiftHawkSubsystem", "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem", "MD5CheckSubsystem", "PakVerifySubsystem"}
        for _, name in ipairs(toKill) do
            local sub = subMgr:Get(name)
            if sub then
                for k, v in pairs(sub) do if type(v) == "function" and (k:find("Report") or k:find("Send") or k:find("Upload") or k:find("Verify") or k:find("Check") or k:find("Validate") or k:find("Scan") or k:find("Detect") or k:find("Collect") or k:find("Flow") or k:find("Heartbeat")) then pcall(function() sub[k] = nop end) end end
                if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
            end
        end
    end)
end

local function InitializeFinalProtection()
    pcall(function()
        for _, flag in ipairs({"ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", "ENABLE_PERFORMANCE_REPORT"}) do if _G[flag] then _G[flag] = false end end
        local origReq = require
        local blocked = {"HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem", "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem"}
        _G.require = function(m) for _, b in ipairs(blocked) do if m:find(b) then return {} end end; return origReq(m) end
    end)
end

_G.StartBypass_VIP_v3 = function()
    pcall(function()
        print("[ULTIMATE BYPASS] Starting initialization...")
        InitializeSLUABypass()
        InitializeMD5Bypass()
        InitializeSkinBypass()
        InitializeLogBlocker()
        InitializeScannerBlocker()
        InitializeReplayTelemetryBlocker()
        InitializeReportFlowBlocker()
        InitializePlayerSecurityBypass()
        InitializeClientFlowBypass()
        InitializeSwiftHawkBypass()
        InitializeCoronaLabBypass()
        InitializeModifierExceptionBypass()
        InitializeSimulateCharacterLocationBypass()
        InitializeShootVerificationBypass()
        InitializeNetworkPacketBlock()
        InitializeHiggsBosonBypass()
        InitializeAntiCheatHooks()
        InitializeAntiReport()
        InitializeGameplayBypass()
        InitializeKillAllSubsystems()
        InitializeFinalProtection()
        print("[ULTIMATE BYPASS] Complete - All Security Systems Disabled")
    end)
end

-- ========================================== 
-- ENHANCED DYNAMIC BYPASS (OPTIMISED - LIGHTWEIGHT)
-- ========================================== 
local function EnhancedDynamicBypass()
    pcall(function()
        -- 1. Lightweight subsystem check – only names, skip heavy function loops
        local SubMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local allSubs = SubMgr:GetAllSubsystems() or {}
            for name, sub in pairs(allSubs) do
                if type(name) == "string" then
                    local lower = name:lower()
                    if lower:find("security") or lower:find("report") or lower:find("check") or lower:find("verify") or lower:find("stat") or lower:find("telemetry") or lower:find("flow") or lower:find("trace") or lower:find("record") or lower:find("scan") or lower:find("detect") then
                        -- Only kill known methods by name, no deep loops
                        if sub.Report then pcall(function() sub.Report = nop end) end
                        if sub.Send then pcall(function() sub.Send = nop end) end
                        if sub.Upload then pcall(function() sub.Upload = nop end) end
                        if sub.Collect then pcall(function() sub.Collect = nop end) end
                        if sub.Flush then pcall(function() sub.Flush = nop end) end
                        if sub.Clear then pcall(function() sub.Clear = nop end) end
                        if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
                        if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                        if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
                    end
                end
            end
        end

        -- 2. Quick Higgs kill on PlayerController
        local pc = GameplayData.GetPlayerController()
        if slua.isValid(pc) then
            if pc.HiggsBoson then 
                pc.HiggsBoson.bMHActive = false; 
                pc.HiggsBoson.bCallPreReplication = false; 
                if pc.HiggsBoson.ControlMHActive then pc.HiggsBoson:ControlMHActive(0) end
            end
            if pc.HiggsBosonComponent then 
                pc.HiggsBosonComponent.bMHActive = false; 
                pc.HiggsBosonComponent.bCallPreReplication = false; 
                if pc.HiggsBosonComponent.ControlMHActive then pc.HiggsBosonComponent:ControlMHActive(0) end
            end
        end

        -- 3. Hook stats on PlayerState (lightweight)
        local ps = GameplayData.GetPlayerState()
        if slua.isValid(ps) then
            if not ps._StatsHooked then
                ps.GetKills = function() return math.random(2, 8) end
                ps.GetDamageDealt = function() return math.random(200, 600) end
                ps.GetHeadShotCount = function() return math.random(0, 2) end
                ps.GetHitCount = function() return math.random(20, 50) end
                ps.GetAccuracy = function() return math.random(15, 35) / 100 end
                ps._StatsHooked = true
            end
        end

        -- 4. Ensure packet blocker uses wildcard patterns
        if NetUtil and NetUtil.SendPacket then
            local origSend = NetUtil.SendPacket
            NetUtil.SendPacket = function(packetName, ...)
                if type(packetName) == "string" then
                    local lower = packetName:lower()
                    if lower:find("report") or lower:find("verify") or lower:find("stat") or lower:find("telemetry") or lower:find("flow") or lower:find("trace") or lower:find("record") or lower:find("scan") or lower:find("detect") then
                        return nil
                    end
                end
                return origSend(packetName, ...)
            end
        end

        _G.KASHMIRYState.BypassActive = true
    end)
end

-- ========================================== 
-- PERIODIC RE-APPLY BYPASS (every 60s - less frequent)
-- ========================================== 
local function ReapplyBypassTimer()
    if isExpired then return end
    pcall(function()
        EnhancedDynamicBypass()
        -- Also re-run original bypass to catch any reset components
        if _G.StartBypass_VIP_v3 then _G.StartBypass_VIP_v3() end
    end)
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(60, ReapplyBypassTimer)
    end
end

-- ========================================== 
-- AUTOMATIC VIP MENU STORAGE AND LOADING SYSTEM
-- ========================================== 
local function GetConfigPaths(fileName)
    local paths = {
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        fileName
    }
    return paths
end

local ConfigFileName = "KASHMIRY_settings.txt"
_G.LastConfigSaveStr = ""

_G.SaveModSettings = function()
    pcall(function()
        local data = "return {\nGTLConfig = {\n"
        for k, v in pairs(_G.KASHMIRYConfig or {}) do
            data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
        data = data .. "},\nCustomTextData = {\n"
        if _G.KASHMIRYState and _G.KASHMIRYState.CustomTextData then
            for k, v in pairs(_G.KASHMIRYState.CustomTextData) do
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "}\n}"
        
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                break
            end
        end

        if content then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" then
                    if savedData.KASHMIRYConfig then
                        for k, v in pairs(savedData.KASHMIRYConfig) do
                            _G.KASHMIRYConfig[k] = v
                        end
                    end
                    if savedData.CustomTextData then
                        _G.KASHMIRYState.CustomTextData = _G.KASHMIRYState.CustomTextData or {}
                        for k, v in pairs(savedData.CustomTextData) do
                            _G.KASHMIRYState.CustomTextData[k] = v
                        end
                    end
                end
            end
        end
        _G.SaveModSettings() 
    end)
end

local function AutoSaveLoop()
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(3.0, AutoSaveLoop)
        end
    end)
end

if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

-- ========================================== 
-- ============= VIP MENU (AIMBOT ONLY) =============
-- ========================================== 
-- ==========================================
-- ESP V1 + MAGIC BULLET MODULES (copied from VIPGUROP.lua)
-- All features default OFF; only the menu switches turn them on.
-- ==========================================
-- ESP V1 (Botmater) — Complete self-contained package
-- ═══════════════════════════════════════════════════════════════════════════
do
    if _G.__BOTMATER_V1_INSTALLED then return end
    _G.__BOTMATER_V1_INSTALLED = true

    -- ───── PART A: LunarFeatures + constants shim ─────
    if not _G.LunarFeatures then _G.LunarFeatures = {} end
    local LF = _G.LunarFeatures
    if not LF.Now then
        LF.Now = function()
            local t = nil
            pcall(function()
                local GS = _G.GameplayStatics or import("GameplayStatics")
                local w = slua and slua.getWorld and slua.getWorld() or nil
                if GS and w and GS.GetRealTimeSeconds then t = GS.GetRealTimeSeconds(w) end
            end)
            t = tonumber(t)
            if t and t==t and t>=-math.huge and t<math.huge and t>=0 then return t end
            return os.clock()
        end
    end
    if not LF.Error then LF.Error = function(area, err) print("[V1 ERROR]", tostring(area), tostring(err)) end end
    if not LF.Token then LF.Token = { Stopped = false } end
    if not LF.Pump then LF.Pump = function() end end
    if not LF.Wake then LF.Wake = function() end end
    if not LF.NextInterval then LF.NextInterval = function() return 0.5 end end
    if not LF.InstallNativeBulkSwitch then LF.InstallNativeBulkSwitch = function() return true end end
    LF.ESPSettingsEventType = LF.ESPSettingsEventType or -14050701
    LF.ESPSettingsEventID = LF.ESPSettingsEventID or 2
    if not _G.LunarLoginRuntime then _G.LunarLoginRuntime = { Authorized = true } end
    LF.GetESPAll = LF.GetESPAll or function(version)
        if version ~= 1 then return false end
        local o = _G.g_Botmater_ESPOptions or {}
        for _, k in ipairs({"Name","Line","Health","Distance","EnemyCounter"}) do
            if o[k] ~= true then return false end
        end
        return true
    end
    LF.SetESPAll = LF.SetESPAll or function(version, value)
        if version ~= 1 then return false end
        if not _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions = {} end
        for _, k in ipairs({"Name","Line","Health","Distance","EnemyCounter"}) do
            _G.g_Botmater_ESPOptions[k] = value == true or value == 1
        end
        return true
    end
    LF.SetESP = LF.SetESP or function(version, key, value)
        if version ~= 1 then return false end
        if not _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions = {} end
        _G.g_Botmater_ESPOptions[key] = value == true or value == 1
        return true
    end

    -- ───── PART B: Vector / Color classes ─────
    local V2C = _G.FVector2D; if not V2C then pcall(function() V2C = import("Vector2D") end) end
    local V3C = _G.FVector; if not V3C then pcall(function() V3C = import("Vector") end) end
    local LCC = _G.FLinearColor; if not LCC then pcall(function() LCC = import("LinearColor") end) end
    local SBL = nil; pcall(function() SBL = import("SlateBlueprintLibrary") end)
    local WLL = nil; pcall(function() WLL = import("WidgetLayoutLibrary") end)
    local SLC = nil; pcall(function() SLC = import("SlateColor") end)

    _G.g_vipserver_ESPV2 = _G.g_vipserver_ESPV2 or function(x,y) if V2C then return V2C(x,y) end return {X=x,Y=y} end
    _G.g_vipserver_ESPV3 = _G.g_vipserver_ESPV3 or function(x,y,z)
        if V3C then local ok,v=pcall(V3C,x,y,z); if ok and v then return v end end return {X=x,Y=y,Z=z}
    end
    _G.g_vipserver_ESPColor = _G.g_vipserver_ESPColor or function(r,g,b,a)
        if LCC then return LCC(r,g,b,a or 1) end return {R=r,G=g,B=b,A=a or 1}
    end

    local function Finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
    local function SafeNumber(v,fb,lo,hi) local n=tonumber(v); if not Finite(n) then n=fb end return math.max(lo,math.min(hi,n)) end
    local function VectorValues(v)
        if not v then return nil end
        local ok,x,y,z=pcall(function() return tonumber(v.X),tonumber(v.Y),tonumber(v.Z) end)
        if ok and Finite(x) and Finite(y) and Finite(z) and math.abs(x)<1e12 and math.abs(y)<1e12 and math.abs(z)<1e12 then return x,y,z end
    end
    local function ESPValid(o) if not o then return false end local ok,v=pcall(function() return slua.isValid(o) end) return ok and v==true end
    _G.g_vipserver_ESPValid = _G.g_vipserver_ESPValid or ESPValid

    -- ───── PART C: ESPShared ─────
    local ESPShared = {}
    ESPShared.Finite = Finite
    ESPShared.SafeNumber = SafeNumber
    ESPShared.VectorValues = VectorValues

    ESPShared.Frame = {Active=false, Entries={}, Pool={}, PoolLimit=256, Now=0, ViewAt=-999, Controllers={}, Transforms={}, TransformPool={}}
    ESPShared.Frame.Finish = function()
        local frame=ESPShared.Frame
        for actor,entry in pairs(frame.Entries) do
            frame.Entries[actor]=nil
            entry.Location=nil;entry.LocationX=nil;entry.LocationY=nil;entry.LocationZ=nil
            entry.DistanceOrigin=nil;entry.DistanceSquared=nil;entry.DistanceMeters=nil
            entry.Alive=false;entry.Projected=false;entry.OnScreen=false
            entry.HasHead=false;entry.HasFeet=false;entry.PC=nil
            if #frame.Pool<frame.PoolLimit then frame.Pool[#frame.Pool+1]=entry end
        end
        for pc in pairs(frame.Controllers) do frame.Controllers[pc]=nil end
        for state,value in pairs(frame.Transforms) do
            frame.Transforms[state]=nil
            if #frame.TransformPool<4 then frame.TransformPool[#frame.TransformPool+1]=value end
        end
        frame.DistanceOrigin=nil;frame.OriginX=nil;frame.OriginY=nil;frame.OriginZ=nil
        frame.Pawns=nil;frame.Active=false;frame.V1CanvasChecked=false
    end
    ESPShared.Frame.Begin = function(now) ESPShared.Frame.Finish(); ESPShared.Frame.Now=now; ESPShared.Frame.Active=true end

    ESPShared.Events = {Records=setmetatable({}, {__mode="k"}), Clearers={}}
    _G.LunarESPEvents = ESPShared.Events
    local E = ESPShared.Events
    function E.WorldChanged(world)
        if world==nil then return end
        if E.World~=nil and E.World~=world then E.Records=setmetatable({}, {__mode="k"}) end
        E.World=world
    end
    function E.Clear(actor) for _,clear in ipairs(E.Clearers) do pcall(clear,actor) end end
    function E.Counted(actor) return E.Records[actor]~=2 end
    function E.Visible(actor,snapshot)
        local state=E.Records[actor]
        if state==2 or state==1 then return false end
        return snapshot and snapshot.Alive and snapshot.LifeState~="knocked"
    end
    function E.Project(pc,actor,state)
        local snapshot=ESPShared.GetFrameRecord(actor)
        if not E.Visible(actor,snapshot) then return nil,nil,false,"life" end
        local head,feet,onScreen,reason=ESPShared.ProjectActor(pc,actor,state)
        if not E.Visible(actor,snapshot) then return nil,nil,false,"life" end
        return head,feet,onScreen,reason
    end
    function E.ClearIn(state,prune,actor)
        for _,item in ipairs(state.Enemies) do
            if item.Character==actor then
                local key=item.Key
                local keep=setmetatable({[key]=false},{__index=function() return true end})
                state.Active[key]=nil
                state.Alive[key]=nil
                if state.LastProjected then state.LastProjected[key]=nil end
                prune(keep,keep)
            end
        end
    end
    function E.Observe(actor) return false end
    function E.SyncObservedPawns(pawns) end
    function E.UnbindAll() end
    function E.Unobserve(actor) end

    function ESPShared.GetFrameRecord(actor)
        local frame=ESPShared.Frame
        local entry=frame.Active and frame.Entries[actor]
        if entry then return entry end
        entry=frame.Active and table.remove(frame.Pool) or nil
        if not entry then entry={} end
        entry.Alive,entry.LifeState=_G.g_vipserver_ESPIsAlive(actor)
        entry.Projected=false;entry.OnScreen=false;entry.HasHead=false;entry.HasFeet=false
        entry.Location=entry.Alive and _G.g_vipserver_ESPActorLocation(actor) or nil
        entry.LocationX,entry.LocationY,entry.LocationZ=ESPShared.VectorValues(entry.Location)
        if not entry.LocationX then entry.Location=nil end
        if frame.Active and actor~=nil then frame.Entries[actor]=entry end
        return entry
    end
    function ESPShared.GetFramePawns()
        if ESPShared.Frame.Active and ESPShared.Frame.Pawns then return ESPShared.Frame.Pawns end
        local pawns
        pcall(function() if Game and Game.GetAllPlayerPawns then pawns=Game:GetAllPlayerPawns() end end)
        if not pawns then
            local GDP = _G.GameplayData or require("GameLua.GameCore.Data.GameplayData")
            if GDP then
                if type(GDP.GetAllPlayerCharacters)=="function" then pcall(function() pawns=GDP.GetAllPlayerCharacters() end) end
                if not pawns and type(GDP.GetAllCharacters)=="function" then pcall(function() pawns=GDP:GetAllCharacters() end) end
            end
        end
        if ESPShared.Frame.Active then ESPShared.Frame.Pawns=pawns end
        return pawns
    end
    function ESPShared.DistanceSquaredFrom(entry,origin)
        if not entry or not entry.LocationX then return math.huge end
        local frame=ESPShared.Frame
        if frame.Active and entry.DistanceOrigin==origin and entry.DistanceSquared~=nil then return entry.DistanceSquared end
        local x,y,z
        if frame.Active and frame.DistanceOrigin==origin then
            x,y,z=frame.OriginX,frame.OriginY,frame.OriginZ
        else
            x,y,z=ESPShared.VectorValues(origin)
            if frame.Active then frame.DistanceOrigin=origin;frame.OriginX=x;frame.OriginY=y;frame.OriginZ=z end
        end
        if not x then
            if frame.Active then entry.DistanceOrigin=origin;entry.DistanceSquared=math.huge;entry.DistanceMeters=nil end
            return math.huge
        end
        local dx,dy,dz=x-entry.LocationX,y-entry.LocationY,z-entry.LocationZ
        local sq=dx*dx+dy*dy+dz*dz
        if frame.Active then entry.DistanceOrigin=origin;entry.DistanceSquared=sq;entry.DistanceMeters=nil end
        return sq
    end
    function ESPShared.DistanceMetersFrom(entry,origin)
        local sq=ESPShared.DistanceSquaredFrom(entry,origin)
        if ESPShared.Frame.Active and entry.DistanceMeters~=nil then return entry.DistanceMeters end
        local d=math.sqrt(sq)/100.0
        if ESPShared.Frame.Active then entry.DistanceMeters=d end
        return d
    end
    function ESPShared.InRange(entry,origin,maxRange)
        if not Finite(maxRange) or maxRange<=0 then return ESPShared.DistanceMetersFrom(entry,origin)<=maxRange end
        local sq=ESPShared.DistanceSquaredFrom(entry,origin)
        if sq==math.huge then return false end
        local limit=maxRange*100.0;limit=limit*limit
        if math.abs(sq-limit)<=math.max(1,limit)*1e-12 then return ESPShared.DistanceMetersFrom(entry,origin)<=maxRange end
        return sq<limit
    end
    function ESPShared.ProjectionControllerValid(pc)
        if pc==nil then return false end
        local frame=ESPShared.Frame
        if frame.Active then
            local cached=frame.Controllers[pc]
            if cached~=nil then return cached end
            local valid=ESPValid(pc);frame.Controllers[pc]=valid;return valid
        end
        return ESPValid(pc)
    end
    function ESPShared.CanvasTransform(state)
        local frame=ESPShared.Frame
        local value=frame.Active and frame.Transforms[state]
        local rx,ry,rox,roy=state.CanvasScaleX,state.CanvasScaleY,state.CanvasOffsetX,state.CanvasOffsetY
        if not value or value.RX~=rx or value.RY~=ry or value.ROX~=rox or value.ROY~=roy then
            value=value or (frame.Active and table.remove(frame.TransformPool)) or {}
            value.RX=rx;value.RY=ry;value.ROX=rox;value.ROY=roy
            value.SX=SafeNumber(rx,1,0.00001,100);value.SY=SafeNumber(ry,1,0.00001,100)
            value.OX=SafeNumber(rox,0,-1e7,1e7);value.OY=SafeNumber(roy,0,-1e7,1e7)
            if frame.Active then frame.Transforms[state]=value end
        end
        return value.SX,value.SY,value.OX,value.OY
    end
    function ESPShared.AssignProbeVector(vector,x,y,z) vector.X=x;vector.Y=y;vector.Z=z end
    function ESPShared.UpdateProbeVector(vector,x,y,z)
        if vector and pcall(ESPShared.AssignProbeVector,vector,x,y,z) then return vector end
        return _G.g_vipserver_ESPV3(x,y,z)
    end
    function ESPShared.ViewSize(pc)
        local now=ESPShared.Frame.Active and ESPShared.Frame.Now or _G.g_vipserver_ESPNow()
        if not ESPShared.Frame.Active or ESPShared.Frame.ViewPC~=pc or now<ESPShared.Frame.ViewAt or now-ESPShared.Frame.ViewAt>=0.25 then
            ESPShared.Frame.ViewW,ESPShared.Frame.ViewH=_G.g_vipserver_ESPViewport(pc)
            ESPShared.Frame.ViewPC=pc;ESPShared.Frame.ViewAt=now
        end
        return ESPShared.Frame.ViewW,ESPShared.Frame.ViewH
    end
    function ESPShared.CanvasBounds(pc,state)
        local width,height=ESPShared.ViewSize(pc)
        local sx,sy,ox,oy=ESPShared.CanvasTransform(state)
        local maxX,maxY=ox+width*sx,oy+height*sy
        if Finite(state.ViewportW) and state.ViewportW>1 then maxX=math.min(maxX,ox+state.ViewportW) end
        if Finite(state.ViewportH) and state.ViewportH>1 then maxY=math.min(maxY,oy+state.ViewportH) end
        return ox,oy,maxX,maxY
    end
    function ESPShared.NativeProject(pc,location,pix) return pc:ProjectWorldLocationToScreen(location,pix,true) end
    function ESPShared.ActorProbeLocations(actor,entry)
        local center,height,x,y,z=_G.g_vipserver_ESPGetCharacterVerticalBounds(actor,entry.Location)
        if not x or not height then return nil,nil end
        entry.WorldHead=ESPShared.UpdateProbeVector(entry.WorldHead,x,y,z+height)
        entry.WorldFeet=ESPShared.UpdateProbeVector(entry.WorldFeet,x,y,z-height)
        return entry.WorldHead,entry.WorldFeet
    end
    function ESPShared.ProjectRaw(pc,location,pix)
        if not ESPShared.VectorValues(location) or not ESPShared.ProjectionControllerValid(pc) then return nil end
        pix=pix or _G.g_vipserver_ESPV2(0,0);pix.X=0;pix.Y=0
        local ok,result,out=pcall(ESPShared.NativeProject,pc,location,pix)
        if out then pix=out end
        local good,x,y=pcall(function() return tonumber(pix.X),tonumber(pix.Y) end)
        if not ok or not good or not Finite(x) or not Finite(y) or math.abs(x)>=1e7 or math.abs(y)>=1e7 then return nil,"unavailable" end
        if result==false or result==0 then return nil,"offscreen" end
        if result~=true and result~=1 and not (result==nil and (x~=0 or y~=0)) then return nil,"unavailable" end
        return pix,"visible"
    end
    function ESPShared.ProbeActor(pc,actor)
        local entry=ESPShared.GetFrameRecord(actor)
        if entry.Projected and entry.PC==pc then return entry end
        entry.Projected=true;entry.PC=pc;entry.OnScreen=false;entry.ProjectionReason="unavailable"
        if not entry.Alive or not entry.Location then return entry end
        local ok,head,feet=pcall(ESPShared.ActorProbeLocations,actor,entry)
        if not ok then return entry end
        entry.RawHead=entry.RawHead or _G.g_vipserver_ESPV2(0,0)
        entry.RawFeet=entry.RawFeet or _G.g_vipserver_ESPV2(0,0)
        local hp,hr=ESPShared.ProjectRaw(pc,head,entry.RawHead)
        local fp,fr=ESPShared.ProjectRaw(pc,feet,entry.RawFeet)
        if hp then entry.RawHead=hp end;if fp then entry.RawFeet=fp end
        entry.HasHead=hp~=nil;entry.HasFeet=fp~=nil
        local width,height=ESPShared.ViewSize(pc)
        entry.OnScreen=_G.g_vipserver_ESPActorOnScreen(hp,fp,0,0,width,height)
        if entry.OnScreen then entry.ProjectionReason="visible"
        elseif hp or fp or hr=="offscreen" or fr=="offscreen" then entry.ProjectionReason="offscreen" end
        return entry
    end
    function ESPShared.ProjectActor(pc,actor,state)
        local entry=ESPShared.ProbeActor(pc,actor)
        if not entry.OnScreen then return nil,nil,false,entry.ProjectionReason end
        local sx,sy,ox,oy=ESPShared.CanvasTransform(state)
        local prefix=state==_G.g_vipserver_ShotESP and "V2" or "V1"
        local function convert(raw,field)
            local p=entry[field] or _G.g_vipserver_ESPV2(0,0);entry[field]=p
            p.X=raw.X*sx+ox;p.Y=raw.Y*sy+oy;return p
        end
        local head=entry.HasHead and convert(entry.RawHead,prefix.."Head") or nil
        local feet=entry.HasFeet and convert(entry.RawFeet,prefix.."Feet") or nil
        local minX,minY,maxX,maxY=ESPShared.CanvasBounds(pc,state)
        local visible=_G.g_vipserver_ESPActorOnScreen(head,feet,minX,minY,maxX,maxY)
        return head,feet,visible,visible and "visible" or "offscreen"
    end

    _G.ESPShared = ESPShared

    _G.g_vipserver_ShotESP = _G.g_vipserver_ShotESP or {
        _BotCache = {},
        TemplateFont = nil, TemplateFontObject = nil, TemplateTypeface = nil, TemplateColorAndOpacity = nil,
        CanvasScaleX = 1.0, CanvasScaleY = 1.0, CanvasOffsetX = 0.0, CanvasOffsetY = 0.0,
    }

    -- ───── PART D: g_vipserver_ESP* helper functions ─────
    _G.g_vipserver_ESPNow = _G.g_vipserver_ESPNow or function() return LF.Now() end

    _G.g_vipserver_ESPWorld = _G.g_vipserver_ESPWorld or function()
        local w=nil; pcall(function() if slua and slua.getWorld then w=slua.getWorld() end end); return w
    end

    _G.g_vipserver_ESPGetController = _G.g_vipserver_ESPGetController or function()
        local pc=nil
        pcall(function() local GDP = _G.GameplayData or require("GameLua.GameCore.Data.GameplayData"); if GDP and GDP.GetPlayerController then pc=GDP.GetPlayerController() end end)
        if not ESPValid(pc) then pcall(function() if slua_GameFrontendHUD then pc=slua_GameFrontendHUD:GetPlayerController() end end) end
        return ESPValid(pc) and pc or nil
    end

    _G.g_vipserver_ESPGetLocalCharacter = _G.g_vipserver_ESPGetLocalCharacter or function()
        local c=nil
        pcall(function() local GDP=_G.GameplayData or require("GameLua.GameCore.Data.GameplayData"); if GDP then
            if GDP.GetPlayerCharacter then c=GDP.GetPlayerCharacter() end
            if not ESPValid(c) and GDP.GetLocalCharacter then c=GDP.GetLocalCharacter() end
        end end)
        if not ESPValid(c) then local pc=_G.g_vipserver_ESPGetController(); if pc then pcall(function() if pc.GetPawn then c=pc:GetPawn() end end) end end
        return ESPValid(c) and c or nil
    end

    _G.g_vipserver_ESPGetPlayerKey = _G.g_vipserver_ESPGetPlayerKey or function(character)
        if not ESPValid(character) then return tostring(character) end
        local key=nil
        pcall(function() if character.GetPlayerKey then key=character:GetPlayerKey() end end)
        if key==nil then pcall(function() key=character.PlayerKey end) end
        if key==nil then pcall(function() local ps=character.PlayerState; if ps then key=ps.PlayerKey end end) end
        if key==nil or tostring(key)=="" or tostring(key)=="0" or tostring(key)=="-1" then return tostring(character) end
        return tostring(key).."_"..tostring(character)
    end

    _G.g_vipserver_ESPIsAlive = _G.g_vipserver_ESPIsAlive or function(c)
        if not ESPValid(c) then return false,"invalid" end
        local dead=false
        pcall(function() if c.bDead==true or c.bIsDead==true or c.bIsDeadFlag==true then dead=true end end)
        if dead then return false,"dead" end
        local hp=nil
        pcall(function() hp=c.Health or c.HP or c.CurrentHealth end)
        hp=tonumber(hp)
        if Finite(hp) then return hp>0,hp>0 and "alive" or "dead" end
        local alive=false
        pcall(function() if c.IsAlive then alive=c:IsAlive() end end)
        if alive==true then return true,"alive" end
        return false,"unknown"
    end

    _G.g_vipserver_ESPActorLocation = _G.g_vipserver_ESPActorLocation or function(c)
        local loc=nil
        if not ESPValid(c) then return nil end
        pcall(function()
            if c.K2_GetActorLocation then loc=c:K2_GetActorLocation()
            elseif Game and Game.GetActorLocation then loc=Game:GetActorLocation(c) end
        end)
        return loc
    end

    _G.g_vipserver_ESPIsBot = _G.g_vipserver_ESPIsBot or function(c, key, cache, now)
        if not ESPValid(c) then return false end
        key = key or _G.g_vipserver_ESPGetPlayerKey(c)
        cache = cache or (_G.g_vipserver_ShotESP and _G.g_vipserver_ShotESP._BotCache) or {}
        now = now or LF.Now()
        local entry = cache[key]
        if entry and now>=entry.Clock and now-entry.Clock<2.0 then return entry.Value end
        local result = nil
        local function take(v) if result==nil and (v==true or v==false or v==1 or v==0) then result=(v==true or v==1) end end
        pcall(function() if Game and Game.IsAI then take(Game:IsAI(c)) end end)
        if result==nil then pcall(function() take(c.bIsAI) end) end
        if result==nil then pcall(function() if c.IsBot then take(c:IsBot()) end end) end
        if result==nil then
            pcall(function()
                local ps=c.PlayerState or (c.GetPlayerState and c:GetPlayerState())
                if ps then
                    take(ps.bIsABot); take(ps.bIsBot); take(ps.bIsAI)
                    if result==nil and ps.IsBot then take(ps:IsBot()) end
                end
            end)
        end
        cache[key] = result ~= nil and {Value=result, Clock=now} or nil
        return result == true
    end

    _G.g_vipserver_ESPViewport = _G.g_vipserver_ESPViewport or function(pc)
        local w,h=nil,nil
        local function take(x,y) x,y=tonumber(x),tonumber(y); if Finite(x) and Finite(y) and x>200 and y>200 and x<1e6 and y<1e6 then w,h=x,y; return true end end
        pcall(function() if WLL and WLL.GetViewportSize then local v=WLL.GetViewportSize(pc); if v then take(v.X,v.Y) end end end)
        if not w and pc then pcall(function() local x,y=pc:GetViewportSize(); take(x,y) end) end
        if not w and pc then pcall(function() local v=_G.g_vipserver_ESPV2(0,0); pc:GetViewportSize(v); take(v.X,v.Y) end) end
        return w or 2400.0, h or 1080.0
    end

    _G.g_vipserver_ESPGetCanvas = _G.g_vipserver_ESPGetCanvas or function()
        local state=_G.g_vipserver_ShotESP
        if ESPValid(state.Canvas) then return state.Canvas end
        local root=nil
        pcall(function()
            local ui=require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            if ui and ui.GetMainControlBaseUI then root=ui.GetMainControlBaseUI() end
        end)
        if not ESPValid(root) then return nil end
        state.RootUI = root
        local canvas=nil
        pcall(function()
            if ESPValid(root.CanvasPanel_0) then canvas=root.CanvasPanel_0
            elseif ESPValid(root.CanvasPanel_42) then canvas=root.CanvasPanel_42 end
        end)
        if ESPValid(canvas) then state.Canvas=canvas; return canvas end
        return nil
    end

    _G.g_vipserver_ESPGetCanvasLocalSize = _G.g_vipserver_ESPGetCanvasLocalSize or function()
        local canvas=_G.g_vipserver_ESPGetCanvas()
        if not ESPValid(canvas) then return nil,nil end
        local cw,ch=nil,nil
        pcall(function()
            local geo=canvas:GetCachedGeometry()
            if not geo then return end
            local size=nil
            if geo.GetLocalSize then size=geo:GetLocalSize()
            elseif SBL and SBL.GetLocalSize then size=SBL.GetLocalSize(geo) end
            if size and Finite(size.X) and Finite(size.Y) and size.X>100 and size.Y>100 then cw,ch=tonumber(size.X),tonumber(size.Y) end
        end)
        return cw,ch
    end

    _G.g_vipserver_ESPUpdateCanvasTransform = _G.g_vipserver_ESPUpdateCanvasTransform or function(pc)
        local state=_G.g_vipserver_ShotESP
        local canvas=_G.g_vipserver_ESPGetCanvas()
        if not ESPValid(canvas) then return false end
        local calibrated=false
        pcall(function()
            if SBL and SBL.AbsoluteToLocal then
                local geo=canvas:GetCachedGeometry()
                if geo then
                    local p0=SBL.AbsoluteToLocal(geo,_G.g_vipserver_ESPV2(0,0))
                    local p1=SBL.AbsoluteToLocal(geo,_G.g_vipserver_ESPV2(100,100))
                    if p0 and p1 and Finite(p0.X) and Finite(p0.Y) and Finite(p1.X) and Finite(p1.Y)
                        and math.abs(p0.X)<1e7 and math.abs(p0.Y)<1e7 and p1.X>p0.X and p1.Y>p0.Y
                        and p1.X-p0.X<10000 and p1.Y-p0.Y<10000 then
                        state.CanvasScaleX=(p1.X-p0.X)/100
                        state.CanvasScaleY=(p1.Y-p0.Y)/100
                        state.CanvasOffsetX=p0.X
                        state.CanvasOffsetY=p0.Y
                        calibrated=true
                    end
                end
            end
        end)
        if not calibrated then
            local scale=1.0
            pcall(function() if WLL and WLL.GetViewportScale then local s=WLL.GetViewportScale(pc); if Finite(s) and s>=0.01 and s<=100 then scale=s end end end)
            state.CanvasScaleX=1.0/scale; state.CanvasScaleY=1.0/scale
            state.CanvasOffsetX=0.0; state.CanvasOffsetY=0.0
        end
        return true
    end

    _G.g_vipserver_ESPSetFont = _G.g_vipserver_ESPSetFont or function(textWidget, size, _)
        if not ESPValid(textWidget) then return end
        pcall(function()
            local f = textWidget.Font
            if f then
                pcall(function() f.Size = size end)
                pcall(function() textWidget:SetFont(f) end)
                pcall(function() textWidget.Font = f end)
            end
            if textWidget.SetShadowOffset then pcall(function() textWidget:SetShadowOffset(_G.g_vipserver_ESPV2(0,0)) end) end
        end)
    end

    _G.g_vipserver_ESPSetTextColor = _G.g_vipserver_ESPSetTextColor or function(textWidget, color)
        if not ESPValid(textWidget) or not color then return end
        local applied=false
        pcall(function()
            local sc=textWidget.ColorAndOpacity or (SLC and SLC())
            if sc then
                sc.SpecifiedColor=color
                pcall(function() sc.ColorUseRule=0 end)
                textWidget:SetColorAndOpacity(sc)
                pcall(function() textWidget.ColorAndOpacity=sc end)
                applied=true
            end
        end)
        if not applied then pcall(function() textWidget:SetColorAndOpacity(color) end) end
        pcall(function() if textWidget.SetOpacity then textWidget:SetOpacity(1.0) end end)
        pcall(function() if textWidget.SetRenderOpacity then textWidget:SetRenderOpacity(1.0) end end)
    end

    _G.g_vipserver_ESPDrawLine = _G.g_vipserver_ESPDrawLine or function(data, x1, y1, x2, y2, thickness)
        if not data or not data.Widget or not data.Slot then return false end
        local dx,dy=x2-x1,y2-y1
        local len=math.sqrt(dx*dx+dy*dy)
        if len<1 then
            if data.Visible~=false then
                pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                data.Visible=false
            end
            return false
        end
        local angle=((math.atan2 and math.atan2(dy,dx)) or math.atan(dy,dx))*180.0/math.pi
        local unchanged=data.Visible==true and data.X1 and
            math.abs(data.X1-x1)<0.25 and math.abs(data.Y1-y1)<0.25 and
            math.abs(data.X2-x2)<0.25 and math.abs(data.Y2-y2)<0.25 and
            math.abs((data.Thickness or 0)-thickness)<0.05
        if unchanged then return true end
        local ok=pcall(function()
            data.Slot:SetPosition(_G.g_vipserver_ESPV2(x1,y1-thickness*0.5))
            data.Slot:SetSize(_G.g_vipserver_ESPV2(len,thickness))
            data.Widget:SetRenderAngle(angle)
            if not data.Visible then data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
        end)
        if not ok then data.Broken=true return false end
        data.Broken=false
        data.X1,data.Y1,data.X2,data.Y2,data.Thickness=x1,y1,x2,y2,thickness
        data.Visible=true
        return true
    end

    _G.g_vipserver_ESPHide = _G.g_vipserver_ESPHide or function(data)
        if data and data.Visible~=false and data.Widget then
            local ok=pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            if not ok then data.Broken=true end
            data.Visible=false
        end
    end

    _G.g_vipserver_ESPDestroyWidgetData = _G.g_vipserver_ESPDestroyWidgetData or function(data)
        if not data then return end
        if _G.ESPWidgetPool and _G.ESPWidgetPool.Release and _G.ESPWidgetPool.Release(data) then return end
        for _,f in ipairs({"Widget","Container","Text","DistanceText"}) do
            local w=data[f]
            if ESPValid(w) then pcall(function() w:RemoveFromParent() end) end
        end
    end

    _G.g_vipserver_ESPGetCharacterVerticalBounds = _G.g_vipserver_ESPGetCharacterVerticalBounds or function(character,cachedLocation)
        if not ESPValid(character) then return nil,nil end
        local center,halfHeight=nil,nil
        local capsule=nil
        pcall(function()
            if character.GetCapsuleComponent then capsule=character:GetCapsuleComponent()
            elseif character.CapsuleComponent then capsule=character.CapsuleComponent end
        end)
        if capsule and ESPValid(capsule) then
            pcall(function()
                if capsule.K2_GetComponentLocation then center=capsule:K2_GetComponentLocation()
                elseif capsule.GetComponentLocation then center=capsule:GetComponentLocation() end
                if capsule.GetScaledCapsuleHalfHeight then halfHeight=capsule:GetScaledCapsuleHalfHeight()
                elseif capsule.GetUnscaledCapsuleHalfHeight then halfHeight=capsule:GetUnscaledCapsuleHalfHeight()
                elseif capsule.CapsuleHalfHeight then halfHeight=capsule.CapsuleHalfHeight end
            end)
        end
        local cx,cy,cz=ESPShared.VectorValues(center)
        if center and not cx then center=nil end
        if not center then center=cachedLocation end
        if not center then pcall(function() if character.K2_GetActorLocation then center=character:K2_GetActorLocation() end end) end
        if not center then pcall(function() if Game and Game.GetActorLocation then center=Game:GetActorLocation(character) end end) end
        if not cx then cx,cy,cz=ESPShared.VectorValues(center) end
        if not cx then return nil,nil end
        halfHeight=tonumber(halfHeight)
        if not Finite(halfHeight) or halfHeight<10 or halfHeight>200 then
            halfHeight=85
            pcall(function()
                if character.bIsCrouched then halfHeight=60 end
                if character.IsProne and character:IsProne() then halfHeight=25 end
            end)
        end
        return center,halfHeight,cx,cy,cz
    end

    _G.g_vipserver_ESPActorOnScreen = _G.g_vipserver_ESPActorOnScreen or function(head,feet,minX,minY,maxX,maxY)
        local function usable(p) return p and Finite(p.X) and Finite(p.Y) end
        head=usable(head) and head or nil;feet=usable(feet) and feet or nil
        if not head and not feet then return false end
        head=head or feet;feet=feet or head
        return math.max(head.X,feet.X)>=minX and math.min(head.X,feet.X)<=maxX
            and math.max(head.Y,feet.Y)>=minY and math.min(head.Y,feet.Y)<=maxY
    end

    _G.g_vipserver_ESPFilterEnemies = _G.g_vipserver_ESPFilterEnemies or function(list, myLocation, maxRange, alive)
        for key in pairs(alive) do alive[key]=nil end
        local count,kept,realCount,botCount=#list,0,0,0
        maxRange=tonumber(maxRange) or 450.0
        if maxRange~=maxRange or maxRange<=0 or maxRange==math.huge then maxRange=450.0 end
        for i=1,count do
            local item=list[i]
            local character=item and item.Character
            local snapshot=item and item.Key and ESPShared.GetFrameRecord(character)
            if snapshot and snapshot.Alive and ESPShared.Events.Counted(character) then
                local distance=ESPShared.DistanceMetersFrom(snapshot,myLocation)
                if distance<=maxRange then
                    item.Distance=distance
                    kept=kept+1;list[kept]=item;alive[item.Key]=true
                    if item.IsBot then botCount=botCount+1 else realCount=realCount+1 end
                end
            end
        end
        for i=kept+1,count do list[i]=nil end
        return realCount,botCount
    end

    -- ───── PART E: ESPWidgetPool ─────
    do
        local ESPWidgetPool = _G.ESPWidgetPool or {V1={}, V2={}}
        local shapes = {
            Line = {Fields={"Widget","Slot","PosVec","SizeVec","VectorReuseDisabled"}, Check={"Widget","Slot"}, Limit=256},
            NameV1 = {Fields={"Widget","BottomLine","HealthBg","HealthFill","Text","DistanceText","LineSlot","HealthBgSlot","HealthFillSlot","TextSlot","DistanceSlot","Slot"},
                Check={"Widget","BottomLine","HealthBg","HealthFill","Text","DistanceText","LineSlot","HealthBgSlot","HealthFillSlot","TextSlot","DistanceSlot","Slot"}, Limit=16},
        }
        local function remove(widget) if widget then pcall(function() widget:RemoveFromParent() end) end end
        function ESPWidgetPool.New(cap) return {Bins={},Canvas=nil,Enabled=true,Weight=0,Capacity=cap,Reused=0,Released=0,Created=0,Discarded=0} end
        if not ESPWidgetPool.V1 or not ESPWidgetPool.V1.Bins then ESPWidgetPool.V1 = ESPWidgetPool.New(128) end
        if not ESPWidgetPool.V2 or not ESPWidgetPool.V2.Bins then ESPWidgetPool.V2 = ESPWidgetPool.New(1024) end
        function ESPWidgetPool.Flush(pool)
            for kind,bin in pairs(pool.Bins) do
                for i=#bin,1,-1 do local item=bin[i];bin[i]=nil;remove(item.Widget);for k in pairs(item) do item[k]=nil end end
                pool.Bins[kind]=nil
            end
            pool.Canvas=nil;pool.Weight=0
        end
        function ESPWidgetPool.Tag(pool,kind,canvas,data)
            if pool.Canvas~=canvas then ESPWidgetPool.Flush(pool);pool.Canvas=canvas end
            data.PoolOwner=pool;data.PoolKind=kind;data.PoolCanvas=canvas
            pool.Created=pool.Created+1
            return data
        end
        function ESPWidgetPool.Release(data)
            if data.PoolReleased then return true end
            local pool,kind,canvas=data.PoolOwner,data.PoolKind,data.PoolCanvas
            if not pool or not pool.Enabled or pool.Canvas~=canvas or data.Broken or not ESPValid(data.Widget) then return false end
            local shape=shapes[kind]
            if not shape then return false end
            local bin=pool.Bins[kind]
            if not bin then bin={};pool.Bins[kind]=bin end
            if #bin>=shape.Limit or pool.Weight+1>pool.Capacity then return false end
            local ok=pcall(function()
                data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if data.Text then data.Text:SetText("") end
                if data.DistanceText then data.DistanceText:SetText("") end
            end)
            if not ok then return false end
            local item={Weight=1}
            for _,field in ipairs(shape.Fields) do item[field]=data[field] end
            for field in pairs(data) do data[field]=nil end
            data.PoolReleased=true
            bin[#bin+1]=item;pool.Weight=pool.Weight+1;pool.Released=pool.Released+1
            return true
        end
        function ESPWidgetPool.Take(pool,kind,canvas)
            if pool.Canvas~=canvas then ESPWidgetPool.Flush(pool);pool.Canvas=canvas end
            if not pool.Enabled then return nil end
            local shape,bin=shapes[kind],pool.Bins[kind]
            if not shape or not bin then return nil end
            while #bin>0 do
                local item=bin[#bin];bin[#bin]=nil;pool.Weight=pool.Weight-item.Weight
                local valid=true
                for _,field in ipairs(shape.Check) do
                    if not ESPValid(item[field]) then valid=false;break end
                end
                if valid then
                    local ok,parent=pcall(function() return item.Widget:GetParent() end)
                    valid=ok and parent==canvas
                end
                if valid then
                    local data={PoolOwner=pool,PoolKind=kind,PoolCanvas=canvas}
                    for _,field in ipairs(shape.Fields) do data[field]=item[field] end
                    pool.Reused=pool.Reused+1
                    return data
                end
                remove(item.Widget);pool.Discarded=pool.Discarded+1
                for key in pairs(item) do item[key]=nil end
            end
            return nil
        end
        _G.ESPWidgetPool = ESPWidgetPool
    end

    -- ───── PART F: V1 BODY (Botmater ESP) ─────
_G.g_Botmater_ESPOptions = _G.g_Botmater_ESPOptions or {
    Name = false,
    Line = false,
    Health = false,
    Distance = false,
    EnemyCounter = false,
}

_G.g_Botmater_VIPShotESP = _G.g_Botmater_VIPShotESP or {
    Enabled = false,
    MaxRangeMeters = 300.0,
    ScanInterval = 0.05,
    UpdateInterval = 1/60,
    TransformInterval = 0.033,
    MaxRendered = 10,
    TracerThickness = 1.0,
    NameGap = 2.0,
    NameFontSize = 9,
    DistanceFontSize = 10,
    DistanceBelowFeet = 14,
}

local g_Botmater_ShotESP = {
    Canvas = nil,
    Enemies = {},
    Lines = {},
    Names = {},
    LastScanClock = -999.0,
    LastTransformClock = -999.0,
    LastWorld = nil,
    CanvasScaleX = 1.0,
    CanvasScaleY = 1.0,
    CanvasOffsetX = 0.0,
    CanvasOffsetY = 0.0,
    LastPawn=nil,
    LastController=nil,
    Active={},
    Alive={},
    LastProjected={},
    RealCount = 0,
    BotCount = 0,
}

local V2 = _G.FVector2D
if not V2 then pcall(function() V2 = import("Vector2D") end) end
local LinearColor = _G.FLinearColor
if not LinearColor then pcall(function() LinearColor = import("LinearColor") end) end
local SlateBlueprintLibrary = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
local WidgetLayoutLibrary = nil
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)

local function g_Botmater_ESPV2(x, y)
    if V2 then return V2(x, y) end
    return {X = x, Y = y}
end

local function g_Botmater_ESPColor(r, g, b, a)
    if LinearColor then return LinearColor(r, g, b, a or 1.0) end
    return {R=r, G=g, B=b, A=a or 1.0}
end

local COLOR_REAL_VIS_RED          = g_Botmater_ESPColor(1.00, 0.00, 0.00, 1.00)
local COLOR_BOT_VIS_CYAN          = g_Botmater_ESPColor(1.00, 1.00, 1.00, 1.00) -- Giữ nguyên Trắng

local COLOR_TEXT_WHITE            = g_Botmater_ESPColor(1.00, 1.00, 1.00, 1.00)
local COLOR_TEXT_BLACK            = g_Botmater_ESPColor(0.00, 0.00, 0.00, 1.00)

-- BẢNG ĐẾM ĐỊCH TRÊN CÙNG (ENEMY COUNTER)
local CACHE_COUNTER_PLAYER_BG   = g_Botmater_ESPColor(1.0, 0.0, 0.0, 1.0)     -- Nền REAL: Đỏ full (R=1, G=0, B=0)
local CACHE_COUNTER_BOT_BG      = g_Botmater_ESPColor(1.0, 1.0, 1.0, 1.0)     -- Nền BOT: Trắng đặc 100% (Giữ nguyên)
local CACHE_COUNTER_PLAYER_TEXT = g_Botmater_ESPColor(0.0, 0.0, 0.0, 1.0)     -- Chữ REAL: Đen
local CACHE_COUNTER_BOT_TEXT    = g_Botmater_ESPColor(0.0, 0.0, 0.0, 1.0)     -- Chữ BOT: Đen

-- MÀU CHO CÁC THÀNH PHẦN NGOÀI MÀN HÌNH (Thanh máu, chữ trên đầu bot)
local COLOR_HP = {
    RealText=g_Botmater_ESPColor(1.0,0.86,0.84,1.0),
    BotText=g_Botmater_ESPColor(1.0,1.0,1.0,1.0),   -- Đã trả về màu TRẮNG để chữ BOT ngoài màn hình không bị đen
    RealMid=g_Botmater_ESPColor(0.78,0.0,0.0,1.0),
    RealLow=g_Botmater_ESPColor(0.55,0.0,0.0,1.0),
    BotMid=g_Botmater_ESPColor(0.075,0.75,0.75,1.0),
    BotLow=g_Botmater_ESPColor(0.055,0.55,0.55,1.0),
    RealBG=g_Botmater_ESPColor(0.06,0.005,0.005,0.75),
    BotBG=g_Botmater_ESPColor(0.005,0.06,0.06,0.75)
}

_G.g_Botmater_VIPShotESP.NameFontSize=math.max(12,tonumber(_G.g_Botmater_VIPShotESP.NameFontSize) or 12)
_G.g_Botmater_VIPShotESP.DistanceFontSize=math.max(12,tonumber(_G.g_Botmater_VIPShotESP.DistanceFontSize) or 12)

local function g_Botmater_ESPGetColors(isBot)
    if isBot then
        return COLOR_BOT_VIS_CYAN, COLOR_HP.BotText
    else
        return COLOR_REAL_VIS_RED, COLOR_HP.RealText
    end
end

local function g_Botmater_ESPValid(obj)
    if not obj then return false end
    local ok, valid = pcall(function() return slua.isValid(obj) end)
    return ok and valid == true
end

local function g_Botmater_ESPNow() return _G.LunarFeatures.Now() end

local function g_Botmater_ESPWorld()
    local w = nil
    pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
    return w
end

local function g_Botmater_ESPGetController() return _G.g_vipserver_ESPGetController() end
local function g_Botmater_ESPGetLocalCharacter() return _G.g_vipserver_ESPGetLocalCharacter() end

local function g_Botmater_ESPGetPlayerState(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local ps = nil
    pcall(function()
        if character.GetPlayerStateSafety then ps = character:GetPlayerStateSafety() end
    end)
    if not g_Botmater_ESPValid(ps) then
        pcall(function() if character.GetPlayerState then ps = character:GetPlayerState() end end)
    end
    if not g_Botmater_ESPValid(ps) then
        pcall(function() ps = character.PlayerState end)
    end
    return g_Botmater_ESPValid(ps) and ps or nil
end

local function g_Botmater_ESPNormalizeName(value)
    if value == nil or value == false then return nil end
    local ok, text = pcall(tostring, value)
    if not ok or not text then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or text == "nil" or text == "None" or text == "NULL" then return nil end
    return text
end

local function g_Botmater_ESPResolvePlayerName(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local name = nil
    local function take(value)
        if not name then name = g_Botmater_ESPNormalizeName(value) end
    end
    pcall(function() if character.GetPlayerNameSafety then take(character:GetPlayerNameSafety()) end end)
    pcall(function() if not name and character.GetPlayerName then take(character:GetPlayerName()) end end)
    pcall(function() if not name then take(character.PlayerName) end end)
    pcall(function() if not name then take(character.NickName) end end)
    if not name then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() if ps.GetPlayerName then take(ps:GetPlayerName()) end end)
            pcall(function() if not name then take(ps.PlayerName) end end)
            pcall(function() if not name then take(ps.PlayerNamePrivate) end end)
            pcall(function() if not name then take(ps.NickName) end end)
        end
    end
    return name
end

local function g_Botmater_ESPGetPlayerKey(c) return _G.g_vipserver_ESPGetPlayerKey(c) end

local function g_Botmater_ESPGetTeamID(character)
    if not g_Botmater_ESPValid(character) then return nil end
    local id = nil
    pcall(function() if character.GetTeamID then id = character:GetTeamID() end end)
    if id == nil then pcall(function() id = character.TeamID end) end
    if id == nil then
        local ps = g_Botmater_ESPGetPlayerState(character)
        if ps then
            pcall(function() if ps.GetTeamID then id = ps:GetTeamID() end end)
            if id == nil then pcall(function() id = ps.TeamID end) end
        end
    end
    return id
end

local function g_Botmater_ESPGetHealthPct(character)
    if not g_Botmater_ESPValid(character) then return 1.0 end
    local hp, maxHp = nil, nil
    pcall(function() hp = character.Health end)
    if type(hp) ~= "number" then pcall(function() hp = character.HP end) end
    pcall(function() maxHp = character.MaxHealth end)
    if type(maxHp) ~= "number" then pcall(function() maxHp = character.MaxHP end) end
    if not ESPShared.Finite(hp) then return 1.0 end
    if not ESPShared.Finite(maxHp) or maxHp <= 0 then maxHp = 100 end
    local pct = hp / maxHp
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct
end

local function g_Botmater_ESPGetHealthColor(pct,isBot)
    pct = tonumber(pct) or 1.0
    if pct >= 0.75 then return isBot and COLOR_BOT_VIS_CYAN or COLOR_REAL_VIS_RED
    elseif pct >= 0.50 then return isBot and COLOR_HP.BotMid or COLOR_HP.RealMid
    else return isBot and COLOR_HP.BotLow or COLOR_HP.RealLow end
end

local function g_Botmater_ESPIsBot(c)
    g_Botmater_ShotESP._BotCache=g_Botmater_ShotESP._BotCache or {}
    return _G.g_vipserver_ESPIsBot(c,_G.g_vipserver_ESPGetPlayerKey(c),g_Botmater_ShotESP._BotCache,_G.LunarFeatures.Now())
end

local V1Cleanup={Items={},Members={},Count=0,Cursor=1,Due=0,Limit=512,AdmissionLimit=128}
function V1Cleanup.Try(widget)
    if not g_Botmater_ESPValid(widget) then return true end
    local hidden,accepted=pcall(function() return widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
    if not hidden or accepted==false then pcall(function() widget:SetRenderOpacity(0) end) end
    local ok,result=pcall(function() return widget:RemoveFromParent() end)
    if not ok or result==false then return false end
    local checked,parent=pcall(function() return widget:GetParent() end)
    return not checked or parent==nil
end
function V1Cleanup.Retire(widget)
    if not widget then return true end
    if V1Cleanup.Members[widget] then return true end
    if V1Cleanup.Try(widget) then return true end
    if V1Cleanup.Count>=V1Cleanup.Limit then return false end
    V1Cleanup.Count=V1Cleanup.Count+1
    V1Cleanup.Items[V1Cleanup.Count]=widget
    V1Cleanup.Members[widget]=true
    return true
end
function V1Cleanup.Pump(now)
    if V1Cleanup.Count==0 then return end
    if now>=V1Cleanup.Due-0.05 and now<V1Cleanup.Due then return end
    V1Cleanup.Due=now+0.05
    local budget=math.min(8,V1Cleanup.Count)
    while budget>0 and V1Cleanup.Count>0 do
        budget=budget-1
        local i=V1Cleanup.Cursor
        if i>V1Cleanup.Count then i=1 end
        local widget=V1Cleanup.Items[i]
        if V1Cleanup.Try(widget) then
            V1Cleanup.Members[widget]=nil
            V1Cleanup.Items[i]=V1Cleanup.Items[V1Cleanup.Count]
            V1Cleanup.Items[V1Cleanup.Count]=nil
            V1Cleanup.Count=V1Cleanup.Count-1
            V1Cleanup.Cursor=i
        else
            V1Cleanup.Cursor=i+1
        end
    end
end
ESPWidgetPool.V1.Remove=V1Cleanup.Retire

local function g_Botmater_ESPDestroyWidgetData(data)
    if not data then return true end
    if ESPWidgetPool.Release(data) then return true end
    return V1Cleanup.Retire(data.Widget or data.Container)
end

local function g_Botmater_ESPResetWidgets()
    ESPShared.Frame.V1CanvasChecked=false
    ESPWidgetPool.V1.Enabled=false
    for _,registry in ipairs({g_Botmater_ShotESP.Lines,g_Botmater_ShotESP.Names}) do
        for key,data in pairs(registry) do
            if g_Botmater_ESPDestroyWidgetData(data) then registry[key]=nil end
        end
    end
    g_Botmater_ShotESP.Canvas=nil
    g_Botmater_ShotESP.RootUI=nil
    g_Botmater_ShotESP.Enemies={}
    g_Botmater_ShotESP._BotCache={}
    g_Botmater_ShotESP.Active={}
    g_Botmater_ShotESP.Alive={}
    g_Botmater_ShotESP.LastProjected={}
    g_Botmater_ShotESP.RealCount=0;g_Botmater_ShotESP.BotCount=0
    g_Botmater_ShotESP.LastScanClock=-999
    g_Botmater_ShotESP.LastTransformClock=-999
    g_Botmater_ShotESP.LastPawn=nil;g_Botmater_ShotESP.LastController=nil
    g_Botmater_ShotESP.CanvasScaleX=1;g_Botmater_ShotESP.CanvasScaleY=1
    g_Botmater_ShotESP.CanvasOffsetX=0;g_Botmater_ShotESP.CanvasOffsetY=0
    g_Botmater_ShotESP.TransformReady=false
    g_Botmater_ShotESP.TransformW=nil;g_Botmater_ShotESP.TransformH=nil
    ESPWidgetPool.Flush(ESPWidgetPool.V1)
    ESPWidgetPool.V1.Enabled=true
end

local function g_Botmater_ESPGetCanvas()
    local frame=ESPShared.Frame
    if frame.Active and frame.V1CanvasChecked then
        return g_Botmater_ESPValid(g_Botmater_ShotESP.Canvas) and g_Botmater_ShotESP.Canvas or nil
    end
    local root
    pcall(function()
        local ui=require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        if ui and ui.GetMainControlBaseUI then root=ui.GetMainControlBaseUI() end
    end)
    if not g_Botmater_ESPValid(root) then
        if g_Botmater_ShotESP.Canvas then g_Botmater_ESPResetWidgets() end
        return nil
    end
    local canvas
    pcall(function()
        if g_Botmater_ESPValid(root.CanvasPanel_0) then canvas=root.CanvasPanel_0
        elseif g_Botmater_ESPValid(root.CanvasPanel_42) then canvas=root.CanvasPanel_42 end
    end)
    if not g_Botmater_ESPValid(canvas) then
        if g_Botmater_ShotESP.Canvas then g_Botmater_ESPResetWidgets() end
        return nil
    end
    if g_Botmater_ShotESP.Canvas~=canvas or g_Botmater_ShotESP.RootUI~=root then
        g_Botmater_ESPResetWidgets()
        g_Botmater_ShotESP.Canvas=canvas;g_Botmater_ShotESP.RootUI=root
    end
    if frame.Active then frame.V1CanvasChecked=true end
    return canvas
end

local function g_Botmater_ESPViewport(pc) return _G.g_vipserver_ESPViewport(pc) end

local function g_Botmater_ESPGetCanvasLocalSize()
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil, nil end
    local cw, ch = nil, nil
    pcall(function()
        local geo = canvas:GetCachedGeometry()
        if not geo then return end
        local size = nil
        if geo.GetLocalSize then size = geo:GetLocalSize()
        elseif SlateBlueprintLibrary and SlateBlueprintLibrary.GetLocalSize then size = SlateBlueprintLibrary.GetLocalSize(geo) end
        if size and ESPShared.Finite(size.X) and ESPShared.Finite(size.Y) and size.X > 1 and size.Y > 1 then
            cw, ch = tonumber(size.X), tonumber(size.Y)
        end
    end)
    return cw, ch
end

local function g_Botmater_ESPUpdateCanvasTransform(pc)
    local state=g_Botmater_ShotESP
    local canvas=g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return false end
    local width,height=ESPShared.ViewSize(pc)
    local sameViewport=state.TransformW==width and state.TransformH==height
    local calibrated=false
    pcall(function()
        local geo=canvas:GetCachedGeometry()
        if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal and geo then
            local p0=SlateBlueprintLibrary.AbsoluteToLocal(geo,g_Botmater_ESPV2(0,0))
            local p1=SlateBlueprintLibrary.AbsoluteToLocal(geo,g_Botmater_ESPV2(100,100))
            if p0 and p1 and ESPShared.Finite(p0.X) and ESPShared.Finite(p0.Y)
                and ESPShared.Finite(p1.X) and ESPShared.Finite(p1.Y)
                and math.abs(p0.X)<1e7 and math.abs(p0.Y)<1e7
                and p1.X>p0.X and p1.Y>p0.Y
                and p1.X-p0.X<10000 and p1.Y-p0.Y<10000 then
                state.CanvasScaleX=(p1.X-p0.X)/100
                state.CanvasScaleY=(p1.Y-p0.Y)/100
                state.CanvasOffsetX=p0.X;state.CanvasOffsetY=p0.Y
                calibrated=true
            end
        end
    end)
    if not calibrated and state.TransformReady and sameViewport then return true end
    if not calibrated then
        local scale=1
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
                local s=WidgetLayoutLibrary.GetViewportScale(pc)
                if ESPShared.Finite(s) and s>=0.01 and s<=100 then scale=s end
            end
        end)
        state.CanvasScaleX=1/scale;state.CanvasScaleY=1/scale
        state.CanvasOffsetX=0;state.CanvasOffsetY=0
    end
    state.TransformReady=true;state.TransformW=width;state.TransformH=height
    return true
end

local function g_Botmater_ESPSetFont(widget,size) _G.g_vipserver_ESPSetFont(widget,size,0) end
local function g_Botmater_ESPSetTextColor(widget,color) _G.g_vipserver_ESPSetTextColor(widget,color) end

local function g_Botmater_ESPCreateLine(color)
    if V1Cleanup.Count>=V1Cleanup.AdmissionLimit then return nil end
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil end
    local pooled=true and ESPWidgetPool.Take(ESPWidgetPool.V1,"Line",canvas)
    if pooled then
        local ok=pcall(function() pooled.Widget:SetBrushColor(color) end)
        if ok then pooled.Visible=false;return pooled end
        V1Cleanup.Retire(pooled.Widget)
    end
    local border = nil
    pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
    if not g_Botmater_ESPValid(border) then return nil end
    pcall(function()
        border:SetBrushColor(color)
        border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        border:SetRenderTransformPivot(g_Botmater_ESPV2(0.0, 0.5))
    end)
    local slot = nil
    pcall(function() slot = canvas:AddChildToCanvas(border) end)
    if not slot then g_Botmater_ESPDestroyWidgetData({Widget=border}) return nil end
    pcall(function() slot:SetAutoSize(false) slot:SetZOrder(30) end)
    local data={Widget=border, Slot=slot, Visible=true}
    if true then ESPWidgetPool.Tag(ESPWidgetPool.V1,"Line",canvas,data) end
    return data
end

local function g_Botmater_ESPDrawLine(...) return _G.g_vipserver_ESPDrawLine(...) end

local function g_Botmater_ESPHide(data)
    if data and g_Botmater_ESPValid(data.Widget) then
        if data.Visible ~= false then
            pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            data.Visible = false
        end
    end
end

local function g_Botmater_ESPCreateNameTag(isBot)
    if V1Cleanup.Count>=V1Cleanup.AdmissionLimit then return nil end
    local canvas = g_Botmater_ESPGetCanvas()
    if not g_Botmater_ESPValid(canvas) then return nil end
    local pooled=ESPWidgetPool.Take(ESPWidgetPool.V1,"NameV1",canvas)
    if pooled then
        local mainColor,textColor=g_Botmater_ESPGetColors(isBot)
        local ok=pcall(function()
            pooled.BottomLine:SetBrushColor(mainColor)
            pooled.BottomLine:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            pooled.HealthBg:SetBrushColor(isBot and COLOR_HP.BotBG or COLOR_HP.RealBG)
            pooled.HealthFill:SetBrushColor(mainColor)
        end)
        if not ok then V1Cleanup.Retire(pooled.Widget);pooled=nil end
        if pooled then
            g_Botmater_ESPSetTextColor(pooled.Text,textColor)
            g_Botmater_ESPSetTextColor(pooled.DistanceText,textColor)
            g_Botmater_ESPSetFont(pooled.Text,tonumber(_G.g_Botmater_VIPShotESP.NameFontSize) or 9)
            g_Botmater_ESPSetFont(pooled.DistanceText,tonumber(_G.g_Botmater_VIPShotESP.DistanceFontSize) or 10)
            pooled.IsBot=isBot;pooled.Visible=false;pooled.LastHealthPct=-1
        end
        if pooled then return pooled end
    end

    local container = nil
    pcall(function() container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
    if not g_Botmater_ESPValid(container) then return nil end

    local bottomLine = nil
    pcall(function() bottomLine = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)
    local nameText = nil
    pcall(function() nameText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)
    local distanceText = nil
    pcall(function() distanceText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", container) end)

    local healthBarBg = nil
    pcall(function() healthBarBg = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)
    local healthBarFill = nil
    pcall(function() healthBarFill = CGame:NewObjectFromPath("/Script/UMG.Border", container) end)

    if not g_Botmater_ESPValid(bottomLine)
        or not g_Botmater_ESPValid(nameText)
        or not g_Botmater_ESPValid(distanceText)
        or not g_Botmater_ESPValid(healthBarBg)
        or not g_Botmater_ESPValid(healthBarFill) then
        g_Botmater_ESPDestroyWidgetData({Widget=container})
        return nil
    end

    local mainColor,textColor=g_Botmater_ESPGetColors(isBot)
    local background=isBot and COLOR_HP.BotBG or COLOR_HP.RealBG

    pcall(function()
        bottomLine:SetBrushColor(mainColor)
        bottomLine:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        nameText:SetText("")
        distanceText:SetText("")
        nameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        distanceText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        if nameText.SetJustification then nameText:SetJustification(1) end
        if distanceText.SetJustification then distanceText:SetJustification(1) end
        healthBarBg:SetBrushColor(background)
        healthBarBg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        healthBarFill:SetBrushColor(mainColor)
        healthBarFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    g_Botmater_ESPSetTextColor(nameText, textColor)
    g_Botmater_ESPSetTextColor(distanceText, textColor)
    g_Botmater_ESPSetFont(nameText, tonumber(_G.g_Botmater_VIPShotESP.NameFontSize) or 9)
    g_Botmater_ESPSetFont(distanceText, tonumber(_G.g_Botmater_VIPShotESP.DistanceFontSize) or 10)

    local lineSlot, nameSlot, distanceSlot, mainSlot = nil, nil, nil, nil
    local healthBgSlot, healthFillSlot = nil, nil
    pcall(function() lineSlot = container:AddChildToCanvas(bottomLine) end)
    pcall(function() healthBgSlot = container:AddChildToCanvas(healthBarBg) end)
    pcall(function() healthFillSlot = container:AddChildToCanvas(healthBarFill) end)
    pcall(function() nameSlot = container:AddChildToCanvas(nameText) end)
    pcall(function() distanceSlot = container:AddChildToCanvas(distanceText) end)
    pcall(function() mainSlot = canvas:AddChildToCanvas(container) end)

    if not lineSlot or not nameSlot or not distanceSlot or not mainSlot or not healthBgSlot or not healthFillSlot then
        g_Botmater_ESPDestroyWidgetData({Widget=container})
        return nil
    end

    pcall(function()
        lineSlot:SetAutoSize(false) lineSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0)) lineSlot:SetZOrder(1)
        healthBgSlot:SetAutoSize(false) healthBgSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0)) healthBgSlot:SetZOrder(1)
        healthFillSlot:SetAutoSize(false) healthFillSlot:SetAlignment(g_Botmater_ESPV2(0.0, 0.0)) healthFillSlot:SetZOrder(2)
        nameSlot:SetAutoSize(true) nameSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5)) nameSlot:SetZOrder(3)
        distanceSlot:SetAutoSize(true) distanceSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5)) distanceSlot:SetZOrder(3)
        mainSlot:SetAutoSize(false) mainSlot:SetZOrder(35)
    end)

    local data={
        Widget       = container,
        BottomLine   = bottomLine,
        HealthBg     = healthBarBg,
        HealthFill   = healthBarFill,
        Text         = nameText,
        DistanceText = distanceText,
        LineSlot     = lineSlot,
        HealthBgSlot = healthBgSlot,
        HealthFillSlot = healthFillSlot,
        TextSlot     = nameSlot,
        DistanceSlot = distanceSlot,
        Slot         = mainSlot,
        IsBot        = isBot,
        Visible      = true,
        LastDistValue = nil,
        LastDistLabel = nil,
        LastHealthPct = -1,
    }
    return ESPWidgetPool.Tag(ESPWidgetPool.V1,"NameV1",canvas,data)
end

local function g_Botmater_ESPUpdateNameTag(key, character, headScreen, footScreen, isBot, distance, healthPct, pc)
    local showName     = _G.g_Botmater_ESPOptions.Name == true
    local showDistance = _G.g_Botmater_ESPOptions.Distance == true
    local showHealth = _G.g_Botmater_ESPOptions.Health == true

    local data = g_Botmater_ShotESP.Names[key]
    if not showName and not showDistance and not showHealth then
        if data and g_Botmater_ESPValid(data.Widget) then
            if data.Visible ~= false then
                pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                data.Visible = false
            end
        end
        return
    end

    if data and data.IsBot~=isBot then data.CachedName=nil end
    local name = nil
    if not showName then
        name=""
    elseif isBot then
        name = "BOT"
    else
        name = data and data.CachedName or nil
        if not name then
            name = g_Botmater_ESPResolvePlayerName(character)
            if data and name then data.CachedName = name end
        end
        if not name then name = showName and "UNKNOWN" or "" end
    end

    headScreen=headScreen or footScreen
    if not headScreen then
        if data and g_Botmater_ESPValid(data.Widget) then
            if data.Visible ~= false then
                pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                data.Visible = false
            end
        end
        return
    end

    if not data or not g_Botmater_ESPValid(data.Widget) then
        g_Botmater_ESPDestroyWidgetData(data)
        data = g_Botmater_ESPCreateNameTag(isBot)
        g_Botmater_ShotESP.Names[key] = data
        if data then data.CachedName = name end
    end
    if not data then return end

    if data.IsBot ~= isBot then
        local mainColor,textColor=g_Botmater_ESPGetColors(isBot)
        g_Botmater_ESPSetTextColor(data.Text,textColor)
        g_Botmater_ESPSetTextColor(data.DistanceText,textColor)
        local ok=pcall(function()
            data.BottomLine:SetBrushColor(mainColor)
            data.HealthBg:SetBrushColor(isBot and COLOR_HP.BotBG or COLOR_HP.RealBG)
        end)
        if ok then data.IsBot=isBot;data.LastHealthPct=nil end
    end

    local dist=math.floor(ESPShared.SafeNumber(distance,0,0,1e8)+0.5)
    local distanceLabel
    if data.LastDistValue ~= dist then
        distanceLabel = string.format("%d m", dist)
        data.LastDistValue = dist
        data.LastDistLabel = distanceLabel
    else
        distanceLabel = data.LastDistLabel or string.format("%d m", dist)
    end

    local hp=ESPShared.SafeNumber(healthPct,1.0,0.0,1.0)
    if hp < 0 then hp = 0 end
    if hp > 1 then hp = 1 end
    local healthChanged=data.LastHealthPct~=hp
    if healthChanged then
        local hpColor = g_Botmater_ESPGetHealthColor(hp,isBot)
        pcall(function()
            if data.HealthFill and g_Botmater_ESPValid(data.HealthFill) then
                data.HealthFill:SetBrushColor(hpColor)
            end
        end)
    end

    local bottomLineH = 4.32
    local baseFontSize=ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.NameFontSize,12,1,96)
    local baseBottomLineH = 3.6
    local fontSize = baseFontSize * (bottomLineH / baseBottomLineH)
    local paddingX    = 5.0
    local paddingY    = 2.0
    local nameHeight  = fontSize + paddingY * 2 + bottomLineH
    local gap=ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.NameGap,2,0,128)

    local nameChars = #name
    local textWidth = math.max(30.0, nameChars * (fontSize * 0.52))
    local boxWidth  = math.max(50.0, textWidth + paddingX * 2)
    local boxHeight = nameHeight

    local LINE_UP_SHIFT = boxHeight * 0.25

    local baseY = headScreen.Y - boxHeight - gap
    local containerY = baseY - LINE_UP_SHIFT

    local minX,minY,maxX,maxY=ESPShared.CanvasBounds(pc,g_Botmater_ShotESP)
    boxWidth=math.min(boxWidth,math.max(1,maxX-minX-4))
    local x=ESPShared.SafeNumber(headScreen.X-boxWidth*0.5,minX,minX,maxX-boxWidth)
    containerY=ESPShared.SafeNumber(containerY,minY,minY,math.max(minY,maxY-boxHeight))

    local anchor=footScreen or headScreen
    local df=ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.DistanceFontSize,12,1,96)
    local halfW=math.min(math.max(18,#distanceLabel*df*0.30),(maxX-minX)*0.49)
    local halfH=math.min(df*0.7+2,(maxY-minY)*0.49)
    local distAbsX=ESPShared.SafeNumber(anchor.X,headScreen.X,minX+halfW,maxX-halfW)
    local distAbsY=ESPShared.SafeNumber(anchor.Y+ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.DistanceBelowFeet,14,0,128),
        minY+halfH,minY+halfH,maxY-halfH)
    containerY=math.min(containerY,distAbsY-halfH)
    local distanceY=distAbsY-containerY
    local totalHeight=math.max(boxHeight,distanceY+halfH)

    local needsPosUpdate = true
    if data.LastBoxX and math.abs(x - data.LastBoxX) < 0.001
       and math.abs(containerY - data.LastBoxY) < 0.001
       and data.LastBoxW == boxWidth and data.LastDistanceY==distanceY then
        needsPosUpdate = false
    end

    local shownName     = showName and name or ""
    local shownDistance = showDistance and distanceLabel or ""

    pcall(function()
        if data.LastName ~= shownName then
            data.Text:SetText(shownName)
            data.LastName = shownName
        end
        if data.LastDistance ~= shownDistance then
            data.DistanceText:SetText(shownDistance)
            data.LastDistance = shownDistance
        end
    end)

    local lineWidth=boxWidth*0.68
    local lineOffsetX=(boxWidth-lineWidth)*0.5
    local healthWidth=lineWidth*hp
    if healthWidth<1 then healthWidth=0 end
    local geometryChanged=data.GeometryWidth~=boxWidth or data.GeometryHeight~=boxHeight
    if geometryChanged or healthChanged then
        local ok=pcall(function()
            if geometryChanged then
                data.HealthBgSlot:SetPosition(g_Botmater_ESPV2(lineOffsetX,boxHeight-bottomLineH))
                data.HealthBgSlot:SetSize(g_Botmater_ESPV2(lineWidth,bottomLineH))
                data.HealthFillSlot:SetPosition(g_Botmater_ESPV2(lineOffsetX,boxHeight-bottomLineH))
                data.TextSlot:SetPosition(g_Botmater_ESPV2(boxWidth*0.5,(boxHeight-bottomLineH)*0.5))
            end
            data.HealthFillSlot:SetSize(g_Botmater_ESPV2(healthWidth,bottomLineH))
        end)
        if ok then data.GeometryWidth=boxWidth;data.GeometryHeight=boxHeight;data.LastHealthPct=hp end
    end
    if needsPosUpdate then
        local ok=pcall(function() data.Slot:SetPosition(g_Botmater_ESPV2(x,containerY)) end)
        if ok then data.LastBoxX=x;data.LastBoxY=containerY;data.LastBoxW=boxWidth end
    end
    if data.LayoutW~=boxWidth or data.LayoutH~=totalHeight then
        local ok=pcall(function() data.Slot:SetSize(g_Botmater_ESPV2(boxWidth,totalHeight)) end)
        if ok then data.LayoutW=boxWidth;data.LayoutH=totalHeight end
    end
    local distX=distAbsX-x
    if data.LastDistanceX~=distX or data.LastDistanceY~=distanceY then
        local ok=pcall(function() data.DistanceSlot:SetPosition(g_Botmater_ESPV2(distX,distanceY)) end)
        if ok then data.LastDistanceX=distX;data.LastDistanceY=distanceY end
    end

    if data.LastHealthVis~=showHealth then
        local ok=pcall(function()
            local visibility=showHealth and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed
            data.HealthBg:SetWidgetVisibility(visibility)
            data.HealthFill:SetWidgetVisibility(visibility)
        end)
        if ok then data.LastHealthVis=showHealth end
    end
    if data.LastNameVis ~= showName then
        local ok=pcall(function() data.Text:SetWidgetVisibility(showName and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed) end)
        if ok then data.LastNameVis=showName end
    end
    if data.LastDistVis ~= showDistance then
        local ok=pcall(function() data.DistanceText:SetWidgetVisibility(showDistance and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed) end)
        if ok then data.LastDistVis=showDistance end
    end

    if data.Visible ~= true then
        local ok=pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        if ok then data.Visible=true end
    end

    data.FinalX = x
    data.FinalY = containerY
    data.FinalW = boxWidth
    data.FinalH = boxHeight
    data.LineEndX = x + boxWidth * 0.5
    data.LineEndY = containerY + (boxHeight - bottomLineH)
end

local function g_Botmater_ESPScanEnemies()
    local pc = g_Botmater_ESPGetController()
    local me = g_Botmater_ESPGetLocalCharacter()
    if not pc or not me then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        return nil
    end
    local myLoc = ESPShared.GetFrameRecord(me).Location
    if not myLoc then
        g_Botmater_ShotESP.Enemies = {}
        g_Botmater_ShotESP.RealCount = 0
        g_Botmater_ShotESP.BotCount = 0
        return pc
    end
    local myTeam = g_Botmater_ESPGetTeamID(me)

    local list = {}
    local realCount = 0
    local botCount = 0
    local pawns=ESPShared.GetFramePawns()
    if not pawns then return pc end
    if pawns then
        for _, character in pairs(pawns) do
            if character~=me and ESPShared.GetFrameRecord(character).Alive and ESPShared.Events.Counted(character) then
                local team = g_Botmater_ESPGetTeamID(character)
                if myTeam == nil or team == nil or tostring(team) ~= tostring(myTeam) then
                    local dist = ESPShared.DistanceMetersFrom(ESPShared.GetFrameRecord(character),myLoc)
                    if dist <= (tonumber(_G.g_Botmater_VIPShotESP.MaxRangeMeters) or 300.0) then
                        local isBot = g_Botmater_ESPIsBot(character)
                        local k = g_Botmater_ESPGetPlayerKey(character)
                        if k then
                            list[#list+1] = {Character=character, Key=k, IsBot=isBot, Distance=dist}
                            if isBot then botCount = botCount + 1 else realCount = realCount + 1 end
                        end
                    end
                end
            end
        end
    end
    local maxRendered = math.floor(ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.MaxRendered,10,1,64))
    if #list > maxRendered then
        table.sort(list,function(a,b)
            if a.Distance==b.Distance then return a.Key<b.Key end
            return a.Distance<b.Distance
        end)
    end
    g_Botmater_ShotESP.Enemies = list
    g_Botmater_ShotESP.RealCount = realCount
    g_Botmater_ShotESP.BotCount = botCount
    return pc
end

local function g_Botmater_ESPPrune(active,alive)
    alive=alive or active
    for _,registry in ipairs({g_Botmater_ShotESP.Lines,g_Botmater_ShotESP.Names}) do
        for key,data in pairs(registry) do
            if not active[key] and g_Botmater_ESPDestroyWidgetData(data) then registry[key]=nil end
        end
    end
    for key in pairs(g_Botmater_ShotESP._BotCache or {}) do if not alive[key] then g_Botmater_ShotESP._BotCache[key]=nil end end
    for key in pairs(g_Botmater_ShotESP.LastProjected) do if not alive[key] then g_Botmater_ShotESP.LastProjected[key]=nil end end
end

ESPShared.Events.Clearers[#ESPShared.Events.Clearers+1]=function(actor)
    ESPShared.Events.ClearIn(g_Botmater_ShotESP,g_Botmater_ESPPrune,actor)
end

local g_Botmater_EnemyCounter = {
    Container = nil, Slot = nil, PlayerBG = nil, BotBG = nil, PlayerText = nil, BotText = nil,
    Width = 218.4, Height = 33.6, OffsetY = 22.5, FontSize = 13, FontScale = 1.2,
    _LastPlayers = -1, _LastBots = -1, _PosVec = nil, _LastPosX = nil, _LastPosY = nil,
    CanvasCenterX = 0.0, CanvasCenterY = 0.0,
}

local function g_Botmater_CounterTextColor(widget,color)
    _G.g_vipserver_ESPSetTextColor(widget,color)
end

local function g_Botmater_CounterCreate()
    if V1Cleanup.Count>=V1Cleanup.AdmissionLimit then return false end
    if g_Botmater_EnemyCounter.Container and slua.isValid(g_Botmater_EnemyCounter.Container) then
        return true
    end
    local canvas = g_Botmater_ESPGetCanvas()
    if not canvas or not g_Botmater_ESPValid(canvas) then return false end

    local W, H = g_Botmater_EnemyCounter.Width, g_Botmater_EnemyCounter.Height
    local halfW = W * 0.5

    local Container, PlayerBG, BotBG, PlayerText, BotText = nil, nil, nil, nil, nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
    if not Container or not slua.isValid(Container) then return false end
    pcall(function() PlayerBG = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    pcall(function() BotBG = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
    pcall(function() PlayerText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)
    pcall(function() BotText = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)

    if not PlayerBG or not BotBG or not PlayerText or not BotText
        or not slua.isValid(PlayerBG) or not slua.isValid(BotBG)
        or not slua.isValid(PlayerText) or not slua.isValid(BotText) then
        V1Cleanup.Retire(Container)
        return false
    end

    pcall(function()
        PlayerBG:SetBrushColor(CACHE_COUNTER_PLAYER_BG)
        PlayerBG:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        BotBG:SetBrushColor(CACHE_COUNTER_BOT_BG)
        BotBG:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    local pbgSlot, bbgSlot = nil, nil
    pcall(function() pbgSlot = Container:AddChildToCanvas(PlayerBG) end)
    pcall(function() bbgSlot = Container:AddChildToCanvas(BotBG) end)
    if not pbgSlot or not bbgSlot then
        V1Cleanup.Retire(Container)
        return false
    end

    pcall(function()
        pbgSlot:SetAutoSize(false)
        pbgSlot:SetPosition(g_Botmater_ESPV2(0, 0))
        pbgSlot:SetSize(g_Botmater_ESPV2(halfW, H))
        pbgSlot:SetZOrder(0)
        bbgSlot:SetAutoSize(false)
        bbgSlot:SetPosition(g_Botmater_ESPV2(halfW, 0))
        bbgSlot:SetSize(g_Botmater_ESPV2(halfW, H))
        bbgSlot:SetZOrder(0)
    end)

    pcall(function()
        PlayerText:SetText("REAL: 0")
        BotText:SetText("BOT: 0")
        _G.g_vipserver_ESPSetFont(PlayerText,g_Botmater_EnemyCounter.FontSize,0)
        _G.g_vipserver_ESPSetFont(BotText,g_Botmater_EnemyCounter.FontSize,0)
        local scale=g_Botmater_EnemyCounter.FontScale
        PlayerText:SetRenderTransformPivot(g_Botmater_ESPV2(0.5,0.5))
        BotText:SetRenderTransformPivot(g_Botmater_ESPV2(0.5,0.5))
        PlayerText:SetRenderScale(g_Botmater_ESPV2(scale,scale))
        BotText:SetRenderScale(g_Botmater_ESPV2(scale,scale))
        PlayerText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        BotText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    g_Botmater_CounterTextColor(PlayerText, CACHE_COUNTER_PLAYER_TEXT)
    g_Botmater_CounterTextColor(BotText, CACHE_COUNTER_BOT_TEXT)

    local ptSlot, btSlot = nil, nil
    pcall(function() ptSlot = Container:AddChildToCanvas(PlayerText) end)
    pcall(function() btSlot = Container:AddChildToCanvas(BotText) end)
    if ptSlot then
        pcall(function()
            ptSlot:SetAutoSize(true)
            ptSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5))
            ptSlot:SetPosition(g_Botmater_ESPV2(halfW * 0.5, H * 0.5))
            ptSlot:SetZOrder(2)
        end)
    end
    if btSlot then
        pcall(function()
            btSlot:SetAutoSize(true)
            btSlot:SetAlignment(g_Botmater_ESPV2(0.5, 0.5))
            btSlot:SetPosition(g_Botmater_ESPV2(halfW + halfW * 0.5, H * 0.5))
            btSlot:SetZOrder(2)
        end)
    end

    local mainSlot = nil
    pcall(function() mainSlot = canvas:AddChildToCanvas(Container) end)
    if not mainSlot then
        V1Cleanup.Retire(Container)
        return false
    end
    pcall(function()
        mainSlot:SetAutoSize(false)
        mainSlot:SetSize(g_Botmater_ESPV2(W, H))
        mainSlot:SetZOrder(50)
    end)

    g_Botmater_EnemyCounter.Container = Container
    g_Botmater_EnemyCounter.Slot = mainSlot
    g_Botmater_EnemyCounter.PlayerBG = PlayerBG
    g_Botmater_EnemyCounter.BotBG = BotBG
    g_Botmater_EnemyCounter.PlayerText = PlayerText
    g_Botmater_EnemyCounter.BotText = BotText
    g_Botmater_EnemyCounter._LastPlayers = -1
    g_Botmater_EnemyCounter._LastBots = -1
    g_Botmater_EnemyCounter._PosVec = nil
    g_Botmater_EnemyCounter._LastPosX = nil
    g_Botmater_EnemyCounter._LastPosY = nil

    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    return true
end

local function g_Botmater_CounterUpdatePosition(pc)
    local slot = g_Botmater_EnemyCounter.Slot
    if not slot or not slua.isValid(slot) then return end
    if not pc or not g_Botmater_ESPValid(pc) then return end

    local canvasW, canvasH = g_Botmater_ESPGetCanvasLocalSize()
    if not canvasW or not canvasH then
        local vw, vh = g_Botmater_ESPViewport(pc)
        if not vw or vw <= 200 then return end
        local sx = g_Botmater_ShotESP.CanvasScaleX or 1.0
        local sy = g_Botmater_ShotESP.CanvasScaleY or 1.0
        local ox = g_Botmater_ShotESP.CanvasOffsetX or 0.0
        local oy = g_Botmater_ShotESP.CanvasOffsetY or 0.0
        canvasW = (vw * sx) - ox
        canvasH = (vh * sy) - oy
    end

    if not canvasW or not canvasH then return end

    local canvasCenterX = canvasW * 0.5
    local canvasCenterY = g_Botmater_EnemyCounter.OffsetY

    local x = canvasCenterX - g_Botmater_EnemyCounter.Width * 0.5
    local y = canvasCenterY

    g_Botmater_EnemyCounter.CanvasCenterX = canvasCenterX
    g_Botmater_EnemyCounter.CanvasCenterY = canvasCenterY + g_Botmater_EnemyCounter.Height * 0.5

    local lx, ly = g_Botmater_EnemyCounter._LastPosX, g_Botmater_EnemyCounter._LastPosY
    if lx ~= nil and ly ~= nil and math.abs(lx - x) < 0.1 and math.abs(ly - y) < 0.1 then return end
    g_Botmater_EnemyCounter._PosVec = g_Botmater_ESPV2(x, y)
    local ok = pcall(function() slot:SetPosition(g_Botmater_EnemyCounter._PosVec) end)
    if ok then
        g_Botmater_EnemyCounter._LastPosX = x
        g_Botmater_EnemyCounter._LastPosY = y
    end
end

local function g_Botmater_GetLineOrigin(pc)
    if _G.g_Botmater_ESPOptions.EnemyCounter then
        g_Botmater_CounterUpdatePosition(pc)
        return g_Botmater_ESPV2(g_Botmater_EnemyCounter.CanvasCenterX,g_Botmater_EnemyCounter.CanvasCenterY+g_Botmater_EnemyCounter.Height*0.5)
    end
    local width=g_Botmater_ESPGetCanvasLocalSize()
    if not width then
        local vw=g_Botmater_ESPViewport(pc)
        width=(vw or 2400)*g_Botmater_ShotESP.CanvasScaleX+g_Botmater_ShotESP.CanvasOffsetX
    end
    local top=g_Botmater_EnemyCounter.OffsetY
    return g_Botmater_ESPV2(width*0.5,top+g_Botmater_EnemyCounter.Height)
end

local function g_Botmater_CounterSetCounts(realCount, botCount)
    realCount = tonumber(realCount) or 0
    botCount = tonumber(botCount) or 0
    if g_Botmater_EnemyCounter._LastPlayers ~= realCount
        and g_Botmater_EnemyCounter.PlayerText and slua.isValid(g_Botmater_EnemyCounter.PlayerText) then
        local ok, applied = pcall(function()
            return g_Botmater_EnemyCounter.PlayerText:SetText(string.format("REAL: %d", realCount)) ~= false
        end)
        if ok and applied then g_Botmater_EnemyCounter._LastPlayers = realCount end
    end
    if g_Botmater_EnemyCounter._LastBots ~= botCount
        and g_Botmater_EnemyCounter.BotText and slua.isValid(g_Botmater_EnemyCounter.BotText) then
        local ok, applied = pcall(function()
            return g_Botmater_EnemyCounter.BotText:SetText(string.format("BOT: %d", botCount)) ~= false
        end)
        if ok and applied then g_Botmater_EnemyCounter._LastBots = botCount end
    end
end

local function g_Botmater_CounterStart(pc)
    if not g_Botmater_CounterCreate() then return end
    pcall(function()
        g_Botmater_EnemyCounter.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)
    g_Botmater_CounterUpdatePosition(pc)
end

local function g_Botmater_CounterStop()
    local container = g_Botmater_EnemyCounter.Container
    g_Botmater_EnemyCounter.Container = nil
    g_Botmater_EnemyCounter.Slot = nil
    g_Botmater_EnemyCounter.PlayerBG = nil
    g_Botmater_EnemyCounter.BotBG = nil
    g_Botmater_EnemyCounter.PlayerText = nil
    g_Botmater_EnemyCounter.BotText = nil
    g_Botmater_EnemyCounter._LastPlayers = -1
    g_Botmater_EnemyCounter._LastBots = -1
    g_Botmater_EnemyCounter._PosVec = nil
    g_Botmater_EnemyCounter._LastPosX = nil
    g_Botmater_EnemyCounter._LastPosY = nil
    g_Botmater_EnemyCounter.CanvasCenterX = 0.0
    g_Botmater_EnemyCounter.CanvasCenterY = 0.0
    if g_Botmater_ESPValid(container) then
        V1Cleanup.Retire(container)
    end
end

local function g_Botmater_ESPRenderActor(item,pc,opt,origin,now)
    local state=g_Botmater_ShotESP
    local c,key,isBot=item.Character,item.Key,item.IsBot
    local head,feet,onScreen,reason=ESPShared.Events.Project(pc,c,state)
    if not onScreen then
        local last=state.LastProjected[key]
        if reason=="unavailable" and last and now>=last and now-last<=0.08 then
            state.Active[key]=true
        else
            state.LastProjected[key]=nil
        end
        return
    end
    local anchor=head or feet
    if not anchor then return end
    state.Active[key]=true;state.LastProjected[key]=now
    local color=g_Botmater_ESPGetColors(isBot)
    local hp=opt.Health and g_Botmater_ESPGetHealthPct(c) or 1
    g_Botmater_ESPUpdateNameTag(key,c,anchor,feet,isBot,item.Distance,hp,pc)
    local line=state.Lines[key]
    if opt.Line and (not line or line.Broken or not g_Botmater_ESPValid(line.Widget)
        or not g_Botmater_ESPValid(line.Slot)) then
        if not g_Botmater_ESPDestroyWidgetData(line) then return end
        line=g_Botmater_ESPCreateLine(color);state.Lines[key]=line
    end
    if opt.Line and line then
        local colorKey=isBot and "B" or "P"
        if line.ColorKey~=colorKey then
            local ok=pcall(function() line.Widget:SetBrushColor(color) end)
            if ok then line.ColorKey=colorKey end
        end
        local tag=state.Names[key]
        local x,y=tag and tag.LineEndX or anchor.X,tag and tag.LineEndY or anchor.Y
        g_Botmater_ESPDrawLine(line,origin.X,origin.Y,x,y,
            ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.TracerThickness,1,0.1,12))
    elseif line then g_Botmater_ESPHide(line) end
end

local function g_Botmater_ESPDrawCandidates(pc,opt,now)
    local state=g_Botmater_ShotESP
    local origin=g_Botmater_GetLineOrigin(pc)
    local limit=math.floor(ESPShared.SafeNumber(_G.g_Botmater_VIPShotESP.MaxRendered,10,1,64))
    for i,item in ipairs(state.Enemies) do
        if i>limit then break end
        local ok,err=pcall(g_Botmater_ESPRenderActor,item,pc,opt,origin,now)
        if not ok then
            state.Active[item.Key]=nil;state.LastProjected[item.Key]=nil
            local f=_G.LunarFeatures
            if f and f.Error then f.Error("V1.Actor",err) end
        end
    end
end

local function g_Botmater_ESPUpdate()
    local state=g_Botmater_ShotESP
    local opt=_G.g_Botmater_ESPOptions
    local details=opt and (opt.Name or opt.Line or opt.Health or opt.Distance)
    local counter=opt and opt.EnemyCounter
    local now=g_Botmater_ESPNow()
    V1Cleanup.Pump(now)
    if not _G.g_Botmater_VIPShotESP.Enabled or (not details and not counter) then
        g_Botmater_ESPResetWidgets();g_Botmater_CounterStop();return
    end
    local world=g_Botmater_ESPWorld()
    ESPShared.Events.WorldChanged(world)
    if world~=state.LastWorld then
        g_Botmater_ESPResetWidgets();g_Botmater_CounterStop();state.LastWorld=world
    end
    local oldCanvas=state.Canvas
    local canvas=g_Botmater_ESPGetCanvas()
    if canvas~=oldCanvas then g_Botmater_CounterStop() end
    if not canvas then return end
    local pc=g_Botmater_ESPGetController()
    if now<state.LastScanClock or now-state.LastScanClock>=(tonumber(_G.g_Botmater_VIPShotESP.ScanInterval) or 0.05) then
        pc=g_Botmater_ESPScanEnemies() or pc;state.LastScanClock=now
    end
    pc=pc or g_Botmater_ESPGetController()
    if not pc then g_Botmater_ESPResetWidgets();g_Botmater_CounterStop();return end
    local location=ESPShared.GetFrameRecord(g_Botmater_ESPGetLocalCharacter()).Location
    local active,alive=state.Active,state.Alive
    state.RealCount,state.BotCount=_G.g_vipserver_ESPFilterEnemies(state.Enemies,location,
        _G.g_Botmater_VIPShotESP.MaxRangeMeters,alive)
    g_Botmater_ESPPrune(alive,alive)
    for k in pairs(active) do active[k]=nil end
    if now<state.LastTransformClock or now-state.LastTransformClock>=(tonumber(_G.g_Botmater_VIPShotESP.TransformInterval) or 0.033) then
        g_Botmater_ESPUpdateCanvasTransform(pc);state.LastTransformClock=now
    end
    if counter then
        pcall(g_Botmater_CounterStart,pc)
        pcall(g_Botmater_CounterSetCounts,state.RealCount,state.BotCount)
    else g_Botmater_CounterStop() end
    local ok,err=true,nil
    if details then ok,err=pcall(g_Botmater_ESPDrawCandidates,pc,opt,now) end
    g_Botmater_ESPPrune(active,alive)
    if not ok then
        local f=_G.LunarFeatures
        if f and f.Error then f.Error("V1.Draw",err) end
    end
end

local F=_G.LunarFeatures
F.V1={State=g_Botmater_ShotESP,Counter=g_Botmater_EnemyCounter,Tick=g_Botmater_ESPUpdate,
    Cleanup=V1Cleanup,
    Reset=function() g_Botmater_ESPResetWidgets();g_Botmater_CounterStop() end,
    Refresh=function() g_Botmater_ShotESP.LastScanClock=-999;g_Botmater_ShotESP.LastTransformClock=-999 end}

    -- ───── PART G: Tick driver + toggle API ─────
    _G.LunarESP_V1_Tick = function()
        if not _G.g_Botmater_ESPOptions then return end
        local now = LF.Now()
        ESPShared.Frame.Begin(now)
        local ok,err = pcall(function()
            local FF = _G.LunarFeatures
            if FF and FF.V1 and FF.V1.Tick then FF.V1.Tick() end
        end)
        ESPShared.Frame.Finish()
        if not ok then print("[V1 Tick Error]", tostring(err)) end
    end

    _G.LunarESP_V1_Reset = function()
        local FF = _G.LunarFeatures
        if FF and FF.V1 and FF.V1.Reset then pcall(FF.V1.Reset) end
    end

    _G.ESP_V1_EnableAll = function()
        if not _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions = {} end
        _G.g_Botmater_ESPOptions.Name = true
        _G.g_Botmater_ESPOptions.Line = true
        _G.g_Botmater_ESPOptions.Health = true
        _G.g_Botmater_ESPOptions.Distance = true
        _G.g_Botmater_ESPOptions.EnemyCounter = true
    end
    _G.ESP_V1_DisableAll = function()
        if not _G.g_Botmater_ESPOptions then return end
        _G.g_Botmater_ESPOptions.Name = false
        _G.g_Botmater_ESPOptions.Line = false
        _G.g_Botmater_ESPOptions.Health = false
        _G.g_Botmater_ESPOptions.Distance = false
        _G.g_Botmater_ESPOptions.EnemyCounter = false
    end
    _G.ESP_V1_Toggle = function(key)
        if not _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions = {} end
        _G.g_Botmater_ESPOptions[key] = not _G.g_Botmater_ESPOptions[key]
    end

    -- (auto-enable removed: every ESP V1 option stays OFF until the user switches it on in the menu)

    print("[ESP V1] Botmater module installed")
end
-- ═══════════════════════════════════════════════════════════════════════════
-- End ESP V1

-- MagicBullet_module.lua
-- Extracted from VIPGUROP.lua: CustomMagicBullet logic (lines ~7841-7862 hash/config,
-- ~7908-7932 helpers + BoneScaleMap, ~8028-8126 per-enemy physics-asset scaling).
-- Self-contained: own config, own state, own tick. Original behaviour kept:
--   * hitbox scale per bone group (head/neck, body, legs) from the original BoneScaleMap
--   * original hitbox sizes are cached once per PhysicsAsset and restored (scale 1.0) when turned off
--   * work is done once per enemy per config hash (no per-frame recompute)
--   * at most 50 body setups per PhysicsAsset
-- Host Lua must call _G.MagicBullet_Tick() every tick, same place as the other mod loops.

do
    if _G.__MAGICBULLET_INSTALLED then return end
    _G.__MAGICBULLET_INSTALLED = true

    -- Config. Menu reads/writes these. Range 0.0 - 5.0 as in the source menu.
    _G.MagicBulletConfig = _G.MagicBulletConfig or {
        Enabled = false,
        Head = 1.0,
        Body = 1.0,
        Legs = 1.0,
    }

    local State = {
        Hash = "",
        Marks = {},     -- per enemy key: { MagicBulletHash, MagicTargetID }
        Modded = {},    -- PhysAssetName -> hash that was last applied
        Orig = {},      -- PhysAssetName -> bone key -> original element sizes
        EverModified = false,
    }
    _G.MagicBulletState = State

    local function Valid(o)
        if o == nil then return false end
        if type(_G.Valid) == "function" then
            local ok, v = pcall(_G.Valid, o)
            return ok and v == true
        end
        local ok, v = pcall(function() return slua.isValid(o) end)
        return ok and v == true
    end

    local function EnemyKey(enemy)
        if Valid(enemy) then
            if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
            if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
        end
        return tostring(enemy)
    end

    local function GetFirstElemSafe(elemArray)
        if elemArray and type(elemArray.Num) == "function" and elemArray:Num() > 0 then
            if type(elemArray.Get) == "function" then return elemArray:Get(0) end
        elseif elemArray and type(elemArray) == "table" and #elemArray > 0 then
            return elemArray[1]
        end
        return nil
    end

    local function ClampScale(v, fallback)
        local n = tonumber(v)
        if n == nil or n ~= n or n == math.huge or n == -math.huge then n = fallback end
        if n < 0 then n = 0 end
        if n > 5 then n = 5 end
        return n
    end

    local function ClearAll()
        State.Marks = {}
        State.Modded = {}
        State.Orig = {}
        State.Hash = ""
        State.EverModified = false
    end

    local function ApplyToEnemy(enemy, enemyMesh, key, runInject, bone)
        local mark = State.Marks[key]
        if not mark then mark = {}; State.Marks[key] = mark end

        local uniqueID = type(enemy.GetUniqueID) == "function" and enemy:GetUniqueID() or tostring(enemy.PlayerKey or enemy)
        if mark.MagicBulletHash == State.Hash and mark.MagicTargetID == uniqueID then return end

        local PhysicsAsset = enemyMesh.PhysicsAssetOverride
        if not slua.isValid(PhysicsAsset) and enemyMesh.SkeletalMesh then PhysicsAsset = enemyMesh.SkeletalMesh.PhysicsAsset end
        if not (slua.isValid(PhysicsAsset) and PhysicsAsset.SkeletalBodySetups) then return end

        local PhysAssetName = "DefaultPhys"
        pcall(function() PhysAssetName = PhysicsAsset:GetName() end)

        if State.Modded[PhysAssetName] ~= State.Hash then
            if not State.Orig[PhysAssetName] then State.Orig[PhysAssetName] = {} end
            local OrigHitboxData = State.Orig[PhysAssetName]

            local SkeletalBodySetups = PhysicsAsset.SkeletalBodySetups
            local numSetups = type(SkeletalBodySetups.Num) == "function" and SkeletalBodySetups:Num() or #SkeletalBodySetups
            local limit = numSetups > 50 and 50 or numSetups

            for i = 1, limit do
                local BodySetup = type(SkeletalBodySetups.Get) == "function" and SkeletalBodySetups:Get(i - 1) or SkeletalBodySetups[i]
                if slua.isValid(BodySetup) then
                    local LowerBoneName = string.lower(tostring(BodySetup.BoneName))
                    local MatchedBoneKey = nil
                    for k, _ in pairs(bone) do
                        if string.find(LowerBoneName, k, 1, true) then MatchedBoneKey = k break end
                    end

                    if MatchedBoneKey then
                        local TargetScale = 1.0
                        if runInject then TargetScale = bone[MatchedBoneKey] end

                        local AggGeom = BodySetup.AggGeom
                        local BoxElems = AggGeom and AggGeom.BoxElems or BodySetup.BoxElems
                        local SphereElems = AggGeom and AggGeom.SphereElems or BodySetup.SphereElems
                        local SphylElems = AggGeom and AggGeom.SphylElems or BodySetup.SphylElems

                        local BoxElem = GetFirstElemSafe(BoxElems)
                        local SphereElem = GetFirstElemSafe(SphereElems)
                        local SphylElem = GetFirstElemSafe(SphylElems)

                        if not OrigHitboxData[MatchedBoneKey] then
                            OrigHitboxData[MatchedBoneKey] = { Box = nil, Sphere = nil, Sphyl = nil }
                            if BoxElem then OrigHitboxData[MatchedBoneKey].Box = { X = BoxElem.X, Y = BoxElem.Y, Z = BoxElem.Z } end
                            if SphereElem then OrigHitboxData[MatchedBoneKey].Sphere = { Radius = SphereElem.Radius } end
                            if SphylElem then OrigHitboxData[MatchedBoneKey].Sphyl = { Radius = SphylElem.Radius, Length = SphylElem.Length } end
                        end

                        local OrigElemData = OrigHitboxData[MatchedBoneKey]

                        if OrigElemData.Box and BoxElem then
                            BoxElem.X = OrigElemData.Box.X * TargetScale
                            BoxElem.Y = OrigElemData.Box.Y * TargetScale
                            BoxElem.Z = OrigElemData.Box.Z * TargetScale
                            if type(BoxElems.Set) == "function" then BoxElems:Set(0, BoxElem) else BoxElems[1] = BoxElem end
                            if AggGeom then AggGeom.BoxElems = BoxElems; BodySetup.AggGeom = AggGeom else BodySetup.BoxElems = BoxElems end
                        end

                        if OrigElemData.Sphere and SphereElem then
                            SphereElem.Radius = OrigElemData.Sphere.Radius * TargetScale
                            if type(SphereElems.Set) == "function" then SphereElems:Set(0, SphereElem) else SphereElems[1] = SphereElem end
                            if AggGeom then AggGeom.SphereElems = SphereElems; BodySetup.AggGeom = AggGeom else BodySetup.SphereElems = SphereElems end
                        end

                        if OrigElemData.Sphyl and SphylElem then
                            SphylElem.Radius = OrigElemData.Sphyl.Radius * TargetScale
                            SphylElem.Length = OrigElemData.Sphyl.Length * TargetScale
                            if type(SphylElems.Set) == "function" then SphylElems:Set(0, SphylElem) else SphylElems[1] = SphylElem end
                            if AggGeom then AggGeom.SphylElems = SphylElems; BodySetup.AggGeom = AggGeom else BodySetup.SphylElems = SphylElems end
                        end
                    end
                end
            end
            State.Modded[PhysAssetName] = State.Hash
            if runInject then State.EverModified = true end
        end

        if enemyMesh.SetPhysicsAsset then enemyMesh:SetPhysicsAsset(PhysicsAsset) end
        enemyMesh.PhysicsAssetOverride = PhysicsAsset

        mark.MagicBulletHash = State.Hash
        mark.MagicTargetID = uniqueID
    end

    _G.MagicBullet_Reset = function()
        ClearAll()
    end

    _G.MagicBullet_Tick = function()
        local ok, err = pcall(function()
            local cfg = _G.MagicBulletConfig
            if not cfg then return end

            local GameplayData = _G.GameplayData or require("GameLua.GameCore.Data.GameplayData")
            if not GameplayData then return end
            local pc = GameplayData.GetPlayerController()
            local localPlayer = nil
            if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end

            -- Lobby / dead / map change: drop every cached reference.
            if not Valid(localPlayer) then ClearAll() return end

            local runInject = cfg.Enabled == true
            local mHead, mBody, mLegs = 1.0, 1.0, 1.0
            if runInject then
                mHead = ClampScale(cfg.Head, 1.0)
                mBody = ClampScale(cfg.Body, 1.0)
                mLegs = ClampScale(cfg.Legs, 1.0)
            end

            local hash = runInject and ("M_" .. tostring(mHead) .. "_" .. tostring(mBody) .. "_" .. tostring(mLegs)) or "OFF"
            State.Hash = hash

            -- Nothing was ever changed and it is off: nothing to restore.
            if not runInject and not State.EverModified then return end

            local bone = {
                ["head"] = mHead, ["neck_01"] = mHead,
                ["pelvis"] = mBody, ["spine_01"] = mBody, ["spine_02"] = mBody, ["spine_03"] = mBody,
                ["thigh_l"] = mLegs, ["thigh_r"] = mLegs,
                ["calf_l"] = mLegs, ["calf_r"] = mLegs,
                ["foot_l"] = mLegs, ["foot_r"] = mLegs,
            }

            local allCharacters = {}
            if GameplayData.GetAllPlayerCharacters then
                allCharacters = GameplayData.GetAllPlayerCharacters()
            elseif GameplayData.GameCharacters then
                for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
            end

            local currentKeys = {}
            for _, enemy in pairs(allCharacters) do
                if Valid(enemy) and enemy ~= localPlayer then currentKeys[EnemyKey(enemy)] = true end
            end
            for key in pairs(State.Marks) do
                if not currentKeys[key] then State.Marks[key] = nil end
            end

            local anyPending = false
            for _, enemy in pairs(allCharacters) do
                if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                    local isDead = false
                    pcall(function()
                        if type(enemy.IsDead) == "function" then isDead = enemy:IsDead()
                        elseif enemy.bIsDead ~= nil then isDead = enemy.bIsDead
                        elseif enemy.bIsDeadFlag ~= nil then isDead = enemy.bIsDeadFlag end
                        if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then isDead = true end
                    end)

                    if not isDead then
                        local eMesh = nil
                        pcall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                        if slua.isValid(eMesh) then
                            local key = EnemyKey(enemy)
                            local okE, errE = pcall(ApplyToEnemy, enemy, eMesh, key, runInject, bone)
                            if not okE then print("[MagicBullet] enemy error", tostring(errE)) end
                            local m = State.Marks[key]
                            if not m or m.MagicBulletHash ~= State.Hash then anyPending = true end
                        end
                    end
                end
            end

            -- After restoring to 1.0 for everyone, stop looping until it is enabled again.
            if not runInject and not anyPending then State.EverModified = false end
        end)
        if not ok then print("[MagicBullet Tick Error]", tostring(err)) end
    end

    print("[MagicBullet] module installed")
end

function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    _G.KASHMIRYState.CustomTextData = _G.KASHMIRYState.CustomTextData or {
        AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
        AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
        AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
        AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0,
    }

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then
                return id
            end
            return old_get(id)
        end
        LocUtil._IsModMenuHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")

        -- ==================== AIMBOT FORCE ====================
        local StackAimbotForce = {
            { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ UR/SCRIM PLAYER - TOUCH AIM", ExpandIndex = 0, GetFunc = function() return _G.KASHMIRYConfig.AimTouchEnable end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchEnable = v return true end },
            
            -- HIPFIRE
            { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Hipfire Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.KASHMIRYConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchHipfire = v return true end },
            { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchHipIgKnock = v return true end },
            { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchHipIgBot = v return true end },
            { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchHipVisCheck = v return true end },
            { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Slider, Text = "      Aim Target (1: Near Crosshair 2: Near Enemy 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchHipPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchHipPrio = val return true end },
            { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Slider, Text = "      Bone Target (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchHipBone = val return true end },
            { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim when firing 2:Always aim)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchHipCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.KASHMIRYState.CustomTextData.AimTouchHipCond = val return true end },
            { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = "      Aim / Speed Smooth (1-62% perfect)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchHipSpeed = v return true end },
            { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = "      FOV Range (1-30% perfect)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchHipFOV = v return true end },
            { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = "      Distance (1-40% safe)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.KASHMIRYState.CustomTextData.AimTouchHipDist or 250) / 5) end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchHipDist = v * 5 return true end },
            
            -- SCOPE ALL
            { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Scoped Aimbot (All Weapons)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.KASHMIRYConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchScopeAll = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchScopeIgKnock = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchScopeIgBot = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchScopeVisCheck = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Slider, Text = "      Scope Target (1: Near Crosshair 2: Near Enemy 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopePrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchScopePrio = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Slider, Text = "      Bone Target (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchScopeBone = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim when firing 2:Always aim)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopeCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.KASHMIRYState.CustomTextData.AimTouchScopeCond = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = "      Scope Aim/Smooth Speed (1-57% safe)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchScopeSpeed = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = "      FOV Range (FOV - 1-20% perfect)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchScopeFOV = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = "      Distance (1-45% safe)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.KASHMIRYState.CustomTextData.AimTouchScopeDist or 300) / 5) end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
            { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = "      Movement Prediction", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopePred or 0 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchScopePred = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = "      Auto Recoil Compensation (set 3-4% for smooth)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchScopeRecoil or 0 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchScopeRecoil = v return true end },

            -- SHOTGUN
            { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Shotgun Aimbot", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.KASHMIRYConfig.AimTouchSG end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSG = v return true end },
            { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = "      Auto Fire (may cause damage bug if not firing manually)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSGAutoFire = v return true end },
            { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSGIgKnock end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSGIgKnock = v return true end },
            { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSGIgBot end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSGIgBot = v return true end },
            { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSGVisCheck end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSGVisCheck = v return true end },
            { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Center 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchSGPrio = val return true end },
            { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Slider, Text = "      Bone Target (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchSGBone = val return true end },
            { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim when firing 2:Always aim)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.KASHMIRYState.CustomTextData.AimTouchSGCond = val return true end },
            { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = "      Smoothing / Speed (1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSGSpeed = v return true end },
            { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = "      FOV Range (FOV - 1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSGFOV = v return true end },
            { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = "      Distance (Jarak - 1-100m)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSGDist or 30 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSGDist = v return true end },
            
            -- SNIPER
            { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Scoped Aimbot (Sniper Rifles Only)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.KASHMIRYConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchScopeSniper = v return true end },
            { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSniperIgKnock end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSniperIgKnock = v return true end },
            { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSniperIgBot end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSniperIgBot = v return true end },
            { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = "      Visibility Check", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.KASHMIRYConfig.AimTouchSniperVisCheck end, SetFunc = function(c,v) _G.KASHMIRYConfig.AimTouchSniperVisCheck = v return true end },
            { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Center 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchSniperPrio = val return true end },
            { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Slider, Text = "      Bone Target (1:Head 2:Chest 3:Stomach 4:Pelvis)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.KASHMIRYState.CustomTextData.AimTouchSniperBone = val return true end },
            { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim when firing 2:Always aim)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperCond or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.KASHMIRYState.CustomTextData.AimTouchSniperCond = val return true end },
            { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = "      Smoothing / Speed (1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperSpeed or 30 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSniperSpeed = v return true end },
            { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = "      FOV Range (1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperFOV or 20 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSniperFOV = v return true end },
            { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = "      Distance (1-500m)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.KASHMIRYState.CustomTextData.AimTouchSniperDist or 400) / 5) end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
            { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = "      Movement Prediction (0-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.KASHMIRYState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.KASHMIRYState.CustomTextData.AimTouchSniperPred = v return true end }
        }

        -- ==================== ESP V1 (PUBG) ====================
        local StackESPV1 = {
            { Key = "ModMenu_V1_Master", UI = AliasMap.Switcher, Text = "▶ Enable ESP V1 (Master)", GetFunc = function() return _G.g_Botmater_VIPShotESP and _G.g_Botmater_VIPShotESP.Enabled == true end, SetFunc = function(c,v) if _G.g_Botmater_VIPShotESP then _G.g_Botmater_VIPShotESP.Enabled = (v == true) end return true end },
            { Key = "ModMenu_V1_Name", UI = AliasMap.Switcher, Text = "   Show Player Name", GetFunc = function() return _G.g_Botmater_ESPOptions and _G.g_Botmater_ESPOptions.Name == true end, SetFunc = function(c,v) if _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions.Name = (v == true) end return true end },
            { Key = "ModMenu_V1_Dist", UI = AliasMap.Switcher, Text = "   Show Distance", GetFunc = function() return _G.g_Botmater_ESPOptions and _G.g_Botmater_ESPOptions.Distance == true end, SetFunc = function(c,v) if _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions.Distance = (v == true) end return true end },
            { Key = "ModMenu_V1_Line", UI = AliasMap.Switcher, Text = "   Show Tracer Line", GetFunc = function() return _G.g_Botmater_ESPOptions and _G.g_Botmater_ESPOptions.Line == true end, SetFunc = function(c,v) if _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions.Line = (v == true) end return true end },
            { Key = "ModMenu_V1_Health", UI = AliasMap.Switcher, Text = "   Show Health Bar", GetFunc = function() return _G.g_Botmater_ESPOptions and _G.g_Botmater_ESPOptions.Health == true end, SetFunc = function(c,v) if _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions.Health = (v == true) end return true end },
            { Key = "ModMenu_V1_Counter", UI = AliasMap.Switcher, Text = "   Enemy Counter", GetFunc = function() return _G.g_Botmater_ESPOptions and _G.g_Botmater_ESPOptions.EnemyCounter == true end, SetFunc = function(c,v) if _G.g_Botmater_ESPOptions then _G.g_Botmater_ESPOptions.EnemyCounter = (v == true) end return true end },
        }

        -- ==================== MAGIC BULLET ====================
        local StackMagicBullet = {
            { Key = "ModMenu_Magic_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ (RISK BAN) Custom Magic Bullet", ExpandIndex = 0, GetFunc = function() return _G.MagicBulletConfig.Enabled == true end, SetFunc = function(c,v) _G.MagicBulletConfig.Enabled = (v == true) return true end },
            { Key = "ModMenu_Magic_Head", UI = AliasMap.Slider, Text = "   Head Damage (0.0 - 5.0)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, Min = 0, Max = 100, GetFunc = function() return math.floor(((_G.MagicBulletConfig.Head or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MagicBulletConfig.Head = (v / 100.0) * 5.0 return true end },
            { Key = "ModMenu_Magic_Body", UI = AliasMap.Slider, Text = "   Body Damage (0.0 - 5.0)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, Min = 0, Max = 100, GetFunc = function() return math.floor(((_G.MagicBulletConfig.Body or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MagicBulletConfig.Body = (v / 100.0) * 5.0 return true end },
            { Key = "ModMenu_Magic_Legs", UI = AliasMap.Slider, Text = "   Legs Damage (0.0 - 5.0)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, Min = 0, Max = 100, GetFunc = function() return math.floor(((_G.MagicBulletConfig.Legs or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MagicBulletConfig.Legs = (v / 100.0) * 5.0 return true end },
        }

        -- ==================== DEFINE MENU PAGE (ONLY AIMBOT) ====================
        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text= " ",
            UIKey = "Setting_Page_Privacy", 
            Category = {
                { Key = "Cat_Aimbot_Force", Text= "UR/ROOM-TOUCH AIM", Stack = StackAimbotForce },
                { Key = "Cat_ESPV1", Text= "ESP V1 (PUBG)", Stack = StackESPV1 },
                { Key = "Cat_MagicBullet", Text= "MAGIC BULLET", Stack = StackMagicBullet },
            }
        }
        
        table.insert(SettingCatalog, SettingPageDefine.ModMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...) 
            
            if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local hasModMenu = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "ModMenu" then
                            hasModMenu = true
                            break
                        end
                    end
                    if not hasModMenu then
                        table.insert(catalog, SettingPageDefine.ModMenu)
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

local function ShowKASHMIRYVIPMenu() 
    if _G.KASHMIRYMenuAlreadyShown then return end
    if _G.KASHMIRYState.MenuStep ~= 0 then return end

    _G.InitModMenuTab()
    _G.KASHMIRYState.MenuStep = 99
    _G.KASHMIRYMenuAlreadyShown = true
end

-- ========================================== 
-- AIMBOT V2 SYSTEM (Aim Touch) - LAG FREE (removed busy-wait)
-- ========================================== 
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then return result end
    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end
    local myTeam = player:GetTeamID()
    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

_G.AimTouch = function()
    pcall(function()
        if not _G.KASHMIRYConfig.AimTouchEnable then return end
        
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end
        
        local pc = player:GetPlayerControllerSafety()
        if not slua.isValid(pc) then return end
        
        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS
        
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        
        local isShotgun = false
        local isSniper = false
        local currentAmmo = 1
        
        if slua.isValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                isShotgun = true 
            end
            
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end
            
            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        if _G.KASHMIRYState.IsAutoFiring then
            pcall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.KASHMIRYState.IsAutoFiring = false
        end

        if isShotgun and currentAmmo <= 0 then
            return
        end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 50
        local fovVal = 30
        local maxDistMeters = 50
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        local predVal = 0 
        local recoilCompVal = 0 

        if isShotgun and _G.KASHMIRYConfig.AimTouchSG then
            cond = _G.KASHMIRYState.CustomTextData.AimTouchSGCond or 1
            if _G.KASHMIRYConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.KASHMIRYState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.KASHMIRYState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.KASHMIRYState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.KASHMIRYState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.KASHMIRYState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.KASHMIRYConfig.AimTouchSGVisCheck
            igKnock = _G.KASHMIRYConfig.AimTouchSGIgKnock
            igBot = _G.KASHMIRYConfig.AimTouchSGIgBot
            
        elseif isADS then
            if isSniper and _G.KASHMIRYConfig.AimTouchScopeSniper then
                cond = _G.KASHMIRYState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.KASHMIRYState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.KASHMIRYState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.KASHMIRYState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.KASHMIRYState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.KASHMIRYState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.KASHMIRYConfig.AimTouchSniperVisCheck
                igKnock = _G.KASHMIRYConfig.AimTouchSniperIgKnock
                igBot = _G.KASHMIRYConfig.AimTouchSniperIgBot
                predVal = _G.KASHMIRYState.CustomTextData.AimTouchSniperPred or 0
            elseif _G.KASHMIRYConfig.AimTouchScopeAll then
                cond = _G.KASHMIRYState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.KASHMIRYState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = _G.KASHMIRYState.CustomTextData.AimTouchScopeBone or 2
                speedVal = _G.KASHMIRYState.CustomTextData.AimTouchScopeSpeed or 40
                fovVal = _G.KASHMIRYState.CustomTextData.AimTouchScopeFOV or 20
                maxDistMeters = _G.KASHMIRYState.CustomTextData.AimTouchScopeDist or 300
                useVisCheck = _G.KASHMIRYConfig.AimTouchScopeVisCheck
                igKnock = _G.KASHMIRYConfig.AimTouchScopeIgKnock
                igBot = _G.KASHMIRYConfig.AimTouchScopeIgBot
                predVal = _G.KASHMIRYState.CustomTextData.AimTouchScopePred or 0
                recoilCompVal = _G.KASHMIRYState.CustomTextData.AimTouchScopeRecoil or 0
            else
                return
            end
        else
            if not _G.KASHMIRYConfig.AimTouchHipfire then return end
            cond = _G.KASHMIRYState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end 
            prioMode = _G.KASHMIRYState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = _G.KASHMIRYState.CustomTextData.AimTouchHipBone or 1
            speedVal = _G.KASHMIRYState.CustomTextData.AimTouchHipSpeed or 50
            fovVal = _G.KASHMIRYState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.KASHMIRYState.CustomTextData.AimTouchHipDist or 250
            useVisCheck = _G.KASHMIRYConfig.AimTouchHipVisCheck
            igKnock = _G.KASHMIRYConfig.AimTouchHipIgKnock
            igBot = _G.KASHMIRYConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100 

        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end
        
        -- Removed busy-wait delay (was causing lag)
        
        local FVector2D = import("Vector2D")
        local UGameplayStatics = import("GameplayStatics")
        local KismetMathLibrary = import("KismetMathLibrary")
        
        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not slua.isValid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end
        
        local ui_util = require("client.common.ui_util")
        if not ui_util then return end
        
        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        -- Randomly shift FOV slightly to avoid perfect consistency
        FOV_RADIUS = FOV_RADIUS * (1 + (math.random() - 0.5) * 0.1)
        
        local bestTarget = nil
        local bestScore = 99999999 
        
        local selBoneName = "head"
        -- Randomly switch bone 5% of the time to avoid perfect headshots
        if math.random() < 0.05 and not isShotgun and not isSniper then
            local bones = {"head", "spine_03", "spine_01", "pelvis"}
            selBoneName = bones[math.random(#bones)]
        else
            if boneIdx == 1 then selBoneName = "head"
            elseif boneIdx == 2 then selBoneName = "spine_03"
            elseif boneIdx == 3 then selBoneName = "spine_01"
            elseif boneIdx == 4 then selBoneName = "pelvis" end
        end

        for i, target in ipairs(enemies) do
            if not slua.isValid(target) then goto continue end
            
            pcall(function()
                if slua.isValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)
            
            if igKnock and target.HealthStatus == 1 then goto continue end
            
            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then goto continue end
            end
            
            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                _G.AimTouchVisCache = _G.AimTouchVisCache or {}
                if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _G.AimTouchVisCache[tId].hidden then goto continue end
            end
            
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            
            -- Add small random inaccuracy to aim point (spread)
            if math.random() < 0.1 then
                tPos.X = tPos.X + (math.random() - 0.5) * 20
                tPos.Y = tPos.Y + (math.random() - 0.5) * 20
                tPos.Z = tPos.Z + (math.random() - 0.5) * 20
            end
            
            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end
            
            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)
            
            if distScreen > FOV_RADIUS then goto continue end
            
            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then 
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end
            
            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
            
            ::continue::
        end
        
        if not slua.isValid(bestTarget) then return end
        
        -- Occasionally miss intentionally (1 in 20 shots)
        if math.random() < 0.05 and isFiring then
            return
        end
        
        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        
        if predVal > 0 then
            pcall(function()
                local tVelocity = nil
                if type(bestTarget.GetVelocity) == "function" then
                    tVelocity = bestTarget:GetVelocity()
                end
                
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0) 
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        
        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
                deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end

        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        local smoothFactor = 0.0
        if speedVal >= 100 then
            smoothFactor = 1.0
        else
            smoothFactor = (speedVal / 100.0) * 0.3
            if smoothFactor < 0.01 then smoothFactor = 0.01 end
        end
        
        -- Add random variation to smooth factor to avoid perfect consistency
        smoothFactor = smoothFactor * (1 + (math.random() - 0.5) * 0.2)
        
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
        local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        
        if recoilCompVal > 0 and isFiring then
            local pullDownForce = (recoilCompVal / 50.0) * 1.5
            finalPitch = finalPitch - pullDownForce
        end

        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }
        pc:SetControlRotation(finalRot, "AimTouch")
        
        if isShotgun and _G.KASHMIRYConfig.AimTouchSGAutoFire then
            pcall(function()
                local distToTarget = player:GetDistanceTo(bestTarget) / 100
                if distToTarget <= maxDistMeters then
                    player.bIsWeaponFiring = true
                    if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                    if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                    local wepMgr = player.WeaponManagerComponent
                    if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                    
                    local currentWep = player:GetCurrentWeapon()
                    if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then 
                        currentWep:StartFire() 
                    end
                    _G.KASHMIRYState.IsAutoFiring = true
                end
            end)
        end

    end)
end

-- ========================================== 
-- MAIN LOOP (ONLY CUSTOM RECOIL & AIMBOT V2)
-- ========================================== 
local function MainLoop() 
    if isExpired then return end

    if _G.KASHMIRYState.CustomTextData == nil then 
        _G.KASHMIRYState.CustomTextData = {
            HRecoil = 0.3, VRecoil = 0.3, 
            AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
            AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
            AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, 
            AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
            AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400,
            AimTouchSniperPred = 0
        }
    end

    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    if not Valid(localPlayer) then 
        if _G.LunarESP_V1_Reset then pcall(_G.LunarESP_V1_Reset) end
        if _G.MagicBullet_Reset then pcall(_G.MagicBullet_Reset) end
        return 
    end

    if _G.MagicBullet_Tick then pcall(_G.MagicBullet_Tick) end

    -- Recoil handling
    pcall(function()
        local weapon = nil
        pcall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then
                weapon = weaponManager:GetCurrentWeapon()
            end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end

        if Valid(weapon) then
            local entities = {}
            if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
            if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
            if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then 
                table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent) 
            end

            for _, entity in ipairs(entities) do
                local anyWeaponModOn = _G.KASHMIRYConfig.CustomHRecoil or _G.KASHMIRYConfig.CustomVRecoil or _G.KASHMIRYConfig.LessShake

                if anyWeaponModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKickADS = entity.RecoilKickADS,
                        }
                    end
                    
                    if _G.KASHMIRYConfig.CustomHRecoil then entity.AccessoriesHRecoilFactor = _G.KASHMIRYState.CustomTextData.HRecoil or 0.3 end
                    if _G.KASHMIRYConfig.CustomVRecoil then entity.AccessoriesVRecoilFactor = _G.KASHMIRYState.CustomTextData.VRecoil or 0.3 end
                    if _G.KASHMIRYConfig.LessShake then entity.RecoilKickADS = 0.0 end
                    
                    entity.KASHMIRYWeaponModsActive = true

                elseif entity.KASHMIRYWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKickADS = orig.RecoilKickADS
                    end
                    entity.KASHMIRYWeaponModsActive = false
                end
            end
        end
    end)

    -- HiggsBoson disable (kept)
    pcall(function()
        if Valid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false end
        end
    end)
end

_G.KASHMIRYState.LoopToken = (_G.KASHMIRYState.LoopToken or 0) + 1 
local myToken = _G.KASHMIRYState.LoopToken

-- ========================================== 
-- LOOP UTAMA (0.2 DETIK)
-- ========================================== 
local function FastTick() 
    if isExpired then 
        if not _G.KASHMIRYNotifiedExpire then
            Notify("MOD HAS EXPIRED! PLEASE CONTACT ADMIN TO RENEW!\nTelegram @DR_SUBHAN")
            _G.KASHMIRYNotifiedExpire = true
        end
        return 
    end

    if myToken ~= _G.KASHMIRYState.LoopToken then return end
    ShowKASHMIRYVIPMenu()
    pcall(MainLoop) 
    local okTicker, ticker = pcall(require, "common.time_ticker") 
    if okTicker and ticker and ticker.AddTimerOnce then 
        ticker.AddTimerOnce(0.4, FastTick) 
    end 
end

-- ========================================== 
-- LOOP AIMBOT (0.016 DETIK)
-- ========================================== 
local aimbotToken = 0
local function FastAimbotTick()
    if isExpired then return end
    if aimbotToken ~= _G.KASHMIRYState.AimbotLoopToken then return end

    pcall(function()
        if _G.KASHMIRYConfig.AimTouchEnable then
            _G.AimTouch()
        end
    end)

    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.016, FastAimbotTick)
    end
end

-- ========================================== 
-- LOOP ESP V1 (0.02 DETIK) - only draws while the Master switch is ON
-- ========================================== 
local espToken = 0
local espWasOn = false
local function FastESPTick()
    if isExpired then return end
    if espToken ~= _G.KASHMIRYState.ESPLoopToken then return end

    pcall(function()
        local master = _G.g_Botmater_VIPShotESP and _G.g_Botmater_VIPShotESP.Enabled == true
        if master then
            espWasOn = true
            if _G.LunarESP_V1_Tick then _G.LunarESP_V1_Tick() end
        elseif espWasOn then
            espWasOn = false
            if _G.LunarESP_V1_Reset then _G.LunarESP_V1_Reset() end
        end
    end)

    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.02, FastESPTick)
    end
end

-- ========================================== 
-- START LOOPS & BYPASS RE-APPLY
-- ========================================== 
if not isExpired then
    -- Start main and aimbot loops
    FastTick() 
    _G.KASHMIRYState.AimbotLoopToken = (_G.KASHMIRYState.AimbotLoopToken or 0) + 1
    aimbotToken = _G.KASHMIRYState.AimbotLoopToken
    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.1, FastAimbotTick)
    end

    -- Start ESP V1 loop (does nothing until the Master switch is turned ON)
    _G.KASHMIRYState.ESPLoopToken = (_G.KASHMIRYState.ESPLoopToken or 0) + 1
    espToken = _G.KASHMIRYState.ESPLoopToken
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.15, FastESPTick)
    end

    -- Start re-apply bypass timer (every 60s - less frequent)
    ReapplyBypassTimer()
    
    Notify("VIP Mod Active – Aimbot V2 + Enhanced Bypass (Optimised, Lag-Free). Telegram: @DR_SUBHAN")
else
    FastTick() 
end

-- ===================================================================================
-- SYSTEM HOOKS BYPASS (initial call)
-- ===================================================================================
local function InitAllModSystems()
    if isExpired then return end 
    pcall(function()
        if _G.StartBypass_VIP_v3 then _G.StartBypass_VIP_v3() end
        EnhancedDynamicBypass() -- extra layer
    end)
end

if not isExpired then
    pcall(function() 
        require("common.time_ticker").AddTimerOnce(0.5, InitAllModSystems) 
    end)
end

-- ==============================================================================
-- ================== THE RETURN SECTION RETAINS THE ORIGINAL CODE. ===================
-- ==============================================================================
local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  }
}, "BRPlayerCharacterBase")
