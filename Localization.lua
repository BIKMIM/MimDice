-- MimDice localization bootstrap.
-- English phrases are the canonical keys. LocalizationAliases.lua normalizes
-- legacy Korean source calls to those English keys, and missing translations
-- always fall back to the canonical English text.

local localeData = {}
local localeNames = {}
local sourceAliases = {}

function MimDice_RegisterSourceAliases(aliases)
    for source, english in pairs(aliases or {}) do
        sourceAliases[source] = english
    end
end

function MimDice_RegisterLocale(locale, displayName, translations)
    if type(locale) ~= "string" or locale == "" then return end
    localeData[locale] = translations or {}
    localeNames[locale] = displayName or locale
end

local function ResolveLanguage()
    local requested = MimDiceDB and MimDiceDB.language or "auto"
    if requested ~= "auto" and localeData[requested] then
        return requested
    end

    local detected = GetLocale and GetLocale() or "enUS"
    if localeData[detected] then
        return detected
    end
    return "enUS"
end

function MimDice_GetLanguage()
    return ResolveLanguage()
end

function MimDice_GetLanguageSetting()
    local requested = MimDiceDB and MimDiceDB.language or "auto"
    if requested ~= "auto" and not localeData[requested] then
        return "auto"
    end
    return requested
end

function MimDice_GetLocaleName(locale)
    return localeNames[locale] or locale
end

function MimDice_GetAvailableLocales()
    local ret = {}
    for locale, name in pairs(localeNames) do
        ret[#ret + 1] = { locale = locale, name = name }
    end
    local preferredOrder = { koKR = 1, enUS = 2 }
    table.sort(ret, function(a, b)
        local aOrder = preferredOrder[a.locale] or 99
        local bOrder = preferredOrder[b.locale] or 99
        if aOrder ~= bOrder then return aOrder < bOrder end
        return a.name < b.name
    end)
    return ret
end

function MimDice_L(key, ...)
    if type(key) ~= "string" then return key end

    local canonicalKey = sourceAliases[key] or key

    local language = ResolveLanguage()
    local translated = localeData[language] and localeData[language][canonicalKey]
    if translated == nil and language ~= "enUS" then
        translated = localeData.enUS and localeData.enUS[canonicalKey]
    end
    if translated == nil then translated = canonicalKey end

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, translated, ...)
        if ok then return formatted end
    end
    return translated
end
