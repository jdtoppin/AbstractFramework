r31:

- Make mover editing fail closed when frame geometry is unavailable or secret.
- Close active mover editing safely when combat begins.

r30:

- Add AF.AttachTransientScrollBar (template-free fade-in/out scroll bar with inactivity fade and drag hold)
- Add AF.CreateTreeList (scrollable tree list: pooled rows, accent highlight, chevron toggles, animated expand/collapse, compact mode with 44px icon-only rows and fixed icon-adjacent title tooltips, icons rendered full-color on lightweight square plates (`iconPlateColors` border/fill, no tint/desaturate option) with the standard icon crop applied to texture shapes only, defaulting to 20px icons in 28px rows and 22px headings; expansion state is shared between compact and expanded presentations with a single scroll offset)
- Add AF.CreateSidebarRail (sidebar rail wrapping a tree list: manual SetCollapsed/GetCollapsed/ToggleCollapsed/SetOnCollapsedChanged collapse API, presentation-width publication, content inset helpers)
- Add Bag_All/Bag_Empty/Bag_IndividualBags/Bag_Misc plus Bag_ProfessionTool adaptive icons for bag sidebar fallback and category states (the rest of the original Bag_* set was pruned after BFInfinite's Bags sidebar v2 moved consumable-subclass and equipment-slot icons to native client art)

[View Full Changelog](https://github.com/enderneko/AbstractWidgets/compare/r19...83bd2eb1a4ea2be3776b3f9366990a6836de39eb)

- Remove TooltipDataHandlerMixin and ClearHandlerInfo call
