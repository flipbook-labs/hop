local types = require("@root/types")

export type Session = types.Session
export type Message = types.Message
export type Provider = types.Provider

local function emptyMessages(): () -> types.Message?
	return function()
		return nil
	end
end

local function collect(providers: { types.Provider }): { types.Session }
	local sessions: { types.Session } = {}
	for _, provider in providers do
		local ok, result = pcall(provider.sessions, provider)
		if ok then
			for _, session in result :: { types.Session } do
				table.insert(sessions, session)
			end
		end
	end
	table.sort(sessions, function(left: types.Session, right: types.Session)
		if left.updatedAt == right.updatedAt then
			return left.id < right.id
		end
		return left.updatedAt > right.updatedAt
	end)
	return sessions
end

return table.freeze({
	collect = collect,
	emptyMessages = emptyMessages,
})
