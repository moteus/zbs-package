
do -- style

local theme = 'SL'

local function h2d(n) return 0+('0x'..n) end

local function H(c, bg) c = c:gsub('#','')
  -- since alpha is not implemented, convert RGBA to RGB
  -- assuming 0 is transparent and 255 is opaque
  -- based on http://stackoverflow.com/a/2645218/1442917
  bg = bg and H(bg) or {255, 255, 255}
  local a = #c > 6 and h2d(c:sub(7,8))/255 or 1
  local r, g, b = h2d(c:sub(1,2)), h2d(c:sub(3,4)), h2d(c:sub(5,6))
  return {
    math.min(255, math.floor((1-a)*bg[1]+a*r)),
    math.min(255, math.floor((1-a)*bg[2]+a*g)),
    math.min(255, math.floor((1-a)*bg[3]+a*b))}
end

-- add more of the specified color (keeping all in 0-255 range)
local mixer = function(c, n, more)
  if not c or #c == 0 then return c end
  local c = {c[1], c[2], c[3]} -- create a copy, so it can be modified
  c[n] = c[n] + more
  local excess = c[n] - 255
  if excess > 0 then
    for clr = 1, 3 do
      c[clr] = n == clr and 255 or c[clr] > excess and c[clr] - excess or 0
    end
  end
  return c
end

-- to change the default color scheme; check tomorrow.lua for the list
-- of supported schemes or use cfg/scheme-picker.lua to pick a scheme.
styles = loadfile('cfg/tomorrow.lua')(theme)

editor.fontsize = 10

-- also apply the same scheme to Output and Console windows
stylesoutshell = styles

styles.auxwindow = styles.text

-- to change markers used in console and output windows
-- styles.marker          = styles.marker or {}
-- styles.marker.message  = {ch = wxstc.wxSTC_MARK_ARROWS,                 fg = {0, 0, 0}, bg = {240, 240, 240}}
-- styles.marker.output   = {ch = wxstc.wxSTC_MARK_BACKGROUND,             fg = {0, 0, 0}, bg = {240, 240, 240}}
-- styles.marker.prompt   = {ch = wxstc.wxSTC_MARK_CHARACTER+('>'):byte(), fg = {0, 0, 0}, bg = {240, 240, 240}}
-- styles.operator        = styles.keywords0
-- styles.whitespace      = styles.keywords0
-- styles.whitespace = {fg = C.Comment},

-- to disable indicators (underlining) on function calls
-- styles.indicator.fncall = nil

-- to change the color of the indicator used for function calls
-- styles.indicator.fncall.fg = {240,0,0}

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

