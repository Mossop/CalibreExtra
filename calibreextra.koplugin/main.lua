--[[
    This plugin implements KOReader integration with *some* calibre features:

        - metadata search
        - wireless transfers

    This module handles the UI part of the plugin.
--]]

local BD = require("ui/bidi")
local CalibreExtensions = require("cex/extensions")
local CalibreMetadata = require("cex/metadata")
local CalibreWireless = require("cex/wireless")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

local Calibre = WidgetContainer:extend{
    name = "calibreextra",
    is_doc_only = false,
}

function Calibre:onNetworkDisconnected()
    CalibreWireless:disconnect()
end

function Calibre:onSuspend()
    CalibreWireless:disconnect()
end

function Calibre:onClose()
    CalibreWireless:disconnect()
end

function Calibre:onCloseWidget()
    CalibreWireless:disconnect()
end

function Calibre:onStartWirelessConnection()
   CalibreWireless:connect()
end

function Calibre:onCloseWirelessConnection()
    CalibreWireless:disconnect()
end

function Calibre:onDispatcherRegisterActions()
    Dispatcher:registerAction("calibreextra_start_connection", { category="none", event="StartWirelessConnection", title=_("Calibre wireless connect"), general=true,})
    Dispatcher:registerAction("calibreextra_close_connection", { category="none", event="CloseWirelessConnection", title=_("Calibre wireless disconnect"), general=true,})
end

function Calibre:init()
    CalibreWireless:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Calibre:addToMainMenu(menu_items)
    menu_items.calibreextra = {
        -- its name is "calibreextra", but all our top menu items are uppercase.
        text = _("Calibre Extra"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    if CalibreWireless.calibre_socket then
                        return _("Disconnect")
                    else
                        return _("Connect")
                    end
                end,
                separator = true,
                enabled_func = function()
                    return G_reader_settings:nilOrTrue("calibre_wireless")
                end,
                callback = function()
                    if not CalibreWireless.calibre_socket then
                        CalibreWireless:connect()
                    else
                        CalibreWireless:disconnect()
                    end
                end,
            },
            {
                text = _("Fields"),
                sub_item_table = self:getFieldsMenuTable(),
            },
            {
                text = _("Wireless settings"),
                keep_menu_open = true,
                sub_item_table = self:getWirelessMenuTable(),
            },
        }
    }
end

-- Browse field menu
function Calibre:getFieldsMenuTable()
    local enabled_fields = G_reader_settings:readSetting("calibre_enabled_fields", {})

    local function field_menu(id, name)
        return {
            text = name,
            keep_menu_open = true,
            checked_func = function()
                return enabled_fields[id]
            end,
            callback = function()
                if enabled_fields[id] then
                    enabled_fields[id] = nil;
                else
                    enabled_fields[id] = true
                end

                G_reader_settings:saveSetting("calibre_enabled_fields", enabled_fields)
            end
        }
    end

    local submenu = {
        field_menu("title", _("Title")),
        field_menu("authors", _("Authors")),
        field_menu("tags", _("Tags")),
        field_menu("series", _("Series"))
    }

    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    if inbox_dir then
        CalibreMetadata:init(inbox_dir)
        for k, field in pairs(CalibreMetadata:getLibraryFields()) do
            if field.datatype ~= "float" then
                table.insert(submenu, field_menu(k, field.name))
            end
        end
        CalibreMetadata:clean()
    end

    return submenu
end

