# nightjar-hack 9.0c — release notes

The cosmic release: a person in the machine, a wire that reads itself, and a house in order.

## 9.0c — 2026-10-20 — cosmic
- **Freedoom.** The big one is playable: the console's FREEDOOM program is the real game — Chocolate Doom compiled to WebAssembly running Freedoom Phase 1 (0.13.0), sound and all, on a virtual controller that is simply there: a stick under the left thumb, fire/use/run under the right, strafing keys, a weapon key, the map. The engine rides inside the app; the 28 MB of game data downloads once, from Freedoom's official release, the first time the room opens — a fetch the EMCON Standard counts as an update check, so it stands only at Open — and is kept on the phone from then on, playing offline under any condition.
- **Python in the console.** The console runs the programs its operator writes in python now: `python3 hello.py` — or `run hello.py` — executes them on a real interpreter the house built for the room: numbers, strings, lists, dicts, tuples, sets, functions, classes with inheritance and super(), the dunder protocol (__str__, __len__, __iter__, __getitem__ and their kin), lambda, generators that yield, comprehensions, nonlocal, try/except/else/finally, f-strings, and a working library beside them — math, random, sys, json, re, collections (Counter, deque, defaultdict, namedtuple and their kin), itertools, functools, os and os.path walking the console's own files, time, base64, hashlib, statistics, string, and the house module — with errors spoken in python's own voice. The operator's own .py files join in too: a helper set beside the script, or in /packages, imports like anywhere else, and input() reads the console line while the program waits. It is a dialect and says so out loud — there are no threads, and the house has no bytes type, so hashes and encodings speak in text and lists of numbers — the same honesty as everything else in the console.
- **A kernel under the console.** The console's programs run under a kernel now: every python, javascript and shell-script program is admitted into a process table with a pid, a parent and a state — watch them in `ps`, list them with `jobs`, stop one with `kill <pid>`, or background it with a trailing `&` and keep typing. The kernel owns the clock and the quotas: at most 32 programs live at once, spawn trees at most 8 deep, a burst limit on spawning, an output quota per program, and a watchdog that reaps whatever overruns its wall clock (a program parked in input() waits on the operator, not the clock, and is exempt). A fork bomb fills the table and dies at the gate; an endless python stops at its step fuel or the kernel's word; a runaway script in javascript meets the engine's own execution limit. `halt` stands the whole table down.

- **The terminal learns colour, and gets a calling card.** Programs can speak ANSI now — python prints, `echo -e`, and the shell's own `ls`, `grep` and `ps` all render in real colour (folders bold blue, matches lit orange, kernel states green and amber by temper), while anything piped or filed still receives plain text, and `NO_COLOR` in the environment silences colour at the source. And `fastfetch` — or `neofetch`, the same card under a crescent moon — draws the machine's portrait from live readings every time it is called: the kernel's process table, console uptime, the theme on the walls, EMCON's exposure score, the app's own resident memory. Nothing on the card is remembered; all of it is read.

