local Package = {
  name = "Paired braces",
  author = "Alexey Melnichuk",
  version = '0.1',
  description = [[Port from SciTE text editor. Goto and select to text between paired braces]],
  dependencies = "1.70",
}

-----------------------------------------------------------------------------------

local function print(...)
  ide:Print(...)
end

local function printf(...)
  ide:Print(string.format(...))
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

local GOTO_MATCH_BRACE = HotKeyToggle:new('Ctrl-E')
local SELECT_MATCH_BRACE = HotKeyToggle:new('Ctrl-Shift-E')

local braces = '[](){}'
local function IsBrace(ch)
    return not not string.find(braces, ch, nil, true)
end

local function EnsureRangeVisible(editor, posStart, posEnd, enforcePolicy)
    local lineStart = editor:LineFromPosition(math.min(posStart, posEnd))
    local lineEnd   = editor:LineFromPosition(math.max(posStart, posEnd))
    for line = lineStart, lineEnd do
        if enforcePolicy then
            editor:EnsureVisibleEnforcePolicy(line)
        else
            editor:EnsureVisible(line)
        end
    end
end

local function FindMatchingBracePosition(editor, sloppy)
    local isInside = false;

    local mainSel = editor:GetMainSelection()
    if editor:GetSelectionNCaretVirtualSpace(mainSel) > 0 then
        return false;
    end

    local lconvert = editor and editor.spec and editor.spec.lexerstyleconvert
    local bracesStyle = lconvert and lconvert.operator and lconvert.operator[1] or 0

    local bracesStyleCheck = (not not editor) and (bracesStyle ~= 0) -- in original code it used for output
    local caretPos = editor:GetCurrentPos()
    local braceAtCaret = -1
    local braceOpposite = -1
    local charBefore
    local styleBefore

    local lengthDoc = editor:GetLength()
    if lengthDoc > 0 and caretPos > 0 then
        local posBefore = editor:PositionBefore(caretPos)
        if posBefore == caretPos - 1 then
            charBefore = Editor.GetSymbolAt(editor, posBefore)
            styleBefore = Editor.GetStyleAt(editor, posBefore)
        end
    end

    -- Priority goes to character before caret
    if charBefore and IsBrace(charBefore) and (
        not bracesStyleCheck or styleBefore == bracesStyle
    ) then
        braceAtCaret = caretPos - 1
    end

    local SCE_P_OPERATOR = 10 --! @fixme

    local colonMode = false
    if editor:GetLexer() == wxstc.wxSTC_LEX_PYTHON and
        charBefore == ':' and styleBefore == SCE_P_OPERATOR
    then
        braceAtCaret = caretPos - 1;
        colonMode = true
    end

    local isAfter = true
    if lengthDoc > 0 and sloppy and braceAtCaret < 0 and caretPos < lengthDoc then
        -- No brace found so check other side
        -- Check to ensure not matching brace that is part of a multibyte character
        local posAfter = editor:PositionAfter(caretPos)
        if posAfter == caretPos + 1 then
            local charAfter = Editor.GetSymbolAt(editor, caretPos)
            local styleAfter = Editor.GetStyleAt(editor, caretPos)
            if charAfter and IsBrace(charAfter) and (
                not bracesStyleCheck or styleAfter == bracesStyle
            ) then
                braceAtCaret = caretPos;
                isAfter = false;
            end

            if editor:GetLexer() == wxstc.wxSTC_LEX_PYTHON and
                ':' == charAfter and styleAfter == SCE_P_OPERATOR
            then
                braceAtCaret = caretPos
                colonMode = true
            end
        end
    end

    if braceAtCaret >= 0 then
        if colonMode then
            local lineStart     = editor:LineFromPosition(braceAtCaret)
            local lineMaxSubord = editor:GetLastChild(lineStart, -1)
            braceOpposite = editor:GetLineEndPosition(lineMaxSubord)
        else
            braceOpposite = editor:BraceMatch(braceAtCaret)
        end
        if braceOpposite > braceAtCaret then
            isInside = isAfter
        else
            isInside = not isAfter
        end
    end

    return isInside, braceAtCaret, braceOpposite
