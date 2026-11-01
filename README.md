# Shatter

Disenchanting a bag of greens means casting Disenchant, clicking the item, looting, then
doing it again for the next one, while making sure the cloak you meant to keep, the set piece for
your second spec or the blue worth more on the auction house isn't the one under the cursor.

Shatter turns that into one button. It lists what in your bags can be disenchanted, leaves out what
you want to keep, and shows what each item should give. Click **Shatter Next** (or press its key)
and it disenchants the selected item: one click, one item, every time.

Made for **World of Warcraft: Forever**, for characters with Enchanting.

<!-- Screenshot: the main window with a queue, the selected item's expected materials and Shatter Next.
![The Shatter window: the Solo queue, the selected item's expected materials and value, and Shatter Next](https://raw.githubusercontent.com/Spotnick2/Shatter/main/docs/screenshots/main.png)
-->

## Install

Install **Shatter** from [CurseForge](https://www.curseforge.com/wow/addons/shatter) or
[Wago](https://addons.wago.io/addons/v63QE4Gb), with their apps or by unzipping it into the
`Interface\AddOns` folder inside your Forever game folder. Then start the game, or restart it
if it's running: the game finds a new addon only when it starts (`/reload` is enough for an
update). Type `/shatter` or click Shatter's minimap button.

## How it works

- **The Solo queue.** Shatter scans your bags and lists the weapons and armor Disenchant takes,
  uncommon and rare by default (Settings > Maximum quality: Uncommon, Rare or Epic). It rescans
  when your bags change. The list is in bag order, or first in first out, or last in first out
  (Settings > Solo queue order).
- **Shatter Next** disenchants the selected item. It's a secure button: one left click casts
  Disenchant on that bag slot, once, and nothing else. It does nothing for a right click, in
  combat, while you're casting, while another spell is waiting for a target, with full bags, or for
  a locked item, and says why.
- **A key for it:** Options > Keybindings > Shatter > Shatter Next. One press works like a click,
  and the key shows on the button. It does nothing while Shatter's window is closed.
- **Skip and Ignore.** Skip leaves the selected item out until a /reload. Ignore keeps it out for
  good: Settings > Ignored items lists those items, with Remove for each and Reset all (which asks
  first). `/shatter ignored` lists them, and `/shatter unignore <itemID or link>` removes one.
- **What it never queues:**
  - items the game won't let you disenchant: enchanter-made wands, PvP insignias and rank gear, some
    quest items. The list comes from the game's own item data;
  - soulbound items, unless you turn on Settings > Include soulbound items;
  - gear saved in an equipment set. A second copy of the same item outside the set is still
    queued.
- **Keeping possible upgrades.** Settings > "Keep items at or above item level" leaves items at
  or above that level out of the queue. Suggest fills it in from the lowest item level you have
  equipped (not the shirt or tabard), since nothing below it is an upgrade. Off by default.
- **Expected materials.** The selected item shows what it should give, each material with its
  chance and amount. The rates are Vanilla's, from Shatter's own tables, since Forever's are
  unpublished. Shatter also counts every disenchant whose loot window it reads, for the item's
  quality, armor or weapon, and item-level bracket. Once a bracket has 20, its estimate blends your
  results with the table, leaning on yours as they grow ("Expected Materials (measured, 20)").
  `/shatter yields` lists what it has measured, and `/shatter yields reset` clears it.
- **Item tooltips** show what an item disenchants into, wherever it appears: bags, bank, loot,
  chat links, vendors, the auction house. Settings > Item tooltips (or `/shatter tooltip`) shows
  them always, only while Shift, Alt or Ctrl is held, or never.
- **Values, with a pricing addon.** With [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
  and a scan, Shatter shows each item's expected value. An essence without a price of its own is
  valued from the other size of its tier (three lesser make one greater). Settings > "Filter queue
  by expected value" then offers these rules, all off by default. Without prices, none of them
  leaves anything out.
  - a minimum expected value;
  - "Only disenchant if worth more than vendoring": an item whose materials are worth no more than
    its vendor price is left out. When only some of its materials have prices, it stays in;
  - "Keep items worth at least N gold on the auction house": items to sell instead. An item with no
    auction price isn't kept, and neither is a soulbound one.
- **A summary.** Summary shows what you've disenchanted, skipped, ignored and failed since you
  logged in, and the materials it gave.
- **The look.** Shatter looks like the game's own windows by default (WoW Forever). Settings > Look
  (or `/shatter skin`) switches to Clear glass, Smoked glass or Flat, at once, even in combat. With
  Glass UI installed, Shatter follows its look unless you choose Flat; a change made in Glass UI
  applies after a /reload.
- **The window** resizes from its bottom-right grip. Shift-drag the grip to scale the whole
  window, right-click it to reset size, scale and position. In combat, opening, closing, moving and
  resizing wait until combat ends.
- **Settings profiles.** Settings are shared by all your characters (Global), or per character
  (Personal).

## Mail Mode (in testing)

For an enchanter who disenchants for others: they mail you their greens, you mail back the
materials.

- **At the mailbox**, Shatter's Mail panel opens beside it. Start a session for all mail or mail
  from one sender; with [Glass Mail](https://www.curseforge.com/wow/addons/glass-mail) or
  [Postal](https://www.curseforge.com/wow/addons/postal), also for the mails you ticked in its
  inbox. Choose where the materials go: back to each sender, all to one character ("Funnel to"),
  or kept.
- **A session lasts until you close it**, across mailbox visits and reloads. Shatter lists the
  attachments, takes them, and disenchants them with Shatter Next, crediting each item's materials
  to its sender. Your own items stay out of it, even an identical one, and a received item stays
  its sender's when you move or sort it.
- **Not yet on:** taking attachments and disenchanting mail items stay off until they're tested on
  the live game. `/shatter mailtest` turns them on until your next /reload, to try them.
- **Not built yet:** sending the materials back. Return them by hand.

Raid / Trade Mode (items received by trade) is planned, and its tab is a placeholder.

## Commands

`/shatter` (or `/shat`) opens or closes the window. The minimap button does the same; right-click
it for Settings.

- `/shatter scan`: rescan your bags
- `/shatter yields`, `/shatter yields reset`: the measured disenchants; clear them
- `/shatter ignored`, `/shatter unignore <itemID or link>`: the ignored items; bring one back
- `/shatter tooltip always|modifier|never`: item tooltips
- `/shatter skin forever|clear|smoked|flat`: the look
- `/shatter reset`: put the window back where it started
- `/shatter mailtest`: Mail Mode's actions, until your next /reload
- `/shatter help`: the list of commands

## Good to know

- **Only for enchanters.** On a character without Enchanting, Shatter stays off and says so. It
  turns on when you learn Enchanting, without a reload.
- **It never acts on its own.** Every disenchant is a click or key press of yours on Shatter Next,
  for one item.
- **The rates are Vanilla's** until your own disenchants correct them, and items above item
  level 92 show "Expected Materials (unverified)".
- **Forever is new.** Shatter's behaviour on the live client is being checked as players get in.
  If something doesn't work, a bug report helps (below).

## Bug reports and ideas

On [GitHub Issues](https://github.com/Spotnick2/Shatter/issues). With an error, turn Lua errors
on first (`/console scriptErrors 1`; they're off by default on this client) and paste the message.

## For developers

- **Tests:** `pwsh tests/run.ps1` (Lua 5.1, plus Python for the tools).
- **Deploy:** from a checkout, `pwsh Tools/deploy.ps1` copies the addon, with the LibGlass-1.0
  checkout next to it, into `_forever_\Interface\AddOns\Shatter`. A brand-new addon folder needs a
  full client restart once; after that, `/reload`.
- **Diagnostics:** `/shatter debug` and `/shatter trace` log what Shatter does. `/shatter sim`
  turns on simulation: fake results, no casting, nothing consumed, with a SIMULATION badge in the
  window; `/shatter simreset` shows the simulated items again.
- `AGENTS.md` and `SPEC.md` describe the design, and `CHANGELOG.md` the releases.

Shatter started as a TBC Anniversary addon; that version is frozen at the tag `v0.1.22-alpha`.

## Supported version

World of Warcraft: Forever, client 1.60.1 (Interface 16001).

## Author and license

By Spotnick. MIT (`LICENSE`). Shatter embeds LibGlass-1.0, also MIT, by the same author.