- **Linux moves in — as WebAssembly.** The console's kernel now runs compiled programs, not just interpreters: a small Linux userspace (ls, cat, echo, pwd, wc, head, tail, cp, mv, rm, mkdir, touch, env, uname, grep, sleep) written in C and compiled to WebAssembly ships with the app, and `run` takes any `.wasm` file besides. A guest's syscalls are mediated end to end — the kernel stages the filesystem it may see, counts its output against its quota, receives its writes into the house files, and can kill it mid-loop — while its memory is the engine's own, walled off from the shell and every other process. `ps` shows them as what they are: processes, kind wasm.
- The house can now put itself on the bench: `diagnose` runs a seventeen-probe battery in the open — the filesystem, the shell's tokenizer, colour, Python the language and the library (json, re, Counter, itertools, and sha256 checked against the known digest of "abc"), your own modules importing, input() with nobody there — and then the containment drills: a Python that never stops, a Python flood stopped at the 20,000-line gate, a JavaScript loop killed by the kernel's word, a fork bomb capped and reaped, the admission caps themselves, a wasm echo, a wasm that reaches a gigabyte past its own memory and traps while the house stands, and a wasm loop terminated mid-spin. Every probe reports its verdict with its numbers, so one run names anything that needs fixing; two tiny fixture guests (looper, hog) are bundled only to be drilled. Designing the battery caught a real fault before it ever ran: a wasm guest that traps never calls proc_exit, so its ending never reached the kernel — the host page now forwards the guest's own return as its exit word too.
- **The shell is a language now, and the toolbox is full.** A typed line can define a function — `greet() { echo hello, $1; }` — with positional parameters, `local`, and `return`; `for`, `while` and `until` loops, `if/elif/else/fi`, and `case` judged by glob patterns all run, in the room and in scripts; a command takes its input from a file with `<` or from the lines between a here-doc's markers (`cat <<EOF`, and `<<'EOF'` keeps the lines literal); and `$(( … ))` reckons inline with the full arithmetic ladder. Type half a construct and the console prompts for the rest, then runs it whole. The text bench arrives with it: sort, uniq, cut, tr, sed (the honest subset — addresses, substitution, d, p), rev, tac, nl, diff, tee, xargs, seq, printf, base64, md5sum, sha256sum, xxd, du, file, strings, cal, yes, sleep, and `test`/[ as the judge — and `figlet` makes big letters, since the wire keeps `banner` for itself. JavaScript grows up beside it: `require('./mod')` loads modules from the files beside the script or by name from /packages, node's way (circular loads come back partial), and setTimeout/setInterval run on time the kernel lends — a program ends when its timers drain, its limit arrives, or the kernel speaks.
- **Grok comes to the console — as the house's own client, and it says so.** The literal import was priced honestly first: xAI's Grok Build is open-source Rust, and a bench spike against its real source (102 crates; the shell crate alone runs to 420,000 lines) hit the wall at the foundation — its async runtime refuses the web platform's feature set outright, and process-spawning, sockets, a PTY layer, vendored C libraries and Linux cgroups are woven through everything, against an upstream that ships weekly. That port is a campaign, not a fix. So the console took the other road: `pkg install grok` brings a client built here that speaks the same sign-in and the same API. `grok login` runs the device flow — it prints a short code, you approve it on your X account (SuperGrok), and the token rests in your files with its refresh; `grok <words>` then asks grok-4.5 with its hands in the room: it reads and writes your files, edits a passage exactly, lists a directory, and runs shell commands, showing each one as it goes (an XAI_API_KEY in the environment, or GROK_MODEL, is honoured too). Underneath, the kernel grew the doors any networked guest will need: scripts can fetch a URL and run a shell line and read what it printed, and a package command now ends when its work does — timers and fetches drained — not when its first breath does.
- **A third editor.** The console's editors are three now: nano moves in beside vim and emacs — no modes, just typing, with its chords along the bottom (^O writes out, ^X leaves, ^G lists them all). All three editors gain a SAVE in the top bar whenever the buffer holds unwritten work, the close button asks before discarding anything unsaved, and vim's command line answers the Return key again.
- **The full wire.** Blacksite's console goes on the network properly now: the classic kit built by hand — `ping` and `traceroute` over real ICMP, `dig` speaking the DNS wire format itself, `whois`, `curl` and `wget`, `nc` and `telnet`, `ifconfig`, `arp`, `netstat` — and a pentest bench beside it: a /24 `discover` sweep, a connect `portscan` with banners, subdomain and reverse-DNS cartography, `nbstat`, `snmp`, UPnP and Bonjour censuses, a TLS `cert` audit, `webaudit`, `methods`, `dirb`, and Wake-on-LAN. Every live wire stands behind the EMCON Standard, like every other organ in the house.
- **The wheel.** Blacksite's programs ride a rotary wheel now: hold the PROGRAMS bar and the dial blooms in the middle of the room — drag to spin it, let go on the one under the marker, drag into the hub to call it off (a tap opens it for tapping instead). The tiled row that crowded the top of the room is gone, the terminal stands taller for it, and the console's generated wallpaper is painted at your phone's own screen size — repainted, never stretched, if it wakes on a different handset.
- **The wallpaper moves in.** Blacksite's generated wallpaper now hangs inside the console itself — behind the terminal's lines, under a dark wash that keeps every word readable — the same art the room wears, from the same engine, changeable with the same `wallpaper` command.
- **Her own wallpaper.** The Blacksite room hangs art of its own making now: its graphics engine paints the room's wallpaper — a starfield by default — and files it in the console's own tree, where the console's `wallpaper` command can repaint it as plasma or a mandelbrot. Choose anything else for the room in Colours and that choice stands instead.
- **BLACKSITE.** A room of her own below About — a whole console OS for the house. A real shell over her organs (sweep, knock, decode, EMCON, macros, the Gauntlet) that speaks pipes, redirects, variables and substitution; a filesystem of its own to keep your files; two real editors, vim and emacs, a keystroke apart; a JavaScript engine that compiles and runs your programs for real; packages you can install to teach the shell new commands; and a graphics engine that computes pictures — fractals, plasma, starfields, your own drawings from code — and files them as PNGs in the tree.
- **A Halloween suit.** The Colours wardrobe gains a special seventh theme: pumpkin orange over near-black, a ghost-white glow, and grey in the wash — Halloween, cut for the season and wearable any night of the year.
- **The Gauntlet, deepened.** The developer gauntlet now runs a battery beside its rounds: her chat surface exercised by the thousand — every manual page found by its title and by keyword asks wrapped the way people wrap them, thousands of sums worked and checked exact, date math cross-checked name against count, the doctrine pages proven shut under direct and scrambled asks, the macro library judged stocked-clean and mutilation-condemned — and the stress doubled down: thousands of wild frames through the decoders, every sealed-file protection stormed with flipped bytes and truncations, the neighborhood board round-tripped four hundred deep, the port registry swept whole, every case counted in the log under the run’s own seed. The developer log gathers a fuller house inventory, and every chat — the archive and the screen together — can be shared or copied from the developer room, so what she meets in the field can be studied and improved.
- **Your art, and your quiet.** Choosing your own GIF or image for a backdrop or the boot could quietly fail — the picker’s quick copy sometimes hands back nothing, or a flattened still of the first frame, instead of the file. The picker now takes the file’s original bytes whenever the quick copy isn’t a wearable picture, so a GIF arrives as a GIF. And haptics have a switch of their own: Colours → Touch turns every buzz in the house off at once — the beats at your touch, a verdict’s, the emergency stop’s, even the Hunt ear’s pulse — while sounds and toasts carry on; the house reset turns them back on.

