local Editor = package_require 'utils.editor'
local HotKeys = package_require 'hotkeys.manager'

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

local keys = {
    copy   = 'Alt+C',
    paste  = 'Alt+V',
    delete = 'Alt+D',
    pgoto  = 'Alt+G',
    select = 'Alt+S',
}

local actions = {
    copy   = wrap(CopyTags),
    paste  = wrap(PasteTags),
    delete = wrap(DeleteTags),
    pgoto  = wrap(GotoPairedTag),
    select = wrap(SelectWithTags),
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

    for handler, key in pairs(keys) do
        handler = assert(actions[handler], 'Unsupported action: ' .. tostring(handler))
        HotKeys:add(package, key, handler)
    end
end

Package.onUnRegister = function(package)
    ide:RemoveIndicator(blue_indic)
    ide:RemoveIndicator(red_indic)
    blue_indic, red_indic = nil
    BLUE_STYLE, RED_STYLE = nil
    HotKeys:close_package(package)
end

local updateneeded

Package.onEditorUpdateUI = function(self, editor, event)
    local lexer = editor.spec and editor.spec.lexer or editor:GetLexer()
    if LEXERS[lexer] then
        if bit.band(event:GetUpdated(), wxstc.wxSTC_UPDATE_SELECTION) > 0 then
            updateneeded = editor
        end
    end
end

Package.onIdle = function()
    if not updateneeded then return end

    local editor = updateneeded
    updateneeded = false

    if not ide:IsValidCtrl(editor) then
        return
    end

    PairedTagsFinder(editor)
end

return Package
