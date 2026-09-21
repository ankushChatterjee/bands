# Keyboard overhaul tasks

- [x] Navigation implementation: deterministic band/thought movement, bounded edges, empty bands, editor isolation, visible selection scrolling.
- [x] Commands implementation: a shared shortcut registry and availability, selected-band creation, top-band global capture, predictable cancellation and removal recovery.
- [x] Theme implementation: neutral graphite/light-gray focus rings, pointer suppression, native editor feedback, truthful shortcut help.
- [x] Automated verification: 37 passing tests, successful packaged build, replacement and relaunch; installed executable hash matches the build.
- [ ] Interactive acceptance: keyboard smoke test, light/dark visual review, Full Keyboard Access and VoiceOver. The UI inspection tool times out connecting to the menu-bar app; these are not verified by unit tests.

## Interaction contract

In the board, Up/Down change bands without wrapping. Band headers form the first column; Right enters the first thought, Left from that thought returns to its band header. The add (+) control is the final content target and is selected when entering an empty band from a thought. Left from + returns through the band’s thoughts, or directly to its band name when empty. Other Left/Right presses move one target and stop at the edges. Moving vertically from a thought preserves its ordinal position where possible. With no selection any arrow selects the first band.

Return edits a thought or renames a band. Command-N opens the selected band's inline composer; Option-L starts in the top band. Empty stores enter band creation. Saving selects the created item; cancelling returns to its band or original thought. Completion/release selects the next item, then the previous, then its band. No persistent capture bar.

A normal panel open never restores an abandoned new-thought composer. Return on a keyboard-selected + opens that band’s composer. A band name is selected by pressing Left from its first thought (or from + when the band is empty); Return renames it, Command-Delete requests deletion, and Command-Option-[ / ] reorders it.

Text editors own cursor movement, selection, copy/paste and undo. Board actions cannot mutate a stale selection while editing or while a sheet is open. Escape cancels the editor, then closes the panel on a subsequent press. Tab does not navigate the board; native controls in Settings and dialogs keep their standard traversal.

Focus rings use graphite in light mode and soft gray in dark mode. They appear only on the keyboard-focused item, never merely on a remembered selection or pointer click. Semantic thought-age colors are preserved.

## Architecture

`BoardNavigation` is a pure, tested navigation policy over ordered band/thought IDs. The panel routes unmodified arrows through one event path instead of competing SwiftUI movement handlers. Native text responders and sheets own their input. Selection, keyboard/pointer modality, and editor focus remain separate concerns.

`PanelCommand` defines the shortcut map for menus and event matching; Settings renders the same command reference. Command availability excludes editing/modal states, missing targets, and impossible reorder directions. Destructive actions retain confirmation. Hover completion uses the shared dispatcher and recovery logic.

These choices follow Apple's guidance on [keyboard interaction](https://developer.apple.com/design/human-interface-guidelines/keyboards) and [focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/), while retaining the requested arrow-only board navigation rather than Tab-based band switching.

## Remaining acceptance checklist

1. From another app, press Option-L: top-band inline composer receives focus, with no separate capture bar. Type a draft, move its caret with arrows, then Escape; no thought is created.
2. Select a lower band using Down. Command-N opens that band's composer; Return creates and selects the new thought. Return again edits it; Escape preserves its saved text.
3. Exercise all four arrows with zero, one, and many thoughts, and empty bands. Edges stop rather than wrap; selection stays visible when scrolling.
4. Complete, move, reorder, and cancel release/delete confirmations. Focus returns to the expected item. Verify both native menu actions and shortcuts, including disabled boundary actions.
5. In light and dark themes, only the keyboard-focused item receives the neutral outline. Clicking clears it. Age colors remain visible and Reduce Motion suppresses optional transitions.
6. Settings and Move dialogs retain native Tab, Return, Escape, and VoiceOver behavior. Check long text and invalid Settings values.

## Deployment record

On September 16, 2026, both running copies (installed app and old worktree build) were stopped. The rebuilt app replaced `/Users/ankush/Applications/bands.app`; only that installed executable was confirmed running afterward. The previous installed bundle was preserved at `/tmp/bands-before-keyboard.5gykar/bands.app`. User bands and thoughts were not removed.
