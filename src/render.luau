local snapshot = require("@root/core/snapshot")
local types = require("@root/types")

export type RecentItem = {
	session: types.Session,
	worktree: types.Worktree?,
	pullRequest: types.PullRequest?,
}

local function label(item: RecentItem): string
	local session = item.session
	local worktree = item.worktree
	local title = session.title or "Untitled session"
	local directory = if worktree then tostring(worktree.path) else session.directory or "unknown workspace"
	local branch = if worktree and worktree.branch
		then worktree.branch
		else session.branchAtSessionTime or "unknown branch"
	local repository = if worktree and worktree.repository then worktree.repository else "-"
	local pullRequest = if item.pullRequest then `#{item.pullRequest.number}` else "-"
	local attention = if session.needsAttention then " !" else ""
	return `[{session.agent}]{attention} {title}\n    {repository} · {branch} · PR {pullRequest}\n    {directory}`
end

local function tildePath(value: string, homeDirectory: string?): string
	if homeDirectory and homeDirectory ~= "" and value:sub(1, #homeDirectory) == homeDirectory then
		return "~" .. value:sub(#homeDirectory + 1)
	end
	return value
end

local function pullRequestSummary(pullRequest: types.PullRequest): string
	local state = if pullRequest.draft then "draft" else (pullRequest.state or ""):lower()
	local title = if pullRequest.title then ` {pullRequest.title}` else ""
	local suffix = if state ~= "" then ` ({state})` else ""
	return `#{pullRequest.number}{title}{suffix}`
end

local function entryLabel(entry: snapshot.Entry, homeDirectory: string?): string
	local worktree = entry.worktree
	local branch = worktree.branch or "detached"
	local pullRequest = if entry.pullRequest then pullRequestSummary(entry.pullRequest) else "no PR"
	return `{snapshot.repositoryName(worktree)} · {branch} · {pullRequest}\n    {tildePath(
		tostring(worktree.path),
		homeDirectory
	)}`
end

local function pullRequestLabel(pullRequest: types.PullRequest): string
	return `{pullRequest.repository} · {pullRequestSummary(pullRequest)}\n    {pullRequest.url}`
end

local function numberedWith<T>(items: { T }, format: (T) -> string): string
	local lines: { string } = {}
	for index, item in items do
		table.insert(lines, `{index}. {format(item)}`)
	end
	return table.concat(lines, "\n")
end

local function numbered(items: { RecentItem }): string
	return numberedWith(items, label)
end

local function chooseWith<T>(items: { T }, format: (T) -> string, input: () -> string?, write: (string) -> ()): T?
	if #items == 0 then
		return nil
	end
	if #items == 1 then
		return items[1]
	end
	write(numberedWith(items, format))
	write("Choose a number:")
	local selection = tonumber(input())
	if selection == nil or selection % 1 ~= 0 or items[selection] == nil then
		error("selection must be one of the listed numbers")
	end
	return items[selection]
end

local function choose(items: { RecentItem }, input: () -> string?, write: (string) -> ()): RecentItem?
	return chooseWith(items, label, input, write)
end

return table.freeze({
	choose = choose,
	chooseWith = chooseWith,
	entryLabel = entryLabel,
	label = label,
	numbered = numbered,
	numberedWith = numberedWith,
	pullRequestLabel = pullRequestLabel,
})
