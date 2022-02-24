local HotKeys = package_require 'hotkeys.manager'

local HOT_KEY = 'Ctrl-R'

local function ReloadCurrentDocument()
  local editor = ide:GetEditor()
  if editor ~= ide:GetEditorWithFocus() then
    return
  end
  local document = ide:GetDocument(editor)
  local fileName = document and document:GetFilePath()
  if fileName then
    editor:BeginUndoAction()
    editor.EmptyUndoBuffer = function()end
    local ok, status = pcall(ide.LoadFile, ide, fileName, editor, true)
    editor.EmptyUndoBuffer = nil
    editor:EndUndoAction()
    if ok and status then
      editor:SetSavePoint()
    end
  end
end

return {
  name = "Reload document",
  description = "Reload current document from file and discard all changes",
  author = "Alexey Melnichuk",
  version = 0.2,
  dependencies = "1.7",

  onRegister = function(package)
    --! @todo add menu item
    --! @todo get shortcut key from config
    HotKeys:add(package, HOT_KEY, ReloadCurrentDocument)
  end,

  onUnRegister = function(package)
    HotKeys:close_package(package)
  end,
}
