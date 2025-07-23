local CalibreMetadata = require("cex/metadata")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local rapidjson = require("rapidjson")
local sort = require("sort")
local time = require("ui/time")

local TITLE_FIELD = {
    name = _("Title"),
    datatype = "text",
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
    cache = nil,
    current = nil,
    field_browser = nil,
}

function CalibreBrowse:display()
    self.field_browser:switchItemTable(self.current.name, self.current.entries, 1)
    UIManager:show(self.field_browser)
end

function CalibreBrowse:push(menu)
    if self.current then
        table.insert(self.field_browser.paths, self.current)
    end

    self.current = menu

    self:display()
end

function CalibreBrowse:pop()
    self.current = table.remove(self.field_browser.paths)
    self:display()
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
                callback = function()
                end
            })
        else
            table.insert(entries, {
                text = field.name,
                callback = function()
                    self:push_field(field)
                end
            })
        end
    end

    local sort_fn
    if node.ordering == "index" then
        sort_fn = function(a, b)
            return a.index - b.index
        end
    else
        local natsort = sort.natsort_cmp()
        sort_fn = function(a, b)
            return natsort(a.text, b.text)
        end
    end

    table.sort(entries, sort_fn)

    self:push({ name = node.name, entries = entries })
end

function CalibreBrowse:browse()
    local start_time = time.now()

    local inbox_dir = G_reader_settings:readSetting("inbox_dir")
    CalibreMetadata:init(inbox_dir)

    local fields = {}
    local enabled_fields = G_reader_settings:readSetting("calibre_enabled_fields", {})

    local function add_field(id, field, values, book, index)
        if not enabled_fields[id] or values == rapidjson.null then
            return
        end

        if not fields[id] then
            local field_order
            if field.datatype == "author" then
                field_order = "author"
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
            end

            table.insert(fields[id].children[value].children, {
                index = index,
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
        add_field("title", TITLE_FIELD, book.title, book)
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

    self.field_browser = Menu:new{
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onReturn = function()
            self:pop()
        end,
        onClose = function()
            Menu.onClose(self.field_browser)

            self.cache = nil
            self.current = nil
            self.field_browser = nil
        end
    }

    self.current = nil
    self:push_field(self.cache)
end

return CalibreBrowse
