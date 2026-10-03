-- Custom filenames are relative to the game folder or the bundled sounds folder.
-- Personal files outside the addon survive MimDice updates.
MimDiceSoundFiles = {}
local SoundFiles = MimDiceSoundFiles
local folders = {
    "sound\\",
    "sounds\\",
    "Interface\\AddOns\\MimDice\\sounds\\",
}
local resolvedPaths = {}

-- Dialog is a game-wide switch, independent of its volume slider. Ask before
-- changing it; a muted channel must not be reported as a missing sound file.
local L = MimDice_L
local dialogPopup = "MIMDICE_ENABLE_DIALOG_SOUND"
local dialogNoticeShown = false
local dialogNoticePending = false
local dialogEvents = CreateFrame("Frame")

local function ResetDialogNotice()
    dialogNoticeShown = false
    dialogNoticePending = false
    dialogEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
    StaticPopup_Hide(dialogPopup)
end

function SoundFiles.CheckDialogChannel(forcePrompt)
    if GetCVar("Sound_EnableDialog") ~= "0" then
        if dialogNoticeShown or dialogNoticePending then ResetDialogNotice() end
        return true
    end

    if StaticPopup_Visible(dialogPopup) then return false end
    if forcePrompt then dialogNoticeShown = false end
    if dialogNoticeShown then return false end

    -- An automatic combat alert should not put a confirmation over the fight.
    if InCombatLockdown() then
        dialogNoticePending = true
        dialogEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    StaticPopupDialogs[dialogPopup] = {
        text = L("[MimDice]\nDialog sound is disabled in WoW, so MimDice cannot play its alerts.\n\nEnabling it also enables NPC dialogue. Turn it on now?"),
        button1 = L("Enable Dialog sound"),
        button2 = L("Later"),
        OnAccept = function()
            local ok = pcall(SetCVar, "Sound_EnableDialog", "1")
            if ok and GetCVar("Sound_EnableDialog") == "1" then
                ResetDialogNotice()
                DEFAULT_CHAT_FRAME:AddMessage(L("|cff00ff00[MimDice]|r Dialog sound is enabled. Use a sound preview to check playback."))
            else
                DEFAULT_CHAT_FRAME:AddMessage(L("|cffffff00[MimDice]|r Could not enable Dialog sound. Please enable it in WoW's audio settings."))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    dialogNoticePending = false
    dialogEvents:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if StaticPopup_Show(dialogPopup) then dialogNoticeShown = true end
    return false
end

dialogEvents:RegisterEvent("CVAR_UPDATE")
dialogEvents:SetScript("OnEvent", function(_, event, name)
    if event == "CVAR_UPDATE" then
        if type(name) == "string" and name:lower() == "sound_enabledialog"
            and GetCVar("Sound_EnableDialog") ~= "0" then
            ResetDialogNotice()
        end
    elseif event == "PLAYER_REGEN_ENABLED" and dialogNoticePending then
        SoundFiles.CheckDialogChannel()
    end
end)

function SoundFiles.Play(file, channel)
    if type(file) ~= "string" or file == "" then return false end
    for _, folder in ipairs(folders) do
        local path = folder .. file
        local ok, willPlay, handle = pcall(PlaySoundFile, path, channel or "Dialog")
        if ok and willPlay then
            resolvedPaths[file] = path
            return true, handle, path
        end
    end
    return false
end

function SoundFiles.Resolve(file)
    if type(file) ~= "string" or file == "" then return nil end
    if resolvedPaths[file] then return resolvedPaths[file] end
    if type(StopSound) ~= "function" then return nil end

    -- AuraSound needs a single path before the buff occurs. Probe playback and
    -- immediately stop its handle; cache successes only, until the next reload.
    -- Master avoids treating a disabled Dialog channel as a missing file.
    local played, handle, path = SoundFiles.Play(file, "Master")
    if played then
        if type(handle) == "number" then pcall(StopSound, handle, 0) end
        return path
    end
    return nil
end
