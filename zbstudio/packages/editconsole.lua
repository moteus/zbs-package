return {
  onMenuOutput = function(self, menu, editor)
    local ID_CONSOLE_PASTE = ID(self.fname..".output.paste")
    local function paste(event)
      local ro = editor:GetReadOnly()
      editor:SetReadOnly(false)
      editor:PasteDyn()
      editor:GetReadOnly(ro)
    end
    menu:Append(ID_CONSOLE_PASTE, "Paste from Clipboard")
    editor:Connect(ID_CONSOLE_PASTE, wx.wxEVT_COMMAND_MENU_SELECTED, paste)
  end
}