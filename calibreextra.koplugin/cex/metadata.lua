--[[--
This module implements functions for loading, saving and editing calibre metadata files.

Calibre uses JSON to store metadata on device after each wired transfer.
In wireless transfers calibre sends the same metadata to the client, which is in charge
of storing it.
--]]--

local BookList = require("ui/widget/booklist")
local DocSettings = require("docsettings")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local rapidjson = require("rapidjson")
local logger = require("logger")
local util = require("util")
local time = require("ui/time")
local _ = require("gettext")
local T = FFIUtil.template

local used_metadata = {
    "uuid",
    "lpath",
    "last_modified",
    "size",
    "title",
    "authors",
    "author_sort_map",
    "tags",
    "series",
    "series_index"
}

local function slim_user_metadata(user_metadata)
    local slim_metadata = rapidjson.object({})
    for key, data in pairs(user_metadata) do
        local slim_field = rapidjson.object({})
        slim_field.name = data.name
        slim_field.datatype = data.datatype
        slim_field["#value#"] = data["#value#"] or rapidjson.null
        slim_field["#extra#"] = data["#extra#"] or rapidjson.null

        slim_metadata[key] = slim_field
    end

    return slim_metadata
end

local function slim_book(book)
    local slim_book = rapidjson.object({})
    for _, k in ipairs(used_metadata) do
        if k == "series" or k == "series_index" then
            slim_book[k] = book[k] or rapidjson.null
        elseif k == "tags" or k == "authors" then
            slim_book[k] = book[k] or rapidjson.array({})
        else
            slim_book[k] = book[k]
        end
    end
    slim_book.user_metadata = slim_user_metadata(book.user_metadata)
    return slim_book
end

--- find calibre files for a given dir
local function findCalibreFiles(dir)
    local function existOrLast(file)
        local fullname
        local options = { file, "." .. file }
        for _, option in ipairs(options) do
            fullname = dir .. "/" .. option
            if util.fileExists(fullname) then
                return true, fullname
            end
        end
        return false, fullname
    end
    local ok_meta, file_meta = existOrLast("metadata.calibre")
    local ok_drive, file_drive = existOrLast("driveinfo.calibre")
    return ok_meta, ok_drive, file_meta, file_drive
end

local CalibreMetadata = {
    -- info about the library itself. It should
    -- hold a table with the contents of "driveinfo.calibre"
    drive = rapidjson.array({}),
    -- info about the books in this library. It should
    -- hold a table with the contents of "metadata.calibre"
    books = rapidjson.array({}),
}

--- loads driveinfo from JSON file
function CalibreMetadata:loadDeviceInfo(file)
    if not file then file = self.driveinfo end
    local json, err = rapidjson.load(file)
    if not json then
        logger.warn("Unable to load device info from JSON file:", err)
        return {}
    end
    return json
end

-- saves driveinfo to JSON file
function CalibreMetadata:saveDeviceInfo(arg)
    -- keep previous device name. This allow us to identify the calibre driver used.
    -- "Folder" is used by connect to folder
    -- "KOReader" is used by smart device app
    -- "Amazon", "Kobo", "Bq" ... are used by platform device drivers
    local previous_name = self.drive.device_name
    self.drive = arg
    if previous_name then
        self.drive.device_name = previous_name
    end
    rapidjson.dump(self.drive, self.driveinfo)
end

-- Gets the custom fields for the library
function CalibreMetadata:getLibraryCustomFields()
    local fields = {}
    for key, field in pairs(self.drive.fieldMetadata) do
        if string.sub(key, 1, 1) == "#" then
            local default = field.display.default_value
            if default == nil then
                default = rapidjson.null
            end

            fields[key] = {
                datatype = field.datatype,
                name = field.name,
                default = default,
            }
        end
    end

    return fields
end

function CalibreMetadata:setLibraryFields(fieldMetadata)
    self.drive.fieldMetadata = fieldMetadata
    rapidjson.dump(self.drive, self.driveinfo)
end

-- loads books' metadata from JSON file
function CalibreMetadata:loadBookList()
    local attr = lfs.attributes(self.metadata)
    if not attr then
        logger.warn("Unable to get file attributes from JSON file:", self.metadata)
        return rapidjson.array({})
    end
    local valid = attr.mode == "file" and attr.size > 0
    if not valid then
        logger.warn("File is invalid", self.metadata)
        return rapidjson.array({})
    end
    local books, err = rapidjson.load(self.metadata)
    if not books then
        logger.warn(string.format("Unable to load library from json file %s: \n%s",
            self.metadata, err))
        return rapidjson.array({})
    end
    return books
end

-- saves books' metadata to JSON file
function CalibreMetadata:saveBookList()
    local file = self.metadata
    local books = self.books
    rapidjson.dump(books, file, { pretty = true })

    local read_field = G_reader_settings:readSetting("calibreextra_read_field")
    if read_field then
        local fields = self:getLibraryCustomFields()
        if not fields[read_field] or fields[read_field].datatype ~= "bool" then
            G_reader_settings:saveSetting("calibreextra_read_field", nil)

            UIManager:show(InfoMessage:new{
                text = T(_("Calibre Extra: No longer syncing read status with missing field '%1'"), read_field),
            })
        end
    end
