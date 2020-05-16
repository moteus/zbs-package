local Package = {
  name = "Highlight paired tags in HTML/XML",
  author = "mozers™, VladVRO, TymurGubayev, nail333, Alexey Melnichuk",
  version = "2.5.0",
  description = [[Port paired_tags from ru-SciTE project
Подсветка парных и непарных тегов в HTML и XML
В файле настроек задается цвет подсветки парных и непарных тегов

Скрипт позволяет копировать и удалять (текущие подсвеченные) теги, а также
вставлять в нужное место ранее скопированные (обрамляя тегами выделенный текст)
  ]],
  dependencies = "1.70",
}

local updateneeded

local LEXERS = {
    [wxstc.wxSTC_LEX_XML] = true,
    [wxstc.wxSTC_LEX_HTML] = true,
}

local DEFAULT_RED_STYLE  = '#FF0000,@30'
local DEFAULT_BLUE_STYLE = '#0000FF,@30'

-- state
local t = {
    -- tag_start, tag_end, paired_start, paired_end -- positions
    -- begin, finish  -- contents of tags (when copying)
}
local old_current_pos
local blue_indic, red_indic -- номера используемых маркеров
local BLUE_STYLE, RED_STYLE

--- end state

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

local function CopyTags(editor)
    if not t.tag_start then
        print("Error : " .. L"Move the cursor on a tag to copy it!")
        return
    end

    local tag = editor:GetTextRange(t.tag_start, t.tag_end + 1)
    if t.paired_start then
        local paired = editor:GetTextRange(t.paired_start, t.paired_end + 1)
        if t.tag_start < t.paired_start then
            t.begin = tag
            t.finish = paired
        else
            t.begin = paired
            t.finish = tag
        end
    else
        t.begin = tag
        t.finish = nil
    end
end

