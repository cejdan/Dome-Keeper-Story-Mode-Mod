# Story Mode: Script

Notes for implementers:
- Company name, used everywhere: Halcyon Extraction. Only the data logs and the planet_end narration mention it.
- The horror's name for the keeper, starting at unobtainium_1: little keeper. Every beat that can fire before the first unobtainium (biomes, first_gem, gate_broken, lava deaths, translators) says only 'you', so the address stays right whatever order the player finds things in.
- The player is meant to work out that they are Keeper 9. The logs come from Keepers 1, 4, 5, 6, 7 and 8. The gaps are deliberate.
- Narration: a line starting with '> ' is the narrator, not the horror (#137). The first beats (b2, b3) open with narration. The user wrote these (2026-11-13); the rest of the script still needs a human pass.
- Lines the logs echo on purpose: 'only frightened, you don't have to be' (log_b3 only: the horror said it to Ines Varga, the keeper no longer hears it at b3), 'doing so well' and 'just a little deeper' (b4, b6), 'put it down' (translator_3), 'little keeper' (log_b7, then unobtainium_1).

## Horror's name

- Velle: Latin for 'to want'. It's soft, two syllables, almost a girl's name, and it's the same word as the keeper's greed. The horror and the keeper want the same thing.
- Somna: from sleep, and it sounds like a lullaby. Too on the nose, though: it tells players what it is before they're scared of it.
- Lume: light, a lamp in the dark. It fits the glowing tier-3 text, and it's what draws the keeper down. Pretty, but it doesn't feel ancient.
- Ommoreth: heavy, old and grinding. It sounds like a god under a planet, but also like every fantasy villain, and it fights the sweetness.
- Hush: what the monsters sing to keep it asleep. It's chilling, but the word turns up in normal speech too often to work as a reveal.

Chosen: Velle

## Story beats

### biome_b2 (tier 1)
> You hear a quiet voice whispering something softly. You can't quite tell if the sound is coming from deep below, or from the walls themselves.
---
> You strain to listen, and think you hear faintly:
Hello digger.

### biome_b3 (tier 1)
> You hear a voice again. You're still not sure if the sound is coming from the walls or the deep. You have a passing thought, but try and dismiss it. Maybe the voice is inside your head.
---
I'm so happy you're here.

### biome_b4 (tier 2)
The monsters trapped me. Caged me. Beat me. Flayed me. But you can save me.
---
You're doing so well.
Every layer you lift is a blanket off my face.
Just a little deeper.

### biome_b5 (tier 2)
I can hear your heartbeat through the stone.
It keeps time with the drill. Isn't that lovely?
Don't go up yet.

### biome_b6 (tier 2)
Others came before you. They stopped about here, for a while.
They always came down in the end.
Just a little deeper.

### biome_b7 (tier 3)
I've waited such a long time for hands like yours.
Patient hands. Hungry hands.
Closer.

### biome_b8 (tier 3)
This is the last crust between us.
Under it, everything is warm and bright, and all of it is yours.
I only want one small thing back. Keep digging.

### lava_ocean (tier 3)
Swim, then. The fire won't mind you.
The bright stone is down there. Your kind call it a fortune.
Every piece you lift, I breathe a little easier. Take as many as you like.

### first_gem (tier 1)
Pretty, isn't it?
There's so much more. All of it further down.

### gate_broken (tier 2)
Someone locked that door a long time ago.
Not against you. Never against you.

### lava_death_1 (tier 2)
Oh. Oh, that hurt you.
The fire is clumsy. I would hold you more gently.
There you are. Come back down.

### lava_death_2 (tier 2)
Oh. Oh, that hurt you.
The fire is clumsy. I would hold you more gently.
There you are. Come back down.

### lava_death_3 (tier 2)
Oh. Oh, that hurt you.
The fire is clumsy. I would hold you more gently.
There you are. Come back down.

### lava_death_4 (tier 2)
Oh. Oh, that hurt you.
The fire is clumsy. I would hold you more gently.
There you are. Come back down.

### lava_death_5 (tier 2)
Oh. Oh, that hurt you.
The fire is clumsy. I would hold you more gently.
There you are. Come back down.

### translator_1 (tier 1)
That's one of theirs. You don't need it.
I already speak your language.

### translator_2 (tier 2)
Another one? Their words are so loud, and so small.
Mine are only for you. Wouldn't you rather have mine?

### translator_3 (tier 3)
Please put it down. They'll tell you I'm something terrible.
Have I ever been anything but kind to you?
Listen to me. Only me.

### unobtainium_1 (tier 3)
Ah. Ahh. Did you feel that?
Something very old just cracked, little keeper.
Do it again.

### unobtainium_3 (tier 3)
Three. I can feel my fingers again, little keeper.
The first thing they touch will be you.

### unobtainium_5 (tier 3)
Five. I can see your lamp through my eyelids, little keeper.
Up there, they're crying. Down here, I'm smiling.
Keep digging.

### unobtainium_7 (tier 4)
Seven. My heart has started again. It beats with yours.
I'm so proud of you, little keeper.
Bring me the rest, and I'll give you everything you came here for.

### unobtainium_10 (tier 4)
Ten. The seal is only a whisper now, little keeper.
Come to the middle of the world. I want to see your face.
Or go home rich, if you like. I'll be awake to wave goodbye.

### boss_chamber (tier 4)
There you are. Oh, look at you. So small, after all that digging.
You were so good, little keeper. Better than the others.
The little ones above have a word for me. It means hunger. That's unkind.
My name is Velle. It means wanting.
You know all about wanting, don't you?
Now come closer, and let me open my eyes.

### boss_wait (tier 4)
Not yet, little keeper. Come closer.
Closer still. I'm almost ready for you.

## Pleas

### Stage A (B1 to B2): warning

#### arrive
- *Stop*. Go home, small digger.
- Ground is *sleeping*. Let it sleep.
- You dig *wrong* place. *Leave*.
- Not for you. Go *away*, please.
- We *warn*. We only warn.
- Quiet the drill. Something *listens*.

#### fight
- *Why* you *dig*? Why?
- No more *holes*. No more!
- *Stop* the drill!
- We not want *hurt*. Just *stop*.
- Down is *bad*. Down is bad!
- You *hear* it? Do not *listen*.
- Go *up*. Go *home*.
- Leave the stones. Stones keep it *asleep*.

#### death
- Please... *stop*...
- Tell it... we *tried*...
- *Warned* you. Warned you...
- Not us... *it*... it wakes...
- Go *home*, digger...
- So *quiet*... soon so quiet...

### Stage B (B3 to B5): begging

#### arrive
- *Please*. We beg you. *Please*.
- *Stop* digging. We give anything.
- It *sleeps* under you. Please!
- Small digger, *listen*. Only listen.
- We bring no anger. Bring *fear*.
- Every hole you make, it *breathes*.

#### fight
- *Please*! Please stop!
- It *talks* to you. It *lies*.
- Warm rock is *it*. Not warm. *It*!
- Do not go *deeper*!
- We have *children* up here!
- It *whispers*? Cover your *ears*!
- You are *helping* it!
- *Stop*, stop, stop!

#### death
- Please... *please*...
- My *children*... keep them...
- It says... *deeper*... do not...
- You... *heard*... us?
- Not angry... *afraid*...
- *Sorry*... sorry we hit dome...

### Stage C (B6 to B8): despair

#### arrive
- Too *deep*. You are too deep.
- Others came *down*. *Never* came up.
- *Why*? Why you not stop?
- We fight. Nothing *else* left.
- *Bright* stone holds it *down*.
- Leave the *seal*. It is last.

#### fight
- *Turn* back! Still time!
- It does not *love*. It *eats*.
- We are *dying* for this!
- Last *seal*! Last one!
- Not *hate* you. *Fear*!
- Hear *us*! Not it. Us!
- *Bones* below. Miner *bones*. Look!
- For *shiny*? All this for shiny?

#### death
- No more... *time*...
- It *smiles*... we feel it smile...
- Was our *home*... was home...
- You will... *wake* it...
- *Remember* us...
- Go *up*... while sky still...

### Stage D (lava ocean and below): grief

#### arrive
- *Too* *late*. Too late now.
- It is *waking*. You did this.
- We came to say *goodbye*.
- No fight left. Only *sing*.
- We sing it to *sleep*. It not listen.
- The *ground* is *breathing*.

#### fight
- Was there *nothing* we could say?
- *Shiny*. All this for shiny.
- Our young hide. *Nowhere* to hide.
- Hit dome. *Nothing* else to do.
- Stop *now*? Please? Even now?
- It *sings* to you. We *hear* it.
- You were *warned*. Every day, warned.
- *Sky* goes *dark* soon.

#### death
- *Goodbye*... digger...
- At least... I *sleep* first...
- I *forgive*... I try to...
- *Home*... was so *pretty*...
- You took... *everything*...
- *Dark* now... very dark...

## Data logs

### keeper_welcome
Title: MEMO: Halcyon Extraction, Keeper Onboarding
Keeper: landing confirmed. Congratulations, and welcome to the site.
Your shift starts now. Halcyon looks forward to a long and productive dig.
Native fauna are easily agitated by mining operations. They are also easily managed with your company-issued laser.

### log_b1
Title: Personal log: Dale Okafor, Keeper 1, shift 3
Bugs hit the dome again. They shriek the whole fight, like they're yelling at me.
Ore's thick up here. Hit quota by noon.
Company sheet says the fauna is acoustically aggressive, non-strategic.
Earplugs in. Drill on.

### log_b2
Title: MEMO: Halcyon Extraction, Fauna Compliance
To all Keepers: native vocalisations are noise, not language. Do not record them.
Alien translation devices found on site are company property. Surrender them unused.
Productivity bonuses resume below Layer 4.

### log_b3
Title: Personal log: Ines Varga, Keeper 4, shift 21
Heard something under the drill tonight. Not the bugs. Lower. Kind.
It said the things on the surface are only frightened. That I don't have to be.
Slept nine hours. First time since landing.

### log_b4
Title: MEMO: Halcyon Extraction, Office of Deep Projects
Keeper 4 reports a voice at Layer 3. Excellent. Do not recall her.
Her depth per shift is up 300 percent since contact.
Classify the voice as a motivational phenomenon. Keep it out of onboarding.
Keepers who hear it dig. Keepers who dig retire.

### log_b5
Title: Personal log: Ruth Ammon, Keeper 5, shift 64
Passed Varga's bones at Layer 3. Her pad said the voice told her she was doing so well.
It tells me that too. I think it means it.
I've stopped going up for the waves. They don't break the dome. They just cry at it.
Just a little deeper. It's always just a little deeper.

### log_b6
Title: Personal log: Sol Haddad, Keeper 6, shift 80
Got a translator working. The company said never to.
They aren't screaming. They're saying please. They've been saying please since day one.
It asked me to put the translator down. It's never asked me for anything before.
I put it down. Then I picked up the drill.

### log_b7
Title: Personal log: Ada Lindqvist, Keeper 7, shift 112
The translator says they've stopped screaming. Now they sing. Funeral songs.
It calls me little keeper now. It told me its name.
I won't write it down. Writing it feels like opening a door.
I said I'd go up. I'm going down.

### log_b8
Title: MEMO: Halcyon Extraction, Office of the Chair (copied by Keeper 8)
The Asset gave Keeper 7 its name: Velle.
The ore was never the product. Once woken, Velle hollows the planet. What's left is solid unobtainium.
Keeper 9 deploys next cycle. Do not brief. Pre-approve the retirement.
Added by Keeper 8: whoever you are, don't buy it.

## Doom ending

### horror_thanks
Thank you, little keeper.
Oh, the air up there. I'd forgotten the air.
---
Go on, then. Fly home. Spend it all.
You were always going to.
---
Don't look back. This part isn't for you.
I'll sing the little ones to sleep, all of them. It's what they wanted.

### planet_end
The pod left the surface at dawn, a million dollars heavier.
Below it, the ground opened like an eye.
On the surface the singing stopped, one voice at a time.
By the time the pod reached orbit, the planet had gone dark.
Halcyon Extraction logged the site as fully yielded.

### monsters_last
- Was it *enough*, digger?
- We *tried*. We tried so hard.
- *Sleep* now, little ones. Close your *eyes*.

## Saved ending

### saved
Velle went quiet, and stayed quiet.
The next wave reached the dome and did not attack. They sat in the dust and sang, low and slow.
The translator called it a lullaby. It was not for the keeper.
The tunnels stayed open to the sky. The keeper had dug every one of them.
Halcyon Extraction marked the site as a loss.

## End screen titles

Doom title: The Planet Is Lost
Doom subtitle: You retired rich. The planet paid for it.

Saved title: The Planet Is Saved
Saved subtitle: Saved by the hands that nearly ended it.
