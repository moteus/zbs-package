local Editor = package_require 'utils.editor'

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
  local symE = BRACES.close[ BRACES.open[char] ]
  if symE then
    return char, symE
  end

  symE = BRACES.open[ BRACES.close[char] ]
  if symE then
    return symE, char
  end

  return '', ''
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

function Package.onEditorKeyDown(self, editor_, event)
  editor = editor_

  if g_isPastedBraceClose ~= true then
    return true
  end

  local mod = event:GetModifiers()
  if not (mod == 0 or mod == wx.wxMOD_SHIFT) then
    return true
  end

  local key = event:GetKeyCode()
  if key ~= wx.WXK_SHIFT then
    g_isPastedBraceClose = false
  end

  if key ~= wx.WXK_BACK then
    return true
  end

  editor:BeginUndoAction()
  editor:CharRight()
  editor:DeleteBack()
  editor:EndUndoAction()

  return false
end

function Package.onEditorKey(self, editor_, event)
  editor = editor_

  local modifier = event:GetModifiers()
  if not (modifier == 0 or modifier == wx.wxMOD_SHIFT) then
    return true
  end

  local code = event:GetKeyCode()
  if code == 0 or code == nil or code == wx.WXK_SHIFT or code > 255 then
    return true
  end

  if SmartBraces( string.char(code) ) then
    return false
  end

  return true
end

return Package
