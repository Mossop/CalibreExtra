# CalibreExtra

An improved version of [KOReader](https://koreader.rocks/)'s [Calibre](https://calibre-ebook.com/) plugin

To install copy the `calibreextra.koplugin` to the plugins directory of your KOReader installation.

## New features

### Library browser

This plugin supports navigating through the Calibre library in a browser like interface. From the plugin's settings you can configure which fields are available, including custom user fields. Then you can navigate the fields displaying all books that match.

## Removed features

The following features are removed in comparison to the default Calibre plugin:

* The metadata search interface.
* Support for multiple Calibre libraries on device, only the inbox for the wireless client is supported.

## Coexistence with the default Calibre plugin

While it is possible to have both plugins enabled in KOReader it is recommended that you disable the default Calibre plugin while using this plugin. If you don't here are a few things to note. There may be other issues not listed here.

* Many of the settings are shared, changing a setting for one plugin changes it for both. This means the directory the wireless client syncs to is shared.
* Using the default plugin to synchronise from Calibre will remove additional metadata that this plugin relies on.
