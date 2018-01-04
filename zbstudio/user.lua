--[[-- This file shows examples of settings you can adjust.

Configuration files with preferences are loaded in the following order:
1. cfg/user.lua (system-wide configuration)
2. HOME/.zbstudio/user.lua (per-user configuration)
3. -cfg <lua code fragment|filename> (command line configuration)

See [configuration](http://studio.zerobrane.com/doc-configuration.html) page for information about location of configuration files.

--]]--

-- to modify loaded configuration for recognized extensions for lua files
-- (no longer needed in v1.21+) local G = ... -- this now points to the global environment
--
--~ local luaspec = ide.specs.lua
--~ luaspec.exts[#luaspec.exts+1] = "luaz"
--~ luaspec.keywords[1] = luaspec.keywords[1] .. ' foo'

-- to change font size to 12
--~ editor.fontsize = 12 -- this is mapped to ide.config.editor.fontsize
--~ editor.fontname = "Courier New"
--~ filehistorylength = 20 -- this is mapped to ide.config.filehistorylength

-- to specify full path to love2d *executable*; this is only needed
-- if the game folder and the executable are NOT in the same folder.
--~ path.love2d = 'd:/lua/love/love'

-- to specify full path to moai *executable* if it's not in one of PATH folders
--~ path.moai = 'd:/lua/moai/moai'

-- Moai config.lua file is searched in the following places: (1) MOAI_CONFIG,
-- (2) project directory (if set) or folder with the current file,
-- (3) folder with the moai executable.

-- to specify full path to gideros *executable* if it's not in one of PATH folders
--~ path.gideros = 'd:/Program Files/Gideros/GiderosPlayer.exe'

-- to specify full path to corona *executable* if it's not in one of PATH folders
--~ path.corona = 'd:/path/to/Corona SDK/Corona Simulator.exe'

-- to specify full path to lua interpreter if you need to use your own version
--~ path.lua = 'd:/lua/lua'

-- to specify full path to GSL-shell *executable* if it's not in one of PATH folders
--~ path.gslshell = [[D:\Lua\gsl-shell\gsl-shell.exe]]

-- to provide output filter for those engines that support redirecting
-- of "print" output to the IDE (like Corona SDK or Gideros)
--~ debugger.outputfilter = function(m) return #m < 124 and m or m:sub(1,120).."...\n" end

-- to fix an issue with 0d0d0a line endings in MOAI examples,
-- which may negatively affect breakpoints during debugging
--~ editor.iofilter = "0d0d0aFix"

-- to have 4 spaces when TAB is used in the editor
--~ editor.tabwidth = 4

-- to have TABs stored in the file (to allow mixing tabs and spaces)
--~ editor.usetabs  = true

-- to disable wrapping of long lines in the editor
editor.usewrap = false

-- to turn dynamic words on and to start suggestions after 4 characters
acandtip.nodynwords = false
acandtip.startat = 4

-- to automatically open files requested during debugging
editor.autoactivate = true

-- to specify a list of MOAI entrypoints
--~ moai = { entrypoints = { "main.lua", "source/main.lua" } }

-- to specify language to use in the IDE (requires a file in cfg/i18n folder)
--~ language = "ru"

-- to change the default color scheme; check tomorrow.lua for the list
-- of supported schemes or use cfg/scheme-picker.lua to pick a scheme.
-- (no longer needed in v1.21+) local G = ... -- this now points to the global environment
styles = loadfile('cfg/tomorrow.lua')('Tomorrow')

-- to change background color (or other colors in the IDE);
-- see cfg/tomorrow.lua for example/details on what other colors to change
-- styles.text = {bg = {240,240,220}}

-- also apply the same scheme to Output and Console windows
stylesoutshell = styles

-- to change markers used in console and output windows
styles.marker          = styles.marker or {}
styles.marker.message  = {ch = wxstc.wxSTC_MARK_ARROWS,                 fg = {0, 0, 0}, bg = {240, 240, 240}}
styles.marker.output   = {ch = wxstc.wxSTC_MARK_BACKGROUND,             fg = {0, 0, 0}, bg = {240, 240, 240}}
styles.marker.prompt   = {ch = wxstc.wxSTC_MARK_CHARACTER+('>'):byte(), fg = {0, 0, 0}, bg = {240, 240, 240}}
styles.operator        = styles.keywords0

editor.fontsize = 10

-- to disable indicators (underlining) on function calls
-- styles.indicator.fncall = nil

-- to change the color of the indicator used for function calls
styles.indicator.fncall.fg = {240,0,0}

-- to change the type of the indicator used for function calls
styles.indicator.fncall.st = wxstc.wxSTC_INDIC_PLAIN
  --[[ other possible values are:
  wxSTC_INDIC_DOTS   Dotted underline; wxSTC_INDIC_PLAIN       Single-line underline
  wxSTC_INDIC_TT     Line of Tshapes;  wxSTC_INDIC_SQUIGGLE    Squiggly underline
  wxSTC_INDIC_STRIKE Strike-out;       wxSTC_INDIC_SQUIGGLELOW Squiggly underline (2 pixels)
  wxSTC_INDIC_BOX    Box;              wxSTC_INDIC_ROUNDBOX    Rounded Box
  wxSTC_INDIC_DASH   Dashed underline; wxSTC_INDIC_STRAIGHTBOX Box with trasparency
  wxSTC_INDIC_DOTBOX Dotted rectangle; wxSTC_INDIC_DIAGONAL    Diagonal hatching
  wxSTC_INDIC_HIDDEN No visual effect;
  --]]

-- to enable additional spec files (like spec/glsl.lua)
-- (no longer needed in v1.51+) load.specs(function(file) return file:find('spec[/\\]glsl%.lua$') end)

-- to specify a default EOL encoding to be used for new files:
-- `wxstc.wxSTC_EOL_CRLF` or `wxstc.wxSTC_EOL_LF`;
-- `nil` means OS default: CRLF on Windows and LF on Linux/Unix and OSX.
-- (OSX had CRLF as a default until v0.36, which fixed it).
editor.defaulteol = wxstc.wxSTC_EOL_LF

-- to turn off checking for mixed end-of-line encodings in loaded files
--~ editor.checkeol = false

-- to force execution to continue immediately after starting debugging;
-- set to `false` to disable (the interpreter will stop on the first line or
-- when debugging starts); some interpreters may use `true` or `false`
-- by default, but can be still reconfigured with this setting.
debugger.runonstart = true

-- to set compact fold that doesn't include empty lines after a block
editor.foldcompact = false

-- set folding style with box, circle, arrow, and plus as accepted values.
editor.foldtype = 'circle'

-- set folding flags that control how folded lines are indicated in the text area (v0.51+);
-- set to 0 to disable all indicator lines. Other values (can be combined)
--  * wxstc.wxSTC_FOLDFLAG_LINEBEFORE_EXPANDED (draw line above if expanded),
--  * wxstc.wxSTC_FOLDFLAG_LINEBEFORE_CONTRACTED (draw line above if contracted),
--  * wxstc.wxSTC_FOLDFLAG_LINEAFTER_EXPANDED (draw line below if expanded),
--  * wxstc.wxSTC_FOLDFLAG_LINEAFTER_CONTRACTED (draw line below if contracted).
editor.foldflags = 0

-- to disable zoom with mouse wheel as it may be too sensitive on OSX
editor.nomousezoom = true

-- to specify a skin for Corona simulator (OSX only);
-- you can also change it between runs from Local Console by executing
-- `ide.config.corona = {skin = 'iPad'}`
--corona = { skin = "iPad" }

-- to style individual keywords; `return` and `break` are shown in red
-- (no longer needed in v1.21+) local G = ... -- this now points to the global environment
local luaspec = ide.specs.lua

local num = #luaspec.keywords
-- take a new slot in the list of keywords (starting from 1)
luaspec.keywords[num+1] = 'return break goto'
-- remove 'return' from the list of "regular" keywords
luaspec.keywords[1] = luaspec.keywords[1]
    :gsub(' return', '')
    :gsub(' break', '')
    :gsub(' goto', '')

-- assign new style to the added slot (starting from 0)
styles["keywords"..num] = {fg = {240, 0, 0}, b = true}

-- enable `Opt+Shift+Left/Right` shortcut on OSX
editor.keymap[#editor.keymap+1] = {wxstc.wxSTC_KEY_LEFT, wxstc.wxSTC_SCMOD_ALT+wxstc.wxSTC_SCMOD_SHIFT, wxstc.wxSTC_CMD_WORDLEFTEXTEND, "Macintosh"}
editor.keymap[#editor.keymap+1] = {wxstc.wxSTC_KEY_RIGHT, wxstc.wxSTC_SCMOD_ALT+wxstc.wxSTC_SCMOD_SHIFT, wxstc.wxSTC_CMD_WORDRIGHTENDEXTEND, "Macintosh"}

-- enable Emacs bindings to use `Ctrl-A` and `Ctrl-E` to go to the line start/end
editor.keymap[#editor.keymap+1] = {('A'):byte(), wxstc.wxSTC_SCMOD_CTRL, wxstc.wxSTC_CMD_HOME}
editor.keymap[#editor.keymap+1] = {('E'):byte(), wxstc.wxSTC_SCMOD_CTRL, wxstc.wxSTC_CMD_LINEEND}
keymap[ID.SELECTALL] = nil -- remove `Ctrl-A` shortcut from `SelectAll`

-- updated shortcuts to use them as of v1.20
keymap[ID.BREAK]            = "Shift-F9"
keymap[ID.BREAKPOINTTOGGLE] = "F9"
keymap[ID.BREAKPOINTNEXT]   = ""
keymap[ID.BREAKPOINTPREV]   = ""

keymap[ID.EXIT]             = ""
keymap[ID.STEP]             = "F11"
keymap[ID.STEPOVER]         = "F10"
keymap[ID.STEPOUT]          = "Ctrl-F10"
keymap[ID.RUNTO]            = "Shift-F10"
keymap[ID.COMMENT]          = ""
keymap[ID.CLEAROUTPUT]      = "Shift-F5"
keymap[ID.STOPDEBUG]        = "Ctrl-F5"
keymap[ID.AUTOCOMPLETE]     = "Ctrl-SPACE"
keymap[ID.REPLACE]          = "Ctrl-H"
keymap[ID.REPLACEINFILES]   = "Ctrl-Shift-H"

-- display whitespaces; set to true or wxstc.wxSTC_WS_VISIBLEALWAYS to display white space characters drawn as dots and arrows;
-- set to wxstc.wxSTC_WS_VISIBLEAFTERINDENT to show white spaces after the first visible character only
-- set to wxstc.wxSTC_WS_VISIBLEONLYININDENT to show white spaces used for indentation only (v1.61+).
editor.whitespace = true

-- set the size of dots indicating whitespaces when shown (v1.61+).
editor.whitespacesize = 2

-- set editor edge to mark lines that exceed a given length (v1.61+);
-- set to true to enable (at 80 columns) or to a number to set to specific column.
editor.edge = 100

-- set how the edge for the long lines is displayed (v1.61+);
-- set to wxstc.wxSTC_EDGE_NONE to disable it
-- set to wxstc.wxSTC_EDGE_LINE to display as a line
-- set to wxstc.wxSTC_EDGE_BACKGROUND to display as a different background color of characters after the column limit.
-- The color of the characters or the edge line is controlled by style.edge.fg configuration setting.
editor.edgemode = wxstc.wxSTC_EDGE_LINE

-- extra spacing (in pixels) above the baseline (v0.51+).
editor.extraascent = nil

-- extra spacing (in pixels) below the baseline (v0.61+).
editor.extradescent = nil

editor.tabwidth = 4

editor.specmap.t = "perl"
editor.specmap.rng = "xml"

-- enable handling of ANSI escapes in the Output window
output.showansi = true

-- wrap long lines (v0.51+); set to nil or false to disable.
output.usewrap = false

--------------------------------------------------------------------------------

debugger.dir_map = {
    {"^/usr/share/userverlua/", ""};
}

findtext = {reserved = {}, markers = {}, highlight = {}}

-- Write to output position of found text
findtext.output     = true

-- Use case sensetive search
findtext.matchcase  = true

-- search only words with same style
-- (valid only for not selected text)
findtext.matchstyle = true

-- Add bookmarks for line where word was find
-- findtext.bookmarks  = 3
findtext.bookmarks  = false

-- write some tips to output
findtext.tutorial  = false

-- style for highlighting current/selected word
-- set to false to disable it
findtext.highlight.style = '#000000,box,@10'

-- 0 - do not highlight
-- 1 - highlight only selected text
-- 2 - highlight current word or selected text
findtext.highlight.mode = 2

-- Use case sensetive search
findtext.highlight.matchcase  = true

-- highlight only words with same style
-- (valid only for not selected text)
findtext.highlight.matchstyle = true

-- do not highligh some words
-- findtext.reserved.lua = {  }
findtext.reserved.lua = {
  'return break goto true false',
  style = {'keywords0'},
}

findtext.reserved.xml = {}

smartbraces = {}

-- Add close brace when enters open one
smartbraces.autoclose = true

-- Braces pairs
smartbraces.open ="({['\"`"
smartbraces.close=")}]'\"`"

-- handle `{}` braces in special way for this lexers
smartbraces.multiline="cpp,css,hypertext"

-- Allows scroll down after last line
endatlast = false