end

local function GoMatchingBrace(editor, select)
    local isInside, braceAtCaret, braceOpposite = FindMatchingBracePosition(editor, true)

    -- Convert the character positions into caret positions based on whether
    -- the caret position was inside or outside the braces.
    if isInside then
        if braceOpposite > braceAtCaret then
            braceAtCaret = editor:PositionAfter(braceAtCaret)
        elseif braceOpposite >= 0 then
            braceOpposite = editor:PositionAfter(braceOpposite)
        end
    else -- Outside
        if braceOpposite > braceAtCaret then
            braceOpposite = editor:PositionAfter(braceOpposite)
        else
            braceAtCaret = editor:PositionAfter(braceAtCaret)
        end
    end

    if braceOpposite >= 0 then
        EnsureRangeVisible(editor, braceOpposite, braceOpposite, true)
        if select then
            Editor.SetSel(editor, braceAtCaret, braceOpposite)
        else
            editor:GotoPos(braceOpposite)
            -- Editor.SetSel(editor, braceOpposite, braceOpposite)
        end
    end
end

local function ConfigureEditor(editor)
    -- settints from ru-SciTE

    -- editor:SetCaretLineBackAlpha(20)

    -- caret.policy.xslop	1
    -- caret.policy.width	20
    -- caret.policy.xstrict	0
    -- caret.policy.xeven	0
    -- caret.policy.xjumps	0
    editor:SetXCaretPolicy(bit.bor(0
        , wxstc.wxSTC_CARET_SLOP
        , wxstc.wxSTC_CARET_STRICT
        -- , wxstc.wxSTC_CARET_EVEN
        -- , wxstc.wxSTC_CARET_JUMPS
    ), 20)

    -- caret.policy.yslop	1
    -- caret.policy.lines	1
    -- caret.policy.ystrict	1
    -- caret.policy.yeven	1
    -- caret.policy.yjumps	0
    editor:SetXCaretPolicy(bit.bor(0
        , wxstc.wxSTC_CARET_SLOP
        , wxstc.wxSTC_CARET_STRICT
        , wxstc.wxSTC_CARET_EVEN
        -- , wxstc.wxSTC_CARET_JUMPS
    ), 1)

    -- visible.policy.strict
    -- visible.policy.slop
    -- visible.policy.lines
    editor:SetVisiblePolicy(bit.bor(0
        -- ,wxstc.wxSTC_VISIBLE_STRICT
        ,wxstc.wxSTC_VISIBLE_SLOP
    ), 3)
end

local function GotoBrace()
  local editor = Editor.HasFocus(ide:GetEditor())
  if not editor then return end
  return GoMatchingBrace(editor, false)
end

local function SelectBrace()
  local editor = Editor.HasFocus(ide:GetEditor())
  if not editor then return end
  return GoMatchingBrace(editor, true)
end

function Package.onRegister(package)
    GOTO_MATCH_BRACE:set(GotoBrace)
    SELECT_MATCH_BRACE:set(SelectBrace)
end

function Package.onUnRegister()
  GOTO_MATCH_BRACE:unset()
  SELECT_MATCH_BRACE:unset()
end

function Package.onEditorNewfunction(_, editor) ConfigureEditor(editor) end

function Package.onEditorLoad(_, editor) ConfigureEditor(editor) end

local function key_is(k, t)
    for i = 1, #t do
        if k == t then return true end
    end
end

local KEY_E = {string.byte('e'), string.byte('E')}

Package.onEditorKeyDown = function(self, editor, event)
    local key = event:GetKeyCode()
    local mod = event:GetModifiers()

    if not key_is(key, KEY_E) then
        return true
    end

    if mod == wx.wxMOD_CONTROL then
        GotoBrace()
        return false
    end

    if mod == (wx.wxMOD_CONTROL + wx.wxMOD_SHIFT) then
        SelectBrace()
        return false
    end

    return true
end

return Package
