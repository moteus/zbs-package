local Package = {
    name = "Comment selected block",
    description = [[Port xComment from ru-SciTE project
Вид комментария зависит от выделения текста:
  * Если выделен поток текста, то скрипт ставит|снимает потоковый комментарий.
  * Если выделена целая строка(включая символ перевода строки) или несколько строк, то то скрипт ставит|снимает блочный комментарий.
  * Если выделение отсутствует, то ставится|снимается блочный комментарий на текущую строку.
  * Если параметры comment.stream.* отсутсвуют, то независимо от способа выделения ставится|снимается блочный комментарий.

Снятие/установка комментария зависит от первого символа выделения:
  * Если первый символ в выделении закомментированн, то комментарий снимается со всего выделения.
  * Если - нет, то на все выделение ставится комментарий.
]],
    author = "mozers™, VladVRO, Alexey Melnichuk",
    version = "1.4.5",
    dependencies = "1.70",
}

-- settings for specific lexers
local comment_settings = {
    lua = {
       block               = '--',
       block_spaces        = 1, -- number of spaces after line comment squence
       block_at_line_start = false,

       stream_start        = '--[[',
       stream_end          = ']]',
    },

    xml = {
       stream_start        = '<!--',
       stream_end          = '-->',
    },

    perl = {
       block               = '#',
       block_spaces        = 1, -- number of spaces after line comment squence
       block_at_line_start = false,
    },

    python = {
       block               = '#',
       block_spaces        = 1, -- number of spaces after line comment squence
       block_at_line_start = false,
    },
}

-- State
local iDEBUG = false
local comment_stream_start
local comment_stream_end
local comment_block
local comment_block_use_space
local comment_block_at_line_start
-- End State

local function print(...)
  ide:Print(...)
end

local function printf(...)
  print(string.format(...))
end

local function L(text)
    return text
end

--------------------------------------------------------------------
local Editor = {} do