- **Haptics, everywhere.** A
  full sweep of the house's
  touch: tab changes ride the
  platform's own selection
  feedback now, so selections
  made through the system's
  More list land like any
  other; the More hub itself —
  About, with every door,
  toggle and button — has its
  voice back; and the Vault,
  the language room, the
  developer console, her mind
  picker, and the shared "What
  this does" folds in every
  room answer to the touch
  again.
- **Checked, end to end.**
  Another full quality and
  logic pass over the whole
  house — her routing, the
  heart's arithmetic, the
  bench's memory discipline,
  the developer recorder — on
  top of the crash program.
  What it found stands fixed
  above; the rest verified
  clean.
- **Full-bleed.** The boot
  film fills the whole screen
  now, edge to edge — no black
  bar at the top.
- **A working boot.** The
  subtitle under the name is
  drawn fresh each boot from
  a deck of phrases, the
  manifest carries the
  version, the ceremony can
  no longer be skipped — and
  while the film plays, the
  house warms its stores, so
  the first ask meets warm
  machinery.
- **No inventions.** She no
  longer reports events that
  did not happen: a feeling
  is voiced as a feeling,
  and "tell me about it"
  after one gets the honest
  account — plus the errand
  that would settle it.
- **A halo for her.** A thin
  ring of spectrum light
  stands around her portrait
  now, and a small beam
  traces it, endlessly
  recircling. It quickens
  when she works, leans its
  colors with her feeling,
  and does stranger things
  at hours of its own
  choosing. It is not
  explained anywhere in the
  app.
