local Editor = package_require 'utils.editor'
local HotKey = package_require 'hotkeys.manager'

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
        return false
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
    if lengthDoc <= 0 then
        return false
    end

    if caretPos > 0 then
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
    if sloppy and braceAtCaret < 0 and caretPos < lengthDoc then
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
    HotKey:add(package, 'Ctrl-E', GotoBrace)
    HotKey:add(package, 'Ctrl-Shift-E', SelectBrace)
end

function Package.onUnRegister(package)
    HotKey:close_package(package)
end

function Package.onEditorNewfunction(_, editor) ConfigureEditor(editor) end

function Package.onEditorLoad(_, editor) ConfigureEditor(editor) end

return Package
