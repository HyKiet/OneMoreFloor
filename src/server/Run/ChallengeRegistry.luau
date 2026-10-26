-- Loads challenge templates and picks one per floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Challenges = script.Parent.Parent:WaitForChild("Challenges", 5) or Instance.new("Folder")

local ChallengeRegistry = {}

local templates = {}
local byId = {}

local REQUIRED = { "Id", "Name", "Build", "Start" }

local function load()
	for _, module in Challenges:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, template = pcall(require, module)
			if not ok then
				warn(`[Challenges] {module.Name} failed to load: {template}`)
				continue
			end
			local valid = typeof(template) == "table"
			for _, key in REQUIRED do
				valid = valid and template[key] ~= nil
			end
			if not valid then
				warn(`[Challenges] {module.Name} is missing required fields`)
				continue
			end
			template.MinFloor = template.MinFloor or 1
			template.MinPlayers = template.MinPlayers or 1
			template.Weight = template.Weight or 1
			template.Zone = template.Zone or 1
			table.insert(templates, template)
			byId[template.Id] = template
		end
	end
	table.sort(templates, function(a, b)
		return a.Id < b.Id -- stable order so seeded (Daily) picks are deterministic
	end)
end

function ChallengeRegistry.Get(id: string)
	return byId[id]
end

function ChallengeRegistry.All()
	return templates
end

-- Picks a template for `floor`. `seen` holds every id this run has played; `recent` the last few, newest first.
-- Boss floors always pick a BossOnly template when one is eligible.
-- Normal floors: an unseen floor from this zone (Config.ZoneFor), else an unseen one from the nearest zone,
-- so nothing repeats until the run has played them all; after that, anything from this zone or shallower
-- that is not recent.
-- Studio only: set workspace attribute OMF_ForceChallenge = "<Id>" to force a template (for testing).
function ChallengeRegistry.Pick(rng: Random, floor: number, isBoss: boolean, aliveCount: number, seen: { [string]: boolean }, recent: { string })
	if RunService:IsStudio() then
		local forced = workspace:GetAttribute("OMF_ForceChallenge")
		if typeof(forced) == "string" and byId[forced] then
			return byId[forced]
		end
	end
	local candidates = {}
	local total = 0
	local function consider(template, weight)
		table.insert(candidates, { Template = template, Weight = weight })
		total += weight
	end
	local function eligible(template): boolean
		return floor >= template.MinFloor and aliveCount >= template.MinPlayers
	end

	if isBoss then
		-- unseen bosses first, then one not played recently (so bosses alternate), then any
		for pass = 1, 3 do
			for _, template in templates do
				local fresh = if pass == 1 then not seen[template.Id] elseif pass == 2 then not table.find(recent, template.Id) else true
				if template.BossOnly and eligible(template) and fresh then
					consider(template, template.Weight)
				end
			end
			if #candidates > 0 then
				break
			end
		end
	end

	if #candidates == 0 then
		local zone = Config.ZoneFor(floor)
		local bestGap = math.huge
		for _, template in templates do
			if not template.BossOnly and eligible(template) and not seen[template.Id] then
				-- deeper zones break ties so an exhausted zone previews the next one
				local gap = math.abs((template.Zone or 1) - zone) * 2 + (if (template.Zone or 1) < zone then 1 else 0)
				bestGap = math.min(bestGap, gap)
			end
		end
		for _, template in templates do
			if not template.BossOnly and eligible(template) and not seen[template.Id] then
				local gap = math.abs((template.Zone or 1) - zone) * 2 + (if (template.Zone or 1) < zone then 1 else 0)
				if gap == bestGap then
					consider(template, template.Weight)
				end
			end
		end
		if #candidates == 0 then
			-- everything seen: replay this zone and shallower ones, skipping the last few
			for _, template in templates do
				if not template.BossOnly and eligible(template) and (template.Zone or 1) <= zone and not table.find(recent, template.Id) then
					consider(template, template.Weight)
				end
			end
		end
	end
	if #candidates == 0 then
		-- ignore floor gates rather than fail
		for _, template in templates do
			if not template.BossOnly and aliveCount >= template.MinPlayers then
				consider(template, 1)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	for _, c in candidates do
		pick -= c.Weight
		if pick <= 0 then
			return c.Template
		end
	end
	return candidates[#candidates].Template
end

load()

return ChallengeRegistry
