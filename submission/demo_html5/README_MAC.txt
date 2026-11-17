Mac running notes
=================

Do not double-click Disc_Golf.html directly. This Godot HTML5 export loads
Disc_Golf.wasm and Disc_Golf.pck with browser fetch(), and macOS browsers often
block those requests from file:// pages. The symptom is usually "Failed to
fetch".

Recommended way:

1. Keep all files in this folder together.
2. Double-click RUN_ON_MAC.command.
3. A Terminal window will start a local server and open:
   http://127.0.0.1:8060/Disc_Golf.html
4. Keep the Terminal window open while playing.
5. Press Control-C in Terminal to stop the server.

If macOS says the command file cannot be opened, run this once in Terminal from
this folder:

chmod +x RUN_ON_MAC.command

If Python 3 is not installed on the Mac, either install Python 3 or upload the
entire folder to a web host such as itch.io, GitHub Pages, Netlify, or a school
web server, then open Disc_Golf.html from the hosted URL.
