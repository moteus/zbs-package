local Package = {
  name = "Find/Highlight identical text",
  author = "mozers™, Алексей, codewarlock1101, VladVRO, Tymur Gubayev, Alexey Melnichuk",
  version = '8.1.0',
  description = [[Port FindText from ru-SciTE project
Подсветка
  * Авто подсветка текста, который совпадает с текущим словом или выделением
Поиск текста:
  * Если текст выделен - ищется выделенная подстрока
  * Если текст не выделен - ищется текущее слово
  * Поиск возможен как в окне редактирования, так и в окне консоли
  * Строки, содержащие результаты поиска, выводятся в консоль
  * Каждый новый поиск оставляет маркеры своего цвета
  * Очистка от маркеров поиска - Ctrl+Alt+C
  ]],
  dependencies = "1.70",
}

-- default settings
local FINDTEXT = {
    output     = true,
    matchcase  = true,
    matchstyle = false,
    bookmarks  = false,
    tutorial   = false,

    markers = {
        '#CC00FF,@50',
        '#0000FF,@50',
        '#00FF00,@50',
        '#FFFF00,@100',
        '#11DDFF,@80',
    },

    highlight = {
        style      = '#646464,roundbox,@50',
        mode       = 2,
        matchcase  = true,
        matchstyle = false,
    },

    reserved = {
        ['*'] = {
            style = {'keywords0'}
        },
    },
}
-- end of configuration
--------------------------------------------------------------------

-- State
local editor, output

local ID_FIND_TEXT_MARK  = ID("FIND_TEXT_MARK")
local ID_FIND_TEXT_CLEAR = ID("FIND_TEXT_CLEAR")

local current_marker = 1

-- array of marker styles
local FIND_MARKERS

-- array of indecators
local INSTALLED_MARKERS

-- 0 - do not highlight
-- 1 - highlight only selected text
-- 2 - highlight selected and current
local HIGHLIGHT_MODE

-- syle for highlight
local HIGHLIGHT_STYLE

-- indicator for highlight
local HIGHLIGHT_MARKER

-- highlight word only with same style
local HIGHLIGHT_MATCHSTYLE

local HIGHLIGHT_MATCHCASE

local RESERVED

local RESERVED_WORDS_CACHE

local flag1
local bookmark
local isOutput
local isTutorial
local matchstyle

-- End state
--------------------------------------------------------------------

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
    return LEXER_NAMES[lexer] or 'UNKNOWN'
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
    local line = editor:LineFromPosition(pos)
    local eol_line = editor:GetLineEndPosition(line)
    if eol_line == pos then
        local next_pos = editor:PositionFromLine(line+1)
        return editor:GetTextRange(pos, next_pos)
    end

    local col = editor:GetColumn(pos)
    for col = col+1, editor:GetColumn(eol_line) do
        local next_pos = editor:FindColumn(line, col)
        if next_pos ~= pos then
            return editor:GetTextRange(pos, next_pos)
        end
    end

    return ''
end

function Editor.GetStyleAt(editor, pos)
    --! @check Found this in ZBS source code
    return bit.band(31, editor:GetStyleAt(pos))
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

local function in_array(a, v)
    if a then
        for _, e in ipairs(a) do
            if e == v then return true end
        end
    end
end

local function IsReservedWord(editor, pos, text)
    local lang = Editor.GetLanguage(editor)
    local reserved = RESERVED[lang] or RESERVED['*']

    if not reserved then return false end

    -- detect by styles and style names
    if type(reserved.style) == 'table' then
        local style = Editor.GetStyleAt(editor, pos)
        local convert = editor.spec and editor.spec.lexerstyleconvert
        for _, reserved_style in ipairs(reserved.style) do
            if type(reserved_style) == 'number' then
                if style == reserved_style then return true end
            elseif convert then
                if in_array(convert[reserved_style], style) then
                    return true
                end
            end
        end
    end

    local cache = RESERVED_WORDS_CACHE[lang]
    if not cache then
        cache = {}
        if type(reserved) == 'string' then
            reserved = {reserved}
        end
        for _, words in ipairs(reserved) do
            for word in string.gmatch(words, "%w+") do
                cache[word] = true
            end
        end
        RESERVED_WORDS_CACHE[lang] = cache
    end

    return cache[text]
end

local function GetCurrentWord(editor, curpos)
    local pos_start = editor:WordStartPosition(curpos, true)
    local pos_end   = editor:WordEndPosition(curpos, true)
    local word = editor:GetTextRange(pos_start, pos_end)
    if #word == 0 then
        -- try to select a non-word under caret
        pos_start = editor:WordStartPosition(curpos, false)
        pos_end   = editor:WordEndPosition(curpos, false)
        word = editor:GetTextRange(pos_start, pos_end)
    end
    return word, pos_start, pos_end