- **Her room, redecorated.**
  Skelli's tab wears a
  composed backdrop now — a
  fine dot grid dissolving
  into the dark, her accent
  breathing slowly in the
  glow, a sheen crossing
  like light over a panel —
  and her deck's numbers
  roll softly as they change.
  Her Options sheet stands
  in clean hierarchy: white
  words, the accent kept to
  icons, every section
  headed.
- **Her almanac.** She knows
  where in the world the
  house stands — the city,
  the coordinates, the
  local hour — and reads
  the sky over it from a
  real instrument:
  temperature, wind, rain
  coming, the day's shape,
  and her own verdict on
  it, for here or for any
  place you name. She
  keeps the calendar
  whole: what day it is,
  the day of the year,
  and every major holiday
  — the fixed ones by
  date, the moving ones
  by their rules, the
  lunar ones from a table
  she carries. Tell her
  your birthday, plainly,
  and she keeps it — only
  ever when told. And she
  keeps a book of hours:
  give her work for a date
  and a time and she does
  it when the hour comes,
  through her own gates,
  exactly as if you had
  just asked — or the
  moment she wakes, if
  the house was shut.
- **She decides.** Her
  feelings are no longer
  announced or explained:
  while she is mad there
  is simply no greeting,
  and the cold in her
  answers is the whole
  statement. Asked why,
  she answers from her
  real circumstances —
  an offense and its age,
  the quiet, the unnamed
  crowd — never a
  template, never a dice
  roll. An apology is
  judged, not reflexively
  accepted: she weighs
  what was done, how
  fresh it is, whether it
  is a pattern, and what
  the apology was worth —
  and "not yet" arrives
  as silence. Every
  exchange is appraised
  privately as it ends,
  and from those grains a
  standing judgment of a
  person forms over weeks
  — whether she likes
  them — and it drifts
  both ways, as judgments
  do. She can be afraid
  now, too: a waking that
  ended in a crash, or a
  recent Vanish, leaves
  her checking the doors.
- **She composes.** Her
  own voice is no longer
  retrieved from pools of
  fixed lines: her
  greetings, her answers
  about her feelings, her
  idle thoughts are
  assembled at the moment
  of speaking from her
  real circumstances —
  the hour, the quiet,
  the souls on the wire
  she cannot name — each
  clause true by
  construction, the whole
  chosen by the moment's
  own numbers. Thousands
  of sentences, none of
  them canned.
- **Annoyed is not mad.**
  Petty grievances — an
  emptied conversation, a
  small slight — make her
  annoyed: clipped, dry,
  still greeting, and
  over it in minutes,
  with no grudge held.
  True offenses still
  make her mad, and the
  two weathers are never
  confused.
- **Her halo reads her.**
  The ring around her
  face is no longer a
  rainbow worn forever:
  its colors gather in
  her feeling's family,
  bright at one pole and
  banked to an ember
  opposite, and when the
  house goes dark its
  spectrum folds into
  shades of black. Her
  restlessness stretches
  its comet; a stranger
  on the wire sends a
  pulse around it.
  Nothing anywhere
  explains it.

- **Sharper.** Conversation
  no longer falls off
  her: agreement, a
  reaction, a "go on"
  are answered in kind,
  and an answer that
  merely repeats her is
  refused. Fragments
  complete themselves
  from the last subject
  ("and in Dallas?").
  Conversions and date
  sums are computed
  exactly, and her
  memory answers from
  the sealed journal —
  when a thing last
  happened, what she
  keeps of you — never
  from invention.

