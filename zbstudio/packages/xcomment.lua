local Editor = package_require 'utils.editor'
local HotKey = package_require 'hotkeys.manager'

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

local function append(t, v)
    t[#t + 1] = v
    return t
end

local lua_patt_chars = "[%(%)%.%+%-%*%?%[%]%^%$%%]"
local function StringToPattern( s )
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
        Editor.ReplaceTextRange(editor, block.bstart, next_line_pos, line_uncomment)
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
    Editor.ReplaceTextRange(editor, block.bstart, block.bend, text_comment)
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
    Editor.ReplaceTextRange(editor, block.bstart, block.bend, text_uncomment)

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

    block.is_comment = (Editor.GetStyleNameAt(editor, block.first_char) == 'comment')
    block.text = text

    if iDEBUG then
        printf([[xComment::GetBlock:
    is_comment = %s;
    is_line    = %s;
    bstart     = %d;
    bend       = %d;
    first_line = %d;
    last_line  = %d;]],
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
    if not ide:IsValidCtrl(editor) then return end

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

Package.onRegister = function(package)
    local _, key = ide:GetHotKey(ID_COMMENT or ID.COMMENT)
    if not key or #key == 0 then key = 'Ctrl+Q'end
    HotKey:add(package, key, xComment, true)
end

Package.onUnRegister = function(package)
    HotKey:close_package(package)
end

return Package
