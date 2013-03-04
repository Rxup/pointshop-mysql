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
local shouldmysql = false
local loaded = false
local db_obj = nil

local Player = FindMetaTable('Player')

-- Prevent load form Fallback
function Player:PS_PlayerSpawn() 

end

-- hook from addon mysql
hook.Add('mysql_connect','pointshop_mysql',function(bdb)
	db_obj = bdb
	MsgN('PointShop MySQL: Connected!')
	
	
	-- set mysql provider
	function PROVIDER:GetData(ply, callback)
		if not shouldmysql then self:GetFallback():GetData(ply, callback) end
		
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
		end
		
		function q:onError(err, sql)
			if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
				db_obj:connect()
				db_obj:wait()
				if db_obj:status() ~= mysqloo.DATABASE_CONNECTED then
					ErrorNoHalt("Re-connection to database server failed.")
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
		if not shouldmysql and not loaded then self:GetFallback():SetData(ply, points, items) end
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
	shouldmysql = true -- Load data
	for k, v in pairs(player.GetAll()) do
		v:PS_LoadData()
		v:PS_SendClientsideModels()
	end

	timer.Simple(1, function()
		function Player:PS_PlayerSpawn() -- Allow auto equip
			if not self:PS_CanPerformAction() then return end
		
			-- TTT ( and others ) Fix
			if TEAM_SPECTATOR != nil and self:Team() == TEAM_SPECTATOR then return end
			if TEAM_SPEC != nil and self:Team() == TEAM_SPEC then return end
		
			timer.Simple(1, function()
				for item_id, item in pairs(self.PS_Items) do
					local ITEM = PS.Items[item_id]
					if item.Equipped and self:Team() == (ITEM.Team or TEAM_HUMAN) then
						ITEM:OnEquip(self, item.Modifiers)
					end
				end
			end)
		end
		-- Auto equip now! (slow mysql fix)
		for k, v in pairs(player.GetAll()) do
			if v:Alive() then
				v:PS_PlayerSpawn()
			end
		end
	
		-- Allow write to mysql
		loaded = true
	end)
end)

PROVIDER.Fallback = 'pdata'

function PROVIDER:GetData(ply, callback)
	self:GetFallback():GetData(ply, callback)
end
function PROVIDER:SetData(ply, points, items)
	self:GetFallback():SetData(ply, points, items)
end