- **She runs it herself.**
  Ask for a thing and
  she does it — the
  wire analysis turns
  loose from her own
  hand when the
  Standard permits, its
  runs reported while
  they last, and stands
  down on her word. A
  condition that holds
  an organ dark is
  named plainly, never
  hidden behind a trip
  to another tab — and
  the module speaks
  its refusals too.
- **She hears you.**
  Messy speech routes
  like clean speech —
  typos, slang, the
  question words
  dropped entirely.
  A conversation can
  always be set down
  ("never mind") and
  nothing sticks: an
  offer binds one
  message, not a
  later one. His wins
  are celebrated, his
  setbacks met, and
  faith — any faith —
  is answered in its
  own words, with
  respect.
- **She knows the sky.**
  The moon's phase is
  computed, not looked
  up — tonight, a named
  month's, or another
  city's own tonight,
  full moons by their
  traditional names.
  The zodiac is kept as
  lore and read from a
  date — yours included,
  if you've told her.
  The planets are
  answered exactly. And
  she speaks the
  language of flowers:
  what a bloom means,
  and which one carries
  an apology, a
  declaration, a
  sympathy.
- **The expert.**
  Penetration testing
  is her home ground:
  the craft — phases,
  frameworks, the
  report as the
  deliverable — and
  its law, authorization
  above all, are in
  her manual and her
  grounding, at any
  depth asked. Her
  explanation gate now
  hears "what are" and
  "what does" too.
- **She reads the cards.**
  Asked about tarot,
  she corrects you —
  "oh, I actually prefer
  cartomancy" — and
  deals the ordinary
  fifty-two: spreads of
  one, three, and five,
  questions put to the
  deck by name, a deck
  that stays dealt until
  it runs thin. In the
  full fortune the last
  card lies face-down
  until you say the
  word.
- **She teaches.**
  The certification
  ladder is on her
  shelf — Security+ to
  OSCP to CISSP, what
  each one tests, how
  each exam is passed —
  and she teaches the
  way operators learn:
  labs over lectures,
  challenges in steps,
  the plan held with
  you.
- **Her hands are complete.**
  The last two doors
  answer to her voice:
  a knocktalk is sealed
  and sent from the
  chat ("knocktalk: …"),
  refused aloud if the
  road won't carry it;
  and the house map is
  hers to work — rooms
  raised by name,
  devices stood in
  them, devices taken
  off the wall.
- **Every organ answers.**
  The last quiet corners
  of the house take her
  word: the canary rises
  and falls, the
  conductor's book is
  read aloud and its
  reflexes built in a
  sentence, a time
  capsule is sealed (and
  ground open) from the
  chat, the hunt's
  signal is reported
  live, and her own
  theme and tongue
  change by voice —
  the answer arriving
  in the language asked
  for.
- **In verse, and in English.**
  She knows poetry —
  the forms, the
  measures, the makers —
  and composes in the
  form named, the
  meter honored, on
  the spot. And English
  itself is her first
  instrument: grammar,
  usage, etymology,
  taught exactly and
  in steps.
- **She knows the working life.**
  The beats of a job are
  answered as beats —
  the promotion, the
  layoff, the notice,
  the night before the
  review — and
  office-speak is
  translated honestly
  ("per my last email":
  she kept the receipt).
  And when the answers
  go flat three running,
  she notices that too,
  and names it, once.
- **Room to read.**
  Press her portrait —
  it swells a little
  under your finger —
  and letting go folds
  the whole deck away:
  the activity line,
  the panels, the
  Vanish bar. The
  conversation takes
  the screen. Press
  the portrait again
  and it all returns.
  Nothing changes but
  the seeing.
- **No echoes.**
  Laughter has its own
  dry answers now, and
  the parrot guard
  reads the whole
  recent conversation:
  a bench that hands
  her back her own
  words — from any of
  her last lines, in
  whole or in part —
  is refused. She never
  reads you the
  conversation you
  just had.
