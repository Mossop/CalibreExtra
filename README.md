# CalibreExtra

An improved version of [KOReader](https://koreader.rocks/)'s [Calibre](https://calibre-ebook.com/) plugin. It is built to be a more capable wireless client to Calibre supporting status synchronisation and browsing through custom columns.

To install copy the `calibreextra.koplugin` to the plugins directory of your KOReader installation.

## New features

### Library browser

This plugin supports navigating through the Calibre library in a browser like interface. From the plugin's settings you can configure which fields are available, including custom user fields. Then you can navigate the fields displaying all books that match.

### Synchronising read status

You can use a custom Yes/No column in Calibre to track whether a book has been read or not and this plugin will synchronise it when connecting. Select the column you want from the plugin settings menu. It synchronises with KOReader's status for the book.

## Removed features

The following features are removed in comparison to the default Calibre plugin:

* The metadata search interface.
* Support for multiple Calibre libraries on device, only the inbox for the wireless client is supported.

## Coexistence with the default Calibre plugin

While it is possible to have both plugins enabled in KOReader it is recommended that you disable the default Calibre plugin while using this plugin. If you don't here are a few things to note. There may be other issues not listed here.

* If the two plugins use the same inbox directory for the wireless client then using the default plugin to synchronise from Calibre will remove additional metadata that this plugin relies on.
