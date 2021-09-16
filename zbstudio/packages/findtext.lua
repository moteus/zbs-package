local Editor       = package_require 'utils.editor'
local HotKeys      = package_require 'hotkeys.manager'

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

local function GetCurrentWord(editor, pos)
    local pos_start = editor:WordStartPosition(pos, true)
    local pos_end   = editor:WordEndPosition(pos, true)
    local word = editor:GetTextRange(pos_start, pos_end)
    if #word == 0 then
        -- try to select a non-word under caret
        pos_start = editor:WordStartPosition(pos, false)
        pos_end   = editor:WordEndPosition(pos, false)
        word = editor:GetTextRange(pos_start, pos_end)
    end
    return word, pos_start, pos_end
end

local function GetWord(editor, pos)
    local sel_start, sel_end = editor:GetAnchor(), editor:GetCurrentPos()
    if sel_start ~= sel_end then
        local word = editor:GetTextRange(math.min(sel_start, sel_end), math.max(sel_start, sel_end))
        return word, true, sel_start, sel_end
    end
    local word, word_start, word_end = GetCurrentWord(editor, pos or editor:GetCurrentPos())
    return word, false, word_start, word_end
end

local function GetWortStyle(editor, pos)
  -- Name allows to select all strings. E.g. for Lua lexer 
  -- single and double quotes have a different styles.
  return Editor.GetStyleNameAt(editor, pos)
  -- return Editor.GetStyleAt(editor, pos)
end

local function EditorClearMarks(editor, indicator, start, length)
    indicator = indicator or INSTALLED_MARKERS
    return Editor.ClearMarks(editor, indicator, start, length)
end

local function EditorMarkText(editor, start, length, indicator)
    return Editor.MarkText(editor, start, length, indicator)
end

local function ShowOutput()
  -- based on menu_view.lua::togglePanel

  local uimgr = ide.frame and ide.frame.uimgr
  if not uimgr then return end

  local pane = uimgr:GetPane('bottomnotebook')
  if not pane then return end

  if pane:IsShown() then return end

  pane:BestSize(pane.window:GetSize())
  pane:Show(true)
  uimgr:Update()

  return true
end

local function GetNextFindMarkerNumber(editor)
  local output = ide:GetOutput()

  local current_mark_number   = INSTALLED_MARKERS[current_marker]
  local current_mark_settings = FIND_MARKERS[current_marker]

  current_marker = current_marker + 1
  if current_marker > #INSTALLED_MARKERS then
    current_marker = 1
  end

  if current_mark_number then
    Editor.ConfigureIndicator(editor, current_mark_number, current_mark_settings)
    Editor.ConfigureIndicator(output, current_mark_number, current_mark_settings)
  end

  return current_mark_number
end

local function GetFileName(editor)
  --! @fixme there no file path for new documents (which not saved on disk)
  local doc = Editor.GetDocument(editor)
  local filePath = doc and (doc:GetFilePath() or doc:GetFileName()) or ''
  return filePath
end

local function GetFindFlags(editor, word_pos, is_selected)
  local flags = is_selected and 0 or wx.wxFR_WHOLEWORD
  if HIGHLIGHT_MATCHCASE then flags = flags + wx.wxFR_MATCHCASE end
  return flags
end

local function GetFindParams(editor, pos)
    local sText, selected, word_start, word_end  = GetWord(editor, pos)
    if (not sText) or (sText == '') then
        return
    end

    local flags       = GetFindFlags(editor, word_start, selected)
    local word_style
    if HIGHLIGHT_MATCHSTYLE and not selected then
        word_style = GetWortStyle(editor, word_start)
    end

    return sText, flags, selected, word_start, word_style, word_end
end