local function append(t, v)
    t[#t+1] = v
    return t
end

local function split_first(str, sep, plain)
  local e, e2 = string.find(str, sep, nil, plain)
  if e then
    return string.sub(str, 1, e - 1), string.sub(str, e2 + 1)
  end
  return str
end

local SC_EOL_CRLF = 0
local SC_EOL_CR   = 1
local SC_EOL_LF   = 2

local LEXER_NAMES = {}
for k, v in pairs(wxstc) do
    if string.find(tostring(k), 'wxSTC_LEX') then
        local name = string.lower(string.sub(k, 11))
        LEXER_NAMES[ v ] = name
    end
end

function Editor.GetLanguage(editor)
    local lexer = editor.spec and editor.spec.lexer or editor:GetLexer()
    local name = LEXER_NAMES[lexer]
    if name then return name end
    if type(lexer) == 'string' then
        name = string.match(lexer, '^lexlpeg%.(.+)$')
    end
    return name or 'UNKNOWN'
end

function Editor.AppendNewLine(editor)
    local line = editor:GetLineCount()
    editor:InsertText(
        editor:PositionFromLine(line),
        Editor.GetEOL(editor)
    )
    return editor:PositionFromLine(line)
end

function Editor.GetEOL(editor)
  local eol = "\r\n"
  if editor.EOLMode == SC_EOL_CR then
    eol = "\r"
  elseif editor.EOLMode == SC_EOL_LF then
    eol = "\n"
  end
  return eol
end

function Editor.GetSelText(editor)
  local selection_pos_start, selection_pos_end = editor:GetSelection()
  local selection_line_start = editor:LineFromPosition(selection_pos_start)
  local selection_line_end   = editor:LineFromPosition(selection_pos_end)

  local selection = {
    pos_start    = selection_pos_start,
    pos_end      = selection_pos_end,
    first_line   = selection_line_start,
    last_line    = selection_line_end,
    is_rectangle = editor:SelectionIsRectangle(),
    is_multiple  = editor:GetSelections() > 1,
    text         = ''
  }

  if selection_pos_start ~= selection_pos_end then
    if selection.is_rectangle then
      local EOL = Editor.GetEOL(editor)
      local selected, not_empty = {}, false
      for line = selection_line_start, selection_line_end do
        local selection_line_pos_start = editor:GetLineSelStartPosition(line)
        local selection_line_pos_end   = editor:GetLineSelEndPosition(line)
        not_empty = not_empty or selection_line_pos_start ~= selection_line_pos_end
        append(selected, editor:GetTextRange(selection_line_pos_start, selection_line_pos_end))
      end
      selection.text = not_empty and (table.concat(selected, EOL) .. EOL) or ''
    else
      selection.text = editor:GetTextRange(selection_pos_start, selection_pos_end)
    end
  end

  return selection.text, selection.pos_start, selection.pos_end
end

function Editor.GetSymbolAt(editor, pos)
    return editor:GetTextRange(pos, editor:PositionAfter(pos))
end

function Editor.GetStyleAt(editor, pos)
    local mask = bit.lshift(1, editor:GetStyleBitsNeeded()) - 1
    return bit.band(mask, editor:GetStyleAt(pos))
end

function Editor.FindText(editor, text, flags, start, finish)
    editor:SetSearchFlags(flags)
    editor:SetTargetStart(start or 0)
    editor:SetTargetEnd(finish or editor:GetLength())
    local posFind = editor:SearchInTarget(text)
    if posFind ~= wx.wxNOT_FOUND then
        start, finish = editor:GetTargetStart(), editor:GetTargetEnd()
        if start >= 0 and finish >= 0 then
            return start, finish
        end
    end
    return wx.wxNOT_FOUND, 0
end

local function isFindDone(forward, pos, finish)
    if forward then
        return pos > finish
    end
    return pos < finish
end

function Editor.iFindText(editor, text, flags, pos, finish, style)
    finish = finish or editor:GetLength()
    pos = pos or 0
    local forward = pos < finish
    return function()
        while not isFindDone(forward, pos, finish) do
            local start_pos, end_pos = Editor.FindText(editor, text, flags, pos, finish)
            if start_pos == wx.wxNOT_FOUND then
                return nil
            end
            if forward then
                pos = end_pos + 1
            else
                pos = start_pos -1
            end
            if (not style) or (style == Editor.GetStyleAt(editor, start_pos)) then
                return start_pos, end_pos
            end
        end
    end
end

function Editor.HasFocus(editor)
    return editor == ide:GetEditorWithFocus() and editor
end

function Editor.GetDocument(editor)
    return ide:GetDocument(editor)
end

function Editor.GetCurrentFilePath(editor)
    local doc = Editor.GetDocument(editor)
    return doc and doc:GetFilePath()
end

function Editor.ClearMarks(editor, indicator, start, length)
    local current_indicator = editor:GetIndicatorCurrent()
    start  = start or 0
    length = length or editor:GetLength()

    if type(indicator) == 'table' then
        for _, indicator in ipairs(indicator) do
            editor:SetIndicatorCurrent(indicator)
            editor:IndicatorClearRange(start, length)
        end
    else
        editor:SetIndicatorCurrent(indicator)
        editor:IndicatorClearRange(start, length)
    end

    editor:SetIndicatorCurrent(current_indicator)
end

function Editor.MarkText(editor, start, length, indicator)
    local current_indicator = editor:GetIndicatorCurrent()
    editor:SetIndicatorCurrent(indicator)
    editor:IndicatorFillRange(start, length)
    editor:SetIndicatorCurrent(current_indicator)
end

local STYLE_CACHE, STYLE_NAMES = {}, {
    dotbox       = wxstc.wxSTC_INDIC_DOTBOX,
    roundbox     = wxstc.wxSTC_INDIC_ROUNDBOX,
    tt           = wxstc.wxSTC_INDIC_TT,
    roundbox     = wxstc.wxSTC_INDIC_ROUNDBOX,
    straightbox  = wxstc.wxSTC_INDIC_STRAIGHTBOX,
    diagonal     = wxstc.wxSTC_INDIC_DIAGONAL,
    squiggle     = wxstc.wxSTC_INDIC_SQUIGGLE,
}

-- Convert sting like #<HEX_COLOR>,style[:alpha],@alpha,[U|u]
function Editor.DecodeStyleString(s)
    local color, style, alpha, under, oalpha
    if s then
        local cached = STYLE_CACHE[s]
        if cached then
            return cached[1], cached[2], cached[3],
                cached[4], cached[5]
        end
        for param in string.gmatch(s, '[^,]+') do
            if not color then
                if string.sub(param, 1, 1) == '#' then
                    local r, g, b, a = string.sub(param, 2, 3), string.sub(param, 4, 5),
                        string.sub(param, 6, 7), string.sub(param, 8, 9)
                    r = tonumber(r, 16) or 0
                    g = tonumber(g, 16) or 0
                    b = tonumber(b, 16) or 0
                    if a and #a > 0 then
                        alpha = tonumber(a, 16) or 0
                    end
                    color = wx.wxColour(r, g, b)
                else
                    param = (tonumber(param) or 0) % (1+0xFFFFFFFF)
                    local r = param % 256; param = math.floor(param / 256)
                    local b = param % 256; param = math.floor(param / 256)
                    local g = param % 256; param = math.floor(param / 256)
                    alpha = param
                    color = wx.wxColour(r, g, b)
                end
            elseif string.sub(param, 1, 1) == '@' then
                alpha = tonumber((string.sub(param, 2)))
            elseif string.sub(param, 1, 1) == 'u' or string.sub(param, 1, 1) == 'U' then
                under = (string.sub(param, 1, 1) == 'U')
            elseif #param > 0 then
                local name, alpha = split_first(param, ':', true)
                style = tonumber(name) or STYLE_NAMES[name]
                    or wxstc['wxSTC_INDIC_' .. name]
                oalpha = tonumber(alpha)
            end
        end
    end

    color = color or wx.wxColour(0, 0, 0)
    alpha = alpha or 0
    style = style or STYLE_NAMES['roundbox']

    if s then
        STYLE_CACHE[s] = {color, style, alpha, under, oalpha}
    end

    return color, style, alpha, under, oalpha
end

function Editor.ConfigureIndicator(editor, indicator, params)
    local color, style, alpha, under, oalpha = Editor.DecodeStyleString(params)
    editor:IndicatorSetForeground(indicator, color)
    editor:IndicatorSetStyle     (indicator, style)
    editor:IndicatorSetAlpha     (indicator, alpha)
    if under ~= nil then
        editor:IndicatorSetUnder (indicator, not not under)
    end
    if oalpha then
        editor:IndicatorSetOutlineAlpha(indicator, oalpha)
    end
end

function Editor.SetSel(editor, nStart, nEnd)
    if nEnd < 0 then nEnd = editor:GetLength() end
    if nStart < 0 then nStart = nEnd end

    editor:GotoPos(nEnd)
    editor:SetAnchor(nStart)
end

end
--------------------------------------------------------------------

--------------------------------------------------------------------
local HotKeyToggle = {} do
HotKeyToggle.__index = HotKeyToggle

function HotKeyToggle:new(key)
    local o = setmetatable({key = key}, self)
    return o
end

function HotKeyToggle:set(handler)
    assert(self.id == nil)
    self.prev = ide:GetHotKey(self.key)
    self.id = ide:SetHotKey(handler, self.key)
    return self
end

function HotKeyToggle:unset()
    assert(self.id ~= nil)
    if self.id == ide:GetHotKey(self.key) then
        if self.prev then
            ide:SetHotKey(self.prev, self.key)
        else
            --! @todo properly remove handler
            ide:SetHotKey(function()end, self.key)
        end
    end
    self.prev, self.id = nil
end

end
--------------------------------------------------------------------

local function append(t, v)
    t[#t + 1] = v
    return t
end

-- Get from ru-SciTE. So there no gurantee about correctness for ZBS
local IS_COMMENT, COMMENTS = {}, {
    abap       = {1, 2},
    ada        = {10},
    asm        = {1, 11},
    au3        = {1, 2},
    baan       = {1, 2},
    bullant    = {1, 2, 3},
    caml       = {12, 13, 14, 15},
    cpp        = {1, 2, 3, 15, 17, 18},
    csound     = {1, 9},
    css        = {9},
    d          = {1, 2, 3, 4, 15, 16, 17},
    escript    = {1, 2, 3},
    euphoria   = {1, 18},
    flagship   = {1, 2, 3, 4, 5, 6},
    forth      = {1, 2, 3},
    gap        = {9},
    hypertext  = {9, 20, 29, 42, 43, 44, 57, 58, 59, 72, 82, 92, 107, 124, 125},
    xml        = {9, 29},
    inno       = {1, 7},
    latex      = {4},
    lua        = {1, 2, 3},
    script_lua = {4, 5},
    mmixal     = {1, 17},
    nsis       = {1, 18},
    opal       = {1, 2},
    pascal     = {2, 3, 4},
    perl       = {2},
    bash       = {2},
    pov        = {1, 2},
    ps         = {1, 2, 3},
    python     = {1, 12},
    rebol      = {1, 2},
    ruby       = {2},
    scriptol   = {2, 3, 4, 5},
    smalltalk  = {3},
    specman    = {2, 3},
    spice      = {8},
    sql        = {1, 2, 3, 13, 15, 17, 18},
    tcl        = {1, 2, 20, 21},
    verilog    = {1, 2, 3},
    vhdl       = {1, 2}
}
for lang, styles in pairs(COMMENTS) do
    local set = {}
    for _, style in ipairs(styles) do
        set[style] = true
    end
    IS_COMMENT[lang] = set
end

--------------------------------------------------------
-- Определение соответствует ли стиль символа стилю комментария
function IsComment(editor, pos)
    local style = Editor.GetStyleAt(editor, pos)

    local is_comment = editor.spec and editor.spec.iscomment
        or IS_COMMENT[Editor.GetLanguage(editor)]

    if is_comment then
        return is_comment[style]
    end

    -- For most other lexers comment has style 1
    -- asn1, ave, blitzbasic, cmake, conf, eiffel, eiffelkw, erlang, euphoria, fortran,
    -- f77, freebasic, kix, lisp, lout, octave, matlab, metapost, nncrontab, props, batch,
    -- makefile, diff, purebasic, vb, yaml
    return style == 1
end

local lua_patt_chars = "[%(%)%.%+%-%*%?%[%]%^%$%%]"
function StringToPattern( s )
  return (s:gsub(lua_patt_chars,'%%%0'))
end

---------------------------------------------
-- Возвращает позицию первого не пробельного символа в блоке
local function FirstLetterFromBlock(editor, selected_text, select_start, select_end)
    local text = selected_text
    if text == '' then -- no selected text so use current line as block
        local line = editor:LineFromPosition(select_start)
        text = editor:GetLine(line)
        select_start = editor:PositionFromLine(line)
    end

    local first_letter = string.find(text_line, "[^%s]", 1)
    if first_letter then
        first_letter = select_start + first_letter - 1
    else
        first_letter = -1
    end

    if iDEBUG then print("FirstLetterFromBlock = "..first_letter) end
    return first_letter
end

--------------------------------------------------
-- Определение что позиция является началом строки
local function IsLineBeginAt(editor, pos, line)
    line = line or editor:LineFromPosition(pos)
    return (pos == 0) or
        editor:LineFromPosition(pos - 1) < line
end

--------------------------------------------------
-- Определение что выделено - блок или поток
local function IsBlock(editor, block)
    local result = block.is_line or (
        IsLineBeginAt(editor, block.bstart, block.first_line)
        and IsLineBeginAt(editor, block.bend, block.last_line)
    )
    if iDEBUG then printf('xComment::IsBlock %s', tostring(result)) end
    return result
end

--------------------------------------------------
-- Комментирование одной невыделенной строки
local function LineComment(editor, block)
    if iDEBUG then
        printf ("Line Comment: start: %s", tostring(comment_block_at_line_start))
    end

    local comment_block = comment_block .. string.rep(" ", comment_block_use_space)
    local cur_pos, ins_pos = editor:GetCurrentPos()
    if comment_block_at_line_start then
        ins_pos = editor:PositionFromLine(block.first_line)
    else
        ins_pos = editor:GetLineIndentPosition(block.first_line)
    end

    editor:BeginUndoAction()
    editor:InsertText(ins_pos, comment_block)
    if cur_pos >= ins_pos then
        editor:GotoPos(cur_pos + #comment_block)
    end
    editor:EndUndoAction()
end

--------------------------------------------------
-- Снятие комментария с одной невыделенной строки
local function LineUnComment(editor, block)
    if iDEBUG then print ("Line UnComment") end

    local cur_pos = editor:GetCurrentPos()
    local text_line = editor:GetCurLine()
    local offset = string.find(text_line, '%S')
    local comment_pattern = "^(%s*)(" .. StringToPattern(comment_block).."~? ?)"
    local line_uncomment = string.gsub(text_line, comment_pattern, "%1", 1)

    if line_uncomment then
        local delta = #text_line - #line_uncomment
        local line_pos = editor:PositionFromLine(block.first_line)
        local start_comment_pos = line_pos + offset - 1
        local end_comment_pos = start_comment_pos + delta

        local next_line_pos = editor:PositionFromLine(
            block.first_line + 1
        )

        editor:BeginUndoAction()
        editor:SetSelection(block.bstart, next_line_pos)
        editor:ReplaceSelection(line_uncomment)
        if end_comment_pos <= cur_pos then
            cur_pos = cur_pos - delta
        end
        editor:GotoPos(cur_pos)
        editor:EndUndoAction()
    end
end

--------------------------------------------------
-- Комментирование нескольких выделенных строк
local function BlockComment(editor, block)
    if iDEBUG then print ("Block Comment") end

    local comment_block = comment_block .. string.rep(" ", comment_block_use_space)

    local cur_line = editor:LineFromPosition(editor:GetCurrentPos())

    local text_comment = {}
    for i = block.first_line, block.last_line - 1 do
        local text_line = editor:GetLine(i)
        if string.find(text_line, "[^%s]") then
            if comment_block_at_line_start then
                append(text_comment, comment_block .. text_line)
            else
                append(text_comment, string.gsub(text_line, "([^%s])", comment_block .. "%1", 1))
            end
        else
            append(text_comment, text_line)
        end
    end
    text_comment = table.concat(text_comment)

    local cursor_at_begin = (block.bstart == editor:GetCurrentPos())

    editor:BeginUndoAction()
    editor:SetSelection(block.bstart, block.bend)
    editor:ReplaceSelection(text_comment)

    local ancor, caret = block.bstart, editor:PositionFromLine(block.last_line)
    if cursor_at_begin then ancor, caret = caret, ancor end
    Editor.SetSel(editor, ancor, caret)

    editor:EndUndoAction()
end

--------------------------------------------------
-- Снятие комментария с нескольких выделенных строк
local function BlockUnComment(editor, block)
    if iDEBUG then print ("Block UnComment") end
    if comment_block == "" then
        print(L"! Missing parameter ".."comment.block."..lexer)
        return 
    end

    local comment_pattern = StringToPattern(comment_block) .. "~? ?"

    local text_uncomment = {}
    for i = block.first_line, block.last_line - 1 do
        local text_line = editor:GetLine(i)
        local line_uncomment = string.gsub(text_line, comment_pattern,"",1)
        append(text_uncomment, line_uncomment)
    end
    text_uncomment = table.concat(text_uncomment)

    local cursor_at_begin = (block.bstart == editor:GetCurrentPos())

    editor:BeginUndoAction()
    editor:SetSelection(block.bstart, block.bend)
    editor:ReplaceSelection(text_uncomment)

    local ancor, caret = block.bstart, editor:PositionFromLine(block.last_line)
    if cursor_at_begin then ancor, caret = caret, ancor end
    Editor.SetSel(editor, ancor, caret)

    editor:EndUndoAction()
end

--------------------------------------------------
-- Определение что выделено - потоковый комментарий или закомментированные строки
local function IsStreamComment(editor, block, PatternStream)
    local result = not not string.find(block.text, PatternStream)
    if iDEBUG then
        printf("xComment::IsStreamComment: %s", tostring(result))
    end

    return result
end

--------------------------------------------------
-- Комментирование выделенного потока текста
local function StreamComment(editor, block, comment_stream_start, comment_stream_end)
    if iDEBUG then print ("Stream Comment") end

    local text_comment = comment_stream_start..block.text..comment_stream_end
    local delta = #text_comment - #block.text
    local ancor, caret = block.bstart, block.bend + delta
    if block.bstart == editor:GetCurrentPos() then ancor, caret = caret, ancor end
    editor:BeginUndoAction()
    editor:ReplaceSelection(text_comment)
    Editor.SetSel(editor, ancor, caret)
    editor:EndUndoAction()
end

--------------------------------------------------
-- Снятие комментария с выделенного потока текста
local function StreamUnComment(editor, block, PatternStream)
    if iDEBUG then print ("Stream UnComment") end

    local text_uncomment = string.gsub(block.text, PatternStream, "%1", 1)
    local delta = #block.text - #text_uncomment
    local ancor, caret = block.bstart, block.bend - delta
    if block.bstart == editor:GetCurrentPos() then ancor, caret = caret, ancor end
    editor:BeginUndoAction()
    editor:ReplaceSelection(text_uncomment)
    Editor.SetSel(editor, ancor, caret)
    editor:EndUndoAction()
end

---------------------------------------------
-- Возвращает позицию первого не пробельного символа в блоке
local function GetBlock(editor, align)
    local text, block_start, block_end = Editor.GetSelText(editor)

    local block = {
        is_line    = text == '';
        bstart     = block_start;
        bend       = block_end;
        first_line = editor:LineFromPosition(block_start);
        last_line  = editor:LineFromPosition(block_end);
    }

    if block.is_line then
        block.bstart = editor:PositionFromLine(block.first_line)
        text = editor:GetLine(block.first_line)
    elseif align and not IsBlock(editor, block) then
        -- align selected text to block
        block.last_line = block.last_line + 1
        block.bend   = editor:PositionFromLine(block.last_line)
        block.bstart = editor:PositionFromLine(block.first_line)
    end

    local block_first_char = string.find(text, '[^%s]')
    if block_first_char then
        block.first_char = block.bstart + block_first_char - 1
    else
        block.first_char = -1
    end

    block.is_comment = IsComment(editor, block.first_char)
    block.text = text

    if iDEBUG then
        printf([[xComment::GetBlock:
    is_comment = %s;
    is_line    = %s;
    bstart     = %d;
    bend       = %d;
    start_line = %d;
    end_line   = %d;]],
        block.is_line and 'true' or 'false',
        block.is_comment and 'true' or 'false',
        block.bstart, block.bend,
        block.first_line, block.last_line
    )
    end

    return block
end

local function ConfigureState(editor)
    local lexer = editor.spec or {}
    local lang = Editor.GetLanguage(editor)
    local settings = comment_settings[lang] or {}

    comment_stream_start        = settings.stream_start or ''
    comment_stream_end          = settings.stream_end or ''

    comment_block               = lexer.linecomment or settings.block or ''
    comment_block_use_space     = settings.block_spaces or 1
    comment_block_at_line_start = settings.block_at_line_start

    -- default value have to be true
    if comment_block_at_line_start == nil then
        comment_block_at_line_start = true
    end
end

---------------------------------------------
-- Обработка нажатия на Ctrl+Q
local function xComment()
    local editor = Editor.HasFocus(ide:GetEditor())
    if not editor then return end

    ConfigureState(editor)

    local support_stream_comment = #comment_stream_start > 0 and #comment_stream_end > 0

    local block = GetBlock(editor, not support_stream_comment)

    -- comment/uncomment current line
    if block.is_line then
        if comment_block == '' then
            print(L"! Missing parameter ".."comment.block."..Editor.GetLanguage(editor))
            return
        end

        if block.is_comment then
            LineUnComment(editor, block)
        else
            LineComment(editor, block)
        end
        return true
    end

    -- comment/uncomment current code block (multiple lines)
    if IsBlock(editor, block) then
        if comment_block == '' then
            print(L"! Missing parameter ".."comment.block."..Editor.GetLanguage(editor))
            return
        end
        if block.is_comment then
            BlockUnComment(editor, block)
        else
            BlockComment(editor, block)
        end
        return true
    end

    assert(support_stream_comment)

    local PatternStream = '^'..StringToPattern(comment_stream_start)
        ..'(.-)'..StringToPattern(comment_stream_end)..'$'

    if IsStreamComment(editor, block, PatternStream) then
        if block.is_comment then
            StreamUnComment(editor, block, PatternStream)
        end
    elseif not block.is_comment then
        StreamComment(editor, block, comment_stream_start, comment_stream_end)
    end
end

local HOT_KEY

Package.onRegister = function(package)
    local _, key = ide:GetHotKey(ID_COMMENT or ID.COMMENT)
    if not key or #key == 0 then key = 'Ctrl+Q'end
    HOT_KEY = HotKeyToggle:new(key)
        :set(xComment)
end

Package.onUnRegister = function()
    HOT_KEY:unset()
    HOT_KEY = nil
end

local function key_is(k, t)
    for i = 1, #t do
        if k == t[i] then return true end
    end
end

Package.onEditorKeyDown = function(self, editor, event)
    local key = event:GetKeyCode()
    local mod = event:GetModifiers()

    if mod ~= wx.wxMOD_CONTROL then
        return true
    end

    if key_is(key, {string.byte('q'), string.byte('Q')}) then
        xComment()
        return false
    end

    return true
end

return Package
