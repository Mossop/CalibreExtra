# CalibreExtra

An improved version of [KOReader](https://koreader.rocks/)'s [Calibre](https://calibre-ebook.com/) plugin

To install copy the `calibreextra.koplugin` to the plugins directory of your KOReader installation.

## Coexistence with the default Calibre plugin

While it is possible to have both plugins enabled in KOReader it is recommended that you disable the default Calibre plugin while using this plugin. If you don't here are a few things to note. There may be other issues not listed here.

* Many of the settings are shared, changing a setting for one plugin changes it for both. This means
  the directory the wireless client syncs to is shared.
* Using the default plugin to synchronise from Calibre will remove additional metadata that this
  plugin relies on.
