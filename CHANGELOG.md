r43:

- Add a native icon-with-duration-underbar presentation whose timer remains inside Blizzard's managed AuraButton path.
- Add a native standalone duration-bar presentation for compact aura displays without a spell icon.
- Add a scriptless native AuraSlot overlay primitive for aura-driven frame highlights without inspecting managed aura state.

r42:

- Add an opt-in native square aura border whose harmful-aura colour is selected privately by Blizzard, including the native None category for untyped effects.

r41:

- Add a scriptless native dispel-overlay AuraSlot primitive for unit-frame health-bar colouring without exposing aura data to addon Lua.

r40:

- Apply low-time duration text colours through Blizzard's native seconds or percentage duration binding, keeping opaque aura timing out of addon Lua.

r39:

- Register only the selected graphical duration carrier on each Retail 12.1 native AuraButton, preventing Blizzard's circular swipe from appearing alongside vertical and Block styles.

r38:

- Fail closed on secret unit class and phase identity before values reach Lua branching, table lookup, or colour selection.

r37:

- Allow callers to paint Block-style aura fills with an optional static RGBA colour while preserving the existing gray default.

r36:

- Abbreviate aura countdowns with native one-letter seconds, minutes, hours, and days while keeping opaque duration values inside Blizzard's duration binding.

r35:

- Restore vertical and block-vertical aura timing with native duration bars, without adding a second countdown provider.
- Add a narrow pre-12.1 filter-complement descriptor for the legacy aura-list compatibility path.

r34:

- Add cumulative native AuraContainer construction diagnostics and initializer-time slot anchoring.

r33:

- Add the Retail 12.1 native AuraContainer adapter for secret-safe aura presentation.

r32:

- Fail closed legacy Retail aura widgets on 12.1 and newer so restricted aura APIs are never used as a native-container fallback.

r31:

- Validate saved mover positions before replacing existing anchors.
- Make mover editing fail closed when frame geometry is unavailable or secret.
- Close active mover editing safely when combat begins.

r30:

- Add AF.AttachTransientScrollBar (template-free fade-in/out scroll bar with inactivity fade and drag hold)
- Add AF.CreateTreeList (scrollable tree list: pooled rows, accent highlight, chevron toggles, animated expand/collapse, compact mode with 44px icon-only rows and fixed icon-adjacent title tooltips, icons rendered full-color on lightweight square plates (`iconPlateColors` border/fill, no tint/desaturate option) with the standard icon crop applied to texture shapes only, defaulting to 20px icons in 28px rows and 22px headings; expansion state is shared between compact and expanded presentations with a single scroll offset)
- Add AF.CreateSidebarRail (sidebar rail wrapping a tree list: manual SetCollapsed/GetCollapsed/ToggleCollapsed/SetOnCollapsedChanged collapse API, presentation-width publication, content inset helpers)
- Add Bag_All/Bag_Empty/Bag_IndividualBags/Bag_Misc plus Bag_ProfessionTool adaptive icons for bag sidebar fallback and category states (the rest of the original Bag_* set was pruned after BFInfinite's Bags sidebar v2 moved consumable-subclass and equipment-slot icons to native client art)

[View Full Changelog](https://github.com/enderneko/AbstractWidgets/compare/r19...83bd2eb1a4ea2be3776b3f9366990a6836de39eb)

- Remove TooltipDataHandlerMixin and ClearHandlerInfo call