-- wireless options available from UI
function Calibre:getWirelessMenuTable()
    local function isEnabled()
        local enabled = G_reader_settings:nilOrTrue("calibre_wireless")
        return enabled and not CalibreWireless.calibre_socket
    end

    local t = {
        {
            text = _("Enable wireless client"),
            separator = true,
            enabled_func = function()
                return not CalibreWireless.calibre_socket
            end,
            checked_func = function()
                return G_reader_settings:nilOrTrue("calibre_wireless")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("calibre_wireless")
            end,
        },
        {
            text = _("Set password"),
            enabled_func = isEnabled,
            callback = function()
                CalibreWireless:setPassword()
            end,
        },
        {
            text = _("Set inbox folder"),
            enabled_func = isEnabled,
            callback = function()
                CalibreWireless:setInboxDir()
            end,
        },
        {
            text_func = function()
                local address = _("automatic")
                if G_reader_settings:has("calibre_wireless_url") then
                    address = G_reader_settings:readSetting("calibre_wireless_url")
                    address = string.format("%s:%s", address["address"], address["port"])
                end
                return T(_("Server address (%1)"), BD.ltr(address))
            end,
            enabled_func = isEnabled,
            sub_item_table = {
                {
                    text = C_("Configuration type", "Automatic"),
                    checked_func = function()
                        return G_reader_settings:hasNot("calibre_wireless_url")
                    end,
                    callback = function()
                        G_reader_settings:delSetting("calibre_wireless_url")
                    end,
                },
                {
                    text = C_("Configuration type", "Manual"),
                    checked_func = function()
                        return G_reader_settings:has("calibre_wireless_url")
                    end,
                    check_callback_updates_menu = true,
                    callback = function(touchmenu_instance)
                        local MultiInputDialog = require("ui/widget/multiinputdialog")
                        local url_dialog
                        local calibre_url = G_reader_settings:readSetting("calibre_wireless_url")
                        local calibre_url_address, calibre_url_port
                        if calibre_url then
                            calibre_url_address = calibre_url["address"]
                            calibre_url_port = calibre_url["port"]
                        end
                        url_dialog = MultiInputDialog:new{
                            title = _("Set custom calibre address"),
                            fields = {
                                {
                                    text = calibre_url_address,
                                    input_type = "string",
                                    hint = _("IP Address"),
                                },
                                {
                                    text = calibre_url_port,
                                    input_type = "number",
                                    hint = _("Port"),
                                },
                            },
                            buttons =  {
                                {
                                    {
                                        text = _("Cancel"),
                                        id = "close",
                                        callback = function()
                                            UIManager:close(url_dialog)
                                        end,
                                    },
                                    {
                                        text = _("OK"),
                                        callback = function()
                                            local fields = url_dialog:getFields()
                                            if fields[1] ~= "" then
                                                local port = tonumber(fields[2])
                                                if not port or port < 1 or port > 65355 then
                                                    --default port
                                                     port = 9090
                                                end
                                                G_reader_settings:saveSetting("calibre_wireless_url", {address = fields[1], port = port })
                                            end
                                            UIManager:close(url_dialog)
                                            if touchmenu_instance then touchmenu_instance:updateItems() end
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:show(url_dialog)
                        url_dialog:onShowKeyboard()
                    end,
                },
            },
        },
    }

    if not CalibreExtensions:isCustom() then
        table.insert(t, 2, {
            text = _("File formats"),
            enabled_func = isEnabled,
            sub_item_table_func = function()
                local submenu = {
                    {
                        text = _("About formats"),
                        keep_menu_open = true,
                        separator = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = string.format("%s: %s \n\n%s",
                                _("Supported file formats"),
                                CalibreExtensions:getInfo(),
                                _("Unsupported formats will be converted by calibre to the first format of the list."))
                            })
                        end,
                    }
                }

                for i, v in ipairs(CalibreExtensions.outputs) do
                    table.insert(submenu, {})
                    submenu[i+1].text = v
                    submenu[i+1].checked_func = function()
                        if v == CalibreExtensions.default_output then
                            return true
                        end
                        return false
                    end
                    submenu[i+1].callback = function()
                        if type(v) == "string" and v ~= CalibreExtensions.default_output then
                            CalibreExtensions.default_output = v
                            G_reader_settings:saveSetting("calibre_wireless_default_format", CalibreExtensions.default_output)
                        end
                    end
                end
                return submenu
            end,
        })
    end
    return t
end

return Calibre
