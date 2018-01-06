local Package = {
  name = "Smart braces",
  author = "Dmitry Maslov, Julgo, TymurGubayev, Alexey Melnichuk",
  version = '1.3.1',
  description = [[Port xComment from ru-SciTE project
Необходим обработчик onEditorKey который не реализован в 1.70
```Lua
  editor:Connect(wx.wxEVT_CHAR,
    function (event)
      if PackageEventHandle("onEditorKey", editor, event) == false then
        -- this event has already been handled
        return
      end
      event:Skip()
    end)
```

-------------------------------------------------
Настройки:
 braces.autoclose = true
 braces.open = открывающиеся скобки
 braces.close = закрывающиеся скобки
 braces.multiline - определяет перечень имен лексеров (через запятую) 
  для которых фигурная скобка вставляется в три строки с курсором посередине.
  По умолчанию braces.multiline=cpp

-------------------------------------------------
Функционал:

 Автозакрытие скобок
 Автозакрытие выделенного текста в скобки
 Особая обработка { и } в cpp: автоматом делает отступ

-------------------------------------------------
Логика работы:

 Скрипт срабатывает только если braces.autoclose = 1

 Если мы вводим символ из braces.open, то автоматически вставляется
 ему пара из braces.close, таким образом, курсор оказывается между скобок

 Если мы вводим закрывающуюся скобку из braces.close и следующий символ
 эта же закрывающаяся скобка, то ввод проглатывается и лишняя закрывающаяся
 скобка не печатается

 Если у нас выделен текст и мы вводим символ из braces.open,
 то текст обрамляется кавычками braces.open - braces.close
 если он уже был обрамлен кавычками, то они снимаются,
 при этом учитывается символ переноса строки, т.е. если выделенный
 текст оканчивается переводом строки, то скобки вставляются до переноса
 строки

 Если мы вводим символ { при редактировании файла cpp, то автоматически
 вставляется перенос строки два раза, а после } - курсор при этом оказывается
 в середине, т.е. после первого переноса строки, все отступы сохраняются

 Если мы вставляем символ } при редактировании файла cpp, то отступ
 автоматически уменьшается на один

 Если мы только что вставили скобку автоматом, то после того
 как нажимаем BACK_SPACE удаляется вставленная скобка, т.е.
 срабатывает как DEL, а не как BACK_SPACE

 Если вставляем скобку у которой braces.open == braces.close,
 то вставляется пара только если таких скобок четно в строке
  ]],
  dependencies = "1.30",
}

local DEFAULT = {
  open   ="({['\"";
  close  =")}]'\"";
}

-----------------------------------------------------------------------------------
local editor, config

local BRACES

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

local lua_patt_chars = "[%(%)%.%+%-%*%?%[%]%^%$%%]"
function StringToPattern( s )
  return (s:gsub(lua_patt_chars,'%%%0'))
end

local function FindCount( text, textToFind )
  local count = 0;
  for _ in string.gmatch(text, StringToPattern(textToFind) ) do
    count = count + 1
  end
  return count
end

local function IsEvenCount(text, textToFind)
  return math.fmod(FindCount(text, textToFind), 2) == 1
end

-- позиция это начало строки (учитывая отступ)
local function IsLineStartPos( pos )
  local line = editor:LineFromPosition(pos)
  return pos == editor:GetLineIndentPosition(line)
end

-- Получить номер текущей строки
local function GetCurrLineNumber()
  local pos = editor:GetCurrentPos()
  return editor:LineFromPosition(pos)
end

-- Получить отступ в строке
local function GetLineIndentation( num_line )
  if num_line < 0 then num_line = 0 end
  local count = editor:GetLineCount()
  if num_line >= count then num_line = count - 1 end

  local line_indent = editor:GetLineIndentation(num_line)
  local indent = editor:GetIndent()
  if indent <= 0 then indent = 1 end

  return math.floor(line_indent / indent)
end

-- последний в строке ?
local function IsInLineEnd( num_line, text )
  local endpos = editor:GetLineEndPosition(num_line)
  if endpos < string.len( text ) then return false end
  local pos_before = editor:PositionBefore( endpos - string.len( text ) + 1 )
  local range = editor:GetTextRange(pos_before, endpos)
  return not not string.find(range, StringToPattern(text))
