local BookList = require("ui/widget/booklist")
local CalibreMetadata = require("cex/metadata")
local FileChooser = require("ui/widget/filechooser")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rapidjson = require("rapidjson")
local time = require("ui/time")

local BookBrowser = FileChooser:extend{
}

function BookBrowser:init()
    self.path_items = {}
    BookList.init(self)
end

local FieldBrowser = Menu:extend{
    covers_fullscreen = true,
    is_borderless = true,
    is_popout = false,
}

local AUTHORS_FIELD = {
    name = _("Authors"),
    datatype = "author",
}

local TAGS_FIELD = {
    name = _("Tags"),
    datatype = "text",
}

local SERIES_FIELD = {
    name = _("Series"),
    datatype = "series",
}

-- This is a singleton
local CalibreBrowse = WidgetContainer:extend{
    inbox_dir = nil,
    cache = nil,
    current = nil,
    field_browser = nil,
    book_browser = nil,
    stack = nil,
}

function CalibreBrowse:display()
    if self.current.datatype == "book" then
        self.book_browser = self.book_browser or BookBrowser:new{
            onReturn = function()
                self:pop()
            end,
            onFileSelect = function(browser, item)
                self:close()

                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("SetupShowReader"))

                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(item.path)
            end,
            onClose = function()
                FileChooser.onClose(self.book_browser)
                self.book_browser = nil
                self:close()
            end
        }

        local files = {}
        for _, entry in ipairs(self.current.entries) do
            local fullpath = self.inbox_dir .. '/' .. entry.lpath
            local attributes = lfs.attributes(fullpath) or {}
            local file_entry = self.book_browser:getListItem(self.inbox_dir, entry.text, fullpath, attributes, {})
            table.insert(files, file_entry)
        end

        self.book_browser.paths = self.stack
        self.book_browser:switchItemTable(self.current.name, files, 1)
        UIManager:show(self.book_browser)
    else
        self.field_browser = self.field_browser or FieldBrowser:new{
            onReturn = function()
                self:pop()
            end,
            onClose = function()
                Menu.onClose(self.field_browser)
                self.field_browser = nil
                self:close()
            end
        }

        if #self.stack > 0 then
            self.field_browser.onReturn = function()
                self:pop()
            end
        else
            self.field_browser.onReturn = nil
        end

        self.field_browser.paths = self.stack
        self.field_browser:switchItemTable(self.current.name, self.current.entries, 1)
        UIManager:show(self.field_browser)
    end
end

function CalibreBrowse:push(menu)
    if self.current then
        table.insert(self.stack, self.current)
    end

    self.current = menu

    self:display()
end

function CalibreBrowse:pop()
    self.current = table.remove(self.stack)
    self:display()
end

local function name(value)
    if value == true then
        return _("Yes")
    elseif value == false then
        return _("No")
    else
        return value
    end
end

function CalibreBrowse:push_field(node)
    local entries = {}
    for _, field in ipairs(node.children) do
        if field.book then
            local text
            if node.ordering == "index" then
                text = string.format("%d - %s", field.index, field.book.title)
            else
                text = field.book.title
            end

            table.insert(entries, {
                index = field.index,
                text = text,
                lpath = field.book.lpath,
                callback = function()
                end
            })
        else
            table.insert(entries, {
                text = name(field.name),
                sort_text = field.sort_name,
                callback = function()
                    self:push_field(field)
                end
            })
        end
    end

    local sort_fn
    if node.ordering == "index" then
        sort_fn = function(a, b)
            return a.index < b.index
        end
    else
        sort_fn = function(a, b)
            local a_text = a.sort_text or a.text
            local b_text = b.sort_text or b.text
            return ffiUtil.strcoll(a_text, b_text)
        end
    end

    table.sort(entries, sort_fn)

    local title = name(node.name)
    if #self.stack > 0 then
        title = self.current.name .. ": " .. title
    end

    self:push({
        name = title,
        ordering = node.ordering,
        datatype = node.datatype,
        entries = entries,
    })
end

function CalibreBrowse:close()
    if self.field_browser then
        UIManager:close(self.field_browser)
    end

    if self.book_browser then
        UIManager:close(self.book_browser)
    end

    self.cache = nil
    self.current = nil
    self.field_browser = nil
    self.book_browser = nil
    self.stack = nil
end

function CalibreBrowse:browse()
    local start_time = time.now()

    self.inbox_dir = G_reader_settings:readSetting("inbox_dir")
    CalibreMetadata:init(self.inbox_dir)

    local fields = {
        title = {
            name = _("All Books"),
            ordering = "text",
            datatype = "book",
            children = {}
        }
    }
    local enabled_fields = G_reader_settings:readSetting("calibreextra_enabled_fields", {})

    local function add_field(id, field, values, book, index)
        if enabled_fields[id] == false or values == rapidjson.null or field.datatype == "float" then
            return
        end

        if not fields[id] then
            local field_order
            if field.datatype == "author" then
                field_order = "author"
            elseif field.datatype == "bool" then
                field_order = "bool"
            else
                field_order = "text"
            end

            fields[id] = {
                name = field.name,
                ordering = field_order,
                children = {}
            }
        end

        if type(values) ~= "table" then
            values = { values }
        end

        local book_order
        if field.datatype == "series" then
            book_order = "index"
        else
            book_order = "text"
        end

        for _, value in ipairs(values) do
            if not fields[id].children[value] then
                fields[id].children[value] = {
                    name = value,
                    datatype = "book",
                    ordering = book_order,
                    children = {}
                }

                if id == "authors" then
                    fields[id].children[value].sort_name = book.author_sort_map[value]
                end
            end

            table.insert(fields[id].children[value].children, {
                index = tonumber(index) or 1,
                book = book
            })
        end
    end

    local function map_to_array(map)
        local tbl = {}
        for _, value in pairs(map) do
            if value.datatype ~= "book" then
                value.children = map_to_array(value.children)
            end

            table.insert(tbl, value)
        end

        return tbl
    end

    for _, book in ipairs(CalibreMetadata.books) do
        table.insert(fields.title.children, { book = book })

        add_field("authors", AUTHORS_FIELD, book.authors, book)
        add_field("tags", TAGS_FIELD, book.tags, book)
        add_field("series", SERIES_FIELD, book.series, book, book.series_index)

        for key, field in pairs(book.user_metadata) do
            add_field(key, field, field["#value#"], book, field["#extra#"])
        end
    end

    CalibreMetadata:clean()

    self.cache = {
        name = _("Calibre"),
        ordering = "text",
        children = map_to_array(fields),
    }

    logger.info(string.format("Built browse cache in %.3f milliseconds",
        time.to_ms(time.since(start_time))))

    self.current = nil
    self.stack = {}
    self:push_field(self.cache)
end

return CalibreBrowse
