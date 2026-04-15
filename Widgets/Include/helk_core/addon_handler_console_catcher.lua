
if not WG.oriAddConsoleLine then
	WG.caughtLines = {}
	local running = false
	local silent = false
	local oriFunc = realHandler.AddConsoleLine
	WG.oriAddConsoleLine = oriFunc
	realHandler.AddConsoleLine = function(self, msg, prio)
		if msg == '[[START CATCH]]' or msg == '[[START SILENT CATCH]]' then
			running = true
			silent = msg == '[[START SILENT CATCH]]'
			if silent then
				return true
			end
		elseif running then
			if msg == '[[END CATCH]]' then
				running = false
				silent = false
				Echo('Successfully copied from console: ' .. #WG.caughtLines .. 'messages')
				return true
			else
				WG.caughtLines[#WG.caughtLines + 1] = msg
			end
			if silent then
				return true
			end
		end
		return oriFunc(self, msg, prio)
	end
	Echo('Successfully implemented Console Catcher Add-on')
end

