--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Schematics = require(script.Schematics)

type Joint = Schematics.Joint
type RigSchematic = Schematics.RigSchematic
type RigTypes = Schematics.RigTypes

local Networking = require(game.ReplicatedFirst.Shared.Networking)


local function createJointInstance(rig: Model, joint: Joint, animationConstraint: AnimationConstraint): Constraint
	local instance: Constraint = Instance.new(joint.JointType)
	instance.Attachment0 = animationConstraint.Attachment0
	instance.Attachment1 = animationConstraint.Attachment1
	instance.Name = "RagdollJoint"
	local properties = joint.Properties or {}
	for name, value in properties do
		if not (instance:: any)[name] then continue end
		(instance:: any)[name] = value
	end
	instance.Parent = animationConstraint.Parent
	return instance
end

local function createColliderInstance(rig: Model, part: BasePart, size: Vector3): BasePart
	local instance = Instance.new("Part")
	instance.Name = "RagdollCollider"
	instance.Size = size
	instance.Transparency = 1
	instance.CanCollide = false
	instance.Massless = true
	instance.CFrame = part.CFrame
	instance.CanQuery = false
	instance.CanTouch = false
	instance.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = instance
	weld.Parent = instance
	instance.Parent = part
	return instance
end

local function findJointInstance(rig: Model, animationConstraint: AnimationConstraint): JointInstance?
	if not animationConstraint.Parent then return nil end
	local joint = animationConstraint.Parent:FindFirstChild("RagdollJoint"):: JointInstance?
	return joint
end

local function findColliderInstance(rig: Model, part: BasePart): BasePart?
	local collider = part:FindFirstChild("RagdollCollider"):: BasePart
	return collider
end

local RagdollModule = {}

function RagdollModule.ragdoll(rig: Model, rigType: RigTypes?)
	if rig:GetAttribute("Ragdolled") then return end
	rig:SetAttribute("Ragdolled", true)
	
	local humanoid = rig:WaitForChild("Humanoid"):: Humanoid
	local humanoidRootPart = rig:WaitForChild("HumanoidRootPart"):: BasePart
	
	local rigType = (rigType ~= "AUTO" and rigType) or humanoid.RigType.Name
	
	local rigSchematic: RigSchematic = Schematics[rigType or "Auto"]
	local jointDatas = rigSchematic.Joints
	local colliderSizes = rigSchematic.Colliders
	
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			local jointData = jointDatas[descendant.Name] 
			if not jointData then continue end
			local jointInstance = findJointInstance(rig, descendant) or createJointInstance(rig, jointData, descendant)
			descendant.Enabled = false
			jointInstance.Enabled = true
		end
		
		if descendant:IsA("BasePart") then
			local colliderSize = colliderSizes[descendant.Name]
			if not colliderSize then continue end			
			local colliderInstance = findColliderInstance(rig, descendant) or createColliderInstance(rig, descendant, colliderSize)
			descendant:SetAttribute("BeforeRagdollCanCollide", descendant.CanCollide)
			descendant.CanCollide = false
			colliderInstance.CanCollide = true
		end
	end
	
	if humanoid.Health <= 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
		return
	end
	
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	rig:SetAttribute("BeforeRagdollEvalutateStateMachine", humanoid.EvaluateStateMachine)
	humanoid.EvaluateStateMachine = false
	
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	
	local player = Players:GetPlayerFromCharacter(rig)
	if player then
		Networking.packets.Ragdoll.sendTo(true, player)
	end
end

function RagdollModule.unragdoll(rig: Model)
	if not rig:GetAttribute("Ragdolled") then return end
	rig:SetAttribute("Ragdolled", false)
	
	local humanoid = rig:WaitForChild("Humanoid"):: Humanoid
	local humanoidRootPart = rig:WaitForChild("HumanoidRootPart"):: BasePart
	
	if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then return end
	
	humanoid.EvaluateStateMachine = rig:GetAttribute("BeforeRagdollEvalutateStateMachine")
	
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			local jointInstance = findJointInstance(rig, descendant)
			if jointInstance then
				jointInstance.Enabled = false
			end
			descendant.Enabled = true
		end
		if descendant:IsA("BasePart") then	
			local colliderInstance = findColliderInstance(rig, descendant)
			descendant.CanCollide = descendant:GetAttribute("BeforeRagdollCanCollide") or false
			if colliderInstance then
				colliderInstance.CanCollide = true
			end
		end
	end	
	
	humanoid:ChangeState(Enum.HumanoidStateType.PlatformStanding)
	
	local player = Players:GetPlayerFromCharacter(rig)
	if player then
		Networking.packets.Ragdoll.sendTo(false, player)
	end
	
	task.wait(0.1)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
end

function RagdollModule.ragdollFor(rig: Model, duration: number)
	if rig:GetAttribute("Ragdolled") then
		return
	end	
	RagdollModule.ragdoll(rig)
	task.delay(duration, function()
		if rig.Parent then
			RagdollModule.unragdoll(rig)
		end		
	end)
end

if RunService:IsClient() then
	local LocalPlayer = Players.LocalPlayer or error("No local player")
	
	local ragdolled = false
	
	Networking.packets.Ragdoll.listen(function(state)
		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		if state == true then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			task.wait()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		end
		ragdolled = state
	end)
	
	RunService.Heartbeat:Connect(function()
		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		
		if humanoid.Health <= 0 and ragdolled then
			Networking.packets.RagdollDeath.send()
			humanoid:ChangeState(Enum.HumanoidStateType.Dead)
		end
	end)
else
	Networking.packets.RagdollDeath.listen(function(_, player)
		assert(player, "Player is nil")
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	end)
end

return RagdollModule
