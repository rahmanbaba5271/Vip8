function _G.InitAKESPVIP()
    if _G.AK_ESP_VIP_Init then return end
    _G.AK_ESP_VIP_Init = true

    if _G.AK_PlayerMapMarker and type(_G.AK_PlayerMapMarker.Stop) == "function" then
        pcall(function() _G.AK_PlayerMapMarker.Stop() end)
        pcall(function() _G.AK_PlayerMapMarker.ClearAllMarks() end)
        _G.AK_PlayerMapMarker.bActive = false
    end
    if _G.AK_RedBoxOverlay and type(_G.AK_RedBoxOverlay.Stop) == "function" then
        pcall(function() _G.AK_RedBoxOverlay.Stop() end)
    end
    
    local AK_PlayerMapMarker = {}

    local AK_RedBoxOverlay = {
        bActive = false,
        MainContainer = nil,
        WidgetSlot = nil,
        TextBlock = nil,
        Width = 300,
        Height = 23,           
        OffsetY = 10,          
        PlayerCount = 0,
        BotCount = 0,
        NearCount = 0,
        FontSize = 16,          
        TextScaleValue = 0.8,   
        NumLayers = 50,
        Red = 1.0,
        Green = 0.0,
        Blue = 0.0,
        LayerAlpha = 0.038,
        _CachedText = "",
        _CachedPosVec = nil
    }

    function AK_RedBoxOverlay.Create()
        if AK_RedBoxOverlay.MainContainer and slua.isValid(AK_RedBoxOverlay.MainContainer) then return true end

        local ParentCanvas = AK_PlayerMapMarker.ESPCanvas
        if not ParentCanvas or not slua.isValid(ParentCanvas) then 
            if not AK_PlayerMapMarker.InitESPCanvas() then return false end
            ParentCanvas = AK_PlayerMapMarker.ESPCanvas
        end

        local Container = nil
        pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
        if not Container or not slua.isValid(Container) then return false end

        local FLinearColor = import("LinearColor") or _G.FLinearColor
        local FVector2D = import("Vector2D") or _G.FVector2D
        local color = FLinearColor(AK_RedBoxOverlay.Red, AK_RedBoxOverlay.Green, AK_RedBoxOverlay.Blue, AK_RedBoxOverlay.LayerAlpha)

        local numLayers = AK_RedBoxOverlay.NumLayers
        local totalWidth = AK_RedBoxOverlay.Width

        for i = 1, numLayers do
            local progress = (i / numLayers) ^ 1.15
            local layerWidth = progress * totalWidth
            local layerX = (totalWidth - layerWidth) / 2.0

            local border = nil
            pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
            if border and slua.isValid(border) then
                pcall(function() border:SetBrushColor(color); border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                local slot = Container:AddChildToCanvas(border)
                if slot then slot:SetPosition(FVector2D(layerX, 0)); slot:SetSize(FVector2D(layerWidth, AK_RedBoxOverlay.Height)) end
            end
        end

        local txtWidget = nil
        pcall(function() txtWidget = CGame:NewObjectFromPath("/Script/UMG.TextBlock", Container) end)

        if txtWidget and slua.isValid(txtWidget) then
            pcall(function()
                local strText = "PLAYER: " .. tostring(AK_RedBoxOverlay.PlayerCount) .. "   BOT: " .. tostring(AK_RedBoxOverlay.BotCount) .. "   400M: " .. tostring(AK_RedBoxOverlay.NearCount)
                txtWidget:SetText(strText)
                AK_RedBoxOverlay._CachedText = strText
                local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                if FSlateColor then txtWidget:SetColorAndOpacity(FSlateColor(FLinearColor(1, 1, 1, 1))) else txtWidget:SetColorAndOpacity(FLinearColor(1, 1, 1, 1)) end
                if txtWidget.Font then local font = txtWidget.Font; font.Size = AK_RedBoxOverlay.FontSize; txtWidget.Font = font end
                txtWidget:SetRenderScale(FVector2D(AK_RedBoxOverlay.TextScaleValue, AK_RedBoxOverlay.TextScaleValue))
                txtWidget:SetRenderTransformPivot(FVector2D(0.5, 0.5))
                txtWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local txtSlot = Container:AddChildToCanvas(txtWidget)
            if txtSlot then
                pcall(function() txtSlot:SetAutoSize(true); txtSlot:SetAlignment(FVector2D(0.5, 0.5)); txtSlot:SetPosition(FVector2D(totalWidth * 0.5, AK_RedBoxOverlay.Height * 0.5)); txtSlot:SetZOrder(1000) end)
            end
            AK_RedBoxOverlay.TextBlock = txtWidget
        end

        local MainSlot = nil
        pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
        if not MainSlot then return false end

        AK_RedBoxOverlay.MainContainer = Container
        AK_RedBoxOverlay.WidgetSlot = MainSlot
        
        pcall(function() MainSlot:SetAutoSize(false); MainSlot:SetZOrder(999); MainSlot:SetAlignment(FVector2D(0.5, 0.0)); MainSlot:SetSize(FVector2D(AK_RedBoxOverlay.Width, AK_RedBoxOverlay.Height)) end)
        AK_RedBoxOverlay.UpdatePosition()
        return true
    end

    function AK_RedBoxOverlay.SetCounts(players, bots, near400)
        if AK_RedBoxOverlay.PlayerCount == players and AK_RedBoxOverlay.BotCount == bots and AK_RedBoxOverlay.NearCount == near400 then
            return
        end
        AK_RedBoxOverlay.PlayerCount = players or 0
        AK_RedBoxOverlay.BotCount = bots or 0
        AK_RedBoxOverlay.NearCount = near400 or 0
        
        if AK_RedBoxOverlay.TextBlock and slua.isValid(AK_RedBoxOverlay.TextBlock) then
            pcall(function()
                local strText = "PLAYER: " .. tostring(AK_RedBoxOverlay.PlayerCount) .. "   BOT: " .. tostring(AK_RedBoxOverlay.BotCount) .. "   400M: " .. tostring(AK_RedBoxOverlay.NearCount)
                if AK_RedBoxOverlay._CachedText ~= strText then
                    AK_RedBoxOverlay.TextBlock:SetText(strText)
                    AK_RedBoxOverlay._CachedText = strText
                end
            end)
        end
    end

    function AK_RedBoxOverlay.UpdatePosition()
        local Slot = AK_RedBoxOverlay.WidgetSlot
        if not Slot or not slua.isValid(Slot) then return end

        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if not slua.isValid(PC) then return end

        local fromX, fromY = AK_PlayerMapMarker.GetSnapLineStartPos(PC)

        pcall(function()
            if not AK_RedBoxOverlay._CachedPosVec then
                AK_RedBoxOverlay._CachedPosVec = import("Vector2D")(fromX, fromY)
            else
                AK_RedBoxOverlay._CachedPosVec.X = fromX
                AK_RedBoxOverlay._CachedPosVec.Y = fromY
            end
            Slot:SetPosition(AK_RedBoxOverlay._CachedPosVec)
        end)
    end

    function AK_RedBoxOverlay.Start()
        if AK_RedBoxOverlay.bActive and AK_RedBoxOverlay.MainContainer and slua.isValid(AK_RedBoxOverlay.MainContainer) then return end
        if AK_RedBoxOverlay.Create() then
            AK_RedBoxOverlay.bActive = true
            pcall(function()
                AK_RedBoxOverlay.MainContainer:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
        end
    end

    function AK_RedBoxOverlay.Stop()
        AK_RedBoxOverlay.bActive = false
        if AK_RedBoxOverlay.MainContainer and slua.isValid(AK_RedBoxOverlay.MainContainer) then
            pcall(function()
                AK_RedBoxOverlay.MainContainer:RemoveFromParent()
                AK_RedBoxOverlay.MainContainer:ConditionalBeginDestroy()
            end)
        end
        AK_RedBoxOverlay.MainContainer = nil
        AK_RedBoxOverlay.WidgetSlot = nil
        AK_RedBoxOverlay.TextBlock = nil
        AK_RedBoxOverlay._CachedPosVec = nil
    end

    _G.AK_RedBoxOverlay = AK_RedBoxOverlay

    local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")

    local SlateBlueprintLibrary = nil
    local WidgetLayoutLibrary = nil
    local KismetMathLibrary = nil
    local KismetSystemLibrary = nil

    pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
    pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
    pcall(function() KismetMathLibrary = import("KismetMathLibrary") end)
    pcall(function() KismetSystemLibrary = import("KismetSystemLibrary") end)

    AK_PlayerMapMarker.MarkTypeID = 1007
    AK_PlayerMapMarker.bUseScreenESP = true
    AK_PlayerMapMarker.bUseScreenMark = false
    AK_PlayerMapMarker.bUseQuickSign = false
    AK_PlayerMapMarker.bUseNavigator = false
    AK_PlayerMapMarker.bUseWidgetComponent = false
    AK_PlayerMapMarker.QuickSignConfigKey = "C_MarkPos"

    AK_PlayerMapMarker.WidgetCompUIPath = "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips"
    AK_PlayerMapMarker.WidgetCompBoneName = "head"
    AK_PlayerMapMarker.WidgetCompOffset = FVector(0, 0, 80)
    AK_PlayerMapMarker.WidgetCompDrawSize = FVector2D(300, 50)

    AK_PlayerMapMarker.ESPBoneName = "head"
    AK_PlayerMapMarker.ESPWorldOffsetZ = 0
    AK_PlayerMapMarker.ESPScreenOffsetY = 0

    AK_PlayerMapMarker.ESPAnchorOffsetX = 50
    AK_PlayerMapMarker.ESPAnchorOffsetY = 0
    AK_PlayerMapMarker.ESPTextOffsetX = 0
    AK_PlayerMapMarker.ESPTextOffsetY = 0

    AK_PlayerMapMarker.ESPWidgetAlignment = FVector2D(0.5, 1.0)
    AK_PlayerMapMarker.ESPWidgetSize = FVector2D(100, 30)
    AK_PlayerMapMarker.ESPWidgetAutoSize = true
    AK_PlayerMapMarker.ESPWidgetZOrder = 2

    AK_PlayerMapMarker.bShowDistance = true
    AK_PlayerMapMarker.DistanceUnit = "m"

    AK_PlayerMapMarker.WeaponIconBrushW = 138
    AK_PlayerMapMarker.WeaponIconBrushH = 69
    AK_PlayerMapMarker.HPWidgetSwitcherTypeIndex = 0
    AK_PlayerMapMarker.HPWidgetSwitcherType2Index = 0
    AK_PlayerMapMarker.bForceSwitcherIndexEveryUpdate = true

    AK_PlayerMapMarker.bUseSnapLines = true
    AK_PlayerMapMarker.SnapLineThickness = 1
    AK_PlayerMapMarker.SnapLineOriginY = 50
    AK_PlayerMapMarker.SnapLineOriginOffsetX = 0
    AK_PlayerMapMarker.SnapLineHeadOffsetX = 0
    AK_PlayerMapMarker.SnapLineHeadOffsetY = -20
    AK_PlayerMapMarker.SnapLineColor = nil
    AK_PlayerMapMarker.SnapLineOpacity = 0.7

    AK_PlayerMapMarker.MapAddedFlag = 4
    AK_PlayerMapMarker.nUpdateInterval = 0.5

    AK_PlayerMapMarker.bUseFrameTick = false
    AK_PlayerMapMarker.nHeavyScanFrameInterval = 15
    AK_PlayerMapMarker.nDistanceUpdateFrameInterval = 5

    AK_PlayerMapMarker.bIncludeMe = false
    AK_PlayerMapMarker.bIncludeAI = true
    AK_PlayerMapMarker.bUseServerMarks = false

    AK_PlayerMapMarker.bActive = false
    AK_PlayerMapMarker.MarkMap = {}
    AK_PlayerMapMarker.PlayerInfo = {}

    AK_PlayerMapMarker.ESPCanvas = nil
    AK_PlayerMapMarker.ESPWidgets = {}
    AK_PlayerMapMarker.ESPWidgetPtrs = {}
    AK_PlayerMapMarker.SnapLineWidgets = {}

    AK_PlayerMapMarker.BoxWidgets = {}
    AK_PlayerMapMarker.HealthWidgets = {}
    AK_PlayerMapMarker.CustomTextWidgets = {}

    function AK_PlayerMapMarker.CreateBoxLine()
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then return nil end
        local Border = nil
        pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", AK_PlayerMapMarker.ESPCanvas) end)
        if not Border or not slua.isValid(Border) then return nil end
        pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        pcall(function() Border.RenderTransformPivot = FVector2D(0.0, 0.0) end)
        pcall(function() Border:SetRenderTransformPivot(FVector2D(0.0, 0.0)) end)
        local Slot = nil
        pcall(function()
            Slot = AK_PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
            if Slot then
                Slot:SetAutoSize(false)
                Slot:SetZOrder(1)
            end
        end)
        return { Widget = Border, Slot = Slot, _vis = 2 }
    end

    function AK_PlayerMapMarker.Update2DBox(KeyStr, topPos, bottomPos, color, isVisible)
        AK_PlayerMapMarker.BoxWidgets = AK_PlayerMapMarker.BoxWidgets or {}
        local box = AK_PlayerMapMarker.BoxWidgets[KeyStr]

        if not isVisible then
            if box then
                for i = 1, 4 do
                    local line = box[i]
                    if line and line.Widget and slua.isValid(line.Widget) and line._vis ~= 2 then
                        pcall(function() line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        line._vis = 2
                    end
                end
            end
            return
        end

        if not box then
            box = { AK_PlayerMapMarker.CreateBoxLine(), AK_PlayerMapMarker.CreateBoxLine(), AK_PlayerMapMarker.CreateBoxLine(), AK_PlayerMapMarker.CreateBoxLine() }
            AK_PlayerMapMarker.BoxWidgets[KeyStr] = box
        end

        local height = bottomPos.Y - topPos.Y
        local width = height * 0.55
        local centerX = bottomPos.X 
        
        local tX = centerX - (width / 2)
        local tY = topPos.Y
        local bX = centerX - (width / 2)
        local bY = bottomPos.Y
        local thick = 1.3

        local lines = {
            { x = tX, y = tY, w = width, h = thick },  
            { x = bX, y = bY, w = width, h = thick },  
            { x = tX, y = tY, w = thick, h = height },  
            { x = tX + width, y = tY, w = thick, h = height + thick }  
        }

        for i = 1, 4 do
            local line = box[i]
            if line and line.Widget and line.Slot then
                if line._vis ~= 0 then
                    pcall(function() line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    line._vis = 0
                end
                
                pcall(function() line.Widget:SetBrushColor(color) end)
                
                local nx, ny = lines[i].x, lines[i].y
                local nw, nh = lines[i].w, lines[i].h
                
                if not line._CachedPos or math.abs(line._CachedPos.X - nx) > 0.5 or math.abs(line._CachedPos.Y - ny) > 0.5 or
                   not line._CachedSize or math.abs(line._CachedSize.X - nw) > 0.5 or math.abs(line._CachedSize.Y - nh) > 0.5 then
                   
                    line._CachedPos = line._CachedPos or FVector2D(nx, ny)
                    line._CachedSize = line._CachedSize or FVector2D(nw, nh)
                    line._CachedPos.X, line._CachedPos.Y = nx, ny
                    line._CachedSize.X, line._CachedSize.Y = nw, nh
                    
                    pcall(function()
                        line.Slot:SetPosition(line._CachedPos)
                        line.Slot:SetSize(line._CachedSize)
                    end)
                end
            end
        end
    end

    function AK_PlayerMapMarker.Update2DHealthBar(KeyStr, topPos, bottomPos, pct, isVisible)
        AK_PlayerMapMarker.HealthWidgets = AK_PlayerMapMarker.HealthWidgets or {}
        local hpBox = AK_PlayerMapMarker.HealthWidgets[KeyStr]

        if not isVisible then
            if hpBox then
                if hpBox.bg and hpBox.bg.Widget and slua.isValid(hpBox.bg.Widget) and hpBox.bg._vis ~= 2 then 
                    pcall(function() hpBox.bg.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); hpBox.bg._vis = 2 
                end
                if hpBox.fg and hpBox.fg.Widget and slua.isValid(hpBox.fg.Widget) and hpBox.fg._vis ~= 2 then 
                    pcall(function() hpBox.fg.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); hpBox.fg._vis = 2 
                end
            end
            return
        end

        if not hpBox then
            hpBox = { bg = AK_PlayerMapMarker.CreateBoxLine(), fg = AK_PlayerMapMarker.CreateBoxLine() }
            AK_PlayerMapMarker.HealthWidgets[KeyStr] = hpBox
        end

        local barTopY = topPos.Y - 14
        local barBottomY = bottomPos.Y + 14
        local barHeight = barBottomY - barTopY

        local boxHeight = bottomPos.Y - topPos.Y
        local boxWidth = boxHeight * 0.55
        local barWidth = 4.0
        local padding = 5.0
        local centerX = bottomPos.X

        local mode = _G.AK_GetVal("ESP_HEALTH_POS") or 1
        local bgX, bgY, bgW, bgH
        local fgX, fgY, fgW, fgH

        if mode == 2 then 
            bgX = centerX + (boxWidth / 2) + padding
            bgY = barTopY
            bgW = barWidth
            bgH = barHeight
            
            fgX = bgX
            fgH = barHeight * pct
            fgY = barBottomY - fgH
            fgW = barWidth

        elseif mode == 3 then
            bgX = centerX - (barHeight / 2)
            bgY = topPos.Y - 11
            bgW = barHeight
            bgH = barWidth
            
            fgX = bgX
            fgY = bgY
            fgW = barHeight * pct
            fgH = barWidth

        elseif mode == 4 then
            bgX = centerX - (barHeight / 2)
            bgY = bottomPos.Y + 7
            bgW = barHeight
            bgH = barWidth
            
            fgX = bgX
            fgY = bgY
            fgW = barHeight * pct
            fgH = barWidth

        else
            bgX = centerX - (boxWidth / 2) - padding - barWidth
            bgY = barTopY
            bgW = barWidth
            bgH = barHeight
            
            fgX = bgX
            fgH = barHeight * pct
            fgY = barBottomY - fgH
            fgW = barWidth
        end

        local hpColor = FLinearColor(0, 1, 0, 1)  
        if pct < 0.25 then 
            hpColor = FLinearColor(1, 0, 0, 1)  
        elseif pct < 0.60 then 
            hpColor = FLinearColor(1, 1, 0, 1) 
        end
        local bgColor = FLinearColor(0, 0, 0, 0.7)

        local drawLine = function(lineData, x, y, w, h, col)
            if lineData and lineData.Widget and lineData.Slot then
                if lineData._vis ~= 0 then
                    pcall(function() lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    lineData._vis = 0
                end
                
                pcall(function() lineData.Widget:SetBrushColor(col) end)
                
                if not lineData._CachedPos or math.abs(lineData._CachedPos.X - x) > 0.01 or math.abs(lineData._CachedPos.Y - y) > 0.01 or
                   not lineData._CachedSize or math.abs(lineData._CachedSize.X - w) > 0.01 or math.abs(lineData._CachedSize.Y - h) > 0.01 then
                   
                    lineData._CachedPos = lineData._CachedPos or FVector2D(x, y)
                    lineData._CachedSize = lineData._CachedSize or FVector2D(w, h)
                    lineData._CachedPos.X, lineData._CachedPos.Y = x, y
                    lineData._CachedSize.X, lineData._CachedSize.Y = w, h
                    
                    pcall(function()
                        lineData.Slot:SetPosition(lineData._CachedPos)
                        lineData.Slot:SetSize(lineData._CachedSize)
                    end)
                end
            end
        end

        drawLine(hpBox.bg, bgX, bgY, bgW, bgH, bgColor)
        drawLine(hpBox.fg, fgX, fgY, fgW, fgH, hpColor)
    end

    function AK_PlayerMapMarker.CreateTextLine()
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then return nil end
        local TxtWidget = nil
        pcall(function() TxtWidget = CGame:NewObjectFromPath("/Script/UMG.TextBlock", AK_PlayerMapMarker.ESPCanvas) end)
        if not TxtWidget or not slua.isValid(TxtWidget) then return nil end
        
        pcall(function() TxtWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        pcall(function() TxtWidget.RenderTransformPivot = FVector2D(0.5, 0.5) end)
        pcall(function() TxtWidget:SetRenderTransformPivot(FVector2D(0.5, 0.5)) end)
        pcall(function() TxtWidget:SetJustification(1) end)

        local Slot = nil
        pcall(function()
            Slot = AK_PlayerMapMarker.ESPCanvas:AddChildToCanvas(TxtWidget)
            if Slot then Slot:SetAutoSize(true); Slot:SetAlignment(FVector2D(0.5, 0.5)); Slot:SetZOrder(3) end
        end)
        return { Widget = TxtWidget, Slot = Slot, _vis = 2 }
    end

    function AK_PlayerMapMarker.Update2DTextData(KeyStr, topPos, bottomPos, nameStr, distStr, teamIDStr, isVisible, espColor)
        AK_PlayerMapMarker.CustomTextWidgets = AK_PlayerMapMarker.CustomTextWidgets or {}
        local tBox = AK_PlayerMapMarker.CustomTextWidgets[KeyStr]

        if not isVisible then
            if tBox then
                if tBox.nameTxt and tBox.nameTxt.Widget and slua.isValid(tBox.nameTxt.Widget) and tBox.nameTxt._vis ~= 2 then 
                    pcall(function() tBox.nameTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.nameTxt._vis = 2 
                end
                if tBox.distTxt and tBox.distTxt.Widget and slua.isValid(tBox.distTxt.Widget) and tBox.distTxt._vis ~= 2 then 
                    pcall(function() tBox.distTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.distTxt._vis = 2 
                end
                if tBox.botTxt and tBox.botTxt.Widget and slua.isValid(tBox.botTxt.Widget) and tBox.botTxt._vis ~= 2 then 
                    pcall(function() tBox.botTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.botTxt._vis = 2 
                end
            end
            return
        end

        if not tBox then
            tBox = { 
                nameTxt = AK_PlayerMapMarker.CreateTextLine(), 
                distTxt = AK_PlayerMapMarker.CreateTextLine(), 
                botTxt = AK_PlayerMapMarker.CreateTextLine() 
            }
            AK_PlayerMapMarker.CustomTextWidgets[KeyStr] = tBox
        end
        
        if not tBox.nameTxt then tBox.nameTxt = tBox.topTxt or AK_PlayerMapMarker.CreateTextLine() end
        if not tBox.distTxt then tBox.distTxt = AK_PlayerMapMarker.CreateTextLine() end

        local centerX = bottomPos.X

        local applyText = function(lineData, x, y, textStr, col, fontSize)
            if lineData and lineData.Widget and lineData.Slot then
                if lineData._vis ~= 0 then
                    pcall(function() lineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    lineData._vis = 0
                end
                
                if lineData._lastTxt ~= textStr then
                    pcall(function() lineData.Widget:SetText(textStr) end)
                    lineData._lastTxt = textStr
                end
                
                pcall(function()
                    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                    if FSlateColor then lineData.Widget:SetColorAndOpacity(FSlateColor(col)) 
                    else lineData.Widget:SetColorAndOpacity(col) end
                end)

                if not lineData._fontInit then
                    pcall(function()
                        if lineData.Widget.Font then 
                            local font = lineData.Widget.Font
                            font.Size = fontSize
                            font.OutlineSettings.OutlineSize = 1
                            font.OutlineSettings.OutlineColor = FLinearColor(0,0,0,1)
                            lineData.Widget:SetFont(font) 
                        end
                    end)
                    lineData._fontInit = true
                end

                if not lineData._CachedPos or math.abs(lineData._CachedPos.X - x) > 0.01 or math.abs(lineData._CachedPos.Y - y) > 0.01 then
                    lineData._CachedPos = lineData._CachedPos or FVector2D(x, y)
                    lineData._CachedPos.X, lineData._CachedPos.Y = x, y
                    pcall(function() lineData.Slot:SetPosition(lineData._CachedPos) end)
                end
            end
        end

        local hpMode = _G.AK_GetVal("ESP_HEALTH_POS") or 1
        local isShowHp = _G.AK_GetVal("ESP_HEALTH") == 1
        
        local yOffsetName = -26
        local yOffsetDist = -14
        local yOffsetTeam = 14
        
        if isShowHp then
            if hpMode == 3 then 
                yOffsetName = -35
                yOffsetDist = -23
            elseif hpMode == 4 then 
                yOffsetTeam = 23
            end
        end

        if nameStr ~= "" then
            applyText(tBox.nameTxt, centerX, topPos.Y + yOffsetName, nameStr, FLinearColor(1, 1, 1, 1), 10)
        else
            if tBox.nameTxt and tBox.nameTxt.Widget and slua.isValid(tBox.nameTxt.Widget) and tBox.nameTxt._vis ~= 2 then 
                pcall(function() tBox.nameTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.nameTxt._vis = 2 
            end
        end

        if distStr ~= "" then
            applyText(tBox.distTxt, centerX, topPos.Y + yOffsetDist, "[" .. distStr .. "]", FLinearColor(0, 1, 0, 1), 10)
        else
            if tBox.distTxt and tBox.distTxt.Widget and slua.isValid(tBox.distTxt.Widget) and tBox.distTxt._vis ~= 2 then 
                pcall(function() tBox.distTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.distTxt._vis = 2 
            end
        end

        if teamIDStr and teamIDStr ~= "" then
            local txtColor = espColor
            local numID = tonumber(teamIDStr)
            if numID then
                local specificColor = AK_PlayerMapMarker.GetTeamColor(numID)
                if specificColor then txtColor = specificColor end
            end
            
            applyText(tBox.botTxt, centerX, bottomPos.Y + yOffsetTeam, tostring(teamIDStr), txtColor, 10)
        else
            if tBox.botTxt and tBox.botTxt.Widget and slua.isValid(tBox.botTxt.Widget) and tBox.botTxt._vis ~= 2 then 
                pcall(function() tBox.botTxt.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); tBox.botTxt._vis = 2
            end
        end
    end

    function AK_PlayerMapMarker.Remove2DBox(KeyStr)
        local box = AK_PlayerMapMarker.BoxWidgets[KeyStr]
        if box then
            for i = 1, 4 do
                if box[i] and box[i].Widget and slua.isValid(box[i].Widget) then
                    pcall(function()
                        box[i].Widget:RemoveFromParent()
                        box[i].Widget:ConditionalBeginDestroy()
                    end)
                end
            end
            AK_PlayerMapMarker.BoxWidgets[KeyStr] = nil
        end
        
        local hpBox = AK_PlayerMapMarker.HealthWidgets[KeyStr]
        if hpBox then
            if hpBox.bg and slua.isValid(hpBox.bg.Widget) then pcall(function() hpBox.bg.Widget:RemoveFromParent(); hpBox.bg.Widget:ConditionalBeginDestroy() end) end
            if hpBox.fg and slua.isValid(hpBox.fg.Widget) then pcall(function() hpBox.fg.Widget:RemoveFromParent(); hpBox.fg.Widget:ConditionalBeginDestroy() end) end
            AK_PlayerMapMarker.HealthWidgets[KeyStr] = nil
        end

        local tBox = AK_PlayerMapMarker.CustomTextWidgets[KeyStr]
        if tBox then
            if tBox.topTxt and slua.isValid(tBox.topTxt.Widget) then pcall(function() tBox.topTxt.Widget:RemoveFromParent(); tBox.topTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.nameTxt and slua.isValid(tBox.nameTxt.Widget) then pcall(function() tBox.nameTxt.Widget:RemoveFromParent(); tBox.nameTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.distTxt and slua.isValid(tBox.distTxt.Widget) then pcall(function() tBox.distTxt.Widget:RemoveFromParent(); tBox.distTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.botTxt and slua.isValid(tBox.botTxt.Widget) then pcall(function() tBox.botTxt.Widget:RemoveFromParent(); tBox.botTxt.Widget:ConditionalBeginDestroy() end) end
            AK_PlayerMapMarker.CustomTextWidgets[KeyStr] = nil
        end
    end

    AK_PlayerMapMarker._cachedViewportW = 1920
    AK_PlayerMapMarker._cachedViewportH = 1080

    AK_PlayerMapMarker._FrameCount = 0
    AK_PlayerMapMarker._bTickRegistered = false
    AK_PlayerMapMarker._CachedAllChars = nil
    AK_PlayerMapMarker._CachedMyLoc = nil
    AK_PlayerMapMarker._CachedMyKey = nil

    AK_PlayerMapMarker.WidgetComps = {}
    AK_PlayerMapMarker._bAllPathsFailed = false

    AK_PlayerMapMarker._bLightUpdateScheduled = false
    AK_PlayerMapMarker._LightUpdateInterval = 0.02

    AK_PlayerMapMarker._bDistanceUpdateScheduled = false
    AK_PlayerMapMarker._DistanceUpdateInterval = 0.1

    local function AK_IsValid(obj)
        if obj == nil then return false end
        if slua and slua.isValid then return slua.isValid(obj) end
        return obj ~= nil
    end

    local function AK_SafeStr(val)
        if val == nil then return "nil" end
        return tostring(val)
    end

    local function AK_GetFVector(X, Y, Z)
        local VT = FVector
        if not VT then
            pcall(function() VT = import("/Script/CoreUObject.Vector") end)
        end
        if VT then
            local ok, vec = pcall(function() return VT(X or 0, Y or 0, Z or 0) end)
            if ok and vec then return vec end
        end
        return nil
    end

    local function AK_GetMapAddedFlag()
        if AK_PlayerMapMarker.MapAddedFlag ~= nil then
            return AK_PlayerMapMarker.MapAddedFlag
        end
        if UEnums and UEnums.EAddMarkFlag and UEnums.EAddMarkFlag.EAMF_Both then
            return UEnums.EAddMarkFlag.EAMF_Both
        end
        return 3
    end

    AK_PlayerMapMarker._bScreenMarkConfigSetup = false

    function AK_PlayerMapMarker.SetupScreenMarkConfig()
        if AK_PlayerMapMarker._bScreenMarkConfigSetup then return true end
        local bOK = false
        pcall(function()
            local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
            local ScreenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
            if ScreenMarkConfig then
                ScreenMarkConfig[1007] = {
                    UIPathName = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C",
                    MaxWidgetNum = 100,
                    MaxShowDistance = 6000000,
                    bBindOutScreen = false,
                    bBindBlocked = true,
                    bNeedPreLoad = true,
                    bIsBindingActor = true,
                    BindSocketName = "HelmetSocket",
                    WorldPositionOffset = FVector(0, 0, 80)
                }
                AK_PlayerMapMarker._bScreenMarkConfigSetup = true
                bOK = true
            end
        end)
        return bOK
    end

    function AK_PlayerMapMarker.GetGameplayData()
        if AK_PlayerMapMarker._CachedGameplayData then
            return AK_PlayerMapMarker._CachedGameplayData
        end
        local ok, GDP = pcall(function()
            return require("GameLua.GameCore.Data.GameplayData")
        end)
        if ok and GDP then
            AK_PlayerMapMarker._CachedGameplayData = GDP
            return GDP
        end
        return nil
    end

    function AK_PlayerMapMarker.GetMyPlayerController()
        local PC = AK_PlayerMapMarker._CachedPC
        if PC and AK_IsValid(PC) then
            return PC
        end
        local GDP = AK_PlayerMapMarker.GetGameplayData()
        if not GDP then return nil end
        pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
        if PC and AK_IsValid(PC) then
            AK_PlayerMapMarker._CachedPC = PC
            return PC
        end
        return nil
    end

    function AK_PlayerMapMarker.GetCGameState()
        if CGameState and AK_IsValid(CGameState) then
            return CGameState
        end
        if AK_PlayerMapMarker._CachedCGameState and AK_IsValid(AK_PlayerMapMarker._CachedCGameState) then
            return AK_PlayerMapMarker._CachedCGameState
        end
        local ok, GS = pcall(function()
            return require("GameLua.GameCore.Data.CGameState")
        end)
        if ok and GS then
            AK_PlayerMapMarker._CachedCGameState = GS
            return GS
        end
        return nil
    end

    function AK_PlayerMapMarker.GetAllCharacters()
        local AllChars = {}
        pcall(function()
            local Pawns = Game:GetAllPlayerPawns()
            if Pawns then
                for _, Pawn in pairs(Pawns) do
                    if Pawn and slua.isValid(Pawn) then
                        local pKey = nil
                        if Pawn.GetPlayerKey then
                            pKey = Pawn:GetPlayerKey()
                        end
                        if not pKey and Pawn.PlayerKey then
                            pKey = Pawn.PlayerKey
                        end
                        if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then
                            pKey = Pawn.PlayerState.PlayerKey
                        end
                        if pKey then
                            AllChars[pKey] = Pawn
                        end
                    end
                end
            end
        end)
        
        if not next(AllChars) then
            local GS = AK_PlayerMapMarker.GetCGameState()
            if GS and GS.GetAllCharacters then
                pcall(function() AllChars = GS:GetAllCharacters() end)
            end
        end
        
        return AllChars
    end

    function AK_PlayerMapMarker.GetMyPlayerKey()
        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if not AK_IsValid(PC) then return nil end
        local MyKey = nil
        pcall(function()
            if PC.GetPlayerKey then
                MyKey = PC:GetPlayerKey()
            elseif PC.PlayerState and PC.PlayerState.PlayerKey then
                MyKey = PC.PlayerState.PlayerKey
            end
        end)
        return MyKey
    end

    function AK_PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
        local bIsMe = false
        pcall(function()
            local GDP = AK_PlayerMapMarker.GetGameplayData()
            if GDP and GDP.GetLocalCharacter then
                local MyChar = GDP.GetLocalCharacter()
                if MyChar and Character == MyChar then
                    bIsMe = true
                    return
                end
            end
            local PC = AK_PlayerMapMarker.GetMyPlayerController()
            if PC and PC.GetPawn then
                local Pawn = PC:GetPawn()
                if Pawn and Character == Pawn then
                    bIsMe = true
                    return
                end
            end
        end)
        if not bIsMe and MyKey ~= nil and PlayerKey ~= nil then
            bIsMe = (tostring(PlayerKey) == tostring(MyKey))
        end
        return bIsMe
    end

    function AK_PlayerMapMarker.GetCharacterLocation(Character)
        if not AK_IsValid(Character) then return nil end
        local Loc = nil
        pcall(function()
            if Character.K2_GetActorLocation then
                Loc = Character:K2_GetActorLocation()
            end
        end)
        if not Loc then
            pcall(function()
                if Game and Game.GetActorLocation then
                    Loc = Game:GetActorLocation(Character)
                end
            end)
        end
        return Loc
    end

    function AK_PlayerMapMarker.CalcDistance(Loc1, Loc2)
        if not Loc1 or not Loc2 then return nil end
        local Dist = nil
        pcall(function()
            if FVector and FVector.Dist2D then
                Dist = FVector.Dist2D(Loc1, Loc2)
            end
        end)
        if not Dist then
            pcall(function()
                local DX = (Loc1.X or 0) - (Loc2.X or 0)
                local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
                Dist = math.sqrt(DX * DX + DY * DY)
            end)
        end
        return Dist
    end

    function AK_PlayerMapMarker.GetDistanceString(MyLoc, TargetLoc)
        if not AK_PlayerMapMarker.bShowDistance then return "" end
        if not MyLoc or not TargetLoc then return "" end
        local Dist = AK_PlayerMapMarker.CalcDistance(MyLoc, TargetLoc)
        if not Dist then return "" end
        local Meters = Dist / 100
        
        if Meters < 1000 then
            return tostring(math.floor(Meters)) .. "m"
        else
            local kmFloor = math.floor((Meters / 1000) * 10) / 10
            return tostring(kmFloor) .. "km"
        end
    end

    function AK_PlayerMapMarker.GetMyLocation()
        local GDP = AK_PlayerMapMarker.GetGameplayData()
        if not GDP then return nil end
        local MyChar = nil
        pcall(function() MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
        if not AK_IsValid(MyChar) then
            local PC = AK_PlayerMapMarker.GetMyPlayerController()
            if AK_IsValid(PC) then
                pcall(function()
                    if PC.GetPawn then
                        local Pawn = PC:GetPawn()
                        if AK_IsValid(Pawn) and Pawn.K2_GetActorLocation then
                            return Pawn:K2_GetActorLocation()
                        end
                    end
                end)
            end
            return nil
        end
        return AK_PlayerMapMarker.GetCharacterLocation(MyChar)
    end

    function AK_PlayerMapMarker.GetPlayerName(Character)
        if not AK_IsValid(Character) then return "Unknown" end
        local Name = nil
        pcall(function()
            if Character.GetPlayerNameSafety then
                Name = Character:GetPlayerNameSafety()
            end
        end)
        if not Name then
            pcall(function()
                local PS = nil
                if Character.GetPlayerStateSafety then
                    PS = Character:GetPlayerStateSafety()
                elseif Character.GetPlayerState then
                    PS = Character:GetPlayerState()
                end
                if AK_IsValid(PS) and PS.GetPlayerName then
                    Name = PS:GetPlayerName()
                end
            end)
        end
        return Name or "Unknown"
    end

    function AK_PlayerMapMarker.IsAI(Character)
        local bAI = false
        pcall(function()
            if Game and Game.IsAI then
                bAI = Game:IsAI(Character)
            end
        end)
        return bAI
    end

    function AK_PlayerMapMarker.IsAlive(Character)
        local bAlive = true
        pcall(function()
            if Character.IsAlive then
                bAlive = Character:IsAlive()
            end
        end)
        return bAlive
    end

    function AK_PlayerMapMarker.GetQuickSignComponent()
        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if not AK_IsValid(PC) then return nil end
        local QSC = nil
        pcall(function()
            if PC.GetQuickSignComponent then
                QSC = PC:GetQuickSignComponent()
            end
        end)
        if not AK_IsValid(QSC) then
            pcall(function()
                local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
                if STExtraBlueprintFunctionLibrary and STExtraBlueprintFunctionLibrary.GetQuickSignComponentFromController then
                    QSC = STExtraBlueprintFunctionLibrary.GetQuickSignComponentFromController(PC)
                end
            end)
        end
        return QSC
    end

    function AK_PlayerMapMarker.CreateQuickSignMark(Location)
        if not Location then return nil end
        local QSC = AK_PlayerMapMarker.GetQuickSignComponent()
        if not AK_IsValid(QSC) then return nil end
        local MsgID = nil
        pcall(function()
            if QSC.MakeCustomMark then
                MsgID = QSC:MakeCustomMark(Location, AK_PlayerMapMarker.QuickSignConfigKey)
            end
        end)
        return MsgID
    end

    function AK_PlayerMapMarker.RemoveQuickSignMark(MsgID)
        if not MsgID then return end
        local QSC = AK_PlayerMapMarker.GetQuickSignComponent()
        if not AK_IsValid(QSC) then return end
        pcall(function()
            if QSC.DealWithDelMsg then
                QSC:DealWithDelMsg(MsgID, false)
            end
        end)
    end

    AK_PlayerMapMarker._NavInstIDCounter = 1000
    AK_PlayerMapMarker.NavigatorUIPath = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C"
    AK_PlayerMapMarker.NavigatorbIsIcon = true

    function AK_PlayerMapMarker.CreateNavigatorMark(Location)
        if not Location then return nil end
        local InstID = AK_PlayerMapMarker._NavInstIDCounter
        AK_PlayerMapMarker._NavInstIDCounter = AK_PlayerMapMarker._NavInstIDCounter + 1
        local NavWidget = nil
        pcall(function()
            if UIManager and UIManager.UI_Config_InGame and UIManager.UI_Config_InGame.NavigatorPanel then
                NavWidget = UIManager.GetUI(UIManager.UI_Config_InGame.NavigatorPanel)
            end
        end)
        if not NavWidget then return nil end
        local Result = nil
        pcall(function()
            Result = InGameMarkTools.ClientAddMarkToNavigator(
                AK_PlayerMapMarker.NavigatorUIPath,
                Location,
                true,
                AK_PlayerMapMarker.NavigatorbIsIcon,
                nil,
                InstID
            )
        end)
        return InstID
    end

    function AK_PlayerMapMarker.UpdateNavigatorMark(InstID, Location)
        if not InstID or not Location then return end
        pcall(function()
            if not UIManager.UI_Config_InGame.NavigatorPanel then return end
            local NavigatorWidget = UIManager.GetUI(UIManager.UI_Config_InGame.NavigatorPanel)
            if not NavigatorWidget then return end
            if NavigatorWidget.UpdateCustomMarkLocation then
                NavigatorWidget:UpdateCustomMarkLocation(InstID, Location)
            end
        end)
    end

    function AK_PlayerMapMarker.RemoveNavigatorMark(InstID)
        if not InstID then return end
        pcall(function()
            InGameMarkTools.ClientDestroyMarkToNavigator(InstID)
        end)
    end

    function AK_PlayerMapMarker.IsOurESPWidget(w)
        if not w or not slua.isValid(w) then return false end
        local bIsOurs = false
        pcall(function()
            local wstr = tostring(w)
            for KeyStr, ESPData in pairs(AK_PlayerMapMarker.ESPWidgets) do
                if ESPData and ESPData.Widget and ESPData.Widget.Container then
                    local cstr = tostring(ESPData.Widget.Container)
                    if cstr == wstr then
                        bIsOurs = true
                        return
                    end
                end
            end
        end)
        if bIsOurs then return true end
        pcall(function()
            if w.GetChildrenCount then
                local n = w:GetChildrenCount()
                for i = 0, n - 1 do
                    local child = w:GetChildAt(i)
                    if child and slua.isValid(child) then
                        local cstr = tostring(child)
                        if string.find(cstr, "Border") then
                            bIsOurs = true
                            break
                        end
                    end
                end
            end
        end)
        if not bIsOurs then
            pcall(function()
                local slot = w.Slot
                if slot and slot.GetPosition then
                    local pos = slot:GetPosition()
                    if pos and (math.abs(pos.X or 0) > 1 or math.abs(pos.Y or 0) > 1) then
                        bIsOurs = true
                    end
                end
            end)
        end
        if not bIsOurs then
            pcall(function()
                local function checkForDist(w2, depth)
                    if not w2 or not slua.isValid(w2) or depth > 5 then return false end
                    if w2.GetText then
                        local txt = nil
                        pcall(function() txt = w2:GetText() end)
                        if txt then
                            local s = tostring(txt)
                            if string.find(s, "%[%d+m%]") or string.find(s, "Dist=") then
                                return true
                            end
                        end
                    end
                    local n = 0
                    pcall(function() if w2.GetChildrenCount then n = w2:GetChildrenCount() end end)
                    for j = 0, n - 1 do
                        local c = nil
                        pcall(function() c = w2:GetChildAt(j) end)
                        if c and checkForDist(c, depth + 1) then return true end
                    end
                    return false
                end
                bIsOurs = checkForDist(w, 0)
            end)
        end
        return bIsOurs
    end

    function AK_PlayerMapMarker.ApplyAnchorBasedPosition(Slot, ScreenPos, Canvas)
        if not Slot or not ScreenPos then return false end
        local sx = ScreenPos.X or 0
        local sy = ScreenPos.Y or 0
        local sz = AK_PlayerMapMarker.ESPWidgetSize or FVector2D(100, 30)
        local align = AK_PlayerMapMarker.ESPWidgetAlignment or FVector2D(0.5, 1.0)

        local canvasW, canvasH = 0, 0
        if AK_PlayerMapMarker._cachedViewportW and AK_PlayerMapMarker._cachedViewportW > 200 then
            canvasW = AK_PlayerMapMarker._cachedViewportW
            canvasH = AK_PlayerMapMarker._cachedViewportH
        end

        if canvasW < 200 then
            pcall(function()
                local PC = AK_PlayerMapMarker.GetMyPlayerController()
                if AK_IsValid(PC) and PC.GetViewportSize then
                    local VS = FVector2D(0, 0)
                    PC:GetViewportSize(VS)
                    if VS and VS.X and VS.X > 200 then
                        canvasW = VS.X
                        canvasH = VS.Y
                        AK_PlayerMapMarker._cachedViewportW = canvasW
                        AK_PlayerMapMarker._cachedViewportH = canvasH
                    end
                end
            end)
        end

        if canvasW < 200 and Canvas then
            pcall(function()
                local current = Canvas
                local depth = 0
                while current and depth < 20 do
                    local w, h = 0, 0
                    pcall(function()
                        if current.GetCachedGeometry then
                            local cg = current:GetCachedGeometry()
                            if cg then
                                if cg.GetAbsoluteSize then
                                    local cs = cg:GetAbsoluteSize()
                                    if cs then
                                        w = cs.X or 0
                                        h = cs.Y or 0
                                    end
                                end
                            end
                        end
                    end)
                    if w >= 200 and h >= 200 then
                        canvasW = w
                        canvasH = h
                        AK_PlayerMapMarker._cachedViewportW = w
                        AK_PlayerMapMarker._cachedViewportH = h
                        break
                    end
                    local parent = nil
                    pcall(function() if current.GetParent then parent = current:GetParent() end end)
                    if not parent then break end
                    current = parent
                    depth = depth + 1
                end
            end)
        end

        if canvasW > 200 and canvasH > 200 then
            local anchorX = (sx + (AK_PlayerMapMarker.ESPAnchorOffsetX or 0)) / canvasW
            local anchorY = (sy + (AK_PlayerMapMarker.ESPAnchorOffsetY or 0)) / canvasH
            anchorX = math.max(0, math.min(1, anchorX))
            anchorY = math.max(0, math.min(1, anchorY))

            local bSuccess = false
            pcall(function()
                if Slot.SetAnchors and FAnchors then
                    local anchors = FAnchors(anchorX, anchorY, anchorX, anchorY)
                    if anchors then
                        Slot:SetAnchors(anchors)
                        Slot:SetPosition(FVector2D(0, 0))
                        bSuccess = true
                    end
                end
            end)
            if not bSuccess then
                pcall(function()
                    if Slot.SetAnchors then
                        Slot:SetAnchors(anchorX, anchorY, anchorX, anchorY)
                        Slot:SetPosition(FVector2D(0, 0))
                        bSuccess = true
                    end
                end)
            end
            if bSuccess then
                pcall(function()
                    if Slot.SetOffsets and FMargin then
                        Slot:SetOffsets(FMargin(0, 0, sz.X, sz.Y))
                    end
                end)
                pcall(function() Slot:SetSize(sz) end)
                pcall(function() Slot:SetAlignment(align) end)
                pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(AK_PlayerMapMarker.ESPWidgetAutoSize or true) end end)
                pcall(function() if Slot.SetZOrder then Slot:SetZOrder(AK_PlayerMapMarker.ESPWidgetZOrder or 2) end end)
                return true
            end
        end

        pcall(function()
            Slot:SetPosition(FVector2D(sx, sy))
            pcall(function() Slot:SetSize(sz) end)
            pcall(function() Slot:SetAlignment(align) end)
            pcall(function() if Slot.SetAutoSize then Slot:SetAutoSize(AK_PlayerMapMarker.ESPWidgetAutoSize or true) end end)
            pcall(function() if Slot.SetZOrder then Slot:SetZOrder(AK_PlayerMapMarker.ESPWidgetZOrder or 2) end end)
        end)
        return false
    end

    function AK_PlayerMapMarker.InitESPCanvas()
        if AK_PlayerMapMarker.ESPCanvas and Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
            return true
        end

        local InGameUITools = nil
        pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
        if not InGameUITools then
            return false
        end

        local MainControlBaseUI = nil
        pcall(function() MainControlBaseUI = InGameUITools.GetMainControlBaseUI() end)
        if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then
            return false
        end

        local ParentCanvas = nil
        pcall(function()
            if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then
                ParentCanvas = MainControlBaseUI.CanvasPanel_0
            elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then
                ParentCanvas = MainControlBaseUI.CanvasPanel_42
            end
        end)

        if not ParentCanvas then
            return false
        end

        AK_PlayerMapMarker.ESPCanvas = ParentCanvas

        pcall(function()
            local nChildren = ParentCanvas:GetChildrenCount()
            for i = nChildren - 1, 0, -1 do
                local child = ParentCanvas:GetChildAt(i)
                if child and slua.isValid(child) then
                    if AK_PlayerMapMarker.IsOurESPWidget(child) then
                        pcall(function() ParentCanvas:RemoveChild(child) end)
                    end
                end
            end
        end)

        return true
    end

    function AK_PlayerMapMarker.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
        if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
        Depth = Depth or 0
        MaxDepth = MaxDepth or 5
        if Depth > MaxDepth then return nil end

        local bIsPB = false
        pcall(function()
            if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then
                bIsPB = true
            end
        end)
        if bIsPB then return WidgetObj end

        local nChildren = 0
        pcall(function()
            if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end
        end)

        for i = 0, math.max(nChildren - 1, 0) do
            local child = nil
            pcall(function() child = WidgetObj:GetChildAt(i) end)
            if child and slua.isValid(child) then
                local result = AK_PlayerMapMarker.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
                if result then return result end
            end
        end

        return nil
    end

    function AK_PlayerMapMarker.GetTeamID(Character)
        if not AK_IsValid(Character) then return nil end
        local TeamID = nil
        pcall(function()
            if Character.GetTeamID then TeamID = Character:GetTeamID() end
        end)
        if not TeamID then
            pcall(function()
                local PS = nil
                if Character.GetPlayerStateSafety then
                    PS = Character:GetPlayerStateSafety()
                elseif Character.GetPlayerState then
                    PS = Character:GetPlayerState()
                end
                if AK_IsValid(PS) and PS.GetTeamID then
                    TeamID = PS:GetTeamID()
                elseif AK_IsValid(PS) and PS.TeamID then
                    TeamID = PS.TeamID
                end
            end)
        end
        if not TeamID then
            pcall(function()
                if Character.TeamID then TeamID = Character.TeamID end
            end)
        end
        return TeamID
    end

    function AK_PlayerMapMarker.GetTeamColor(TeamID)
        if TeamID == nil then return nil end
        local TeamColors = {
            [1] = FLinearColor(1.0, 0.2, 0.2, 1.0),
            [2] = FLinearColor(0.2, 0.4, 1.0, 1.0),
            [3] = FLinearColor(0.2, 0.9, 0.3, 1.0),
            [4] = FLinearColor(1.0, 0.9, 0.2, 1.0),
            [5] = FLinearColor(0.8, 0.3, 1.0, 1.0),
            [6] = FLinearColor(0.2, 0.9, 0.9, 1.0),
            [7] = FLinearColor(1.0, 0.5, 0.2, 1.0),
            [8] = FLinearColor(1.0, 0.4, 0.7, 1.0),
        }
        local color = TeamColors[TeamID]
        if color then return color end
        if TeamID == 1 then
            return FLinearColor(1.0, 0.2, 0.2, 1.0)
        else
            return FLinearColor(0.2, 0.4, 1.0, 1.0)
        end
    end

    local _WhiteTexture = nil
    local _bWhiteTextureFailed = false

    local function GetWhiteTexture()
        if _WhiteTexture then return _WhiteTexture end
        if _bWhiteTextureFailed then return nil end
        pcall(function()
            local paths = {
                "/Game/BluePrints/UI/Textures/White.White",
                "/Game/BluePrints/UI/Textures/Common/White.White",
                "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture",
                "/Engine/EngineMaterials/DefaultWhiteGrid.DefaultWhiteGrid",
            }
            for _, path in ipairs(paths) do
                pcall(function()
                    local tex = import(path)
                    if tex and slua.isValid(tex) then
                        _WhiteTexture = tex
                        return
                    end
                end)
                if _WhiteTexture then break end
            end
        end)
        if not _WhiteTexture then
            _bWhiteTextureFailed = true
        end
        return _WhiteTexture
    end

    local function SetImageColor(Image, color)
        if not Image or not slua.isValid(Image) then return false end
        local bOK = false
        pcall(function()
            if Image.SetBrushTintColor then
                Image:SetBrushTintColor(color)
                bOK = true
            end
        end)
        pcall(function()
            if Image.SetBrushColor then
                Image:SetBrushColor(color)
                bOK = true
            end
        end)
        pcall(function()
            if Image.SetColorAndOpacity then
                Image:SetColorAndOpacity(color)
                bOK = true
            end
        end)
        pcall(function()
            if Image.SetTintColorAndOpacity then
                Image:SetTintColorAndOpacity(color)
                bOK = true
            end
        end)
        pcall(function()
            if Image.SetBrushFromTexture then
                local whiteTex = GetWhiteTexture()
                if whiteTex then
                    Image:SetBrushFromTexture(whiteTex, false)
                    if Image.SetColorAndOpacity then
                        Image:SetColorAndOpacity(color)
                    end
                    if Image.SetBrushTintColor then
                        Image:SetBrushTintColor(color)
                    end
                    bOK = true
                end
            end
        end)
        pcall(function()
            if Image.SetBrushFromAsset and not bOK then
                Image:SetBrushFromAsset("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture", false)
                if Image.SetColorAndOpacity then
                    Image:SetColorAndOpacity(color)
                end
                bOK = true
            end
        end)
        pcall(function() Image:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        pcall(function() Image:SetRenderOpacity(1.0) end)
        return bOK
    end

    function AK_PlayerMapMarker._GetWidgetRoot(WidgetObj)
        if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
        local Root = nil
        pcall(function()
            if WidgetObj.GetRootWidget then
                Root = WidgetObj:GetRootWidget()
            end
        end)
        if Root and slua.isValid(Root) then return Root end
        pcall(function()
            if WidgetObj.WidgetTree and WidgetObj.WidgetTree.RootWidget then
                Root = WidgetObj.WidgetTree.RootWidget
            end
        end)
        if Root and slua.isValid(Root) then return Root end
        pcall(function()
            if WidgetObj.RootWidget and slua.isValid(WidgetObj.RootWidget) then
                Root = WidgetObj.RootWidget
            end
        end)
        return Root
    end

    function AK_PlayerMapMarker._FindNamedWidgetInTree(WidgetObj, TargetName, MaxDepth)
        if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
        MaxDepth = MaxDepth or 8

        local wname = nil
        pcall(function()
            if WidgetObj.GetName then wname = WidgetObj:GetName() end
        end)
        if wname and wname == TargetName then return WidgetObj end

        local wstr = tostring(WidgetObj)
        if wstr and string.find(wstr, TargetName, 1, true) then
            if wname and wname == TargetName then
                return WidgetObj
            elseif not wname or wname == "" then
                local _, endPos = string.find(wstr, TargetName, 1, true)
                if endPos then
                    local nextChar = string.sub(wstr, endPos + 1, endPos + 1)
                    if nextChar ~= "_" and nextChar ~= "" then
                        return WidgetObj
                    end
                end
            end
        end

        local nChildren = 0
        pcall(function()
            if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end
        end)

        if nChildren > 0 then
            for i = 0, nChildren - 1 do
                local child = nil
                pcall(function() child = WidgetObj:GetChildAt(i) end)
                if child and slua.isValid(child) then
                    local found = AK_PlayerMapMarker._FindNamedWidgetInTree(child, TargetName, MaxDepth - 1)
                    if found then return found end
                end
            end
        else
            local Root = AK_PlayerMapMarker._GetWidgetRoot(WidgetObj)
            if Root and slua.isValid(Root) and Root ~= WidgetObj then
                local found = AK_PlayerMapMarker._FindNamedWidgetInTree(Root, TargetName, MaxDepth - 1)
                if found then return found end
            end
        end

        return nil
    end

    function AK_PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
        if not Widget or not Widget.Container then return end
        local color = AK_PlayerMapMarker.GetTeamColor(TeamID)
        if not color then return end

        pcall(function()
            local W = Widget.Container
            if not W or not slua.isValid(W) then return end

            if W.SetTeamColor then
                pcall(function() W:SetTeamColor(TeamID) end)
            end
            if W.SetTeamID then
                pcall(function() W:SetTeamID(TeamID) end)
            end
        end)
    end

    function AK_PlayerMapMarker.GetCharacterMesh(Character)
        if not AK_IsValid(Character) then return nil end
        local Mesh = nil
        pcall(function()
            if Character.Mesh and Game:IsValid(Character.Mesh) then
                Mesh = Character.Mesh
            end
        end)
        if not Mesh then
            pcall(function()
                local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent")
                Mesh = Character:GetComponentByClass(SkeletalMeshCompClass)
            end)
        end
        return Mesh
    end

    function AK_PlayerMapMarker.GetBoneLocation(Character, BoneName)
        if not AK_IsValid(Character) or not BoneName then return nil end
        local Mesh = AK_PlayerMapMarker.GetCharacterMesh(Character)
        if not Mesh or not Game:IsValid(Mesh) then return nil end
        local Loc = nil
        pcall(function()
            if Mesh.GetSocketLocation then
                Loc = Mesh:GetSocketLocation(BoneName)
            end
        end)
        if not Loc then
            pcall(function()
                if Mesh.GetBoneLocation then
                    Loc = Mesh:GetBoneLocation(BoneName)
                end
            end)
        end
        return Loc
    end

    function AK_PlayerMapMarker.ApplyWorldOffset(Loc, OffsetZ)
        if not Loc then return nil end
        if not OffsetZ or OffsetZ == 0 then return Loc end
        
        local ok = pcall(function()
            Loc.Z = Loc.Z + OffsetZ
        end)
        if ok then
            return Loc
        end

        local result = nil
        pcall(function()
            local X = Loc.X or 0
            local Y = Loc.Y or 0
            local Z = (Loc.Z or 0) + OffsetZ
            if FVector then
                result = FVector(X, Y, Z)
            end
        end)
        return result or Loc
    end

    function AK_PlayerMapMarker.GetESPLocation(Character)
        if not AK_IsValid(Character) then return nil end
        
        local BoneLoc = AK_PlayerMapMarker.GetCharacterLocation(Character)
        if BoneLoc then
            local heightOffset = 65
            pcall(function()
                if Character.bIsCrouched then heightOffset = 40 end
                if Character.IsProne and Character:IsProne() then heightOffset = 15 end
            end)
            BoneLoc = AK_PlayerMapMarker.ApplyWorldOffset(BoneLoc, heightOffset + (AK_PlayerMapMarker.ESPWorldOffsetZ or 0))
        end
        
        return BoneLoc
    end

    function AK_PlayerMapMarker.GetCharacterWeaponInfo(Character)
        if not AK_IsValid(Character) then return nil end

        local WeaponID = nil
        local WeaponName = nil
        local WeaponIconPath = nil
        local WeaponIconTexture = nil
        local CurrentWeapon = nil

        pcall(function()
            if Character.GetCurrentWeapon then
                CurrentWeapon = Character:GetCurrentWeapon()
            end
        end)
        
        if not CurrentWeapon then
            pcall(function()
                CurrentWeapon = Character.CurrentWeapon
            end)
        end

        if not CurrentWeapon then
            pcall(function()
                if Character.GetWeaponManager then
                    local WM = Character:GetWeaponManager()
                    if WM and WM.GetCurrentWeapon then
                        CurrentWeapon = WM:GetCurrentWeapon()
                    end
                end
            end)
        end

        if not CurrentWeapon then
            pcall(function()
                if Character.GetInventoryComponent then
                    local IC = Character:GetInventoryComponent()
                    if IC and IC.GetCurrentWeapon then
                        CurrentWeapon = IC:GetCurrentWeapon()
                    end
                end
            end)
        end

        if CurrentWeapon and AK_IsValid(CurrentWeapon) then
            pcall(function()
                if CurrentWeapon.GetWeaponID then
                    WeaponID = CurrentWeapon:GetWeaponID()
                end
            end)
            if not WeaponID then
                pcall(function()
                    WeaponID = CurrentWeapon.WeaponID
                end)
            end
            if not WeaponID then
                pcall(function()
                    if CurrentWeapon.GetItemID then
                        WeaponID = CurrentWeapon:GetItemID()
                    end
                end)
            end
            
            pcall(function()
                if CurrentWeapon.GetWeaponName then
                    WeaponName = CurrentWeapon:GetWeaponName()
                end
            end)
            if not WeaponName then
                pcall(function()
                    WeaponName = CurrentWeapon.WeaponName
                end)
            end
            
            pcall(function()
                if CurrentWeapon.GetWeaponIconPath then
                    WeaponIconPath = CurrentWeapon:GetWeaponIconPath()
                end
            end)
            if not WeaponIconPath then
                pcall(function()
                    WeaponIconPath = CurrentWeapon.IconPath
                end)
            end
            
            pcall(function()
                if CurrentWeapon.GetWeaponIcon then
                    WeaponIconTexture = CurrentWeapon:GetWeaponIcon()
                end
            end)
            if not WeaponIconTexture then
                pcall(function()
                    WeaponIconTexture = CurrentWeapon.IconTexture
                end)
            end
        end

        if not WeaponID then
            pcall(function()
                local PS = nil
                if Character.GetPlayerStateSafety then
                    PS = Character:GetPlayerStateSafety()
                elseif Character.GetPlayerState then
                    PS = Character:GetPlayerState()
                end
                if PS and AK_IsValid(PS) then
                    if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                    if not WeaponID and PS.CurrentWeaponID then WeaponID = PS.CurrentWeaponID end
                    if not WeaponID and PS.WeaponID then WeaponID = PS.WeaponID end
                    if not WeaponID and PS.HoldWeaponID then WeaponID = PS.HoldWeaponID end
                    if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
                    if not WeaponID and PS.EquipWeaponID then WeaponID = PS.EquipWeaponID end
                end
            end)
        end
        
        if not WeaponID then
            pcall(function()
                if Character.WeaponID then WeaponID = Character.WeaponID end
                if not WeaponID and Character.CurrentWeaponID then WeaponID = Character.CurrentWeaponID end
                if not WeaponID and Character.HoldWeaponID then WeaponID = Character.HoldWeaponID end
                if not WeaponID and Character.CurWeaponID then WeaponID = Character.CurWeaponID end
                if not WeaponID and Character.EquipWeaponID then WeaponID = Character.EquipWeaponID end
                if not WeaponID and Character.WeaponManagerComponent then
                    local WMC = Character.WeaponManagerComponent
                    if WMC.CurrentWeaponID then WeaponID = WMC.CurrentWeaponID end
                    if not WeaponID and WMC.WeaponID then WeaponID = WMC.WeaponID end
                    if not WeaponID and WMC.HoldWeaponID then WeaponID = WMC.HoldWeaponID end
                    if not WeaponID and WMC.CurWeaponID then WeaponID = WMC.CurWeaponID end
                end
            end)
        end

        return {
            WeaponID = WeaponID,
            WeaponName = WeaponName,
            WeaponIconPath = WeaponIconPath,
            WeaponIconTexture = WeaponIconTexture,
            CurrentWeapon = CurrentWeapon,
        }
    end

    function AK_PlayerMapMarker.FindWeaponIconInWidget(WidgetObj, Depth, MaxDepth)
        if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
        Depth = Depth or 0
        MaxDepth = MaxDepth or 8

        local propNames = {
            "Image_Weapon", "Image_WeaponIcon", "Image_Gun", "Image_Icon",
            "WeaponIcon", "WeaponImage", "WeaponIconImage",
            "Image_Equip", "Image_WeaponIcon_2", "Image_WeaponIcon2",
        }
        
        for _, pname in ipairs(propNames) do
            pcall(function()
                local prop = WidgetObj[pname]
                if prop and slua.isValid(prop) then
                    local hasBrush = false
                    pcall(function() if prop.Brush then hasBrush = true end end)
                    if hasBrush then
                        return prop
                    end
                end
            end)
        end

        if Depth >= MaxDepth then
            return nil
        end

        local nChildren = 0
        pcall(function()
            if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end
        end)

        for i = 0, math.max(nChildren - 1, 0) do
            local child = nil
            pcall(function() child = WidgetObj:GetChildAt(i) end)
            if child and slua.isValid(child) then
                local result = AK_PlayerMapMarker.FindWeaponIconInWidget(child, Depth + 1, MaxDepth)
                if result then return result end
            end
        end

        if nChildren == 0 then
            local Root = AK_PlayerMapMarker._GetWidgetRoot(WidgetObj)
            if Root and slua.isValid(Root) and Root ~= WidgetObj then
                local result = AK_PlayerMapMarker.FindWeaponIconInWidget(Root, Depth + 1, MaxDepth)
                if result then return result end
            end
        end

        return nil
    end

    function AK_PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, DefaultW, DefaultH)
        if not ImageWidget or not slua.isValid(ImageWidget) then return end
        
        DefaultW = DefaultW or 138
        DefaultH = DefaultH or 69
        
        pcall(function()
            local brush = ImageWidget.Brush
            if brush then
                brush.ImageSize = FVector2D(DefaultW, DefaultH)
                brush.DrawAs = 3
                brush.TintColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                if ImageWidget.SetBrush then
                    ImageWidget:SetBrush(brush)
                end
            end
            
            if ImageWidget.SetDesiredSizeOverride then
                ImageWidget:SetDesiredSizeOverride(FVector2D(DefaultW, DefaultH))
            end
            
            local slot = ImageWidget.Slot
            if slot and slot.SetSize then
                slot:SetSize(FVector2D(DefaultW, DefaultH))
            end
            
            ImageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            ImageWidget:SetRenderOpacity(1.0)
            ImageWidget:SetColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
        end)
    end

    function AK_PlayerMapMarker.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
        local fullIcon = FLinearColor(1.0, 1.0, 1.0, 1.0)

        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end

        pcall(function()
            if ourWeaponIcon.SetRenderOpacity then ourWeaponIcon:SetRenderOpacity(1.0) end
        end)
        pcall(function()
            if ourWeaponIcon.SetColorAndOpacity then ourWeaponIcon:SetColorAndOpacity(fullIcon) end
        end)
        pcall(function()
            if ourWeaponIcon.SetBrushTintColor then ourWeaponIcon:SetBrushTintColor(fullIcon) end
        end)
        pcall(function()
            if ourWeaponIcon.SetTintColorAndOpacity then ourWeaponIcon:SetTintColorAndOpacity(fullIcon) end
        end)
        
        pcall(function()
            local brush = ourWeaponIcon.Brush
            if brush then
                pcall(function() brush.TintColor = fullIcon end)
                if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end
            end
        end)

        local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon",
            "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
        for _, pname in ipairs(chainNames) do
            pcall(function()
                local node = Container and Container[pname]
                if node and slua.isValid(node) and node.SetRenderOpacity then
                    node:SetRenderOpacity(1.0)
                end
                if node and slua.isValid(node) and node.SetColorAndOpacity then
                    node:SetColorAndOpacity(fullIcon)
                end
            end)
        end
    end

    function AK_PlayerMapMarker.ApplyWeaponIconToImage(ImageWidget, winfo)
        if not ImageWidget or not slua.isValid(ImageWidget) then
            return false, "no_widget"
        end
        if not winfo or not winfo.WeaponID then
            return false, "no_weapon_id"
        end

        local iconPath = nil
        local method = "none"
        local bHasAddKnownMissing = false
        local defaultW = 138
        local defaultH = 69

        pcall(function()
            local itemRecord = CDataTable.GetTableData("Item", winfo.WeaponID)
            if itemRecord and itemRecord.KillWhiteIcon and itemRecord.KillWhiteIcon ~= "" then
                iconPath = itemRecord.KillWhiteIcon
                method = "KillWhiteIcon"
            end

            if (not iconPath or iconPath == "") and winfo.WeaponIconPath and winfo.WeaponIconPath ~= "" then
                iconPath = winfo.WeaponIconPath
                method = "WeaponIconPath"
            end

            if (not iconPath or iconPath == "") and winfo.WeaponIconTexture and slua.isValid(winfo.WeaponIconTexture) then
                if ImageWidget.SetBrushFromTexture then
                    ImageWidget:SetBrushFromTexture(winfo.WeaponIconTexture, true)
                    method = "WeaponIconTexture"
                    return
                end
            end

            if not iconPath or iconPath == "" then
                local UIUtil = require("client.common.ui_util")
                iconPath, bHasAddKnownMissing = UIUtil.GetItemBigIcon(winfo.WeaponID, ImageWidget)
                if iconPath and iconPath ~= "" then
                    method = "GetItemBigIcon"
                end
            end

            if not iconPath or iconPath == "" then
                local UIUtil = require("client.common.ui_util")
                iconPath = UIUtil.GetItemSmallIcon(winfo.WeaponID, ImageWidget, bHasAddKnownMissing)
                if iconPath and iconPath ~= "" then
                    method = "GetItemSmallIcon"
                end
            end
        end)

        if method == "WeaponIconTexture" then
            AK_PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH)
            return true, method
        end
        
        if not iconPath or iconPath == "" then
            return false, "no_path"
        end

        local bOK = false
        pcall(function()
            if ImageWidget.SetBrushResourceFromPathSync then
                ImageWidget:SetBrushResourceFromPathSync(iconPath, true)
                bOK = true
            end
            
            if not bOK then
                local util = require("client.slua_ui_framework.util")
                local result = util.SetTexture(ImageWidget, iconPath, {
                    sync = true,
                    bMatchSize = true,
                    bIsInCombatState = true,
                    bHasAddKnownMissing = bHasAddKnownMissing,
                })
                bOK = result ~= nil
            end
            
            if not bOK then
                local tex = import(iconPath)
                if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then
                    ImageWidget:SetBrushFromTexture(tex, true)
                    bOK = true
                end
            end
            
            if not bOK then
                local LoadObject = import("LoadObject")
                if LoadObject then
                    local tex = LoadObject(iconPath)
                    if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then
                        ImageWidget:SetBrushFromTexture(tex, true)
                        bOK = true
                    end
                end
            end
        end)

        if bOK then
            AK_PlayerMapMarker.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH)
        end

        return bOK, method .. ":" .. tostring(iconPath)
    end

    function AK_PlayerMapMarker.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return false end
        if not nativeWeaponIcon or not slua.isValid(nativeWeaponIcon) then return false end

        local bCopied = false
        
        pcall(function()
            local nBrush = nativeWeaponIcon.Brush
            if nBrush then
                local resObj = nil
                pcall(function() resObj = nBrush.ResourceObject end)
                if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                    ourWeaponIcon:SetBrushFromTexture(resObj, true)
                    bCopied = true
                end
                
                if bCopied then
                    local imgSize = nil
                    pcall(function() imgSize = nBrush.ImageSize end)
                    if imgSize then
                        local oBrush = ourWeaponIcon.Brush
                        if oBrush then
                            oBrush.ImageSize = imgSize
                            if ourWeaponIcon.SetBrush then
                                ourWeaponIcon:SetBrush(oBrush)
                            end
                        end
                    end
                end
            end
        end)

        return bCopied
    end

    function AK_PlayerMapMarker.AddWeaponIconToESP(WidgetData, Character)
        if not WidgetData or not WidgetData.Container then return end
        local Container = WidgetData.Container
        if not slua.isValid(Container) then return end

        if _G.AK_GetVal and _G.AK_GetVal("ESP_WEAPON") ~= 1 then
            local names = {"WeaponIcon", "Image_Weapon", "Border_Weapon", "Switcher_WeaponIcon", "SizeBox_Weapon"}
            for _, n in ipairs(names) do
                if Container[n] and slua.isValid(Container[n]) then
                    pcall(function() Container[n]:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                end
            end
            return
        end

        pcall(function()
            local eWeapon = Character:GetCurrentWeapon()
            local wepID = 0
            if slua.isValid(eWeapon) then
                local def = eWeapon:GetItemDefineID()
                wepID = def and def.TypeSpecificID or 0
            end

            if wepID == 0 then
                local names = {"WeaponIcon", "Image_Weapon", "Border_Weapon", "Switcher_WeaponIcon", "SizeBox_Weapon"}
                for _, n in ipairs(names) do
                    if Container[n] and slua.isValid(Container[n]) then
                        pcall(function() Container[n]:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                    end
                end
                return
            end

            pcall(function() if Container.UpdateWeapon then Container:UpdateWeapon(wepID) end end)
            pcall(function() if Container.SetWeaponID then Container:SetWeaponID(wepID) end end)

            local iconWidget = Container.WeaponIcon or Container.Image_Weapon or Container.Image_Gun
            if not iconWidget or not slua.isValid(iconWidget) then
                iconWidget = AK_PlayerMapMarker.FindWeaponIconInWidget(Container, 0, 6)
            end

            if slua.isValid(iconWidget) then
                local ItemData = CDataTable.GetTableData("Item", wepID)
                if ItemData and ItemData.ItemWhiteIcon and ItemData.ItemWhiteIcon ~= "" then
                    
                    iconWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    iconWidget:SetBrushFromPathAsync(ItemData.ItemWhiteIcon, false)
                    pcall(function() iconWidget:SetColorAndOpacity(import("LinearColor")(1,1,1,1)) end)
                    pcall(function() iconWidget:SetRenderOpacity(1.0) end)
                    
                    local brush = slua.IndexReference(iconWidget, "Brush")
                    if brush then
                        brush.ImageSize = import("Vector2D")(128, 64)
                        if iconWidget.SetBrush then iconWidget:SetBrush(brush) end
                    end

                    local parent = iconWidget
                    for i = 1, 7 do
                        if not parent or not slua.isValid(parent) then break end
                        pcall(function()
                            if parent.GetParent then
                                local p = parent:GetParent()
                                if slua.isValid(p) then
                                    p:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                                    pcall(function() p:SetRenderOpacity(1.0) end)
                                    
                                    if string.find(tostring(p), "WidgetSwitcher") then
                                        local count = p:GetChildrenCount()
                                        for j = 0, count - 1 do
                                            local child = p:GetChildAt(j)
                                            if child == parent or tostring(child) == tostring(parent) then
                                                p:SetActiveWidgetIndex(j)
                                                break
                                            end
                                        end
                                    end
                                    parent = p
                                else
                                    parent = nil
                                end
                            else
                                parent = nil
                            end
                        end)
                    end
                end
            end
        end)
    end

    AK_PlayerMapMarker._OBHeadWidgetClass = nil
    AK_PlayerMapMarker._OBHeadWidgetLoadFailed = false
    AK_PlayerMapMarker._bDumpedWidgetChildren = false

    function AK_PlayerMapMarker.CreateESPWidget()
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
            return nil
        end

        if AK_PlayerMapMarker._OBHeadWidgetLoadFailed then
            return nil
        end

        if not AK_PlayerMapMarker._OBHeadWidgetClass then
            pcall(function()
                local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
                local uClass = slua.loadClass(Path)
                if uClass then
                    AK_PlayerMapMarker._OBHeadWidgetClass = uClass
                end
            end)
            if not AK_PlayerMapMarker._OBHeadWidgetClass then
                AK_PlayerMapMarker._OBHeadWidgetLoadFailed = true
                return nil
            end
        else
            local bValid = false
            pcall(function() bValid = slua.isValid(AK_PlayerMapMarker._OBHeadWidgetClass) end)
            if not bValid then
                AK_PlayerMapMarker._OBHeadWidgetLoadFailed = true
                AK_PlayerMapMarker._OBHeadWidgetClass = nil
                return nil
            end
        end

        local Widget = nil
        pcall(function()
            local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
            local PC = AK_PlayerMapMarker.GetMyPlayerController()
            local OuterObj = AK_IsValid(PC) and PC.Object or AK_PlayerMapMarker.ESPCanvas
            Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(AK_PlayerMapMarker._OBHeadWidgetClass, OuterObj)
        end)

        if not Widget then
            return nil
        end

        pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        pcall(function() Widget:SetRenderOpacity(1.0) end)
        Widget._vis = 0

        local NameText = nil
        local HealthFill = nil
        local bIsOriginalProgressBar = false

        pcall(function()
            NameText = Widget.TextBlock_TeamName
            if NameText and slua.isValid(NameText) then
                pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            end
            if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then
                pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            end

            local WS_Type = Widget.WidgetSwitcher_Type
            local WS_Type2 = Widget.WidgetSwitcher_Type2
            if WS_Type and slua.isValid(WS_Type) then
                pcall(function()
                    if WS_Type.SetActiveWidgetIndex then
                        WS_Type:SetActiveWidgetIndex(AK_PlayerMapMarker.HPWidgetSwitcherTypeIndex)
                    end
                end)
            end
            if WS_Type2 and slua.isValid(WS_Type2) then
                pcall(function()
                    if WS_Type2.SetActiveWidgetIndex then
                        WS_Type2:SetActiveWidgetIndex(AK_PlayerMapMarker.HPWidgetSwitcherType2Index)
                    end
                end)
            end

            local SizeBox_HP = Widget.SizeBox_HP
            if SizeBox_HP and slua.isValid(SizeBox_HP) then
                pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                pcall(function() SizeBox_HP:SetHeightOverride(6) end)
                pcall(function() SizeBox_HP:SetWidthOverride(100) end)

                local ExistingChild = nil
                pcall(function()
                    if SizeBox_HP.GetContent then
                        ExistingChild = SizeBox_HP:GetContent()
                    end
                end)
                if not ExistingChild then
                    pcall(function()
                        if SizeBox_HP.GetChildAt then
                            ExistingChild = SizeBox_HP:GetChildAt(0)
                        end
                    end)
                end

                if ExistingChild and slua.isValid(ExistingChild) then
                    pcall(function() ExistingChild:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() ExistingChild:SetRenderOpacity(1.0) end)

                    local FoundPB = AK_PlayerMapMarker.FindProgressBarInWidget(ExistingChild, 0, 5)
                    if FoundPB and slua.isValid(FoundPB) then
                        HealthFill = FoundPB
                        bIsOriginalProgressBar = true
                        pcall(function() FoundPB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() FoundPB:SetRenderOpacity(1.0) end)
                    else
                        local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", ExistingChild)
                        if PB then
                            pcall(function() PB:SetFillColorAndOpacity(FLinearColor(0, 1, 0, 1)) end)
                            pcall(function() PB:SetPercent(1.0) end)
                            pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                            pcall(function() PB:SetRenderOpacity(1.0) end)
                            pcall(function() PB:SetDesiredSizeOverride(FVector2D(100, 6)) end)
                            pcall(function() ExistingChild:AddChild(PB) end)
                            HealthFill = PB
                        end
                    end
                else
                    local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", SizeBox_HP)
                    if PB then
                        pcall(function() PB:SetFillColorAndOpacity(FLinearColor(0, 1, 0, 1)) end)
                        pcall(function() PB:SetPercent(1.0) end)
                        pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() PB:SetRenderOpacity(1.0) end)
                        pcall(function() PB:SetDesiredSizeOverride(FVector2D(100, 6)) end)

                        local bUsedSetContent = false
                        pcall(function()
                            if SizeBox_HP.SetContent then
                                SizeBox_HP:SetContent(PB)
                                bUsedSetContent = true
                            end
                        end)
                        if not bUsedSetContent then
                            pcall(function() SizeBox_HP:AddChild(PB) end)
                        end
                        HealthFill = PB
                    end
                end
            end
        end)

        local WidgetData = {
            Container = Widget,
            NameText = NameText,
            HealthFill = HealthFill,
            IsGameWidget = true,
            IsOriginalProgressBar = bIsOriginalProgressBar,
            HasChildren = (NameText ~= nil)
        }
        return WidgetData
    end

    AK_PlayerMapMarker._CanvasScaleX = 1.0
    AK_PlayerMapMarker._CanvasScaleY = 1.0
    AK_PlayerMapMarker._CanvasOffsetX = 0.0
    AK_PlayerMapMarker._CanvasOffsetY = 0.0

    function AK_PlayerMapMarker.UpdateCanvasTransform(PC)
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
            return
        end

        local success = false

        pcall(function()
            local SBL = SlateBlueprintLibrary
            if SBL and SBL.AbsoluteToLocal then
                local cg = AK_PlayerMapMarker.ESPCanvas:GetCachedGeometry()
                if cg then
                    local pt0 = SBL.AbsoluteToLocal(cg, FVector2D(0, 0))
                    local pt1 = SBL.AbsoluteToLocal(cg, FVector2D(100, 100))
                    if pt0 and pt1 then
                        AK_PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                        AK_PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                        AK_PlayerMapMarker._CanvasOffsetX = pt0.X
                        AK_PlayerMapMarker._CanvasOffsetY = pt0.Y
                        success = true
                    end
                end
            end
        end)

        if not success then
            pcall(function()
                local WLL = WidgetLayoutLibrary
                if WLL and WLL.ScreenToWidgetLocal then
                    local cg = AK_PlayerMapMarker.ESPCanvas:GetCachedGeometry()
                    if cg then
                        local pt0 = FVector2D(0, 0)
                        local pt1 = FVector2D(0, 0)
                        WLL.ScreenToWidgetLocal(PC, cg, FVector2D(0, 0), pt0)
                        WLL.ScreenToWidgetLocal(PC, cg, FVector2D(100, 100), pt1)
                        AK_PlayerMapMarker._CanvasScaleX = (pt1.X - pt0.X) / 100
                        AK_PlayerMapMarker._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                        AK_PlayerMapMarker._CanvasOffsetX = pt0.X
                        AK_PlayerMapMarker._CanvasOffsetY = pt0.Y
                        success = true
                    end
                end
            end)
        end

        if not success then
            local scale = 1.0
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                scale = WLL.GetViewportScale(PC) or 1.0
            end
            AK_PlayerMapMarker._CanvasScaleX = 1.0 / scale
            AK_PlayerMapMarker._CanvasScaleY = 1.0 / scale
            AK_PlayerMapMarker._CanvasOffsetX = 0
            AK_PlayerMapMarker._CanvasOffsetY = 0
        end
    end

    function AK_PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
        if not ScreenPixelPos then return FVector2D(0, 0) end
        local scaleX = AK_PlayerMapMarker._CanvasScaleX or 1.0
        local scaleY = AK_PlayerMapMarker._CanvasScaleY or 1.0
        local offsetX = AK_PlayerMapMarker._CanvasOffsetX or 0
        local offsetY = AK_PlayerMapMarker._CanvasOffsetY or 0
        return FVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)
    end

    function AK_PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
        if not AK_IsValid(PC) or not WorldLoc then return false, FVector2D(0, 0) end
        
        local ScreenPixelPos = FVector2D(0, 0)
        local bOK = false

        pcall(function()
            local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
            if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then
                bOK = true
            end
        end)

        if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then
            return false, FVector2D(0, 0)
        end

        local CanvasLocalPos = AK_PlayerMapMarker.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
        return true, CanvasLocalPos
    end

    function AK_PlayerMapMarker.GetDynamicViewportSize(PC)
        local width, height = 0, 0
        
        if AK_PlayerMapMarker.ESPCanvas and Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
            pcall(function()
                local cg = AK_PlayerMapMarker.ESPCanvas:GetCachedGeometry()
                if cg and cg.GetLocalSize then
                    local sz = cg:GetLocalSize()
                    if sz and sz.X and sz.X > 200 then
                        width = sz.X
                        height = sz.Y
                    end
                end
            end)
        end

        if width > 200 then return width, height end

        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportSize then
                local sz = WLL.GetViewportSize(PC or AK_PlayerMapMarker.GetMyPlayerController())
                if sz and sz.X and sz.X > 200 then
                    width = sz.X
                    height = sz.Y
                end
            end
        end)

        if width > 200 then
            pcall(function()
                local WLL = WidgetLayoutLibrary
                if WLL and WLL.GetViewportScale then
                    local scale = WLL.GetViewportScale(PC or AK_PlayerMapMarker.GetMyPlayerController())
                    if scale and type(scale) == "number" and scale > 0 and scale ~= 1.0 then
                        width = width / scale
                        height = height / scale
                    end
                end
            end)
            return width, height
        end

        return AK_PlayerMapMarker._cachedViewportW or 1920, AK_PlayerMapMarker._cachedViewportH or 1080
    end

    function AK_PlayerMapMarker.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
        if not Widget or not AK_IsValid(PC) then return false end
        local Container = Widget.Container or Widget

        local bOnScreen = true
        if not CanvasPos then
            if not WorldLoc then return false end
            bOnScreen, CanvasPos = AK_PlayerMapMarker.ProjectWorldToCanvasLocal(PC, WorldLoc)
        end

        if not bOnScreen then
            if Container._vis ~= 2 then
                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                Container._vis = 2
            end
            return false
        end

        pcall(function()
            if AK_PlayerMapMarker.ESPCanvas and Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
                local ptr = tostring(Container)
                local Slot = AK_PlayerMapMarker.ESPWidgetPtrs[ptr]

                if not Slot or not slua.isValid(Slot) or type(Slot) == "boolean" then
                    local addedSlot = AK_PlayerMapMarker.ESPCanvas:AddChildToCanvas(Container)
                    if addedSlot and slua.isValid(addedSlot) then
                        Slot = addedSlot
                        AK_PlayerMapMarker.ESPWidgetPtrs[ptr] = addedSlot
                        if type(Widget) == "table" then
                            Widget.Slot = addedSlot
                        end
                        
                        pcall(function() Slot:SetAutoSize(true) end)
                        pcall(function() Slot.bAutoSize = true end)
                        local align = FVector2D(0.5, 1.0)
                        pcall(function() Slot.Alignment = align end)
                        pcall(function() Slot:SetAlignment(align) end)
                        pcall(function() Slot:SetAlignment(0.5, 1.0) end)
                        pcall(function() Slot:SetZOrder(AK_PlayerMapMarker.ESPWidgetZOrder or 20) end)
                    end
                end

                if Container._vis ~= 0 then
                    Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    Container._vis = 0
                end
                
                if not Widget._OffsetResetDone then
                    pcall(function() Container:SetRenderTranslation(FVector2D(0.0, 0.0)) end)
                    if Widget and type(Widget) == "table" then
                        if Widget.NameText and slua.isValid(Widget.NameText) then
                            pcall(function() Widget.NameText:SetRenderTranslation(FVector2D(0.0, 0.0)) end)
                        end
                        if Widget.HealthFill and slua.isValid(Widget.HealthFill) then
                            pcall(function() Widget.HealthFill:SetRenderTranslation(FVector2D(0.0, 0.0)) end)
                        end
                    end
                    
                    pcall(function() Container.RenderTransformPivot = FVector2D(0.5, 1.0) end)
                    pcall(function() Container:SetRenderTransformPivot(FVector2D(0.5, 1.0)) end)
                    Widget._OffsetResetDone = true
                end

                if not Slot or not slua.isValid(Slot) or Slot == AK_PlayerMapMarker.ESPCanvas then
                    if Widget and type(Widget) == "table" and Widget.Slot and slua.isValid(Widget.Slot) then
                        Slot = Widget.Slot
                    elseif Container.Slot and slua.isValid(Container.Slot) then
                        Slot = Container.Slot
                    end
                end

                if Slot and slua.isValid(Slot) and Slot ~= AK_PlayerMapMarker.ESPCanvas then
                    local finalX = CanvasPos.X + (AK_PlayerMapMarker.ESPAnchorOffsetX or 0) - 25  
                    local finalY = CanvasPos.Y + (AK_PlayerMapMarker.ESPAnchorOffsetY or 0)
                    if Widget and type(Widget) == "table" then
                        if not Widget._CachedPosVec or math.abs(Widget._CachedPosVec.X - finalX) > 0.5 or math.abs(Widget._CachedPosVec.Y - finalY) > 0.5 then
                            Widget._CachedPosVec = Widget._CachedPosVec or FVector2D(finalX, finalY)
                            Widget._CachedPosVec.X = finalX
                            Widget._CachedPosVec.Y = finalY
                            pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
                        end
                    else
                        pcall(function() Slot:SetPosition(FVector2D(finalX, finalY)) end)
                    end
                end
            end
        end)
        return true
    end

    function AK_PlayerMapMarker.UpdateESPText(Widget, Text)
    end

    function AK_PlayerMapMarker.UpdateESPHealth(Widget, pct)
    end

    function AK_PlayerMapMarker.RemoveESPWidget(Widget)
        if not Widget then return end
        local Container = Widget.Container or Widget
        pcall(function()
            local ptr = tostring(Container)
            AK_PlayerMapMarker.ESPWidgetPtrs[ptr] = nil
            Container:RemoveFromParent()
            Container:ConditionalBeginDestroy()
        end)
    end

    function AK_PlayerMapMarker.CreateSnapLine()
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then return nil end

        local Border = nil
        pcall(function()
            Border = CGame:NewObjectFromPath("/Script/UMG.Border", AK_PlayerMapMarker.ESPCanvas)
        end)
        if not Border or not slua.isValid(Border) then return nil end

        local color = AK_PlayerMapMarker.SnapLineColor or FLinearColor(1.0, 1.0, 1.0, AK_PlayerMapMarker.SnapLineOpacity or 0.7)
        pcall(function() Border:SetBrushColor(color) end)
        pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        
        pcall(function() Border.RenderTransformPivot = FVector2D(0.0, 0.5) end)
        pcall(function() Border:SetRenderTransformPivot(FVector2D(0.0, 0.5)) end)

        local Slot = nil
        pcall(function()
            Slot = AK_PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)
            if Slot then
                Slot:SetAutoSize(false)
                Slot:SetZOrder(1)
            end
        end)

        return { Widget = Border, Slot = Slot, _vis = 2 }
    end

    function AK_PlayerMapMarker.GetSnapLineStartPos(PC)
        local screenPixelW, screenPixelH = 0, 0
        local scale = 1.0

        pcall(function()
            if PC and PC.GetViewportSize then
                local vs = FVector2D(0, 0)
                PC:GetViewportSize(vs)
                if vs and vs.X and vs.X > 200 then
                    screenPixelW = vs.X
                    screenPixelH = vs.Y
                end
            end
        end)

        if screenPixelW <= 200 then
            pcall(function()
                local WLL = WidgetLayoutLibrary
                if WLL and WLL.GetViewportSize then
                    local vs = WLL.GetViewportSize(PC)
                    if vs and vs.X and vs.X > 200 then
                        screenPixelW = vs.X
                        screenPixelH = vs.Y
                    end
                end
            end)
        end

        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                local s = WLL.GetViewportScale(PC)
                if s and type(s) == "number" and s > 0 then scale = s end
            end
        end)

        if screenPixelW <= 200 then
            screenPixelW = (AK_PlayerMapMarker._cachedViewportW or 1920) * scale
            screenPixelH = (AK_PlayerMapMarker._cachedViewportH or 1080) * scale
        end

        if not AK_PlayerMapMarker._CachedTopCenterPixel then
            AK_PlayerMapMarker._CachedTopCenterPixel = FVector2D(0, 0)
        end
        AK_PlayerMapMarker._CachedTopCenterPixel.X = screenPixelW / 2.0
        AK_PlayerMapMarker._CachedTopCenterPixel.Y = (AK_PlayerMapMarker.SnapLineOriginY or 50) * scale

        local fromCanvasPos = AK_PlayerMapMarker.ScreenPixelToCanvasLocal(PC, AK_PlayerMapMarker._CachedTopCenterPixel)
        local fromX = fromCanvasPos.X + (AK_PlayerMapMarker.SnapLineOriginOffsetX or 0)
        local fromY = fromCanvasPos.Y

        return fromX, fromY
    end

    function AK_PlayerMapMarker.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY, color)
        if not AK_PlayerMapMarker.bUseSnapLines then return end
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then return end

        local LineData = AK_PlayerMapMarker.SnapLineWidgets[KeyStr]

        if not bOnScreen or not CanvasPos then
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) and LineData._vis ~= 2 then
                pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                LineData._vis = 2
            end
            return
        end

        local bIsNew = false
        if not LineData then
            LineData = AK_PlayerMapMarker.CreateSnapLine()
            if not LineData or not LineData.Widget or not LineData.Slot then return end
            AK_PlayerMapMarker.SnapLineWidgets[KeyStr] = LineData
            bIsNew = true
        end

        local Widget = LineData.Widget
        local Slot = LineData.Slot

        if LineData._vis ~= 0 then
            pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            LineData._vis = 0
        end
        
        if color then
            pcall(function() Widget:SetBrushColor(color) end)
        end
        
        if not LineData._PivotSet then
            pcall(function() Widget.RenderTransformPivot = FVector2D(0.0, 0.5) end)
            pcall(function() Widget:SetRenderTransformPivot(FVector2D(0.0, 0.5)) end)
            LineData._PivotSet = true
        end

        local toX = CanvasPos.X + (AK_PlayerMapMarker.SnapLineHeadOffsetX or 0)
        local toY = CanvasPos.Y + (AK_PlayerMapMarker.SnapLineHeadOffsetY or 0)

        local dx = toX - fromX
        local dy = toY - fromY
        local length = math.sqrt(dx * dx + dy * dy)
        local thickness = AK_PlayerMapMarker.SnapLineThickness or 1.5

        local angle_rad = 0
        if math.atan2 then angle_rad = math.atan2(dy, dx) else angle_rad = math.atan(dy, dx) end
        local angle = angle_rad * (180.0 / math.pi)

        if not LineData._CachedPosVec then
            LineData._CachedPosVec = FVector2D(fromX, fromY - thickness / 2.0)
            LineData._CachedSizeVec = FVector2D(length, thickness)
        else
            LineData._CachedPosVec.X = fromX
            LineData._CachedPosVec.Y = fromY - thickness / 2.0
            LineData._CachedSizeVec.X = length
            LineData._CachedSizeVec.Y = thickness
        end

        pcall(function() 
            Slot:SetPosition(LineData._CachedPosVec) 
            Slot:SetSize(LineData._CachedSizeVec)
            if bIsNew then Slot:SetZOrder(1) end
        end)
        pcall(function() Widget:SetRenderAngle(angle) end)
    end

    function AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
        local LineData = AK_PlayerMapMarker.SnapLineWidgets[KeyStr]
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function()
                LineData.Widget:RemoveFromParent()
                LineData.Widget:ConditionalBeginDestroy()
            end)
            AK_PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
        end
    end

    function AK_PlayerMapMarker.ClearAllSnapLines()
        for KeyStr, LineData in pairs(AK_PlayerMapMarker.SnapLineWidgets) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
        AK_PlayerMapMarker.SnapLineWidgets = {}
    end

    function AK_PlayerMapMarker.ClearAllESP()
        AK_RedBoxOverlay.Stop()

        for KeyStr, Data in pairs(AK_PlayerMapMarker.ESPWidgets) do
            AK_PlayerMapMarker.RemoveESPWidget(Data.Widget)
        end
        AK_PlayerMapMarker.ESPWidgets = {}
        AK_PlayerMapMarker.ESPWidgetPtrs = {}
        AK_PlayerMapMarker.ClearAllSnapLines()
        
        for KeyStr, box in pairs(AK_PlayerMapMarker.BoxWidgets or {}) do
            AK_PlayerMapMarker.Remove2DBox(KeyStr)
        end
        AK_PlayerMapMarker.BoxWidgets = {}

        for KeyStr, hpBox in pairs(AK_PlayerMapMarker.HealthWidgets or {}) do
            if hpBox.bg and slua.isValid(hpBox.bg.Widget) then pcall(function() hpBox.bg.Widget:RemoveFromParent(); hpBox.bg.Widget:ConditionalBeginDestroy() end) end
            if hpBox.fg and slua.isValid(hpBox.fg.Widget) then pcall(function() hpBox.fg.Widget:RemoveFromParent(); hpBox.fg.Widget:ConditionalBeginDestroy() end) end
        end
        AK_PlayerMapMarker.HealthWidgets = {}

        for KeyStr, tBox in pairs(AK_PlayerMapMarker.CustomTextWidgets or {}) do
            if tBox.topTxt and slua.isValid(tBox.topTxt.Widget) then pcall(function() tBox.topTxt.Widget:RemoveFromParent(); tBox.topTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.nameTxt and slua.isValid(tBox.nameTxt.Widget) then pcall(function() tBox.nameTxt.Widget:RemoveFromParent(); tBox.nameTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.distTxt and slua.isValid(tBox.distTxt.Widget) then pcall(function() tBox.distTxt.Widget:RemoveFromParent(); tBox.distTxt.Widget:ConditionalBeginDestroy() end) end
            if tBox.botTxt and slua.isValid(tBox.botTxt.Widget) then pcall(function() tBox.botTxt.Widget:RemoveFromParent(); tBox.botTxt.Widget:ConditionalBeginDestroy() end) end
        end
        AK_PlayerMapMarker.CustomTextWidgets = {}
        
        for _, lineData in pairs(AK_PlayerMapMarker.SkeletonWidgets or {}) do pcall(function() lineData.Widget:RemoveFromParent() end) end
        AK_PlayerMapMarker.SkeletonWidgets = {}
        
        if AK_PlayerMapMarker.ESPCanvas and Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then
            pcall(function()
                local n = AK_PlayerMapMarker.ESPCanvas:GetChildrenCount()
                for i = n - 1, 0, -1 do
                    local child = AK_PlayerMapMarker.ESPCanvas:GetChildAt(i)
                    if child and slua.isValid(child) then
                        if AK_PlayerMapMarker.IsOurESPWidget(child) then
                            AK_PlayerMapMarker.ESPCanvas:RemoveChild(child)
                        end
                    end
                end
            end)
        end
        
        if _G.AK_EnvWidgets then
            for k, wData in pairs(_G.AK_EnvWidgets) do
                if wData and slua.isValid(wData.Widget) then
                    pcall(function() wData.Widget:RemoveFromParent(); wData.Widget:ConditionalBeginDestroy() end)
                end
            end
            _G.AK_EnvWidgets = {}
        end

        AK_PlayerMapMarker.ESPCanvas = nil
        AK_PlayerMapMarker._OBHeadWidgetClass = nil
        AK_PlayerMapMarker._OBHeadWidgetLoadFailed = false
        AK_PlayerMapMarker._bDumpedWidgetChildren = false
        AK_PlayerMapMarker._cachedViewportW = 1920
        AK_PlayerMapMarker._cachedViewportH = 1080
    end

    function AK_PlayerMapMarker.ScanAndUpdate()
        if _G.AK_GetVal and _G.AK_GetVal("ESP_FULL_INFO") ~= 1 then
            AK_PlayerMapMarker.ClearAllESP()
            return 0
        end

        local AllChars = AK_PlayerMapMarker.GetAllCharacters()
        if not AllChars then
            AK_RedBoxOverlay.SetCounts(0, 0, 0)
            return 0
        end

        local MyKey = AK_PlayerMapMarker.GetMyPlayerKey()
        local MyLoc = AK_PlayerMapMarker.GetMyLocation()

        local MyChar = nil
        pcall(function()
            local GDP = AK_PlayerMapMarker.GetGameplayData()
            if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
            else local PC = AK_PlayerMapMarker.GetMyPlayerController(); if PC and PC.GetPawn then MyChar = PC:GetPawn() end end
        end)
        local MyTeamID = AK_PlayerMapMarker.GetTeamID(MyChar)

        local realPlayers = 0
        local botPlayers = 0
        local near400 = 0 

        for PlayerKey, Character in pairs(AllChars) do
            if AK_IsValid(Character) then
                local bIsMe = AK_PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
                local bIsAlive = AK_PlayerMapMarker.IsAlive(Character)

                if bIsAlive and not bIsMe then
                    local bIsMyTeam = false
                    if MyTeamID ~= nil then
                        if AK_PlayerMapMarker.GetTeamID(Character) == MyTeamID then bIsMyTeam = true end
                    end
                    
                    if not bIsMyTeam then
                        local isNormalBot, isMLBot = false, false
                        if _G.AK_CheckIsBot then isNormalBot, isMLBot = _G.AK_CheckIsBot(Character) end
                        
                        if isNormalBot or isMLBot then botPlayers = botPlayers + 1 else realPlayers = realPlayers + 1 end
                        
                        local Loc = AK_PlayerMapMarker.GetCharacterLocation(Character)
                        if Loc and MyLoc then
                            local d = AK_PlayerMapMarker.CalcDistance(MyLoc, Loc) / 100.0
                            if d <= 400.0 then near400 = near400 + 1 end
                        end
                    end
                end
            end
        end

        if _G.AK_GetVal and _G.AK_GetVal("ESP_COUNT_BOX") == 1 then
            if AK_RedBoxOverlay.bActive then AK_RedBoxOverlay.SetCounts(realPlayers, botPlayers, near400)
            else AK_RedBoxOverlay.Start() end
        else
            AK_RedBoxOverlay.Stop()
        end

        if AK_PlayerMapMarker.bUseScreenMark then
            AK_PlayerMapMarker.SetupScreenMarkConfig()
        end

        if AK_PlayerMapMarker.bUseScreenESP then
            AK_PlayerMapMarker.UpdateESP(AllChars, MyLoc)
            return 0
        end

        if AK_PlayerMapMarker.bUseWidgetComponent then
            AK_PlayerMapMarker.UpdateWidgetComps(AllChars, MyLoc)
            return 0
        end

        local nCount = 0
        local nMarked = 0
        local nNewMarks = 0
        local nUpdated = 0
        local SeenKeys = {}

        for PlayerKey, Character in pairs(AllChars) do
            if AK_IsValid(Character) then
                local bIsMe = AK_PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
                local bIsAI = AK_PlayerMapMarker.IsAI(Character)
                local bIsAlive = AK_PlayerMapMarker.IsAlive(Character)
                local KeyStr = tostring(PlayerKey)
                local Name = AK_PlayerMapMarker.GetPlayerName(Character)
                local Loc = AK_PlayerMapMarker.GetCharacterLocation(Character)

                local DistStr = ""
                if _G.AK_GetVal and _G.AK_GetVal("ESP_DISTANCE") == 1 then
                    AK_PlayerMapMarker.bShowDistance = true
                else
                    AK_PlayerMapMarker.bShowDistance = false
                end

                if AK_PlayerMapMarker.bShowDistance and MyLoc and Loc then
                    DistStr = AK_PlayerMapMarker.GetDistanceString(MyLoc, Loc)
                end

                local MarkText = Name
                if DistStr and DistStr ~= "" then
                    MarkText = Name .. " [" .. DistStr .. "]"
                end

                nCount = nCount + 1
                SeenKeys[KeyStr] = true

                local bSkip = false
                if bIsMe and not AK_PlayerMapMarker.bIncludeMe then bSkip = true end
                if bIsAI and not AK_PlayerMapMarker.bIncludeAI then bSkip = true end

                if not bSkip and Loc then
                    local ExistingMark = AK_PlayerMapMarker.MarkMap[KeyStr]

                    if AK_PlayerMapMarker.bUseQuickSign then
                        if ExistingMark then
                            AK_PlayerMapMarker.RemoveQuickSignMark(ExistingMark)
                        end
                        local MsgID = AK_PlayerMapMarker.CreateQuickSignMark(Loc)
                        if MsgID then
                            AK_PlayerMapMarker.MarkMap[KeyStr] = MsgID
                            AK_PlayerMapMarker.PlayerInfo[KeyStr] = {
                                Name = Name, bIsAlive = bIsAlive, bIsAI = bIsAI, bIsMe = bIsMe, LastDistStr = DistStr,
                            }
                            nMarked = nMarked + 1
                            if not ExistingMark then nNewMarks = nNewMarks + 1 else nUpdated = nUpdated + 1 end
                        end
                    elseif AK_PlayerMapMarker.bUseNavigator then
                        if not ExistingMark then
                            local NavInstID = AK_PlayerMapMarker.CreateNavigatorMark(Loc)
                            if NavInstID then
                                AK_PlayerMapMarker.MarkMap[KeyStr] = NavInstID
                                AK_PlayerMapMarker.PlayerInfo[KeyStr] = {
                                    Name = Name, bIsAlive = bIsAlive, bIsAI = bIsAI, bIsMe = bIsMe, LastDistStr = DistStr,
                                }
                                nMarked = nMarked + 1
                                nNewMarks = nNewMarks + 1
                            end
                        else
                            AK_PlayerMapMarker.UpdateNavigatorMark(ExistingMark, Loc)
                            nMarked = nMarked + 1
                            nUpdated = nUpdated + 1
                            local OldInfo = AK_PlayerMapMarker.PlayerInfo[KeyStr]
                            if OldInfo then
                                OldInfo.Name = Name
                                OldInfo.bIsAlive = bIsAlive
                                OldInfo.LastDistStr = DistStr
                            end
                        end
                    else
                        if not ExistingMark then
                            local InstID = AK_PlayerMapMarker.CreateMark(Loc, MarkText, Character)
                            if InstID then
                                AK_PlayerMapMarker.MarkMap[KeyStr] = InstID
                                AK_PlayerMapMarker.ShowMark(InstID)
                                AK_PlayerMapMarker.PlayerInfo[KeyStr] = {
                                    Name = Name, bIsAlive = bIsAlive, bIsAI = bIsAI, bIsMe = bIsMe, LastDistStr = DistStr,
                                }
                                nMarked = nMarked + 1
                                nNewMarks = nNewMarks + 1
                            end
                        else
                            if not AK_PlayerMapMarker.bUseScreenMark then
                                AK_PlayerMapMarker.UpdateMarkLocation(ExistingMark, Loc)
                            end
                            AK_PlayerMapMarker.UpdateMarkString(ExistingMark, MarkText)
                            nMarked = nMarked + 1
                            nUpdated = nUpdated + 1
                            local OldInfo = AK_PlayerMapMarker.PlayerInfo[KeyStr]
                            if OldInfo then
                                OldInfo.Name = Name
                                OldInfo.bIsAlive = bIsAlive
                                OldInfo.LastDistStr = DistStr
                            end
                        end
                    end
                elseif bSkip and AK_PlayerMapMarker.MarkMap[KeyStr] then
                    if AK_PlayerMapMarker.bUseQuickSign then
                        AK_PlayerMapMarker.RemoveQuickSignMark(AK_PlayerMapMarker.MarkMap[KeyStr])
                    elseif AK_PlayerMapMarker.bUseNavigator then
                        AK_PlayerMapMarker.RemoveNavigatorMark(AK_PlayerMapMarker.MarkMap[KeyStr])
                    else
                        AK_PlayerMapMarker.HideMark(AK_PlayerMapMarker.MarkMap[KeyStr])
                    end
                    AK_PlayerMapMarker.MarkMap[KeyStr] = nil
                    AK_PlayerMapMarker.PlayerInfo[KeyStr] = nil
                end
            end
        end

        for KeyStr, MarkID in pairs(AK_PlayerMapMarker.MarkMap) do
            if not SeenKeys[KeyStr] then
                if AK_PlayerMapMarker.bUseQuickSign then
                    AK_PlayerMapMarker.RemoveQuickSignMark(MarkID)
                elseif AK_PlayerMapMarker.bUseNavigator then
                    AK_PlayerMapMarker.RemoveNavigatorMark(MarkID)
                else
                    AK_PlayerMapMarker.HideMark(MarkID)
                end
                AK_PlayerMapMarker.MarkMap[KeyStr] = nil
                AK_PlayerMapMarker.PlayerInfo[KeyStr] = nil
            end
        end

        return nCount
    end

    function AK_PlayerMapMarker.UpdateESP(AllPlayers, MyLoc)
        if not AK_PlayerMapMarker.bUseScreenESP then return end

        if not AK_PlayerMapMarker.InitESPCanvas() then
            return
        end

        if AK_PlayerMapMarker._OBHeadWidgetLoadFailed then return end

        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if AK_IsValid(PC) then
            AK_PlayerMapMarker.UpdateCanvasTransform(PC)
        end

        AK_PlayerMapMarker.bUseSnapLines = (_G.AK_GetVal and _G.AK_GetVal("ESP_LINE") == 1)

        local fromX, fromY = 0, 0
        if AK_PlayerMapMarker.bUseSnapLines and AK_IsValid(PC) then
            fromX, fromY = AK_PlayerMapMarker.GetSnapLineStartPos(PC)
        end

        local MyKey = AK_PlayerMapMarker.GetMyPlayerKey()
        local SeenKeys = {}
        
        local MyChar = nil
        pcall(function()
            local GDP = AK_PlayerMapMarker.GetGameplayData()
            if GDP and GDP.GetLocalCharacter then
                MyChar = GDP.GetLocalCharacter()
            else
                if PC and PC.GetPawn then MyChar = PC:GetPawn() end
            end
        end)
        local MyTeamID = AK_PlayerMapMarker.GetTeamID(MyChar)

        for PlayerKey, Character in pairs(AllPlayers) do
            if AK_IsValid(Character) then
                local bIsMe = AK_PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
                local bIsAI = AK_PlayerMapMarker.IsAI(Character)
                local KeyStr = tostring(PlayerKey)
                local isNormalBot, isMLBot = false, false
                if _G.AK_CheckIsBot then isNormalBot, isMLBot = _G.AK_CheckIsBot(Character) end
                
                local Name = "BOT"
                if not (isNormalBot or isMLBot) then
                    Name = AK_PlayerMapMarker.GetPlayerName(Character)
                end

                local Loc = AK_PlayerMapMarker.GetESPLocation(Character)

                local DistStr = ""
                if _G.AK_GetVal and _G.AK_GetVal("ESP_DISTANCE") == 1 then
                    AK_PlayerMapMarker.bShowDistance = true
                else
                    AK_PlayerMapMarker.bShowDistance = false
                end

                if MyLoc and Loc and AK_PlayerMapMarker.bShowDistance then
                    DistStr = AK_PlayerMapMarker.GetDistanceString(MyLoc, Loc)
                end

                local bSkip = false
                if bIsMe and not AK_PlayerMapMarker.bIncludeMe then bSkip = true end
                if bIsAI and not AK_PlayerMapMarker.bIncludeAI then bSkip = true end
                
                local TeamID = AK_PlayerMapMarker.GetTeamID(Character)
                if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then
                    bSkip = true
                end

                local bIsAlive = AK_PlayerMapMarker.IsAlive(Character)

                if not bSkip and Loc then
                    SeenKeys[KeyStr] = true
                    local ESPData = AK_PlayerMapMarker.ESPWidgets[KeyStr]

                    local TeamID = ESPData and ESPData.TeamID or AK_PlayerMapMarker.GetTeamID(Character)
                    local Text = ""
                    if _G.AK_GetVal and _G.AK_GetVal("ESP_TEAMID") == 1 and TeamID then
                        Text = tostring(TeamID) .. "  " .. Name
                    else
                        Text = Name
                    end
                    if DistStr and DistStr ~= "" then
                        Text = Text .. "  [" .. DistStr .. "]"
                    end

                    if not ESPData then
                        local Widget = AK_PlayerMapMarker.CreateESPWidget()
                        if Widget then
                            AK_PlayerMapMarker.ESPWidgets[KeyStr] = {
                                Widget = Widget,
                                Character = Character,
                                Name = Name,
                                LastDistStr = DistStr,
                                TeamID = TeamID,
                            }
                            if bIsAlive then
                                AK_PlayerMapMarker.ApplyTeamColor(Widget, TeamID)
                            else
                                local Container = Widget.Container or Widget
                                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                                Container._vis = 2
                            end
                        end
                    else
                        ESPData.Character = Character
                        ESPData.Name = Name
                        ESPData.LastDistStr = DistStr
                        if bIsAlive then
                            if TeamID ~= ESPData.TeamID then
                                ESPData.TeamID = TeamID
                                AK_PlayerMapMarker.ApplyTeamColor(ESPData.Widget, TeamID)
                            end
                        else
                            local Container = ESPData.Widget.Container or ESPData.Widget
                            if Container._vis ~= 2 then
                                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                                Container._vis = 2
                            end
                        end
                    end
                end
            end
        end

        for KeyStr, Data in pairs(AK_PlayerMapMarker.ESPWidgets) do
            if not SeenKeys[KeyStr] then
                AK_PlayerMapMarker.RemoveESPWidget(Data.Widget)
                AK_PlayerMapMarker.ESPWidgets[KeyStr] = nil
                
                AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
                AK_PlayerMapMarker.Remove2DBox(KeyStr)
            end
        end
    end
    
  
    function AK_PlayerMapMarker.UpdateEnvESPLight()
        if _G.AK_GetVal and _G.AK_GetVal("ESP_FULL_INFO") ~= 1 then return end
        local pc = AK_PlayerMapMarker.GetMyPlayerController()
        local myLoc = AK_PlayerMapMarker.GetMyLocation()
        local canvas = AK_PlayerMapMarker.ESPCanvas
        if not AK_IsValid(pc) or not myLoc or not slua.isValid(canvas) then return end

        local seenWidgets = {}

        local function DrawEnvUMG(key, actor, textStr, r, g, b, scale, zOffset)
            _G.AK_EnvWidgets = _G.AK_EnvWidgets or {}
            local wData = _G.AK_EnvWidgets[key]
            
            local bOnScreen, screenPos = false, import("Vector2D")(0,0)
            pcall(function()
                local loc = actor:K2_GetActorLocation()
                loc.Z = loc.Z + zOffset
                local res = pc:ProjectWorldLocationToScreen(loc, screenPos, true)
                if res == true or res == 1 then bOnScreen = true end
            end)

            if not bOnScreen then
                if wData and slua.isValid(wData.Widget) and wData._vis ~= 2 then 
                    pcall(function() wData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end); wData._vis = 2
                end
                return
            end

            seenWidgets[key] = true

            if not wData then
                local txt = nil
                pcall(function() txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", canvas) end)
                if txt and slua.isValid(txt) then
                    pcall(function() txt.RenderTransformPivot = import("Vector2D")(0.5, 0.5) end)
                    local slot = canvas:AddChildToCanvas(txt)
                    if slot then
                        slot:SetAutoSize(true); slot:SetAlignment(import("Vector2D")(0.5, 0.5)); slot:SetZOrder(1)
                        wData = { Widget = txt, Slot = slot, _vis = 0 }
                        _G.AK_EnvWidgets[key] = wData
                    end
                end
            end

            if wData and slua.isValid(wData.Widget) then
                if wData._vis ~= 0 then pcall(function() wData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end); wData._vis = 0 end
                
                if wData._lastTxt ~= textStr then
                    pcall(function() wData.Widget:SetText(textStr); wData.Widget:SetJustification(1) end)
                    wData._lastTxt = textStr
                end

                pcall(function()
                    local col = import("LinearColor")(r/255.0, g/255.0, b/255.0, 1.0)
                    local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                    if FSlateColor then wData.Widget:SetColorAndOpacity(FSlateColor(col)) else wData.Widget:SetColorAndOpacity(col) end
                    
                    if not wData._fInit then
                        local f = wData.Widget.Font
                        f.Size = 11; f.OutlineSettings.OutlineSize = 1; f.OutlineSettings.OutlineColor = import("LinearColor")(0,0,0,1)
                        wData.Widget:SetFont(f); wData._fInit = true
                    end
                    wData.Widget:SetRenderScale(import("Vector2D")(scale, scale))
                end)

                local cvsPos = AK_PlayerMapMarker.ScreenPixelToCanvasLocal(pc, screenPos)
                if not wData._cPos or math.abs(wData._cPos.X - cvsPos.X) > 0.05 or math.abs(wData._cPos.Y - cvsPos.Y) > 0.05 then
                    wData._cPos = cvsPos
                    pcall(function() wData.Slot:SetPosition(cvsPos) end)
                end
            end
        end

        if _G.AK_GetVal("ESP_CAR") == 1 and _G.AK_CachedCars then
            for _, veh in ipairs(_G.AK_CachedCars) do
                if slua.isValid(veh) then
                    local dist = AK_PlayerMapMarker.CalcDistance(myLoc, veh:K2_GetActorLocation()) / 100.0
                    if dist <= 400 then
                        local dynamicScale = math.max(0.6, 1.0 - (dist / 400))
                        local vehName = "PHƯƠNG TIỆN"; local r,g,b = 200,200,200
                        pcall(function()
                            local className = import("KismetSystemLibrary").GetClassDisplayName(veh:GetClass())
                            if string.find(className, "MotorcycleCart") or string.find(className, "SideCar") then vehName = "MOTOR 3 BÁNH"; r,g,b = 255,215,0
                            elseif string.find(className, "Glider") then vehName = "TÀU LƯỢN"; r,g,b = 255,250,205
                            elseif string.find(className, "Motorcycle") or string.find(className, "Motor") then vehName = "MOTOR 2 BÁNH"; r,g,b = 255,255,0
                            elseif string.find(className, "CoupeRB") or string.find(className, "SportsCar") then vehName = "COUPE RB"; r,g,b = 0,250,154
                            elseif string.find(className, "UAZ") then vehName = "UAZ"; r,g,b = 0,255,0
                            elseif string.find(className, "Dacia") then vehName = "DACIA"; r,g,b = 0,191,255
                            elseif string.find(className, "Buggy") then vehName = "BUGGY"; r,g,b = 255,20,147
                            elseif string.find(className, "Mirado") then vehName = "MIRADO"; r,g,b = 255,140,0
                            elseif string.find(className, "Scooter") then vehName = "SCOOTER"; r,g,b = 135,206,235
                            elseif string.find(className, "Boat") or string.find(className, "PG117") then vehName = "CA NÔ"; r,g,b = 0,0,255
                            end
                        end)
                        local infoStr = vehName .. "\n[" .. tostring(math.floor(dist)) .. "m]"
                        DrawEnvUMG("CAR_"..tostring(veh), veh, infoStr, r, g, b, dynamicScale, 100)
                    end
                end
            end
        end
        
        if _G.AK_GetVal("ESP_BOMB") == 1 and _G.AK_CachedBombs then
            local gameTime = 0.0
            pcall(function() gameTime = AK_PlayerMapMarker.GetCGameState():GetServerWorldTimeSeconds() end)
            if not _G.AK_BombTimers then _G.AK_BombTimers = {} end

            for _, bomb in ipairs(_G.AK_CachedBombs) do
                if slua.isValid(bomb) and not bomb.bExploded and not (bomb.bHidden or (bomb.Mesh and bomb.Mesh.bHidden)) then
                    local dist = AK_PlayerMapMarker.CalcDistance(myLoc, bomb:K2_GetActorLocation()) / 100.0
                    if dist <= 100 then
                        local itemID = 0
                        pcall(function()
                            local className = import("KismetSystemLibrary").GetClassDisplayName(bomb:GetClass())
                            if string.find(className, "Smoke") then itemID = 602002 
                            elseif string.find(className, "Burn") or string.find(className, "Molotov") then itemID = 602003 
                            elseif string.find(className, "Grenade") then itemID = 602004 end
                        end)

                        if itemID > 0 then
                            local dynamicScale = math.max(0.6, 1.0 - (dist / 100))
                            local infoStr = ""; local r,g,b = 255,255,255
                            local addr = tostring(bomb)

                            if itemID == 602004 then
                                if not _G.AK_BombTimers[addr] then _G.AK_BombTimers[addr] = gameTime end
                                local timeLeft = 7.0 - (gameTime - _G.AK_BombTimers[addr])
                                if timeLeft < 0 then timeLeft = 0.0 end
                                if timeLeft <= 2.0 then r,g,b = 255,0,0 else r,g,b = 255,165,0 end
                                infoStr = "[BOM NỔ]\n[" .. tostring(math.floor(timeLeft * 10) / 10) .. "s]\n[" .. tostring(math.floor(dist)) .. "m]"
                            elseif itemID == 602003 then
                                r,g,b = 255,69,0; infoStr = "[BOM LỬA]\n[" .. tostring(math.floor(dist)) .. "m]"
                            elseif itemID == 602002 then
                                r,g,b = 0,255,0; infoStr = "[BOM KHÓI]\n[" .. tostring(math.floor(dist)) .. "m]"
                            end

                            DrawEnvUMG("BOMB_"..addr, bomb, infoStr, r, g, b, dynamicScale * 1.2, 50)
                        end
                    end
                end
            end
        end

        if _G.AK_GetVal("ESP_ITEM") == 1 and _G.AK_CachedItems then
            if not _G.AK_LootedItems then _G.AK_LootedItems = {} end

            for _, data in ipairs(_G.AK_CachedItems) do
                local item = data.actor
                if slua.isValid(item) then
                    local isGhost = false
                    local addr = tostring(item)
                    
                    pcall(function() if item:IsPendingKill() then isGhost = true end end)
                    
                    if not isGhost then
                        local itemLoc = item:K2_GetActorLocation()
                        if (itemLoc.X == 0 and itemLoc.Y == 0) or itemLoc.Z < -5000 then
                            isGhost = true
                        end
                        
                        local dist = AK_PlayerMapMarker.CalcDistance(myLoc, itemLoc) / 100.0
                        
                        local isHidden = false
                        pcall(function()
                            isHidden = item.bHidden or item.bIsHidden
                            if not isHidden and item.Mesh then isHidden = item.Mesh.bHidden or false end
                            if not isHidden and type(item.IsHidden) == "function" then isHidden = item:IsHidden() end
                        end)
                        
                        if not data.isDrop then
                            if not isHidden then
                                _G.AK_LootedItems[addr] = nil
                            else
                                if dist < 12.0 then
                                    _G.AK_LootedItems[addr] = true
                                end
                            end
                            if _G.AK_LootedItems[addr] then isGhost = true end
                        else
                            if isHidden then isGhost = true end
                        end
                        
                        if not isGhost and dist > 0.1 and dist <= 150 then
                            local scaleDist = dist > 150 and 150 or dist
                            local dynamicScale = math.max(0.6, 1.0 - (scaleDist / 150))
                            local infoStr = "[" .. data.name .. "]\n[" .. tostring(math.floor(dist)) .. "m]"
                            DrawEnvUMG("ITEM_"..addr, item, infoStr, data.r, data.g, data.b, dynamicScale, 30)
                            seenWidgets["ITEM_"..addr] = true
                        end
                    end
                end
            end
        end

        if _G.AK_EnvWidgets then
            for k, wData in pairs(_G.AK_EnvWidgets) do
                if not seenWidgets[k] then
                    if wData and slua.isValid(wData.Widget) then
                        pcall(function() wData.Widget:RemoveFromParent(); wData.Widget:ConditionalBeginDestroy() end)
                    end
                    _G.AK_EnvWidgets[k] = nil
                end
            end
        end
    end
    

    function AK_PlayerMapMarker.UpdateESPLight()
        if _G.AK_GetVal and _G.AK_GetVal("ESP_FULL_INFO") ~= 1 then return end

        if AK_RedBoxOverlay.bActive then
            AK_RedBoxOverlay.UpdatePosition()
        end

        if not AK_PlayerMapMarker.bUseScreenESP then return end
        if not AK_PlayerMapMarker.ESPCanvas or not Game:IsValid(AK_PlayerMapMarker.ESPCanvas) then return end

        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if not AK_IsValid(PC) then return end

        AK_PlayerMapMarker.UpdateCanvasTransform(PC)

        AK_PlayerMapMarker.bUseSnapLines = (_G.AK_GetVal and _G.AK_GetVal("ESP_LINE") == 1)
        local fromX, fromY = 0, 0
        if AK_PlayerMapMarker.bUseSnapLines then
            fromX, fromY = AK_PlayerMapMarker.GetSnapLineStartPos(PC)
        end

        local MyLoc = AK_PlayerMapMarker.GetMyLocation()

        for KeyStr, ESPData in pairs(AK_PlayerMapMarker.ESPWidgets) do
            local Widget = ESPData.Widget
            local Character = ESPData.Character
            local Container = Widget and (Widget.Container or Widget)
            local bWidgetValid = false
            pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

            if Widget and bWidgetValid and Character and AK_IsValid(Character) then
                local bIsAlive = AK_PlayerMapMarker.IsAlive(Character)

                if not bIsAlive then
                    if Container._vis ~= 2 then
                        pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        Container._vis = 2
                    end
                    AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
                    AK_PlayerMapMarker.Remove2DBox(KeyStr)
                else
                    local rootLoc = AK_PlayerMapMarker.GetCharacterLocation(Character)
                    local topLoc = AK_PlayerMapMarker.GetESPLocation(Character)
                    
                    if rootLoc and topLoc then
                        local dist2D = 0
                        if MyLoc then
                            dist2D = AK_PlayerMapMarker.CalcDistance(MyLoc, rootLoc) / 100.0
                        end

                        rootLoc.Z = rootLoc.Z - 90
                        topLoc.Z = topLoc.Z + 15
                        
                        local bOnBot, botPos = AK_PlayerMapMarker.ProjectWorldToCanvasLocal(PC, rootLoc)
                        local bOnTop, topPos = AK_PlayerMapMarker.ProjectWorldToCanvasLocal(PC, topLoc)
                        
                        local isVisible = (bOnBot or bOnTop)
                        
                        if isVisible then
                            local estHeight = 18000 / math.max(dist2D, 1)
                            if estHeight > 3000 then estHeight = 3000 elseif estHeight < 15 then estHeight = 15 end
                            
                            if bOnBot and not bOnTop then
                                topPos = import("Vector2D")(botPos.X, botPos.Y - estHeight)
                            elseif bOnTop and not bOnBot then
                                botPos = import("Vector2D")(topPos.X, topPos.Y + estHeight)
                            end
                            
                            if botPos.Y < topPos.Y then
                                local tempY = botPos.Y
                                botPos.Y = topPos.Y
                                topPos.Y = tempY
                            end
                            
                            local height = botPos.Y - topPos.Y
                            
                            if height > 3000 then
                                botPos.Y = topPos.Y + 3000
                            end
                            
                            if dist2D > 650 then
                                isVisible = false
                            end
                        end

                        if isVisible then

                            if Container._vis ~= 0 then
                                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                                Container._vis = 0
                            end
                            
                            AK_PlayerMapMarker.UpdateESPPositionWithPC(Widget, topLoc, PC, topPos)
                            
                            if not ESPData.bCleanedUpUMG then
                                local hideNames = {"TextBlock_TeamID", "TextBlock_PlayerTeamID", "Text_TeamID", "TextBlock_Team", "Image_TeamBG", "Image_TeamLogoBG", "TeamBgBorder", "Image_RingBG", "Image_TeamBG_2", "SizeBox_HP"}
                                for _, name in ipairs(hideNames) do
                                    local w = Container[name]
                                    if w and slua.isValid(w) then pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
                                end
                                if Widget.NameText and slua.isValid(Widget.NameText) then pcall(function() Widget.NameText:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
                                if Container.TextBlock_PlayerName and slua.isValid(Container.TextBlock_PlayerName) then pcall(function() Container.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
                                if Container.TextBlock_TeamName and slua.isValid(Container.TextBlock_TeamName) then pcall(function() Container.TextBlock_TeamName:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) end
                                ESPData.bCleanedUpUMG = true
                            end
                            
                            local bShowBox      = (_G.AK_GetVal("ESP_BOX") == 1)
                            local bShowHealth   = (_G.AK_GetVal("ESP_HEALTH") == 1)
                            local bShowName     = (_G.AK_GetVal("ESP_NAME") == 1)
                            local bShowDistance = (_G.AK_GetVal("ESP_DISTANCE") == 1)
                            local bShowTeam     = (_G.AK_GetVal("ESP_TEAMID") == 1)
                            local bShowLine     = (_G.AK_GetVal("ESP_LINE") == 1)

                            local isNormalBot, isMLBot = false, false
                            if _G.AK_CheckIsBot then isNormalBot, isMLBot = _G.AK_CheckIsBot(Character) end
                            local isBot = isNormalBot or isMLBot
                            local espColor = isBot and import("LinearColor")(1, 1, 1, 1) or import("LinearColor")(1, 0, 0, 1)

                            if bShowLine then
                                AK_PlayerMapMarker.UpdateSnapLine(KeyStr, topPos, isVisible, fromX, fromY, espColor)
                            else
                                AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
                            end

                            AK_PlayerMapMarker.Update2DBox(KeyStr, topPos, botPos, espColor, isVisible and bShowBox)

                            local HP, MaxHP = 100, 100
                            pcall(function()
                                HP = type(Character.GetHealth) == "function" and Character:GetHealth() or Character.Health or 0
                                MaxHP = type(Character.GetHealthMax) == "function" and Character:GetHealthMax() or Character.MaxHealth or 100
                            end)
                            local pct = (HP > 0 and MaxHP > 0) and (HP / MaxHP) or 0
                            if pct > 1 then pct = 1 elseif pct < 0 then pct = 0 end
                            
                            AK_PlayerMapMarker.Update2DHealthBar(KeyStr, topPos, botPos, pct, isVisible and bShowHealth)

                          
                            local distStr   = bShowDistance and (ESPData.LastDistStr or "") or ""
                            local nameStr   = bShowName and (ESPData.Name or "Unknown") or ""
                            local teamIDStr = bShowTeam and (ESPData.TeamID and tostring(ESPData.TeamID) or "") or ""
                            
                            AK_PlayerMapMarker.Update2DTextData(KeyStr, topPos, botPos, nameStr, distStr, teamIDStr, isVisible, espColor)

 
                            AK_PlayerMapMarker.AddWeaponIconToESP(Widget, Character)

                        else

                            if Container._vis ~= 2 then
                                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                                Container._vis = 2
                            end
                            AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
                            AK_PlayerMapMarker.Update2DBox(KeyStr, nil, nil, nil, false)
                            AK_PlayerMapMarker.Update2DHealthBar(KeyStr, nil, nil, 0, false)
                            AK_PlayerMapMarker.Update2DTextData(KeyStr, nil, nil, "", "", "", false, nil)
                        end
                    else
                        if Container._vis ~= 2 then
                            pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            Container._vis = 2
                        end
                        AK_PlayerMapMarker.RemoveSnapLine(KeyStr)
                        AK_PlayerMapMarker.Update2DBox(KeyStr, nil, nil, nil, false)
                        AK_PlayerMapMarker.Update2DHealthBar(KeyStr, nil, nil, 0, false)
                        AK_PlayerMapMarker.Update2DTextData(KeyStr, nil, nil, "", "", "", false, nil)
                    end
                end
            end
        end
    end

    function AK_PlayerMapMarker.UpdateESPDistances()
        if _G.AK_GetVal and _G.AK_GetVal("ESP_DISTANCE") ~= 1 then return end
        if not AK_PlayerMapMarker.bUseScreenESP then return end

        local MyLoc = AK_PlayerMapMarker.GetMyLocation()
        if not MyLoc then return end

        local PC = AK_PlayerMapMarker.GetMyPlayerController()
        if not AK_IsValid(PC) then return end

        AK_PlayerMapMarker.UpdateCanvasTransform(PC)

        for KeyStr, ESPData in pairs(AK_PlayerMapMarker.ESPWidgets) do
            local Character = ESPData.Character
            local Widget = ESPData.Widget
            local Container = Widget and (Widget.Container or Widget)
            local bWidgetValid = false
            pcall(function() bWidgetValid = Container and slua.isValid(Container) end)
            if Character and AK_IsValid(Character) and Widget and bWidgetValid then
                local Loc = AK_PlayerMapMarker.GetESPLocation(Character)
                if Loc then
                    local Dist = AK_PlayerMapMarker.CalcDistance(MyLoc, Loc)
                    ESPData.LastDistance = Dist

                    if AK_PlayerMapMarker.bShowDistance then
                        local DistStr = ""
                        local Meters = 0
                        if Dist then
                            Meters = Dist / 100
                            if Meters < 1000 then
                                DistStr = tostring(math.floor(Meters)) .. "m"
                            else
                                local kmFloor = math.floor((Meters / 1000) * 10) / 10
                                DistStr = tostring(kmFloor) .. "km"
                            end
                        end

                        ESPData.LastDistStr = DistStr
                    end
                end
            end
        end
    end

    function AK_PlayerMapMarker.OnTick(deltaTime)
        if not AK_PlayerMapMarker.bActive then return end

        pcall(function()
            local currentPC = AK_PlayerMapMarker.GetMyPlayerController()
            if AK_PlayerMapMarker._LastPC ~= currentPC then
                AK_PlayerMapMarker.ClearAllESP()
                AK_PlayerMapMarker._LastPC = currentPC
                AK_PlayerMapMarker.ESPCanvas = nil
            end

            AK_PlayerMapMarker._FrameCount = AK_PlayerMapMarker._FrameCount + 1
            local frame = AK_PlayerMapMarker._FrameCount

            if frame % AK_PlayerMapMarker.nHeavyScanFrameInterval == 0 then
                local AllChars = AK_PlayerMapMarker.GetAllCharacters()
                if AllChars then
                    local MyLoc = AK_PlayerMapMarker.GetMyLocation()
                    AK_PlayerMapMarker._CachedAllChars = AllChars
                    AK_PlayerMapMarker._CachedMyLoc = MyLoc
                    AK_PlayerMapMarker.UpdateESP(AllChars, MyLoc)
                end
            end

            if frame % AK_PlayerMapMarker.nDistanceUpdateFrameInterval == 0 then
                AK_PlayerMapMarker.UpdateESPDistances()
            end

            AK_PlayerMapMarker.UpdateESPLight()
        end)
    end

    AK_PlayerMapMarker._WorkingWidgetPath = nil
    AK_PlayerMapMarker._FailedWidgetPaths = {}

    AK_PlayerMapMarker.WidgetCompUIPaths = {
        "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips_C",
        "/Game/BluePrints/ControlInput/IngameUI/TipsItem/ChangeSight_Item01_UIBP.ChangeSight_Item01_UIBP_C",
        "/Game/Mod/PlanBT/BluePrints/UI/Fusion/FusionTitle_UIBP.FusionTitle_UIBP_C",
        "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips",
    }

    function AK_PlayerMapMarker.CreateWidgetCompForPlayer(Character, Text)
        if not AK_IsValid(Character) then return nil end
        local Mesh = AK_PlayerMapMarker.GetCharacterMesh(Character)
        if not Mesh or not Game:IsValid(Mesh) then return nil end

        if AK_PlayerMapMarker._bAllPathsFailed then return nil end

        local PathsToTry = {}
        if AK_PlayerMapMarker._WorkingWidgetPath then
            table.insert(PathsToTry, AK_PlayerMapMarker._WorkingWidgetPath)
        else
            for _, path in ipairs(AK_PlayerMapMarker.WidgetCompUIPaths) do
                if not AK_PlayerMapMarker._FailedWidgetPaths[path] then
                    table.insert(PathsToTry, path)
                end
            end
        end

        if #PathsToTry == 0 then
            AK_PlayerMapMarker._bAllPathsFailed = true
            return nil
        end

        local STExtraBlueprintFunctionLibrary = nil
        pcall(function() STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary") end)
        if not STExtraBlueprintFunctionLibrary then return nil end

        local Widget = nil
        local UsedPath = nil
        for _, path in ipairs(PathsToTry) do
            local ok = false
            pcall(function()
                Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByPathName(path, Character)
                if Widget and slua.isValid(Widget) then ok = true end
            end)
            if ok and Widget then
                UsedPath = path
                AK_PlayerMapMarker._WorkingWidgetPath = path
                break
            else
                Widget = nil
                AK_PlayerMapMarker._FailedWidgetPaths[path] = true
            end
        end

        if not Widget then
            if not AK_PlayerMapMarker._WorkingWidgetPath then
                AK_PlayerMapMarker._bAllPathsFailed = true
            end
            return nil
        end

        local WidgetComp = nil
        pcall(function()
            local UWidgetComponent = import("WidgetComponent")
            WidgetComp = Game:AddComponent(UWidgetComponent, Character, "PlayerMapMarkerWidget")

            if WidgetComp and Game:IsValid(WidgetComp) then
                WidgetComp.AlwaysLoadOnClient = true
                WidgetComp.AlwaysLoadOnServer = false
                WidgetComp:SetOwnerNoSee(false)
                WidgetComp.bGenerateOverlapEvents = false
                WidgetComp.bCanEverAffectNavigation = false
                WidgetComp.bUseAttachParentBound = true
                WidgetComp.Space = 1

                pcall(function() WidgetComp:SetHiddenInGame(false) end)
                pcall(function() WidgetComp:SetVisibility(true) end)
                pcall(function() WidgetComp:SetComponentTickEnabled(true) end)

                pcall(function() WidgetComp:SetDrawSize(AK_PlayerMapMarker.WidgetCompDrawSize) end)
                WidgetComp:SetWidget(Widget)
                WidgetComp:RequestRedraw()

                WidgetComp:K2_AttachToComponent(
                    Mesh,
                    AK_PlayerMapMarker.WidgetCompBoneName,
                    UEnums.EAttachmentRule.SnapToTarget,
                    UEnums.EAttachmentRule.SnapToTarget,
                    UEnums.EAttachmentRule.KeepWorld,
                    false
                )

                local KismetMathLibrary = import("KismetMathLibrary")
                local Transform = KismetMathLibrary.MakeTransform(
                    AK_PlayerMapMarker.WidgetCompOffset,
                    FRotator(0, 180, 0),
                    FVector(1, 1, 1)
                )
                WidgetComp:K2_SetRelativeTransform(Transform, false, nil, false)

                local UserWidget = WidgetComp:GetUserWidgetObject()
                if UserWidget and Game:IsValid(UserWidget) then
                    pcall(function()
                        if UserWidget.PlayerName then
                            UserWidget.PlayerName:SetText(Text or "")
                        elseif UserWidget.TextTitle then
                            UserWidget.TextTitle:SetText(Text or "")
                        elseif UserWidget.UTRichTextBlock_Tips22_Text1 then
                            UserWidget.UTRichTextBlock_Tips22_Text1:SetText(Text or "")
                        end
                    end)
                end

                CGame:RegisterComponent(WidgetComp)
                pcall(function() WidgetComp:RequestRedraw() end)
            end
        end)

        if not WidgetComp or not Game:IsValid(WidgetComp) then
            if WidgetComp and Game:IsValid(WidgetComp) then
                pcall(function() WidgetComp:DestroyComponent() end)
            end
            return nil
        end

        return WidgetComp
    end

    function AK_PlayerMapMarker.UpdateWidgetCompText(WidgetComp, Text)
        if not WidgetComp or not Game:IsValid(WidgetComp) then return end
        pcall(function()
            local UserWidget = WidgetComp:GetUserWidgetObject()
            if UserWidget and Game:IsValid(UserWidget) then
                if UserWidget.PlayerName then
                    UserWidget.PlayerName:SetText(Text or "")
                elseif UserWidget.TextTitle then
                    UserWidget.TextTitle:SetText(Text or "")
                elseif UserWidget.UTRichTextBlock_Tips22_Text1 then
                    UserWidget.UTRichTextBlock_Tips22_Text1:SetText(Text or "")
                end
            end
        end)
    end

    function AK_PlayerMapMarker.RemoveWidgetComp(WidgetComp)
        if not WidgetComp then return end
        pcall(function()
            if Game:IsValid(WidgetComp) then
                WidgetComp:K2_DetachFromComponent(2, false)
                local UserWidget = WidgetComp:GetUserWidgetObject()
                if UserWidget and Game:IsValid(UserWidget) then
                    UserWidget:RemoveFromViewport()
                    UserWidget:ConditionalBeginDestroy()
                end
                WidgetComp:DestroyComponent()
            end
        end)
    end

    function AK_PlayerMapMarker.ClearAllWidgetComps()
        for KeyStr, WidgetComp in pairs(AK_PlayerMapMarker.WidgetComps) do
            AK_PlayerMapMarker.RemoveWidgetComp(WidgetComp)
        end
        AK_PlayerMapMarker.WidgetComps = {}
    end

    function AK_PlayerMapMarker.UpdateWidgetComps(AllPlayers, MyLoc)
        if not AK_PlayerMapMarker.bUseWidgetComponent then return end
        if AK_PlayerMapMarker._bAllPathsFailed then return end

        local MyKey = AK_PlayerMapMarker.GetMyPlayerKey()
        local SeenKeys = {}

        for PlayerKey, Character in pairs(AllPlayers) do
            if AK_IsValid(Character) then
                local bIsMe = AK_PlayerMapMarker.IsMe(Character, PlayerKey, MyKey)
                local bIsAI = AK_PlayerMapMarker.IsAI(Character)
                local KeyStr = tostring(PlayerKey)
                local Name = AK_PlayerMapMarker.GetPlayerName(Character)
                local Loc = AK_PlayerMapMarker.GetCharacterLocation(Character)

                local DistStr = ""
                if MyLoc and Loc then
                    DistStr = AK_PlayerMapMarker.GetDistanceString(MyLoc, Loc)
                end

                local bSkip = false
                if bIsMe and not AK_PlayerMapMarker.bIncludeMe then bSkip = true end
                if bIsAI and not AK_PlayerMapMarker.bIncludeAI then bSkip = true end

                if not bSkip then
                    SeenKeys[KeyStr] = true
                    local Text = Name
                    if DistStr and DistStr ~= "" then
                        Text = Name .. " [" .. DistStr .. "]"
                    end

                    local ExistingComp = AK_PlayerMapMarker.WidgetComps[KeyStr]
                    if not ExistingComp or not Game:IsValid(ExistingComp) then
                        local WidgetComp = AK_PlayerMapMarker.CreateWidgetCompForPlayer(Character, Text)
                        if WidgetComp then
                            AK_PlayerMapMarker.WidgetComps[KeyStr] = WidgetComp
                        end
                    else
                        AK_PlayerMapMarker.UpdateWidgetCompText(ExistingComp, Text)
                    end
                end
            end
        end

        for KeyStr, WidgetComp in pairs(AK_PlayerMapMarker.WidgetComps) do
            if not SeenKeys[KeyStr] then
                AK_PlayerMapMarker.RemoveWidgetComp(WidgetComp)
                AK_PlayerMapMarker.WidgetComps[KeyStr] = nil
            end
        end
    end

    function AK_PlayerMapMarker.CreateMark(Location, CustomString, Actor)
        if not AK_PlayerMapMarker.bUseScreenMark and not Location then return nil end

        local InstID = nil
        local Flag = AK_GetMapAddedFlag()

        local MarkPos = Location
        if AK_PlayerMapMarker.bUseScreenMark then
            MarkPos = nil
        end

        if AK_PlayerMapMarker.bUseServerMarks then
            pcall(function()
                InstID = InGameMarkTools.ServerAddMapMark(
                    AK_PlayerMapMarker.MarkTypeID,
                    MarkPos,
                    nil,
                    nil,
                    nil,
                    UEnums.EMarkDispatchRange.EMAMDT_ALL,
                    nil,
                    Actor
                )
            end)
        else
            pcall(function()
                local actorObj = Actor and (Actor.Object or Actor) or nil
                InstID = InGameMarkTools.ClientAddMapMark(
                    AK_PlayerMapMarker.MarkTypeID,
                    MarkPos,
                    0,
                    CustomString or "",
                    Flag,
                    actorObj,
                    0,
                    nil
                )
            end)
        end

        return InstID
    end

    function AK_PlayerMapMarker.UpdateMarkLocation(InstID, Location)
        if not InstID or not Location then return end
        pcall(function()
            InGameMarkTools.UpdateMapMarkLocation(InstID, Location)
        end)
    end

    function AK_PlayerMapMarker.HideMark(InstID)
        if not InstID then return end
        pcall(function()
            InGameMarkTools.HideMapMark(InstID)
        end)
    end

    function AK_PlayerMapMarker.ShowMark(InstID)
        if not InstID then return end
        pcall(function()
            InGameMarkTools.ShowMapMark(InstID)
        end)
    end

    function AK_PlayerMapMarker.UpdateMarkString(InstID, sName)
        if not InstID or not sName then return end
        pcall(function()
            InGameMarkTools.UpdateMapMarkCustomString(InstID, sName)
        end)
    end

    function AK_PlayerMapMarker.ClearAllMarks()
        for KeyStr, MarkID in pairs(AK_PlayerMapMarker.MarkMap) do
            if AK_PlayerMapMarker.bUseQuickSign then
                AK_PlayerMapMarker.RemoveQuickSignMark(MarkID)
            elseif AK_PlayerMapMarker.bUseNavigator then
                AK_PlayerMapMarker.RemoveNavigatorMark(MarkID)
            else
                AK_PlayerMapMarker.HideMark(MarkID)
            end
        end
        AK_PlayerMapMarker.MarkMap = {}
        AK_PlayerMapMarker.PlayerInfo = {}
        AK_PlayerMapMarker.ClearAllWidgetComps()
        AK_PlayerMapMarker.ClearAllESP()
    end

    function AK_PlayerMapMarker.AttachTimers()
        local ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
        if not ticker or not ticker.AddTimerLoop then return end

         
        if AK_PlayerMapMarker.MasterTimerHandle then 
            ticker.RemoveTimer(AK_PlayerMapMarker.MasterTimerHandle) 
            AK_PlayerMapMarker.MasterTimerHandle = nil
        end

        local frameCount = 0

 
        AK_PlayerMapMarker.MasterTimerHandle = ticker.AddTimerLoop(0, function()
            if not AK_PlayerMapMarker.bActive then return end

            pcall(function()
                frameCount = frameCount + 1
 
                AK_PlayerMapMarker.UpdateESPLight()
                AK_PlayerMapMarker.UpdateEnvESPLight()

 
                if frameCount % 6 == 0 then
                    if AK_PlayerMapMarker.bUseScreenESP and AK_PlayerMapMarker.bShowDistance then
                        AK_PlayerMapMarker.UpdateESPDistances()
                    end
                end

 
                if frameCount >= 30 then
                    local currentPC = AK_PlayerMapMarker.GetMyPlayerController()
                    if currentPC and AK_PlayerMapMarker._LastPC ~= currentPC then
                        AK_PlayerMapMarker.ClearAllESP()
                        AK_PlayerMapMarker._LastPC = currentPC
                        AK_PlayerMapMarker.ESPCanvas = nil
                    end

                    AK_PlayerMapMarker.ScanAndUpdate()
                    
                    frameCount = 0 
                end
            end)
        end, -1, 0.016)
    end

    function AK_PlayerMapMarker.Start()
        if AK_PlayerMapMarker.bActive then
            return
        end

        AK_PlayerMapMarker.bActive = true
        AK_PlayerMapMarker._FrameCount = 0

        AK_PlayerMapMarker.ScanAndUpdate()
        AK_PlayerMapMarker.AttachTimers()
    end

    function AK_PlayerMapMarker.Stop()
        AK_PlayerMapMarker.bActive = false
        AK_PlayerMapMarker._FrameCount = 0

        local ticker = package.loaded["common.time_ticker"] or require("common.time_ticker")
        if ticker then

            if AK_PlayerMapMarker.MasterTimerHandle then 
                ticker.RemoveTimer(AK_PlayerMapMarker.MasterTimerHandle)
                AK_PlayerMapMarker.MasterTimerHandle = nil 
            end
        end

        AK_PlayerMapMarker.ClearAllMarks()
    end

    function AK_PlayerMapMarker.Reset()
        AK_PlayerMapMarker.ClearAllMarks()
    end

    function AK_PlayerMapMarker.ManualScan()
        return AK_PlayerMapMarker.ScanAndUpdate()
    end

    _G.AK_PlayerMapMarker = AK_PlayerMapMarker
    AK_PlayerMapMarker.Start()
end
