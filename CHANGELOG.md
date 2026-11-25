# Changelog

## 0.1.29 — November 25, 2026

On Windows, Now Playing looks and works like the Mac's, and Notchy's Christmas music stays on it.

- **The Christmas music stays.** The Now Playing button opens the player with Notchy's Christmas music on it, as on the Mac. Windows used to take Notchy's own music for another app starting, and the music stepped aside by itself a few seconds in, leaving an empty card.
- **Volume in the notch.** A bar under the controls sets your PC's volume as you drag it, and the speaker beside it mutes and unmutes. There is no bar when the PC has no sound output.
- **The Mac's player.** Title and artist at the top, volume at the bottom, the buttons at the Mac's size and without hover circles, the real icon of the app that is playing in the corner (Notchy's own for the Christmas music), titles without " - Remastered" or "(Live)", Mochi dancing while it plays, and black cards. The Christmas album leans like the Mac's and its cover is sharper.
- **A second click on the Now Playing button brings up the app that is playing.** A song starting brings up the notch without a sound.
- **New versions, from the notch.** Notchy looks for a new version every hour, and when there is one the notch says so: *Update now* downloads it, installs it and restarts Notchy; *Later* leaves it for now.
- On Linux, Now Playing still reads nothing, so the player and its volume do not show there.

## 0.1.28 — November 25, 2026

What a client sends you can now be copied straight from the notch and pasted anywhere: their words, their photo, their voice message, their PDF.

- **Click it, it's copied.** A click on the message's text, its photo, the photo's caption or a voice message's transcript copies the message, and "✓ Copied" shows beside it for a moment. A **Copy** button beside Open does the same.
- **Exactly what was sent.** Words go as they were written, never the "📷 Photo" or "📎 Sent a file" the card shows. A photo goes whole, the original, the right way up. A voice message goes as the audio file, named for the format it really is. A PDF or any other file goes under its own name, and every photo of an album goes together.
- **To see a photo whole,** use the ↗ in its corner, now that a click on the photo copies it.
- On Windows the clipboard takes one kind of thing per copy: words as text, a photo as the image, a voice message or a PDF as the file. An iPhone photo (HEIC), a WebP or a GIF goes as the file. On the Mac a photo also brings what was written with it, and a voice message its transcript, for places that only take words.

## 0.1.27 — November 24, 2026

A photo someone sends you on Mattermost now shows in the notch, instead of "Sent a file".

- **The photo, in the notch.** The card grows to show it, and is the right size as soon as it opens. While the photo loads, a blurred preview stands in for it. A tall photo sits in the middle of the card, so it lines up with the name, the text and the reply box like any other message.
- **Click it to see it whole.** The original opens in your image viewer.
- **What came with it.** Text sent with the photo shows underneath, in up to two lines, or all of it if you show whole messages. When there are more photos, a "+2" (or however many) on the corner says so. The pill, the list and the notification say "📷 Photo", or show the text.
- On Windows, an iPhone photo (HEIC) that the server did not convert shows as a placeholder, because Windows cannot draw it there. A click still opens it.
- **On the Mac, since 0.1.22:** water and the calendar moved out of the island's header onto round buttons around the island, which you can rearrange in *Settings → Dynamic Island*; and *Settings → General → Behavior* has a *Never* button beside "Hide after … s without movement", in place of the *Always visible* checkbox.

## 0.1.26 — November 23, 2026

On Windows, Notchy is much lighter on your PC while you are not using it, and looks and works exactly as before.

- **Less CPU at rest.** The clipboard history no longer reads the clipboard twice a second: with a screenshot on it, Notchy was decoding the whole image every time. Now Playing no longer reconnects to Windows' media controls every second either. Measured on a Windows machine, Notchy's own CPU at rest went from 1.46 % to 0.05 %, and the app with all its parts from 1.91 % to 0.16 %.
- **Half the processes.** ChatGPT and WhatsApp each run a browser of their own, and both used to start with Notchy for everyone. They now start the first time you use them, so anyone who does not has 13 processes instead of 25 and about 100 MB less in use. ChatGPT's closes again ten minutes after you leave it; you stay signed in.
- **The snow costs less to draw,** with exactly the same flakes, and the island's own animations stop while it is folded.
- **The Christmas music lets go of its player after five minutes paused,** and picks up where it stopped when you press play.

## 0.1.25 — November 23, 2026

On Windows, ChatGPT and the site open inside the island, as on the Mac, and the island's header icons are the Mac's.

- **ChatGPT inside the island.** The chat tab opens ChatGPT in the island itself, dark, under the Mac's row with Mochi, reload and close, instead of in a window of its own. You can type in it straight away; Escape, either X or the close shortcut puts it away and gives the keyboard back to the app you were in. ChatGPT keeps its own sign-in now, as on the Mac, so it asks you to sign in once more.
- **The site inside the island too,** with its own row: back, reload, open in your browser, close. It shows while it loads, links stay in it, and it never takes your keyboard.
- **The Mac's header icons.** The gear, the timer, the speaker and the rest are drawn as the Mac draws them, at the same size and spacing, and the tabs no longer click when pressed.
- **Fixed:** clicks on the island could do nothing while the keyboard disappeared into hidden windows; a video going fullscreen in a page could stretch the island over the whole screen; typing could land in a field that was no longer on screen; a reply could mark the wrong message as read.
- **Safer pages:** only a link you click can open your mail or phone app, an address the app cannot read is refused, and the app's own windows can no longer be shown inside a web page.
- On Linux, ChatGPT and the site are still windows of their own, laid over the island.

## 0.1.24 — November 22, 2026

Water and the calendar moved out of the island's header, on Windows as on the Mac.

- **Water and the calendar hang under the island.** They are round buttons below the open island now, beside the others around it, instead of tabs in its header. Water opens the Hydration card, the calendar opens the Agenda. The timer stays in the header.
- **You can move them.** They are in *Settings → Dynamic Island* with the other buttons around the island: put them left, right or underneath, or take them off.
- If you had already arranged the buttons around the island, the two are added underneath once. The calendar shows only while the Agenda is on, as its tab did.

## 0.1.23 — November 22, 2026

On Windows, Settings is now the same window as on the Mac.

- **The Mac's Settings, on Windows.** Settings is no longer one long dark page. It is the Mac's window, with a sidebar: General, Active pills, Dynamic Island, Chat, Integrations, Characters and Hydration. Each pane has the Mac's rows, in the same order, with the same controls and the same words. It follows Windows' light or dark mode.
- **It opens out of the island's way.** Settings opens on the display the island is on, folds the island first, and stays clear of it. The island's gear, the integrations card and the hydration card each open it on their own pane.
- **Home starts on Notifications**, as on the Mac. If you were on the old default, *Automatic*, you move to Notifications; pick Automatic again under *Settings → Active pills → Home shows*.
- **Standby is gone.** If you had it on, it is now off. *Never*, beside "Hide after … s without movement", stays.
- **A new install no longer starts with Windows** until you turn it on, as on the Mac. An install that already starts with Windows keeps doing so.
- **ChatGPT and the site load when you open them.** They used to load in the background every time Notchy started, whether you used them or not.
- WhatsApp now remembers that it is linked. Before, it forgot within seconds of the QR code window closing.
- On the Mac, *Settings → General → Behavior* now has the same *Never* button beside "Hide after … s without movement", in place of the *Always visible* checkbox.

## 0.1.22 — November 19, 2026

The welcome's Mochi notices you, and every Mochi gets dressed there.

- **A Mochi that reacts.** At the top of the welcome Mochi now follows your pointer, leaning toward it as one piece so his face never slides off, widens his eyes when you hover over him and sends hearts if you stay, and gets cross — then dizzy — if you click him three times, as he does on the island.
- **Every Mochi, in the welcome.** The look screen now dresses everyone: the default and each pill's own Mochi, in that pill's colour (Now Playing, Mattermost, Ato, WhatsApp and Notifications), with tabs for the face, the body and — until January 6 — Christmas: twelve ready-made outfits, and every hat, pair of eyes, texture and extra on its own. Picking a face takes the Christmas outfit off, so the face you pick is the face you see.
- The welcome window is a little taller to fit it. *Settings → General → Show the welcome again…* opens the new one.

## 0.1.21 — November 19, 2026

Mochi learns your name.

- **A welcome before Notchy opens.** The first time Notchy starts — and once more after this update — a short welcome comes first: Mochi says hello and asks what to call you, which language to speak, which look to wear, what to keep an eye on, and whether to start with your computer and play sounds. Every choice is saved as you make it, so *Skip* keeps whatever you already picked. *Settings → General → Show the welcome again…* brings it back.
- **Good morning, by name.** The hello the island plays when Notchy starts now says it under Mochi: *Good morning*, *Good afternoon* or *Good evening*, by your clock and in your language.
- **Your name, in Settings and in the chat.** *Settings → General → Your name*. Left empty, Mochi uses the first name on your account. The chat calls you by it too.

## 0.1.20 — November 19, 2026

Mochi reminds you to drink water.

- **A glass you tap, in a tab of the island.** A new drop tab shows today's water: tap the glass each time you drink and it fills, with the count beside it. Choose the size of a serving (150, 250, 350 or 500 ml), undo a tap, or remove one of the last logs. On this card Mochi is made of glass and fills up along with it.
- **A reminder now and then.** During the hours you say you are online, the island opens with "How about some water?" and two answers: *I drank 250 ml* or *Later*. Every log restarts the interval, so it stays quiet while you are already drinking. It waits for a focus timer to end and for anything that is waiting on an answer, has quiet hours and a pause, and stops for the day once the goal is reached.
- **A goal that is an estimate, not a prescription.** Eight quick questions, every one of them skippable, suggest a daily amount to start from; Settings shows how the number was reached and which public references it leans on, and says plainly that no health professional has reviewed it. For pregnancy, breastfeeding, a kidney, heart or liver condition, a diuretic, a doctor's guidance about fluids or anyone under 18 it suggests nothing: you type your own number, as a target to reach or a limit not to pass.
- **Days that freeze.** Reach the goal and the day freezes: the card shows the week and how many days in a row. A missed day spends a rest day — you earn one a week — instead of ending the streak.
- **Off until you turn it on.** Click the drop tab on the island, or open Settings → *Hydration*. Nothing about it leaves your computer.

## 0.1.19 — November 19, 2026

Voice messages from Ato, heard and read on the island.

- **An Ato voice message shows as one.** A customer's audio used to arrive as "[anexo]". Now the card says it is a voice message and gives it a player: play and pause (pausing keeps your place), back and forward by the same seconds as the music player, and a bar you click or drag to jump to any point.
- **The transcript, right under it.** When Ato has transcribed the audio, what the customer said appears below the player, in a box you scroll to read the rest — so you can listen, read, and answer from the same card. While Ato is still transcribing it says so, and the text appears on its own when it is ready. The list, the pill and the notification show the transcript too.
- Listening keeps the card open, and a new message waits until you are done instead of replacing the one you are hearing.

## 0.1.18 — November 19, 2026

Your meetings from the commercial panel, and Christmas music.

- **Agenda: today's meetings in a tab of the island.** For anyone at Actuar: turn it on in Settings → *Agenda* and a calendar tab appears beside the timer, listing today's client meetings from the commercial panel (Onboarding and Backoffice) where you are the responsible person — the time, the customer, the case code, which connection and which attempt, and how long until it starts. A click opens the meeting in the panel. It uses the Actuar account saved under Ato, so there is no second password, and it is off unless you turn it on.
- **A heads-up before each meeting.** The island opens on the Agenda with the meeting marked, 15 minutes before it starts by default (5, 10, 15, 30 or 60 in Settings), and only for the processes you pick. A meeting that was moved or cancelled in the meantime is not announced, and none is announced twice.
- **Christmas music, until January 6.** Notchy plays vintage Christmas songs as it says hello at launch, and a Christmas album sits beside the player's artwork: click it to bring the music back after another app took over. The switch is *Christmas music when Notchy starts* — Windows and Linux: Settings → General; Mac: Settings → Island → Christmas.

## 0.1.17 — November 18, 2026

It snows on the island.

- **Snow on the island, until January 6.** A little snow comes down across the island and settles along its bottom edge, on the resting bar and on an open card alike. The bank gets deeper while the island stays open and thins again when it closes. The flakes are faint and can only lighten what is under them, so nothing you are reading is ever covered, and none of it takes a click.
- **Sweep it with the mouse.** Pass the pointer through the snow on the floor and it ploughs a furrow, heaps a mound ahead of itself and throws a few flakes; leave it alone and the furrow fills back in.
- **On by itself from November 15, and it has a switch.** Windows and Linux: Settings → General → *Snow on the island*. Mac: Settings → Island → Layout. The switch is only there while the season is, and with the system set to reduce motion the snow lies still and nothing falls.

## 0.1.16 — November 17, 2026

Mochi in its corner answers the mouse again on Windows.

- **The resting bar opens when you point at it.** With **Never** on — Settings → General, beside *Hide after* — Mochi rests as the compact bar in its corner, and resting the mouse on it opens the island. On Windows that bar could stop answering after the island had closed a few times: the mouse went straight through it to whatever was behind, and only a message brought the island back. It now takes the mouse every time, and puts itself right within half a second if anything ever leaves it otherwise.
- **Turning Never on while Mochi has folded away brings the bar straight back**, on Windows and Linux. The corner used to stay empty until the mouse found it.

## 0.1.15 — November 17, 2026

Mochi dresses for Christmas, and the island closes when you tell it to.

- **A Christmas wardrobe, for every Mochi and for Ato.** Settings → Characters gains a Christmas section from November 15 to January 6: eleven things for the head (Santa hat, elf hat and ears, antlers, a star, a halo…), nine pairs of eyes including two novelty glasses, seven textures, eight extras — a beard, a string of lights that really blinks, a scarf, falling snow — and twelve ready-made outfits. Each one is fitted to every body, the frog included, and Ato can wear them too. What you had chosen before is untouched, and a character still dressed in February keeps its outfit.
- **Close the island yourself.** An X at the far right of the island's header closes whatever is open; the message stays unread. Settings also offers a keyboard shortcut for it, off by default, with Ctrl+Alt+X (⌃⌥X on the Mac) filled in.

## 0.1.14 — November 16, 2026

Ato on Windows and Linux, as on the Mac.

- **An Ato card wears Ato.** On Windows and Linux the island took its face from whichever pill was clicked last, so an Ato message arriving while Now Playing was in focus came up with Now Playing's Mochi. It now goes by what the island is showing, as the Mac does: Ato's card and list wear Ato.
- **Mochi dances on Windows and Linux too, Ato included.** With something playing and the Now Playing pill on, the character hops and sways to the beat with happy eyes, when the island is folded or showing the player — the same dance as on the Mac.

## 0.1.13 — November 16, 2026

Ato messages reach the notch again.

- **A conversation you are answering is yours.** When a customer writes back after a pause, Ato's bot sends the conversation through its menu again and leaves it unassigned in whatever queue they pick — so the reply to a conversation you were in the middle of went to nobody. Notchy now counts any conversation you replied to as yours until a colleague takes it or it closes, including replies sent from Ato itself or before Notchy was running.

## 0.1.12 — November 16, 2026

Ato takes over from ClickMassa, and WhatsApp comes to the notch.

- **Ato, Actuar's support inbox, is a message source** on the Mac and on Windows. Sign in with the Actuar account you use on novo.actuar.com; a customer writing on a conversation assigned to you, or waiting in one of your queues, opens a card you can answer from. Listening does not change your status in Ato.
- **Answer Ato with files and voice messages.** The paperclip and the microphone now work on an Ato card, as they already did for Mattermost.
- **WhatsApp in the notch.** Turn the WhatsApp pill on and link it once with the QR code in Settings, as you would WhatsApp Web. New messages open a card you can answer from — words, images, files and voice notes — without anything being marked read before you reply.
- **Ato is Ato's own mascot.** The orange, cyan and blue orb from novo.actuar.com and the Actuar blog, drawn by a port of Actuar's own engine: the three layers turning against each other, the dot eyes, the blink, the wink and hop every few seconds. It takes Mochi's place wherever the Ato pill would put him — the pill, the island while Ato has it — and reacts: a badge for a waiting message, grey when Ato is unreachable, a welcome when it reconnects. The ring and Settings show it still, and its colour is Actuar's blue.
- **Ato reacts like every Mochi.** Its eyes follow the pointer in every state, not only at rest. Hover over it and it gets heart eyes, Actuar's pink cheeks and hearts floating up. Click it and it squints with line eyes; three clicks make it dizzy, with spiral eyes. It dances to music, and in the pill it looks around like the other minis.
- **ClickMassa is gone.** Its pill becomes Ato's in the same slot, a Home pinned to it follows, and the password it kept is deleted from the Keychain and the Credential Manager.

## 0.1.11 — November 2, 2026

Answer by talking, and read the whole message where it arrived.

- **Reply with your voice.** The notch's reply bar has a microphone beside the arrow. Hold it, say what you meant, and it goes as a voice note; while it records, the field steps aside for the recording strip instead of the row jumping. You can send a file to a ClickMassa conversation the same way, from the paperclip that was already there.
- **The whole message, in the card.** Settings → *Show the whole message*: a long message stops being clipped to two lines and the card grows to hold it, as far as the ChatGPT page already goes. Past that the text scrolls inside the card, with a scrollbar that appears only when there is more to read.
- **Mochi moves with it.** He used to stay at the top of a card that had grown three times his height. He now follows it half way down, so he sits with the message rather than above it — and a card that did not grow does not move him at all.
- The island keeps itself on screen and on time on both platforms, and on Windows it goes back on top instead of trusting the system to leave it there.

## 0.1.10 — October 29, 2026

Two reasons an update could look like it did nothing. Both fixed.

- **An update this copy cannot install now says so first.** The signing key was replaced on October 25, five days after the version had become 0.1.7 — so two builds call themselves 0.1.7, and the earlier one cannot verify anything signed since. It downloaded the package, failed on "the signature was created with a different key than the one provided", and offered to try again, which could never work. The check now compares the two keys before downloading, and opens the download page instead.
- **Installing no longer leaves two copies side by side.** The app was called Coucou until October 25, and a Windows installer finds a previous install by product name — so every installer since wrote a second copy and left the old one's shortcuts and start-at-login entry pointing at it. The old copy kept opening, and the new version looked like it never arrived. The installer now closes that copy, removes it and takes over its shortcuts.
- **If you are on a build that cannot update itself, this is the one you install by hand.** Close Notchy first. After this one, nothing else is manual.

## 0.1.9 — October 29, 2026

When an update check fails, it now says why.

- **The reason is on screen.** "The check did not go through." used to be the whole answer. The sentence saying *why* — the host that could not be reached, the error GitHub returned — was printed at the foot of the section, under a four-line paragraph and below the bottom edge of the window, so nobody ever read it. It sits directly under the message now.
- Settings → Updates still said **Coucou**, in English, after the rename and after everything else was translated: the version line, the window title, and every sentence the updater says while it works. All of it is Notchy now, in your language.
- Publishing a release uploads the packages before the manifest that announces them, instead of both at once. A copy that checked during those seconds got a failure that looked exactly like a broken connection.

## 0.1.8 — October 29, 2026

Notchy speaks your language.

- **Settings → General → Language**: English, Español or Português (Brasil), and "Same as system", which is what a fresh install picks — Spanish or Portuguese if Windows is set to one of them, English otherwise. It takes effect at once; nothing restarts.
- It is the whole app, not the settings window: the island, every card, the chat, the notification-area menu, the messages you get when a service will not connect, and the names of Mochi's faces.
- The line that says what Claude Code is doing was French — `Bash` read as "Exécute". It is in your language now, like everything else.
- The site and the installer speak all three too.

## 0.1.5 — October 13, 2026

Windows catches up with the Mac.

- The AI Agents dashboard: what Claude Code has been doing and what it cost — today's spend, the hourly trend, the split by model and by project, and thirteen weeks of activity. It is all read from Claude Code's own transcripts on this machine; nothing is sent anywhere.
- A globe on the island opens your site, and the chat tab can open ChatGPT instead of the built-in chat (Settings → Pages). Each opens a window of its own, and a link to anywhere else opens in your browser.
- One Notifications pill over both message services, so what is waiting is one queue instead of two places to remember.
- Seven integrations nobody was using — Resend, n8n, Vercel, GitHub, Stripe, Cal.com and Notion — are gone, along with the seven pollers that woke all day to find no key. Your stored choices are migrated; the pills that are left are seeded if every one you had was removed.
- Updating itself works from this release on. The packages before it were signed with a key that no longer exists, so this one is installed by hand once and the ones after it arrive on their own.

## 0.1.4 — October 9, 2026

- Coucou updates itself. It asks GitHub every few hours whether a newer release exists and offers it from the icon by the clock and in Settings → Updates; one click downloads, verifies and installs it. Nothing is downloaded or restarted until you click, because a restart nobody asked for would drop a Claude Code permission request that was waiting to be answered. The check carries no identifier and no usage of any kind, and can be switched off.
- Every package is signed, and one whose signature does not match is refused before it is run — so a tampered download can do nothing but fail.
- macOS (GitHub build) and the Linux AppImage update the same way. The portable Windows .zip and the .deb and .rpm packages cannot replace themselves, so they say a new version is out and point at the download page instead.

## 0.1.3 — October 3, 2026

- Answer Claude's questions from the notch: when Claude Code asks a multiple-choice question, pick an option or type your own answer right in the island, and Reply in terminal hands it back. Update your hooks in Settings to turn it on (#165) — thanks @Vega8991 for the idea (#94)
- Claude plan usage (GitHub build): turn on Settings → Agents → Plan usage to see your 5-hour and weekly limits in a small pill in the notch header, and click it for the details and reset times. Pro and Max plans; your current status line keeps working (#159)
- Chat with local models through Ollama or LM Studio, no API key needed: connect them in Settings → Chat → Local models. Answers stream in, and thinking blocks stay hidden (#156)
- Markdown in chat answers: bold, lists, headings, quotes, and code blocks with a copy button. Links open only when they are web links (#156)
- Apple Music (GitHub build): see what is playing in the notch, play, pause and skip on hover, and Mochi dances along (#144, #153)
- Settings are now organized in a sidebar (#153)
- The chat greets you by your own first name (#154)

## 0.1.2 — October 2, 2026

- Codex support (GitHub build): sessions show up live on the Codex pill, and permission requests get Allow and Deny in the notch. Install from Settings → Codex Hooks, then trust the hooks once with /hooks in Codex (#130) — thanks @lacatu5
- Cursor: Claude Code started in Cursor's terminal shows up on the Cursor pill, and you can answer its permission requests from the notch (#120).
- Pick your main coding tool in Settings → Active pills: VS Code, Cursor, Codex or Antigravity (Codex and Antigravity: GitHub build). It stays on and no longer takes one of the 4 slots (#120).
- The permission card stays in the notch until you answer it: the mouse no longer folds it, and reopening the island shows the request again (#117).
- The permission card also shows when the island is already open, and the pill you were on comes back once you answer (#120).

## 0.1.1 — October 2, 2026

- Declare the tools you use in Settings: Gemini CLI, Antigravity, Anthropic, Google AI and OpenAI pills join the existing ones (Cursor and Codex pills are coming soon), and you pick the main pill.
- Chat now supports Google AI (Gemini) and OpenAI in addition to Anthropic; switch provider and model by clicking the model name in the chat view, on macOS.
- Linux version: the Tauri app now builds for Linux too (AppImage, .deb, .rpm), with the island as a layer-shell overlay on Wayland and Claude Code hooks over a private Unix socket (#21) — thanks @Davy133
- Compact island on screens without a notch (#22) — thanks @Kamasoutra
- Only web links (http/https) open from the notch; other kinds of links from Claude or integrations are ignored (#16) — thanks @Cris1670
- Hook socket limited to your own user account, with size and time limits; logs no longer keep commands, n8n data or full URLs, and stay under 1 MB (#16) — thanks @Cris1670 and @Vignesh-Thangamariappan
- The island always reopens after folding, and Settings opens below it, resizable — thanks @rouderz
- Choose the Claude model for the chat in Settings; the list comes from your Anthropic account, and Claude Sonnet 4.6 stays the default — thanks @rouderz
- Windows build artifacts are now downloadable from a manual CI run — thanks @MysJofR
- Any agent can talk to Mochi: tag a hook payload with `coucou_agent` (e.g. `nb-hook --agent my-agent`) and it gets its own pill in the island (#7, #9) — thanks @lacatu5
- Gemini CLI and Antigravity (agy) hook support on macOS: install from Settings and their sessions show up in the island — thanks @corefusiion
