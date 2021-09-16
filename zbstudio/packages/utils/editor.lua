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

local Editor = {}

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

local function IsComment(spec, lang, style)
  local is_comment = spec and spec.iscomment or IS_COMMENT[lang]

  if is_comment then
    return is_comment[style]
  end

  -- For most other lexers comment has style 1
  -- asn1, ave, blitzbasic, cmake, conf, eiffel, eiffelkw, erlang, euphoria, fortran,
  -- f77, freebasic, kix, lisp, lout, octave, matlab, metapost, nncrontab, props, batch,
  -- makefile, diff, purebasic, vb, yaml
  return style == 1
end

local function IsString(spec, lang, style)
  local is_string = spec and spec.isstring
  return is_string and is_string[style] or false
end

local function GetStyleName(spec, lang, style)
  if IsComment(spec, lang, style) then
    return 'comment'
  end

  if IsString(spec, lang, style) then
    return 'string'
  end

  return 'text'
end

function Editor.GetLexer(editor)
  return editor.spec and editor.spec.lexer or editor:GetLexer()
end

function Editor.GetLanguage(editor)
  local lexer = Editor.GetLexer(editor)
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

function Editor.GetStyleNameAt(editor, pos)
  local style = Editor.GetStyleAt(editor, pos)
  local lang  = Editor.GetLanguage(editor)
  return GetStyleName(editor.spec, lang, style), lang
end

function Editor.ReplaceTextRange(editor, start_pos, end_pos, text)
  if start_pos ~= end_pos then
    local length = math.abs(start_pos - end_pos)
    start_pos    = math.min(start_pos, end_pos)
    editor:DeleteRange(start_pos, length)
  end
  editor:InsertText(start_pos, text)
  editor:SetSelection(start_pos + #text, start_pos + #text)
end

function Editor.FindText(editor, text, flags, start, finish)
  editor:SetSearchFlags(flags or 0)
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

local function isStyleMatch(editor, pos, style)
  if type(style) == 'string' then
    return (style == Editor.GetStyleNameAt(editor, pos))
  end
  return (style == Editor.GetStyleAt(editor, pos))
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
      if (not style) or isStyleMatch(editor, start_pos, style) then
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

-- Получить отступ в строке
function Editor.GetLineIndentationLevel(editor, num_line)
  if num_line < 0 then num_line = 0 end
  local count = editor:GetLineCount()
  if num_line >= count then num_line = count - 1 end

  local line_indent = editor:GetLineIndentation(num_line)
  local indent = editor:GetIndent()
  if indent <= 0 then indent = 1 end

  return math.floor(line_indent / indent)
end

-- Получить номер текущей строки
function Editor.GetCurrLineNumber(editor)
  local pos = editor:GetCurrentPos()
  return editor:LineFromPosition(pos)
end

function Editor.GetCurrColNumber(editor)
  local pos = editor:GetCurrentPos()
  return editor:GetColumn(pos)
end

return Editor