-- The two humans allowed into the web tool. RLS keys on these emails;
-- the teacher logs in as username "sensei", mapped client-side to the
-- placeholder address (no mailbox needed - password auth, no magic links).
insert into allowed_users (email, role) values
    ('stevenrguido@gmail.com', 'owner'),
    ('sensei@bromodachi.local', 'teacher');
