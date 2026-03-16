-- Create ReviewVector table (VECTOR type not supported by DacFx, deployed as raw SQL)
:r ..\Tables\ReviewVector.sql
GO

-- Seed data: Categories, Products, Customers, Reviews (Star Trek toy shop)

-- ═══════════════════════════════════════════════════════════════
--  Categories
-- ═══════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM dbo.Category)
BEGIN
    SET IDENTITY_INSERT dbo.Category ON;
    INSERT INTO dbo.Category (CategoryId, [Name]) VALUES
        (1, N'Federation Starships'),
        (2, N'Klingon Warships'),
        (3, N'Romulan Vessels'),
        (4, N'Borg Cubes'),
        (5, N'Space Stations');
    SET IDENTITY_INSERT dbo.Category OFF;
END

-- ═══════════════════════════════════════════════════════════════
--  Products  (same catalog as Session-H12)
-- ═══════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM dbo.Product)
BEGIN
    SET IDENTITY_INSERT dbo.Product ON;
    INSERT INTO dbo.Product (ProductId, [Name], CategoryId, Price) VALUES
        (1,  N'USS Enterprise NCC-1701',         1, 149.99),
        (2,  N'USS Enterprise NCC-1701-D',       1, 89.99),
        (3,  N'USS Defiant NX-74205',            1, 64.99),
        (4,  N'USS Voyager NCC-74656',           1, 79.99),
        (5,  N'USS Enterprise NCC-1701-E',       1, 99.99),
        (6,  N'Klingon Bird-of-Prey',            2, 59.99),
        (7,  N'Klingon Vor''cha Attack Cruiser', 2, 74.99),
        (8,  N'Romulan D''deridex Warbird',      3, 109.99),
        (9,  N'Borg Cube',                       4, 129.99),
        (10, N'Deep Space Nine',                 5, 189.99);
    SET IDENTITY_INSERT dbo.Product OFF;
END

-- ═══════════════════════════════════════════════════════════════
--  Customers  (drawn from CrmDb Star Trek contacts)
-- ═══════════════════════════════════════════════════════════════
IF NOT EXISTS (SELECT 1 FROM dbo.Customer)
BEGIN
    SET IDENTITY_INSERT dbo.Customer ON;
    INSERT INTO dbo.Customer (CustomerId, FirstName, LastName, Email) VALUES
        (1,  N'James',       N'Kirk',      N'jkirk@starfleet.org'),
        (2,  N'Spock',       N'Grayson',   N'spock@starfleet.org'),
        (3,  N'Jean-Luc',    N'Picard',    N'jpicard@starfleet.org'),
        (4,  N'William',     N'Riker',     N'wriker@starfleet.org'),
        (5,  N'Kathryn',     N'Janeway',   N'kjaneway@starfleet.org'),
        (6,  N'Benjamin',    N'Sisko',     N'bsisko@starfleet.org'),
        (7,  N'Worf',        N'Mogh',      N'wmogh@starfleet.org'),
        (8,  N'Geordi',      N'LaForge',   N'glaforge@starfleet.org'),
        (9,  N'Data',        N'Soong',     N'dsoong@starfleet.org'),
        (10, N'Deanna',      N'Troi',      N'dtroi@starfleet.org'),
        (11, N'Montgomery',  N'Scott',     N'mscott@starfleet.org'),
        (12, N'Seven',       N'Hansen',    N'shansen@starfleet.org'),
        (13, N'Tom',         N'Paris',     N'tparis@starfleet.org'),
        (14, N'Julian',      N'Bashir',    N'jbashir@starfleet.org'),
        (15, N'Beverly',     N'Crusher',   N'bcrusher@starfleet.org');
    SET IDENTITY_INSERT dbo.Customer OFF;
END

-- ═══════════════════════════════════════════════════════════════
--  Reviews  (long ones intentionally verbose for chunking demo)
-- ═══════════════════════════════════════════════════════════════

-- Disable the ReviewChanged trigger during seeding so we don't
-- clear ReviewVector rows while inserting reviews.
IF OBJECT_ID('dbo.ReviewChanged', 'TR') IS NOT NULL
    DISABLE TRIGGER dbo.ReviewChanged ON dbo.Review;

