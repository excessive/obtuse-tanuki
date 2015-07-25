local sql = {
	login       = {},
	login_realm = {},
}

sql.login.select_realms = [[
select
	id,
	name,
	address,
	port
from
	Realms
]]

sql.login.select_channels = [[
select
	id,
	address,
	port
from
	Channels
where
	realm_id=?
]]

sql.login.recv_credentials = [[
select
	id,
	username,
	show_name,
	show_stats,
	status,
	last_login,
	last_realm_id,
	created_at
from
	Users
where
	username=?
	and password=?
limit
	1
]]

sql.login.select_characters = [[
select
	C.id as character_id,
	C.area_id,
	C.party_id,
	C.alias_id,
	A.name as alias,
	C.subtitle,
	C.model,
	C.last_login,
	C.created_at,
	V.image as avatar,
	V.id as avatar_id,
	C.position_x,
	C.position_y,
	C.position_z
from
	Characters as C
left join
	Aliases as A
on
	C.alias_id = A.id
left join
	Avatars as V
on
	A.avatar_id = V.id
where
	C.user_id=?
]]

sql.login.select_character = [[
select
	C.id as character_id,
	C.area_id,
	C.party_id,
	C.alias_id,
	A.name as alias,
	C.subtitle,
	C.model,
	C.last_login,
	C.created_at,
	V.image as avatar,
	V.id as avatar_id,
	C.position_x,
	C.position_y,
	C.position_z
from
	Characters as C
left join
	Aliases as A
on
	C.alias_id = A.id
left join
	Avatars as V
on
	A.avatar_id = V.id
where
	C.id=?
]]

sql.login_realm.select_party_characters = [[
select
	alias_id
from
	Characters
where
	party_id=?
]]

sql.login_realm.update_user_last_login = [[
update
	Users
set
	last_login=?
where
	id=?
]]

sql.login_realm.update_character_last_login = [[
update
	Characters
set
	last_login=?
where
	id=?
	and user_id=?
]]

sql.login_realm.insert_alias = [[
insert into
	Aliases
	(character_id, avatar_id, name, created_at)
values
	(?, ?, ?, ?)
]]

sql.login_realm.insert_party = [[
insert into
	Parties
	(leader_id, realm_id)
values
	(?, ?)
]]

sql.login_realm.update_party = [[
update
	Parties
set
	leader_id=?
where
	leader_id=?
]]

sql.login_realm.update_character_alias = [[
update
	Characters
set
	alias_id=?
where
	id=?
	and user_id=?
]]

sql.login_realm.insert_avatar = [[
insert into
	Avatars
	(created_at, character_id, image)
values
	(?, ?, ?)
]]

sql.login_realm.update_character_avatar = [[
update
	Aliases
set
	avatar_id=?
where
	id=?
]]
-- in
-- 	(select alias_id from Characters where id = ?)

sql.login_realm.update_character_party = [[
update
	Characters
set
	party_id=?
where
	id=?
	and user_id=?
]]

return sql
