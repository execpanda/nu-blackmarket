-- Nu-Blackmarket Server Script
-- Handles all server-side logic using QBX Core (QBox) functions

local currentStock = {}

-- Initialize stock levels from config
local function initializeStock()
    for _, category in pairs(Config.Items) do
        for _, item in pairs(category.items) do
            local stockKey = category.category .. "_" .. item.name
            currentStock[stockKey] = item.stock
        end
    end
    if Config.Debug then
        lib.print.info("[Nu-Blackmarket] Stock initialized")
    end
end

-- Refresh stock based on config settings
local function refreshStock()
    if not Config.StockRefresh.enabled then return end
    
    for _, category in pairs(Config.Items) do
        for _, item in pairs(category.items) do
            if item.stock > 0 then
                local stockKey = category.category .. "_" .. item.name
                local currentLevel = currentStock[stockKey] or 0
                local maxStock = item.stock
                local refreshAmount = math.floor(maxStock * Config.StockRefresh.percentage)
                currentStock[stockKey] = math.min(currentLevel + refreshAmount, maxStock)
            end
        end
    end

    if Config.Debug then
        lib.print.info("[Nu-Blackmarket] Stock refreshed")
    end
end

-- Get current stock for an item
local function getItemStock(category, itemName)
    local stockKey = category .. "_" .. itemName
    return currentStock[stockKey] or 0
end

-- Update stock for an item
local function updateItemStock(category, itemName, quantity)
    local stockKey = category .. "_" .. itemName
    if currentStock[stockKey] then
        currentStock[stockKey] = math.max(0, currentStock[stockKey] - quantity)
        return true
    end
    return false
end

-- Check if player has required job restrictions
local function checkJobRestrictions(source)
    if not Config.JobRestrictions or #Config.JobRestrictions == 0 then
        return true
    end

    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false end

    local playerJob = Player.PlayerData.job.name
    for _, restrictedJob in pairs(Config.JobRestrictions) do
        if playerJob == restrictedJob then
            return false
        end
    end
    return true
end


local function hasAndUseTicket(source)
    if not Config.Ticket.enabled then
        return true -- ticket system disabled, allow
    end

    local ticketCount = exports.ox_inventory:GetItemCount(source, Config.Ticket.itemName)
    if ticketCount < 1 then
        return false
    end

    if Config.Ticket.removeOnUse then
        local removed = exports.ox_inventory:RemoveItem(source, Config.Ticket.itemName, 1)
        if not removed then
            return false
        end
    end

    return true
end


-- Check time restrictions

local function checkTimeRestrictions(currentHour)
    if not Config.TimeRestrictions.enabled then
        return true
    end

    local startHour = Config.TimeRestrictions.startHour
    local endHour = Config.TimeRestrictions.endHour

    if startHour > endHour then
        return currentHour >= startHour or currentHour <= endHour
    else
        return currentHour >= startHour and currentHour <= endHour
    end
end

-- local function checkTimeRestrictions()
--     if not Config.TimeRestrictions.enabled then
--         return true
--     end

--     local currentHour = tonumber(os.date("%H"))
--     local startHour = Config.TimeRestrictions.startHour
--     local endHour = Config.TimeRestrictions.endHour

--     if startHour > endHour then
--         return currentHour >= startHour or currentHour <= endHour
--     else
--         return currentHour >= startHour and currentHour <= endHour
--     end
-- end

-- Get player money
local function getPlayerMoney(source, moneyType)
    if moneyType == "cash" or moneyType == "bank" or moneyType == "crypto" then
        local amount = exports.qbx_core:GetMoney(source, moneyType)
        return amount or 0
    else
        local itemCount = exports.ox_inventory:GetItemCount(source, moneyType)
        return itemCount or 0
    end
end

-- Remove money
local function removePlayerMoney(source, moneyType, amount)
    if moneyType == "cash" or moneyType == "bank" or moneyType == "crypto" then
        return exports.qbx_core:RemoveMoney(source, moneyType, amount, "blackmarket-purchase")
    else
        return exports.ox_inventory:RemoveItem(source, moneyType, amount)
    end
