pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
platform channels:
	1:	map
	2:	blocks

hurt channels:
	1:	slime
	2:	tomato
]]

-- convenient no-op function that does nothing
function noop() end

local min_world_x=4
local max_world_x=868

local entities
local slime
local buttons={}
local button_presses={}
local landing_sprites={0,1,1,1,2,2,3,4,4,4,5,5,5,6,6,6,7}
local camera_x=4
local num_tomatoes=0
local tomatoes_collected=0
local timer=0
local frames=0

-- a dictionary of entity classes that can be spawned via spawn_entity
-- todo: tap up to stick into the underside of a short ceiling
-- todo: die if left+right or up+down collisions in a single turn
local entity_classes={
	slime={
		width=10,
		height=8,
		prev_vx=0,
		prev_vy=0,
		hit_channel=2, -- tomato
		hurt_channel=1, -- slime
		collision_channel=1+2, -- map + blocks
		collision_indent=3,
		input_buffer_amount=3,
		jump_dir=nil,
		stuck_dir=nil,
		stuck_platform=nil,
		has_double_jump=false,
		jumpable_surface=nil,
		flag=nil,
		jumpable_surface_dir=nil,
		jumpable_surface_buffer_frames=0,
		jump_disabled_frames=0,
		stick_disabled_frames=0,
		slide_frames=0,
		has_slid_this_frame=false,
		momentum_level=0,
		momentum_dir=nil,
		momentum_reset_frames=0,
		is_bouncing=false,
		bounce_energy=0,
		bounces=0,
		gravity=0.203,
		is_airborne=true,
		is_facing_left=false,
		landing_animation_frames=0,
		-- sliding_platform=nil,
		init=function(self)
			-- initialize object to keep track of inputs
			self.buffered_presses={}
			local i
			for i=0,5 do
				self.buffered_presses[i]=0
			end
		end,
		update=function(self)
			if self.frames_alive<10 then
				return
			end
			self.prev_vx,self.prev_vy=self.vx,self.vy
			-- stop bouncing if down is no longer held
			if self.is_bouncing and not buttons[3] and self.bounces>0 then
				self.is_bouncing=false
			end
			if not self.stuck_platform and decrement_counter_prop(self,"jumpable_surface_buffer_frames") then
				self.jumpable_surface=nil
				self.jumpable_surface_dir=nil
			end
			increment_counter_prop(self,"landing_animation_frames")
			decrement_counter_prop(self,"jump_disabled_frames")
			decrement_counter_prop(self,"stick_disabled_frames")
			-- maintain momentum so long as the slime doesn't stick to anything for too long
			if not self.stuck_platform then
				self.momentum_reset_frames=7
			elseif decrement_counter_prop(self,"momentum_reset_frames") then
				self.momentum_level=0
				self.momentum_dir=nil
			end
			-- keep track of inputs
			local i
			for i=0,5 do
				self.buffered_presses[i]=decrement_counter(self.buffered_presses[i])
				if button_presses[i] then
					self.buffered_presses[i]=self.input_buffer_amount
				end
			end
			-- gravity accelerates the slime downwards
			if not self.stuck_platform then
				self.vy+=self.gravity
			end
			-- the slime slows to a stop when sliding
			if self.slide_frames>6 and self.has_slid_this_frame then
				local base_vx=self.jumpable_surface and self.jumpable_surface.vx or 0
				self.vx=base_vx+0.92*(self.vx-base_vx)
			end
			-- check for bounce
			if false and not self.is_bouncing and self.vy>-0.5 and not self.jumpable_surface and not self.stuck_platform and button_presses[3] then
				self.is_bouncing=true
				self.has_double_jump=false
				self.vy=max(self.vy,3)
				self.bounces=0
				self:recalc_bounce_energy()
			end
			if self.stuck_platform then
				self.vx=self.stuck_platform.vx
				self.vy=self.stuck_platform.vy
			end
			-- check for jumps
			if not self.is_bouncing and self.jump_disabled_frames<=0 and (self.jumpable_surface_buffer_frames>0 or self.has_double_jump) then
				-- slide down right surface
				-- if buttons[1] and self.stuck_dir=="right" then
				-- 	self.buffered_presses[1]=0
				-- 	self.jump_dir="right"
				-- 	self:unstick()
				-- -- slide down left surface
				-- elseif buttons[0] and self.stuck_dir=="left" then
				-- 	self.buffered_presses[0]=0
				-- 	self.jump_dir="left"
				-- 	self:unstick()
				-- let go of top surface
				if self.buffered_presses[2]>0 and self.stuck_dir=="up" then
					self.buffered_presses[2]=0
					self.jump_dir="up"
					self:unstick()
				-- jump right
				elseif self.buffered_presses[1]>0 and self.stuck_dir!="right" then
					self.buffered_presses[1]=0
					self:jump("right")
				-- jump left
				elseif self.buffered_presses[0]>0 and self.stuck_dir!="left" then
					self.buffered_presses[0]=0
					self:jump("left")
				-- jump up
				elseif self.buffered_presses[2]>0 then
					self.buffered_presses[2]=0
					self:jump("up")
				end
			end
			-- clamp velocity
			self.velocity_x=mid(-3.5,self.velocity_x,3.5)
			self.velocity_y=mid(-3.5,self.velocity_y,3.5)
			-- apply the velocity
			self.slide_platform=nil
			self.collision_padding=ternary(self.stick_disabled_frames>0,0,1.5)
			self.has_slid_this_frame=false
			self:apply_velocity(self.is_bouncing)
			-- the slime might get unstuck from the platform
			if self.stuck_platform and not self:check_for_collision(self.stuck_platform) then
				self:unstick()
			end
			-- keep track of slide time
			if self.has_slid_this_frame then
				self.is_airborne=false
				increment_counter_prop(self,"slide_frames")
			elseif self.stuck_platform then
				self.is_airborne=false
			else
				self.is_airborne=true
			end
			-- the slime sticks if it slows to a stop
			if not self.stuck_platform and self.jumpable_surface_dir=="down" and abs(self.vx-self.jumpable_surface.vx)<0.1 then
				self:stick(self.jumpable_surface,self.jumpable_surface_dir)
			end
			-- keep the slime in bounds
			if self.x<min_world_x then
				self.x=min_world_x
			end
			if self.y<0 then
				self.y=0
				if self.vy<0 then
					self.vy=0
				end
			end
			-- self.x=mid(min_world_x,self.x,max_world_x-self.width)
			-- die if fallen off the bottom edge of the map
			if self.y>128 then
				self:die()
			end
		end,
		draw=function(self)
			if self.frames_alive<10 then
				return
			end
			-- self:draw_outline(9)
			-- pset(self.x+self.width/2-0.5,self.y+self.height/2-0.5,9)
			-- pset(self.x+self.width/2+0.5,self.y+self.height/2-0.5,9)
			local sprite
			local landing_sprite_offset=landing_sprites[min(self.landing_animation_frames,#landing_sprites)]
			if self.is_airborne then
				if self.vx==mid(-1,self.vx,1) then
					sprite=mid(16,flr(self.vy/1.5+18.5),20)
				else
					sprite=mid(24,flr(self.vy+27.5),30)
				end
			elseif self.stuck_dir=="up" then
				sprite=48+landing_sprite_offset
			elseif self.stuck_dir=="left" or self.stuck_dir=="right" then
				sprite=40+landing_sprite_offset
			else
				sprite=32+landing_sprite_offset
			end
			local shadow_color=ternary(tomatoes_collected>=num_tomatoes,2,3)
			local base_color=ternary(tomatoes_collected>=num_tomatoes,8,11)
			local highlight_color=ternary(tomatoes_collected>=num_tomatoes,14,7)
			pal(3,shadow_color)
			pal(11,base_color)
			pal(7,highlight_color)
			if self.is_facing_left then
				pal(2,shadow_color) -- purple -> dark green
				pal(14,shadow_color) -- pink -> dark green
				pal(6,base_color) -- grey -> light green
				pal(4,base_color) -- brown -> light green
				pal(9,highlight_color) -- orange -> white
				pal(15,highlight_color) -- peach -> white
			else
				pal(2,base_color) -- purple -> light green
				pal(14,highlight_color) -- pink -> white
				pal(6,highlight_color) -- grey -> white
				pal(4,shadow_color) -- brown -> dark green
				pal(9,shadow_color) -- orange -> dark green
				pal(15,base_color) -- peach -> light green
			end
			sspr(16*(sprite%8),40+11*flr(sprite/8),16,11,self.x-ternary(self.is_facing_left,3.5,1.5),self.y-1.5,16,11,self.is_facing_left)
		end,
		on_collide=function(self,dir,other)
			local vx=self.vx
			self:handle_collision(dir,other)
			-- bounce off of the platform
			if self.is_bouncing then
				self:bounce(other,dir,vx)
			-- slide across the platform
			-- elseif self.stick_disabled_frames>0 or (self.jump_dir=="left" and buttons[0]) or (self.jump_dir=="right" and buttons[1]) or (self.jump_dir=="up" and buttons[2] and dir!="up") then
			-- 	self:slide(other,dir)
			-- stick to the platform
			elseif not self.stuck_platform or (dir=="down" and self.stuck_dir!="down") then
				self:stick(other,dir)
			end
		end,
		bounce=function(self,platform,dir,vx)
			local vy=min(3.25,sqrt(2*(self.bounce_energy-self.gravity*(128-self.y))))
			if dir=="down" then
				increment_counter_prop(self,"bounces")
				self.jump_disabled_frames=9
				self.stick_disabled_frames=3
				self.has_double_jump=true
				self.vy=platform.vy-vy
				self:recalc_bounce_energy()
			elseif dir=="up" then
				self.vy=platform.vy+vy
				self:recalc_bounce_energy()
			elseif dir=="left" then
				self.vx=max(0,platform.vx-(vx-platform.vx))
				self.is_facing_left=false
			elseif dir=="right" then
				self.vx=min(0,platform.vx-(vx-platform.vx))
				self.is_facing_left=true
			end
		end,
		recalc_bounce_energy=function(self)
			self.bounce_energy=self.vy*self.vy/2+self.gravity*(128-self.y)
		end,
		slide=function(self,platform,dir)
			if dir=="down" then
				self.has_double_jump=true
				self:set_jumpable_surface(platform,dir)
				self.has_slid_this_frame=true
			end
		end,
		stick=function(self,platform,dir)
			if dir=="left" then
				self.is_facing_left=false
			elseif dir=="right" then
				self.is_facing_left=true
			end
			if abs(self.prev_vx)>1.75 or abs(self.prev_vy)>1.75 then
				self.landing_animation_frames=1
				sfx(1,1)
			elseif abs(self.prev_vx)>0.75 or abs(self.prev_vy)>0.75 then
				self.landing_animation_frames=9
				sfx(1,1)
			else
				self.landing_animation_frames=14
			end
			self.jump_dir=nil
			self.has_double_jump=true
			self:set_jumpable_surface(platform,dir)
			self.jump_disabled_frames=0
			self.stuck_dir=dir
			self.stuck_platform=platform
			self.vx=platform.vx
			self.vy=platform.vy
			self.slide_frames=0
		end,
		unstick=function(self)
			self.stuck_dir=nil
			self.stuck_platform=nil
			self.jumpable_surface=nil
			self.jumpable_surface_dir=nil
			self.jumpable_surface_buffer_frames=0
			self.stick_disabled_frames=2
			self.slide_frames=0
		end,
		jump=function(self,dir)
			local momentum_vx=self.momentum_level
			-- jump off of a surface
			if self.jumpable_surface_buffer_frames>0 then
				sfx(0,0)
				-- continue gaining momentum
				if dir==self.momentum_dir then
					increment_counter_prop(self,"momentum_level")
				end
				-- stick to it momentarily (in case we were sliding)
				self:stick(self.jumpable_surface,self.jumpable_surface_dir)
				-- switch directions when jumping up off of walls
				if dir=="up" then
					if self.jumpable_surface_dir=="left" then
						increment_counter_prop(self,"momentum_level")
						self.momentum_dir="right"
					elseif self.jumpable_surface_dir=="right" then
						increment_counter_prop(self,"momentum_level")
						self.momentum_dir="left"
					end
				-- begin gaining momentum
				elseif dir!=self.momentum_dir then
					self.momentum_dir=dir
					if self.jumpable_surface_dir=="left" or self.jumpable_surface_dir=="right" then
						increment_counter_prop(self,"momentum_level")
					else
						momentum_vx=0
						self.momentum_level=1
					end
				end
			-- exhaust double jump to jump in mid-air
			else
				sfx(2,0)
				self.has_double_jump=false
				if (dir=="left" or dir=="right") and self.momentum_dir!=dir then
					self.momentum_dir=dir
					self.momentum_level=1
				end
			end
			-- set jump vars
			self.is_airborne=true
			self.jump_dir=dir
			self.jump_disabled_frames=5
			self.slide_frames=0
			-- change velocity
			if dir=="left" then
				self.vx=-2
				if self.jumpable_surface_dir=="up" then
					self.vy=0
				else
					self.vy=-2
				end
				self.is_facing_left=true
			elseif dir=="right" then
				self.vx=2
				if self.jumpable_surface_dir=="up" then
					self.vy=0
				else
					self.vy=-2
				end
				self.is_facing_left=false
			elseif dir=="up" then
				if self.stuck_dir=="left" or self.stuck_dir=="right" or abs(self.vx)>0.75 then
					self.vx=ternary(self.is_facing_left,-0.5,0.5)
				else
					self.vx=0
				end
				self.vy=-2.8
			end
			-- and the slime is no longer stuck to any platforms
			if self.jumpable_surface_buffer_frames>0 then
				self:unstick()
				self.is_airborne=true
			end
		end,
		set_jumpable_surface=function(self,platform,dir)
			if self.jumpable_surface_buffer_frames<3 or dir=="down" then
				self.jumpable_surface=platform
				self.jumpable_surface_dir=dir
				self.jumpable_surface_buffer_frames=3
			end
		end,
		on_death=function(self)
			if self.flag then
				slime=spawn_entity("slime",self.flag.x+7,self.flag.y-16)
				slime.flag=self.flag
				sfx(5,3)
			end
		end
	},
	block={
		platform_channel=2, -- blocks
		draw=function(self)
			self:draw_outline(0)
		end
	},
	tomato={
		width=6,
		height=5,
		hurt_channel=2, -- tomato
		init=function(self)
			num_tomatoes+=1
		end,
		draw=function(self)
			local f=self.frames_alive%24
			local sprite
			if f<5 then
				sprite=124
			elseif f<12 then
				sprite=125
			elseif f<17 then
				sprite=126
			else
				sprite=127
			end
			spr(sprite,self.x-0.5,self.y-1.5)
		end,
		on_hurt=function(self)
			sfx(4,2)
			self:die()
			tomatoes_collected+=1
		end
	},
	flag={
		is_activated=false,
		update=function(self)
			if not self.is_activated and slime and slime.x+slime.width>self.x then
				sfx(3,3)
				self.is_activated=true
				slime.flag=self
			end
		end,
		draw=function(self)
			-- self:draw_outline(0)
			local sprite
			local f=self.frames_alive%25
			if f<7 then
				sprite=140
			elseif f<14 then
				sprite=141
			elseif f<21 then
				sprite=142
			else
				sprite=143
			end
			pal(8,ternary(self.is_activated,9,8))
			spr(sprite,self.x+0.5,self.y+0.5)
		end
	}
}

function _init()
	entities={}
	-- spawn initial entities
	-- spawn_entity("block",5,20,{ height=60 })
	-- spawn_entity("block",119,20,{ height=60 })
	-- spawn_entity("block",1,90,{ width=126 })
	-- spawn_entity("block",30,68,{ width=60 })
	-- spawn_entity("block",64,28,{
	-- 	width=8,
	-- 	height=8,
	-- 	update=function(self)
	-- 		self.vy=ternary(self.frames_alive%224<120,0.5,-0.5)
	-- 		self:apply_velocity()
	-- 	end,
	-- 	draw=function(self)
	-- 		spr(1,self.x+0.5,self.y+0.5)
	-- 	end
	-- })
	slime=spawn_entity("slime",39,75)
	-- spawn_entity("tomato",50,60)
	-- load level
	local col
	local row
	for col=0,128 do
		for row=0,16 do
			if mget(col,row)==124 then
				spawn_entity("tomato",8*col+1,8*row+2)
			elseif mget(col,row)==140 then
				spawn_entity("flag",8*col,8*row)
			end
		end
	end
end

-- local skip_frames=0
function _update()
	if not slime or not slime.flag or slime.flag.x<800 then
		frames+=1
		if frames>=30 then
			frames=0
			timer=min(timer+1,5999)
		end
	end
	-- skip_frames+=1
	-- if skip_frames%10>0 and not btn(5) then return end
	-- keep better track of button presses
	--  (because btnp repeats presses when holding)
	local i
	for i=0,5 do
		button_presses[i]=btn(i) and not buttons[i]
		buttons[i]=btn(i)
	end
	-- update all the entities
	local entity
	for entity in all(entities) do
		increment_counter_prop(entity,"frames_alive")
		entity:update()
	end
	-- check for hits
	for i=1,#entities do
		local j
		for j=1,#entities do
			if i!=j and entities[i]:is_hitting(entities[j]) then
				entities[i]:on_hit(entities[j])
				entities[j]:on_hurt(entities[i])
			end
		end
	end
	-- remove dead entities
	for entity in all(entities) do
		if not entity.is_alive then
			del(entities,entity)
		end
	end
	-- update the camera's position
	if slime then
		-- todo figure out the slime problem
		local offset=camera_x-slime.x+42.5
		if offset<0 then
			camera_x-=offset
		end
		if offset>24 then
			camera_x-=offset-24
		end
		camera_x=mid(min_world_x,camera_x,max_world_x)
		-- local target_x=slime.x-43
		-- if camera_x<target_x then
		-- 	camera_x=target_x
		-- end
	end
end

function _draw()
	camera()
	-- clear the screen to yellow
	cls(10)
	-- draw the sky layers
	rectfill(0,0,127,6,15) -- tan
	rectfill(0,9,127,9,15) -- tan
	rectfill(0,0,127,1,7) -- white
	rectfill(0,116,127,127,9) -- orange
	rectfill(0,113,127,113,9) -- orange
	rectfill(0,124,127,124,4) -- brown
	rectfill(0,126,127,127,4) -- brown
	-- draw the map
	camera(camera_x,0)
	map(0,0,0,0,128,16,1)
	-- draw controls
	print("controls",45,53,9)
	sspr(103,39,25,17,48,60)
	-- draw ending
	print("thank you",953,52,9)
	print("for playing!",942,59,9)
	print(flr(timer/60)..":"..ternary(timer%60<10,"0","")..(timer%60),905,59)
	spr(15,964,70)
	-- draw all the entities
	local entity
	for entity in all(entities) do
		entity:draw()
		pal()
	end
	-- draw the tomato counter
	camera()
	print(tomatoes_collected,12,4,8)
	spr(159,3,2)
end

-- spawns an entity that's an instance of the given class
function spawn_entity(class_name,x,y,args)
	local class_def=entity_classes[class_name]
	-- create a default entity
	local entity={
		class_name=class_name,
		frames_alive=0,
		is_alive=true,
		x=x,
		y=y,
		vx=0,
		vy=0,
		width=8,
		height=8,
		collision_indent=2,
		collision_padding=0,
		platform_channel=0,
		collision_channel=0,
		hit_channel=0,
		hurt_channel=0,
		init=noop,
		update=function(self)
			self:apply_velocity()
		end,
		apply_velocity=function(self,stop_after_collision)
			-- move in discrete steps if we might collide with something
			if self.collision_channel>0 then
				local max_move_x=min(self.collision_indent,self.width-2*self.collision_indent)-0.1
				local max_move_y=min(self.collision_indent,self.height-2*self.collision_indent)-0.1
				local steps=max(1,ceil(max(abs(self.vx/max_move_x),abs(self.vy/max_move_y))))
				local i
				for i=1,steps do
					-- apply velocity
					self.x+=self.vx/steps
					self.y+=self.vy/steps
					-- check for collisions
					if self:check_for_collisions() and stop_after_collision then
						return
					end
				end
			-- just move all at once
			else
				self.x+=self.vx
				self.y+=self.vy
			end
		end,
		-- collision functions
		check_for_collisions=function(self)
			local found_collision=false
			-- check for collisions with other entity
			local entity
			for entity in all(entities) do
				if entity!=self then
					local collision_dir=self:check_for_collision(entity)
					if collision_dir then
						-- they are colliding!
						self:on_collide(collision_dir,entity)
						found_collision=true
					end
				end
			end
			-- check each nearby tile on the map
			local map_min_x,map_max_x=flr((self.x-1)/8),ceil((self.x+self.width+1)/8)
			local map_min_y,map_max_y=flr((self.y-1)/8),ceil((self.y+self.height+1)/8)
			local x,y
			for x=map_min_x,map_max_x do
				for y=map_min_y,map_max_y do
					local sprite=mget(x,y)
					if fget(sprite,1) then
						local tile_obj={
							x=8*x,
							y=8*y,
							width=8,
							height=8,
							vx=0,
							vy=0,
							platform_channel=1
						}
						local collision_dir=self:check_for_collision(tile_obj)
						if collision_dir then
							-- they are colliding!
							self:on_collide(collision_dir,tile_obj)
							found_collision=true
						end
					end
				end
			end
			return found_collision
		end,
		check_for_collision=function(self,other)
			if band(self.collision_channel,other.platform_channel)>0 then
				return objects_colliding(self,other)
			end
		end,
		on_collide=function(self,dir,other)
			-- just handle the collision by default
			self:handle_collision(dir,other)
		end,
		handle_collision=function(self,dir,other)
			-- reposition this entity and adjust the velocity
			if dir=="left" then
				self.x=other.x+other.width
				self.vx=max(self.vx,other.vx)
			elseif dir=="right" then
				self.x=other.x-self.width
				self.vx=min(self.vx,other.vx)
			elseif dir=="up" then
				self.y=other.y+other.height
				self.vy=max(self.vy,other.vy)
			elseif dir=="down" then
				self.y=other.y-self.height
				self.vy=min(self.vy,other.vy)
			end
		end,
		-- hit functions
		is_hitting=function(self,other)
			return band(self.hit_channel,other.hurt_channel)>0 and objects_hitting(self,other)
		end,
		on_hit=noop,
		on_hurt=noop,
		-- draw functions
		draw=noop,
		draw_outline=function(self,color)
			rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color)
		end,
		die=function(self)
			if self.is_alive then
				self.is_alive=false
				self:on_death()
			end
		end,
		on_death=noop
	}
	-- add class-specific properties
	local key,value
	for key,value in pairs(class_def) do
		entity[key]=value
	end
	-- override with passed-in arguments
	for key,value in pairs(args or {}) do
		entity[key]=value
	end
	-- add it to the list of entities
	add(entities,entity)
	-- initialize the entitiy
	entity:init()
	-- return the new entity
	return entity
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

-- check to see if obj1 is overlapping with obj2
function objects_hitting(obj1,obj2)
	return rects_overlapping(obj1.x,obj1.y,obj1.width,obj1.height,obj2.x,obj2.y,obj2.width,obj2.height)
end

-- check to see if obj1 is colliding into obj2, and if so in which direction
function objects_colliding(obj1,obj2)
	local x1,y1,w1,h1,i,p=obj1.x,obj1.y,obj1.width,obj1.height,obj1.collision_indent,obj1.collision_padding
	local x2,y2,w2,h2=obj2.x,obj2.y,obj2.width,obj2.height
	-- check hitboxes
	if rects_overlapping(x1+i,y1+h1/2,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy>=obj2.vy then
		return "down"
	elseif rects_overlapping(x1+w1/2,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx>=obj2.vx then
		return "right"
	elseif rects_overlapping(x1-p,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx<=obj2.vx then
		return "left"
	elseif rects_overlapping(x1+i,y1-p,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy<=obj2.vy then
		return "up"
	end
end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

function increment_counter(n)
	return ternary(n>32000,2000,n+1)
end

function increment_counter_prop(obj,key)
	obj[key]=increment_counter(obj[key])
end

function decrement_counter(n)
	return max(0,n-1)
end

function decrement_counter_prop(obj,key)
	local initial_value=obj[key]
	obj[key]=decrement_counter(initial_value)
	return initial_value>0 and initial_value<=1
end
__gfx__
00000000499999994999999924999999224444442222222222222222000000002222222222222222222222222222222200000000000030002222222200000000
00000000244444492444444924444449222222242222222222222222000000002222222222222222222222222222222200000000000303002222222209909900
00000000244999492449994924249949222244242222222222222222000000002222222222222222222222222222222200000000000003002222222299999090
00000000242449492424494922244949222224242222222222222222000000002222222222222222222222222222222200000bb0000000002222222299999090
0000000024244949222449492224444422222222222222222222222200600060222222222222222222222222222222220000bb00000000002222222209999900
0000000024222449222224492222224422222222222222222222222200d700d7222222222222222222222222222222220bb0bb00000000002222222200999000
0000000024444449222244492222222222222222222222222222222205d605d622222222222222222222222222222222003b3000000000002222222200090000
0000000022222224222222222222222222222222222222222222222205d605d62222222222222222222222222222222200033000000000002222222200000000
22222222000000000000000000000000000000000000000000000766222222226670000022222222222222222222222222222222222222222222222222222222
02222240222222222222222222222222222222222222222200006ddd22222222ddd6000022222222222222222222222222222222222222222222222222222222
02222440222222222222222222222222222222222222222200000055222222225500000022222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222200000000222222220000000022222222222222222222222222222222222222222222222222222222
02222240222222222222222222222222222222222222222200000766222222226670000022222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222200006ddd22222222ddd6000022222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222200000055222222225500000022222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222200000000222222220000000022222222222222222222222222222222222222222222222222222222
0022240000000000222222222222222222222222222222222222222205d605d62222222222222222222222222222222222222222222222222222222222222222
0022240000000000222222222222222222222222222222222222222205d605d62222222222222222222222222222222222222222222222222222222222222222
0022240000000000222222222222222222222222222222222222222200d700d72222222222222222222222222222222222222222222222222222222222222222
00222400000004002222222222222222222222222222222222222222006000602222222222222222222222222222222222222222222222222222222222222222
00222400000024002222222222222222222222222222222222222222000000002222222222222222222222222222222222222222222222222222222222222222
00222400002224002222222222222222222222222222222222222222000000002222222222222222222222222222222222222222222222222222222222222222
00222400002224002222222222222222222222222222222222222222000000002222222222222222222222222222222222222222222222222222222222222222
00222400002224002222222222222222222222222222222222222222000000002222222222222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222400222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222200222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222200222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222200222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00222200222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222220000000099999999900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090000000900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090009000900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090099900900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090999990900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090000000900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090000000900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222220000000090000000900000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229999999999999999999999999
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229000000090000000900000009
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229000900090000000900090009
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229009900090000000900099009
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229099900090000000900099909
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229009900090000000900099009
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229000900090000000900090009
00333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229000000090000000900000009
04fbe200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222229999999990000000999999999
49bbb6e3300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
344bbbb2233200000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000003000000300000030000
3444bbbbb22e20000000000000000000000000000000000000000000000000000000000000000000000000000000000000833300008883300088330000338800
0334444b2223300000000000000000000000000000000000000000000000000000000000000000000000000000000000088838800888838008888e8008888e80
00333333333300000000000000000000000000000000000000000000000000000000000000000000000000000000000008888e8008888e8008888e8008888e80
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008888e8008888e800888888008888880
00000033330000000000000000000000000000000000000000000000000000000000333300000000222222222222222200888800008888000088880000888800
000004bb6200000000000333300000000000000000000000000033330000000000044fb220000000222222222222222200000000000000000000000000000000
000049bbbe20000000004fbbe2000000000033333300000000049bb2200000000004fbb622000000222222222222222248800000488880004888880048000800
00009bbbb630000000049bbbbe20000000044fb6622000000049bbbe220000000003fbbbe2000000222222222222222248888000488888004888800048888800
00034bbbbb3000000004bbbbb23000000044fbbbb62200000039bbbb620000000003bbbbe2300000222222222222222248888000488008004880000048888000
00034bbbb23000000034bbbbb23000000034bbbbbb2300000034bbbb6230000000034bbbbe300000222222222222222240088800400000004000000040880000
00034bbbb23000000034bbbb223000000034bbbbbb2300000033bbbbb230000000034bbbb2300000222222222222222240000000400000004000000040000000
000344bb230000000034bbbb2300000000334bbbb223000000034bbbb2300000000034bbb2300000222222222222222240000000400000004000000040000000
000334423300000000334bb2330000000003344223300000000334bb233000000000334b23300000222222222222222220000000200000002000000020000000
00033333300000000003333330000000000033333300000000003333330000000000033333000000222222222222222220000000200000002000000020000000
00000000000000000000333300000000000000000000000000000333300000000000003333000000222222222222222222222222222222222222222200000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000033330000000002222222200000000
00000033333000000000000000000000000000000000000000000000000000000000000000000000003330000000000000444bb3000000002222222200038800
000044bbbe220000000000333330000000000033333000000000033330000000003333300000000004444333000000000049bbbb330000002222222200333880
00004fbbbbe20000000044bbbe220000000444bbbe22000000449fbbb22000000449bbb3333000000494bb6b330000000034fbbb622000002222222200838880
00039bbbbb2300000004bffbbbe200000034ffbbbbe200000349bbbb66220000049bbbbb66220000034fbbb6623000000034bbbbbe2000002222222200888880
0003bbbbb2230000003bfbbbbb230000034fbbbbbb230000034bbbbbbbe30000034bbbbbbbe20000003bbbbbb622000000034bbbb62300002222222200088800
0033bbbbb2300000003bbbbbb2230000034bbbbbbb230000034bbbbbbb2300000344bbbbbb2300000034bbbbbb22000000033bbbbb2300002222222200000000
00344bbb233000000344bbbb223000000334bbbbb23300000334bbbbbb33000000334bbbb223000000033bbbb2230000000033bbb23300002222222222222222
003444333300000003444b22330000000333333333300000003334bb233000000003333222330000000033332233000000003333333300002222222222222222
00333333000000000333333300000000003333300000000000000333300000000000003333300000000000333330000000000033333000002222222222222222
00033330000000000033300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000033300000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000033330000000000049b220000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000049bb2200000000009bb622000000000033300000000000000000000000000000033330000000
00000000033300000000000000000000000000000000000000009bbb6200000000039bbb6300000000044b6333000000000333333300000000044bbbb2200000
000000004b2e20000000000000000000000000000333000000039bbbbe30000000034bbb630000000044fbbbee20000000449fb6622000000044ffbb66220000
000003339bb2e2000000000000033330000320034bbe220000034bbbb630000000034bbb623000000039bbbbb2e200000049bbbbb62200000039bbbbbbe30000
004334bfbbb2230004332000049bb2e2004b6234fbbbe23000034bbbbb23000000034bbbb23000000034bbbbb22300000034bbbbbb2300000034bbbbbb230000
04944bbbbb222300494be2333fbbbb220349bbbbbbbb2230000344bbb2230000000334bb2233000000344bbbb223000000344bbbb223000000344bbbb2230000
033444bb222330003444bbbbbbbbb23303344bbbbb2223300003344322330000000033333333000000334442223300000033444b22330000003344bb22330000
00333333333300000333333333333330003333333333330000003333333000000000333333300000000333333330000000333333333300000003333333300000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00043330000000000004333300000000000433300000000000044300000000000000000000000000000000000000000000044000000000000004433000000000
00044be20000000000049b2e20000000000442e2000000000034f63000000000000043333000000000044330000000000034f330000000000034fb2200000000
0039bb22000000000039bbb2300000000039bbe200000000003fbb62200000000034fbb6e22000000034fb2330000000003fbbe200000000003fbbbe20000000
003fbb2300000000003fbb3300000000003fbb2300000000003fbbbbe2000000003fbbbbbe200000003fbb6622000000003fbb6200000000003fbbb620000000
003bb23000000000003bb30000000000003bbb3000000000003bbbbbe3000000003bbbbbb6230000003bbbbb62200000003bbbbe30000000003bbbbbe3000000
003bb30000000000003b300000000000003bbb3000000000003bbbb2230000000034bbbbbb230000003bbbbbb2300000003bbbb2300000000034bbbb23000000
0034b30000000000003b300000000000003bb300000000000034bb33300000000034bbbbb22300000034bbbbb23000000034bbb2300000000034bbb223000000
0034be00000000000039be00000000000034b300000000000034433000000000003344422230000000344bbb223000000034bbb23000000000344bb223000000
00343220000000000034422000000000003433000000000000333300000000000033333333000000003344223300000000334b23300000000033442233000000
00333330000000000033323000000000003333000000000000033000000000000000033300000000000333333000000000333333000000000003333330000000
00033300000000000003333000000000000330000000000000000000000000000000000000000000000000000000000000033330000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00333333333300000333333333333330003333333333330000003333333000000000333333300000000333333330000000333333333300000003333333300000
04944bbbbb6e2000494bb6bbbbbbb2e2049bb6bbbbb2e22000044fbb6e220000000049bbee22000000449bbb6e22000000449fbb6e22000000449fbb6e220000
044444bbbbbbe20044442223349bbb220444bbbbbbbb2e2000049bbbbbe2000000049bbbb2e200000049bbbbbbe200000049bbbbbbe200000049bbbbbbe20000
0033344bbbbb23000333300004444b230034b2349bbb223000034bbbbb22000000039bbbb22000000034bbbbbb2300000034bbbbbb2300000034bbbbbb230000
000003333bb2230000000000000333300003300444423300000344bbbb30000000034bbbb230000000344bbbb223000000344bbbb22300000034bbbbbb230000
0000000033323000000000000000000000000000033300000000344bb3300000000344bbb3000000003344bb23300000003344bb2330000000344bbbb2230000
00000000033300000000000000000000000000000000000000003344330000000003344bb3000000000333333300000000033333330000000003344223300000
00000000000000000000000000000000000000000000000000000333300000000000334433000000000033300000000000000000000000000000033330000000
00000000000000000000000000000000000000000000000000000000000000000000033330000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222222222
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222220123
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002222222222224567
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000022222222222289ab
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222222222222cdef
__gff__
0003030303030101000000000101000001000000000001000100000000000000010100000000000100000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005050505050505050505000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004040404040404040404000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007c0000000000000000000003030303030303030302000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002010100000000000000000002010101010101010101000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007c0000000000000000000000000000000000000000000000000002010100000000000000000002010101010101010101000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020101010100000000008c000000000000000000000000000000000003020200000000000000000002010101010101010101000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000010000000000101010000000000000000000000000000000000100000000000000000000003010101010101010101000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000007c0000000000000000000000000000007c0000000000000000000000007c000000200000002000000000010101000000000000000201017c00000000000020000000000000000000001000007c00007c000010000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008c00000000000000000000002000000020000000000101010000000000000002010100000000000000200000000000000000000020000000000000000020000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000001010101010101010101000000020101000000020100000002010100000000000000030202000000000000002000000000000000000000200000000000000000200000000000008c7c00000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000007c000000000000000100000000000000001000000010001000000010000000000202010000000000000000100000000000000000200000000000000000020101000000000000000002010100000002010100000000000000000000000000
0000000000000000000000000000007c000000007c0000010101010101060606060101010100000000000100000000000000002000000020002000000020000000000202020000000000000000200000000000000000200000000000000000020101000000000000000002010100000010000000000000000000000000000000
0101010101010101010101010101010101010101010101010100000001060606060100010101010101010100000000000000002000000020002000000020002100000303020000000000000000200000000000000000200000000000000000030202000000000000000003020200000020000000000000000000000000000000
0000000000001000000000000000001000000000000000001000000002060606060200000000000000001000000000000000002000000020002000000020002000000403030000000000000000200000000000000000200000000000000000001000000000000000000000100000000020000000002100000000000000000000
0000000000002000000000000000002000000000000000002000000003030303030300000000000000002000000000000000002000000020002000000020002000000504040000000000000000200000000000000000200000000000000000002000000000000000000000200000000020000000002000000000000000000000
0000000000003000000000000000003000000000000000003000000000000000001000000000000000003000000000000000003000000030003000000030003000000505050000000000000000300000000000000000300000000000000000003000000000000000000000300000000030000000003000000000000000000000
__sfx__
010600001f73220732217222271222712007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000000
01040000107120e7120d7120d7120e7120f7120070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
010600002173222732237222471224712007000070000700007000070000700007000070000700007000070000000000000000000000000000000000000000000000000000000000000000000000000000000000
010900002056420564205642056020541205312052120511005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
0108000029750307503074030730307203071030710067000a7000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000000000000
01040000245601d551165410c531271501f1511a1511915116151151511415112151111510f1510e1510e1510e1510f151151511e151271510010000100001000010000100001000010000100001000010000100