IF NOT EXISTS (SELECT 1 FROM dbo.Review)
BEGIN
    SET IDENTITY_INSERT dbo.Review ON;

    -- ── LONG REVIEW 1 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (1, 1, 1, '2025-10-15',
N'I cannot begin to express how much this model of the USS Enterprise NCC-1701 means to me. Growing up in the late 1970s in a small town in Iowa, Star Trek was my entire world. My father used to take me to the local hobby shop every Saturday morning and I would press my face against the glass display case that held these incredible ship models. The original Enterprise was always the one that caught my eye with its elegant saucer section and those beautiful glowing nacelles on the old box art.

I remember saving up my allowance for months, mowing lawns, washing cars, doing every odd job a ten-year-old could find, all for this ship. When I finally had enough money my father drove me to the shop on a rainy October afternoon. I can still feel the weight of that box in my hands as I carried it to the car. I spent the entire weekend assembling it with my dad at the kitchen table, painting with the careful precision of a surgeon. He showed me how to thin the paint so it went on smooth and how to use a toothpick for the tiny registry numbers.

That model sat on my desk through middle school, high school, and even went with me to college. My roommate thought I was nuts but I did not care. Years later, after my father passed away, I went looking through the old house and found it in a box in the attic. Decades of dust, a few broken nacelles, but still there. I tried to restore it but it was beyond saving and I thought I would never find another one like it.

Then I stumbled upon this listing and I could not believe my eyes. The detail on this model is extraordinary. The saucer section has that perfect pearl-white finish that catches the light the same way the original TV prop did. The nacelle caps actually glow when you turn on the LED lighting system. The registry number is crisp and clean and the deflector dish has a subtle amber warmth to it that takes me right back to 1979.

When the package arrived I opened it at the kitchen table and my twelve-year-old daughter walked in. She asked me what it was and I told her the whole story about grandpa and the hobby shop and the rainy October day. She sat down next to me and helped me set it up on the shelf in my home office. Now it sits right next to my computer monitor and every time I look at it I think of my father and Saturday mornings and the hobby shop that is long gone. This model is not just a collectible. It is a bridge between generations. The craftsmanship is superb, the attention to detail is museum-quality, and the price is honestly a bargain for what you get. I bought a second one for my daughter for her birthday.');

    -- ── LONG REVIEW 2 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (2, 2, 3, '2025-11-02',
N'I grew up in a house where Star Trek The Next Generation was appointment television. Every Saturday evening my father would make tea, Earl Grey of course, and we would sit together in the living room and watch the Enterprise-D explore the galaxy. I was maybe seven or eight when the show premiered and by the time it ended I was a teenager, but those Saturday evenings never changed. It was our thing.

My father was an engineer and he loved talking about the ship design. He would pause the VHS tape and point out the details of the saucer separation mechanism or explain why the warp nacelles were positioned exactly where they were. He had opinions about everything on that ship. We used to argue about whether the Galaxy-class was really the best design Starfleet ever produced. He thought so. I was not so sure at the time but I have come around to his way of thinking.

When I saw this model of the NCC-1701-D I knew I had to have it. The proportions are absolutely perfect. So many model makers get the Galaxy-class wrong because the saucer is so enormous relative to the engineering section, but this one nails it. The aztec paneling across the hull is subtle and realistic. The windows along the saucer rim are individually lit and at night with the room lights off it looks like the actual ship floating in space.

I set it up on a shelf in my study right next to a framed photo of my father and me. He passed away three years ago but I know he would have loved this model. He would have spent an hour examining it with a magnifying glass, pointing out every detail, and then he would have made tea and told me about the engineering specifications of the real ship. I miss those conversations but this model brings them back in a small way.

The build quality is excellent. The stand is rock-solid and the ship can be positioned at a slight upward angle as though it is heading to warp. The packaging was superb with absolutely no damage. If you grew up watching TNG with someone you love, this is the model for your shelf. It is a memory you can hold.');

    -- ── LONG REVIEW 3 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (3, 10, 6, '2025-12-20',
N'Building the Deep Space Nine model with my two kids over winter break was one of the best family projects we have ever done. I have to admit I was a little intimidated by it because the station design is so much more complex than a starship. All those docking pylons and the habitat ring and the Promenade section. But the instructions were clear and the pieces fit together beautifully.

My son who is fourteen was in charge of the upper pylons and the weapons array. He is a detail guy and he spent two full evenings getting the phaser strips positioned exactly right. My daughter who is eleven took on the habitat ring and she was meticulous about painting the windows to look illuminated even though this model does not have built-in lights. She used a metallic gold paint pen and the effect is surprisingly convincing.

I handled the central core and the docking ring and I have to say the engineering on these parts is impressive. The way the pylons click into the ring with those hidden pegs means you do not need any glue for the main structure. Everything locks together with a satisfying snap. We did use a tiny bit of model cement on the smaller antennae pieces but that was it.

The finished station is substantial. It measures about eighteen inches across the docking ring and it has real weight to it. We hung it from a ceiling hook in the playroom using fishing line and it looks incredible. When the light catches it from the side it casts shadows that look like the station in orbit above Bajor. My son immediately wanted to build a scale Defiant to dock with it and honestly I cannot blame him.

What really makes this model special is the time we spent together building it. Three evenings of working at the dining room table, talking about the show, debating which DS9 episodes were the best, and just being a family. My daughter had never actually watched the show before but now she is working her way through the first season. I told her it gets much better in season three and she should stick with it.

If you are looking for a model that doubles as a family project, this is the one. The difficulty is moderate enough that kids can contribute meaningfully and the end result is genuinely display-worthy. We are already planning to tackle the Borg Cube next.');

    -- ── LONG REVIEW 4 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (4, 6, 7, '2025-11-18',
N'My older brother had a Klingon Bird-of-Prey model when we were kids and I wanted it more than anything in the world. He kept it on the top shelf of his bookcase, way out of my reach, and he would not let me touch it. Not even once. He said my hands were too clumsy and I would break the wings. I was maybe six and he was twelve and he was probably right, but it did not make it hurt any less.

I would sneak into his room when he was at school and just stare at it. The way the wings angled downward in attack position, that dark green hull with the red accents, the bird painted on the underside. It was the coolest thing I had ever seen. I used to draw pictures of it in my school notebooks. My teachers thought I was drawing some kind of angry bird but I knew what it was.

When my brother left for college he took it with him of course. I never saw it again. I think it got lost in one of his many moves over the years. We are both in our forties now and last Thanksgiving I mentioned the old Bird-of-Prey and he laughed and said he had completely forgotten about it. But I never did. Some things just stay with you from childhood.

So when I found this model online I did not hesitate for a second. I placed the order immediately. When it arrived and I opened the box I felt like that six-year-old kid again staring up at his brother''s bookshelf. The detail on this thing is magnificent. The wings are poseable so you can set them in cruise mode angled up or attack mode angled down. The disruptor cannons on the wing tips are individually sculpted. The cloaking device housing on the underside is a separate piece with its own paint finish.

I put it on my desk at work and my colleague who is also a Trek fan noticed it immediately. We spent twenty minutes discussing whether the Bird-of-Prey is the most iconic alien ship design in all of science fiction. I think it is. The Klingon aesthetic is just so aggressive and purposeful and this model captures that perfectly. The paint job has this wonderful weathered quality that makes it look like it has been through a few battles.

I sent a photo to my brother and he replied with a single word: jealous. That might be the most satisfying text message I have ever received.');

    -- ── LONG REVIEW 5 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (5, 4, 5, '2026-01-08',
N'I had genuinely given up on ever finding a quality Voyager model. I have been collecting Star Trek ships for over twenty years and Voyager has always been the gap in my collection. The Intrepid-class has this sleek asymmetric design with the variable-geometry nacelles that most model makers just cannot get right. Either the nacelles are too thick or the proportions of the secondary hull are wrong or the paint does not capture that distinctive blue-grey finish.

I had a cheap one years ago that I picked up at a convention and it was terrible. The nacelles did not even move and the saucer looked like it was designed by someone who had only seen the ship described in words. I threw it away eventually which is something I almost never do with a Trek model, that is how bad it was.

Then a friend told me about this site and said they had a Voyager that was actually good. I was skeptical but I ordered it anyway because hope springs eternal as they say. When the package arrived I opened it carefully expecting disappointment and instead I got one of the best model ships I have ever owned.

The first thing you notice is the nacelles. They actually pivot between the cruise and warp configurations. The mechanism is smooth and there is a subtle click when they lock into position. The paint work on the hull captures that unique Voyager finish perfectly. It is not quite the same blue-grey as the Enterprise and this model gets that right. There is a slightly warmer tone to it, almost a hint of teal, and the aztec pattern is present but understated.

The deflector dish has a beautiful copper-orange tone and the phaser arrays along the saucer edge are individually detailed. The bridge module is tiny but you can still make out the windows. The stand positions the ship at a slight nose-down angle that gives it that perpetual sense of motion that Voyager always had on screen.

It now sits in my display case between the Enterprise-D and the Defiant and it absolutely holds its own. I have been staring at it for a week and I keep noticing new details. The shuttle bay doors, the lifeboat hatches along the saucer, the RCS thrusters. Someone who loves this ship designed this model and it shows. If you have been waiting for a proper Voyager like I was, the wait is over.');

    -- ── LONG REVIEW 6 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (6, 9, 12, '2026-02-14',
N'I realize the irony of me owning a Borg Cube model is not lost on anyone. My kids think it is hilarious. My oldest who is sixteen calls it my comfort cube. But there is something genuinely fascinating about the Borg aesthetic and this model captures it beautifully in a way I did not expect from what is essentially a geometric shape.

The surface detail is what makes it. Every face of the cube is covered in microscopic mechanical textures. Conduits, access ports, alcove arrays, power distribution nodes. You can spend a solid ten minutes examining one face of this thing with a magnifying glass and still find details you missed. Under the right lighting it almost looks organic, like the surface is alive and constantly reconfiguring itself. Which is exactly what the Borg do.

The green internal glow is achieved through an LED panel in the base that shines upward through a translucent core. At night it casts these incredible geometric shadows across the wall behind it. My daughter took a photo of it for her art class at school and her teacher asked where we got such an interesting light sculpture. When she explained it was a Star Trek toy the teacher looked confused but gave her an A on the photography project anyway.

I keep it on the bookshelf in the living room next to our family photos. Guests always notice it and it starts the most wonderful conversations. People who have never seen Star Trek ask what it represents and I get to explain the concept of a cybernetic collective that assimilates technology and biological organisms. It is a surprisingly effective conversation starter at dinner parties.

My younger son who is twelve wants me to get the Enterprise-D next so he can set up a confrontation scene on the shelf. He has already planned the lighting and wants to use cotton batting for weapons fire. I told him that sounds like a project we can do together this summer. In the meantime the Cube sits on its shelf, glowing green in the dark, a strange and wonderful centerpiece for a home that is full of warmth. Resistance, as they say, was futile.');

    -- ── LONG REVIEW 7 ──────────────────────────────────────────
    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (7, 1, 11, '2025-12-05',
N'As an engineer I have always appreciated the original Enterprise from a design perspective. Matt Jefferies created something in the 1960s that still looks futuristic today and that is an extraordinary achievement. I have studied the original design schematics that were published in the Star Trek technical manuals and the proportions of this model match them almost exactly. Whoever designed this did their homework.

The nacelle struts are precisely angled at the correct thirty-degree sweep. The interconnecting dorsal between the saucer and the engineering hull has the right taper. The deflector dish is positioned exactly where it should be relative to the lower sensor dome. These are the kinds of details that most casual observers would never notice but they make all the difference to someone who has spent years thinking about this ship.

I display it on my desk at the office right next to my engineering reference books. My colleagues in the mechanical engineering department have all stopped by to admire it. One of them, a naval architect, said the saucer section design is fascinating from a structural engineering standpoint because it distributes stress loads across the widest possible surface area. We had a forty-minute discussion about fictional spacecraft engineering principles and it was one of the best conversations I have had at work in years.

The model came with a display stand that allows for about fifteen degrees of pitch adjustment. I have it angled slightly upward as though the ship is beginning its climb out of orbit. The LED lighting kit was easy to install and the nacelle glow is exactly the right shade of blue. Not too bright, not too dim. Whoever chose that color temperature understood the source material.

My only minor note is that the impulse engines on the back of the saucer could be slightly more pronounced. On the original filming model they had a distinct reddish glow that is barely hinted at here. But that is an extremely minor complaint about what is otherwise a masterpiece of model engineering. I plan to order the refit version next.');

    -- ── SHORT AND MEDIUM REVIEWS ───────────────────────────────

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (8, 2, 4, '2025-11-25',
N'Solid model of the Enterprise-D. The proportions are spot-on and the Galaxy-class saucer is massive, just as it should be. Great paint finish too. My only complaint is the nacelle pylons feel a little fragile. I would recommend handling it carefully when positioning it on the stand. Overall very happy with the purchase and it looks great on my bookshelf.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (9, 5, 8, '2026-01-15',
N'The Sovereign-class Enterprise-E is my favorite ship design and this model does it justice. The lines are aggressive and sleek compared to the rounder Galaxy-class. Clean build, good weight, nice stand.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (10, 9, 9, '2025-12-28',
N'Fascinating. The Borg Cube as a collectible is an interesting study in minimalist geometry. The surface detailing is remarkably intricate for what appears at first glance to be a simple shape. I have calculated that the surface area to volume ratio is mathematically optimal for a vessel designed to maximize internal space. The LED glow effect is pleasing. I find it calming to observe.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (11, 8, 10, '2025-10-30',
N'Beautiful ship. The Romulan Warbird has always been one of the most graceful designs in Trek and this model captures the sweeping lines perfectly. Looks wonderful on my desk.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (12, 1, 2, '2025-11-10',
N'A logical purchase. The NCC-1701 is historically significant as the vessel that began it all. This model is well constructed with accurate proportions and fine detailing. The nacelle lighting is a particularly effective feature. I note that the registry lettering uses the correct font from the original series which demonstrates commendable attention to canon accuracy. I find no significant flaws in the construction.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (13, 3, 13, '2026-02-01',
N'The Defiant is compact but tough, just like on the show. Great little model for the price.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (14, 10, 14, '2025-12-10',
N'Deep Space Nine is an impressive model. The docking ring and pylons are well engineered and the Promenade section has real character. I used to watch the show during medical school and this brings back memories of late-night study sessions with DS9 on in the background. Quality is excellent for the price point and it makes a fine conversation piece.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (15, 4, 15, '2026-01-22',
N'Lovely Voyager model. The variable nacelles are a nice touch. Perfect size for a bookshelf.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (16, 6, 1, '2025-11-30',
N'I bought the Bird-of-Prey to go alongside my Enterprise on the shelf. The Klingon ship has a menacing presence that contrasts nicely with the Enterprise''s clean lines. The poseable wings are a great feature. Attack position looks particularly fierce. Good detail on the disruptor cannons and the underside bird artwork is well done.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (17, 10, 5, '2026-02-18',
N'Great station model but the assembly was a bit more involved than I expected. End result is worth the effort.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (18, 7, 4, '2025-12-15',
N'The Vor''cha is an underrated design. This model makes it look as imposing as it deserves. Nice weathering effects on the hull.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (19, 5, 3, '2026-03-01',
N'Excellent Sovereign-class model. Sharp lines, good heft. Stands proudly next to my Enterprise-D.');

    INSERT INTO dbo.Review (ReviewId, ProductId, CustomerId, ReviewDate, ReviewText) VALUES
    (20, 6, 11, '2026-01-05',
N'A fine Bird-of-Prey. From an engineering standpoint the wing articulation mechanism is cleverly designed. The pivot points are reinforced and there is no wobble at any angle. The paint is well applied with consistent coverage across the hull. I particularly enjoy the weathering on the wing tips which gives the ship a battle-worn appearance. A worthy addition to any collection and a good conversation piece during office hours.');

    SET IDENTITY_INSERT dbo.Review OFF;
END

IF OBJECT_ID('dbo.ReviewChanged', 'TR') IS NOT NULL
    ENABLE TRIGGER dbo.ReviewChanged ON dbo.Review;

-- Snapshot for ResetDemo (idempotent demo runs)
IF OBJECT_ID('dbo.ReviewSeed', 'U') IS NULL
    SELECT ReviewId, ReviewText INTO dbo.ReviewSeed FROM dbo.Review;