end

-- последний символ в строке - конец строки?
local function IsEOLlast( text )
  local eol = Editor.GetEOL(editor)
  return string.sub(text, -#eol) == eol
end

-- следующий за позицией текст == text ?
local function nextIs(pos, text)
  local pos_after = editor:PositionAfter(pos + string.len(text) - 1)
  local range = editor:GetTextRange(pos, pos_after)
  return not not string.find(range, StringToPattern(text))
end

-- следующий символ позиции конец строки?
local function nextIsEOL(pos)
  return pos >= editor:GetLength()
    or nextIs(pos, Editor.GetEOL(editor))
end

-----------------------------------------------------------------
-- проверяет скобки, заданные bracebegin и braceend в строке s на 
-- сбалансированность: "(x)y(z)" -> true, "x)y(z" -> false
local function BracesBalanced (s, bracebegin, braceend)
  if (#bracebegin + #braceend) > 2 then
    --@warn: данная функция не будет работать со "скобками" больше одного символа.
    --@todo: для "длинных" скобок нужно переписать эту функцию на lpeg. Но кому оно надо?..
    return true
  end

  local b , e = s:find("%b"..bracebegin..braceend)
  local b2 = s:find(bracebegin, 1, true)
  local e2 = s:find(braceend, 1, true)
  return (b == b2) and (e == e2)
end -- BracesBalanced

local function BlockBraces( bracebegin, braceend )
  local pos = editor:GetCurrentPos()
  local text, selbegin, selend = Editor.GetSelText(editor)
  local b, e   = string.find( text, "^%s*"..StringToPattern(bracebegin) )
  local b2, e2 = string.find( text, StringToPattern(braceend).."%s*$" )
  local add = ( IsEOLlast( text ) and Editor.GetEOL(editor) ) or ""

  editor:BeginUndoAction()
  if b and b2 and BracesBalanced(string.sub(text, e+1, b2-1), bracebegin, braceend) then
    text = string.sub(text, e+1, b2-1 )
    editor:ReplaceSelection(text..add)
    selend = selbegin + #( text..add )
  else
    editor:InsertText( selend - #add, braceend )
    editor:InsertText( selbegin, bracebegin )
    selend = selend + #( bracebegin..braceend )
  end
  if pos == selbegin then
    selbegin, selend = selend, selbegin
  end
  Editor.SetSel(editor, selbegin, selend)

  editor:EndUndoAction()

  return true
end

-- возвращает открывающуюся скобку и закрывающуюся скобку
-- по входящему символу, т.е. например,
-- если на входе ')' то на выходе '(' ')'
-- если на входе '(' то на выходе '(' ')'
local function GetBraces( char )
  local braceOpen, braceClose = '', ''
  local brIdx, symE = BRACES.open[char]
  if brIdx then
    symE = BRACES.close[brIdx]
    if symE then
      braceOpen = char
      braceClose = symE
    end
  else
    brIdx = BRACES.close[char]
    if brIdx then
      symE = BRACES.open[brIdx]
      if symE then
        braceOpen = symE
        braceClose = char
      end
    end
  end
  return braceOpen, braceClose
end

local g_isPastedBraceClose = false

-- "умные скобки/кавычки" 
-- возвращает true когда обрабатывать дальше символ не нужно
local function SmartBraces(char)
  if not config.autoclose then
    return false
  end

  -- находим парный символ
  local braceOpen, braceClose = GetBraces(char)

  if braceOpen == '' or braceClose == '' then
    return false
  end

  -- if we have multiple selections then just ignore it
  if editor:GetSelections() > 1 then
    return false
  end

  local multiline = BRACES.multi[Editor.GetLanguage(editor)]

  local isSelection = editor:GetSelectionStart() ~= editor:GetSelectionEnd()

  if isSelection then
    -- делаем обработку по автозакрытию текста скобками
    return BlockBraces(braceOpen, braceClose)
  end

  local curpos = editor:GetCurrentPos()
  local nextSymbol = Editor.GetSymbolAt(editor, curpos)

  -- если следующий символ закрывающаяся скобка
  -- и мы ее вводим, то ввод проглатываем
  if char == nextSymbol and BRACES.close[nextSymbol] then
    editor:CharRight()
    return true
  end

  -- если мы ставим открывающуюся скобку и
  -- следующий символ конец строки или это парная закрывающаяся скобка
  -- то сразу вставляем закрывающуюся скобку
  if char == braceOpen and (nextIsEOL(curpos) or nextIs(curpos, braceClose)) then
      -- по волшебному обрабатываем скобку { в cpp
      if char == '{' and multiline then
        editor:BeginUndoAction()
        local ln = GetCurrLineNumber()
        if ln > 0
          and GetLineIndentation( ln ) > GetLineIndentation( ln - 1 )
          and IsLineStartPos( curpos )
          and not IsInLineEnd( ln-1, '{' )
        then
          editor:BackTab()
        end
        editor:AddText( '{' )
        editor:NewLine()
        if GetLineIndentation( ln ) == GetLineIndentation( ln + 1 ) then
          editor:Tab()
        end
        local pos = editor:GetCurrentPos()
        editor:NewLine()
        if GetLineIndentation( ln + 2 ) == GetLineIndentation( ln + 1 ) then
          editor:BackTab()
        end
        editor:AddText( '}' )
        editor:GotoPos( pos )
        editor:EndUndoAction()
        return true
      end

      -- если вставляем скобку с одинаковыми правой и левой, то смотрим есть ли уже открытая в строке
      if braceOpen == braceClose and IsEvenCount(editor:GetCurLine(), braceOpen) then
        return false
      end

      -- вставляем закрывающуюся скобку
      editor:BeginUndoAction()
      editor:InsertText(curpos, braceClose)
      editor:EndUndoAction()
      g_isPastedBraceClose = true

      return false
  end

  -- если мы ставим закрывающуюся скобку
  if char == braceClose then
    -- "по волшебному" обрабатываем скобку } в cpp
    if char == '}' and multiline then
      editor:BeginUndoAction()
      if IsLineStartPos(curpos)then
        editor:BackTab()
      end
      editor:AddText('}')
      editor:EndUndoAction()
      return true
    end

    return false
  end

  return false
end

-- Перехватываем функцию редактора OnKey
local function OnKey(key, shift, ctrl, alt, char)
  if ( key == 8 and g_isPastedBraceClose == true ) then -- VK_BACK (08)
    g_isPastedBraceClose = false
    editor:BeginUndoAction()
    editor:CharRight()
    editor:DeleteBack()
    editor:EndUndoAction()
    return true
  end

  g_isPastedBraceClose = false

  if char then
    return SmartBraces( char )
  end
end

function Package.onRegister(package)
  config = package:GetConfig()
  local open, close
  if config.open then
    open, close = config.open, config.close or ''
  else
    open, close = DEFAULT.open, DEFAULT.close
  end

  local n = math.min(#open, #close)
  BRACES = {open = {}, close = {}, multi = {}}
  for i = 1, n do
    local ch = string.sub(open, i, i)
    BRACES.open[i] = ch
    BRACES.open[ch] = i

    ch = string.sub(close, i, i)
    BRACES.close[i] = ch
    BRACES.close[ch] = i
  end

  local multiline = config.multiline
  if multiline ~= false then
    multiline = multiline or 'cpp'
    for lang in string.gmatch(multiline, "%w+") do
      BRACES.multi[lang] = true
    end
  end
end

function Package.onUnRegister()
  editor, config, BRACES = nil
end

local function IsBitSet(b, v)
    return (v == bit.band(b, v))
end

function Package.onEditorKey(self, editor_, event)
  editor = editor_
  local key  = event:GetKeyCode()
  local char = (key < 255) and string.format('%c', key)
  local mode = bit.band(event:GetModifiers(),
    wx.wxMOD_SHIFT + wx.wxMOD_ALT + wx.wxMOD_CONTROL
  )
  local shift, ctrl, alt = IsBitSet(mode, wx.wxMOD_SHIFT),
    IsBitSet(mode, wx.wxMOD_CONTROL), IsBitSet(mode, wx.wxMOD_ALT)

  if not OnKey(key, shift, ctrl, alt, char) then
    event:Skip()
  end

  return false
end

return Package
