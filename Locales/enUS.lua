-- English is the canonical source locale. Phrase keys are already English, so
-- no duplicate values are required here. To add another language, copy
-- koKR.lua and translate its values while keeping the English keys unchanged.
MimDice_RegisterLocale("enUS", "English", {
    ["CUSTOM_SOUND_FOLDER_HELP"] = "Store your personal sound files in World of Warcraft\\_retail_\\sound to keep them when the addon updates.\nIf the sound folder does not exist, you can create it.\nUse MP3 (.mp3) or OGG (.ogg) files. Restart the game after adding files to make them available.",
    ["FONT_ADD_HELP"] = "□ Do not use WoW's main Fonts folder.\n□ Put the font file in Interface\\AddOns\\MimDice\\Fonts.\n□ Only TTF and OTF files are supported.\n□ Enter the exact filename and click Add.\n□ Fully restart the game after adding a new font file.\n□ Select the font, then reload the UI to apply it.",
})
