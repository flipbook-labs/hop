local types = require("@root/types")

type Ranked = {
	worktree: types.Worktree,
	score: number,
}

local function basename(value: string): string
	return value:gsub("/+$", ""):match("([^/]+)$") or value
end

local function matchWorktrees(worktrees: { types.Worktree }, query: string): { types.Worktree }
	local normalized = query:lower()
	local exactBranches: { types.Worktree } = {}
	local ranked: { Ranked } = {}

	for _, worktree in worktrees do
		if worktree.branch and worktree.branch:lower() == normalized then
			table.insert(exactBranches, worktree)
			continue
		end

		local score = 0
		local branch = if worktree.branch then worktree.branch:lower() else ""
		local leaf = basename(tostring(worktree.path)):lower()
		local repository = if worktree.repository then worktree.repository:lower() else ""
		if branch:find(normalized, 1, true) then
			score = 300
		elseif leaf:find(normalized, 1, true) then
			score = if leaf == normalized then 250 else 200
		elseif repository:find(normalized, 1, true) then
			score = if repository == normalized then 150 else 100
		end
		if score > 0 then
			table.insert(ranked, { worktree = worktree, score = score })
		end
	end

	if #exactBranches > 0 then
		table.sort(exactBranches, function(left, right)
			return tostring(left.path) < tostring(right.path)
		end)
		return exactBranches
	end
	table.sort(ranked, function(left: Ranked, right: Ranked)
		if left.score == right.score then
			return tostring(left.worktree.path) < tostring(right.worktree.path)
		end
		return left.score > right.score
	end)
	local result: { types.Worktree } = {}
	for _, candidate in ranked do
		table.insert(result, candidate.worktree)
	end
	return result
end

return matchWorktrees