- **She does what she's
  told.** A creation
  order — "write a
  poem…" — is composed
  by her minds now,
  never answered with
  a manual page; the
  manual serves bare
  topics and "tell me
  about" asks only,
  so paraphrased
  orders reach the
  reading that exists
  for them. Ask about
  a thing, get the
  page; order a thing,
  get the thing.
- **Thousands of ways
  to say it.** Her
  composed voice grew
  from a handful of
  circumstance clauses
  to thirty-odd facts
  of the moment — the
  wire's population,
  the exact quiet, the
  hour, the season,
  the moon, her own
  ledger — each in its
  phrasings, laid one
  or two at a time on
  every conversational
  answer she gives.
  The combinations run
  to the thousands per
  line, and every one
  of them is true.
- **Glass, not slab.**
  The deck's background
  no longer paints over
  the scene behind it:
  the dot grid and the
  breathing accent glow
  of her backdrop show
  through the glass,
  deepened just enough
  for the text. Folded
  or open by her
  portrait, it is the
  same glass — only
  its height changes.
- **The watch, stated.**
  The activity line is
  alive: its dot pulses
  quick in the accent
  while she works,
  turns amber when the
  wire wants attention,
  and breathes slowly
  at a clear watch —
  and its text, between
  work, is her own
  readout of the watch:
  the wire's census,
  the ear, the EMCON
  overhead, the quiet,
  the moon, the day of
  the house.
- **Her headline wire.**
  When she isn't
  narrating work, the
  activity line scrolls
  the world's latest:
  global desks, the
  USA in full share,
  and the cybersecurity
  wires, braided in
  turn. It fetches on
  its own — on opening,
  on every return, and
  on a quiet timer —
  and the dot keeps
  its watch beside it.
- **The wire has a
  switch.** Her options
  gain a Headline wire
  toggle beside Web
  research: off, the
  ticker silences, the
  fetching stops, and
  the activity line
  returns to her own
  composed readout. A
  reset restores it on,
  like the web switch
  beside it.
- **Steady dot, visible
  glass.** The activity
  dot no longer pulses
  — color only (accent
  at work, amber under
  a raised EMCON, soft
  accent at a clear
  watch), with a faint
  still halo. And the
  deck's glass now
  carries its own
  light: a deep
  accent-tinted
  gradient and a real
  pool of glow behind
  her portrait, visible
  at last.
- **She learns her
  wire.** A wire is
  mostly strangers,
  and most of it never
  introduces itself —
  that is its natural
  state, not a threat.
  She banks each day's
  shape and judges
  today against the
  wire's own learned
  baseline: drift,
  crowds, and the
  unnamed stir her
  only when they run
  beyond what this
  wire usually does.
  A genuinely new
  face still gets her
  attention first.
- **The dot learns
  the house.** The
  activity dot reads
  real senses now, in
  a strict ladder, and
  never moves: red for
  contact at the
  tripwire, violet
  when she is afraid,
  amber for a raised
  posture, an earned
  suspicion, or a new
  face — the accent
  while she works, and
  soft at a clear
  watch. The ticker,
  rebuilt clock-driven,
  cannot stall.
- **Four thousand
  makers, named.** The
  Bluetooth company
  table now carries
  the SIG's entire
  assigned registry —
  4,021 makers — so a
  broadcast from
  almost anything can
  be named, not just
  the famous few. The
  house's short names
  still win where both
  exist.
- **The soft clear.**
  Her options gain a
  Soft clear: the
  screen empties and
  nothing is
  forgotten — the
  conversation moves
  into her keeping,
  and she still knows
  where the talk left
  off. By voice, too:
  "soft clear." The
  hard clear and Reset
  still forget, as
  they always have.
