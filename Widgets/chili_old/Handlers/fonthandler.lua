--//=============================================================================
--// FontSystem

FontHandler = {}


--//=============================================================================
--// cache loaded fonts

local loadedFonts = {}


--//=============================================================================
--// Destroy
local glDeleteFont = gl.DeleteFont
local glLoadFont = gl.LoadFont

FontHandler._scream = Script.CreateScream()
FontHandler._scream.func = function()
  for font in pairs(loadedFonts) do
    glDeleteFont(font)
    loadedFonts[font] = nil
  end
end


local n = 0
function FontHandler.Update()
	n = n + 1
	if (n <= 100) then
		return
	end
	n = 0

  for font, refCount in pairs(loadedFonts) do     
		--// the font isn't in use anymore, free it
    if refCount <= 0 then
	    glDeleteFont(font)
      loadedFonts[font] = nil
    end
	end
end

--//=============================================================================
--// API

function FontHandler.UnloadFont(font)
  local refCount = loadedFonts[font]
  if refCount then
    loadedFonts[font] = refCount - 1
  end
end

function FontHandler.LoadFont(fontname,size,outwidth,outweight)
  for font, refCount in pairs(loadedFonts) do
    if (font.path == fontname or font.path == 'fonts/'..fontname)
      and font.size == size
      and font.outlinewidth == outwidth
      and font.outlineweight == outweight
    then
      loadedFonts[font] = refCount + 1
      return font
    end
  end

  local font = glLoadFont(fontname,size,outwidth,outweight)
  loadedFonts[font] = 1
  return font
end
