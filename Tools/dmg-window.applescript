-- Lays out the installer window inside a mounted, still-writable Awake.dmg.
--
-- Finder is the only thing that can write a window's appearance, so the disk
-- image is built read-write, opened here, and only then compressed. The numbers
-- match Tools/MakeDiskImageBackground, which draws the arrow between the two
-- icon positions set below.
--
-- Two things here are load-bearing and both were found by testing the resulting
-- image rather than by reading the dictionary:
--
--   * Every icon view property is set through the full reference chain. Setting
--     them through a saved `icon view options` variable reports success and is
--     then silently dropped: 48pt icons, arranged by name, no background.
--
--   * The window is left open. Closing it makes Finder rewrite .DS_Store
--     without the background alias, so the backdrop survives being mounted and
--     then vanishes from the compressed image. The volume is unmounted from
--     under the open window instead, which Finder handles.
--
-- Usage: osascript dmg-window.applescript <volume name>

on run argv
	set volumeName to item 1 of argv

	tell application "Finder"
		tell disk volumeName
			open
			delay 1

			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false

			-- 600x400 of content, plus room for the title bar, which the
			-- bounds include but the background picture does not fill.
			set the bounds of container window to {200, 120, 800, 548}

			-- Before the positions below: while the window is arranged by
			-- name, Finder snaps icons back to its own grid.
			set arrangement of the icon view options of container window to not arranged
			set icon size of the icon view options of container window to 128
			set text size of the icon view options of container window to 12
			set background picture of the icon view options of container window ¬
				to file ".background:background.tiff"

			set position of item "Awake.app" of container window to {160, 170}
			set position of item "Applications" of container window to {440, 170}

			update without registering applications

			-- Finder writes .DS_Store lazily and the caller unmounts as soon as
			-- this returns; leaving early loses the layout.
			delay 3
		end tell
	end tell

	delay 2
end run
