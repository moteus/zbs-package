local Package = {
  name = "Do not highligh line when select",
  author = "Alexey Melnichuk",
  version = '0.1',
  description = [[Turn off highlight current line when do selection]],
  dependencies = "1.70",
}

local updateneeded

local unpack = table.unpack or unpack

local function is_color(w, c)
    return c[1] == w:Red() and c[2] == w:Green()
        and c[3] == w:Blue()
end

Package.onEditorUpdateUI = function(self, editor, event)
    if bit.band(event:GetUpdated(), wxstc.wxSTC_UPDATE_SELECTION) > 0 then
        updateneeded = editor
    end
end

Package.onIdle = function(self)
    if not updateneeded then return end

    local editor = updateneeded
    updateneeded = false

    if not ide:IsValidCtrl(editor) then
        return
    end

    local style = ide:GetConfig().styles
    local caret = style.text.bg
    local caretlinebg = style.caretlinebg.bg

    local color = editor:GetCaretLineBackground()

    local background

    local s, e = editor:GetSelection()
    if s ~= e then
        if not is_color(color, caret) then
            background = wx.wxColour(unpack(caret))
        end
    else
        if not is_color(color, caretlinebg) then
            background = wx.wxColour(unpack(caretlinebg))
        end
    end

    if background then
        editor:SetCaretLineBackground(background)
    end
end

return Package