end

local function GetWord(editor, pos)
    local word, sel_start, sel_end = Editor.GetSelText(editor)
    if sel_start ~= sel_end then
        return word, true, sel_start, sel_end
    end
    word, sel_start, sel_end = GetCurrentWord(editor, pos or editor:GetCurrentPos())
    return word, false, sel_start, sel_end
end

local function EditorClearMarks(editor, indicator, start, length)
    indicator = indicator or INSTALLED_MARKERS
    return Editor.ClearMarks(editor, indicator, start, length)
end

local function EditorMarkText(editor, start, length, indicator)
    return Editor.MarkText(editor, start, length, indicator)
end

local function DoFindText(editor_, pos, marker)
    editor = editor_

    local current_mark_number   = INSTALLED_MARKERS[current_marker]
    local current_mark_settings = FIND_MARKERS[current_marker]

    current_marker = current_marker + 1
    if current_marker > #INSTALLED_MARKERS then current_marker = 1 end

    if current_mark_number then
        Editor.ConfigureIndicator(editor, current_mark_number, current_mark_settings)
    end

    --! @fixme there no file path for new documents (which not saved on disk)
    local doc = Editor.GetDocument(editor)
    local filePath = doc and (doc:GetFilePath() or doc:GetFileName()) or ''
    local sText, selected, word_pos  = GetWord(editor, pos)
    local flags = selected and 0 or wx.wxFR_WHOLEWORD
    if matchcase then flags = flags + wx.wxFR_MATCHCASE end
    local word_style
    if matchstyle and not selected then
        word_style = Editor.GetStyleAt(editor, word_pos)
    end

    if sText ~= '' then
        if bookmark then editor:MarkerDeleteAll(bookmark) end

        if isOutput then
            local msg
            if selected then
                msg = '> '..L'Search for selected text'..': "'
            else
                msg = '> '..L'Search for current word'..': "'
            end

            --- seems this settings allows highlingth word in Output console in SciTE
            -- props['lexer.errorlist.findtitle.begin'] = msg
            -- output:SetProperty('lexer.errorlist.findtitle.begin', msg)
            -- props['lexer.errorlist.findtitle.end'] = '"'
            -- output:SetProperty('lexer.errorlist.findtitle.end', '"')

            print(msg .. sText .. '"')
        end

        local count, marked = 0
        for s, e in Editor.iFindText(editor, sText, flags, nil, nil, word_style) do
            count = count + 1

            local line = editor:LineFromPosition(s)
            EditorMarkText(editor, s, #sText, current_mark_number)
            if line ~= marked then
                if bookmark then editor:MarkerAdd(line, bookmark) end
                local str = editor:GetLine(line) or ''
                str = string.gsub(str, '%s+', ' ')
                if isOutput then
                    print(
                        filePath .. string.format(':%d:\t', line + 1) .. str
                    )
                end
                marked = line
            end
        end

        if count > 0 then
            if isOutput then
                print('> '..string.gsub(L('Found: @ results'), '@', count))
                if isTutorial then
                    print('F3 (Shift+F3) - '..L'Jump by markers' )
                    print('F4 (Shift+F4) - '..L'Jump by lines'   )
                    print('Ctrl+Alt+C - '..L'Erase all markers'  )
                end
            end
        else
            print('> '..string.gsub(L"Can't find [@]!", '@', sText))
        end

        local pos
        if selected then
            pos = editor:GetSelectionStart()
        else
            pos = editor:GetCurrentPos()
            pos = editor:WordStartPosition(pos, false)
        end

        editor:GotoPos(pos)
        output:SetFocus()
    end
end

local function HasMoreThanOne(editor, value, length, flag, style)
    local num = 0
    for _ in Editor.iFindText(editor, value, flag, 0, length, style) do
        num = num + 1
        if num == 2 then
            return true
        end
    end
end

local function ClearFindMarks()
    editor = ide:GetEditor()
    if not editor then return end
    EditorClearMarks(editor)
    if bookmark then editor:MarkerDeleteAll(bookmark) end
    current_marker = 1
end

local CLEAR_HOT_KEY = HotKeyToggle:new'Ctrl-Alt-C'

Package.onRegister = function(package)
    local config = package:GetConfig()
    local findtext = (type(config) == 'table') and config or FINDTEXT

    output = ide:GetOutput()

    FIND_MARKERS = findtext.markers or FINDTEXT.markers
    if #FIND_MARKERS == 0 then FIND_MARKERS = FINDTEXT.markers end

    --! @check Can we configure indicators here

    local highlight = findtext.highlight or FINDTEXT.highlight

    HIGHLIGHT_MATCHCASE   = not not highlight.matchcase
    HIGHLIGHT_MATCHSTYLE  = not not highlight.matchstyle
    HIGHLIGHT_MODE        = highlight.mode or FINDTEXT.highlight.mode
    HIGHLIGHT_STYLE       = highlight.style or FINDTEXT.highlight.style
    HIGHLIGHT_MARKER      = ide:AddIndicator('find.text.highlight.marker')

    INSTALLED_MARKERS = {}
    for i in ipairs(FIND_MARKERS) do
        local name = string.format('find.text.mark.%d', i)
        local id = ide:AddIndicator(name)
        table.insert(INSTALLED_MARKERS, id)
    end

    RESERVED_WORDS_CACHE = {}

    -- merge values from default and from config
    RESERVED = {} do
        if FINDTEXT.reserved then
            for lang, reserved in pairs(FINDTEXT.reserved) do
                RESERVED[lang] = reserved
            end
        end

        if config.reserved then
            for lang, reserved in pairs(config.reserved) do
                RESERVED[lang] = reserved
            end
        end
    end

    matchstyle = not not findtext.matchstyle
    matchcase  = not not findtext.matchcase
    bookmark   = findtext.bookmarks
    isOutput   = findtext.output
    isTutorial = findtext.tutorial
    if bookmark == true then bookmark = FINDTEXT.bookmarks end

    CLEAR_HOT_KEY:set(ClearFindMarks)
end

Package.onUnRegister = function()
    CLEAR_HOT_KEY:unset()

    ide:RemoveIndicator(HIGHLIGHT_MARKER)
    for _, indicator in ipairs(INSTALLED_MARKERS) do
        ide:RemoveIndicator(indicator)
    end
    INSTALLED_MARKERS, HIGHLIGHT_MARKER, FIND_MARKERS,
        HIGHLIGHT_STYLE, RESERVED, RESERVED_WORDS_CACHE = nil
end

Package.onEditorUpdateUI = function(self, editor, event)
    if bit.band(event:GetUpdated(), wxstc.wxSTC_UPDATE_SELECTION) > 0 then
        updateneeded = editor
    end
end

Package.onIdle = function(self)
    if HIGHLIGHT_MODE < 2 then return end

    if not updateneeded then return end
    local editor = updateneeded
    updateneeded = false

    local length, curpos = editor:GetLength(), editor:GetCurrentPos()

    local value, is_selected, select_start, select_end = GetWord(editor, curpos)
    local flags = is_selected and 0 or wx.wxFR_WHOLEWORD
    if HIGHLIGHT_MATCHCASE then flags = flags + wx.wxFR_MATCHCASE end

    -- highlight only selected text
    if is_selected and (HIGHLIGHT_MODE == 1) then return end

    local is_selected_rectangle = is_selected and editor:SelectionIsRectangle()
        and editor:LineFromPosition(select_start) ~= editor:LineFromPosition(select_end)

    local word_style
    if HIGHLIGHT_MATCHSTYLE and not is_selected then
        word_style = Editor.GetStyleAt(editor, select_start)
    end

    local clear = string.find(value,'^%s+$')
        or is_selected_rectangle
        or not HasMoreThanOne(editor, value, length, flags, word_style)
        or ((not is_selected) and IsReservedWord(editor, select_start, value))

    EditorClearMarks(editor, HIGHLIGHT_MARKER, 0, length)
    if clear then
        ide:SetStatusFor('', 0)
        return
    end

    Editor.ConfigureIndicator(editor, HIGHLIGHT_MARKER, HIGHLIGHT_STYLE)

    editor:SetIndicatorCurrent(HIGHLIGHT_MARKER)
    local count = 0
    for s, e in Editor.iFindText(editor, value, flags, 0, length, word_style) do
        editor:IndicatorFillRange(s, e-s)
        count = count + 1
    end

    if is_selected then
        ide:SetStatusFor(("Found %d instance(s)."):format(count), 5)
    end
end

Package.onMenuEditor = function(self, menu, editor, event)
    local point = editor:ScreenToClient(event:GetPosition())
    local pos = editor:PositionFromPointClose(point.x, point.y)
    menu:Append(ID_FIND_TEXT_MARK, "Search Selected Word")
    menu:Enable(ID_FIND_TEXT_MARK, true)

    editor:Connect(ID_FIND_TEXT_MARK, wx.wxEVT_COMMAND_MENU_SELECTED,
        function() DoFindText(editor, pos) end)
end

return Package