end

-- Add money
local function addPlayerMoney(source, moneyType, amount)
    if moneyType == "cash" or moneyType == "bank" or moneyType == "crypto" then
        exports.qbx_core:AddMoney(source, moneyType, amount, "blackmarket-refund")
    else
        exports.ox_inventory:AddItem(source, moneyType, amount)
    end
end

-- Find item in config
local function findItemInConfig(itemName)
    for _, category in pairs(Config.Items) do
        for _, item in pairs(category.items) do
            if item.name == itemName then
                return item, category.category
            end
        end
    end
    return nil, nil
end

-- Send Discord webhook
local function sendWebhook(playerName, citizenid, items, totalCost)
    if not Config.Webhook.enabled or not Config.Webhook.url or Config.Webhook.url == "" then
        return
    end

    local itemsList = ""
    for _, item in pairs(items) do
        itemsList = itemsList .. "• " .. item.label .. " x" .. item.quantity .. " ($" .. (item.price * item.quantity) .. ")\n"
    end

    local embed = {
        {
            title = Config.Webhook.title,
            description = "**Player:** " .. playerName .. "\n**Citizen ID:** " .. citizenid .. "\n**Total Cost:** $" .. totalCost .. "\n\n**Items Purchased:**\n" .. itemsList,
            color = Config.Webhook.color,
            footer = {
                text = Config.Webhook.footer .. " • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    PerformHttpRequest(Config.Webhook.url, function(err, text, headers) end, "POST", json.encode({ embeds = embed }), { ["Content-Type"] = "application/json" })
end

RegisterNetEvent("nu-blackmarket:checkAccess", function(inGameHour)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src) -- QBX Core player retrieval
    if not Player then
        TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Player not found")
        return
    end

    -- Time check: pass the inGameHour to your time check function (you need to adjust it to accept parameter)
    if not checkTimeRestrictions(inGameHour) then
        TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Black Market is closed right now.")
        return
    end

    -- Job check
    -- Check job restrictions
    if not checkJobRestrictions(src) then
        TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Nah Piggy, i smelt you a mile away! Get outta 'ere or ill call Diddy!")
        return
    end
    
    -- Ticket check
    if Config.Ticket.enabled then
        local itemCount = exports.ox_inventory:GetItemCount(src, Config.Ticket.itemName)
        if not itemCount or itemCount < 1 then
            TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Ey man,  Wheres the Item you were supposed to bring? Dont come back till you have it! k?")
            return
        end

     if Config.Ticket.removeOnUse then
            exports.ox_inventory:RemoveItem(src, Config.Ticket.itemName, 1)
        end
    end
    -- All checks passed: open the UI
    TriggerClientEvent("nu-blackmarket:client:openUIAllowed", src)
end)



-- RegisterNetEvent("nu-blackmarket:server:requestOpenUI", function()
--     local src = source
--     local Player = exports.qbx_core:GetPlayer(src)
--     if not Player then return end

--     -- Check job restrictions
--     if not checkJobRestrictions(src) then
--         TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Nah Piggy, i smelt you a mile away! Get outta 'ere or ill call Diddy!")
--         return
--     end

--     -- Check time restrictions
--     if not checkTimeRestrictions() then
--         TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Dont you see im closed? Get outta here foo!")
--         return
--     end

    -- if Config.Ticket.enabled then
    --     local itemCount = exports.ox_inventory:GetItemCount(src, Config.Ticket.itemName)
    --     if not itemCount or itemCount < 1 then
    --         TriggerClientEvent("nu-blackmarket:client:openUIDenied", src, "Ey man,  Wheres the Item you were supposed to bring? Dont come back till you have it! k?")
    --         return
    --     end

    --  if Config.Ticket.removeOnUse then
    --         exports.ox_inventory:RemoveItem(src, Config.Ticket.itemName, 1)
    --     end
    -- end
--     -- Passed all checks, allow UI open
--     TriggerClientEvent("nu-blackmarket:client:openUIAllowed", src)
-- end)



RegisterNetEvent("nu-blackmarket:server:getStock", function()
    local src = source
    local stockData = {}
    for _, category in pairs(Config.Items) do
        stockData[category.category] = {}
        for _, item in pairs(category.items) do
            stockData[category.category][item.name] = getItemStock(category.category, item.name)
        end
    end
    local moneyAmount = getPlayerMoney(src, Config.Currency.type)
    TriggerClientEvent("nu-blackmarket:client:receiveStock", src, stockData)
    TriggerClientEvent("nu-blackmarket:client:receivePlayerMoney", src, moneyAmount, Config.Currency.type)
end)

RegisterNetEvent("nu-blackmarket:server:getPlayerMoney", function()
    local src = source
    local moneyAmount = getPlayerMoney(src, Config.Currency.type)
    TriggerClientEvent("nu-blackmarket:client:receivePlayerMoney", src, moneyAmount, Config.Currency.type)
end)

RegisterNetEvent("nu-blackmarket:server:purchaseItems", function(cartItems)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Player data not found")
        return
    end

    if not cartItems or type(cartItems) ~= "table" or #cartItems == 0 then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Invalid cart data")
        return
    end

    if not checkJobRestrictions(src) then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Access denied due to job restrictions")
        return
    end

    if not checkTimeRestrictions() then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Black market is closed at this time")
        return
    end

    local validatedItems = {}
    local totalCost = 0

    for _, cartItem in pairs(cartItems) do
        local configItem, category = findItemInConfig(cartItem.name)
        if not configItem then
            TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Invalid item: " .. cartItem.name)
            return
        end

        local availableStock = getItemStock(category, cartItem.name)
        if configItem.stock > 0 and availableStock < cartItem.quantity then
            TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Insufficient stock for " .. configItem.label)
            return
        end

        if configItem.maxQuantity and cartItem.quantity > configItem.maxQuantity then
            TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Maximum quantity exceeded for " .. configItem.label)
            return
        end

        table.insert(validatedItems, {
            name = cartItem.name,
            label = configItem.label,
            quantity = cartItem.quantity,
            price = configItem.price,
            metadata = configItem.metadata or {}
        })

        totalCost = totalCost + (configItem.price * cartItem.quantity)
    end

    local playerMoney = getPlayerMoney(src, Config.Currency.type)
    if playerMoney < totalCost then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Insufficient funds")
        return
    end

    if not removePlayerMoney(src, Config.Currency.type, totalCost) then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Failed to process payment")
        return
    end

    local success = true
    local addedItems = {}

    for _, item in pairs(validatedItems) do
        local configItem, category = findItemInConfig(item.name)
        local itemAdded = exports.ox_inventory:AddItem(src, item.name, item.quantity, item.metadata)

        if itemAdded then
            if configItem.stock > 0 then
                updateItemStock(category, item.name, item.quantity)
            end
            table.insert(addedItems, item)
        else
            success = false
            lib.print.error("[Nu-Blackmarket] Failed to add item: " .. item.name .. " for player: " .. src)
        end
    end

    if success and #addedItems > 0 then
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, true, "Purchase successful!")
        sendWebhook(Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname, Player.PlayerData.citizenid, addedItems, totalCost)

        if Config.Debug then
            lib.print.info("[Nu-Blackmarket] Purchase completed for player: " .. src .. " | Items: " .. #addedItems .. " | Cost: $" .. totalCost)
        end
    else
        addPlayerMoney(src, Config.Currency.type, totalCost)
        TriggerClientEvent("nu-blackmarket:client:purchaseResult", src, false, "Failed to process some items. Money refunded.")
    end
end)

-- Initialize when resource starts
CreateThread(function()
    initializeStock()
    if Config.StockRefresh.enabled then
        while true do
            Wait(Config.StockRefresh.interval * 60000)
            refreshStock()
        end
    end
end)

-- Export functions for other resources
exports("getItemStock", getItemStock)
exports("updateItemStock", updateItemStock)
exports("getCurrentStock", function()
    return currentStock
end)

lib.print.info("^2[Nu-Blackmarket]^7 Server script loaded successfully!")
