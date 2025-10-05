--//=============================================================================
--// FontSystem

FontHandler = {}


--//=============================================================================
--// cache loaded fonts

local loadedFonts = {}

--//  maximum fontsize difference
--// when we don't find the wanted font rendered with the wanted fontsize
--// (in respect to this threshold) then recreate a new one
-- local fontsize_threshold = 0 -- who thought this was ever a good idea?

--//=============================================================================
--// Destroy
local glDeleteFont = gl.DeleteFont
local glLoadFont = gl.LoadFont
local Echo = Spring.Echo
FontHandler._scream = Script.CreateScream()
FontHandler._scream.func = function()
	for font in pairs(loadedFonts) do
		glDeleteFont(font)
		loadedFonts[font] = nil
	end
end


local n = 0
local deletedCount = 0
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
			deletedCount = deletedCount + 1
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
			and (not outwidth or font.outlinewidth == outwidth)
			and (not outweight or font.outlineweight == outweight)
		then
			loadedFonts[font] = refCount + 1
			return font
		end
	end

	local font = glLoadFont(fontname,size,outwidth,outweight)
	loadedFonts[font] = 1
	return font
end

function FontHandler.InvalidateFontCache()
	loadedFonts = {}
end

function FontHandler.Tell()
	local cntLoad, cntRef = 0, 0
	for _, ref in pairs(loadedFonts) do
		cntLoad, cntRef = cntLoad + 1, cntRef + ref
	end
	Echo('Total loaded fonts: ' .. cntLoad, cntRef .. ' references. ' .. deletedCount .. ' has been deleted.')
end