if theme == 'SL' then

    local luaspec = ide.specs.lua

    local function subs_kw(kw, num)
        num = num or (#luaspec.keywords + 1)
        luaspec.keywords[num] = 
            (luaspec.keywords[num] or '') ..
            ' ' .. table.concat(kw, ' ')

        local i, p = kw[0], {' &1 ', ' &1$', '^&1$', '^&1 '}
        if i then
            for _, w in ipairs(kw) do
                for _, pat in ipairs(p) do
                    pat = string.gsub(pat, '&1', w)
                    luaspec.keywords[i] = string.gsub(luaspec.keywords[i], pat, ' ')
                end
            end
            luaspec.keywords[i] = string.gsub(luaspec.keywords[i], '%s+', ' ')
        end

        return string.format("keywords%d", num - 1)
    end

    -- to style individual keywords; `return` and `break` are shown in red
    lua_reserved_additional = subs_kw{[0] = 1, 'return', 'break', 'goto'}
    styles[lua_reserved_additional] = {fg = H'F77C6A', b = true}
    subs_kw({[0] = 1, 'or', 'and', 'not'}, 3)

    styles.indicator.varlocal.fg = styles.comment.fg
    styles.indicator.varglobal.fg = styles.comment.fg
    styles.whitespace = {fg = {0x66, 0x6E, 0x78}}

    -- styles.operator.fg = H'E4DC70'
    styles.operator.b = true
    styles.number.b = true

    styles['`'] = {fg = H'B2ACA6', i = true, b = true}
    styles.keywords1.fg = H'59A6EC' -- true false
    styles.keywords2.fg = H'9AAF23' -- print ipairs
    styles.keywords3.fg = H'2DC4C4' -- string.format

    -- for findtext plugin
    findtext_markers = {
        '#C9B93B,@100',
        '#11DDFF,@80',
        '#F4F8FF,@80',
        '#DFCD6F,@90',
        '#CCFF00,@50',
        '#4DC3E0,@90',
    }
end

end

do -- spaces
-- to disable wrapping of long lines in the editor
editor.usewrap = false

-- display whitespaces; set to true or wxstc.wxSTC_WS_VISIBLEALWAYS to display white space characters drawn as dots and arrows;
-- set to wxstc.wxSTC_WS_VISIBLEAFTERINDENT to show white spaces after the first visible character only
-- set to wxstc.wxSTC_WS_VISIBLEONLYININDENT to show white spaces used for indentation only (v1.61+).
editor.whitespace = true

-- set the size of dots indicating whitespaces when shown (v1.61+).
editor.whitespacesize = 2

-- to specify a default EOL encoding to be used for new files:
-- `wxstc.wxSTC_EOL_CRLF` or `wxstc.wxSTC_EOL_LF`;
-- `nil` means OS default: CRLF on Windows and LF on Linux/Unix and OSX.
-- (OSX had CRLF as a default until v0.36, which fixed it).
editor.defaulteol = wxstc.wxSTC_EOL_LF

-- to turn off checking for mixed end-of-line encodings in loaded files
--~ editor.checkeol = false

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
editor.extraascent = 1

-- extra spacing (in pixels) below the baseline (v0.61+).
editor.extradescent = nil

editor.usetabs  = false

editor.tabwidth = 4

end

do -- debug

-- to automatically open files requested during debugging
editor.autoactivate = true

-- to force execution to continue immediately after starting debugging;
-- set to `false` to disable (the interpreter will stop on the first line or
-- when debugging starts); some interpreters may use `true` or `false`
-- by default, but can be still reconfigured with this setting.
debugger.runonstart = true

debugger.dir_map = {
    {"^/usr/share/userverlua/", "../automattic-userver/"};
}

end

do -- misc

-- to specify language to use in the IDE (requires a file in cfg/i18n folder)
--~ language = "ru"

-- to turn dynamic words on and to start suggestions after 4 characters
acandtip.nodynwords = false
acandtip.startat = 4


-- to disable zoom with mouse wheel as it may be too sensitive on OSX
editor.nomousezoom = true

editor.specmap.t = "perl"
editor.specmap.rng = "xml"

-- enable handling of ANSI escapes in the Output window
output.showansi = true

-- wrap long lines (v0.51+); set to nil or false to disable.
output.usewrap = false

-- (v1.71+)
-- editor.modifiedprefix = '* '

-- (v1.71+)
editor.endatlastline = false

end

do -- folding

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

end

do -- keymap

-- enable `Opt+Shift+Left/Right` shortcut on OSX
editor.keymap[#editor.keymap+1] = {wxstc.wxSTC_KEY_LEFT, wxstc.wxSTC_SCMOD_ALT+wxstc.wxSTC_SCMOD_SHIFT, wxstc.wxSTC_CMD_WORDLEFTEXTEND, "Macintosh"}
editor.keymap[#editor.keymap+1] = {wxstc.wxSTC_KEY_RIGHT, wxstc.wxSTC_SCMOD_ALT+wxstc.wxSTC_SCMOD_SHIFT, wxstc.wxSTC_CMD_WORDRIGHTENDEXTEND, "Macintosh"}


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
keymap[ID.COMMENT]          = "Ctrl+Q"
keymap[ID.CLEAROUTPUT]      = "Shift-F5"
keymap[ID.STOPDEBUG]        = "Ctrl-F5"
keymap[ID.AUTOCOMPLETE]     = "Ctrl-SPACE"
keymap[ID.REPLACE]          = "Ctrl-H"
keymap[ID.REPLACEINFILES]   = "Ctrl-Shift-H"
keymap[ID.REPLACEINFILES]   = "Ctrl-Shift-H"
keymap[ID.VIEWTOOLBAR]      = "Ctrl-Shift-T"

end

do -- plugins

do -- findtext

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
-- findtext.highlight.style = '#000000,box:80,@10'
findtext.highlight.style = '#CC9900,box:180,@10,U'

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
  -- 'return break goto true false',
  'or and not true false pairs ipairs',
  style = {'keywords0', lua_reserved_additional},
}

findtext.reserved.xml = {}

findtext.markers = findtext_markers

end

do -- smartbraces

smartbraces = {}

-- Add close brace when enters open one
smartbraces.autoclose = true

-- Braces pairs
smartbraces.open ="({['\"`"
smartbraces.close=")}]'\"`"

-- handle `{}` braces in special way for this lexers
smartbraces.multiline="cpp,css,hypertext"

end

do -- pairedtags

pairedtags = {style={}}

pairedtags.style.blue = '#9DC0FB,@30'

pairedtags.style.red  = '#F8304D,@30'

end

do -- virtual_space

-- Allows move cursors beyound EOL ()
virtual_space = {}

virtual_space.selection = true

virtual_space.editor    = false

virtual_space.nowrap    = false

end

-- Allows scroll down after last line
-- endatlast = false

end

do -- colorize

(...).colorize = function (lexer_name)
  lexer_name = lexer_name or 'lua'
  ide:GetEditor():SetupKeywords(lexer_name)
end

end