local function DoFindText(editor_, pos)
    editor = editor_

    local current_pos = pos or editor:GetCurrentPos()

    local sText, flags, selected, word_pos, word_style = GetFindParams(editor, current_pos)
    if not sText then
        return
    end

    local marker      = GetNextFindMarkerNumber(editor)
    local filePath    = GetFileName(editor)

    if bookmark then editor:MarkerDeleteAll(bookmark) end

    local output      = ide:GetOutput()
    if isOutput then
        local msg
        if selected then
            msg = '> '..L'Search for selected text'..': "'
        else
            msg = '> '..L'Search for current word'..': "'
        end

        print(msg .. sText .. '"')
    end

    local current_output_line_start, current_editor_line_start

    local count, marked = 0
    for s, e in Editor.iFindText(editor, sText, flags, nil, nil, word_style) do
        count = count + 1

        local line = editor:LineFromPosition(s)
        EditorMarkText(editor, s, e - s, marker)
        if line ~= marked then
            marked = line
            if bookmark then editor:MarkerAdd(line, bookmark) end

            if isOutput then
                local prefix = filePath .. string.format(':%d:\t', line + 1)

                current_editor_line_start = editor:PositionFromLine(line)
                -- we always aling output to line start
                current_output_line_start = output:GetCurrentPos()
                current_output_line_start = current_output_line_start + #prefix

                local str = editor:GetLine(line) or ''
                local length = #str
                str = string.gsub(str, '^%s+', '')

                current_output_line_start = current_output_line_start - (length - #str)

                -- can not remove spaces in the middle of the string because of
                -- it will change offsets of the words
                str = string.gsub(str, '%s+$', '')
                print(prefix .. str)
            end
        end

        if isOutput then
            local offset_in_line = s - current_editor_line_start
            local length = e - s
            local output_offset = current_output_line_start + offset_in_line
            EditorMarkText(output, output_offset, length, marker)
        end
    end

    if count > 0 then
        if isOutput then
            print('>' .. TR("Found %d instance.", count):format(count))
            if isTutorial then
                --! @todo implement jump by marks/lines
                -- print('F3 (Shift+F3) - '..L'Jump by markers' )
                -- print('F4 (Shift+F4) - '..L'Jump by lines'   )
                print('Ctrl+Alt+C - '..L'Erase all markers'  )
            end
        end
    else
        print('> '..string.gsub(L"Can't find [@]!", '@', sText))
    end

    editor:GotoPos(current_pos)

    ShowOutput()

    output:Show()
    output:SetFocus()
end

local function SetNextSelection(editor, skip, start_pos, end_pos)
    if skip then
        if editor:GetSelections() <= 1 then
            Editor.SetSel(editor, start_pos, end_pos)
        else
            local index = editor:GetMainSelection()
            editor:SetSelectionNCaret(index, end_pos)
            editor:SetSelectionNAnchor(index, start_pos)
        end
    else
        editor:AddSelection(start_pos, end_pos)
        local index = editor:GetMainSelection()
        editor:SetSelectionNCaret(index, end_pos)
        editor:SetSelectionNAnchor(index, start_pos)
    end
    editor:ShowRange(end_pos, start_pos)
end

local function CalculateSelectionRange(selected, order, s, e, offset)
    local start_pos, end_pos
    if selected then
        if order then
            start_pos, end_pos = s, e
        else
            start_pos, end_pos = e, s
        end
    else
        start_pos = s + offset
        end_pos = start_pos
    end
    return start_pos, end_pos
end

local function PosInSelection(editor, pos)
    for i = 1, editor:GetSelections() do
        local start_pos, end_pos = editor:GetSelectionNStart(i-1), editor:GetSelectionNEnd(i-1)
        if pos >= start_pos and pos <= end_pos then
            return i
        end
    end
end

local function GotoNext(editor_, skip)
    editor = editor_

    local sText, flags, selected, word_start, word_style, word_end = GetFindParams(editor, pos)
    if not sText then
        return
    end

    local pos = editor:GetCurrentPos()
    local offset = pos - word_start
    local order  = (word_start <= word_end)

    local search_start_pos = math.max(word_start, word_end)
    for s, e in Editor.iFindText(editor, sText, flags, search_start_pos, nil, word_style) do
        local start_pos, end_pos = CalculateSelectionRange(selected, order, s, e, offset)
        if not PosInSelection(editor, end_pos) then
            SetNextSelection(editor, skip, start_pos, end_pos)
            return
        end
    end

    search_start_pos = math.min(word_start, word_end)
    for s, e in Editor.iFindText(editor, sText, flags, nil, search_start_pos, word_style) do
        local start_pos, end_pos = CalculateSelectionRange(selected, order, s, e, offset)
        if not PosInSelection(editor, end_pos) then
            SetNextSelection(editor, skip, start_pos, end_pos)
            return
        end
    end
end

local function FindAll(editor_)
    editor = editor_

    local sText, flags, selected, word_start, word_style, word_end = GetFindParams(editor, pos)
    if not sText then
        return
    end

    local first_line = editor:GetFirstVisibleLine()
    local pos = editor:GetCurrentPos()
    local offset = pos - word_start
    local order  = (word_start <= word_end)

    editor:ClearSelections()

    local main_index
    for s, e in Editor.iFindText(editor, sText, flags, nil, nil, word_style) do
        if s <= pos and pos <= e then
            main_index = editor:GetSelections() - 1
        end
        local start_pos, end_pos = CalculateSelectionRange(selected, order, s, e, offset)
        if not PosInSelection(editor, end_pos) then
            SetNextSelection(editor, skip, start_pos, end_pos)
        end
    end

    if main_index then
        editor:SetMainSelection(main_index)
        editor:SetFirstVisibleLine(first_line)
    end
end

local function UndoNext(editor)
    if editor:GetSelections() <= 1 then
        return
    end

    local index = editor:GetMainSelection()
    editor:DropSelectionN(index)
    local sel_start, sel_end = editor:GetSelection()
    editor:ShowRange(sel_end, sel_start)
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

local function RangeExists(positions, a, b)
    for i = 1, #positions do
        local range = positions[i]
        if range[1] == a and range[2] == b then
            return true
        end
    end
end

local function AppendSelectionArray(editor, positions)
    local selection_pos_start, selection_pos_end = editor:GetSelection()
    if selection_pos_start == selection_pos_end then return positions end

    if RangeExists(positions.ranges, selection_pos_start, selection_pos_end) then
        return positions
    end
    table.insert(positions.ranges, {selection_pos_start, selection_pos_end})

    if not editor:SelectionIsRectangle() then
        table.insert(positions,{
            selection_pos_start, selection_pos_end
        })
        return positions
    end

    local selection_line_start = editor:LineFromPosition(selection_pos_start)
    local selection_line_end   = editor:LineFromPosition(selection_pos_end)
    for line = selection_line_start, selection_line_end do
        local selection_line_pos_start = editor:GetLineSelStartPosition(line)
        local selection_line_pos_end   = editor:GetLineSelEndPosition(line)
        table.insert(positions, {selection_line_pos_start, selection_line_pos_end})
    end
    return positions
end

local function GetAllSelections(editor)
    local positions = {ranges = {}}
    local current_selection = editor:GetMainSelection()
    for i = 0, editor:GetSelections() - 1 do
        editor:SetMainSelection(i)
        AppendSelectionArray(editor, positions)
    end
    editor:SetMainSelection(current_selection)

    table.sort(positions, function(lhs, rhs)
        if lhs[1] == rhs[1] then
            return lhs[2] < rhs[2]
        end
        return lhs[1] < rhs[1] 
    end)

    return positions
end

local function iSelection(editor)
    local i = 0
    return function(p)
        i = i + 1
        local r = p[i]
        if r then return r[1], r[2] end
    end, GetAllSelections(editor)
end

local function ClearFindMarks()
    local editor = ide:GetEditor()
    if not editor then return end

    local selected = false

    for selection_pos_start, selection_pos_end in iSelection(editor) do
        selected = true
        local selection_legth = selection_pos_end - selection_pos_start
        EditorClearMarks(editor, nil, selection_pos_start, selection_legth)
        if bookmark then
            local selection_line_start = editor:LineFromPosition(selection_pos_start)
            local selection_line_end   = editor:LineFromPosition(selection_pos_end)
            for line = selection_line_start, selection_line_end do
                editor:MarkerDelete(line, bookmark)
            end
        end
    end

    if not selected then
        EditorClearMarks(editor)
        if bookmark then editor:MarkerDeleteAll(bookmark) end
    end

    current_marker = 1
end

local function MarkSelected(editor, indicator, unmark)
  if type(indicator) == 'string' then
    indicator = ide:GetIndicator()
  end

  if type(indicator) ~= 'number' then
    return
  end

  for selection_pos_start, selection_pos_end in iSelection(editor) do
    local selection_legth = selection_pos_end - selection_pos_start
    Editor.MarkText(editor, selection_pos_start, selection_legth, indicator)
  end
end

local function CallMarkSelected()
    local editor = ide:GetEditor()
    local indicator = INSTALLED_MARKERS[1]
    local style     = FIND_MARKERS[1]
    Editor.ConfigureIndicator(editor, indicator, style)
    MarkSelected(editor, indicator)
end

local actions = {
    next       = function() local editor = ide:GetEditorWithFocus() if ide:IsValidCtrl(editor) then GotoNext(editor, false) end end,
    skip_next  = function() local editor = ide:GetEditorWithFocus() if ide:IsValidCtrl(editor) then GotoNext(editor, true) end end,
    undo_next  = function() local editor = ide:GetEditorWithFocus() if ide:IsValidCtrl(editor) then UndoNext(editor) end end,
    find_all   = function() local editor = ide:GetEditorWithFocus() if ide:IsValidCtrl(editor) then FindAll(editor) end end,
    clear      = function() local editor = ide:GetEditor() if ide:IsValidCtrl(editor) then ClearFindMarks(editor) end end,
    call       = function() local editor = ide:GetEditor() if ide:IsValidCtrl(editor) then ClearFindMarks(editor) end end,
}

local keys = {
    ['Ctrl-Alt-C'         ] = 'clear',
    ['Ctrl-Alt-S'         ] = 'call',
    ['Ctrl-J'             ] = 'next',    ['Alt-J'              ] = 'find_all',
    ['Ctrl-K Ctrl-J'      ] = 'skip_next',
    ['Ctrl-Shift-J'       ] = 'undo_next',
}

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

    bookmark   = findtext.bookmarks
    isOutput   = findtext.output
    isTutorial = findtext.tutorial
    if bookmark == true then bookmark = FINDTEXT.bookmarks end

    for key, handler in pairs(keys) do
        handler = assert(actions[handler], 'Unsupported action: ' .. tostring(handler))
        HotKeys:add(package, key, handler)
    end
end

Package.onUnRegister = function(package)
    HotKeys:close_package(package)

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

    if not ide:IsValidCtrl(editor) then
        return
    end

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
        word_style = GetWortStyle(editor, select_start)
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

Package.onEditorKeyDown = function(self, editor, event)
    if event:GetModifiers() ~= 0 then
        return true
    end

    if event:GetKeyCode() ~= wx.WXK_ESCAPE then
        return true
    end

    local n = editor:GetSelections() - 1

    if n <= 0 then
        return true
    end

    local start_pos, end_pos = editor:GetSelection()
    if end_pos == editor:GetAnchor() then
        start_pos, end_pos = end_pos, start_pos
    end
    editor:ClearSelections()
    Editor.SetSel(editor, start_pos, end_pos)

    return true
end

return Package