end

-- add a book to our books table
function CalibreMetadata:addBook(book)
    -- prevent duplicate entries
    if not self:updateBook(book) then
        table.insert(self.books, #self.books + 1, slim_book(book))
        self:updateRead(book)
    end
end

-- update a book in our books table if exists
function CalibreMetadata:updateBook(book)
    local _, index = self:getBookUuid(book.lpath)
    if index then
        self.books[index] = slim_book(book)
        self:updateRead(book)
        return true
    end
    return false
end

function CalibreMetadata:updateRead(book)
    local read_field = G_reader_settings:readSetting("calibreextra_read_field")
    if read_field then
        local updated_is_read = nil
        for k, v in pairs(book.user_metadata) do
            if k == read_field and v["#value#"] ~= rapidjson.null then
                updated_is_read = v["#value#"]
            end
        end

        if updated_is_read == nil then
            return
        end

        local full_path = self.path .. "/" .. book.lpath
        local summary = BookList.getBookInfo(full_path) or {}
        local local_is_read = summary.status == "complete"

        if updated_is_read ~= nil then
            if local_is_read ~= updated_is_read then
                local doc_settings = DocSettings:open(full_path)
                if updated_is_read then
                    summary.status = "complete"
                else
                    summary.status = nil
                end
                BookList.setBookInfoCacheProperty(full_path, "status", summary.status)
                doc_settings:saveSetting("summary", summary)
                doc_settings:flush()
            end
        end
    end
end

function CalibreMetadata:updateReadField()
    for _, book in ipairs(self.books) do
        self:updateRead(book)
    end
end

-- remove a book from our books table
function CalibreMetadata:removeBook(lpath)
    local function drop_lpath(t, i, j)
        return t[i].lpath ~= lpath
    end
    util.arrayRemove(self.books, drop_lpath)
end

-- gets the uuid and index of a book from its path
function CalibreMetadata:getBookUuid(lpath)
    for index, book in ipairs(self.books) do
        if book.lpath == lpath then
            return book.uuid, index
        end
    end
    return "none"
end

-- gets the book id at the given index
function CalibreMetadata:getBookId(index)
    local book = {}
    book.priKey = index
    for _, key in ipairs({"uuid", "lpath", "last_modified"}) do
        book[key] = self.books[index][key]
    end

    local read_field = G_reader_settings:readSetting("calibreextra_read_field")
    if read_field then
        local full_path = self.path .. "/" .. book.lpath
        book["_is_read_"] = BookList.getBookStatus(full_path) == "complete"
    end

    return book
end

-- gets the book metadata at the given index
function CalibreMetadata:getBookMetadata(index)
    return self.books[index]
end

-- removes deleted books from table
function CalibreMetadata:prune()
    local count = 0
    for index, book in ipairs(self.books) do
        local path = self.path .. "/" .. book.lpath
        if not util.fileExists(path) then
            logger.dbg("prunning book from DB at index", index, "path", path)
            self:removeBook(book.lpath)
            count = count + 1
        end
    end
    if count > 0 then
        self:saveBookList()
    end
    return count
end

--- removes unused metadata from books
function CalibreMetadata:cleanUnused()
    for index, book in ipairs(self.books) do
        self.books[index] = slim_book(book)
    end
end

-- cleans all temp data stored for current library.
function CalibreMetadata:clean()
    self.books = rapidjson.array({})
    self.drive = rapidjson.array({})
    self.path = nil
    self.driveinfo = nil
    self.metadata = nil
end

-- get keys from driveinfo.calibre
function CalibreMetadata:getDeviceInfo(dir, kind)
    if not dir or not kind then return end
    local _, ok_drive, __, driveinfo = findCalibreFiles(dir)
    if not ok_drive then return end
    local drive = self:loadDeviceInfo(driveinfo)
    if drive then
        return drive[kind]
    end
end

-- initialize a directory as a calibre library.

-- This is the main function. Call it to initialize a calibre library
-- in a given path. It will find calibre files if they're on disk and
-- try to load info from them.

-- NOTE: Take special notice of the books table, because it could be huge.
-- If you're not working with the metadata directly (ie: in wireless connections)
-- you should copy relevant data to another table and free this one to keep things tidy.

function CalibreMetadata:init(dir)
    if not dir then return end
    local start_time = time.now()
    self.path = dir
    local ok_meta, ok_drive, file_meta, file_drive = findCalibreFiles(dir)
    self.driveinfo = file_drive
    if ok_drive then
        self.drive = self:loadDeviceInfo()
    end
    self.metadata = file_meta
    if ok_meta then
        self.books = self:loadBookList()
        self:cleanUnused()
    end

    local msg
    local deleted_count = self:prune()
    msg = string.format("in %.3f milliseconds: %d books. %d pruned",
        time.to_ms(time.since(start_time)), #self.books, deleted_count)
    logger.info(string.format("calibre info loaded from disk %s", msg))
    return true
end

return CalibreMetadata
