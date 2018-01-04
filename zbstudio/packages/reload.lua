local HOT_KEY = 'Ctrl-R'

local ID_RELOAD, ID_PREVIEW

local function ReloadCurrentDocument()
  local editor = ide:GetEditor()
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

  onRegister = function()
    --! @todo add menu item
    --! @todo get shortcut key from config
    ID_PREVIEW = ide:GetHotKey(HOT_KEY)
    ID_RELOAD  = ide:SetHotKey(ReloadCurrentDocument, HOT_KEY)
  end,

  onUnRegister = function()
    if ID_RELOAD == ide:GetHotKey(HOT_KEY) then
      if ID_PREVIEW then
        ide:SetHotKey(ID_PREVIEW, HOT_KEY)
      else
        --! @fixme ZBS 1.70 seems do not accept remove hot keys
        ide:SetHotKey(function()end, HOT_KEY)
      end
    end
    ID_RELOAD, ID_PREVIEW = nil
  end,
}
