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

local function numbered(items: { RecentItem }): string
	local lines: { string } = {}
	for index, item in items do
		table.insert(lines, `{index}. {label(item)}`)
	end
	return table.concat(lines, "\n")
end

local function choose(items: { RecentItem }, input: () -> string?, write: (string) -> ()): RecentItem?
	if #items == 0 then
		return nil
	end
	if #items == 1 then
		return items[1]
	end
	write(numbered(items))
	write("Choose a number:")
	local selection = tonumber(input())
	if selection == nil or selection % 1 ~= 0 or items[selection] == nil then
		error("selection must be one of the listed numbers")
	end
	return items[selection]
end

return table.freeze({
	choose = choose,
	label = label,
	numbered = numbered,
})