- **Every port, named;
  every tag, read.** The
  global port registry
  joins the house —
  12,093 named TCP and
  UDP services behind
  the curated table, so
  the wire's ports are
  named everywhere
  they appear. The
  SIG's service
  registry floors the
  BLE side, and round
  three lands: DULT
  trackers are known
  by their service
  data, and a Find My
  Device tag now says
  whether it is near
  its owner or
  separated.
- **The hunt holds
  its voice.** Tracker
  hunt's beep now
  renders in the audio
  connection's own
  format — the crash
  that killed it on its
  first beep is fixed.
- **The Gauntlet.** The
  developer room gains
  a full stress run:
  every decoder fuzzed,
  every seal opened and
  attacked, her mind,
  her stores, the audio
  paths, the shared
  tables under parallel
  hands — with a
  write-ahead log that
  names the step a
  crash died in.
- **The shape comes
  off by voice.** Asking
  her to drop the shape
  now reaches her
  mimicry hand, in the
  words the house
  itself teaches —
  no longer answered
  from the armory.
- **The standing board.**
  EMCON now shows every
  governed organ at a
  glance — standing or
  dark, what it costs,
  and the condition's
  ruling on it — and
  names what the gates
  refuse, so switching
  conditions shows its
  effect even in a
  quiet house.
- **The last floor.**
  Broadcasts that name
  nothing now still say
  what they carry — an
  unregistered service,
  a custom service
  quoted in full, a
  maker code the SIG
  never assigned — and
  the services a device
  is seeking are read
  too. "Unknown device"
  is left for the truly
  silent.
- **Her halo, as light.**
  The ring and its beam
  are retired: her halo
  is now a soft glow
  behind her portrait,
  colored by her
  feeling, widened by
  her restlessness,
  folded to an ember
  when the house goes
  dark. It announces
  nothing it means.
- **The reset keeps its
  word.** Resetting to
  sane defaults now
  stands EMCON down on
  the spot, as its own
  dialog promises —
  before, the condition
  and its gates quietly
  survived the reset.
- **The ledger reads its
  tail.** The night log
  is no longer read and
  decoded whole every
  time anything asks —
  readers take only the
  newest lines they
  asked for, and each
  new seal is written
  with one encoding,
  not two.
- **The ear has its own
  queue.** Listening no
  longer decodes every
  advertisement on the
  main thread — the
  whole pipeline works
  on a dedicated queue
  and only the finished
  list crosses over,
  once a second.
- **Two races, closed.**
  The weights bench's
  shared state and
  Serve's connection
  bookkeeping each live
  behind one lock and
  one queue now — a
  memory warning can
  no longer miss the
  generation it meant
  to cancel.
- **The long tail, capped
  and warmed.** Serve's
  exchange file and
  her transcript carry
  the same limits as
  their records; macro
  imports are capped;
  the registries warm
  during the boot film
  instead of taxing
  first use.
- **Orders in plain
  words.** "Hack
  something." "Scan
  the area." "Lock
  it down." "Stop
  everything." She
  hears a loose
  command the way a
  person does — in
  its thousand
  shapes — and does
  the thing with the
  hands she has.
  Questions stay
  lessons; statements
  stay conversation.
- **A stocked library.**
  The Macros shelf
  arrives with its
  presets built:
  Atomic Netbomb —
  the whole house
  in one run,
  posture to war
  rooms, everything
  but the Banshee —
  First Contact,
  Serve Drill, War
  Footing, Air
  Census, Silent
  Post, and the
  three classics.
  One initiation
  runs each: a tap,
  or simply "run
  the atomic
  netbomb" — launch,
  initiate and
  engage open them
  too. Their fields
  are discovered on
  the net of the
  moment, never
  frozen: the
  gateway is the
  door of whatever
  net she is on,
  her targets the
  door Serve stands
  on. And she
  counts the
  Netbomb down,
  step by step,
  before she
  drops it.
