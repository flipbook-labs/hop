local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")
local process = require("@std/process")

local types = require("@root/types")

export type Options = {
	homeDirectory: path.Pathlike?,
	projectsPath: path.Pathlike?,
}

local Claude = {}

local function textFromValue(value: json.Value): string?
	if type(value) == "string" then
		return value
	end
	local object = json.asObject(value)
	if object then
		for _, key in { "text", "content", "message" } do
			local child = object[key]
			if child ~= nil then
				local text = textFromValue(child)
				if text and text ~= "" then
					return text
				end
			end
		end
	end
	local array = json.asArray(value)
	if array then
		local parts: { string } = {}
		for _, child in array do
			local text = textFromValue(child)
			if text and text ~= "" then
				table.insert(parts, text)
			end
		end
		if #parts > 0 then
			return table.concat(parts, " ")
		end
	end
	return nil
end

local function cleanTitle(value: string): string
	return (value:gsub("<[^>]+>", " "):gsub("[%c%z]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""):sub(1, 160)
end

local function parseIsoTimestamp(value: string): number?
	local year, month, day, hour, minute, second = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
	if not year then
		return nil
	end
	return os.time({
		year = tonumber(year) :: number,
		month = tonumber(month) :: number,
		day = tonumber(day) :: number,
		hour = tonumber(hour) :: number,
		min = tonumber(minute) :: number,
		sec = tonumber(second) :: number,
	})
end

local function messagesFactory(filepath: path.Pathlike): () -> () -> types.Message?
	return function()
		local ok, contents = pcall(fs.readFileToString, filepath)
		local lines: { string } = {}
		if ok then
			for line in (contents :: string):gmatch("[^\r\n]+") do
				table.insert(lines, line)
			end
		end
		local index = 0
		return function(): types.Message?
			while index < #lines do
				index += 1
				local decodedOk, decoded = pcall(json.deserialize, lines[index])
				local object = if decodedOk then json.asObject(decoded) else nil
				local message = if object then json.asObject(object.message) else nil
				local role = if message then message.role else if object then object.type else nil
				local text = if message then textFromValue(message.content) else nil
				if type(role) == "string" and text and text ~= "" then
					local timestamp = if object and type(object.timestamp) == "string" then object.timestamp else nil
					return { role = role, text = text, timestamp = timestamp }
				end
			end
			return nil
		end
	end
end

local function parseSession(filepath: path.Pathlike): types.Session?
	local readOk, contents = pcall(fs.readFileToString, filepath)
	if not readOk then
		return nil
	end
	local title: string? = nil
	local firstUserMessage: string? = nil
	local directory: string? = nil
	local branch: string? = nil
	local updatedAt = 0
	local id = tostring(filepath):match("([^/]+)%.jsonl$") or tostring(filepath)

	for line in (contents :: string):gmatch("[^\r\n]+") do
		local decodeOk, decoded = pcall(json.deserialize, line)
		local object = if decodeOk then json.asObject(decoded) else nil
		if not object then
			continue
		end
		if object.type == "ai-title" and type(object.aiTitle) == "string" then
			title = cleanTitle(object.aiTitle)
		end
		if type(object.cwd) == "string" then
			directory = object.cwd
		end
		if type(object.gitBranch) == "string" then
			branch = object.gitBranch
		end
		if type(object.timestamp) == "string" then
			updatedAt = parseIsoTimestamp(object.timestamp) or updatedAt
		end
		if firstUserMessage == nil and object.type == "user" then
			local message = json.asObject(object.message)
			local text = if message then textFromValue(message.content) else nil
			if text then
				firstUserMessage = cleanTitle(text)
			end
		end
	end
	if updatedAt == 0 then
		local metadataOk, metadata = pcall(fs.metadata, filepath)
		if metadataOk then
			updatedAt = math.floor(metadata.modified:toSeconds())
		end
	end
	return {
		agent = "claude" :: "claude",
		id = id,
		title = title or firstUserMessage,
		directory = directory,
		branchAtSessionTime = branch,
		updatedAt = updatedAt,
		needsAttention = false,
		filesChanged = nil,
		messages = messagesFactory(filepath),
	}
end

function Claude.new(options: Options?): types.Provider
	local resolved: Options = options or {}
	local home = resolved.homeDirectory or process.homedir()
	local projectsPath = resolved.projectsPath or path.join(home, ".claude", "projects")
	return {
		name = "claude",
		sessions = function()
			if not fs.exists(projectsPath) then
				return {}
			end
			local projectsOk, projects = pcall(fs.listDirectory, projectsPath)
			if not projectsOk then
				return {}
			end
			local sessions: { types.Session } = {}
			for _, project in projects :: { fs.DirectoryEntry } do
				if project.type ~= "dir" then
					continue
				end
				local directory = path.join(projectsPath, project.name)
				local filesOk, files = pcall(fs.listDirectory, directory)
				if not filesOk then
					continue
				end
				for _, entry in files :: { fs.DirectoryEntry } do
					if entry.type == "file" and entry.name:match("%.jsonl$") then
						local session = parseSession(path.join(directory, entry.name))
						if session then
							table.insert(sessions, session)
						end
					end
				end
			end
			return sessions
		end,
	}
end

return table.freeze(Claude)
