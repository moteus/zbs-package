local enabled
local function configure(editor)
    if enabled ~= nil then
        editor:SetEndAtLastLine(not not enabled)
    end
end
return {
  onRegister = function(package) enabled = ide:GetConfig().endatlast end,
  onEditorNew = function(_, editor) configure(editor) end,
  onEditorLoad = function(_, editor) configure(editor) end,
}