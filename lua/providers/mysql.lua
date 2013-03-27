--[[ UPGRADE
INSERT INTO
    `pointshop_data` (`uniqueid`,`points`,`items`)
SELECT
	DISTINCT `t1`.`uniqueid`,`t1`.`points`,IF(`t2`.`items` IS NULL,'[]',`t2`.`items`)
FROM
	`pointshop_points` as `t1`
LEFT JOIN
	`pointshop_items` as `t2` on `t1`.uniqueid = `t2`.uniqueid;
UPDATE `pointshop_data` SET `items` = '{}' WHERE `items` = '[]';
]]

require('mysqloo')
local loaded = {}
local db_obj = nil

local Player = FindMetaTable('Player')

-- Prevent load form Fallback
local oldPS_PlayerSpawn = Player.PS_PlayerSpawn
function Player:PS_PlayerSpawn() 
--	print('Player:PS_PlayerSpawn - block')
--	print(os.time())
end

local PS_PlayerSpawn = {}

-- hook from addon mysql
hook.Add('mysql_connect','pointshop_mysql',function(bdb)
	db_obj = bdb
	MsgN('PointShop MySQL: Connected!')
	
	
	-- set mysql provider
	function PROVIDER:GetData(ply, callback)
		local q = db_obj:query("SELECT * FROM `pointshop_data` WHERE uniqueid = '" .. ply:UniqueID() .. "'")
		
		function q:onSuccess(data)
			if #data > 0 then
				local row = data[1]
			 
				local points = row.points or 0
				local items = util.JSONToTable(row.items or '{}')
	 
				callback(points, items)
			else
				callback(0, {})
			end
			loaded[ply:UserID()] = true
			-- Allow hook for addons
			timer.Simple(1, function()
				hook.Call('ps_mysql_ready',nil,ply)
			end)
		end
		
		function q:onError(err, sql)
			if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
				db_obj:connect()
				db_obj:wait()
				if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
					ErrorNoHalt("Re-connection to database server failed.")
					
					-- keep original data
					if IsValid(ply) then
						loaded[ply:UserID()] = false
					end
					callback(0, {})
					
					return
				end
			end
			MsgN('PointShop MySQL: Query Failed: ' .. err .. ' (' .. sql .. ')')
			q:start()
		end
		 
		q:start()
	end
	
	function PROVIDER:SetData(ply, points, items)
		-- Before loaded: Readonly (Protect reset point)
		if not loaded[ply:UserID()] then return false end -- self:GetFallback():SetData(ply, points, items)  throw null - comment it
		local q = db_obj:query("INSERT INTO `pointshop_data` (uniqueid, points, items) VALUES ('" .. ply:UniqueID() .. "', '" .. (points or 0) .. "', '" .. util.TableToJSON(items or {}) .. "') ON DUPLICATE KEY UPDATE points = VALUES(points), items = VALUES(items)")
		
		function q:onError(err, sql)
			if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
				db_obj:connect()
				db_obj:wait()
				if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
					ErrorNoHalt("Re-connection to database server failed.")
					return
				end
			end
			MsgN('PointShop MySQL: Query Failed: ' .. err .. ' (' .. sql .. ')')
			q:start()
		end
		
		q:start()
	end
	
	for k, v in pairs(player.GetAll()) do
		v:PS_LoadData()
		v:PS_SendClientsideModels()
	end
	
	function Player:PS_PlayerSpawn()
		-- prevent spam (trail bug)
		if PS_PlayerSpawn[self:UserID()] and PS_PlayerSpawn[self:UserID()] == os.time() then
			return
		end
		PS_PlayerSpawn[self:UserID()] = os.time()
		timer.Simple(1, function()
			oldPS_PlayerSpawn(self)
		end)
	end
	--Player.PS_PlayerSpawn = oldPS_PlayerSpawn
	
	-- Auto equip now! (slow mysql fix)
	for k, v in pairs(player.GetAll()) do
		if v:Alive() and not PS_PlayerSpawn[v:UserID()] then
			v:PS_PlayerSpawn()
		end
	end
end)

PROVIDER.Fallback = 'pdata'

function PROVIDER:GetData(ply, callback)
	self:GetFallback():GetData(ply, callback)
end
function PROVIDER:SetData(ply, points, items)
	self:GetFallback():SetData(ply, points, items)
end