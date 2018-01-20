local Package = {
  name = "onEditorKey event",
  author = "Alexey Melnichuk",
  version = '0.1.0',
  description = [[
    Maps wxEVT_CHAR event to onEditorKey pakage event
    This event calls before editor write char.
    And if plugin returns false then this char will be discarded.
]],
  dependencies = "1.70",
}

local SET = setmetatable({}, {__mode = 'k'})

local function configure(editor)
    if SET[editor] then return end

    editor:Disconnect(wx.wxEVT_CHAR)

    editor:Connect(wx.wxEVT_CHAR, function (event)
        if PackageEventHandle("onEditorKey", editor, event) == false then
            -- this event has already been handled
            return
        end
        event:Skip()
    end)

    SET[editor] = true
end

return {
    onEditorNew  = function(_, editor) configure(editor) end,
    onEditorLoad = function(_, editor) configure(editor) end,
}
