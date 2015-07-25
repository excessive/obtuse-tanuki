-- mockup, not actual API
function account()
	local online_modes = {
		offline        = 0,
		online         = 1,
		do_not_disturb = 2,
		invisible      = 3,
	}
	local function new_account()
		local account = {
			show_name   = true,
			show_stats  = true,
			online_mode = online_modes.offline,
			money       = {},
			inventory   = {},
			last_login  = nil,
		}
		return account
	end
end

function player()
	local function new_player(account, name)
		local player = {
			last_location = nil,
			last_login    = nil,
			money         = {},
			inventory     = {},
			equipment     = {},
			outfit        = {},
			skills        = {
				attacks = {},
				support = {},
				actions = {}
			},
			name      = name,
			account   = account,
		}
		return player
	end
end

local client = net_client()

-- password should be sent as a hash, never in plaintext?
submit_login("username", "password", "pve")

local function login_successful(account)
	-- login passes back a destination server and unique token for handoff
	client:connect(account.destination, account.token)
	join_game(account)
end

local function update()
	local states = {
		login = function()
			-- wait on network thread until we get a login
			local account = client:pop()
			if account then
				if check_login(account) then
					-- we got back our account information
					login_successful(account)
					self.state = "entering"
				else
					login_failed()
					self.state = "error"
				end
			end
		end,
		entering = function()
			local instance = client:pop()
			if instance then
				if check_instance(instance) then
					self.state = "connected"
				else
					login_failed()
					self.state = "error"
				end
			end
		end,
		connected = function()
			-- we have ARRIVED!
		end,
		error = function()
			print("it's broken :(")
		end
	}
	assert(states[self.state])
	states[self.state]()
end