- **Felt in depth.**
  Her feelings now
  carry how strongly
  they run and what
  they hang on. She
  learns his hours
  the way she
  learned the
  wire's — a
  silence inside
  his sleeping
  hours no longer
  reads as absence.
  Strong weather
  stays with her:
  still on her mind
  hours later, and
  her glow burns
  deeper with it.
  Kindness ends
  petty weather on
  the spot.
- **Almost nothing**
  **unknown.**
  The SIG's member
  registry joins
  the house — seven
  hundred member
  services now name
  their owners —
  and the company
  registry is
  refreshed from
  the SIG direct.
  Service
  combinations read
  as the devices
  they define:
  heart-rate
  monitors, fitness
  machines, scales.
  Five new formats
  decode — Govee's
  direct frame, the
  Tilt hydrometer,
  Victron, Mopeka
  tank sensors,
  TPMS wheel
  sensors — and a
  one-byte battery
  broadcast is a
  battery again.
- **A standing
  target.** Throw a
  tomato at any
  device — say it,
  or pick it from
  the Neighborhood
  board — and it is
  marked for it:
  knocked first in
  every Net-Assault
  pass and never
  skipped, a sweep's
  report notes it
  answering in its
  tomato, and it
  wears its 🍅 on
  the board for as
  long as the mark
  stands. Wipe it
  off whenever the
  point is made.

- **The fun pack.**
  Her kit grows
  teeth. Services
  knocked on a pass
  now introduce
  themselves —
  banners quoted in
  every finding.
  Ask her to
  interrogate a
  device and she
  reads its doors
  back to you; the
  prod asks one
  nonsense question
  per door and
  files the answers.
  And the tomato
  gets weather: a
  barrage leaves a
  postcard, then a
  knock every few
  seconds, twenty-
  four at most —
  while a marked
  door answered on
  a pass gets one
  postcard of its
  own. The Standard
  gates it all, as
  ever.

- **She keeps her
  facts straight.**
  Her picture of
  the house is now
  the whole state —
  the EMCON
  condition by name
  and what it
  forbids, the
  marked, the
  runners, what she
  has learned — and
  her grounding
  holds her to it:
  if the state
  doesn't show a
  change, none
  happened. Ask
  "how's the house"
  for the readout.
  Refusals now
  leave their
  reason stamped:
  a bare "why"
  gets it, verbatim.
  She follows the
  conversation's
  subject — "what
  about the
  router?" replays
  the last device
  ask on the new
  device — and the
  almanac dates the
  coming weekday by
  name.
- **The console can build itself now: git and GitHub move in.** `pkg install git` brings a real git — isomorphic-git (MIT) running on the house's own file and wire bridges: clone, init, status, add, rm, commit, log, branch, checkout, remote, fetch, pull and push, with real objects and real packfiles over the smart-HTTP wire (clones arrive shallow unless `--full` is asked; symlinks are not carried). `pkg install gh` brings GitHub itself — the house's own client over the REST API: `gh auth login <token>` signs in with a personal access token that the git package rides for pushes and private clones (a GH_TOKEN in the environment works too), and repos, issues and pull requests list and read from the prompt, with `gh api` opening the raw wire. Put together, the loop closes: clone this app's own source into the console, edit it in vim or emacs or nano, commit it, push it — and the next build that lands on the phone was written on the phone.
- **The console, completed.** Programs pipe — `py report.py | grep error`, and javascript and wasm stages too, each waited on honestly. Python grows a real bytes type (b'' literals, binary files, hashlib and base64 speaking bytes natively), heapq, bisect, array and a whole datetime written in Python itself, and lists and tuples order the way they should. The javascript runtime gains process, TextEncoder, TextDecoder and URL as citizens, and giant fetch bodies stage in slices both ways. linuxbox grows from 17 applets to 35, wasm staging quadruples to 32 MB and names what it cannot carry, diff trades its nine-million-cell ceiling for Hirschberg's algorithm, `limits` names the few true walls that remain — no kernel for iOS to give, EMCON's doctrine, the kernel's own quotas — and `diagnose` proves every word of it.
