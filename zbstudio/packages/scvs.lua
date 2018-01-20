-- configure Virtual Spaces
local Package = {
  name = "Virtual Spaces configuration",
  author = "Alexey Melnichuk",
  version = '0.1.0',
  description = [[
Virtual space can be enabled or disabled for rectangular selections or in other circumstances or in both.
There are three bit flags SCVS_RECTANGULARSELECTION=1, SCVS_USERACCESSIBLE=2, and SCVS_NOWRAPLINESTART=4 
which can be set independently. 
SCVS_NONE=0, the default, disables all use of virtual space.

SCVS_NOWRAPLINESTART prevents left arrow movement and selection from wrapping to the previous line.
This is most commonly desired in conjunction with virtual space but is an independent setting so works 
without virtual space.

# Configuration

virtual_space = {}
virtual_space.selection = true
virtual_space.editor    = true
virtual_space.nowrap    = true

]],
  dependencies = "1.70",
}

local SCVS_NONE                 = 0
local SCVS_RECTANGULARSELECTION = 1
local SCVS_USERACCESSIBLE       = 2
local SCVS_NOWRAPLINESTART      = 4

local virtual_space_flags

local function build_flag(t)
  if not t then return SCVS_NONE end
  if type(t) == 'number' then return t end
  if t == true then
    return SCVS_RECTANGULARSELECTION
      + SCVS_USERACCESSIBLE
      + SCVS_NOWRAPLINESTART
  end

  local flags = SCVS_NONE

  if t.selection then flags = flags + SCVS_RECTANGULARSELECTION end
  if t.editor    then flags = flags + SCVS_USERACCESSIBLE       end
  if t.nowrap    then flags = flags + SCVS_NOWRAPLINESTART      end

  return flags
end

local function configure(editor)
  editor:SetVirtualSpaceOptions(
    virtual_space_flags
  )
end

return {
  onRegister   = function()
    virtual_space_flags = build_flag(
      ide:GetConfig().virtual_space or SCVS_NONE
    )
  end,
  onEditorNew  = function(_, editor) configure(editor) end,
  onEditorLoad = function(_, editor) configure(editor) end,
}