local function PasteTags(editor)
    if t.begin then
        editor:BeginUndoAction()
        if t.finish then
            local sel_text, pos = Editor.GetSelText(editor)
            local text = t.begin .. sel_text .. t.finish
            editor:ReplaceSelection(text)
            if sel_text == '' then
                editor:GotoPos(pos + #t.begin)
            else
                editor:GotoPos(pos + #text)
            end
        else
            editor:ReplaceSelection(t.begin)
        end
        editor:EndUndoAction()
    end
end

local function DeleteTags(editor)
    if t.tag_start then
        editor:BeginUndoAction()
        if t.paired_start~=nil then
            if t.tag_start < t.paired_start then
                editor:SetSelection(t.paired_start, t.paired_end + 1)
                editor:DeleteBack()
                editor:SetSelection(t.tag_start, t.tag_end + 1)
                editor:DeleteBack()
            else
                editor:SetSelection(t.tag_start, t.tag_end + 1)
                editor:DeleteBack()
                editor:SetSelection(t.paired_start, t.paired_end + 1)
                editor:DeleteBack()
            end
        else
            editor:SetSelection(t.tag_start, t.tag_end + 1)
            editor:DeleteBack()
        end
        editor:EndUndoAction()
    else
        print("Error : "..L"Move the cursor on a tag to delete it!")
    end
end

local function GotoPairedTag(editor)
    if t.paired_start then -- the paired tag found
        editor:GotoPos(t.paired_start+1)
    end
end

local function SelectWithTags(editor)
    if t.tag_start and t.paired_start then -- the paired tag found
        if t.tag_start < t.paired_start then
            editor:SetSelection(t.paired_end + 1, t.tag_start)
        else
            editor:SetSelection(t.tag_end + 1, t.paired_start)
        end
    end
end

local function FindPairedTag(editor, tag)
    local count = 1
    local find_start, find_end, dec

    if editor:GetCharAt(t.tag_start + 1) ~= 47 then -- [/]
        -- поиск вперед (закрывающего тега)
        find_start = t.tag_start + 1
        find_end = editor.Length
        dec = -1
    else
        -- поиск назад (открывающего тега)
        find_start = t.tag_start
        find_end = 0
        dec = 1
    end

    local pattern = "</?"..tag..".*?>"
    local flags = wxstc.wxSTC_FIND_POSIX + wxstc.wxSTC_FIND_REGEXP
    for paired_start, paired_end in
        Editor.iFindText(editor, pattern, flags, find_start, find_end, 1)
    do
        if editor:GetCharAt(paired_start + 1) == 47 then -- [/]
            count = count + dec
        else
            count = count - dec
        end
        if count == 0 then
            t.paired_start = paired_start
            t.paired_end = paired_end - 1
            break
        end
    end
end

local function PairedTagsFinder(editor)
    local current_pos = editor:GetCurrentPos()
    if current_pos == old_current_pos then return end
    old_current_pos = current_pos

    local tag_start = editor:FindText(current_pos, 0,"[<>]",
        wxstc.wxSTC_FIND_POSIX + wxstc.wxSTC_FIND_REGEXP
    )
    if tag_start < 0 then tag_start = nil end

    if tag_start == nil
        or editor:GetCharAt(tag_start) ~= 60 -- [<]
        or Editor.GetStyleAt(editor, tag_start + 1) ~= 1
    then
        t.tag_start = nil
        t.tag_end = nil
        Editor.ClearMarks(editor, blue_indic)
        Editor.ClearMarks(editor, red_indic)
        return
    end

    if tag_start == t.tag_start then return end
    t.tag_start = tag_start

    local tag_end = editor:FindText(current_pos, editor:GetLength(), "[<>]",
        wxstc.wxSTC_FIND_POSIX + wxstc.wxSTC_FIND_REGEXP
    )
    if tag_end < 0 then tag_end = nil end

    if tag_end == nil or editor:GetCharAt(tag_end) ~= 62 then -- [>]
        return
    end
    t.tag_end = tag_end

    t.paired_start = nil
    t.paired_end = nil
    if editor:GetCharAt(t.tag_end-1) ~= 47 then -- не ищем парные теги для закрытых тегов, типа <BR />
        local pos1, pos2 = Editor.FindText(editor, "\\w+",
            wxstc.wxSTC_FIND_POSIX + wxstc.wxSTC_FIND_REGEXP,
            t.tag_start, t.tag_end
        )
        local tag = (pos1 >= 0) and editor:GetTextRange(pos1, pos2) or ''
        FindPairedTag(editor, tag)
    end

    Editor.ClearMarks(editor, blue_indic)
    Editor.ClearMarks(editor, red_indic)

    if t.paired_start then
        -- paint in Blue
        Editor.MarkText(editor, t.tag_start + 1,    t.tag_end    - t.tag_start    - 1, blue_indic)
        Editor.MarkText(editor, t.paired_start + 1, t.paired_end - t.paired_start - 1, blue_indic)
    else
        -- paint in Red
        Editor.MarkText(editor, t.tag_start + 1, t.tag_end - t.tag_start - 1, red_indic)
    end
end

local function ConfigureEditor(editor)
    Editor.ConfigureIndicator(editor, red_indic, RED_STYLE)
    Editor.ConfigureIndicator(editor, blue_indic, BLUE_STYLE)
end

local function wrap(fn) return function()
    local editor = Editor.HasFocus(ide:GetEditor())
    if not editor then return end

    local lexer = editor.spec and editor.spec.lexer or editor:GetLexer()
    if not LEXERS[lexer] then return end

    return fn(editor)
end end

local function K(...) return HotKeyToggle:new(...) end

local HotKeys = {
    copy   = K'Alt+C',
    paste  = K'Alt+V',
    delete = K'Alt+D',
    pgoto  = K'Alt+G',
    select = K'Alt+S',
}

Package.onEditorNew  = function(_, editor) ConfigureEditor(editor) end

Package.onEditorLoad = function(_, editor) ConfigureEditor(editor) end

Package.onRegister = function(package)
    local config = package:GetConfig()

    BLUE_STYLE = config and config.style
        and config.style.blue or DEFAULT_BLUE_STYLE
    RED_STYLE = config and config.style
        and config.style.red or DEFAULT_RED_STYLE

    blue_indic = ide:AddIndicator('pairedtags.blue')
    red_indic  = ide:AddIndicator('pairedtags.red')

    HotKeys.copy   :set(wrap(CopyTags))
    HotKeys.paste  :set(wrap(PasteTags))
    HotKeys.delete :set(wrap(DeleteTags))
    HotKeys.pgoto  :set(wrap(GotoPairedTag))
    HotKeys.select :set(wrap(SelectWithTags))
end

Package.onUnRegister = function()
    ide:RemoveIndicator(blue_indic)
    ide:RemoveIndicator(red_indic)
    blue_indic, red_indic = nil
    BLUE_STYLE, RED_STYLE = nil
    for _, key in pairs(HotKeys) do
        key:unset()
    end
end

Package.onEditorUpdateUI = function(self, editor, event)
    local lexer = editor.spec and editor.spec.lexer or editor:GetLexer()
    if LEXERS[lexer] then
        if bit.band(event:GetUpdated(), wxstc.wxSTC_UPDATE_SELECTION) > 0 then
            updateneeded = editor
        end
    end
end

Package.onIdle = function()
    local editor = updateneeded
    updateneeded = false
    if not ide:IsValidCtrl(editor) then return end
    PairedTagsFinder(editor)
end

return Package
