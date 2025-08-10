--[[
ErnOneStick for OpenMW.
Copyright (C) 2025 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

local util = require('openmw.util')

TargetCollection = {}

function TargetCollection:new(gameObjects)
    local collection = {
        gameObjects = gameObjects,
        sorted = false,
        currentIdx = 0
    }
    setmetatable(collection, self)
    self.__index = self
    return collection
end

function TargetCollection:sort(player)
    -- Objects we are facing are weighted highly.
    -- Objects that are closer are weighted highly.
    if self.sorted then
        return
    end
    -- could maybe use camera.viewportToWorldVector(0.5, 0.5) instead to get facing.
    local facing = player.rotation:apply(util.vector3(0.0, 1.0, 0.0)):normalize()
    -- sort by most weight first
    local weight = {}
    for i, e in ipairs(self.gameObject) do
        local relativePos = (player.position - e.position)
        -- dot product returns 0 if at 90*, 1 if codirectional, -1 if opposite.
        local faceWeight = 100 * (4 + facing:dot(relativePos))
        weight[e.id] = faceWeight / (relativePos:length())
    end
    table.sort(self.gameObject, function(a, b) return weight[a.id] < weight[b.id] end)
    self.sorted = true
end

function TargetCollection:next()
    self:sort()
    if #(self.gameObjects) == 0 then
        return nil
    end
    self.currentIdx = self.currentIdx + 1
    if self.currentIdx > #(self.gameObjects) then
        self.currentIdx = 1
    end
end

function TargetCollection:previous()
    self:sort()
    if #(self.gameObjects) == 0 then
        return nil
    end
    self.currentIdx = self.currentIdx - 1
    if self.currentIdx <= 0 then
        self.currentIdx = #(self.gameObjects)
    end
end

return {
    TargetCollection = TargetCollection
}
