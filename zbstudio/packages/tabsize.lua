local Package = {
  name = "Set tab size dialog",
  author = "Alexey Melnichuk",
  version = '0.1.0',
  description = [[Create simple dialog to be able set tab size,
  indend size and use tabs parameters.
  ]],
  dependencies = "1.70",
}

local function print(...)
  ide:Print(...)
end

local function printf(...)
  print(string.format(...))
end

local function Counter(n, i)
    i = i or 1
    n = (n or 0) - i
    return function()
        n = n + i
        return n
    end
end

--------------------------------------------------------------------
local GetValues do

local dialog, tabSizeValue, indentSizeValue, useTabsCheckBox

local NextID = Counter(1)

local function CreateDialog()
  dialog = wx.wxDialog(
      wx.NULL,
      wx.wxID_ANY,
      "Set indent opttions",
      wx.wxDefaultPosition,
      wx.wxDefaultSize
  )

  local ID_TABSIZE_TEXTCTRL = NextID()
  local ID_INDEND_TEXTCTRL  = NextID()
  local ID_USETABS_CHECKBOX = NextID()

  local panel          = wx.wxPanel(dialog, wx.wxID_ANY)

  local mainSizer      = wx.wxBoxSizer(wx.wxHORIZONTAL)
  local boxSizer       = wx.wxStaticBoxSizer(
      wx.wxStaticBox(panel, wx.wxID_ANY, ""), wx.wxHORIZONTAL
  )
  local buttonSizer    = wx.wxGridSizer(0, 1, 0, 0)
  local editorSizer    = wx.wxGridBagSizer()

  boxSizer:Add(editorSizer)
  boxSizer:Add(buttonSizer)

  tabSizeValue   = wx.wxTextCtrl( panel, ID_TABSIZE_TEXTCTRL, "4", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTE_PROCESS_ENTER )
  indentSizeValue = wx.wxTextCtrl( panel, ID_INDEND_TEXTCTRL, "4", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTE_PROCESS_ENTER )

  local tabSizeLabel   = wx.wxStaticText( panel, wx.wxID_ANY, 'Tab size')
  local text_w         = tabSizeValue:GetTextExtent("000") * 2
  tabSizeValue:SetInitialSize(wx.wxSize(text_w, -1))

  local indentSizeLabel = wx.wxStaticText( panel, wx.wxID_ANY, 'Indent size')
  indentSizeValue:SetInitialSize(wx.wxSize(text_w, -1))

  useTabsCheckBox = wx.wxCheckBox(panel, ID_USETABS_CHECKBOX, "Use tabs             ",
      wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxALIGN_RIGHT
  )

  local p = wx.wxGBPosition
  local s = wx.wxGBSpan

  editorSizer:Add( tabSizeLabel,     p(0, 0), s(1, 1), wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL+wx.wxALL,  5 )
  editorSizer:Add( tabSizeValue,     p(0, 1), s(1, 1), wx.wxGROW+wx.wxALIGN_CENTER+wx.wxALL, 5 )
  editorSizer:Add( indentSizeLabel,  p(1, 0), s(1, 1), wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL+wx.wxALL,  5 )
  editorSizer:Add( indentSizeValue,  p(1, 1), s(1, 1), wx.wxGROW+wx.wxALIGN_CENTER+wx.wxALL, 5 )
  editorSizer:Add( useTabsCheckBox,  p(2, 0), s(1, 2), wx.wxALIGN_LEFT + wx.wxALIGN_CENTER_VERTICAL+wx.wxALL,  5 )

  local okButton = wx.wxButton( panel, wx.wxID_OK, "")
  okButton:SetDefault()
  local cancelButton = wx.wxButton( panel, wx.wxID_CANCEL, "")

  buttonSizer:Add(okButton,     0, wx.wxALIGN_CENTER_VERTICAL+wx.wxALL,  2 )
  buttonSizer:Add(cancelButton, 0, wx.wxALIGN_CENTER_VERTICAL+wx.wxALL,  2 )

  mainSizer:Add(boxSizer, 0, wx.wxGROW+wx.wxALIGN_CENTER+wx.wxALL, 5 )

  panel:SetSizer(mainSizer)
  mainSizer:SetSizeHints( dialog )
end

function GetValues(tabsize, indent, usetabs)
  if not dialog then CreateDialog() end

  tabsize = tonumber(tabsize) or 2
  indent  = tonumber(indent)  or 2
  usetabs = not not usetabs

  tabSizeValue:SetValue(
    string.format('%d', tabsize)
  )
  indentSizeValue:SetValue(
    string.format('%d', indent)
  )
  useTabsCheckBox:SetValue(usetabs)

  dialog:Centre()

  tabSizeValue:SetFocus()

  local result = dialog:ShowModal(true)

  if wx.wxID_OK == result then
    tabsize = tonumber(tabSizeValue:GetValue()) or tabsize
    indent  = tonumber(indentSizeValue:GetValue()) or indent
    usetabs = not not useTabsCheckBox:GetValue()
    return true, tabsize, indent, usetabs
  end
end

end
--------------------------------------------------------------------

--------------------------------------------------------------------
local HotKeyToggle = {} do
HotKeyToggle.__index = HotKeyToggle

function HotKeyToggle:new(key)
  local o = setmetatable({key = key}, self)
  return o
end

function HotKeyToggle:set(handler)
  assert(self.id == nil)
  self.prev = ide:GetHotKey(self.key)
  self.id = ide:SetHotKey(handler, self.key)
  return self
end

function HotKeyToggle:unset()
  assert(self.id ~= nil)
  if self.id == ide:GetHotKey(self.key) then
    if self.prev then
      ide:SetHotKey(self.prev, self.key)
    else
      --! @todo properly remove handler
      ide:SetHotKey(function()end, self.key)
    end
  end
  self.prev, self.id = nil
end

end
--------------------------------------------------------------------

local function ShowDialog()
  local editor = ide:GetEditor()
  if not editor then return end

  local ok, tabsize, indent, usetabs = GetValues(
    editor:GetTabWidth(),
    editor:GetIndent(),
    editor:GetUseTabs()
  )

  if ok then
    editor:SetTabWidth(tabsize)
    editor:SetIndent(indent)
    editor:SetUseTabs(usetabs)
  end
end

local HOT_KEY = HotKeyToggle:new('Ctrl-Shift-I')

Package.onRegister = function()
  HOT_KEY:set(ShowDialog)
end

Package.onUnRegister = function()
  HOT_KEY:unset()
end

return Package
