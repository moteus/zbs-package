-- required patch for `LoadFile` function to be able
-- keep Undo buffer intact

local function ReloadCurrentDocument(editor)
  local document = ide:GetDocument(editor)
  local fileName = document and document:GetFilePath()
  if fileName then
    editor:BeginUndoAction()
    LoadFile(fileName, editor, true, nil, true)
    editor:EndUndoAction()
  end
end

return {
  name = "Reload document",
  description = "Reload current document from file and discard all changes",
  author = "Alexey Melnichuk",
  version = 0.1,
  dependencies = "1.7",

  onEditorKeyDown = function(self, editor, event)
      local key = event:GetKeyCode()
      local mod = event:GetModifiers()

      -- Ctrl+R
      if (key == string.byte('r') or key == string.byte('R')) and
          (mod == wx.wxMOD_CONTROL)
      then
          ReloadCurrentDocument(editor)
          return false
      end
  end,
}